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
# brightening from the app toward the folder, rising slightly as they go, each
# smeared a little more than the last.
#
# Note that Finder, not this image, decides the colour of the two icon labels:
# black in Light appearance, white in Dark, with no per-image override. The
# ground is dark, so the labels are legible in Dark and marginal in Light.
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
run("magick","-size",f"{W*2}x{H*2}","gradient:#242426-#141416",f"{T}/acc.png")

# (sprite, centre x, centre y, drawn size, opacity, horizontal smear)
# The last entry reuses p3 rather than adding a fifth frame: by then the smoke
# is diffuse enough that the repeat does not read as one.
for name, cx, cy, sz, op, mb in [("p1", 430, 452, 160, 0.45,  4),
                                 ("p2", 550, 442, 215, 0.65,  6),
                                 ("p3", 670, 428, 275, 0.85,  9),
                                 ("p4", 795, 412, 335, 1.00, 12),
                                 ("p3", 905, 398, 375, 0.88, 16)]:
    s = f"{T}/{name}-{cx}.png"
    run("magick", f"{puffs}/{name}.png", "-trim", "+repage", "-resize", f"{sz}x{sz}",
        "-motion-blur", f"0x{mb}+0", "-channel","A","-evaluate","multiply",op,"+channel", s)
    w, h = ident(s,"%w"), ident(s,"%h")
    run("magick", f"{T}/acc.png", s, "-geometry", f"+{int(cx-w/2)}+{int(cy-h/2)}",
        "-compose","Screen","-composite", f"{T}/n.png")
    shutil.move(f"{T}/n.png", f"{T}/acc.png")

# Grain, laid on after compositing rather than as a filter: the ground is three
# near-blacks a few steps apart, which on an 8-bit panel rings into visible
# contours, and this breaks those up. Kept light -- the smoke carries plenty of
# texture of its own. Generated at 1x and scaled up so the 2x asset shows the
# same size of speck on screen as a 1x one would.
run("magick","-size",f"{W}x{H}","xc:gray50","+noise","Gaussian","-attenuate","0.35",
    "-colorspace","Gray","-resize",f"{W*2}x{H*2}",f"{T}/noise.png")
run("magick",f"{T}/acc.png",f"{T}/noise.png","-compose","Overlay","-composite",f"{T}/rough.png")
# -depth 8 and -strip: the composite lands at 16 bits per channel, which is
# 3.7 MB of background inside every download for no visible gain.
run("magick",f"{T}/acc.png",f"{T}/rough.png","-compose","blend",
    "-define","compose:args=28","-composite","-alpha","off",
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
