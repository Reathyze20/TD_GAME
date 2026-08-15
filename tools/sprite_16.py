"""Turn a generated 64px creature sheet into the 16px frames the game draws.

Why this exists as a tool and not as a one-off: every enemy in the game is 16x16 art
scaled x2, PixelLab cannot generate below 32x32, and *no* resampling filter produces a
usable 16px creature from a 64px one. That combination is permanent, so the translation
step is permanent too.

What goes wrong with the obvious approaches, all of it measured on the notification
creature:

  NEAREST  samples one arbitrary pixel per block, so whether the sprite ends up with an
           eye is luck
  BOX      keeps the silhouette and averages every feature into the body — the glowing
           eye smears across the whole head
  mode     picks the commonest colour per block, which deletes the eye outright: in its
           own 2x2 block the eye is a minority

So the 16px frame is *authored* instead: read the silhouette, build a ramp from the
reference's own fur, then place the accent deliberately. A 16x16 creature has room for a
shape, four value steps and exactly one bright mark — and which pixel is that mark is a
judgement no filter can make.

Both the ramp and the accent colour are computed once per animation from a single
reference frame and reused for every frame. Recomputed per frame, the body repaints
itself and the eye strobes as the creature walks.

Usage:
    python tools/sprite_16.py <frames_dir> <out_dir> <base_id> [--variant _b] [--death]
"""
from PIL import Image
from collections import Counter
import colorsys
import os
import sys

TARGET = 16


# --------------------------------------------------------------------- basics

def lum(p):
    return 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]


def hsv(p):
    return colorsys.rgb_to_hsv(p[0] / 255.0, p[1] / 255.0, p[2] / 255.0)


def salience(p):
    s, v = hsv(p)[1], hsv(p)[2]
    return s * v


# ------------------------------------------------------------ the bright mark

def _components(mask, w, h):
    seen = [False] * (w * h)
    out = []
    for start in range(w * h):
        if not mask[start] or seen[start]:
            continue
        stack, cells = [start], []
        seen[start] = True
        while stack:
            i = stack.pop()
            cells.append(i)
            x, y = i % w, i // w
            for nx, ny in ((x-1, y), (x+1, y), (x, y-1), (x, y+1), (x-1, y-1),
                           (x+1, y-1), (x-1, y+1), (x+1, y+1)):
                if 0 <= nx < w and 0 <= ny < h:
                    j = ny * w + nx
                    if mask[j] and not seen[j]:
                        seen[j] = True
                        stack.append(j)
        out.append(cells)
    return out


def find_accent(im, signature=(0.80, 0.06)):
    """The compact vivid blob — the eye, the screen, whatever the creature leads with.

    Vividness alone is not enough to find it. These creatures carry rim light in the same
    hue as the eye, wrapped right around the silhouette, so candidates are filtered by
    shape: the accent is a compact blob, the rim is a thin outline around everything.
    A hue inside `signature` scores higher, which is what stops a small amber second eye
    from beating the big magenta one.
    """
    w, h = im.size
    px = im.load()
    sal = [salience(px[i % w, i // w]) if px[i % w, i // w][3] > 128 else -1.0
           for i in range(w * h)]
    top = max(sal)
    if top <= 0.18:            # a dead eye on a death frame — nothing to preserve
        return set()
    mask = [s >= top * 0.62 for s in sal]
    best = None
    for cells in _components(mask, w, h):
        xs = [i % w for i in cells]
        ys = [i // w for i in cells]
        bw, bh = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
        if bw > w * 0.6 or bh > h * 0.6:      # wraps the body: rim light, not an accent
            continue
        fill = len(cells) / float(bw * bh)
        if fill < 0.35 or len(cells) < 4:     # thin and stringy: a highlight
            continue
        hues = sorted(hsv(px[i % w, i // w])[0] for i in cells)
        hue = hues[len(hues) // 2]
        bonus = 1.6 if (hue > signature[0] or hue < signature[1]) else 1.0
        score = len(cells) * fill * bonus
        if best is None or score > best[0]:
            best = (score, cells)
    return set(best[1]) if best else set()


def accent_colors(im, accent):
    """A bright colour and a pupil, both taken from the accent itself."""
    if not accent:
        return None, None
    px = im.load()
    w = im.width
    cols = [px[i % w, i // w] for i in accent]
    # The most vivid pixel, not the brightest: the brightest is the specular dot on the
    # eyeball, almost white, and saturating that turns a magenta eye amber.
    h, s, v = max((hsv(c) for c in cols), key=lambda t: t[1] * t[2])
    r, g, b = colorsys.hsv_to_rgb(h, min(1.0, s * 1.1), min(1.0, v * 1.15))
    return (int(r*255), int(g*255), int(b*255)), min(cols, key=lum)[:3]


# ------------------------------------------------------------------- the ramp

def build_ramp(im, steps=4, accent=None):
    """Four hue-shifted steps in the reference's dominant body hue.

    One hue for the whole ramp, taken from the commonest bucket rather than sampled at
    luminance percentiles: the brightest unsaturated pixels on these creatures are the
    tan belly lumps, so percentile sampling produced a brown "fur" ramp on a violet
    monster. Rim light and the accent are both excluded, or the ramp's top step comes
    back hot magenta and the finished sprite is speckled pink.
    """
    px = im.load()
    w, h = im.size
    accent = accent or set()
    body = []
    for i in range(w * h):
        p = px[i % w, i // w]
        if p[3] < 128 or i in accent or salience(p) > 0.30:
            continue
        body.append(p)
    if not body:
        return [(60, 60, 70)] * steps

    hsvs = [hsv(p) for p in body]
    buckets = {}
    for t in hsvs:
        buckets.setdefault(int(t[0] * 12) % 12, []).append(t)
    dom = max(buckets.values(), key=len)
    base_h = sorted(t[0] for t in dom)[len(dom) // 2]
    base_s = sorted(t[1] for t in dom)[len(dom) // 2]
    vals = sorted(t[2] for t in hsvs)

    ramp = []
    for k in range(steps):
        q = (0.10, 0.30, 0.55, 0.80)[k] if steps == 4 else (k + 0.5) / steps
        v = vals[min(len(vals) - 1, int(q * len(vals)))]
        shift = (k / float(steps - 1)) - 0.5        # -0.5 shadow .. +0.5 light
        hh = (base_h - 0.035 * shift) % 1.0         # shadows cooler, lights warmer
        ss = min(1.0, base_s * (1.0 - 0.30 * shift))
        r, g, b = colorsys.hsv_to_rgb(hh, ss, v)
        ramp.append((int(r * 255), int(g * 255), int(b * 255)))
    return ramp


# ------------------------------------------------------------------ the frame

def make_frame(im, ramp, accent_col=None, size=TARGET, cover=0.45):
    im = im.convert("RGBA")
    w = im.width
    n = w // size
    px = im.load()
    accent = find_accent(im)
    bright, pupil = accent_col if accent_col else accent_colors(im, accent)

    cells = {}
    for y in range(size):
        for x in range(size):
            block = [px[x*n + dx, y*n + dy] for dy in range(n) for dx in range(n)]
            solid = [p for p in block if p[3] > 128]
            if len(solid) < cover * len(block):
                continue
            cells[(x, y)] = sum(lum(p) for p in solid) / len(solid)

    # A pixel dangling off the silhouette is what an antenna or a fur wisp becomes at
    # this scale, and it reads as dirt on the screen rather than as anatomy.
    for p in [p for p in cells
              if sum(1 for d in ((1, 0), (-1, 0), (0, 1), (0, -1))
                     if (p[0] + d[0], p[1] + d[1]) in cells) < 2]:
        del cells[p]

    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if not cells:
        return out
    op = out.load()
    # Cut the ramp against the block means, not against raw source pixels: averaging a
    # block lifts its darkest pixel, so every cell clears a threshold set from source
    # luminance and the creature comes out uniformly pale. Weighted late (30/60/85) so
    # the two dark steps carry the body and the lightest stays a highlight.
    vals = sorted(cells.values())
    cuts = [vals[min(len(vals) - 1, int(q * len(vals)))] for q in (0.30, 0.60, 0.85)]
    for (x, y), l in cells.items():
        op[x, y] = ramp[sum(1 for c in cuts if l > c)] + (255,)

    # The accent goes on last and at full size: it is the one thing a 16px creature has
    # to communicate, so it is placed rather than sampled. Never below 2x2 — a single
    # pixel of accent is a speck.
    if accent and bright:
        cx = int(sum((i % w) / float(n) for i in accent) / len(accent))
        cy = int(sum((i // w) / float(n) for i in accent) / len(accent))
        span = max(2, int(round(len(accent) ** 0.5 / n)))
        for dy in range(span):
            for dx in range(span):
                if 0 <= cx + dx < size and 0 <= cy + dy < size:
                    op[cx + dx, cy + dy] = bright + (255,)
        if span >= 2 and pupil:
            op[cx, cy] = pupil + (255,)
    return out


def match_to_reference(im, ref_im):
    """Pull a generated rotation back onto the source sprite's colour.

    create_character's v3 mode reproduces the south view pixel-for-pixel but drifts on the
    turned views — measured on one creature, east came back 8% brighter and east/west both
    shifted ~0.05-0.08 in hue toward pink. Left alone the creature visibly pales and warms
    as it turns a corner, which reads as a different monster rather than the same one
    facing another way.

    Body pixels only: the accent is excluded from the measurement, because a big saturated
    eye would drag the medians around and the correction would then chase the eye instead
    of the fur.

    Brightness is corrected by scaling RGB linearly against the median of sum(RGB) — the
    same measure and the same method build_wall_atlas.py uses to level independently
    generated tile sets. Matching HSV value instead was tried and overshot by 12%, because
    sum(RGB) also moves with saturation, so the number being measured was not the number
    being corrected.
    """
    def body_medians(x):
        acc = find_accent(x)
        w = x.width
        px = x.load()
        hs, sums = [], []
        for i in range(w * x.height):
            if i in acc:
                continue
            p = px[i % w, i // w]
            if p[3] < 128:
                continue
            sums.append(p[0] + p[1] + p[2])
            h, s, _ = hsv(p)
            if s > 0.12:
                hs.append(h)
        if not sums:
            return None, None
        return (sorted(hs)[len(hs) // 2] if hs else None, sorted(sums)[len(sums) // 2])

    ref_h, ref_sum = body_medians(ref_im)
    cur_h, cur_sum = body_medians(im)
    if ref_sum is None or not cur_sum:
        return im
    k = ref_sum / float(cur_sum)
    dh = (ref_h - cur_h) if (ref_h is not None and cur_h is not None) else 0.0

    im = im.convert("RGBA").copy()
    w = im.width
    px = im.load()
    for i in range(w * im.height):
        x, y = i % w, i // w
        p = px[x, y]
        if p[3] < 128:
            continue
        r, g, b = (min(255, int(p[0] * k)), min(255, int(p[1] * k)),
                   min(255, int(p[2] * k)))
        if dh:
            h, s, v = hsv((r, g, b, 255))
            fr, fg, fb = colorsys.hsv_to_rgb((h + dh) % 1.0, s, v)
            r, g, b = int(fr * 255), int(fg * 255), int(fb * 255)
        px[x, y] = (r, g, b, p[3])
    return im


def dissolve(im, strength, seed):
    """Eat a death frame away, head first.

    The generator's death does land — the eye cracks and goes dark — but at sixteen
    pixels the body is still a solid mass on the final frame, so the creature reads as
    freezing rather than dying. The head goes first and the feet last, so it reads as
    burning off from the top while the contact shadow fades under it; an even sprinkle
    would read as a transmission fault. Deterministic per pixel, so a frame always
    crumbles the same way.
    """
    im = im.copy()
    w, h = im.size
    px = im.load()
    for y in range(h):
        height = 1.0 - (y / float(h - 1))
        for x in range(w):
            if px[x, y][3] < 128:
                continue
            noise = ((x * 73 + y * 151 + seed * 31) % 97) / 97.0
            if noise < strength * (0.45 + 0.85 * height):
                px[x, y] = px[x, y][:3] + (0,)
    return im


# ----------------------------------------------------------- 2x reduction step

def halve(im, size, margin=0.34):
    """A straight 2x reduction, for when the source is already clean pixel art.

    Used to get 64px generator output down to the 32px reference this module reads.
    BOX for the shape, snapped back to the source palette, then any block whose most
    salient pixel is far more vivid than its own average is re-stamped with that pixel.
    Good for one halving; it is *not* good enough for two, which is what this whole
    module exists to work around.
    """
    im = im.convert("RGBA")
    n = im.width // size
    pal = [p for p in set(im.get_flattened_data()) if p[3] > 128]
    if not pal:
        return Image.new("RGBA", (size, size), (0, 0, 0, 0))
    box = im.resize((size, size), Image.BOX)
    src, dst = im.load(), box.load()
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    op = out.load()
    for y in range(size):
        for x in range(size):
            block = [src[x*n + dx, y*n + dy] for dy in range(n) for dx in range(n)]
            cover = sum(1 for p in block if p[3] > 128) / float(len(block))
            avg = dst[x, y]
            if avg[3] < 110 and cover < 0.5:
                continue
            best = max(block, key=lambda p: salience(p) if p[3] > 128 else -1.0)
            snapped = min(pal, key=lambda p: sum((p[k] - avg[k]) ** 2 for k in range(3)))
            op[x, y] = ((best[:3] if salience(best) - salience(snapped) > margin
                         else snapped[:3]) + (255,))
    return out


# ------------------------------------------------------------------------ main

def convert(frames, out_dir, base_id, variant="", death=False, dissolve_tail=4,
            ref_path=None):
    """frames: list of paths, frame 1 first.

    `ref_path` is the frame the ramp and accent colour are read from, and every sequence
    of one creature must be given the *same* one — pass the walk cycle's first frame when
    converting its death. Left to default, each sequence reads its own opening frame, and
    although those are nominally the same image the generator re-encodes it per job; on
    one variant that was enough to flip the dominant hue bucket, and the creature died a
    different colour than it walked.
    """
    ref = Image.open(ref_path or frames[0]).convert("RGBA")
    accent = find_accent(ref)
    ramp = build_ramp(ref, accent=accent)
    col = accent_colors(ref, accent)
    tag = "death_frame" if death else "frame"
    written = []
    for i, path in enumerate(frames):
        img = make_frame(Image.open(path).convert("RGBA"), ramp, accent_col=col)
        left = len(frames) - 1 - i
        if death and left < dissolve_tail:
            img = dissolve(img, (dissolve_tail - left) / float(dissolve_tail + 0.4), i)
        p = os.path.join(out_dir, "%s%s_%s_%d.png" % (base_id, variant, tag, i + 1))
        img.save(p)
        written.append(p)
    return written


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = [a for a in sys.argv[1:] if a.startswith("--")]
    if len(args) < 3:
        print(__doc__)
        sys.exit(1)
    src_dir, out_dir, base = args[0], args[1], args[2]
    variant = ""
    for f in flags:
        if f.startswith("--variant"):
            variant = f.split("=", 1)[1] if "=" in f else ""
    paths = sorted(os.path.join(src_dir, f) for f in os.listdir(src_dir)
                   if f.endswith(".png"))
    done = convert(paths, out_dir, base, variant, death="--death" in flags)
    print("wrote %d frames to %s" % (len(done), out_dir))
