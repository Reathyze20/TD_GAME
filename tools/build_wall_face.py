"""Turn generated cliff-face strips into the game's wall-face tiles.

Raw generator output cannot be used directly, for the same reasons the wall atlas needs
post-processing (see build_wall_atlas.py):

  * it comes back far too bright and drifted off-palette — measured around 300-400
    sum(RGB) against a wall body median of 144, i.e. the face would have been lighter
    than the surface it hangs from
  * top-lighting is asked for in the prompt but not reliably delivered, and a face lit
    from the bottom reads as glowing rather than as shade
  * nothing makes one tile's left edge agree with another tile's right edge, and every
    cell along a wall picks its own variant

So: reduce x3 to the world raster, force the vertical light ramp, snap to the wall's own
palette, normalise the median against the wall body, and wrap-blend the side columns so
any variant can sit beside any other.

Usage:  python tools/build_wall_face.py <in_dir> [out_dir]
"""
from PIL import Image
from collections import Counter
import glob
import os
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import game_raster                                             # noqa: E402

## Celo zdi je siroke jednu bunku a vysoke FACE_SCREEN_H pixelu OBRAZOVKY. Vyska je
## vytvarne rozhodnuti (Game.WALL_FACE_H), ne nasobek bunky -- pri zjemneni rastru se
## zed na obrazovce nesmi zmensit, takze se drzi v pixelech obrazovky a na art se
## prepocita az tady.
FACE_SCREEN_H = 24
ZOOM = game_raster.SCALE
ART_W, ART_H = game_raster.ART_PX, FACE_SCREEN_H // ZOOM

## Fraction of the wall body's median brightness the face should sit at. The face is a
## vertical surface under a top light, so it must be clearly darker than the wall's top
## (144) while staying clearly lighter than the floor (77) — otherwise the wall reads as
## floating on a dark band rather than standing on the ground.
FACE_LEVEL = 0.88

## Multiplier down the face, applied below the lip. The foot sits in its own shade.
LIGHT_TOP, LIGHT_BOTTOM = 1.10, 0.72

## The lit edge where the top surface rolls over into the face is PAINTED, not taken from
## the generator — the same reasoning as repainting the wall atlas rim from its alpha.
## Left to the generator it lands wherever the texture happened to be bright: one variant
## snapped to the atlas rim colour (sum 396) across its whole width and read as a neon
## strip, another put its light at the foot and looked lit from below. A fixed multiple of
## the face median gives every variant the same crisp fold and keeps it in the ramp.
LIP_LEVEL = 1.55

BLEND_COLS = 2             # side columns cross-faded so any tile abuts any other


def wall_palette_and_median(atlas_path):
    """The wall's own colours and brightness, so the face cannot introduce a new material."""
    im = Image.open(atlas_path).convert("RGBA")
    px = im.load()
    t = im.width // 4
    variants = im.height // (t * 4)
    pal, vals = [], []
    for v in range(variants):
        for y in range(3 * t, 4 * t):          # slot 15 = solid interior
            for x in range(3 * t, 4 * t):
                p = px[x, v * t * 4 + y]
                if p[3] > 128:
                    pal.append(p[:3])
                    vals.append(sum(p[:3]))
    return pal, statistics.median(vals)


def nearest(c, pal):
    return min(pal, key=lambda p: (p[0]-c[0])**2 + (p[1]-c[1])**2 + (p[2]-c[2])**2)


def light_ramp(im):
    """Force top-lighting on rows below the lip, whatever the generator produced."""
    px = im.load()
    for y in range(1, im.height):
        t = (y - 1) / float(im.height - 2)
        k = LIGHT_TOP + (LIGHT_BOTTOM - LIGHT_TOP) * t
        for x in range(im.width):
            r, g, b, a = px[x, y]
            px[x, y] = (min(255, int(r*k)), min(255, int(g*k)), min(255, int(b*k)), a)
    return im


def paint_lip(im, pal, target_med):
    """Replace the top row with a single lit edge colour from the wall's own palette."""
    want = target_med * LIP_LEVEL
    lip = min(pal, key=lambda p: abs(sum(p) - want))
    px = im.load()
    for x in range(im.width):
        px[x, 0] = lip + (255,)
    return im


def wrap_blend(im):
    """Cross-fade the outer columns with the opposite edge.

    Every cell along a wall rolls its own variant, so tile boundaries are everywhere. If
    each tile is made to meet ITSELF cleanly, then any tile also meets any other cleanly,
    because they all converge on the same edge colours.
    """
    px = im.load()
    for i in range(BLEND_COLS):
        w = (i + 1) / float(BLEND_COLS + 1)     # 0 at the very edge, ->0.5 inward
        for y in range(im.height):
            left = px[i, y]
            right = px[im.width - 1 - i, y]
            mix = tuple(int(left[k] * w + right[k] * (1.0 - w)) for k in range(3))
            px[i, y] = mix + (left[3],)
            px[im.width - 1 - i, y] = mix + (right[3],)
    return im


def build(src, pal, target_med):
    im = Image.open(src).convert("RGBA")
    im = im.resize((ART_W, ART_H), Image.BOX)
    im = light_ramp(im)

    px = im.load()
    vals = [sum(px[x, y][:3]) for y in range(ART_H) for x in range(ART_W)]
    med = statistics.median(vals) or 1
    k = target_med / med
    for y in range(ART_H):
        for x in range(ART_W):
            r, g, b, a = px[x, y]
            snapped = nearest((min(255, int(r*k)), min(255, int(g*k)), min(255, int(b*k))), pal)
            px[x, y] = snapped + (255,)
    im = paint_lip(im, pal, target_med)
    return wrap_blend(im)


if __name__ == "__main__":
    in_dir = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.path.dirname(__file__), "..", "assets", "terrain", "face")
    atlas = os.path.join(os.path.dirname(__file__), "..", "assets", "terrain",
                         "high_ground_atlas.png")
    os.makedirs(out_dir, exist_ok=True)
    pal, body_med = wall_palette_and_median(atlas)
    target = body_med * FACE_LEVEL
    print("wall body median %.0f -> face target %.0f (%d palette colours)"
          % (body_med, target, len(set(pal))))
    for i, p in enumerate(sorted(glob.glob(os.path.join(in_dir, "*.png")))):
        out = build(p, pal, target)
        dst = os.path.join(out_dir, "face_%02d.png" % i)
        out.save(dst)
        px = out.load()
        vals = [sum(px[x, y][:3]) for y in range(ART_H) for x in range(ART_W)]
        print("%s -> %s  median %.0f  top row %.0f  bottom row %.0f"
              % (os.path.basename(p), os.path.basename(dst), statistics.median(vals),
                 statistics.median([sum(px[x, 0][:3]) for x in range(ART_W)]),
                 statistics.median([sum(px[x, ART_H-1][:3]) for x in range(ART_W)])))
