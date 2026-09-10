#!/bin/sh
# Usage: run.sh <model.gguf> [more.gguf ...]
# Runs the eval cases through each GGUF in-process via Homebrew's llama.cpp
# (`brew install llama.cpp`), printing pass count, latency, memory and CPU.
# For Apple Intelligence use `make eval` at the repo root instead.
set -e
cd "$(dirname "$0")"
swift build -c release 2>&1 | grep -E "error" || true
.build/release/bench "$(cd ../.. && pwd)" "$@"
