#!/usr/bin/env bash
# Print a reproducibility snapshot of the host environment.
# Output is plain text suitable for committing alongside benchmark results.

set -euo pipefail

echo "## date"
date
echo

echo "## uname"
uname -a
echo

echo "## sw_vers"
sw_vers || true
echo

echo "## cpu/mem"
sysctl -n machdep.cpu.brand_string 2>/dev/null || true
sysctl -n hw.memsize 2>/dev/null || true
echo

echo "## caches (sysctl)"
sysctl -n hw.l1dcachesize 2>/dev/null || true
sysctl -n hw.l2cachesize 2>/dev/null || true
sysctl -n hw.cachelinesize 2>/dev/null || true
echo

echo "## disk"
df -h / || true
echo

echo "## toolchain"
command -v brew >/dev/null 2>&1 && brew --version | head -2 || echo "brew: not found"
command -v python3 >/dev/null 2>&1 && python3 --version || echo "python3: not found"
command -v rustc >/dev/null 2>&1 && rustc --version || echo "rustc: not found"
command -v cargo >/dev/null 2>&1 && cargo --version || echo "cargo: not found"
command -v hyperfine >/dev/null 2>&1 && hyperfine --version || echo "hyperfine: not found"
