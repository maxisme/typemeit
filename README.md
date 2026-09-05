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

Dependencies are the transcribe.cpp XCFramework, fetched by SwiftPM from the upstream release (`Packages/TranscribeCpp`), and Sparkle, which handles updates. The speech model (697 MB) is downloaded during onboarding into `~/Library/Application Support/TypeMeIt/models/`.

## Permissions

Microphone, Accessibility (pasting and reading corrections) and Input Monitoring (the fn key). Grants are keyed to the code signature, so run a Developer ID signed build from `/Applications` or expect to re-grant after each rebuild.

## Release

A `v*` tag runs `.github/workflows/release.yml`, which calls `Scripts/release-dmg.sh`: plain `xcodebuild` and `notarytool`, runnable by hand with `DEVELOPMENT_TEAM`, `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_PATH` set. It builds with Developer ID, notarises and staples both the app and the DMG, verifies the result with `syspolicy_check distribution`, and signs a Sparkle appcast for it. The workflow attaches the DMG and `appcast.xml` to a GitHub release.

`SUFeedURL` points at `/releases/latest/download/appcast.xml`, and the cloud on typeme.it links to `/releases/latest/download/TypeMeIt.dmg`. Both only resolve because the repository is public and the DMG asset is named the same every release, so publishing the release is what ships the update, and Sparkle installs the same DMG a first-time visitor downloads.

The appcast is signed with an EdDSA key. Its public half is `SUPublicEDKey` in `project.yml`; the private half lives in the login Keychain under the `typemeit` account locally, and in the `SPARKLE_ED_PRIVATE_KEY` repository secret for CI. Export it with Sparkle's own tool:

```
build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key.txt --account typemeit
```

## Layout

- `TypeMeIt/` app sources, one file per module
- `TypeMeIt/Learning/`, `TypeMeIt/Insights/` ports of Handy's learning engine and insights, with their tests in `TypeMeItTests/`
- `Packages/TranscribeCpp/` the XCFramework wrapper
- `web/` the puff on a web page, driven by the pointer; `generate.py` transpiles the shader from `TypeMeIt/Overlay/Puff.metal`
- `Scripts/`, `.github/workflows/` the release pipeline; `Scripts/generate-dmg-background.sh` draws the disk image's background from frames of the app's own puff shader in `Scripts/puff/`; `Scripts/generate-og.sh` draws the site's link previews, `web/og.png` and `web/og-square.png`, the same way through `Scripts/og/`
