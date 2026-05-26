#!/usr/bin/env python3
"""Aggregate per-run perf-counter blocks into a single summary row.

Reads a tab-separated file of (event, value) pairs split into runs by the
trailing 'wall_seconds' line. Appends one mean-aggregated row to the
summary TSV consumed by perf_summary_to_latex.py.
"""
import argparse
import math
from collections import defaultdict


def mean(xs):
    return sum(xs) / len(xs) if xs else float("nan")


def std(xs):
    if len(xs) < 2:
        return 0.0
    m = mean(xs)
    return math.sqrt(sum((x - m) ** 2 for x in xs) / (len(xs) - 1))


def parse_runs(path):
    runs = []
    cur = defaultdict(list)
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                ev, val = line.split("\t", 1)
            except ValueError:
                continue
            try:
                x = float(val)
            except ValueError:
                continue
            cur[ev].append(x)
            if ev == "wall_seconds":
                run = {k: v[-1] for k, v in cur.items() if v}
                runs.append(run)
                cur = defaultdict(list)
    return runs


def summarize(runs):
    agg = defaultdict(list)
    for r in runs:
        for k, v in r.items():
            agg[k].append(v)
    return agg


def get_counter(agg, event):
    xs = agg.get(event, [])
    return mean(xs) if xs else float("nan")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--alpha-milli", type=int, required=True)
    ap.add_argument("--state-bytes", type=int, required=True)
    ap.add_argument("--mode", type=str, required=True)
    ap.add_argument("--k-selected", type=int, required=True)
    ap.add_argument("--input", type=str, required=True)
    ap.add_argument("--output", type=str, required=True)
    args = ap.parse_args()

    runs = parse_runs(args.input)
    if not runs:
        raise SystemExit(f"No runs parsed from {args.input}")
    agg = summarize(runs)

    wall_s = agg.get("wall_seconds", [])
    wall_ms = [x * 1000.0 for x in wall_s]
    wall_ms_mean = mean(wall_ms)
    wall_ms_std = std(wall_ms)

    cycles = get_counter(agg, "cycles")
    inst = get_counter(agg, "instructions")
    branches = get_counter(agg, "branches")
    br_miss = get_counter(agg, "branch-misses")
    cache_ref = get_counter(agg, "cache-references")
    cache_miss = get_counter(agg, "cache-misses")

    k_selected = args.k_selected

    line = (
        f"{args.alpha_milli}\t{args.state_bytes}\t{k_selected}\t{args.mode}\t"
        f"{wall_ms_mean:.3f}\t{wall_ms_std:.3f}\t"
        f"{cycles:.3f}\t{inst:.3f}\t{branches:.3f}\t{br_miss:.3f}\t{cache_ref:.3f}\t{cache_miss:.3f}\n"
    )
    with open(args.output, "a", encoding="utf-8") as f:
        f.write(line)


if __name__ == "__main__":
    main()
