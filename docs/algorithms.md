# CA-BPN algorithms (extract)

Markdown extract of Algorithm 1 and Proposition 1 from the companion preprint
[`docs/paper.pdf`](paper.pdf). The full formal treatment — including the
correctness theorem for delayed normalization (Theorem 1) and the constant-time
template assumptions (Proposition 2) — lives in the paper.

## Notation

| Symbol | Meaning |
|---|---|
| `C_L1` | L1 data cache size in bytes |
| `B_state` | Estimated bytes per live projective state, including inverse-recovery scratch |
| `α ∈ (0, 1)` | Safety factor; the fraction of L1 the policy is willing to budget |
| `n` | Chain length (number of projective updates in the relevant translation subroutine) |
| `k` | Batch size chosen by the policy |
| `I`, `M` | Cost of a field inversion and a field multiplication, respectively |

## Algorithm 1 — CA-BPN: cache-aware batch-size selection

```
Require: chain length n, cache budget C_L1, estimated bytes/state B_state, safety α
 1: k_max ← ⌊α · C_L1 / B_state⌋
 2: k ← largest power-of-two ≤ k_max
 3: if k < 1 then
 4:     k ← 1
 5: end if
 6: optionally round k to a convenient divisor of n   (implementation choice)
 7: return k
```

The "largest power-of-two ≤ k_max" choice on line 2 is for two reasons:

- it makes the policy deterministic and trivially reproducible across runs;
- batched inversion bookkeeping (prefix products, fold-back acc multiplications)
  vectorises slightly more cleanly at power-of-two sizes on most contemporary
  microarchitectures.

The optional rounding on line 6 keeps the chain decomposition free of partial
tail batches when that simplifies downstream code; it is not required for the
correctness or working-set bound below.

## Proposition 1 — Working-set bound

**Claim.** Suppose the implementation maintains at most `k` projective states
"live" at a time, each with estimated footprint at most `B_state` bytes
(including any buffers required for inverse recovery within a batch). If
CA-BPN selects `k ≤ k_max = ⌊α · C_L1 / B_state⌋`, then the estimated live
footprint satisfies

    k · B_state ≤ α · C_L1.

**Proof.** By definition of `k_max`, we have `k_max · B_state ≤ α · C_L1`.
Since CA-BPN enforces `k ≤ k_max`, multiplying by `B_state` gives
`k · B_state ≤ k_max · B_state ≤ α · C_L1`.  ∎

This is the cache-pressure guarantee the policy is named for. It is a *budget*
guarantee, not a *miss-rate* guarantee: how close the actual L1 occupancy
tracks the estimate depends on `B_state`'s fidelity, on the layout of the
auxiliary scratch (prefix arrays, fold-back accumulators), and on contention
with the rest of the surrounding pipeline. The paper recommends calibrating
`B_state` per target platform.

## Cost model (background, from Section 3 of the paper)

Treat scheduling as choosing normalization boundaries `1 = t_0 < t_1 < ⋯ < t_s = n`
inducing segment lengths `k_j = t_j − t_{j−1}`. The objective is

    Cost = Σ_{j=1..s} ( I + μ(k_j) · M ) + λ · Φ(k_j; B_state, C_L1, …)

where `μ(k)` captures the multiplication overhead for inverse recovery and `Φ`
is a cache-pressure proxy that increases with the live footprint. A batched
inversion of `k` elements costs approximately `1 · I + 3·(k − 1) · M` plus
additional multiplications to recover each individual inverse.

CA-BPN sidesteps the joint minimisation of the algebraic term and the `Φ`
term by picking a single `k` from an explicit cache budget, and then evaluating
the resulting end-to-end runtime empirically. This deliberately trades
analytical tightness for a policy that is cheap, deterministic, and easy to
audit.

## What is *not* in this extract

- The correctness theorem for delaying affine normalization in homogeneous
  theta-coordinate updates (Theorem 1).
- The constant-time template (Algorithm 3) and the scope of Proposition 2,
  which states the assumptions under which the template can be realised
  without secret-dependent control flow or memory access.
- The full related-work discussion and the cost-model derivation.

For those, see [`paper.pdf`](paper.pdf).
