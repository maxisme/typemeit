#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from the puff shader.
#
# AppIconRender/main.swift shows one frozen frame of PuffView in a black
# window; this script captures it at 2x, places it on the dark icon tile,
# masks the tile to the macOS icon shape and writes every icns size.
# Requires: Xcode command line tools, magick (ImageMagick 7), screen
# recording permission for the terminal (screencapture -l).
#
#   EXPANSION  puff size, 0...1                       (default 1)
#   TIME       instant of the texture                  (default 250)
#   CROP       fraction of the frame kept, centred    (default 0.62)
#   DENSITY    brightness multiplier on the smoke      (default 2.5)
#   PREVIEW=1  write only preview.png next to this script, keep AppIcon.icns
set -euo pipefail

cd "$(dirname "$0")"
OVERLAY="../../Overlay"
OUT="../../Resources/AppIcon.icns"
EXPANSION="${EXPANSION:-1}"
TIME="${TIME:-250}"
POINTS=512                       # window size in points; captured at 2x = 1024 px
TILE=824                         # icon tile on the 1024 canvas, Apple's grid
RADIUS=186                       # corner radius of the tile
BG="#141414"

TMP="$(mktemp -d)"
trap 'pkill -f "$TMP/render" 2>/dev/null || true; [ -n "${KEEP_TMP:-}" ] && echo "Kept $TMP" || rm -rf "$TMP"' EXIT

# Compile the shader to a metallib next to the renderer so ShaderLibrary
# finds it as the default library, then the renderer itself.
xcrun -sdk macosx metal -c "$OVERLAY/Puff.metal" -o "$TMP/Puff.air"
xcrun -sdk macosx metallib "$TMP/Puff.air" -o "$TMP/default.metallib"
xcrun -sdk macosx swiftc -O AppIconRender/main.swift "$OVERLAY/PuffView.swift" -o "$TMP/render"

"$TMP/render" "$EXPANSION" "$TIME" "$POINTS" > "$TMP/render.log" 2>&1 &
for _ in $(seq 1 40); do
  grep -q WINDOW "$TMP/render.log" 2>/dev/null && break
  sleep 0.25
done
WID="$(awk '/WINDOW/ {print $2}' "$TMP/render.log")"
sleep 2.5
screencapture -l"$WID" -o -x "$TMP/frame.png"
pkill -f "$TMP/render" || true

# The frame is the puff on black at 1024 px. Crop to the middle so the puff
# fills the tile, screen it over the tile colour so its black surround
# becomes the tile, then clip to the rounded tile on a transparent canvas.
CROP=$(python3 -c "print(round(1024 * ${CROP:-0.62}))")
# -strip drops the capture's colour profile, which otherwise makes ImageMagick
# treat the grey frame as a grayscale PNG and lose the later compositing.
magick "$TMP/frame.png" -strip -colorspace sRGB -type TrueColor \
  -evaluate Multiply "${DENSITY:-2.5}" \
  -gravity center -crop "${CROP}x${CROP}+0+0" +repage -resize "${TILE}x${TILE}!" \
  \( -size "${TILE}x${TILE}" xc:"$BG" \) -compose Screen -composite "PNG24:$TMP/tile.png"
magick "$TMP/tile.png" -alpha set \
  \( -size "${TILE}x${TILE}" xc:none -fill white -draw "roundrectangle 0,0 $((TILE-1)),$((TILE-1)) $RADIUS,$RADIUS" \) \
  -compose DstIn -composite \
  -compose Over -background none -gravity center -extent 1024x1024 "PNG32:$TMP/icon1024.png"

if [ "${PREVIEW:-0}" = "1" ]; then
  cp "$TMP/icon1024.png" "${PREVIEW_OUT:-preview.png}"
  echo "Wrote $(pwd)/${PREVIEW_OUT:-preview.png}"
  exit 0
fi

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for px in 16 32 128 256 512; do
  magick "$TMP/icon1024.png" -resize "${px}x${px}" "PNG32:$ICONSET/icon_${px}x${px}.png"
  magick "$TMP/icon1024.png" -resize "$((px*2))x$((px*2))" "PNG32:$ICONSET/icon_${px}x${px}@2x.png"
done
iconutil --convert icns --output "$OUT" "$ICONSET"
echo "Wrote $(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
