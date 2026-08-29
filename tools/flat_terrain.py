# Prepise iso teren na PLOCHY styl ("Rogue Tower"): zadna textura, jen ploche barvy.
#
# PROC TO JDE UDELAT BEZPECNE
#
# U kazdeho souboru se ZACHOVA PRESNA ALFA a prebarvi se jen RGB. Silueta dlazdice se
# tim nemuze zmenit ani o pixel, takze nemuzou vzniknout spary ani posuny -- coz je
# jediny zpusob, jak menit teren bez rizika, ze se rozejde s mrizkou (viz historie
# TERRAIN_ART_PX v data.gd).
#
# PROC PLOCHE
#
# Zmereno 21. 8. 2026: hlucny povrch se pri dlazdeni 3x3 rozpadne na mrizku opakovanych
# hrbolu. Plocha plocha ten problem nema z definice -- neni co opakovat. Vyska se cte
# z pomeru vrch : levy bok : pravy bok = 100 : 70 : 45 (docs/art/iso_bible.md kap. 2),
# a ten ploche barvy trefi presne, protoze je to prosté nasobeni jedne barvy.
#
#   python tools/flat_terrain.py                 # vychozi: linka jen na podlaze
#   python tools/flat_terrain.py --edge none     # ani na podlaze
#   python tools/flat_terrain.py --edge all      # linka vsude
#   python tools/flat_terrain.py --restore       # vrati zalohu
#
# POUCENI 21. 8. 2026: prvni verze mela linku VSUDE a uzivatel to hned poznal ("ten
# povrch je viditelne oddeleny nejakou texturou, jakoze hranou"). Na TERASE je linka
# vada: masiv se rozpadne na dlazdenou podlahu a souvisla stena na svisle panely, cimz
# prestane cist jako teleso -- a prave to je jedina informace, kterou terasa nese.
# Stavebni bloky 3x3 uz navic znaci tecky v _draw_static_field(), takze linka tu
# informaci nenesla ani nahodou.
#
# Na PODLAZE jsem ji nechal s tim, ze da "mericko vzdalenosti". Uzivatel ji o kolo pozdeji
# nahlasil znovu, a spravne: cetla jako MEZERY mezi dlazdicemi, ne jako mrizka. Duvod je
# v geometrii -- alfa dlazdice neni ciste 2:1 (radky rostou po 6 px misto po 4), takze se
# sousedi PREKRYVAJI (zmereno: 0 der, 2720 prekryvajicich se pixelu). Tmavy lem jedne
# dlazdice tim padem lezi na vnitrku sousedni a vznikne tmava mriz.
#
# Skutecne mezery to nejsou a nikdy nebyly. Proto vychozi "none".
import argparse
import os
import shutil
import sys

import numpy as np
from PIL import Image

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ISO = os.path.join(PROJ, "assets", "terrain", "iso")
BACKUP = os.path.join(PROJ, "build", "_flat_backup")

# Barvy se NEVYMYSLEJI: berou se z dnesniho artu a z pasem v bibli, aby se menila
# hlucnost, ne paleta.
# Zem: dnesni art mel soucet 51, coz je POD pasmem, ktere bible predepisuje (60-110).
# Pri ploche podlaze to zacne vadit: skok zem -> pruh byl 2,9x a pruh cetl jako druha
# nejvyraznejsi plocha na desce hned po terase. Na 78 je skok 1,9x a poradi zustane
# terasa > pruh > zem, jak ma byt.
GROUND = (20, 17, 41)      # soucet 78 -- spodni tretina pasma 60-110
LANE = (78, 52, 16)        # jantar, soucet 146 -- bible chce pasmo 120-160
TOP = (184, 165, 135)      # median vrchu dnesni terasy, soucet 484
K_LEFT, K_RIGHT = 0.70, 0.45

## Jak tmava je linka na okraji dlazdice. Bez ni splynou sousedni bunky v jednu plochu a
## nejde poznat, kde jsou stavebni bloky 3x3 -- presne to Rogue Tower resi tenkou linkou.
EDGE_K = 0.72


def _edge_mask(alpha):
    """Pixely, ktere sousedi s pruhlednem -- obrys dlazdice, sirka 1 px."""
    p = np.pad(alpha, 1, constant_values=False)
    inner = (p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:])
    return alpha & ~inner


def paint(path, faces, edge=True):
    """faces: seznam (maska, rgb). Alfa zustava presne jak byla."""
    im = Image.open(path).convert("RGBA")
    a = np.array(im)
    alpha = a[..., 3] > 8
    out = a.copy()
    for mask, rgb in faces:
        m = mask & alpha
        if not m.any():
            continue
        out[..., :3][m] = np.array(rgb, dtype=np.uint8)
    if edge:
        em = _edge_mask(alpha)
        out[..., :3][em] = (out[..., :3][em].astype(float) * EDGE_K).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(path)


def faces_of(path):
    """Vrch / levy bok / pravy bok podle geometrie kosoctverce -- tatáž jako iso_faces.py."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import iso_faces
    a = np.array(Image.open(path).convert("RGBA"))
    alpha = a[..., 3] > 8
    ys, xs = np.where(alpha)
    x0, y0, w = xs.min(), ys.min(), xs.max() - xs.min() + 1
    return iso_faces._faces(a, x0, y0, w, w / 2.0)


def scale(rgb, k):
    return tuple(int(min(255, round(v * k))) for v in rgb)


def backup():
    if os.path.isdir(BACKUP):
        print(f"zaloha uz existuje: {os.path.relpath(BACKUP, PROJ)} (nechavam)")
        return
    for d in ("ground", "lane", "terrace"):
        src, dst = os.path.join(ISO, d), os.path.join(BACKUP, d)
        os.makedirs(dst, exist_ok=True)
        for f in os.listdir(src):
            if f.endswith(".png"):
                shutil.copy2(os.path.join(src, f), os.path.join(dst, f))
    print(f"zaloha -> {os.path.relpath(BACKUP, PROJ)}")


def restore():
    if not os.path.isdir(BACKUP):
        raise SystemExit("zadna zaloha")
    n = 0
    for d in ("ground", "lane", "terrace"):
        for f in os.listdir(os.path.join(BACKUP, d)):
            shutil.copy2(os.path.join(BACKUP, d, f), os.path.join(ISO, d, f))
            n += 1
    print(f"vraceno {n} souboru z zalohy")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--edge", choices=["all", "floor", "none"], default="none",
                    help="kde kreslit tmavou linku po bunce: vsude / jen podlaha / nikde")
    ## O kolik je akcentova dlazdice svetlejsi nez zakladni. Puvodne 1,35 -- na hladke
    ## podlaze z toho byly viditelne schody mezi svetlejsimi a tmavsimi ostrovy. 1,12 je
    ## jen naznak, aby plocha nebyla uplne mrtva.
    ap.add_argument("--accent", type=float, default=1.12)
    ap.add_argument("--restore", action="store_true")
    a = ap.parse_args()
    if a.restore:
        restore()
        return
    backup()
    edge_floor = a.edge in ("all", "floor")
    edge_terrace = a.edge == "all"

    n = 0
    # --- zem: osm odstinu tehoz tonu, at plocha neni uplne mrtva, ale zustane ticha
    for i in range(8):
        for name, base, spread in (("ground_%02d" % i, GROUND, 1.0),
                                   ("ground_accent_%02d" % i, GROUND, a.accent)):
            p = os.path.join(ISO, "ground", name + ".png")
            if not os.path.isfile(p):
                continue
            k = spread * (0.94 + 0.02 * (i % 4))
            full = np.ones((1, 1), bool)
            im = Image.open(p)
            paint(p, [(np.ones((im.height, im.width), bool), scale(base, k))], edge_floor)
            n += 1

    # --- pruh: jeden jantar na vsechny masky. Rozdil mezi maskami byl informace, kterou
    # nesla TEXTURA; ploche pojeti ji nese tvarem souvisle plochy, takze masky prestanou
    # byt videt a pruh cte jako jedna cesta misto jako sada dilku.
    for f in sorted(os.listdir(os.path.join(ISO, "lane"))):
        if not f.endswith(".png"):
            continue
        p = os.path.join(ISO, "lane", f)
        im = Image.open(p)
        paint(p, [(np.ones((im.height, im.width), bool), LANE)], edge_floor)
        n += 1

    # --- terasa: tri plochy, pomer 100 : 70 : 45, svetlo zleva
    bp = os.path.join(ISO, "terrace", "block.png")
    top, left, right = faces_of(bp)
    paint(bp, [(top, TOP), (left, scale(TOP, K_LEFT)), (right, scale(TOP, K_RIGHT))], edge_terrace)
    n += 1
    cp = os.path.join(ISO, "terrace", "cap.png")
    im = Image.open(cp)
    paint(cp, [(np.ones((im.height, im.width), bool), TOP)], edge_terrace)
    n += 1

    print(f"prebarveno {n} souboru na plochy styl (edge={a.edge})")


if __name__ == "__main__":
    main()
