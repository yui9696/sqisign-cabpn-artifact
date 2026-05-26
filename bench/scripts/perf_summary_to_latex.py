#!/usr/bin/env python3
"""Reduce a Linux-perf sweep TSV into a concise LaTeX table.

Input is the TSV produced by bench/linux/run_perf_sweep.sh.
Output is a LaTeX tabular fragment with one row per (alpha, state_bytes)
group, showing CA-BPN vs sequential vs best fixed-k.
"""
import argparse
import csv
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Tuple


def latex_escape(s: str) -> str:
    return (
        s.replace("\\", "\\textbackslash{}")
        .replace("_", "\\_")
        .replace("%", "\\%")
        .replace("&", "\\&")
        .replace("#", "\\#")
    )


def fnum(x: float, digits: int = 3) -> str:
    if x is None or (isinstance(x, float) and (math.isnan(x) or math.isinf(x))):
        return ""
    return f"{x:.{digits}f}"


@dataclass(frozen=True)
class Row:
    alpha_milli: int
    state_bytes: int
    k_selected: int
    mode: str
    wall_ms_mean: float
    cycles: float
    instructions: float
    cache_misses: float


def to_int(s: str) -> int:
    return int(float(s))


def to_float(s: str) -> float:
    return float(s) if s != "" else float("nan")


def load_rows(path: Path) -> List[Row]:
    rows: List[Row] = []
    with path.open("r", encoding="utf-8") as f:
        r = csv.DictReader(f, delimiter="\t")
        for d in r:
            rows.append(
                Row(
                    alpha_milli=to_int(d.get("alpha_milli", "0")),
                    state_bytes=to_int(d.get("state_bytes", "0")),
                    k_selected=to_int(d.get("k_selected", "0")),
                    mode=(d.get("mode", "") or "").strip(),
                    wall_ms_mean=to_float(d.get("wall_ms_mean", "")),
                    cycles=to_float(d.get("cycles", "")),
                    instructions=to_float(d.get("instructions", "")),
                    cache_misses=to_float(d.get("cache_misses", "")),
                )
            )
    return rows


def group(rows: List[Row]) -> Dict[Tuple[int, int], List[Row]]:
    g: Dict[Tuple[int, int], List[Row]] = {}
    for row in rows:
        key = (row.alpha_milli, row.state_bytes)
        g.setdefault(key, []).append(row)
    return g


def best_fixed(rows: List[Row]) -> Row | None:
    fixed = [x for x in rows if x.mode == "fixed" and not math.isnan(x.wall_ms_mean)]
    if not fixed:
        return None
    return min(fixed, key=lambda x: x.wall_ms_mean)


def pick_mode(rows: List[Row], mode: str) -> Row | None:
    xs = [x for x in rows if x.mode == mode]
    return xs[0] if xs else None


def make_table(groups: Dict[Tuple[int, int], List[Row]], caption: str, label: str) -> str:
    keys = sorted(groups.keys())

    out: List[str] = []
    out.append("\\begin{table}[t]")
    out.append("\\centering")
    out.append(f"\\caption{{{latex_escape(caption)}}}")
    out.append(f"\\label{{{latex_escape(label)}}}")
    out.append("\\begin{tabular}{rrrrrrrr}")
    out.append("\\toprule")
    out.append(
        "alpha(milli) & state(B) & $k_{\\mathrm{CA}}$ & CA-BPN(ms) & seq(ms) & best $k$ & best(ms) & CA/best(ms) \\\\"
    )
    out.append("\\midrule")

    for (a, sb) in keys:
        rs = groups[(a, sb)]
        cabpn = pick_mode(rs, "cabpn")
        seq = pick_mode(rs, "sequential")
        bf = best_fixed(rs)
        if cabpn is None or seq is None:
            continue

        time_ratio = float("nan")
        if bf is not None and bf.wall_ms_mean > 0 and not math.isnan(cabpn.wall_ms_mean):
            time_ratio = cabpn.wall_ms_mean / bf.wall_ms_mean

        out.append(
            " & ".join(
                [
                    str(a),
                    str(sb),
                    str(cabpn.k_selected),
                    fnum(cabpn.wall_ms_mean),
                    fnum(seq.wall_ms_mean),
                    "" if bf is None else str(bf.k_selected),
                    "" if bf is None else fnum(bf.wall_ms_mean),
                    fnum(time_ratio, digits=2),
                ]
            )
            + " \\\\"
        )

    out.append("\\bottomrule")
    out.append("\\end{tabular}")
    out.append("\\end{table}")
    out.append("")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description="Reduce perf sweep TSV into a concise LaTeX table.")
    ap.add_argument("tsv", type=Path, help="summary_perf.tsv")
    ap.add_argument("--caption", default="Linux perf sweep summary (CA-BPN vs baselines).")
    ap.add_argument("--label", default="tab:perf_sweep")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--alpha", type=int, default=0, help="If set, filter to this alpha_milli.")
    args = ap.parse_args()

    rows = load_rows(args.tsv)
    if args.alpha:
        rows = [r for r in rows if r.alpha_milli == args.alpha]
    g = group(rows)

    tex = make_table(g, args.caption, args.label)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(tex, encoding="utf-8")


if __name__ == "__main__":
    main()
