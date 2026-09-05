#!/usr/bin/env bash
# Regenerates the menu bar glyph from puff.svg into two asset catalog layers,
# menu_puff (the outline) and menu_puff_arcs (the inner arcs), which
# MenuBarIcon.swift tints and composes at run time, plus menu_puff_dashed,
# the outline drawn dashed, which the dev build wears instead.
# Requires: rsvg-convert (librsvg), magick (ImageMagick 7), python3.
#
# Both layers are cropped by the same box, measured from the whole drawing, so
# stacking one on the other puts the arcs exactly where the artwork puts them.
# The glyph is trimmed and re-centred at GLYPH_PT tall in a SLOT_PT square:
# Bluetooth and the battery run 15-16 pt in the same 20 pt slot.
set -euo pipefail

cd "$(dirname "$0")"
ASSETS="../../Resources/Assets.xcassets"
OUT_OUTLINE="$ASSETS/menu_puff.imageset/outline.png"
OUT_ARCS="$ASSETS/menu_puff_arcs.imageset/arcs.png"
OUT_DASHED="$ASSETS/menu_puff_dashed.imageset/dashed.png"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

CANVAS=102     # pixels, drawn by MenuBarIcon.swift into a SLOT_PT square
SLOT_PT=20
GLYPH_PT=16

# One SVG per layer, in the master's viewBox, so the crop box fits both.
python3 - puff.svg "$TMP" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
tmp = sys.argv[2]
head = src[:src.index("<g ")]
groups = dict(re.findall(r'<g id="([a-z]+)">(.*?)</g>', src, re.S))
for name, body in groups.items():
    open(f"{tmp}/{name}.svg", "w").write(head + body + "</svg>\n")
dashed = head.replace('stroke-linecap="round"', 'stroke-linecap="butt" stroke-dasharray="5 3.2"')
open(f"{tmp}/dashed.svg", "w").write(dashed + groups["outline"] + "</svg>\n")
PY

GLYPH_PX=$(python3 -c "print(round($CANVAS * $GLYPH_PT / $SLOT_PT))")

# Rendered oversized so the trim lands on solid pixels rather than the SVG's
# antialiased fringe, then scaled down to the height the bar wants.
rsvg-convert -w 1024 -h 1024 puff.svg -o "$TMP/full.png"
rsvg-convert -w 1024 -h 1024 "$TMP/outline.svg" -o "$TMP/outline.png"
rsvg-convert -w 1024 -h 1024 "$TMP/arcs.svg" -o "$TMP/arcs.png"
rsvg-convert -w 1024 -h 1024 "$TMP/dashed.svg" -o "$TMP/dashed.png"

BOX="$(magick "$TMP/full.png" -format "%@" info:)"

mkdir -p "$(dirname "$OUT_OUTLINE")" "$(dirname "$OUT_ARCS")" "$(dirname "$OUT_DASHED")"
for pair in "outline.png:$OUT_OUTLINE" "arcs.png:$OUT_ARCS" "dashed.png:$OUT_DASHED"; do
  # PNG32 explicitly: a single black shape on empty space would otherwise be
  # written as opaque greyscale and draw as a filled square.
  magick "$TMP/${pair%%:*}" -crop "$BOX" +repage -resize "x$GLYPH_PX" \
    -background none -gravity center -extent "${CANVAS}x${CANVAS}" \
    "PNG32:${pair#*:}"
done

for dir in "$(dirname "$OUT_OUTLINE")" "$(dirname "$OUT_ARCS")" "$(dirname "$OUT_DASHED")"; do
  file="$(ls "$dir"/*.png | xargs -n1 basename)"
  cat > "$dir/Contents.json" <<JSON
{
  "images" : [
    { "filename" : "$file", "idiom" : "universal", "scale" : "1x" },
    { "idiom" : "universal", "scale" : "2x" },
    { "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
done

echo "Wrote $(cd "$(dirname "$OUT_OUTLINE")" && pwd)/$(basename "$OUT_OUTLINE")"
echo "Wrote $(cd "$(dirname "$OUT_ARCS")" && pwd)/$(basename "$OUT_ARCS")"
echo "Wrote $(cd "$(dirname "$OUT_DASHED")" && pwd)/$(basename "$OUT_DASHED")"
