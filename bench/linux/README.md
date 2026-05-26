# Linux `perf` counters (cloud or bare-metal)

The Mac sweeps (`make sweep`, `make sweep-alpha`) give you wall-clock means via
`hyperfine`. To support the cache-pressure claim with **hardware performance
counters** — cycles, instructions, branch misses, L1D / LLC references and
misses — repeat the sweep on an x86_64 Linux machine using `perf stat`.

## Recommended environment

- Ubuntu 24.04 LTS (x86_64)
- `perf stat` available (kernel and `perf_event_paranoid` permitting)

## 1. Setup

From the repository root, on the target Linux machine:

```bash
bash bench/linux/setup_ubuntu.sh
```

This installs `build-essential`, `python3`, the matching `linux-tools-$(uname -r)`,
a Rust toolchain (if absent), and builds the harness in release mode.

## 2. Perf sweep

```bash
N=4096 ITERS=200 REPEATS=20 \
ALPHA_LIST='300 500 700' \
STATE_BYTES_LIST='256 512 1024 1536 2048 3072 4096' \
FIXED_K_LIST='8 16 32 64' \
bash bench/linux/run_perf_sweep.sh
```

Results land in `bench/out/perf_sweep_<timestamp>/`:

- `summary_perf.tsv` — one row per (alpha, state_bytes, mode) configuration
- `raw/` — per-run `perf stat` stderr and stdout for auditing

## 3. Convert to LaTeX (optional)

```bash
TSV="bench/out/perf_sweep_<timestamp>/summary_perf.tsv"
python3 bench/scripts/perf_summary_to_latex.py "$TSV" \
  --out results_perf_sweep.tex \
  --caption "Linux perf sweep summary (CA-BPN vs baselines)." \
  --label "tab:perf_sweep"
```

## When `perf` is not available

Many cloud VM classes do not expose hardware performance counters to guests; in
that case `perf stat` will report most events as `<not supported>` and only
wall-clock timing remains. Two ways forward:

- Check `sysctl kernel.perf_event_paranoid` on Ubuntu and lower it if your
  policy allows it.
- Use a bare-metal cloud instance (e.g. AWS `*.metal`). The scripts under
  `bench/aws/` automate this with explicit cost limiters.

Wall-clock-only data still demonstrates the scheduling shape, but cannot
attribute speedups to cache behaviour by itself.
