"""Build a looping "breathing glow + rising motes" animation for a lit tower head.

Companion to pulse_anim.py, for the other kind of motion. pulse_anim slides rigid bands
(the Zen Pulsar's slabs); this one leaves the sprite where it is and animates its LIGHT —
the Tome of Focus's spine glow swelling while runes lift off the pages.

Why not `animate_image`, again: fed the native 64px book it produced real motion but let
the gold drain out of the spine by frame 6 and never brought it back, so the loop
flickered bright-dark-bright. Pinning `last_frame_url` to the first frame fixed the loop
exactly (seam 0.00, glow constant) and flattened the motion to a mean frame delta of 1.9
— under the repo's own "motionless" threshold of ~4 (docs/PIXELLAB.md §5b). One knob
traded directly against the other, so neither setting shipped.

    python tools/aura_anim.py <source.png> <outdir> [--motes N] [--rise N] [--seed N]

Source is the resting pose at ART SIZE x2 (64x64 for 32px head art). Install with
sprite_16.halve(im, 32) per frame as head_<id>_frame_N.png.

The loop is exact by construction: every mote's travel is a function of (phase + i/frames)
mod 1, and its alpha is sin(pi*u) so it is invisible at both ends of that trip. Nothing
has to line up by hand and there is no seam frame to tune.
"""
import os
import sys

import numpy as np
from PIL import Image

FRAMES = 9
PULSE = 0.30          # how far ABOVE the resting brightness the glow swells (never below)


def glow_mask(a, tight=True):
    """Opaque pixels that read as the light source rather than as lit material.

    The tight mask has to be genuinely tight: on the Tome, cream parchment also passes a
    naive "warm" test (994 of ~2000 opaque px), so motes would spawn off the whole page
    instead of the spine and the effect would read as static, not as a source.
    """
    op = a[..., 3] > 40
    if tight:
        return op & (a[..., 0] >= 225) & (a[..., 1] >= 130) & (a[..., 1] <= 225) \
            & (a[..., 2] <= 150)
    return op & (a[..., 0] > 150) & (a[..., 0] - a[..., 2] > 55)


def _mote_color(a, glow):
    """Average the source's own glow so tier 2's hotter light gives hotter motes."""
    if not glow.any():
        return np.array([255, 190, 90], dtype=float)
    return np.array([a[..., c][glow].mean() for c in range(3)], dtype=float)


def build(src, outdir, frames=FRAMES, motes=16, rise=16, seed=7, pulse=PULSE):
    im = Image.open(src).convert("RGBA")
    base = np.asarray(im).astype(float)
    w, h = im.size
    tight = glow_mask(base)
    soft = glow_mask(base, tight=False)
    col = _mote_color(base, tight if tight.any() else soft)

    # Motes lift off the TOP edge of the light, not from anywhere inside it — a rune
    # appearing in the middle of a page reads as a speck of dirt, one leaving the spine
    # reads as a rune leaving the spine.
    ys, xs = np.where(tight if tight.any() else soft)
    if ys.size == 0:
        raise ValueError("no glow found in source")
    top_by_col = {}
    for y, x in zip(ys, xs):
        if x not in top_by_col or y < top_by_col[x]:
            top_by_col[x] = y
    spawn = sorted(top_by_col.items())

    rng = np.random.default_rng(seed)
    picks = rng.integers(0, len(spawn), size=motes)
    phases = rng.random(motes)
    sways = rng.uniform(-2.5, 2.5, size=motes)
    # 2px minimum on both axes: sprite_16.halve() averages 2x2 blocks, so a single source
    # pixel survives to 32px as a quarter-strength smudge — invisible in play.
    sizes = [(2, 2) if r < 0.6 else ((3, 2) if r < 0.85 else (2, 3))
             for r in rng.random(motes)]

    os.makedirs(outdir, exist_ok=True)
    out = []
    for i in range(frames):
        t = i / float(frames)
        arr = base.copy()

        # Breathing light. The whole lit body swings, not just the core, so the pages
        # brighten with the spine instead of the spine floating on a dead page.
        #
        # The swing only ever ADDS: a symmetric sin dipped the glow to 0.78x at the
        # trough and the spine visibly flattened for two of nine frames, which reads as
        # the light failing rather than breathing. The authored pose is the floor.
        k = 1.0 + pulse * (0.5 + 0.5 * np.sin(2.0 * np.pi * t))
        for c in range(3):
            arr[..., c] = np.where(soft, np.clip(arr[..., c] * k, 0, 255), arr[..., c])

        for m in range(motes):
            u = (phases[m] + t) % 1.0
            fade = np.sin(np.pi * u)              # 0 at both ends -> seamless wrap
            if fade <= 0.02:
                continue
            x0, y0 = spawn[picks[m]][0], spawn[picks[m]][1]
            mx = int(round(x0 + sways[m] * np.sin(2.0 * np.pi * u)))
            my = int(round(y0 - rise * u))
            mw, mh = sizes[m]
            for dy in range(mh):
                for dx in range(mw):
                    px, py = mx + dx, my + dy
                    if not (0 <= px < w and 0 <= py < h):
                        continue
                    al = 255.0 * fade
                    # Straight alpha-over so a mote crossing the page brightens it rather
                    # than punching a hole in the sprite.
                    src_a = arr[py, px, 3]
                    arr[py, px, :3] = (col * al + arr[py, px, :3] * src_a * (1 - al / 255.0)) \
                        / max(1e-3, al + src_a * (1 - al / 255.0))
                    arr[py, px, 3] = min(255.0, al + src_a * (1 - al / 255.0))

        p = os.path.join(outdir, "frame_%d.png" % (i + 1))
        Image.fromarray(np.clip(arr, 0, 255).astype("uint8"), "RGBA").save(p)
        out.append(p)
    return out


def gild_corners(im, darken=0.78, mark=(255, 196, 92), size=3):
    """Darken the sprite's solid body and stamp metal fittings on its outer corners.

    The tier-2 delta for the Tome. img2img would not do it: four generations off the
    tier-1 book at strengths 170-230 all came back as the same book with no fittings at
    all — a 2x3-pixel structural detail is below what the generator will reliably place,
    while being trivial to put exactly where it belongs in code.

    "Body" is what is neither the light nor the pale page stock — the leather. Its
    left/right/bottom extremes are the three cover corners an open book actually shows in
    this isometric view; the fourth is behind the pages, and stamping it would put a gold
    mark floating in the page gutter.
    """
    a = np.asarray(im.convert("RGBA")).astype(float)
    op = a[..., 3] > 40
    lit = glow_mask(a, tight=False)
    pale = op & (a[..., 0] > 190) & (a[..., 2] > 150)        # parchment
    body = op & ~lit & ~pale
    if not body.any():
        return Image.fromarray(a.astype("uint8"), "RGBA")

    for c in range(3):
        a[..., c] = np.where(body, a[..., c] * darken, a[..., c])

    ys, xs = np.where(body)
    corners = [
        (xs.min(), int(round(ys[xs == xs.min()].mean()))),   # left cover corner
        (xs.max(), int(round(ys[xs == xs.max()].mean()))),   # right cover corner
        (int(round(xs[ys == ys.max()].mean())), ys.max()),   # front corner
    ]
    h_img, w_img = op.shape
    col = np.array(mark, dtype=float)
    for cx, cy in corners:
        for dy in range(-size // 2, size // 2 + 1):
            for dx in range(-size // 2, size // 2 + 1):
                px, py = int(cx) + dx, int(cy) + dy
                if not (0 <= px < w_img and 0 <= py < h_img) or not op[py, px]:
                    continue
                # Only gild the leather: a fitting bleeding onto the page reads as a stain.
                if not body[py, px]:
                    continue
                edge = abs(dx) == size // 2 or abs(dy) == size // 2
                a[py, px, :3] = col if edge else col * 0.7
    return Image.fromarray(np.clip(a, 0, 255).astype("uint8"), "RGBA")


def _draw_motes(arr, marks, col, w, h):
    """Alpha-over a list of (x, y, mw, mh, alpha) marks onto an RGBA float array."""
    for mx, my, mw, mh, fade in marks:
        al = 255.0 * fade
        for dy in range(mh):
            for dx in range(mw):
                px, py = mx + dx, my + dy
                if not (0 <= px < w and 0 <= py < h):
                    continue
                src_a = arr[py, px, 3]
                out_a = al + src_a * (1 - al / 255.0)
                arr[py, px, :3] = (col * al + arr[py, px, :3] * src_a * (1 - al / 255.0)) \
                    / max(1e-3, out_a)
                arr[py, px, 3] = min(255.0, out_a)


def build_orbit(src, outdir, frames=FRAMES, motes=14, lift=3, rx=22, ry=7, seed=11,
                pulse=PULSE, pad=0):
    """A levitating variant: the sprite lifts off its base and runes ORBIT it.

    The orbit is what sells the levitation, and it only reads if it has depth — so each
    rune's ellipse is split. While it is on the far side it is composited UNDER the
    sprite (and dimmed), on the near side OVER it. Drawn as one flat ring instead, the
    runes slide across the book like stickers and the whole thing reads as a decal.

    Loop is exact for the same reason as build(): position is a function of
    (phase + i/frames) mod 1, so frame N wraps onto frame 0 with nothing to tune.
    """
    im = Image.open(src).convert("RGBA")
    if pad:
        # An orbit needs somewhere to BE. The Tome fills ~27 of its 32 art px, so a ring
        # drawn at the sprite's own radius just hugs the silhouette and reads as gold
        # trim, not as runes going around. Growing the CANVAS (not the book) buys the
        # margin: tower.gd draws any head at art size x2 centred, so the drawing stays
        # exactly the size it was and only gains empty room around it.
        grown = Image.new("RGBA", (im.width + pad * 2, im.height + pad * 2), (0, 0, 0, 0))
        grown.alpha_composite(im, (pad, pad))
        im = grown
    base = np.asarray(im).astype(float)
    w, h = im.size
    soft = glow_mask(base, tight=False)
    tight = glow_mask(base)
    col = _mote_color(base, tight if tight.any() else soft)

    # Lift: the book leaves the pedestal. Done here rather than in the source art so the
    # tier-1 and tier-2 sprites stay the same drawing at the same angle — the only note
    # that mattered in the brief.
    lifted = np.zeros_like(base)
    if lift > 0:
        lifted[:-lift] = base[lift:]
    else:
        lifted = base.copy()
    lifted_img_mask = lifted[..., 3] > 40

    ys, xs = np.where(lifted_img_mask)
    cx = (xs.min() + xs.max()) / 2.0
    cy = (ys.min() + ys.max()) / 2.0

    rng = np.random.default_rng(seed)
    phases = rng.random(motes)
    # Spread the runes over a band of orbit radii and heights so it reads as a swarm
    # rather than as one wire hoop.
    rxs = rx * rng.uniform(0.72, 1.12, size=motes)
    rys = ry * rng.uniform(0.65, 1.20, size=motes)
    yoff = rng.uniform(-6.0, 4.0, size=motes)
    sizes = [(2, 2) if r < 0.55 else ((3, 2) if r < 0.8 else (2, 3))
             for r in rng.random(motes)]

    os.makedirs(outdir, exist_ok=True)
    out = []
    for i in range(frames):
        t = i / float(frames)
        back, front = [], []
        for m in range(motes):
            u = (phases[m] + t) % 1.0
            ang = 2.0 * np.pi * u
            mx = int(round(cx + rxs[m] * np.cos(ang)))
            my = int(round(cy + rys[m] * np.sin(ang) + yoff[m]))
            mw, mh = sizes[m]
            # sin(ang) < 0 is the top of the ellipse, which in this isometric view is the
            # far side of the orbit.
            far = np.sin(ang) < 0.0
            (back if far else front).append(
                (mx, my, mw, mh, 0.55 if far else 1.0))

        arr = np.zeros_like(lifted)
        _draw_motes(arr, back, col, w, h)          # far side first, under the sprite
        # Composite the (already lifted) sprite over the far-side runes.
        sa = lifted[..., 3:4] / 255.0
        arr[..., :3] = lifted[..., :3] * sa + arr[..., :3] * (1.0 - sa)
        arr[..., 3] = np.clip(lifted[..., 3] + arr[..., 3] * (1.0 - sa[..., 0]), 0, 255)

        k = 1.0 + pulse * (0.5 + 0.5 * np.sin(2.0 * np.pi * t))
        lifted_soft = np.zeros_like(soft)
        if lift > 0:
            lifted_soft[:-lift] = soft[lift:]
        else:
            lifted_soft = soft
        for c in range(3):
            arr[..., c] = np.where(lifted_soft, np.clip(arr[..., c] * k, 0, 255), arr[..., c])

        _draw_motes(arr, front, col, w, h)         # near side last, over the sprite

        p = os.path.join(outdir, "frame_%d.png" % (i + 1))
        Image.fromarray(np.clip(arr, 0, 255).astype("uint8"), "RGBA").save(p)
        out.append(p)
    return out


def _arg(flag, default):
    return int(sys.argv[sys.argv.index(flag) + 1]) if flag in sys.argv else default


if __name__ == "__main__":
    source, dest = sys.argv[1], sys.argv[2]
    if "--orbit" in sys.argv:
        made = build_orbit(source, dest, motes=_arg("--motes", 14),
                           lift=_arg("--lift", 3), rx=_arg("--rx", 22),
                           ry=_arg("--ry", 7), seed=_arg("--seed", 11),
                           pad=_arg("--pad", 0))
    else:
        made = build(source, dest, motes=_arg("--motes", 16), rise=_arg("--rise", 16),
                     seed=_arg("--seed", 7))
    print("wrote %d frames to %s" % (len(made), dest))
