#!/usr/bin/env bash
# Regenerates the site favicons from the menu bar puff,
# TypeMeIt/Support/Icon/puff.svg. Requires rsvg-convert, magick, python3.
#
# favicon.svg      follows the browser's colour scheme (Chrome, Firefox)
# favicon.ico      16/32/48, dark ink, for Safari and everything older
# favicon-32.png   same, for tooling that wants a PNG
# apple-touch-icon light puff on dark paper; iOS fills transparency with black
# icon-512.png     dark ink, for link previews and manifests
set -euo pipefail
cd "$(dirname "$0")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 - "$TMP" <<'PY'
import re, sys
tmp = sys.argv[1]
src = open('../TypeMeIt/Support/Icon/puff.svg').read()
outline, *arcs = re.findall(r'<path d="([^"]+)"/>', src)
# The stroke-3 artwork spans 10.6..54.3 x 8.5..54.4 in the 64 viewBox; a
# 52-unit square centred on it leaves room for the heavier stroke.
svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="6.4 5.4 52 52" fill="none" stroke="#0a0a0a" stroke-width="5" stroke-linecap="round" stroke-linejoin="round">
  <!-- The menu bar puff from TypeMeIt/Support/Icon/puff.svg, stroked heavier
       so it survives 16 px. Follows the tab bar's colour scheme in browsers
       that render SVG favicons; the PNG and ICO cover the rest. -->
  <style>@media (prefers-color-scheme: dark) { svg { stroke: #fafafa; } }</style>
''' + ''.join(f'  <path d="{p}"/>\n' for p in [outline, *arcs]) + '</svg>\n'
open('favicon.svg', 'w').write(svg)
open(f'{tmp}/dark.svg', 'w').write(svg.replace('<style>', '<style>svg{stroke:#0a0a0a !important}'))
open(f'{tmp}/light.svg', 'w').write(svg.replace('<style>', '<style>svg{stroke:#fafafa !important}'))
PY

for s in 16 32 48; do rsvg-convert -w $s -h $s "$TMP/dark.svg" -o "$TMP/$s.png"; done
magick "$TMP/16.png" "$TMP/32.png" "$TMP/48.png" favicon.ico
cp "$TMP/32.png" favicon-32.png
rsvg-convert -w 512 -h 512 "$TMP/dark.svg" -o icon-512.png
rsvg-convert -w 1024 -h 1024 -b '#0b0b0b' "$TMP/light.svg" -o "$TMP/touch.png"
magick "$TMP/touch.png" -resize 180x180 apple-touch-icon.png
echo "Wrote favicon.svg favicon.ico favicon-32.png icon-512.png apple-touch-icon.png"
