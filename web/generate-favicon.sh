#!/usr/bin/env bash
# Regenerates the site favicons from the menu bar puff,
# TypeMeIt/Support/Icon/puff.svg. Requires rsvg-convert, magick, python3.
#
# favicon.svg      source stroke; follows the browser's colour scheme (Chrome, Firefox)
# favicon.ico      16/32 stroked heavier so the arcs survive, 48 at source stroke; dark ink
# favicon-32.png   the heavy 32, for tooling that wants a PNG
# apple-touch-icon light ink on the site's paper; iOS fills transparency with black
# icon-512.png     dark ink, source stroke, for link previews and manifests
set -euo pipefail
cd "$(dirname "$0")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 - "$TMP" <<'PY'
import re, sys
tmp = sys.argv[1]
src = open('../TypeMeIt/Support/Icon/puff.svg').read()
paths = re.findall(r'<path d="([^"]+)"/>', src)
# The artwork spans 10.6..54.3 x 8.5..54.4 in the 64 viewBox; a 60-unit
# square centred on it leaves a margin of about an eighth on every side, so the
# puff sits clear of the rounded frames Slack, iOS and tab strips draw around it.
def svg(width, style=''):
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="2.45 1.45 60 60" fill="none" stroke="#0a0a0a" '
            f'stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round">\n'
            '  <!-- The menu bar puff from TypeMeIt/Support/Icon/puff.svg. Follows the tab\n'
            '       bar\'s colour scheme in browsers that render SVG favicons; the PNG and\n'
            '       ICO cover the rest. -->\n'
            f'  <style>{style}@media (prefers-color-scheme: dark) {{ svg {{ stroke: #fafafa; }} }}</style>\n'
            + ''.join(f'  <path d="{p}"/>\n' for p in paths) + '</svg>\n')
open('favicon.svg', 'w').write(svg(3))
dark = 'svg{stroke:#0a0a0a !important}'
light = 'svg{stroke:#f0f0f0 !important}'
open(f'{tmp}/thin.svg', 'w').write(svg(3, dark))
open(f'{tmp}/thick.svg', 'w').write(svg(5, dark))
open(f'{tmp}/touch.svg', 'w').write(svg(3, light))
PY

rsvg-convert -w 16 -h 16 "$TMP/thick.svg" -o "$TMP/16.png"
rsvg-convert -w 32 -h 32 "$TMP/thick.svg" -o "$TMP/32.png"
rsvg-convert -w 48 -h 48 "$TMP/thin.svg" -o "$TMP/48.png"
magick "$TMP/16.png" "$TMP/32.png" "$TMP/48.png" favicon.ico
cp "$TMP/32.png" favicon-32.png
rsvg-convert -w 512 -h 512 "$TMP/thin.svg" -o icon-512.png
rsvg-convert -w 180 -h 180 -b '#0e0e0e' "$TMP/touch.svg" -o apple-touch-icon.png
echo "Wrote favicon.svg favicon.ico favicon-32.png icon-512.png apple-touch-icon.png"
