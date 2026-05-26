#!/usr/bin/env python3
"""Convert a TSV summary into a LaTeX tabular for the ePrint/arXiv submission."""
import argparse
import csv
from pathlib import Path


def infer_alignment(headers):
    aligns = []
    for h in headers:
        if "mean" in h or "ms" in h:
            aligns.append("r")
        elif "k" in h or "bytes" in h or "alpha" in h:
            aligns.append("r")
        else:
            aligns.append("l")
    return "".join(aligns)


def latex_escape(s: str) -> str:
    return (
        s.replace("\\", "\\textbackslash{}")
        .replace("_", "\\_")
        .replace("%", "\\%")
        .replace("&", "\\&")
        .replace("#", "\\#")
    )


def main():
    ap = argparse.ArgumentParser(description="Convert a TSV summary into a LaTeX tabular.")
    ap.add_argument("tsv", type=Path)
    ap.add_argument("--caption", default="Benchmark summary.")
    ap.add_argument("--label", default="tab:bench")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--columns", default="", help="Comma-separated subset of columns to include.")
    args = ap.parse_args()

    with args.tsv.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        rows = list(reader)
        headers = reader.fieldnames or []

    if args.columns.strip():
        keep = [c.strip() for c in args.columns.split(",") if c.strip()]
        headers = [h for h in headers if h in keep]
        rows = [{h: r.get(h, "") for h in headers} for r in rows]

    align = infer_alignment(headers)

    out_lines = []
    out_lines.append("\\begin{table}[t]")
    out_lines.append("\\centering")
    out_lines.append(f"\\caption{{{latex_escape(args.caption)}}}")
    out_lines.append(f"\\label{{{latex_escape(args.label)}}}")
    out_lines.append(f"\\begin{{tabular}}{{{align}}}")
    out_lines.append("\\toprule")
    out_lines.append(" & ".join(latex_escape(h) for h in headers) + " \\\\")
    out_lines.append("\\midrule")
    for r in rows:
        out_lines.append(" & ".join(latex_escape(str(r.get(h, ""))) for h in headers) + " \\\\")
    out_lines.append("\\bottomrule")
    out_lines.append("\\end{tabular}")
    out_lines.append("\\end{table}")
    out_lines.append("")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(out_lines), encoding="utf-8")


if __name__ == "__main__":
    main()
