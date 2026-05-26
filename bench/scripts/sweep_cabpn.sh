#!/usr/bin/env bash
set -euo pipefail

# State-size sweep (fixed alpha): compare CA-BPN-selected k against the
# same k as a fixed-k policy across a list of state_bytes values, using
# hyperfine for wall-clock means. Saves per-state hyperfine JSON and a
# combined summary TSV.

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/bench/rust_harness/target/release/rust_harness"

if [[ ! -x "$BIN" ]]; then
  echo "error: binary not found: $BIN"
  echo "build it first:"
  echo "  cd $ROOT/bench/rust_harness && cargo build --release"
  exit 1
fi

STAMP="$(date +"%Y%m%d_%H%M%S")"
OUT_DIR="$ROOT/bench/out/sweep_${STAMP}"
mkdir -p "$OUT_DIR"

# Defaults (override via env vars)
N="${N:-4096}"
ITERS="${ITERS:-100}"
L1_BYTES="${L1_BYTES:-65536}"
ALPHA_MILLI="${ALPHA_MILLI:-500}" # 500 => 0.5
WARMUP="${WARMUP:-3}"
MIN_RUNS="${MIN_RUNS:-15}"

# State sizes to sweep (bytes)
STATE_BYTES_LIST=(${STATE_BYTES_LIST:-256 512 1024 1536 2048 3072 4096})

ENV_FILE="$OUT_DIR/env.txt"
bash "$ROOT/bench/scripts/collect_env.sh" > "$ENV_FILE"

SUMMARY_TSV="$OUT_DIR/summary.tsv"
printf "state_bytes\tk_selected\tmean_ms_cabpn\tmean_ms_fixedk\n" > "$SUMMARY_TSV"

echo "out_dir=$OUT_DIR"
echo "env=$ENV_FILE"
echo "n=$N iters=$ITERS l1_bytes=$L1_BYTES alpha_milli=$ALPHA_MILLI"
echo

for STATE_BYTES in "${STATE_BYTES_LIST[@]}"; do
  echo "== state_bytes=$STATE_BYTES =="

  ONE_RUN_OUT="$OUT_DIR/one_run_state_${STATE_BYTES}.txt"
  "$BIN" --mode chain_cabpn --n "$N" --iters 1 \
    --l1-bytes "$L1_BYTES" --state-bytes "$STATE_BYTES" --alpha-milli "$ALPHA_MILLI" \
    > "$ONE_RUN_OUT"

  K_SELECTED="$(
    python3 - "$ONE_RUN_OUT" <<'PY'
import sys
path = sys.argv[1]
k = None
with open(path, "r", encoding="utf-8") as f:
    for line in f:
        if line.startswith("k_selected="):
            k = int(line.strip().split("=", 1)[1])
            break
if k is None:
    raise SystemExit("k_selected not found")
print(k)
PY
  )"

  HF_JSON="$OUT_DIR/hyperfine_state_${STATE_BYTES}.json"
  hyperfine --warmup "$WARMUP" --min-runs "$MIN_RUNS" --export-json "$HF_JSON" \
    "$BIN --mode chain_cabpn --n $N --iters $ITERS --l1-bytes $L1_BYTES --state-bytes $STATE_BYTES --alpha-milli $ALPHA_MILLI" \
    "$BIN --mode chain_fixedk --k $K_SELECTED --n $N --iters $ITERS"

  python3 - "$HF_JSON" "$STATE_BYTES" "$K_SELECTED" >> "$SUMMARY_TSV" <<'PY'
import json, sys
path, state_bytes, k_sel = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
r = data["results"]
def mean_ms(i: int) -> float:
    # hyperfine stores seconds
    return r[i]["mean"] * 1000.0
cabpn = mean_ms(0)
fixedk = mean_ms(1)
print(f"{state_bytes}\t{k_sel}\t{cabpn:.4f}\t{fixedk:.4f}")
PY

  echo
done

echo "DONE"
echo "summary: $SUMMARY_TSV"
