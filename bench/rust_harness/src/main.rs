// CA-BPN scheduling-policy harness.
//
// This program is the reference harness for the companion ePrint preprint
// "Formal Guarantees and Microarchitectural Scheduling for Constant-Time
// Normalization in Theta-Coordinate Isogeny Pipelines" (M. Tabei, 2026).
//
// IMPORTANT — what this is, and what it is NOT:
//
//   * The field arithmetic below is a TOY 64-bit prime field (MOD = 2^64 - 59).
//     It is NOT an SQIsign field, NOT a 254/256-bit field, and NOT a constant-
//     time bignum stack. Using a small word-sized prime keeps the harness
//     dependency-free and makes the scheduling-policy shape (Algorithm 1 of
//     the paper) reproducible on a laptop in seconds.
//
//   * The benchmark measures the shape of CA-BPN's k-selection and its
//     end-to-end runtime against fixed-k and sequential baselines on a
//     synthetic chain of batched inversions. It is an *integration* study of
//     the scheduling interface, not a benchmark of a real isogeny stack.
//
//   * "Constant-time" in the paper refers to the algorithmic template
//     (Algorithm 3, fixed loop bounds, fixed memory access pattern). This
//     harness implements that template shape; it does NOT perform bit-level
//     constant-time verification (no dudect, no formal CT proof, no checked
//     compiler output).
//
// See ../../README.md, section "Scope and limitations" for the full caveats.

use std::time::Instant;

// A fixed 64-bit prime (2^64 - 59) is prime.
const MOD: u64 = 0xFFFF_FFFF_FFFF_FFC5;

#[derive(Clone, Copy)]
struct XorShift64 {
    x: u64,
}

impl XorShift64 {
    fn new(seed: u64) -> Self {
        Self { x: seed.max(1) }
    }
    fn next(&mut self) -> u64 {
        let mut x = self.x;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.x = x;
        x
    }
}

#[inline(always)]
fn mod_mul(a: u64, b: u64) -> u64 {
    // (a*b) mod MOD using u128 reduction (MOD < 2^64).
    let p = (a as u128) * (b as u128);
    (p % (MOD as u128)) as u64
}

#[inline(always)]
fn mod_add(a: u64, b: u64) -> u64 {
    let s = a.wrapping_add(b);
    if s >= MOD { s - MOD } else { s }
}

fn egcd(mut a: i128, mut b: i128) -> (i128, i128, i128) {
    // returns (g, x, y) such that ax + by = g
    let (mut x0, mut x1) = (1i128, 0i128);
    let (mut y0, mut y1) = (0i128, 1i128);
    while b != 0 {
        let q = a / b;
        (a, b) = (b, a - q * b);
        (x0, x1) = (x1, x0 - q * x1);
        (y0, y1) = (y1, y0 - q * y1);
    }
    (a, x0, y0)
}

fn mod_inv(a: u64) -> u64 {
    // Inverse modulo MOD (assumes a != 0).
    // NOTE: extended Euclidean is *not* a constant-time inversion routine.
    // The paper's Proposition 2 assumes a constant-time `inv` primitive
    // exists on the target platform (e.g., a Bernstein-Yang style routine
    // over the real SQIsign field). This harness uses egcd purely to make
    // the toy field self-contained and dependency-free.
    let (g, x, _) = egcd(a as i128, MOD as i128);
    debug_assert!(g == 1);
    let mut r = x % (MOD as i128);
    if r < 0 {
        r += MOD as i128;
    }
    r as u64
}

#[derive(Default)]
struct Counters {
    muls: u64,
    invs: u64,
}

/// Algorithm 3 of the paper: constant-time batched inversion template
/// with fixed loop bounds and a fixed, sequential memory access pattern.
fn ct_batched_inversion(d: &[u64], inv_out: &mut [u64], ctr: &mut Counters) {
    let k = d.len();
    let mut prefix = vec![0u64; k + 1];
    prefix[0] = 1;
    for i in 1..=k {
        prefix[i] = mod_mul(prefix[i - 1], d[i - 1]);
        ctr.muls += 1;
    }
    let mut acc = mod_inv(prefix[k]);
    ctr.invs += 1;
    for i in (1..=k).rev() {
        inv_out[i - 1] = mod_mul(acc, prefix[i - 1]);
        ctr.muls += 1;
        acc = mod_mul(acc, d[i - 1]);
        ctr.muls += 1;
    }
}

fn sequential_inversion(d: &[u64], inv_out: &mut [u64], ctr: &mut Counters) {
    for (i, &x) in d.iter().enumerate() {
        inv_out[i] = mod_inv(x);
        ctr.invs += 1;
    }
}

fn largest_pow2_leq(x: usize) -> usize {
    if x < 1 {
        return 0;
    }
    1usize << (usize::BITS as usize - 1 - (x as u64).leading_zeros() as usize)
}

/// Algorithm 1 of the paper: CA-BPN cache-aware batch-size selection.
/// k_max = floor(alpha * L1 / state_bytes); k = largest power-of-two <= k_max.
/// alpha is encoded in milli-units (e.g., 500 = 0.5).
fn cabpn_select_k(l1_bytes: usize, state_bytes: usize, alpha_milli: u64, n: usize) -> usize {
    if state_bytes == 0 {
        return 1;
    }
    let budget = (l1_bytes as u128) * (alpha_milli as u128) / 1000u128;
    let k_max = (budget / (state_bytes as u128)) as usize;
    let mut k = largest_pow2_leq(k_max.max(1));
    if k == 0 {
        k = 1;
    }
    k = k.min(n.max(1));
    k
}

fn chain_process_batched(d: &[u64], k: usize, inv_out: &mut [u64], ctr: &mut Counters) {
    let n = d.len();
    let mut i = 0;
    while i < n {
        let end = (i + k).min(n);
        ct_batched_inversion(&d[i..end], &mut inv_out[i..end], ctr);
        i = end;
    }
}

fn chain_process_sequential(d: &[u64], inv_out: &mut [u64], ctr: &mut Counters) {
    sequential_inversion(d, inv_out, ctr);
}

fn parse_u64(args: &[String], key: &str, default: u64) -> u64 {
    args.iter()
        .position(|a| a == key)
        .and_then(|i| args.get(i + 1))
        .and_then(|v| v.parse::<u64>().ok())
        .unwrap_or(default)
}

fn parse_str<'a>(args: &'a [String], key: &str, default: &'a str) -> &'a str {
    args.iter()
        .position(|a| a == key)
        .and_then(|i| args.get(i + 1))
        .map(|s| s.as_str())
        .unwrap_or(default)
}

fn print_help() {
    let help = r#"rust_harness — CA-BPN scheduling-policy demonstrator (toy 64-bit prime field)

Companion artifact to the ePrint preprint:
  "Formal Guarantees and Microarchitectural Scheduling for Constant-Time
   Normalization in Theta-Coordinate Isogeny Pipelines" (M. Tabei, 2026).

USAGE:
  rust_harness [--mode MODE] [options]

MODES:
  inv_sequential     Invert k elements one by one using Fermat/extended-Euclid.
  inv_batched        Invert k elements via Algorithm 3 (CT batched inversion).
  chain_fixedk       Process a chain of length n in batches of fixed size k.
  chain_cabpn        Select k via CA-BPN (Algorithm 1), then process the chain.
  chain_sequential   Process the chain element-by-element (k = 1 baseline).

OPTIONS:
  --iters N          Number of measurement iterations (default: 20000).
  --seed N           XorShift64 PRNG seed (default: 0xC0FFEE).
  --k N              Batch size for inv_* and chain_fixedk (default: 8).
  --n N              Chain length for chain_* modes (default: 1024).
  --l1-bytes N       L1D cache size in bytes for CA-BPN (default: 65536).
  --state-bytes N    Estimated bytes per live projective state (default: 512).
  --alpha-milli N    Safety factor alpha * 1000 (default: 500 -> alpha=0.5).
  -h | --help        Print this help and exit.

NOTES:
  * The field is a toy 64-bit prime (2^64 - 59). This harness is NOT an
    SQIsign implementation. See README.md for scope and limitations.
  * Output is printed as key=value lines (mode, k, n, iters, muls, invs,
    checksum, elapsed_ms) suitable for parsing by the sweep scripts.

EXAMPLES:
  # State-size sweep (CA-BPN selects k):
  rust_harness --mode chain_cabpn --n 4096 --iters 100 \
      --l1-bytes 65536 --state-bytes 1024 --alpha-milli 500

  # Fixed-k baseline at the CA-BPN-selected k for direct comparison:
  rust_harness --mode chain_fixedk --k 32 --n 4096 --iters 100
"#;
    print!("{help}");
}

fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.iter().any(|a| a == "-h" || a == "--help") {
        print_help();
        return;
    }

    // Modes:
    // - inv_sequential: invert k elements sequentially
    // - inv_batched: invert k elements using CT batched inversion (Algorithm 3)
    // - chain_fixedk: process a chain of length n using fixed k batches
    // - chain_cabpn: select k via CA-BPN policy (Algorithm 1) then process chain
    // - chain_sequential: process chain element by element (k=1 baseline)
    let mode = parse_str(&args, "--mode", "inv_batched");
    let iters = parse_u64(&args, "--iters", 20_000);
    let seed = parse_u64(&args, "--seed", 0xC0FFEE_u64);

    let mut rng = XorShift64::new(seed);
    let k = parse_u64(&args, "--k", 8) as usize;
    let n = parse_u64(&args, "--n", 1024) as usize;
    let l1 = parse_u64(&args, "--l1-bytes", 65_536) as usize;
    let state_bytes = parse_u64(&args, "--state-bytes", 512) as usize;
    let alpha_milli = parse_u64(&args, "--alpha-milli", 500); // 500 => 0.5

    let input_len = if mode.starts_with("inv_") { k } else { n };
    let mut d = vec![0u64; input_len];
    for i in 0..input_len {
        let mut v = rng.next() % MOD;
        if v == 0 {
            v = 1;
        }
        d[i] = v;
    }

    let mut inv = vec![0u64; input_len];
    let mut ctr = Counters::default();

    let start = Instant::now();
    let mut checksum: u64 = 0;
    for _ in 0..iters {
        match mode {
            "inv_sequential" => sequential_inversion(&d, &mut inv, &mut ctr),
            "inv_batched" => ct_batched_inversion(&d, &mut inv, &mut ctr),
            "chain_fixedk" => chain_process_batched(&d, k.max(1), &mut inv, &mut ctr),
            "chain_cabpn" => {
                let k_sel = cabpn_select_k(l1, state_bytes, alpha_milli, d.len());
                chain_process_batched(&d, k_sel, &mut inv, &mut ctr);
            }
            "chain_sequential" => chain_process_sequential(&d, &mut inv, &mut ctr),
            _ => {
                eprintln!("unknown --mode {}", mode);
                eprintln!("run with --help for usage.");
                std::process::exit(2);
            }
        }
        // cheap checksum to prevent optimization-out
        for &x in inv.iter() {
            checksum = mod_add(checksum, x);
        }
    }
    let elapsed = start.elapsed();

    println!("mode={}", mode);
    println!("k={}", k);
    if mode == "chain_cabpn" {
        let k_sel = cabpn_select_k(l1, state_bytes, alpha_milli, input_len);
        println!("k_selected={}", k_sel);
        println!("l1_bytes={}", l1);
        println!("state_bytes={}", state_bytes);
        println!("alpha_milli={}", alpha_milli);
    }
    if mode.starts_with("chain_") {
        println!("n={}", n);
    }
    println!("iters={}", iters);
    println!("muls={}", ctr.muls);
    println!("invs={}", ctr.invs);
    println!("checksum={}", checksum);
    println!(
        "elapsed_ms={}",
        (elapsed.as_secs_f64() * 1000.0).to_string()
    );
}
