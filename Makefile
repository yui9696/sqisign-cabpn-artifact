# Convenience targets for the CA-BPN artifact.
#
# All targets are thin wrappers over the scripts in bench/scripts/ and
# bench/linux/ so the underlying invocations remain transparent and
# reproducible by hand.

SHELL := /usr/bin/env bash
HARNESS_DIR := bench/rust_harness
HARNESS_BIN := $(HARNESS_DIR)/target/release/rust_harness

.PHONY: help build bench-mac bench-linux sweep sweep-alpha env clean

help: ## Show this help.
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build the Rust harness in release mode.
	cd $(HARNESS_DIR) && cargo build --release

$(HARNESS_BIN): build

bench-mac: $(HARNESS_BIN) ## Mac wall-clock micro-bench (hyperfine; CA-BPN vs fixed-k).
	@command -v hyperfine >/dev/null || { echo "install hyperfine first: brew install hyperfine"; exit 1; }
	bash bench/scripts/sweep_cabpn.sh

bench-linux: $(HARNESS_BIN) ## Linux perf-counter sweep (requires perf + sudo).
	@command -v perf >/dev/null || { echo "install perf first: sudo apt-get install linux-tools-generic"; exit 1; }
	bash bench/linux/run_perf_sweep.sh

sweep: $(HARNESS_BIN) ## State-size sweep at fixed alpha=0.5 (Mac, hyperfine).
	bash bench/scripts/sweep_cabpn.sh

sweep-alpha: $(HARNESS_BIN) ## Joint (alpha, state_bytes) sweep (Mac, hyperfine).
	bash bench/scripts/sweep_cabpn_alpha.sh

env: ## Print the local environment snapshot used by sweep scripts.
	bash bench/scripts/collect_env.sh

clean: ## Remove build artifacts.
	cd $(HARNESS_DIR) && cargo clean
	rm -rf bench/out
