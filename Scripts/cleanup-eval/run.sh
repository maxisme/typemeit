#!/bin/sh
# Compiles the app's TextCleanup and PostProcessor into the eval and runs it.
# Needs macOS 26 with Apple Intelligence enabled. Takes about a second a case.
# An optional argument names another PostProcessor.swift to score instead.
set -e
cd "$(dirname "$0")"
PP="${1:-../../TypeMeIt/PostProcessor.swift}"
swiftc -parse-as-library -O eval.swift "$PP" ../../TypeMeIt/Log.swift ../../TypeMeIt/TextCleanup.swift ../../TypeMeIt/TextCleanupCurrency.swift -o eval
./eval
