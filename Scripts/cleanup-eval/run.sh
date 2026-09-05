#!/bin/sh
# Compiles and runs the Apple Intelligence clean-up eval. Needs macOS 26 with
# Apple Intelligence enabled. Takes about a second a case.
set -e
cd "$(dirname "$0")"
swiftc -parse-as-library -O eval.swift -o eval
./eval "$@"
