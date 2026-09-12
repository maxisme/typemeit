#!/bin/sh
# Builds the probe against the app's Transcriber and runs it over the
# recordings in Application Support. Arguments pass through: a count of
# most-recent recordings (default 80), or --all.
set -e
cd "$(dirname "$0")"
swift build -c release 2>&1 | grep -E "error|warning: unre" || true
.build/release/probe "$@"
