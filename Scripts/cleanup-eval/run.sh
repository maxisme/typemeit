#!/bin/sh
# Scores the shipped clean-up path on cases.json: the app's PostProcessor
# compiled in, run against Apple Intelligence. Needs macOS 26 with Apple
# Intelligence on. An optional argument names another PostProcessor.swift.
set -e
cd "$(dirname "$0")"
PP="${1:-../../TypeMeIt/PostProcessor.swift}"
swiftc -parse-as-library -O -enable-bare-slash-regex eval.swift "$PP" ../../TypeMeIt/Log.swift ../../TypeMeIt/ModelText.swift ../../TypeMeIt/ScreenContext.swift ../../TypeMeIt/CustomWordMatcher.swift ../../TypeMeIt/LocalCleanup.swift -o eval
./eval
