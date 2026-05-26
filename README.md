# CA-BPN: A Cache-Aware Batch-Size Policy for Constant-Time Normalization in Isogeny Pipelines

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Paper](https://img.shields.io/badge/paper-ePrint%202026%2FXXXX-lightgrey.svg)](https://eprint.iacr.org/2026/XXXX)
[![Rust](https://img.shields.io/badge/rust-edition%202024-orange.svg)](bench/rust_harness/Cargo.toml)

> Companion artifact to the ePrint preprint
> **"Formal Guarantees and Microarchitectural Scheduling for Constant-Time
> Normalization in Theta-Coordinate Isogeny Pipelines"** — Moe Tabei, 2026.
> [`docs/paper.pdf`](docs/paper.pdf).

**CA-BPN** (Cache-Aware Batch-size Policy for Normalization) is a deterministic,
cache-budgeted heuristic for choosing the batch size of inverse-recovery
operations inside translation pipelines for theta-coordinate isogeny
computations (SQIsign, SQIsign2D-West, SQIsign2DPush, Qlapoti-based
IdealToIsogeny). It treats the batch size `k` as a microarchitectural
engineering parameter — selected from an explicit L1 budget — rather than a
purely algebraic optimum.

This repository is the reference harness, the sweep drivers, and a sample of
measurements. It is **not** an SQIsign implementation. The scope and
limitations section below is the most important part of this README; please
read it before drawing platform-level conclusions from the numbers here.

## What's in this repository

| Path | What it is | What it isn't |
|---|---|---|
| [`bench/rust_harness/`](bench/rust_harness) | Reference implementation of **Algorithm 1** (CA-BPN k-selection) and **Algorithm 3** (constant-time batched-inversion template), over a toy 64-bit prime field. Five modes: `inv_sequential`, `inv_batched`, `chain_fixedk`, `chain_cabpn`, `chain_sequential`. | An SQIsign field implementation. The 64-bit prime is a stand-in to keep the scheduling-policy shape reproducible on a laptop in seconds. |
| [`bench/scripts/`](bench/scripts) | Mac-friendly sweep drivers (`hyperfine`, `bash`, `python3`), plus TSV → LaTeX converters. | Auto-tuning. The sweeps emit raw TSVs; interpretation is yours. |
| [`bench/linux/`](bench/linux) | x86_64 Linux `perf stat` driver for hardware-counter measurements (cycles, instructions, L1D / LLC references and misses). | Available on every cloud guest — many do not expose perf counters. See [`bench/linux/README.md`](bench/linux/README.md). |
| [`bench/aws/`](bench/aws) | One-click EC2 / EC2-`*.metal` scripts that provision an instance, run the sweep, copy results back, and terminate. With explicit cost limiters. | Free. The scripts launch real EC2 instances — review them before use. |
| [`bench/results/`](bench/results) | Sample sweep outputs from Apple M2 (Feb 2026 measurements) for reference. | Production benchmarks. They demonstrate the policy shape on one platform. |
| [`docs/paper.pdf`](docs/paper.pdf) | The companion preprint (March 2026 revision). | The single source of truth — once an ePrint ID is assigned, the canonical link will be in [`CITATION.cff`](CITATION.cff). |
| [`docs/algorithms.md`](docs/algorithms.md) | Markdown extract of Algorithm 1 and Proposition 1. | The full paper. See [`docs/paper.pdf`](docs/paper.pdf). |

## The CA-BPN policy in one screen

Given an L1 data cache size `C_L1`, an estimated live-state size `B_state`
(bytes per projective state including inverse-recovery scratch), and a safety
factor `α ∈ (0, 1)`:

```
k_max = ⌊ α · C_L1 / B_state ⌋
k     = largest power-of-two ≤ k_max
        (optionally rounded to a divisor of the chain length n)
```

**Working-set bound (Proposition 1 of the paper).** If the implementation
keeps at most `k` projective states live at a time, each with footprint at
most `B_state` bytes, then `k · B_state ≤ α · C_L1`.

This is a *budget* guarantee, not a miss-rate guarantee — how close the
actual L1 occupancy tracks the estimate depends on `B_state`'s fidelity, on
the layout of auxiliary scratch, and on contention with the rest of the
pipeline. See [`docs/algorithms.md`](docs/algorithms.md) for the pseudocode
and proof, and the paper for the cost-model derivation.

## Reproducing the measurements

### macOS — wall-clock means (hyperfine)

```bash
brew install hyperfine
make build
make sweep         # state-size sweep at α = 0.5, L1D = 64 KB
make sweep-alpha   # joint (α, state_bytes) sweep
```

Outputs land in `bench/out/sweep_<timestamp>/summary.tsv`.

### Linux x86_64 — hardware counters (perf stat)

```bash
bash bench/linux/setup_ubuntu.sh
make bench-linux
```

Requires `perf_event_paranoid` permissive enough to expose hardware events.
See [`bench/linux/README.md`](bench/linux/README.md).

### AWS — one-click bare-metal

```bash
cd bench/aws
AWS_RUNTIME_MINUTES=10 bash one_click_perf_ec2_metal.sh
```

`*.metal` instance classes expose hardware performance counters that ordinary
EC2 guests do not. Three independent cost limiters are in place; see
[`bench/aws/README.md`](bench/aws/README.md) before running.

### Show all targets

```bash
make help
```

## Sample results

All numbers below were collected on a single Apple M2 (16 GB RAM, L1D = 64 KB)
with `n = 4096`, `iters = 200`, batched-inversion harness in release mode.
Raw data lives in [`bench/results/`](bench/results).

### State-size sweep at α = 0.5

| `state_bytes` | `k_selected` (CA-BPN) | `mean_ms` (CA-BPN) | `mean_ms` (fixed-k baseline) |
|---:|---:|---:|---:|
| 256  | 128 | 21.11 | 21.13 |
| 512  |  64 | 22.83 | 23.47 |
| 1024 |  32 | 24.76 | 24.92 |
| 2048 |  16 | 30.01 | 29.98 |

Source: [`bench/results/sweep_state_20260219/summary.tsv`](bench/results/sweep_state_20260219/summary.tsv).

CA-BPN consistently tracks the fixed-k baseline at the same selected `k`,
with no manual tuning. The differences are within `hyperfine` measurement
noise on a single platform. The value of CA-BPN on this data is **the policy
interface itself** — a deterministic rule that selects `k` from a stated cache
budget — not a raw speedup on one machine.

### Joint (α, state_bytes) sweep

| `α` | `state_bytes` | `k_selected` | `mean_ms` (CA-BPN) | `mean_ms` (fixed-k) |
|---:|---:|---:|---:|---:|
| 0.3 |  512 | 32 | 25.02 | 24.74 |
| 0.3 | 2048 |  8 | 42.19 | 40.06 |
| 0.7 |  512 | 64 | 22.26 | 22.27 |
| 0.7 | 2048 | 16 | 29.92 | 31.86 |

Source: [`bench/results/sweep_alpha_20260219/summary.tsv`](bench/results/sweep_alpha_20260219/summary.tsv).

The α-sweep is mostly a sanity check that the policy responds monotonically
to the safety factor: tightening α from 0.7 to 0.3 halves `k` at fixed
`state_bytes`, and runtime degrades accordingly when the resulting batches
become too short to amortise the per-batch inversion cost. Cross-platform
replication of this shape is one of the cleaner follow-ups; see the **Open
questions** section of [`ARTICLE.md`](ARTICLE.md).

## Scope and limitations

This is a research artifact. Please weight the following caveats as heavily
as the headline numbers:

- **Toy field.** The Rust harness uses a 64-bit prime field (`2⁶⁴ − 59`).
  This keeps the harness fast and dependency-free, but is **not** an SQIsign
  field. Translating to real SQIsign field arithmetic (e.g. a constant-time
  Bernstein-Yang inversion over a 254/256-bit prime) will change the
  inversion-to-multiplication ratio `I/M` and may change which batch sizes
  are optimal. The harness exists to exercise the *scheduling-policy
  interface*, not to claim end-to-end speedups for a real signature scheme.

- **Algorithmic CT, not bit-level CT.** "Constant-time" in the paper refers
  to the *algorithmic template* (Algorithm 3): fixed loop bounds, fixed
  memory access pattern, no secret-dependent control flow. This artifact
  implements that template shape. It does **not** include `dudect`-style
  bit-level CT verification, formal CT proofs, or compiled-output audits.
  The harness's egcd-based inversion in particular is *not* a constant-time
  routine; the paper's Proposition 2 assumes a constant-time `inv` primitive
  is available on the target platform.

- **Single-platform measurements.** The sample results were collected on one
  Apple M2 and a small set of Linux / AWS perf runs. Cross-platform
  replication is welcome — that is the entire point of publishing the harness
  rather than only the paper.

- **CA-BPN is a policy, not an oracle.** It selects `k` from an explicit
  cache budget; it does not search the (cycles, L1 misses, LLC misses)
  Pareto frontier. It will under-select on platforms where the algebraic
  term dominates and over-select on platforms with very large L1D where the
  batched-inversion bookkeeping itself becomes the bottleneck.

If any of these caveats is decisive for your evaluation, the right next step
is to swap in your target's real field arithmetic and re-run the sweeps.
[Issues and PRs welcome.](#contact)

## Companion paper

```
Moe Tabei. "Formal Guarantees and Microarchitectural Scheduling for
Constant-Time Normalization in Theta-Coordinate Isogeny Pipelines."
Cryptology ePrint Archive, Paper 2026/XXXX, March 2026.
https://eprint.iacr.org/2026/XXXX     [placeholder — to be updated on assignment]
```

The paper:

- Formalises the correctness conditions for delaying affine normalization in
  homogeneous theta-coordinate updates (**Theorem 1**).
- Proves the working-set bound for CA-BPN (**Proposition 1**).
- Scopes the assumptions under which the constant-time template can be
  realised without secret-dependent control flow or memory access
  (**Proposition 2**).
- Provides the reproducibility protocol (this repository).

A [BibTeX entry](CITATION.cff) is provided. Once an ePrint ID is assigned,
the canonical link will be propagated through that file.

## About the author

**Moe Tabei** is an independent researcher working at the boundary of
post-quantum cryptography and microarchitectural engineering. Secondary
focus on Solidity / EVM smart-contract security review, with public
engagements on Cantina.

The independent-researcher status is a feature, not a bug, of how this
artifact is published: the implementation, the sweep harness, the
measurements, and the paper were produced as a single coherent unit, with
no separation between the formal treatment and the engineering. The repository
is the primary deliverable; the paper is its formal companion.

## Contact

Open to remote cryptography research and smart-contract security roles
globally.

📬 **tabei@ryun.jp** &nbsp;·&nbsp; ePrint preprint:
[`docs/paper.pdf`](docs/paper.pdf) &nbsp;·&nbsp;
GitHub Issues for technical questions on the harness.
