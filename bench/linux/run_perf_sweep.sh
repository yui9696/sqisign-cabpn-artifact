#!/usr/bin/env bash
set -euo pipefail

# Perf-based sweep runner for the CA-BPN harness on Linux.
#
# Outputs:
#   bench/out/perf_sweep_<timestamp>/summary_perf.tsv
#   bench/out/perf_sweep_<timestamp>/raw/*.txt
#
# Environment variables (with defaults):
#   N=4096
#   ITERS=200
#   REPEATS=15
#   L1_BYTES=32768
#   SEED=1
#   ALPHA_LIST="300 500 700"
#   STATE_BYTES_LIST="256 512 1024 2048 4096"
#   FIXED_K_LIST="8 16 32 64"
#   PERF_EVENTS="cycles,instructions,branches,branch-misses,cache-references,cache-misses"
#
# Notes:
# - Some systems expose L1/LLC events with different names; override PERF_EVENTS if needed.
# - If perf requires sudo, run this script with sudo (it preserves env by default on
#   some distros; otherwise use sudo -E).

N="${N:-4096}"
ITERS="${ITERS:-200}"
REPEATS="${REPEATS:-15}"
L1_BYTES="${L1_BYTES:-32768}"
SEED="${SEED:-1}"
ALPHA_LIST="${ALPHA_LIST:-300 500 700}"
STATE_BYTES_LIST="${STATE_BYTES_LIST:-256 512 1024 2048 4096}"
FIXED_K_LIST="${FIXED_K_LIST:-8 16 32 64}"
PERF_EVENTS="${PERF_EVENTS:-cycles,instructions,branches,branch-misses,cache-references,cache-misses}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HARNESS="$ROOT_DIR/bench/rust_harness/target/release/rust_harness"

if [[ ! -x "$HARNESS" ]]; then
  echo "ERROR: harness not built at $HARNESS"
  echo "Run: bash bench/linux/setup_ubuntu.sh"
  exit 1
fi

PERF_CMD=(perf)
if ! perf stat -e cycles -- true >/dev/null 2>&1; then
  if sudo -n true >/dev/null 2>&1; then
    PERF_CMD=(sudo -n perf)
    echo "## perf requires sudo; using: sudo -n perf"
  else
    echo "ERROR: perf is not permitted for this user, and sudo requires a password."
    echo "Fix: run this script with sudo, or enable passwordless sudo for perf."
    exit 1
  fi
fi

TS="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="$ROOT_DIR/bench/out/perf_sweep_$TS"
RAW_DIR="$OUT_DIR/raw"
mkdir -p "$RAW_DIR"

SUMMARY="$OUT_DIR/summary_perf.tsv"
echo -e "alpha_milli\tstate_bytes\tk_selected\tmode\twall_ms_mean\twall_ms_std\tcycles\tinstructions\tbranches\tbranch_misses\tcache_references\tcache_misses" > "$SUMMARY"

run_one() {
  local alpha_milli="$1"
  local state_bytes="$2"
  local mode="$3"   # cabpn|fixed|sequential
  local k="$4"      # only for fixed mode
  local tag="$5"

  local args=( "--n" "$N" "--iters" "$ITERS" "--seed" "$SEED" "--l1-bytes" "$L1_BYTES" "--state-bytes" "$state_bytes" "--alpha-milli" "$alpha_milli" )
  if [[ "$mode" == "cabpn" ]]; then
    args+=( "--mode" "chain_cabpn" )
  elif [[ "$mode" == "fixed" ]]; then
    args+=( "--mode" "chain_fixedk" "--k" "$k" )
  else
    args+=( "--mode" "chain_sequential" )
  fi

  local perf_out="$RAW_DIR/perf_${tag}.tsv"
  local log_out="$RAW_DIR/log_${tag}.txt"
  local stdout_out="$RAW_DIR/stdout_${tag}.txt"

  local cmd=( "$HARNESS" "${args[@]}" )

  local k_selected="$k"
  if [[ "$mode" == "cabpn" ]]; then
    local probe_out
    probe_out="$("$HARNESS" --mode chain_cabpn --n "$N" --iters 1 --seed "$SEED" --l1-bytes "$L1_BYTES" --state-bytes "$state_bytes" --alpha-milli "$alpha_milli" | tr -d '\r')"
    k_selected="$(printf "%s\n" "$probe_out" | awk -F'=' '/^k_selected=/{print $2; exit}')"
    if [[ -z "${k_selected:-}" ]]; then
      k_selected="0"
    fi
  fi

  : > "$perf_out"
  : > "$log_out"
  : > "$stdout_out"

  for ((r=1; r<=REPEATS; r++)); do
    echo "## run $r/$REPEATS : $tag" | tee -a "$log_out" >/dev/null
    # shellcheck disable=SC2086
    /usr/bin/time -f "WALL_MS\t%e" \
      "${PERF_CMD[@]}" stat -x $'\t' -e "$PERF_EVENTS" -- \
      "${cmd[@]}" \
      2> "$RAW_DIR/stderr_${tag}_r${r}.txt" \
      1>> "$stdout_out"

    awk -F'\t' '
      BEGIN { }
      {
        v=$1;
        gsub(/^[ \t]+/, "", v);
        gsub(/[ \t]+$/, "", v);
      }
      v ~ /^[0-9,]+(\.[0-9]+)?$/ {
        gsub(/,/, "", v);
        ev="";
        if (NF >= 3 && $3 != "" && $3 !~ /^#/) { ev=$3; }
        else if (NF >= 2 && $2 != "" && $2 !~ /^#/) { ev=$2; }
        if (ev != "") {
          gsub(/^[ \t]+/, "", ev);
          gsub(/[ \t]+$/, "", ev);
          sub(/:.*/, "", ev);
          print ev "\t" v;
        }
      }
      $1 ~ /^WALL_MS/ {
        print "wall_seconds\t" $2;
      }
    ' "$RAW_DIR/stderr_${tag}_r${r}.txt" >> "$perf_out"
  done

  python3 "$ROOT_DIR/bench/linux/summarize_perf_tsv.py" \
    --alpha-milli "$alpha_milli" \
    --state-bytes "$state_bytes" \
    --mode "$mode" \
    --k-selected "$k_selected" \
    --input "$perf_out" \
    --output "$SUMMARY"
}

for alpha_milli in $ALPHA_LIST; do
  for state_bytes in $STATE_BYTES_LIST; do
    tag="cabpn_a${alpha_milli}_s${state_bytes}"
    run_one "$alpha_milli" "$state_bytes" "cabpn" "0" "$tag"

    tag="seq_a${alpha_milli}_s${state_bytes}"
    run_one "$alpha_milli" "$state_bytes" "sequential" "0" "$tag"

    for k in $FIXED_K_LIST; do
      tag="fixedk${k}_a${alpha_milli}_s${state_bytes}"
      run_one "$alpha_milli" "$state_bytes" "fixed" "$k" "$tag"
    done
  done
done

echo
echo "WROTE: $SUMMARY"
echo "RAW:   $RAW_DIR/"
