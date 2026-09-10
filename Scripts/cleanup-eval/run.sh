#!/bin/sh
# Scores the shipped clean-up path on cases.json: the app's TextCleanup and
# PostProcessor compiled in, run against Apple Intelligence. Needs macOS 26 with
# Apple Intelligence on. An optional argument names another PostProcessor.swift.
set -e
cd "$(dirname "$0")"
PP="${1:-../../TypeMeIt/PostProcessor.swift}"
swiftc -parse-as-library -O eval.swift "$PP" ../../TypeMeIt/Log.swift ../../TypeMeIt/TextCleanup.swift -o eval
./eval
