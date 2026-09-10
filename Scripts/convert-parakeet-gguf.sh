#!/bin/sh
# Convert an NVIDIA NeMo checkpoint to the GGUF the app loads, and print the
# constants ModelStore.swift needs for it.
#
# This is what handy-computer runs to publish their GGUFs: transcribe.cpp's own
# converter reads NVIDIA's checkpoint directly, and its quantize tool produces
# the smaller file from the F32 reference. Doing it here rather than downloading
# their build means a new NVIDIA model can ship the day it lands instead of
# whenever it gets quantised upstream.
#
# The converter is pinned to the same transcribe.cpp release the app links, so
# the GGUF can never be built by a version of the code that cannot read it.
#
#   Scripts/convert-parakeet-gguf.sh [model-id] [quant]
#
# Needs uv, cmake and git. It downloads NeMo and torch on first run (a few GB,
# cached by uv afterwards) and writes ~4GB of intermediates. CPU only -- this is
# a format conversion, not training.

set -eu

MODEL="${1:-nvidia/parakeet-unified-en-0.6b}"
QUANT="${2:-Q8_0}"
SLUG="${MODEL##*/}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK="${PARAKEET_WORK_DIR:-$ROOT/build/parakeet-convert}"

for tool in uv cmake git; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "$tool is not installed" >&2
        exit 1
    }
done

# Whatever xcframework the app links, built from the same tag.
VERSION=$(sed -n 's|.*releases/download/\(v[^/]*\)/.*|\1|p' "$ROOT/Packages/TranscribeCpp/Package.swift")
[ -n "$VERSION" ] || {
    echo "no transcribe.cpp release found in Packages/TranscribeCpp/Package.swift" >&2
    exit 1
}
echo "==> transcribe.cpp $VERSION, converting $MODEL to $QUANT"

if [ ! -d "$WORK/.git" ]; then
    mkdir -p "$(dirname "$WORK")"
    git clone --depth 1 --branch "$VERSION" \
        https://github.com/handy-computer/transcribe.cpp.git "$WORK"
else
    git -C "$WORK" fetch --depth 1 origin tag "$VERSION"
    git -C "$WORK" checkout --quiet "$VERSION"
fi

echo "==> building the quantize tool"
cmake -S "$WORK" -B "$WORK/build" -DTRANSCRIBE_BUILD_TOOLS=ON >/dev/null
cmake --build "$WORK/build" --target transcribe-quantize >/dev/null

REFERENCE="$WORK/models/$SLUG/$SLUG-F32.gguf"
if [ -f "$REFERENCE" ]; then
    echo "==> reusing $REFERENCE"
else
    echo "==> converting the checkpoint (slow on the first run: NeMo and torch)"
    (cd "$WORK" && uv run --project scripts/envs/parakeet scripts/convert-parakeet.py "$MODEL")
    [ -f "$REFERENCE" ] || {
        echo "the converter did not write $REFERENCE" >&2
        exit 1
    }
fi

OUTPUT="$WORK/models/$SLUG/$SLUG-$QUANT.gguf"
echo "==> quantizing to $QUANT"
"$WORK/build/bin/transcribe-quantize" "$REFERENCE" "$OUTPUT" --quant "$QUANT" >/dev/null

BYTES=$(wc -c < "$OUTPUT" | tr -d ' ')
SHA=$(shasum -a 256 "$OUTPUT" | cut -d' ' -f1)

cat <<EOF

$OUTPUT

ModelStore.swift wants:

    nonisolated static let fileName = "$SLUG-$QUANT.gguf"
    nonisolated static let expectedBytes: Int64 = $BYTES
    nonisolated static let sha256 = "$SHA"

downloadURL has to point at wherever this file gets hosted; the app downloads
it at runtime and will not build it.
EOF
