#!/usr/bin/env bash
# Draws web/og.png, the link preview for typeme.it: the puff growing from a
# dense wisp into a thin cloud, left to right across the site's paper, with
# the wordmark in DM Mono. Square fallbacks (a long iMessage title, some feed
# thumbnails) crop this to its centre; that is accepted, the landscape is
# what most previews show.
# The puff is the app's own shader (web/puff.glsl.js) rendered by headless
# Chrome through Scripts/og/render.html, since a browser is the only thing here
# that can run it. The PNG is 2x (2400 x 1260) so it stays sharp on Retina
# previews; it is mostly flat paper, so lossless is small.
# Requires: Google Chrome, python3, magick.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="web/og.png"
CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SERVE=; CHROME=
TMP="$(mktemp -d)"
trap 'kill $SERVE $CHROME 2>/dev/null; wait $CHROME 2>/dev/null; rm -rf "$TMP"' EXIT

# x and y are fractions of the image; the rest are the shader's inputs. Density
# eases down as the puff grows, so the wisp reads solid and the cloud as the
# same smoke spread thin.
FRAMES='[{"x":0.12,"size":950,"exp":0.3,"flow":0.3,"time":140,"dens":1.15},
         {"x":0.34,"size":1100,"exp":0.5,"trail":0.55,"flow":0.45,"time":150,"dens":1.1},
         {"x":0.58,"size":1400,"exp":0.72,"trail":0.8,"flow":0.6,"time":160,"dens":1.05},
         {"x":0.82,"size":1600,"exp":0.95,"trail":1.0,"flow":0.75,"time":170,"dens":1.0}]'
Q="$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$FRAMES")"

python3 Scripts/og/serve.py "$TMP" & SERVE=$!
sleep 1
"$CH" --headless=new --use-angle=metal --window-size=2400,1400 --user-data-dir="$TMP/chrome" \
  "http://127.0.0.1:8792/Scripts/og/render.html?name=og&frames=$Q" >/dev/null 2>&1 & CHROME=$!
for _ in $(seq 1 90); do [ -f "$TMP/og.png" ] && break; sleep 1; done
[ -f "$TMP/og.png" ] || { echo "render did not finish" >&2; exit 1; }
sleep 1
magick "$TMP/og.png" -strip -define png:compression-level=9 "$OUT"
echo "wrote $OUT ($(stat -f %z "$OUT") bytes)"
