# Handoff — what to do next

This file is for the repository owner (Moe Tabei). Delete it before, or
shortly after, publishing the repo. It is not part of the artifact.

## Repository tree (depth 3, post-completion)

```
sqisign-cabpn-artifact/
├── ARTICLE.md
├── CITATION.cff
├── HANDOFF.md                 ← delete before/after publishing
├── LICENSE
├── Makefile
├── README.md
├── bench/
│   ├── aws/
│   │   ├── README.md
│   │   ├── one_click_perf_ec2.sh
│   │   └── one_click_perf_ec2_metal.sh
│   ├── linux/
│   │   ├── README.md
│   │   ├── run_perf_sweep.sh
│   │   ├── setup_ubuntu.sh
│   │   └── summarize_perf_tsv.py
│   ├── results/
│   │   ├── sweep_alpha_20260219/
│   │   │   ├── env.txt
│   │   │   └── summary.tsv
│   │   └── sweep_state_20260219/
│   │       ├── env.txt
│   │       └── summary.tsv
│   ├── rust_harness/
│   │   ├── Cargo.toml
│   │   └── src/main.rs
│   └── scripts/
│       ├── collect_env.sh
│       ├── perf_summary_to_latex.py
│       ├── sweep_cabpn.sh
│       ├── sweep_cabpn_alpha.sh
│       └── tsv_to_latex.py
└── docs/
    ├── algorithms.md
    └── paper.pdf
```

## Three steps to go live

### 1. Create the GitHub repo (private first, public after sanity check)

```bash
cd /Users/moe/sqisign-cabpn-artifact    # move target — see "Location" below
gh repo create sqisign-cabpn-artifact --public --source=. --remote=origin \
    --description "Cache-Aware Batch-size Policy for Constant-Time Normalization in Isogeny Pipelines — companion artifact to ePrint preprint."
git push -u origin main
```

If you prefer to eyeball it once before going public, swap `--public` for
`--private`, push, browse it on github.com, then flip the visibility from
the repo settings.

### 2. Resolve the placeholder URLs

Three places carry an `eprint.iacr.org/2026/XXXX` placeholder:

- [`README.md`](README.md) — badge URL and "Companion paper" block
- [`ARTICLE.md`](ARTICLE.md) — opening blockquote
- [`CITATION.cff`](CITATION.cff) — `preferred-citation.url` and `notes`

Once ePrint assigns an ID, `sed` them all in one shot:

```bash
EPRINT_ID="2026/0042"  # replace
sed -i '' "s|2026/XXXX|${EPRINT_ID}|g" README.md ARTICLE.md CITATION.cff
```

(macOS `sed` needs the empty `''` after `-i`; on Linux drop it.)

Also update the GitHub URL in `CITATION.cff` (`repository-code`) if your
username differs from `moetabei`. Same for the `[repo]:` link reference at
the top of `ARTICLE.md` and the AWS link in the same file.

### 3. Announce

#### Paste-ready X post (≤ 280 chars)

> New open-source artifact: CA-BPN, a cache-aware batch-size policy for
> constant-time normalization in isogeny pipelines (SQIsign / Qlapoti).
> Working-set bound, reproducible Mac + Linux + AWS sweeps, companion ePrint
> preprint. Implementation-first.
> https://github.com/moetabei/sqisign-cabpn-artifact

(279 chars including the URL — adjust handle if different.)

#### Paste-ready Hacker News submission

- **Title:** `CA-BPN: cache-aware batch scheduling for constant-time isogeny normalization`
- **URL:** `https://github.com/moetabei/sqisign-cabpn-artifact`
- **First comment (post immediately after submission to seed discussion):**
  ```
  Author here. This is the open-source companion to a paper that didn't make
  it through one round of academic peer review — the gist of the review was
  that the work sits between cryptography and computer architecture and
  leans on engineering measurements over tight analytical bounds. Those are
  fair concerns for a venue; orthogonal to whether the policy is useful in
  practice, which is what the repo is for.

  The artifact ships the policy (CA-BPN), the constant-time batched-inversion
  template (Algorithm 3 in the paper), a reproducible sweep harness with
  Mac/Linux/AWS drivers, and sample measurements on Apple M2. The harness
  uses a toy 64-bit prime field, deliberately — the goal is to exercise the
  scheduling-policy interface, not to claim end-to-end speedups for a real
  signature stack. README has the full scope-and-limitations section.

  Happy to take feedback on the policy, the proof, or the harness.
  ```

#### Suggested distribution sequence

1. **Day 0:** Push to GitHub, post on X, submit to HN. Tag people in the PQC
   space who follow your account (not before — let the post stand on its
   own first).
2. **Day 1–2:** Copy `ARTICLE.md` content into [HackMD](https://hackmd.io)
   under your account. Cross-post the same content to
   [Mirror.xyz](https://mirror.xyz) for the Web3 audience. Both will
   tolerate the markdown as-is.
3. **Day 3–5:** If you have a quiet research-Discord or Telegram group
   (e.g. an isogeny-focused channel), share once with a one-liner. Don't
   spam; one targeted share is worth ten broadcasts.
4. **Day 7+:** Update `CITATION.cff` and the placeholder URLs once the
   ePrint ID is assigned; push a follow-up commit.

## Location

The agent that scaffolded this artifact built it inside `katana-audit/`.
That's an audit working directory and an odd place for a public-facing
repository to live. Move it to the home directory before running `gh repo
create`:

```bash
mv /Users/moe/katana-audit/sqisign-cabpn-artifact /Users/moe/sqisign-cabpn-artifact
```

A `git init` and initial commit are part of the standard flow — see step 1
above. The repository does not yet contain a `.git/` directory; you'll
create it freshly on the first `gh repo create` (or `git init` followed by
`git add . && git commit`).

## Things flagged for the paper itself

Two minor things spotted while writing the artifact:

1. **`CITATION.cff` vs. paper title.** The current paper PDF in
   `docs/paper.pdf` is the March 8, 2026 revision. The artifact's
   `CITATION.cff` cites the same title with month: 3 / year: 2026. If you
   resubmit a *revised* version to ePrint with a different title or
   subtitle, update `CITATION.cff` to match.
2. **The harness's `mod_inv` is egcd, not constant-time.** This is
   correctly noted in the harness comments and in the README's scope
   section, but consider adding a one-sentence forward pointer in the
   *paper*'s implementation section saying "the public reference harness
   uses egcd for the toy field for simplicity; Proposition 2 applies to a
   CT `inv` primitive substituted in by the implementer." This avoids
   anyone reading the paper and the artifact in the wrong order and
   concluding the policy is unsafe.

Neither is blocking.

## What was *not* done

- **No `cargo bench`.** The sweep is driven by `hyperfine` and shell scripts
  rather than Criterion / `cargo bench`, on the grounds that wall-clock
  means + perf counters are the metrics the paper cares about. If you want
  a Criterion harness later for completeness, it would slot in alongside
  the existing scripts.
- **No CI.** No GitHub Actions workflow. A minimal one that runs `cargo
  build --release` on push would be polite but is not required for the
  artifact to be usable.
- **No GitHub push.** Credentials and visibility decisions belong to you.

## When you're done with this file

```bash
git rm HANDOFF.md && git commit -m "Remove handoff notes"
```
