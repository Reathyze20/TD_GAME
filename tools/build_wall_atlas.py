"""Build high_ground_atlas.png from three independently generated PixelLab tilesets.

Three fixes over the naive compose:
  1. straight edges are SNAPPED flat, or the tile's own rounded corners repeat every
     48 px and the wall grows battlements
  2. interior highlights are CLAMPED, or the one distinctive bright cluster in the
     solid tile repeats in a visible lattice
  3. the rim is REPAINTED from the tile's alpha shape: light on north-facing boundaries,
     shadow on south-facing ones, so it reads as light from above and not as an outline
"""
from PIL import Image
from collections import Counter
import statistics, os

import sys                                                     # noqa: E402
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import game_raster                                             # noqa: E402

T = game_raster.ART_PX       # strana dlazdice v pixelech ARTU
ZOOM = game_raster.SCALE     # kolikrat se uklada do atlasu (atlas je v px OBRAZOVKY)
# Adresáře se staženými sadami z PixelLabu (create_tiles_pro, tile_feature='tileset').
# Každá sada = jedna varianta v atlasu, proto musí být z NEZÁVISLÝCH generování.
SETS = ['terr', 'd_wall777', 'd_wall4242']

RIM = (108, 122, 166)        # sum 396 — clearly above the body, far below any enemy
SHADE = 0.55                 # south-facing boundary darkening
HEADROOM = 55                # how far above the body median a pixel may sit


def load_set(folder):
    """Key the floor colour to alpha and index by PixelLab mask."""
    t0 = Image.open('%s/t0.png' % folder).convert('RGB')
    floor = Counter(t0.getdata()).most_common(1)[0][0]
    out = {}
    for i in range(16):
        im = Image.open('%s/t%d.png' % (folder, i)).convert('RGBA')
        px = im.load()
        for y in range(T):
            for x in range(T):
                r, g, b, a = px[x, y]
                if max(abs(r-floor[0]), abs(g-floor[1]), abs(b-floor[2])) <= 10:
                    px[x, y] = (r, g, b, 0)
        out[i] = im
    return out


def game_to_pl(m):
    """game.gd: bit1=NW,2=NE,4=SW,8=SE   PixelLab: NW<<3|NE<<2|SW<<1|SE — bit-reversed."""
    return ((8 if m & 1 else 0) | (4 if m & 2 else 0)
            | (2 if m & 4 else 0) | (1 if m & 8 else 0))


def opaque(im, x, y):
    if 0 <= x < T and 0 <= y < T:
        return im.getpixel((x, y))[3] > 128
    return None          # outside the tile: unknown, never treated as a boundary


## The half-way line every straight edge must land on. Fixed, not measured per tile:
## each generated set rounds its plateau differently, so a per-tile mode made the
## variants step against one another and the wall grew blocks along its top.
SNAP_LINE = {'N': T // 2, 'W': T // 2, 'S': T // 2 - 1, 'E': T // 2 - 1}


def snap(im, solid_src, side):
    """Force a straight edge onto the shared half-way line, filling from the solid tile."""
    im = im.copy()
    px = im.load()
    target = SNAP_LINE[side]
    for a in range(T):
        for b in range(T):
            x, y = (a, b) if side in ('N', 'S') else (b, a)
            inside = (b >= target) if side in ('N', 'W') else (b <= target)
            if inside and not opaque(im, x, y):
                r, g, bb, _ = solid_src.getpixel((x, y))
                px[x, y] = (r, g, bb, 255)
            elif not inside and opaque(im, x, y):
                px[x, y] = px[x, y][:3] + (0,)
    return im


def relight(im):
    im = im.copy()
    px = im.load()
    vals = [sum(px[x, y][:3]) for y in range(T) for x in range(T) if px[x, y][3] > 128]
    if not vals:
        return im
    cap = statistics.median(vals) + HEADROOM
    # 1) flatten the generator's stray sparkles: they are what tiles into a lattice
    for y in range(T):
        for x in range(T):
            r, g, b, a = px[x, y]
            if a > 128 and r + g + b > cap:
                k = cap / float(r + g + b)
                px[x, y] = (int(r*k), int(g*k), int(b*k), a)
    # 2) repaint the edge from the alpha shape, top-lit
    edge = {}
    for y in range(T):
        for x in range(T):
            if px[x, y][3] <= 128:
                continue
            if opaque(im, x, y - 1) is False:
                edge[(x, y)] = 'N'
            elif opaque(im, x, y + 1) is False:
                edge.setdefault((x, y), 'S')
    for (x, y), kind in edge.items():
        if kind == 'N':
            px[x, y] = RIM + (255,)
        else:
            r, g, b, a = px[x, y]
            px[x, y] = (int(r*SHADE), int(g*SHADE), int(b*SHADE), a)
    return im


def body_median(tiles):
    vals = []
    for im in tiles.values():
        px = im.load()
        vals += [sum(px[x, y][:3]) for y in range(T) for x in range(T) if px[x, y][3] > 128]
    return statistics.median(vals)


def rescale(im, k):
    im = im.copy()
    px = im.load()
    for y in range(T):
        for x in range(T):
            r, g, b, a = px[x, y]
            if a > 128:
                px[x, y] = (min(255, int(r*k)), min(255, int(g*k)), min(255, int(b*k)), a)
    return im


sheet = Image.new('RGBA', (4 * T, 4 * T * len(SETS)), (0, 0, 0, 0))
STRAIGHT = {3: 'S', 12: 'N', 5: 'E', 10: 'W'}

loaded = [load_set(f) for f in SETS]
meds = [body_median(t) for t in loaded]
target_med = sum(meds) / len(meds)
print('mediany jasu sad:', [round(m) for m in meds], '-> srovnano na', round(target_med))

for v, s in enumerate(loaded):
    s = {k: rescale(im, target_med / meds[v]) for k, im in s.items()}
    solid = s[15]
    by_pl = dict(s)
    from PIL import ImageOps
    by_pl[13] = ImageOps.mirror(s[14])       # mask 13 never comes back from the generator
    for m in range(16):
        tile = by_pl[game_to_pl(m)]
        if m in STRAIGHT:
            tile = snap(tile, solid, STRAIGHT[m])
        tile = relight(tile)
        sheet.paste(tile, ((m % 4) * T, (v * 4 + m // 4) * T))

out = sheet.resize((sheet.width * ZOOM, sheet.height * ZOOM), Image.NEAREST)
out.save('atlas_v2.png')
op = [p for p in out.getdata() if p[3] > 200]
print('atlas_v2.png', out.size, '|', len(SETS), 'variant z RUZNYCH sad')
print('nejjasnejsi pixel zdi sum=%d' % max(sum(p[:3]) for p in op))
