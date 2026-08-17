# Cistka spritu: z AI renderu udelej pixel art.
#
#   python tools/sprite_cleanup.py                      # vsechny prisery, nahledy, nic neprepise
#   python tools/sprite_cleanup.py --colors 12          # prisnejsi paleta
#   python tools/sprite_cleanup.py --only energy_drink  # jen jedna prisera
#   python tools/sprite_cleanup.py --apply              # az to schvalis: prepis assets/
#
# CO TENHLE NASTROJ RESI
#
# PixelLab dela dobre tu tezkou cast (pohyb, pozy, silueta) a spatne tu snadnou
# (povrch). Zmereno na energy_drink a autoplay walk cyklu:
#
#     37 az 52 barev na 32x32 spritu       (rucne kresleny ma 8-16)
#     42 az 44 % pixelu nema ani jednoho souseda stejne barvy
#     12 az 14 % pixelu je nakresleno barvou, ktera v nekterych framech chybi
#
# To posledni je duvod, proc animace pusobi "zprzene". Nejde o spatnou animaci -
# silueta je stabilni na 1 px. Jde o to, ze povrch mezi framy vari: stejne misto
# na tele ma frame od framu jiny odstin. Oko to cte jako sum.
#
# JAK SE TO OPRAVI
#
# 1. JEDNA PALETA NA PRISERU. Vsechny framy jedne prisery - vsechny smery i
#    animace dohromady - jdou do jednoho pytle a z nej se spocita K barev
#    (k-means v Oklabu, vazeno cetnosti pixelu). Barva, ktera neexistuje, nemuze
#    bliknout: blikani tim mizi z principu, ne odhadem prahu.
#
#    Oklab a ne RGB proto, ze v RGB je vzdalenost cislo bez vztahu k tomu, co
#    oko vidi - tmave odstiny by se slouctily a svetle zbytecne rozdelily.
#
#    Kazda polozka palety se nakonec prilepi na nejcastejsi SKUTECNOU barvu ve
#    svem shluku, ne na spocitany prumer. Diky tomu zustane cerny obrys presne
#    cerny a paleta obsahuje barvy, ktere v arte doopravdy byly.
#
# 2. ODSTRANENI OSAMOCENYCH PIXELU. Pixel bez jedineho souseda stejne barvy,
#    ktery sedi uvnitr jednolite plochy, je zbytek po zmenseni renderu. Nahradi
#    se prevladajici barvou okoli.
#
#    Pozor na oci: 1px oko je taky "osamocene". Rozliseni delá KONTRAST - zbytek
#    po zmenseni je vzdycky odstin blizky okoli, kdezto oko je barva vyrazne jina.
#    Cokoliv kontrastnejsiho nez --detail se necha byt.
#
# Obe casti maji parametr, ktery rozhoduje o tom, jestli prezije drobny detail:
# --weight-exp (dostane oko vlastni barvu v palete?) a --detail (prezije oko
# despeckle?). Kdyz nekde zmizi oko nebo odlesk, saha se na tyhle dva.
#
# Nastroj NIC neprepisuje, dokud nedostane --apply. Bez nej zapisuje do
# build/distractions_clean/ a vedle toho vyrobi nahledy: kontaktni list
# (staticke srovnani) a GIF (na blikani, ktere ve statickem obrazku neuvidis).
import argparse
import os
import re
import sys
from collections import Counter

import numpy as np
from PIL import Image

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(PROJ, "assets", "distractions")
OUT = os.path.join(PROJ, "build", "distractions_clean")
PREVIEW = os.path.join(PROJ, "build", "sprite_cleanup_preview")

# Poradi jmena je <id><varianta><smer|animace>_frame_N.png (viz distraction_animator.gd).
# Odripnutim tehle koncovky zbyde <id><varianta> - a to je skupina, ktera sdili paletu.
# Varianty (_b, _c) jsou zamerne jinak barevne, takze kdyby vznikly, dostanou paletu svou.
SUFFIXES = ("_north", "_east", "_attack", "_death")

FRAME_RE = re.compile(r"^(.*)_frame_(\d+)\.png$")


# ----------------------------------------------------------------- Oklab
#
# sRGB -> linear -> LMS -> Oklab. Vzorce jsou Bjorn Ottosson, prevzato tak jak jsou.

_M1 = np.array([
    [0.4122214708, 0.5363325363, 0.0514459929],
    [0.2119034982, 0.6806995451, 0.1073969566],
    [0.0883024619, 0.2817188376, 0.6299787005],
])
_M2 = np.array([
    [0.2104542553, 0.7936177850, -0.0040720468],
    [1.9779984951, -2.4285922050, 0.4505937099],
    [0.0259040371, 0.7827717662, -0.8086757660],
])


def to_oklab(rgb: np.ndarray) -> np.ndarray:
    """rgb: (...,3) v 0-255 -> Oklab (...,3)."""
    c = rgb.astype(np.float64) / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    lms = lin @ _M1.T
    lms = np.cbrt(lms)
    return lms @ _M2.T


# ----------------------------------------------------------------- k-means


def kmeans(pts: np.ndarray, w: np.ndarray, k: int, iters: int = 80):
    """Vazeny k-means s k-means++ inicializaci. Deterministicky (pevny seed)."""
    n = len(pts)
    if n <= k:
        return np.arange(n)

    rng = np.random.default_rng(20250817)
    base = w / w.sum()
    centers = [pts[rng.choice(n, p=base)]]
    d2 = ((pts - centers[0]) ** 2).sum(1)
    while len(centers) < k:
        p = d2 * w
        idx = rng.choice(n, p=(p / p.sum()) if p.sum() > 0 else base)
        centers.append(pts[idx])
        d2 = np.minimum(d2, ((pts - centers[-1]) ** 2).sum(1))
    C = np.array(centers)

    lab = np.zeros(n, dtype=int)
    for _ in range(iters):
        lab = ((pts[:, None, :] - C[None, :, :]) ** 2).sum(2).argmin(1)
        newC = C.copy()
        for j in range(k):
            m = lab == j
            if m.any():
                ww = w[m][:, None]
                newC[j] = (pts[m] * ww).sum(0) / ww.sum()
        if np.allclose(newC, C):
            break
        C = newC
    return lab


def build_palette(counts: Counter, k: int, weight_exp: float = 0.5) -> np.ndarray:
    """Z pytle barev (barva -> pocet pixelu) udelej paletu K skutecnych barev.

    weight_exp je tu kvuli ocim. K-means minimalizuje VAZENOU chybu, takze
    prirozene obetuje vzacne barvy: oko ma osm pixelu, telo osm set, a odstin oka
    se vsakne do tela - presne to se stalo duchovi phantom_buzz. Umocnenim
    cetnosti na 0.5 se pomer 800:8 zmensi na 28:3, cimz vyrazny detail prezije,
    ale cetnost porad rozhoduje. 1.0 = ciste podle plochy, 0.0 = plocha je jedno.
    """
    cols = np.array(list(counts.keys()), dtype=np.int64)
    w = np.array([counts[tuple(c)] for c in cols], dtype=np.float64) ** weight_exp
    if len(cols) <= k:
        return cols

    lab = kmeans(to_oklab(cols), w, k)
    # Reprezentant shluku = jeho nejcastejsi SKUTECNA barva, ne prumer.
    # Tim zustane obrys presne cerny misto "skoro cerny".
    out = []
    for j in sorted(set(lab.tolist())):
        m = lab == j
        out.append(cols[m][w[m].argmax()])
    return np.array(out, dtype=np.int64)


def remap(rgb: np.ndarray, mask: np.ndarray, pal: np.ndarray, pal_lab: np.ndarray) -> np.ndarray:
    """Kazdy neprusvitny pixel na nejblizsi barvu palety v Oklabu. Bez ditheringu."""
    out = rgb.copy()
    if not mask.any():
        return out
    px = to_oklab(rgb[mask])
    idx = ((px[:, None, :] - pal_lab[None, :, :]) ** 2).sum(2).argmin(1)
    out[mask] = pal[idx]
    return out


# ----------------------------------------------------------------- despeckle


def isolated_mask(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """True tam, kde neprusvitny pixel nema ani jednoho ze 4 sousedu stejne barvy."""
    h, w = alpha.shape
    same = np.zeros((h, w), bool)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        sh = np.zeros((h, w), bool)
        ys = slice(max(0, dy), h + min(0, dy))
        xs = slice(max(0, dx), w + min(0, dx))
        yd = slice(max(0, -dy), h + min(0, -dy))
        xd = slice(max(0, -dx), w + min(0, -dx))
        sh[yd, xd] = (rgb[ys, xs] == rgb[yd, xd]).all(-1) & alpha[ys, xs]
        same |= sh
    return alpha & ~same


def despeckle(rgb, alpha, lab_of, min_support=5, detail=0.12):
    """Osamoceny pixel uvnitr jednolite plochy -> prevladajici barva okoli.

    min_support: kolik z 8 sousedu musi drzet stejnou barvu, aby se pixel prepsal.
                 Cim vic, tim opatrnejsi - pixel musi sedet uvnitr jednolite plochy,
                 ne na hrane nebo v tenke koncetine.

    detail:      TOHLE ZACHRANUJE OCI. Zbytek po zmenseni renderu je vzdycky odstin
                 BLIZKY okoli - o par jednotek jinak nasvicena kuze. Oko, zub nebo
                 odlesk je naopak barva VYRAZNE jina. Takze se osamoceny pixel
                 prepise jen tehdy, kdyz je od prevladajici barvy okoli v Oklabu bliz
                 nez tenhle prah; cokoliv kontrastnejsiho je zamer a zustava.

                 Prvni verze tohohle nastroje chranila misto toho pixely, ktere drzi
                 barvu skrz cely cyklus. Znelo to dobre a nefungovalo: duch
                 phantom_buzz se pri chuzi houpe o pixel nahoru dolu, takze oko neni
                 na stejne souradnici ve dvou framech po sobe a ochrana ho minula.
    """
    h, w = alpha.shape
    iso = isolated_mask(rgb, alpha)
    out = rgb.copy()
    changed = kept = 0
    for y, x in zip(*np.nonzero(iso)):
        neigh = Counter()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy == 0 and dx == 0:
                    continue
                yy, xx = y + dy, x + dx
                if 0 <= yy < h and 0 <= xx < w and alpha[yy, xx]:
                    neigh[tuple(out[yy, xx])] += 1
        if not neigh:
            continue
        col, cnt = neigh.most_common(1)[0]
        if cnt < min_support:
            continue
        if np.linalg.norm(lab_of[tuple(out[y, x])] - lab_of[col]) >= detail:
            kept += 1                                    # kontrastni detail - nechat
            continue
        out[y, x] = col
        changed += 1
    return out, changed, kept


# ----------------------------------------------------------------- io / grouping


def anim_key(stem: str):
    """'energy_drink_east' -> ('energy_drink', '_east'). Skupina palety je ta prvni cast."""
    for s in SUFFIXES:
        if stem.endswith(s):
            return stem[: -len(s)], s
    return stem, ""


def collect():
    """assets/distractions -> {palette_group: {anim_suffix: [(path, frame_no)]}}"""
    groups = {}
    for name in sorted(os.listdir(SRC)):
        m = FRAME_RE.match(name)
        if not m:
            continue                                     # spritesheety a jine se preskoci
        stem, num = m.group(1), int(m.group(2))
        base, suffix = anim_key(stem)
        groups.setdefault(base, {}).setdefault(suffix, []).append((os.path.join(SRC, name), num))
    for g in groups.values():
        for k in g:
            g[k].sort(key=lambda t: t[1])
    return groups


def load(path):
    a = np.array(Image.open(path).convert("RGBA"))
    return a[..., :3].astype(np.int64), a[..., 3]


def save(path, rgb, alpha):
    a = np.dstack([rgb.astype(np.uint8), alpha.astype(np.uint8)])
    Image.fromarray(a, "RGBA").save(path)


# ----------------------------------------------------------------- nahledy


def upscale(rgb, alpha, z):
    a = np.dstack([rgb.astype(np.uint8), alpha.astype(np.uint8)])
    im = Image.fromarray(a, "RGBA")
    return im.resize((im.width * z, im.height * z), Image.NEAREST)


def contact_sheet(before, after, path, zoom=5, pad=3, bg=(28, 28, 34)):
    """Dva radky: nahore original, dole po cistce. Staticke srovnani detailu."""
    if not before:
        return
    tw, th = before[0][0].shape[1] * zoom, before[0][0].shape[0] * zoom
    n = len(before)
    W = n * tw + (n + 1) * pad
    H = 2 * th + 3 * pad
    sheet = Image.new("RGB", (W, H), bg)
    for i, (rgb, al) in enumerate(before):
        sheet.paste(upscale(rgb, al, zoom), (pad + i * (tw + pad), pad), upscale(rgb, al, zoom))
    for i, (rgb, al) in enumerate(after):
        im = upscale(rgb, al, zoom)
        sheet.paste(im, (pad + i * (tw + pad), 2 * pad + th), im)
    sheet.save(path)


def compare_gif(before, after, path, zoom=6, gap=8, ms=120, bg=(28, 28, 34)):
    """Original vedle vycistene verze, prehrane. Na blikani je tohle jediny test."""
    if not before:
        return
    tw, th = before[0][0].shape[1] * zoom, before[0][0].shape[0] * zoom
    frames = []
    for (rb, ab), (ra, aa) in zip(before, after):
        im = Image.new("RGB", (tw * 2 + gap, th), bg)
        l, r = upscale(rb, ab, zoom), upscale(ra, aa, zoom)
        im.paste(l, (0, 0), l)
        im.paste(r, (tw + gap, 0), r)
        frames.append(im.convert("P", palette=Image.ADAPTIVE, colors=128))
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=ms, loop=0, disposal=2)


# ----------------------------------------------------------------- metriky


def measure(anims):
    """anims: {suffix: [(rgb, alpha)]} -> (barev celkem, % osamocenych, % blikajicich)

    Blikani se MUSI merit uvnitr jedne animace. Merene pres vsechny animace
    najednou by se barva pouzita jen v death cyklu tvarila jako blikani, i kdyz
    je v ramci sve animace naprosto stabilni.
    """
    union = set()
    iso = opaque = flick = total = 0
    for frames in anims.values():
        n = len(frames)
        presence = Counter()
        for rgb, al in frames:
            m = al > 32
            cols = {tuple(c) for c in rgb[m]}
            union |= cols
            for c in cols:
                presence[c] += 1
            iso += isolated_mask(rgb, m).sum()
            opaque += m.sum()
        for rgb, al in frames:
            m = al > 32
            for c in map(tuple, rgb[m]):
                total += 1
                if presence[c] < n:
                    flick += 1
    return len(union), 100.0 * iso / max(1, opaque), 100.0 * flick / max(1, total)


# ----------------------------------------------------------------- main


def main():
    ap = argparse.ArgumentParser(description="Cistka AI spritu na skutecny pixel art.")
    ap.add_argument("--colors", type=int, default=16, help="barev na priseru (default 16)")
    ap.add_argument("--only", help="jen prisery, jejichz jmeno obsahuje tenhle retezec")
    ap.add_argument("--despeckle", type=int, default=5, metavar="N",
                    help="kolik z 8 sousedu musi souhlasit, aby se osamoceny pixel prepsal; "
                         "vyssi = opatrnejsi, 9 = vypnuto (default 5)")
    ap.add_argument("--weight-exp", type=float, default=0.5, metavar="E",
                    help="jak moc pri vyberu palety rozhoduje plocha barvy: 1.0 = jen "
                         "plocha (drobne detaily jako oci zmizi), 0.0 = plocha je jedno "
                         "(default 0.5)")
    ap.add_argument("--detail", type=float, default=0.12, metavar="D",
                    help="jak kontrastni musi osamoceny pixel byt, aby se bral jako "
                         "zamer (oko, odlesk) a necistil se; vzdalenost v Oklabu, "
                         "0 = cistit vsechno (default 0.12)")
    ap.add_argument("--apply", action="store_true",
                    help="prepsat assets/distractions/ misto zapisu do build/")
    args = ap.parse_args()

    groups = collect()
    if args.only:
        groups = {k: v for k, v in groups.items() if args.only in k}
    if not groups:
        sys.exit("Nic k cisteni.")

    dest = SRC if args.apply else OUT
    os.makedirs(dest, exist_ok=True)
    if not args.apply:
        os.makedirs(PREVIEW, exist_ok=True)

    print(f"paleta: {args.colors} barev/prisera (vaha plochy {args.weight_exp})   "
          f"despeckle: {'vyp' if args.despeckle >= 9 else args.despeckle}"
          f"   prah detailu: {args.detail}")
    print(f"cil: {os.path.relpath(dest, PROJ)}\n")
    print(f"{'prisera':<20}{'barev':>14}{'osamocenych':>18}{'blikajicich':>16}"
          f"{'cisteno':>9}{'detail':>8}")

    tot_changed = 0
    for base, anims in sorted(groups.items()):
        # --- 1. jeden pytel barev pres uplne vsechny framy prisery
        pool = Counter()
        loaded = {}
        for suffix, files in anims.items():
            fr = [load(p) for p, _ in files]
            loaded[suffix] = fr
            for rgb, al in fr:
                for c in map(tuple, rgb[al > 32]):
                    pool[c] += 1

        pal = build_palette(pool, args.colors, args.weight_exp)
        pal_lab = to_oklab(pal)

        b_cols, b_iso, b_flick = measure(loaded)

        # --- 2. remap + despeckle, animaci po animaci
        # Po remapu existuje uz jen 16 barev, takze Oklab staci spocitat jednou
        # dopredu misto pro kazdy pixel zvlast.
        lab_of = {tuple(c): l for c, l in zip(map(tuple, pal), pal_lab)}

        cleaned, changed, kept = {}, 0, 0
        for suffix, fr in loaded.items():
            step = [(remap(rgb, al > 32, pal, pal_lab), al) for rgb, al in fr]
            if args.despeckle < 9:
                out = []
                for rgb, al in step:
                    r2, n, k = despeckle(rgb, al > 32, lab_of, args.despeckle, args.detail)
                    changed += n
                    kept += k
                    out.append((r2, al))
                step = out
            cleaned[suffix] = step

        a_cols, a_iso, a_flick = measure(cleaned)
        tot_changed += changed

        print(f"{base:<20}{b_cols:>6} -> {a_cols:<5}{b_iso:>10.0f}% -> {a_iso:<4.0f}%"
              f"{b_flick:>9.1f}% -> {a_flick:<4.1f}%{changed:>9}{kept:>8}")

        # --- 3. zapis
        for suffix, files in anims.items():
            for (src_path, _), (rgb, al) in zip(files, cleaned[suffix]):
                save(os.path.join(dest, os.path.basename(src_path)), rgb, al)

        if not args.apply:
            for suffix in sorted(anims):
                tag = base + (suffix or "_south")
                contact_sheet(loaded[suffix], cleaned[suffix],
                              os.path.join(PREVIEW, f"{tag}.png"))
                compare_gif(loaded[suffix], cleaned[suffix],
                            os.path.join(PREVIEW, f"{tag}.gif"))

    print(f"\ncelkem prepsano {tot_changed} osamocenych pixelu")
    if args.apply:
        print("assets/distractions/ PREPSANO - zkontroluj `git diff --stat` a hru.")
    else:
        print(f"nahledy: {os.path.relpath(PREVIEW, PROJ)}  (GIFy ukazou blikani, "
              f"kontaktni listy detail)")
        print("az to bude sedet:  python tools/sprite_cleanup.py --apply "
              + (f"--colors {args.colors} " if args.colors != 16 else "")
              + (f"--despeckle {args.despeckle} " if args.despeckle != 5 else "")
              + (f"--detail {args.detail}" if args.detail != 0.12 else ""))


if __name__ == "__main__":
    main()
