"""Midjourney koncept -> predloha pro PixelLab, ktera obstoji vedle obranců.

Pouziti:
    python tools/mj_to_sprite.py <koncept.png> <predloha_64.png> [--test]

Pak uz jen:
    create_character(mode="v3", size=64, reference_image_base64=<predloha_64.png>,
                     view="low top-down")
    -> animate_character SABLONOU (ne custom v3) -> stahnout -> halve() 64->32

--------------------------------------------------------------------------------
Proc 64 a ne 32 (draha lekce ze 17. 8. 2026)

Puvodne tenhle skript delal predlohu v 64 px. Po kritice dvojiho pulení jsem prepnul
na nativnich 32 px — a to bylo hur: v 32 px nema generator kam nakreslit obrys, takze
notifikace vysla jako 95px smouha bez siluety (brokolice ma 451 px).

Spravne to je: **generuj v 64 a pul PRAVE JEDNOU.** Presne to dela roster obranců.
`sprite_16.halve()` je podle vlastni dokumentace dobra na jedno zmenseni; chyba nikdy
nebyla v tom, ze se puli z 64, ale ze se pulilo z rozmazane malby a pak jeste jednou.

--------------------------------------------------------------------------------
Proc kvantizace a obrys

Samotny LANCZOS + halve nechá z malby spojite prechody. Zmereno na hotovych spritech:

    broccoli (lata)   bbox 23x30  hmota 451  barev 25  obrys -21,0  casti 1
    clickbait (MJ)    bbox 27x28  hmota 540  barev 57  obrys -37,2  casti 1
    notification (32) bbox  9x12  hmota  83  barev 33  obrys - 2,9  casti 1

Clickbait mel dvojnasobnou paletu -> vypadal jako rozmazana fotka mezi pixel-art
sousedy. Notifikace nemela obrys vubec. Proto se sem pridala adaptivni paleta na 24
barev a 1px tmavy prstenec kolem siluety — tim, cim brokolice drzi tvar.
"""
import os
import sys
from collections import deque

import numpy as np
from PIL import Image
from scipy.ndimage import binary_dilation, binary_erosion, label

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sprite_16


# ------------------------------------------------------------------ vyriznuti

#: Vyrez podle BARVY, ne podle vyplneni z rohu.
#:
#: Midjourney pod 3D render skoro vzdy zapece vrzeny stin, a `cutout()` ho neodstrani:
#: je to plynuly prechod, takze vylevani z rohu se v nem zastavi, a `strip_shadow()`
#: bere jen spodni pas, kdezto stin sahá do strany.
#:
#: Zmereno na koncepte rajcete (21. 8. 2026):
#:     stin      sytost 0,129   soucet 479
#:     ciferník  sytost 0,170   soucet 283   <- nejzradnejsi, taky sedy
#:     telo      sytost 0,961   soucet 117
#:     pozadi    sytost 0,025   soucet 658
#:
#: Stin je SVETLY a NESYTY zaroven. Ciferník je nesyty, ale tmavy. Objekt je bud syty,
#: nebo tmavy -- a to je cela ta hranice.
CHROMA_SAT = 0.18
CHROMA_VAL = 420.0


def cutout_chroma(src, sat_thr=CHROMA_SAT, val_thr=CHROMA_VAL):
    im = Image.open(src).convert("RGB")
    a = np.asarray(im).astype(float)
    mx, mn = a.max(2), a.min(2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    keep = (sat > sat_thr) | (a.sum(2) < val_thr)
    # Jen nejvetsi souvisla oblast: drobky po prahovani jsou presne to, na cem pada
    # brana "casti > 1".
    lab, n = label(keep)
    if n > 1:
        sizes = np.bincount(lab.ravel())
        sizes[0] = 0
        keep = lab == sizes.argmax()
    out = np.dstack([np.asarray(im), (keep * 255).astype(np.uint8)])
    return Image.fromarray(out, "RGBA")


def _flood(a, seed, tol, starts):
    h, w, _ = a.shape
    vis = np.zeros((h, w), bool)
    mask = np.zeros((h, w), bool)
    q = deque()
    for s in starts:
        if not vis[s]:
            vis[s] = True
            q.append(s)
    while q:
        y, x = q.popleft()
        if a[y, x, 3] == 0:
            continue
        p = a[y, x]
        if abs(int(p[0]) - seed[0]) + abs(int(p[1]) - seed[1]) + abs(int(p[2]) - seed[2]) > tol:
            continue
        mask[y, x] = True
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not vis[ny, nx]:
                vis[ny, nx] = True
                q.append((ny, nx))
    return mask


def cutout(src, tol_bg=72, tol_ground=90):
    """Vyklici pozadi i zapecenou zem a vrati ctvercovy orez na postavu.

    Dve kola: MJ pod postavu maluje zem, ktera se NEDOTYKA okraje platna, takze ji
    okrajovy flood-fill mine.
    """
    a = np.asarray(Image.open(src).convert("RGBA")).astype(np.int16).copy()
    h, w, _ = a.shape
    border = ([(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)]
              + [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)])
    a[..., 3] = np.where(_flood(a, a[2, 2, :3].astype(int), tol_bg, border), 0, 255)

    band = a[int(h * 0.80):, :, :3].astype(float)
    mx, mn = band.max(2), band.min(2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1), 0)
    cand = (sat < 0.20) & (mx > 50) & (mx < 195) & (a[int(h * 0.80):, :, 3] > 0)
    ys, xs = np.nonzero(cand)
    if len(ys):
        sy, sx = int(np.median(ys)) + int(h * 0.80), int(np.median(xs))
        a[..., 3] = np.where(_flood(a, a[sy, sx, :3].astype(int), tol_ground, [(sy, sx)]),
                             0, a[..., 3])

    ys, xs = np.nonzero(a[..., 3] > 0)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    side = int(max(y1 - y0, x1 - x0) * 1.04)
    cy, cx = (y0 + y1) // 2, (x0 + x1) // 2
    top, left = max(0, cy - side // 2), max(0, cx - side // 2)
    return Image.fromarray(a.astype(np.uint8), "RGBA").crop((left, top, left + side, top + side))


# ------------------------------------------------------------------- na raster

def fit(cut, size=64, margin=2):
    """Natahne bytost tak, aby vyplnila platno az na okraj.

    Sklada se ve dvojnasobku a pak se jednou zavola halve(); ta chce ctverec, takze
    se sem nesmi cpat nectvercovy mezikrok.
    """
    a = np.asarray(cut.convert("RGBA"))
    ys, xs = np.nonzero(a[..., 3] > 128)
    body = cut.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    big = size * 2
    target = (size - 2 * margin) * 2
    w, h = body.size
    s = target / max(w, h)
    nw, nh = max(1, round(w * s)), max(1, round(h * s))
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    canvas.alpha_composite(body.resize((nw, nh), Image.LANCZOS),
                           ((big - nw) // 2, big - margin * 2 - nh))
    return sprite_16.halve(canvas, size)


def strip_shadow(img, band=0.18):
    """Odstrani sedou zapecenou zem. Barevnou zem chyti az cut_floor()."""
    a = np.asarray(img.convert("RGBA")).astype(np.int16).copy()
    m = a[..., 3] > 128
    if not m.any():
        return img
    ys = np.nonzero(m)[0]
    y0 = int(ys.max() - (ys.max() - ys.min()) * band)
    rgb = a[..., :3].astype(float)
    lum = rgb @ [0.299, 0.587, 0.114]
    mx, mn = rgb.max(2), rgb.min(2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1), 0)
    kill = np.zeros_like(m)
    kill[y0:] = m[y0:] & (sat[y0:] < 0.30) & (lum[y0:] < lum[m].mean() * 0.80)
    a[..., 3][kill] = 0
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def strip_panel(img, ratio=0.62):
    """Umaze tmavou plochu zapecenou za postavou, ktera sahá k okraji platna.

    Nutne proto, ze `strip_shadow` ji minie: generator ji obarvi **barvou postavy**,
    takze je sytejsi nez telo (u clickbaitovy smrti 0,726 proti 0,660) a test na
    nizkou sytost na ni neplati. Geometrie ale plati vzdycky — postava je vycentrovana
    a okraje platna se nedotyka, kdezto zapeceny panel ano. Proto flood od okraje
    pres tmave pixely.
    """
    a = np.asarray(img.convert("RGBA")).copy()
    m = a[..., 3] > 128
    if not m.any():
        return img
    lum = a[..., :3].astype(float) @ [0.299, 0.587, 0.114]
    ref = lum[m].mean()
    dark = m & (lum < ref * ratio)
    h, w = m.shape
    border = ([(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)]
              + [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)])
    seeds = [(y, x) for y, x in border if dark[y, x]]
    if not seeds:
        return img
    lab, _ = label(dark)
    kill = np.isin(lab, list({lab[y, x] for y, x in seeds}))
    a[..., 3][kill] = 0
    return Image.fromarray(a, "RGBA")


def cut_floor(img):
    """Umaze vsechno pod dotykovou carou.

    Zem byva stejne tmava i stejne barevna jako nohy, ktere na ni stoji (u obou nasich
    konceptu magentova), takze ji spolehlive urcuje jen geometrie: zem je sirsi nez
    nohy. Scanuje se SHORA DOLU a rez padne v prvnim rozsireni — hledat globalne
    nejuzsi radek nelze, ten lezi az uplne dole uvnitr stinu.

    Musi bezet na slozenem platne, ne na plnem rozliseni: pomer nohou a stinu se
    zmensenim meni a prah nalezeny v 1024 px na 64 px nesedi.
    """
    a = np.asarray(img.convert("RGBA")).copy()
    m = a[..., 3] > 128
    if not m.any():
        return img
    ys = np.nonzero(m)[0]
    lo, hi = ys.min(), ys.max()
    span = {y: int(np.nonzero(m[y])[0].max() - np.nonzero(m[y])[0].min() + 1)
            for y in range(lo, hi + 1) if m[y].any()}
    band = sorted(y for y in span if y >= hi - (hi - lo) * 0.25)
    if len(band) < 3:
        return img
    floor, run_min = hi, span[band[0]]
    for y in band:
        if span[y] > run_min * 1.25:
            floor = y - 1
            break
        run_min = min(run_min, span[y])
    a[..., 3][floor + 1:] = 0
    return Image.fromarray(a, "RGBA")


def settle(img, margin=2):
    """Posadi orezanou postavu zpatky na spodni okraj bez dalsiho prevzorkovani."""
    a = np.asarray(img.convert("RGBA"))
    ys = np.nonzero(a[..., 3] > 128)[0]
    shift = (img.height - margin - 1) - ys.max()
    if shift == 0:
        return img
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(img, (0, shift))
    return out


def quantize(img, colors=24):
    """Adaptivni paleta pres neprusvitne pixely; alfa se binarizuje."""
    a = np.asarray(img.convert("RGBA")).copy()
    m = a[..., 3] > 128
    a[..., 3] = np.where(m, 255, 0)
    pal = Image.fromarray(a[..., :3]).quantize(
        colors=colors, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
    return Image.fromarray(np.dstack([np.asarray(pal), a[..., 3]]).astype(np.uint8), "RGBA")


def outline(img, strength=0.42):
    """Prida 1px tmavy prstenec kolem siluety — to, cim brokolice drzi tvar."""
    a = np.asarray(img.convert("RGBA")).astype(np.int16).copy()
    m = a[..., 3] > 128
    ring = binary_dilation(m) & ~m
    dark = np.clip(a[..., :3][m].astype(float).mean(0) * strength, 8, 90).astype(np.int16)
    a[..., :3][ring] = dark
    a[..., 3][ring] = 255
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def outline_color(ref, target=21.0):
    """Spocita barvu obrysu JEDNOU pro celou animaci; None = obrys uz staci.

    Pocitat ji per-snimek nelze: obrys by mezi snimky blikal, protoze kazda poza ma
    jiny pomer okraje k telu. Stejny duvod, proc si sprite_16 pocita rampu z jedine
    referencni snimky.
    """
    a = np.asarray(ref.convert("RGBA"))
    m = a[..., 3] > 128
    edge = m & ~binary_erosion(m)
    lum = a[..., :3].astype(float) @ [0.299, 0.587, 0.114]
    body, rim = lum[m].mean(), lum[edge].mean()
    if rim <= body - target:
        return None
    tint = a[..., :3][m].astype(float).mean(0)          # drz odstin tela, jen tmavsi
    scale = max(body - target, 6.0) / max(tint @ [0.299, 0.587, 0.114], 1.0)
    return np.clip(tint * scale, 4, 255).astype(np.uint8)


def restore_outline(img, rim):
    """Prebarvi stavajici okrajove pixely JEDNOU tmavou barvou.

    Nedilatuje — na 32 px by 1 px navic byl videt. A nesmi to byt ztmaveni kazdeho
    pixelu zvlast: to sice obrys spravi, ale paleta vyskoci (u clickbaita 23 -> 38
    barev) a sprite zase vypada jako rozmazana malba. Pixel art ma obrys jednou barvou.

    Proc je to vubec potreba: PixelLab kresli v 64 px tenci obrys nez roster obranců a
    `halve()` ho smicha s telem. Namereno po zmenseni -12,9 (clickbait) a -13,5
    (notifikace) proti -21,0 u brokolice.
    """
    if rim is None:
        return img
    a = np.asarray(img.convert("RGBA")).copy()
    m = a[..., 3] > 128
    edge = m & ~binary_erosion(m)
    a[..., :3][edge] = rim
    return Image.fromarray(a, "RGBA")


#: Prumerny jas `assets/background.png`. Prah kontrastu je +30 (viz ART_PIPELINE 3b).
BG_LUM = 20.3


def lift_gamma(ref, target=32.0, bg=BG_LUM):
    """Najde gamu na HSV-V, ktera zvedne sprite nad prah kontrastu. None = uz staci.

    Pocitat ji per-snimek nelze — sprite by pri chuzi pulzoval. Jednou na animaci.
    """
    a = np.asarray(ref.convert("RGBA"))
    m = a[..., 3] > 128
    if not m.any():
        return None
    lum = (a[..., :3].astype(float) @ [0.299, 0.587, 0.114])[m]
    if lum.mean() - bg >= target:
        return None
    lo, hi = 0.25, 1.0
    for _ in range(24):                       # pulení intervalu, gama je monotonni
        g = (lo + hi) / 2
        if (255.0 * (lum / 255.0) ** g).mean() - bg >= target:
            lo = g
        else:
            hi = g
    return (lo + hi) / 2


def lift(img, gamma):
    """Rozjasni pres hodnotu v HSV, ne pres cerny bod v RGB.

    Zvednuti cerneho bodu v RGB cisla kontrastu spravi, ale **znici sytost** — u
    incognita spadla z 0,664 na 0,226 a prisera zesedivela, zatimco metriky vypadaly
    dobre. Gama na V drzi odstin i sytost (0,713 po uprave proti 0,714 pred).
    """
    if gamma is None or gamma >= 0.999:
        return img
    a = np.asarray(img.convert("RGBA")).copy()
    m = a[..., 3] > 128
    rgb = a[..., :3].astype(np.float32)
    v = rgb.max(2)
    scale = np.where(v > 0, 255.0 * (v / 255.0) ** gamma / np.maximum(v, 1), 1.0)
    rgb *= scale[..., None]
    a[..., :3] = np.where(m[..., None], np.clip(rgb, 0, 255).astype(np.uint8), a[..., :3])
    return Image.fromarray(a, "RGBA")


def largest_piece(img):
    """Jeden souvisly kus. Rozpadle uletky vypadaji ve hre jako chyba vykreslovani."""
    a = np.asarray(img.convert("RGBA")).copy()
    lab, n = label(a[..., 3] > 128)
    if n > 1:
        keep = 1 + int(np.argmax([(lab == i).sum() for i in range(1, n + 1)]))
        a[..., 3] = np.where(lab == keep, a[..., 3], 0)
    return Image.fromarray(a, "RGBA")


def build(cut, size=64, colors=24):
    """Cely retez z vyriznuteho konceptu na predlohu pro PixelLab."""
    return largest_piece(outline(quantize(settle(cut_floor(strip_shadow(fit(cut, size)))),
                                          colors)))


# ------------------------------------------------------------------- kontrola

#: Prahy odectene z rosteru obranců. `fill` zamerne chybi — kryti skaluje s
#: `def.radius` te prisery (clickbait radius 14 -> 48 %, notifikace radius 9 -> 28,5 %
#: a oboji je spravne), takze absolutni prah na nej nasadit nejde.
GATES = dict(colors=32, outline=15, pieces=1, thin=2, height=26)


def audit(img):
    """Cisla, ktera rozhoduji, jestli sprite ve hre obstoji. Mer na 32 px."""
    a = np.asarray(img.convert("RGBA"))
    m = a[..., 3] > 128
    ys, xs = np.nonzero(m)
    lum = a[..., :3].astype(float) @ [0.299, 0.587, 0.114]
    edge = m & ~binary_erosion(m)
    widths = []
    for y in range(a.shape[0]):
        c = 0
        for v in m[y]:
            if v:
                c += 1
            elif c:
                widths.append(c)
                c = 0
        if c:
            widths.append(c)
    return dict(w=int(xs.max() - xs.min() + 1), h=int(ys.max() - ys.min() + 1),
                fill=100 * m.mean(), px=int(m.sum()),
                colors=len(set(map(tuple, (a[..., :3][m] // 8)))),
                outline=float(lum[m].mean() - lum[edge].mean()),
                pieces=int(label(m)[1]),
                thin=sum(1 for x in widths if x < 2), segs=len(widths))


def passes(k):
    """Vrati seznam porusenych bran; prazdny seznam = sprite je pouzitelny."""
    bad = []
    if k["colors"] > GATES["colors"]:
        bad.append(f"barev {k['colors']} > {GATES['colors']} (rozmazane, ne pixel art)")
    if k["outline"] < GATES["outline"]:
        bad.append(f"obrys -{k['outline']:.1f} < {GATES['outline']} (silueta se rozteka)")
    if k["pieces"] > GATES["pieces"]:
        bad.append(f"casti {k['pieces']} > 1 (uletle fragmenty)")
    if k["thin"] > GATES["thin"]:
        bad.append(f"tenkych segmentu {k['thin']} > {GATES['thin']}")
    if k["h"] < GATES["height"]:
        bad.append(f"vyska {k['h']} < {GATES['height']} (prisera je drobek)")
    return bad


def report(name, img):
    k = audit(img)
    bad = passes(k)
    print(f"{name:24s} bbox {k['w']:2d}x{k['h']:2d}  hmota {k['px']:4d}  barev {k['colors']:3d}"
          f"  obrys -{k['outline']:5.1f}  casti {k['pieces']}  tenkych {k['thin']}/{k['segs']}")
    for b in bad:
        print(f"{'':24s}   !! {b}")
    return not bad


if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    # --chroma: vyrez podle barvy (stin pryc). Vychozi zustava puvodni vylevani z rohu,
    # aby se starym konceptum nezmenil vysledek pod rukama.
    cut = cutout_chroma(src) if "--chroma" in sys.argv else cutout(src)
    ref = build(cut)
    ref.save(dst)
    print(f"predloha 64 px -> {dst}")
    if "--test" in sys.argv:
        report("predloha (mereno na 32)", sprite_16.halve(ref, 32))
