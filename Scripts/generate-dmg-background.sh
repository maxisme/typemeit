#!/usr/bin/env bash
# Draws the background of the disk image the app ships in.
# Requires: magick (ImageMagick 7).
#
# The window this sits behind is 660 x 410 of content, and Finder draws the two
# icons on top of it at the positions declared below. They are repeated in
# Scripts/dmg-layout.applescript, which is what actually places them -- smoke
# drawn here at coordinates the layout script does not share streams at nothing.
# Change both together.
#
# No mark and no words on it: the app's own icon is already the largest thing in
# the window, and the folder beside it says where the app goes. The direction of
# the drag is carried by the smoke instead of by an arrow -- puffs growing and
# darkening from the app toward the folder, rising slightly as they go, each
# smeared a little more than the last.
#
# Note that Finder, not this image, decides the colour of the two icon labels:
# black in Light appearance, white in Dark, with no per-image override. The
# ground is white, so the labels read in Light and wash out in Dark.
#
# The puffs in Scripts/puff are frames of the app's own shader, not stock smoke
# -- see Scripts/puff/serve.py for how they are regenerated.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="Scripts/dmg-background.png"
PUFFS="Scripts/puff"

W=660
H=410
ICON_Y=214       # centre of both Finder icons, in window points
APP_X=170
FOLDER_X=490

python3 - "$PUFFS" "$OUT" "$W" "$H" <<'PY'
import subprocess, sys, tempfile, shutil, os
puffs, out, W, H = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
T = tempfile.mkdtemp()
run = lambda *a: subprocess.run([str(x) for x in a], check=True)
ident = lambda f, fmt: int(subprocess.run(["magick","identify","-format",fmt,f],
                                          capture_output=True, text=True).stdout)

# Everything below is in 2x pixels: the asset is drawn at twice the window size.
run("magick","-size",f"{W*2}x{H*2}","gradient:#FFFFFF-#F2F2F4",f"{T}/acc.png")

# (sprite, centre x, centre y, drawn size, opacity, horizontal smear)
# Every cy is the icon row: the plume sits on the same line as the two icons
# rather than drifting above it. The mass is largest and densest at the app and
# tapers toward the folder -- smoke leaving the app and thinning as it travels --
# with the smear growing as it goes, so the direction reads from the taper.
for name, cx, cy, sz, op, mb in [("p4", 500, 428, 360, 0.95,  6),
                                 ("p3", 622, 428, 300, 0.78,  9),
                                 ("p2", 730, 428, 238, 0.60, 13),
                                 ("p1", 828, 428, 184, 0.44, 18),
                                 ("p1", 908, 428, 140, 0.30, 23)]:
    s = f"{T}/{name}-{cx}.png"
    # The shader draws white smoke on transparent. Negating the colour channels
    # and leaving alpha alone turns it into black smoke of the same shape, which
    # then composites straight over the white ground.
    run("magick", f"{puffs}/{name}.png", "-trim", "+repage", "-resize", f"{sz}x{sz}",
        "-motion-blur", f"0x{mb}+0", "-channel","RGB","-negate","+channel",
        "-channel","A","-evaluate","multiply",op,"+channel", s)
    w, h = ident(s,"%w"), ident(s,"%h")
    run("magick", f"{T}/acc.png", s, "-geometry", f"+{int(cx-w/2)}+{int(cy-h/2)}",
        "-compose","Over","-composite", f"{T}/n.png")
    shutil.move(f"{T}/n.png", f"{T}/acc.png")

# Grain, laid on after compositing rather than as a filter, to break up the
# banding a near-flat ramp rings into on an 8-bit panel. Very light: on a white
# ground grain reads as dirt, and the smoke carries plenty of texture of its own.
# Generated at 1x and scaled up so the 2x asset shows the same size of speck on
# screen as a 1x one would.
run("magick","-size",f"{W}x{H}","xc:gray50","+noise","Gaussian","-attenuate","0.22",
    "-colorspace","Gray","-resize",f"{W*2}x{H*2}",f"{T}/noise.png")
run("magick",f"{T}/acc.png",f"{T}/noise.png","-compose","Overlay","-composite",f"{T}/rough.png")
# -depth 8 and -strip: the composite lands at 16 bits per channel, which is
# 3.7 MB of background inside every download for no visible gain.
run("magick",f"{T}/acc.png",f"{T}/rough.png","-compose","blend",
    "-define","compose:args=18","-composite","-alpha","off",
    "-depth","8","-strip", out)

# A .DS_Store holds a single background file and Finder sizes it by its stored
# resolution, so 144 dpi is how a 1320 x 820 image comes out as a 660 x 410
# window that is sharp on a Retina display. Shipping the 1x file instead is
# legible but visibly soft.
run("magick", out, "-density","144","-units","PixelsPerInch", out)
shutil.rmtree(T)
PY

echo "wrote $OUT -- 2x pixels, 144 dpi, presents as ${W}x${H}"
echo "icon centres: app ($APP_X, $ICON_Y)  Applications ($FOLDER_X, $ICON_Y)"
echo "keep those in step with Scripts/dmg-layout.applescript"
