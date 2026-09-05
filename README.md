# Type Me It

Hold the fn key, speak, let go. The speech is transcribed on this Mac by Parakeet through transcribe.cpp, tidied up by Apple Intelligence, and pasted wherever the cursor is. It learns your vocabulary from the corrections you make afterwards, keeps a text-only history, and shows usage insights. Nothing leaves the computer.

macOS 26 or newer, Apple silicon.

## Build

```
brew install xcodegen
DEVELOPMENT_TEAM=Z28DW76Y3W xcodegen generate
xcodebuild -project TypeMeIt.xcodeproj -scheme TypeMeIt -configuration Debug build
xcodebuild -project TypeMeIt.xcodeproj -scheme TypeMeIt test
```

The only dependency is the transcribe.cpp XCFramework, fetched by SwiftPM from the upstream release (`Packages/TranscribeCpp`). The speech model (697 MB) is downloaded during onboarding into `~/Library/Application Support/TypeMeIt/models/`.

## Permissions

Microphone, Accessibility (pasting and reading corrections) and Input Monitoring (the fn key). Grants are keyed to the code signature, so run a Developer ID signed build from `/Applications` or expect to re-grant after each rebuild.

## Release

A `v*` tag runs `.github/workflows/release.yml`, which builds, notarises and staples a DMG through `fastlane mac dmg` and attaches it to a GitHub release. The app checks that release feed and opens the release page when a newer version exists.

## Layout

- `TypeMeIt/` app sources, one file per module
- `TypeMeIt/Learning/`, `TypeMeIt/Insights/` ports of Handy's learning engine and insights, with their tests in `TypeMeItTests/`
- `Packages/TranscribeCpp/` the XCFramework wrapper
- `web/` the puff on a web page, driven by the pointer; `generate.py` transpiles the shader from `TypeMeIt/Overlay/Puff.metal`
- `fastlane/`, `Scripts/`, `.github/workflows/` the release pipeline
