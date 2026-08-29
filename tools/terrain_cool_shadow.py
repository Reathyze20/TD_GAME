# Terén: posun stínu do chladna, ne přebarvení materiálu.
#
# CO SE ZMĚŘILO (tools/style_audit.py --only terrain, 19. 8. 2026):
#
#   path/*.png (podlaha)   hue shift 2.2-4.2°   medián sum(RGB) 77-100
#   high_ground_atlas.png  hue shift 8.7°       medián sum(RGB) 145
#   face/*.png (čelo zdi)  hue shift 10.8-11.2° medián sum(RGB) 124-145
#
# Cíl je 20°+ (style_bible_measured.md, stejný práh jako věže/distrakce/obránci). Rozbor palety
# ukázal PROČ je to nízké: světlé i tmavé tóny leží skoro na STEJNÉM odstínu (~257-290°,
# tedy modro-fialová) — liší se jen jasem. To je přesně "ztmavování do černé": stín
# NEMĚNÍ odstín, jen snižuje L. Není to tedy jiný materiál, který chybí — je to rotace,
# která chybí.
#
# OPRAVA je čistě post-process, žádná nová generace v PixelLabu:
#   1. Existující barvy (celá paleta path/face, resp. atlas) se převedou do Oklabu.
#   2. Podle toho, jak tmavý je pixel v RÁMCI SVÉ SKUPINY (path dohromady, face dohromady,
#      atlas zvlášť), se odstín pootočí o 0..ROT_MAX stupňů — světlé pixely skoro vůbec,
#      nejtmavší nejvíc (ROT_MAX * t**GAMMA). Small chroma boost na nejtmavších, aby
#      rotace byla vůbec vidět (chroma u zdrojových stínů je 0.02-0.06 -- nízko).
#   3. L (jas) se NEMĚNÍ. Rozpočet jasu (style_bible, PIXELLAB.md §terrain) se tímhle
#      krokem netýká -- mění se barva stínu, ne kolik světla je ve scéně.
#
# Proč rotace k VYŠŠÍMU úhlu (směr fialová), ne k nižšímu (směr azurová): světlé tóny už
# dnes leží kolem 257-265°, což je v Oklabu "čistá modrá". Posun stínu dál stejným směrem
# by splynul s barvou samotnou; posun opačným směrem (k fialové, ~290-305°) je to, co
# PIXELLAB.md a style_bible popisují frází "shadow tones shift toward cool blue/violet" --
# světlo je modré, stín je HLUBŠÍ, fialovější modrá. Obojí zůstává v modro-fialové rodině,
# takže materiál se nemění, jen získá směr.
#
# Pouziti:
#   python tools/terrain_cool_shadow.py            # nahled: 1 podlahova + 1 celo zdi,
#                                                    # zmereno pred/po, ulozeno do build/
#   python tools/terrain_cool_shadow.py --all       # cely path/, cele face/, atlas
#   python tools/terrain_cool_shadow.py --all --apply   # a prepsat assets/terrain/
import argparse
import os
import sys
from collections import Counter

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sprite_cleanup import to_oklab, _M1, _M2               # noqa: E402
from style_audit import hue_shift, outline_strength          # noqa: E402

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH_DIR = os.path.join(PROJ, "assets", "terrain", "path")
FACE_DIR = os.path.join(PROJ, "assets", "terrain", "face")
ATLAS_PATH = os.path.join(PROJ, "assets", "terrain", "high_ground_atlas.png")
BUILD = os.path.join(PROJ, "build", "terrain_cool_shadow")

ROT_MAX = 44.0       # stupnu na nejtmavsim pixelu skupiny
GAMMA = 1.25         # >1 = rotace se soustredi do skutecne tmave casti, stred se nehne
CHROMA_BOOST = 0.35  # nejtmavsi pixely dostanou az +35% sytosti, jinak by rotace nebyla videt
CHROMA_CAP = 0.095   # strop, aby stin nezacal svitit (matte, low contrast musi drzet)

_M1_INV = np.linalg.inv(_M1)
_M2_INV = np.linalg.inv(_M2)


def from_oklab(lab: np.ndarray) -> np.ndarray:
    """Oklab (...,3) -> sRGB 0-255 (...,3), float, NEKLAMOVANO (klamej az pri ukladani)."""
    lms = lab @ _M2_INV.T
    lms = lms ** 3
    lin = lms @ _M1_INV.T
    srgb = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.clip(lin, 0, None) ** (1 / 2.4) - 0.055)
    return srgb * 255.0


def cool_shift_colors(colors_rgb: np.ndarray) -> np.ndarray:
    """N x 3 uint8 -> N x 3 uint8, rotovano do chladna podle relativni tmavosti UVNITR
    tehle mnoziny barev. Pouziva se na CELOU skupinu (vsechny path dohromady, vsechny
    face dohromady), aby sousedni dlazdice sdilely stejnou rotacni krivku a nevznikaly
    mezi nimi svy."""
    lab = to_oklab(colors_rgb.astype(np.float64))
    L = lab[:, 0]
    lo, hi = L.min(), L.max()
    t = np.clip((hi - L) / max(hi - lo, 1e-6), 0.0, 1.0)     # 0 = nejsvetlejsi, 1 = nejtmavsi
    rot = np.radians(ROT_MAX * t ** GAMMA)

    chroma = np.hypot(lab[:, 1], lab[:, 2])
    hue = np.arctan2(lab[:, 2], lab[:, 1])
    new_hue = hue + rot
    new_chroma = np.minimum(chroma * (1.0 + CHROMA_BOOST * t), CHROMA_CAP)

    new_lab = lab.copy()
    new_lab[:, 1] = new_chroma * np.cos(new_hue)
    new_lab[:, 2] = new_chroma * np.sin(new_hue)
    # L se nemeni -- meni se jen kam barva miri v (a,b) rovine.

    out = from_oklab(new_lab)
    return np.clip(np.round(out), 0, 255).astype(np.uint8)


def remap_image(im: Image.Image, mapping: dict) -> Image.Image:
    """Presny remap barva->barva pres slovnik (zadne mixovani, zadny novy pixel)."""
    a = np.array(im.convert("RGBA"))
    out = a.copy()
    for (r, g, b), (nr, ng, nb) in mapping.items():
        m = (a[..., 0] == r) & (a[..., 1] == g) & (a[..., 2] == b) & (a[..., 3] > 0)
        out[..., 0][m] = nr
        out[..., 1][m] = ng
        out[..., 2][m] = nb
    return Image.fromarray(out, "RGBA")


def build_group_mapping(paths):
    """Sjednoceny pool barev pres vsechny soubory skupiny -> {rgb: novy_rgb}."""
    pool = Counter()
    for p in paths:
        a = np.array(Image.open(p).convert("RGBA"))
        m = a[..., 3] > 32
        for c in map(tuple, a[..., :3][m]):
            pool[c] += 1
    colors = np.array(list(pool.keys()), dtype=np.uint8)
    new_colors = cool_shift_colors(colors)
    return {tuple(int(v) for v in c): tuple(int(v) for v in n) for c, n in zip(colors, new_colors)}


def measure(path):
    a = np.array(Image.open(path).convert("RGBA"))
    m = a[..., 3] > 32
    med = float(np.median(a[..., :3][m].astype(np.int64).sum(axis=1))) if m.any() else float("nan")
    return hue_shift(a), med


def process_group(name, paths, apply_):
    os.makedirs(BUILD, exist_ok=True)
    mapping = build_group_mapping(paths)
    print(f"\n{name}: {len(paths)} soubor(u), {len(mapping)} barev v poolu")
    for p in paths:
        im = Image.open(p).convert("RGBA")
        out = remap_image(im, mapping)
        h0, med0 = measure(p)
        dst_preview = os.path.join(BUILD, os.path.basename(p))
        out.save(dst_preview)
        a1 = np.array(out)
        h1 = hue_shift(a1)
        m1 = a1[..., 3] > 32
        med1 = float(np.median(a1[..., :3][m1].astype(np.int64).sum(axis=1)))
        print(f"  {os.path.basename(p):<16} hue {h0:5.1f}° -> {h1:5.1f}°   "
              f"medián sum(RGB) {med0:5.1f} -> {med1:5.1f}")
        if apply_:
            out.save(p)
    return mapping


def process_atlas(apply_):
    os.makedirs(BUILD, exist_ok=True)
    im = Image.open(ATLAS_PATH).convert("RGBA")
    a = np.array(im)
    m = a[..., 3] > 32
    colors = np.array(sorted({tuple(c) for c in map(tuple, a[..., :3][m])}), dtype=np.uint8)
    new_colors = cool_shift_colors(colors)
    mapping = {tuple(int(v) for v in c): tuple(int(v) for v in n) for c, n in zip(colors, new_colors)}
    out = remap_image(im, mapping)
    h0, med0 = measure(ATLAS_PATH)
    dst_preview = os.path.join(BUILD, "high_ground_atlas.png")
    out.save(dst_preview)
    a1 = np.array(out)
    h1 = hue_shift(a1)
    m1 = a1[..., 3] > 32
    med1 = float(np.median(a1[..., :3][m1].astype(np.int64).sum(axis=1)))
    print(f"\nATLAS ({len(mapping)} barev v poolu): hue {h0:.1f}° -> {h1:.1f}°   "
          f"medián sum(RGB) {med0:.1f} -> {med1:.1f}")
    if apply_:
        out.save(ATLAS_PATH)
    return mapping


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true", help="cely path/ + cele face/ + atlas "
                     "(bez toho jen 1 podlahova dlazdice + 1 celo zdi, test)")
    ap.add_argument("--apply", action="store_true", help="prepsat assets/terrain/ "
                     "(bez toho jen build/terrain_cool_shadow/)")
    ap.add_argument("--atlas", action="store_true", help="jen atlas (s --all zahrnut vzdy)")
    args = ap.parse_args()

    if args.apply and not args.all:
        raise SystemExit("--apply bez --all by prepsal jen testovaci soubory -- "
                          "pridej --all, nebo spust bez --apply.")

    path_files = sorted(os.path.join(PATH_DIR, f) for f in os.listdir(PATH_DIR)
                        if f.endswith(".png"))
    face_files = sorted(os.path.join(FACE_DIR, f) for f in os.listdir(FACE_DIR)
                        if f.endswith(".png") and "bak" not in f)

    if not args.all:
        path_files = path_files[:1]
        face_files = face_files[:1]
        print("REZIM TEST: 1 podlahova dlazdice + 1 celo zdi (--all pro celou sadu)")

    process_group("PATH (podlaha)", path_files, args.apply)
    process_group("FACE (celo zdi)", face_files, args.apply)
    if args.all or args.atlas:
        process_atlas(args.apply and args.all)

    print(f"\nnahledy v {os.path.relpath(BUILD, PROJ)}" + (" (a zapsano do assets/)" if args.apply else ""))


if __name__ == "__main__":
    main()
