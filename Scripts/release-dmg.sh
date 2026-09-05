#!/bin/bash
# The direct-download channel: a Developer ID app, notarized, in a stapled DMG,
# with a signed Sparkle appcast pointing at it.
#
#   Scripts/release-dmg.sh
#
# Requires DEVELOPMENT_TEAM, and ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH for
# notarization. MARKETING_VERSION overrides the version in project.yml -- CI sets
# it from the tag. SPARKLE_ED_PRIVATE_KEY signs the appcast on a machine with no
# login Keychain; locally the key is read from the Keychain instead.
set -euo pipefail

cd "$(dirname "$0")/.."
: "${DEVELOPMENT_TEAM:?set DEVELOPMENT_TEAM}"
: "${ASC_KEY_ID:?set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
: "${ASC_KEY_PATH:?set ASC_KEY_PATH}"

IDENTITY="Developer ID Application: Max Mitchell (Z28DW76Y3W)"
BUILD="$PWD/build"
DERIVED="$BUILD/DerivedData"
ARCHIVE="$BUILD/TypeMeIt.xcarchive"
APP="$BUILD/export/TypeMeIt.app"

# Always moves forward, so it outranks every earlier build with no shared-state
# lookup. A commit count does not survive re-running the same commit.
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"

# /bin/bash on macOS is 3.2, where `"${arr[@]}"` on an empty array trips `set -u`.
VERSION_ARG=()
if [ -n "${MARKETING_VERSION:-}" ]; then
  VERSION_ARG=("MARKETING_VERSION=$MARKETING_VERSION")
fi

rm -rf "$BUILD/export" "$ARCHIVE"
mkdir -p "$BUILD"
xcodegen generate

cat > "$BUILD/ExportOptions-developer-id.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>teamID</key>
  <string>${DEVELOPMENT_TEAM}</string>
  <key>signingStyle</key>
  <string>automatic</string>
</dict>
</plist>
PLIST

# -derivedDataPath is not a tidiness flag: Sparkle's tools ship as an SPM binary
# artifact, and this is what puts them at a known path below.
xcodebuild archive \
  -project TypeMeIt.xcodeproj \
  -scheme TypeMeIt \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  ${VERSION_ARG[@]+"${VERSION_ARG[@]}"}

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$BUILD/ExportOptions-developer-id.plist" \
  -exportPath "$BUILD/export" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

VERSION="${MARKETING_VERSION:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")}"

# Unversioned on purpose: the website links to
# /releases/latest/download/TypeMeIt.dmg, which only resolves if the asset name
# is the same every release. The version is in the appcast entry and in the
# app's Info.plist, and each release's asset URL carries its own tag, so Sparkle
# still sees a distinct URL per update.
DMG="$BUILD/TypeMeIt.dmg"

# Notarization round-trips to Apple and takes minutes, so a binary that can never
# pass fails here instead -- locally, in a second, naming the reason.
info="$(codesign -dvv "$APP" 2>&1)"
grep -q "Developer ID Application" <<<"$info" || { echo "not signed with a Developer ID certificate:"; echo "$info"; exit 1; }
grep -q "Timestamp=" <<<"$info" || { echo "no secure timestamp; notarization rejects that"; exit 1; }
grep -q "flags=0x10000(runtime)" <<<"$info" || { echo "hardened runtime is not enabled"; exit 1; }
# --deep here is *verification*, which is fine; what Quinn warns against is
# `codesign --deep` to *sign*, which this script never does.
codesign --verify --deep --strict --verbose=2 "$APP"

notarize() { # file
  xcrun notarytool submit "$1" \
    --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" \
    --wait
}

# Round 1: notarize the .app so its ticket is stapled into the bundle itself.
# Stapling only the DMG is not enough -- once the app is dragged to /Applications
# it carries no ticket, so an offline Mac that has never seen it has nothing
# local to verify against.
ditto -c -k --keepParent "$APP" "$BUILD/TypeMeIt.zip"
notarize "$BUILD/TypeMeIt.zip"
xcrun stapler staple "$APP"
rm -f "$BUILD/TypeMeIt.zip"

STAGE="$BUILD/dmg-stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/TypeMeIt.app"
ln -s /Applications "$STAGE/Applications"
if [ -f Scripts/dmg-background.png ]; then
  mkdir -p "$STAGE/.background"
  cp Scripts/dmg-background.png "$STAGE/.background/background.png"
fi

# Two passes: Finder stores the window layout in the volume's .DS_Store and a
# UDZO image is read-only, so lay out a UDRW image first, then convert. Laying
# it out after compression looks like it works and silently produces a default
# window.
RW="$BUILD/TypeMeIt-rw.dmg"
MNT="/Volumes/Type Me It"
rm -f "$RW"
hdiutil create -volname "Type Me It" -srcfolder "$STAGE" -ov -format UDRW "$RW"
hdiutil attach "$RW" -nobrowse -mountpoint "$MNT"
osascript Scripts/dmg-layout.applescript "Type Me It"
sync
# Finder is still writing the .DS_Store the layout just arranged, and a detach
# that races it fails with "Resource busy". Patience first; -force is a last
# resort, because a forced eject mid-write is how a half-saved layout ships.
detached=""
for _ in 1 2 3 4 5; do
  if hdiutil detach "$MNT"; then detached=yes; break; fi
  sleep 3
done
[ -n "$detached" ] || hdiutil detach "$MNT" -force
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG"
rm -f "$RW"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

# Round 2 covers the DMG the user actually downloads.
notarize "$DMG"
xcrun stapler staple "$DMG"

# `spctl` asks Apple and reports "accepted" even when no ticket is stapled;
# `syspolicy_check distribution` is the offline-truthful check.
xcrun stapler validate "$DMG"
VERIFY="$BUILD/verify-mnt"
rm -rf "$VERIFY"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$VERIFY"
result="$(syspolicy_check distribution "$VERIFY/TypeMeIt.app" 2>&1 || true)"
hdiutil detach "$VERIFY"
echo "$result"
if grep -q "failed one or more" <<<"$result"; then
  echo "app failed pre-distribution checks"
  exit 1
fi

# The stapled DMG serves both first install and Sparkle updates, so there is one
# artifact to publish and one thing to get right. generate_appcast writes one
# entry per DMG it finds, so the directory is emptied first: a second local build
# would otherwise publish an appcast describing both.
UPDATES="$BUILD/updates"
rm -rf "$UPDATES"
mkdir -p "$UPDATES"
cp "$DMG" "$UPDATES"

GENERATE_APPCAST="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
[ -x "$GENERATE_APPCAST" ] || { echo "Sparkle's generate_appcast is missing from $DERIVED"; exit 1; }

# Release assets live under the tag, not under `latest`, so the prefix carries
# the tag being published. Only the appcast itself is fetched through
# /releases/latest/download.
TAG="${RELEASE_TAG:-v$VERSION}"
PREFIX="https://github.com/maxisme/typemeit/releases/download/$TAG/"

if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
  # CI has no login Keychain to read the key from. `--ed-key-file -` takes it on
  # stdin, so the secret is never written to the runner's disk.
  printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$GENERATE_APPCAST" --ed-key-file - \
    --download-url-prefix "$PREFIX" "$UPDATES"
else
  # The key is held under the "typemeit" account -- deliberately not the default
  # account, which holds a different app's key.
  "$GENERATE_APPCAST" --account typemeit --download-url-prefix "$PREFIX" "$UPDATES"
fi

[ -f "$UPDATES/appcast.xml" ] || { echo "generate_appcast produced no appcast.xml"; exit 1; }

echo "==> $DMG"
echo "==> $UPDATES/appcast.xml"
