#!/usr/bin/env bash
# Draws the link previews for typeme.it:
#   web/og.png         the puff growing from a wisp into a cloud, left to
#                      right across the site's paper, 4800 x 2520, what the
#                      Open Graph and Twitter tags point at
#   web/og-square.png  one cloud, 2400 x 2400, for anywhere a square is
#                      wanted by hand; no tag serves it, platforms crop
#                      og.png to its centre for their square fallbacks
# The puff is the app's own shader (web/puff.glsl.js) rendered by headless
# Chrome through Scripts/og/render.html, since a browser is the only thing here
# that can run it. Both are 4x so the smoke's finest grain survives Retina
# previews; they are mostly flat paper, so lossless stays small.
# Requires: Google Chrome, python3, magick.
set -euo pipefail
cd "$(dirname "$0")/.."
CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SERVE=; CHROME=
TMP="$(mktemp -d)"
trap 'kill $SERVE $CHROME 2>/dev/null; wait $CHROME 2>/dev/null; rm -rf "$TMP"' EXIT

# x and y are fractions of the image; the rest are the shader's inputs. The
# growth is carried by the drawn size, not by expansion: past 0.5 the shader
# spreads the same smoke thin, and the big cloud should stay as dense and
# lobed as the small ones.
FRAMES='[{"x":0.12,"size":1900,"exp":0.3,"flow":0.3,"time":140,"dens":1.5},
         {"x":0.34,"size":2200,"exp":0.5,"trail":0.55,"flow":0.45,"time":150,"dens":1.5},
         {"x":0.58,"size":3100,"exp":0.5,"trail":0.56,"flow":0.5,"time":175,"dens":1.5},
         {"x":0.82,"size":4100,"exp":0.5,"trail":0.58,"flow":0.55,"time":205,"dens":1.5}]'
SQUARE='[{"x":0.5,"y":0.5,"size":4600,"exp":0.5,"trail":0.58,"flow":0.55,"time":205,"dens":1.5}]'
quote() { python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$1"; }

python3 Scripts/og/serve.py "$TMP" & SERVE=$!
sleep 1

# render <name> <w> <h> <frames>: the page posts <name>.png back to $TMP.
# detail=1 is one octave of noise beyond the app's, see render.html.
render() {
  "$CH" --headless=new --use-angle=metal --window-size="$(($2+200)),$(($3+200))" --user-data-dir="$TMP/chrome-$1" \
    "http://127.0.0.1:8792/Scripts/og/render.html?name=$1&w=$2&h=$3&detail=1&frames=$(quote "$4")" >/dev/null 2>&1 & CHROME=$!
  for _ in $(seq 1 180); do [ -f "$TMP/$1.png" ] && break; sleep 1; done
  [ -f "$TMP/$1.png" ] || { echo "render of $1 did not finish" >&2; exit 1; }
  sleep 1; kill $CHROME 2>/dev/null; wait $CHROME 2>/dev/null; CHROME=
  magick "$TMP/$1.png" -strip -define png:compression-level=9 "web/$1.png"
  echo "wrote web/$1.png ($(stat -f %z "web/$1.png") bytes)"
}
render og 4800 2520 "$FRAMES"
render og-square 2400 2400 "$SQUARE"
