#!/usr/bin/env bash
# Draws web/og.png, the link preview for typeme.it: one expanded puff in the
# middle of the site's paper with the wordmark under it in DM Mono. Everything
# sits on the centre line because the small Twitter card, WhatsApp and iMessage
# crop the 1.9:1 image to its centre square, and the cloud has to survive that.
# The puff is the app's own shader (web/puff.glsl.js) rendered by headless
# Chrome through Scripts/og/render.html, since a browser is the only thing here
# that can run it. The PNG is 2x (2400 x 1260) so it stays sharp on Retina
# previews; it is mostly flat paper, so lossless is small.
# Requires: Google Chrome, python3, magick.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="web/og.png"
CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; kill $SERVE $CHROME 2>/dev/null || true' EXIT

# x and y are fractions of the image; the rest are the shader's inputs. Trail
# above expansion leaves fragments around the body, the puff mid-growth.
FRAMES='[{"x":0.5,"y":0.44,"size":2500,"exp":0.82,"trail":0.97,"flow":0.6,"time":160,"dens":1.35}]'
Q="$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$FRAMES")"

python3 Scripts/og/serve.py "$TMP" & SERVE=$!
sleep 1
"$CH" --headless=new --use-angle=metal --window-size=2400,1400 --user-data-dir="$TMP/chrome" \
  "http://127.0.0.1:8792/Scripts/og/render.html?name=og&ty=0.83&frames=$Q" >/dev/null 2>&1 & CHROME=$!
for _ in $(seq 1 90); do [ -f "$TMP/og.png" ] && break; sleep 1; done
[ -f "$TMP/og.png" ] || { echo "render did not finish" >&2; exit 1; }
sleep 1
magick "$TMP/og.png" -strip -define png:compression-level=9 "$OUT"
echo "wrote $OUT ($(stat -f %z "$OUT") bytes)"
