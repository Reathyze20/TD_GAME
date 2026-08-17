"""Build a charge-and-slam animation for a stacked, glowing-seam tower head.

Why this is code and not a PixelLab call: `animate_image` cannot hold this motion. Fed a
48px Zen Pulsar it redrew the tower as an orange humanoid; fed the native 64px source
with a hand-built end pose pinned as `last_frame_url` it kept the silhouette but still
melted the stone into a yellow blob over the last third. The motion is purely mechanical
— rigid slabs sliding apart, light stretching between them — so it is cheaper and
strictly better to slide the source's OWN pixels than to ask a model to redraw them.
Same principle as build_wall_atlas.py and build_wall_face.py: post-process what the
generator cannot hold steady.

    python tools/pulse_anim.py <source.png> <outdir>          # auto-detect the bands
    python tools/pulse_anim.py <source.png> <outdir> --show   # just print the bands

The source is the resting (slabs closed) pose at ART SIZE x2 — 64x64 for 32px head art.
Install the result with sprite_16.halve(im, 32) per frame, as head_<id>_frame_N.png.

Frame 1 is the closed pose with the core punched white — the slam. Frames 2..N open the
stack step by step. tower.gd's `charge_telegraph` maps the reload onto these frames, so
frame 1 plays on the shot and the last frame is "charged and waiting".
"""
import os
import sys

import numpy as np
from PIL import Image

# Growth per gap, per frame. Explicit steps, NOT an eased float that gets rounded: easing
# then rounding to a pixel silently produced two identical frames mid-charge, a visible
# stutter at tower.gd's HEAD_FPS of 8. Monotonic, with the only hold at peak charge where
# a beat wants one. The ceiling is bounded by headroom — see build().
GROWTH_STEPS = [0, 1, 2, 3, 4, 5, 5]


def _masks(a):
    """Opaque / warm (core light) / cool (crystal) pixel masks."""
    op = a[..., 3] > 40
    warm = op & (a[..., 0] > 130) & (a[..., 0] - a[..., 2] > 50)
    cool = op & (a[..., 2] > 130) & (a[..., 2] - a[..., 0] > 40)
    return op, warm, cool


def detect_bands(im, warm_frac=0.25):
    """Split the sprite into alternating ('art', y0, y1) / ('gap', y0, y1) row bands.

    A 'gap' is a run of rows where the core light dominates — those are the seams that
    stretch when the slabs separate. Everything else is rigid stone that only translates.
    """
    a = np.asarray(im.convert("RGBA")).astype(int)
    op, warm, _ = _masks(a)
    rows = np.where(op.any(axis=1))[0]
    if rows.size == 0:
        raise ValueError("source is fully transparent")
    top, bottom = int(rows[0]), int(rows[-1]) + 1

    is_gap = []
    for y in range(top, bottom):
        n = op[y].sum()
        is_gap.append(n > 0 and warm[y].sum() >= warm_frac * n)

    bands, start = [], top
    for i in range(1, len(is_gap) + 1):
        if i == len(is_gap) or is_gap[i] != is_gap[i - 1]:
            bands.append(("gap" if is_gap[i - 1] else "art", start, top + i))
            start = top + i
    # A gap can only stretch if stone sits on both sides of it; a warm run at either end
    # is part of the silhouette (the lit top face), not a seam.
    while bands and bands[0][0] == "gap":
        bands.pop(0)
    while bands and bands[-1][0] == "gap":
        bands.pop()
    return bands


def frame(im, bands, grow, t, flash=0.0):
    """One frame. `grow` = px each gap opens by, `t` in [0,1] = how charged the light is."""
    w, h = im.size
    heights = [(b - a + (grow if k == "gap" else 0)) for k, a, b in bands]
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    y = bands[-1][2] - sum(heights)          # bottom slab pinned; the stack grows upward
    for (kind, a, b), nh in zip(bands, heights):
        strip = im.crop((0, a, w, b))
        if nh != b - a:
            strip = strip.resize((w, nh), Image.NEAREST)
        if y < 0:                            # ran off the top: clip, never wrap
            canvas.alpha_composite(strip.crop((0, -y, w, nh)), (0, 0))
        else:
            canvas.alpha_composite(strip, (0, y))
        y += nh

    arr = np.asarray(canvas).astype(float)
    op, warm, cool = _masks(arr)
    # Blue climbs fastest, so the core rides orange -> gold -> white-hot as it charges
    # instead of just getting brighter.
    for c, m in ((0, 0.14), (1, 0.26), (2, 0.70)):
        arr[..., c] = np.where(warm, np.clip(arr[..., c] * (1.0 + m * t), 0, 255), arr[..., c])
    for c, m in ((0, 0.20), (1, 0.12), (2, 0.10)):
        arr[..., c] = np.where(cool, np.clip(arr[..., c] * (1.0 + m * t), 0, 255), arr[..., c])
    if flash:
        # Discharge: the core whites out and throws light onto the stone around it.
        for c, m in ((0, 0.18), (1, 0.42), (2, 1.40)):
            arr[..., c] = np.where(warm, np.clip(arr[..., c] * (1.0 + m * flash), 0, 255),
                                   arr[..., c])
        stone = op & ~warm & ~cool
        arr[..., :3] = np.where(stone[..., None],
                                np.clip(arr[..., :3] * (1.0 + 0.30 * flash), 0, 255),
                                arr[..., :3])
    return Image.fromarray(arr.astype("uint8"), "RGBA")


def build(src, outdir, bands=None, steps=None):
    im = Image.open(src).convert("RGBA")
    bands = bands or detect_bands(im)
    steps = list(steps or GROWTH_STEPS)

    # Every gap grows on every step, so at full charge the stack needs gaps * max_step
    # rows of room above it. Overshoot clips the top of the sprite, so clamp — but
    # counting only the EMPTY rows is far too strict: a tapering tip (the Zen Pulsar's
    # crystal) is a handful of pixels per row, and spending those buys motion the sprite
    # would otherwise never show. So the budget is empty rows PLUS the leading rows thin
    # enough that losing them costs nothing readable.
    n_gaps = sum(1 for k, _, _ in bands if k == "gap")
    if n_gaps:
        op = np.asarray(im)[..., 3] > 40
        per_row = op.sum(axis=1)
        thin = max(1, int(0.15 * per_row.max()))
        headroom = bands[0][1]
        for y in range(bands[0][1], bands[-1][2]):
            if per_row[y] > thin:
                break
            headroom += 1
        cap = max(0, headroom // n_gaps)
        if max(steps) > cap:
            print("clamping growth %d -> %d px (%d gaps, %d rows of headroom)"
                  % (max(steps), cap, n_gaps, headroom))
            steps = [min(s, cap) for s in steps]

    os.makedirs(outdir, exist_ok=True)
    out = [os.path.join(outdir, "frame_1.png")]
    frame(im, bands, 0, 0.0, flash=1.0).save(out[0])
    for i, g in enumerate(steps):
        # Light surges late (t^1.6) so the frame that holds its geometry at peak charge
        # still visibly climbs — the core blazes just before the slam.
        t = (i / max(1.0, len(steps) - 1.0)) ** 1.6
        p = os.path.join(outdir, "frame_%d.png" % (i + 2))
        frame(im, bands, g, t).save(p)
        out.append(p)
    return out


if __name__ == "__main__":
    source, dest = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "pulse_out")
    if "--show" in sys.argv:
        for band in detect_bands(Image.open(source)):
            print("%-4s %2d..%2d" % band)
    else:
        made = build(source, dest)
        print("wrote %d frames to %s" % (len(made), dest))
