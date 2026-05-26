#!/usr/bin/env bash
set -euo pipefail

# Minimal setup for Ubuntu 24.04 to run perf-based sweeps.
# Run from the repository root.

echo "## apt update"
sudo apt-get update -y

echo "## install deps (perf, build-essential, python3)"
sudo apt-get install -y \
  build-essential \
  curl \
  python3 \
  python3-venv \
  linux-tools-common \
  linux-tools-generic \
  linux-tools-$(uname -r) || true

echo "## install rust (system)"
if ! command -v cargo >/dev/null 2>&1; then
  curl https://sh.rustup.rs -sSf | sh -s -- -y
  # shellcheck disable=SC1090
  source "$HOME/.cargo/env"
fi

echo "## install hyperfine (optional)"
if ! command -v hyperfine >/dev/null 2>&1; then
  cargo install hyperfine || true
fi

echo "## build harness"
cd bench/rust_harness
cargo build --release

echo "DONE"
