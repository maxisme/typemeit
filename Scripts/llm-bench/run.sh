#!/bin/sh
# Usage: run.sh apple | run.sh <model.gguf> [more.gguf ...]
# Needs `brew install llama.cpp` for the gguf mode. Writes result-*.json next
# to this script and prints one summary line per model.
set -e
cd "$(dirname "$0")"
swift build -c release 2>&1 | grep -E "error|warning: unre" || true
.build/release/bench "$(cd ../.. && pwd)" "$@"
