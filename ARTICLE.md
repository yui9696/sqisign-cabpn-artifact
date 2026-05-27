# Optimizing Isogeny-Based Signatures: A Cache-Aware Batch Scheduling Approach

> *Companion writeup to* **"Formal Guarantees and Microarchitectural Scheduling
> for Constant-Time Normalization in Theta-Coordinate Isogeny Pipelines"**
> *(ePrint preprint, March 2026) and the open-source artifact at*
> [github.com/yui9696/sqisign-cabpn-artifact][repo].

[repo]: https://github.com/yui9696/sqisign-cabpn-artifact

---

Post-quantum signature schemes built on isogenies between elliptic curves —
SQIsign and its 2D variants (SQIsign2D-West, SQIsign2DPush) — have spent the
last few rounds of NIST and IACR papers getting *faster*. Most of that
acceleration came from algebraic restructuring: better isogeny representations,
fewer inversions, lazier normalisation. The most recent step, by way of
Qlapoti, was to attack the surrounding norm-equation problem directly,
shrinking the cost of the `IdealToIsogeny` translation layer that sits between
the abstract algebra and the on-curve arithmetic.

This post is about the *next* engineering question, the one that gets less
attention because it doesn't yield a cleaner theorem: **once you know you have
to batch your inversions, what batch size do you pick — and how do you defend
that choice in front of an auditor?**

The companion paper proposes a small, deterministic, cache-budgeted policy
called **CA-BPN** (Cache-Aware Batch-size policy for Normalization), formalises
the conditions under which it preserves correctness inside delayed-affine
normalisation, and ships a reproducible harness with sample measurements. This
post explains the *why* in plain language. If you only want the
copy-pasteable, run-it-yourself version, skip straight to the
[reproducibility section](#reproducing-the-measurements) and the [GitHub
repository][repo].

## The problem: when should you normalise inside a translation pipeline?

In theta-coordinate implementations of `(2,2)`-isogeny chains, affine
normalisation — really just field inversion — is the single dominant cost
driver. The standard countermeasure is **batched inversion** in the
Montgomery style: invert `k` elements with one shared inversion and roughly
`3(k − 1)` extra multiplications, by accumulating a prefix product, inverting
that, and folding the inverse back through the list.

The algebraic question — *how many multiplications does that cost?* — has a
clean answer. The pipeline question — *where along a chain of length `n`
should you place the normalisation boundaries, and how big should each batch
be?* — does not. It depends on:

1. **The ratio `I/M`** between the cost of an inversion and the cost of a
   multiplication, which varies wildly across platforms and field sizes.
2. **The live working-set footprint** of the `k` projective states held while
   the batched inversion is in flight. Large batches make the algebraic cost
   per element approach zero but blow out of L1.
3. **Constant-time constraints**: secret-dependent control flow and
   secret-dependent memory access patterns are unacceptable for a signature
   scheme, so whatever batching shape you pick has to be defensible under
   that lens too.

Existing work — Dartois–Maino–Pope–Robert give modular descriptions and
operation counts; Lin–Wang–Zhao develop inversion-free blocks and mixed
chain strategies — handles the algebraic side carefully. The integration
question is usually left to "engineering judgement" inside an implementation.

CA-BPN is an attempt to push that judgement one level further: into a small
deterministic policy that consumes platform inputs and emits a batch size,
with a provable working-set bound.

## The CA-BPN policy

Take three inputs:

- `C_L1` — the L1 data cache size on the target platform, in bytes;
- `B_state` — an estimate of the bytes occupied by one live projective state,
  including the auxiliary scratch (prefix products, fold-back accumulators)
  needed for inverse recovery;
- `α ∈ (0, 1)` — a safety factor saying "I'm willing to spend at most this
  fraction of L1 on the live working set".

Compute:

    k_max = ⌊ α · C_L1 / B_state ⌋
    k     = largest power-of-two ≤ k_max

That's it. The policy returns `k` (clamped to ≥ 1, optionally rounded to a
divisor of the chain length `n`). Power-of-two rounding is for determinism
and bookkeeping ergonomics, not deep mathematical reasons.

The working-set bound (**Proposition 1** in the paper) is a one-line proof:
since `k ≤ k_max = ⌊α · C_L1 / B_state⌋`, multiplying by `B_state` gives
`k · B_state ≤ α · C_L1`. That's the cache-pressure guarantee the policy is
named for.

It's worth being precise about what that bound *isn't*. It's a budget
guarantee, not a miss-rate guarantee. How tightly the actual L1 occupancy
tracks the estimate depends on `B_state`'s fidelity (you have to calibrate it
per platform), on the auxiliary scratch layout, and on contention with the
rest of the surrounding pipeline. CA-BPN gives you a single defensible
number; it does not absolve you from re-measuring.

## What about constant-time?

This is the part where the paper does most of the work and the post can only
gesture at it.

The constant-time template (Algorithm 3 in the paper) requires:

- **Fixed loop bounds.** The batched-inversion routine processes exactly `k`
  elements in both the forward (prefix-product) sweep and the backward
  (fold-back) sweep, with `k` known statically per batch.
- **Fixed memory access pattern.** The pattern of reads and writes to the
  prefix array and the fold-back accumulator is identical regardless of the
  input values; only the values themselves vary.
- **A constant-time `inv` primitive at the bottom.** The single inversion
  performed on the accumulated prefix product is delegated to a CT inversion
  routine — a Bernstein-Yang style algorithm, say — that exists outside the
  template.

The harness in the artifact implements the template shape. It does **not**
implement a bit-level constant-time inversion, and it does **not** validate
the template against `dudect` or formal CT tooling. The paper is explicit
about this: Proposition 2 scopes the assumptions under which the template
*can* be realised constant-time on a target platform. Realising it is the
implementer's problem; the paper gives a checklist.

If you take one thing away from this section: **"constant-time" in CA-BPN
means an algorithmic template, not a verified binary.** The artifact gives
you the policy, the scheduling shape, and a reproducible measurement
harness. It does not give you a deployed signature scheme.

## Reproducing the measurements

Everything below is from the [GitHub repository][repo].

### On macOS

```bash
brew install hyperfine
git clone https://github.com/yui9696/sqisign-cabpn-artifact
cd sqisign-cabpn-artifact
make build
make sweep
```

`make sweep` runs the state-size sweep at `α = 0.5` on a 64 KB L1D budget,
calls `hyperfine` for wall-clock means, and drops a TSV at
`bench/out/sweep_<timestamp>/summary.tsv`.

### On Linux x86_64

```bash
bash bench/linux/setup_ubuntu.sh
make bench-linux
```

This adds hardware-counter sampling (cycles, instructions, branch misses,
L1D / LLC references and misses) via `perf stat`, provided the kernel's
`perf_event_paranoid` policy is permissive enough.

### On AWS

```bash
cd bench/aws
AWS_RUNTIME_MINUTES=10 bash one_click_perf_ec2_metal.sh
```

`*.metal` instance classes expose hardware performance counters that
ordinary EC2 guests do not. Three independent cost limiters (an in-instance
`shutdown -h +45`, `instance-initiated-shutdown-behavior=terminate`, and an
explicit `terminate-instances` on script exit) make it safe to run
ad-hoc — see the [AWS README][aws] before pulling the trigger.

[aws]: https://github.com/yui9696/sqisign-cabpn-artifact/blob/main/bench/aws/README.md

## Sample results (Apple M2)

State-size sweep at `α = 0.5`, `n = 4096`, `iters = 200`:

| `state_bytes` | `k_selected` (CA-BPN) | `mean_ms` (CA-BPN) | `mean_ms` (fixed-k) |
|---:|---:|---:|---:|
| 256  | 128 | 21.11 | 21.13 |
| 512  |  64 | 22.83 | 23.47 |
| 1024 |  32 | 24.76 | 24.92 |
| 2048 |  16 | 30.01 | 29.98 |

Joint `(α, state_bytes)` sweep:

| `α` | `state_bytes` | `k_selected` | `mean_ms` (CA-BPN) | `mean_ms` (fixed-k) |
|---:|---:|---:|---:|---:|
| 0.3 |  512 | 32 | 25.02 | 24.74 |
| 0.3 | 2048 |  8 | 42.19 | 40.06 |
| 0.7 |  512 | 64 | 22.26 | 22.27 |
| 0.7 | 2048 | 16 | 29.92 | 31.86 |

Two observations and one warning.

**Observation 1.** On the Apple M2 with this toy field, CA-BPN tracks the
fixed-k baseline at the same selected `k` essentially within `hyperfine`
noise. The headline value of CA-BPN on this data is not a raw speedup — it
is the *interface*: a deterministic rule that selects `k` from a stated
cache budget without manual sweeping, and that comes with a working-set
bound a reviewer can audit.

**Observation 2.** Tightening α from 0.7 to 0.3 at fixed `state_bytes` halves
`k`, and runtime degrades when the resulting batches become too short to
amortise the per-batch inversion cost. This is the qualitative shape the
policy is supposed to produce, and it's reassuring that the harness exhibits
it; it would be worrying if it didn't.

**Warning.** All of these numbers are from one Apple M2. The harness uses a
toy 64-bit prime field (2⁶⁴ − 59), which makes the `I/M` ratio close to 1
and makes inversion comparatively cheap. Real SQIsign-grade fields are much
larger, and the I/M ratio there is substantially worse. **Do not extrapolate
these microsecond numbers to a real signature stack.** The artifact exists
to give you the harness and the policy; running it on your target field and
your target machine is the actual experiment.

## What this work is *not*

A short list, in roughly decreasing order of importance:

1. **Not an SQIsign implementation.** The harness operates on a toy 64-bit
   prime field. Translating to real SQIsign field arithmetic is left to
   downstream consumers.
2. **Not a verified constant-time binary.** The CT story is at the
   algorithmic-template level. Bit-level CT verification (dudect, formal
   tooling) is out of scope.
3. **Not a cross-platform study.** Sample results are from one Apple M2 and
   a small handful of Linux / AWS runs. Cross-platform replication is the
   most obvious follow-up.
4. **Not an autotuner.** CA-BPN selects from an explicit cache budget; it
   does not search the (cycles, L1 misses, LLC misses) Pareto frontier.
   Future work might.
5. **Not a comparison against published SQIsign optimisations.** The
   appropriate baseline for CA-BPN is "fixed-k chosen by hand or by the
   prior art's mixed strategy". Comparing against a fully tuned SQIsign
   implementation in real fields is a separate, much larger study.

## Open questions

A handful of things I'd like to see attempted by anyone with the
infrastructure to do so:

- **Real field arithmetic.** Drop in a Bernstein-Yang inversion over a real
  SQIsign field, repeat the sweeps, see how `k_selected` changes and whether
  the working-set bound still tracks reality at that scale.
- **Joint scheduling with the surrounding pipeline.** CA-BPN selects `k` in
  isolation from the surrounding Qlapoti `IdealToIsogeny` translation. A
  whole-pipeline scheduler that co-budgets the translation buffers and the
  inversion batches would close the integration loop more tightly than this
  policy alone.
- **Adversarial cache-pressure tests.** The working-set bound is a budget
  guarantee, not a miss-rate guarantee. Stress-testing it against
  contention (co-resident workloads, hyperthreaded siblings, NUMA crossings)
  would let you put numbers on the gap between bound and reality.
- **Formal CT for the template.** A small mechanised proof that Algorithm 3,
  *modulo* a CT `inv` primitive, has no secret-dependent control flow or
  memory access — preferably in a form that survives compilation.

If you do any of these, please open a PR; if you do all of them, you
probably have a follow-up paper.

## Closing note

The companion paper went through one round of academic peer review and was
not accepted, on roughly the grounds that it sits between cryptography and
computer architecture, leans on engineering measurements rather than tight
analytical bounds, and is authored by an independent researcher without an
institutional anchor. I think those are reasonable concerns for a
publication venue; I also think they're orthogonal to whether the result
is useful.

So the work is being published the other way: implementation first,
reproducibility first, paper as the formal companion. The repository is
the primary deliverable. The paper is in [`docs/paper.pdf`][paper] of the
repository (and will be on ePrint once the ID is assigned). The harness
runs in seconds on a laptop.

[paper]: https://github.com/yui9696/sqisign-cabpn-artifact/blob/main/docs/paper.pdf

If you build on this, I'd love to know. If you find an error in the
policy, the proof, or the harness, I'd love to know *more*. The repository
has Issues turned on.

📬 **tabei@ryun.jp** &nbsp;·&nbsp;
[Repository][repo] &nbsp;·&nbsp;
[Paper][paper] &nbsp;·&nbsp;
Open to remote cryptography and smart-contract security roles globally.
