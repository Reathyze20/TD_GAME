# Zmeri iso blok tak, jak ho soudi bible: vyska boku a pomer vrch : levy bok : pravy bok.
#
# PROC SAMOSTATNY NASTROJ
#
# `pl_iso.py check` rekne medianovy jas cele dlazdice, coz u bloku nic neznamena --
# vrch a dva boky se v jednom cisle zprumeruji. Bible (docs/art/iso_bible.md, kap. 2)
# ale predepisuje POMER mezi tremi plochami (100 : 70 : 45) a vysku boku, protoze prave
# vyska nese informaci "sem se da stavet".
#
# Tenhle projekt uz jednou stalo kolo prace to, ze se pomer zmeril spatne: rozdelenim
# na vodorovna pasma misto na levou a pravou stenu vyslo "boky jsou stejne" (100:66:66),
# coz vedlo k objednavani noveho artu misto k prebarveni stavajiciho. Skutecna hodnota
# byla 100:83:62. Proto se tady plochy oddeluji GEOMETRII kosoctverce, ne odhadem.
#
#   python tools/iso_faces.py <soubor.png> [dalsi.png ...]
#   python tools/iso_faces.py --regrade <vstup.png> <vystup.png>
#
# `--regrade` posadi boky na predepsany pomer vynasobenim jasu. Pouziva TUTEZ geometrii
# jako mereni, aby nesly rozejit -- prave to je duvod, proc regrade neni zvlastni skript.
# Vrch se nedotyka: ten urcuje pasmo "sem se da stavet" a menit ho znamena menit bibli.
import sys

import numpy as np
from PIL import Image

TARGET = (100.0, 70.0, 45.0)


def measure(path):
    im = Image.open(path).convert("RGBA")
    a = np.array(im)
    alpha = a[..., 3] > 8
    if not alpha.any():
        return None
    ys, xs = np.where(alpha)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    w = x1 - x0 + 1
    h_top = w / 2.0                      # iso 2:1 -- vrchni kosoctverec je vzdy sirka/2

    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    fx = (xx - (x0 + (w - 1) / 2.0)) / (w / 2.0)
    fy = (yy - (y0 + (h_top - 1) / 2.0)) / (h_top / 2.0)
    diamond = (np.abs(fx) + np.abs(fy)) <= 1.0

    rgb = a[..., :3].astype(int).sum(2)
    top = alpha & diamond
    skirt = alpha & ~diamond
    left = skirt & (xx < x0 + w / 2.0)
    right = skirt & (xx >= x0 + w / 2.0)

    def med(m):
        return float(np.median(rgb[m])) if m.any() else 0.0

    t, l, r = med(top), med(left), med(right)
    return dict(
        name=path, canvas=(im.width, im.height), content=(w, y1 - y0 + 1),
        skirt=int(round(y1 - (y0 + h_top - 1))),
        top=t, left=l, right=r,
        ratio=(100.0, 100.0 * l / t if t else 0, 100.0 * r / t if t else 0),
        px=(int(top.sum()), int(left.sum()), int(right.sum())),
    )


def _faces(a, x0, y0, w, h_top):
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    fx = (xx - (x0 + (w - 1) / 2.0)) / (w / 2.0)
    fy = (yy - (y0 + (h_top - 1) / 2.0)) / (h_top / 2.0)
    diamond = (np.abs(fx) + np.abs(fy)) <= 1.0
    alpha = a[..., 3] > 8
    left = alpha & ~diamond & (xx < x0 + w / 2.0)
    right = alpha & ~diamond & (xx >= x0 + w / 2.0)
    return alpha & diamond, left, right


def regrade(src, dst):
    """Vynasobi levou a pravou stenu tak, aby vysly na TARGET vuci vrchu."""
    im = Image.open(src).convert("RGBA")
    a = np.array(im).astype(float)
    alpha = a[..., 3] > 8
    ys, xs = np.where(alpha)
    x0, y0, w = xs.min(), ys.min(), xs.max() - xs.min() + 1
    top, left, right = _faces(np.array(im), x0, y0, w, w / 2.0)
    rgb = a[..., :3].sum(2)
    t = float(np.median(rgb[top]))
    for mask, want in ((left, TARGET[1]), (right, TARGET[2])):
        cur = float(np.median(rgb[mask]))
        if cur <= 0:
            continue
        k = (want / 100.0 * t) / cur
        a[..., :3][mask] = np.clip(a[..., :3][mask] * k, 0, 255)
    Image.fromarray(a.astype("uint8"), "RGBA").save(dst)
    print(f"regrade {src} -> {dst}")


def main():
    if sys.argv[1:2] == ["--regrade"]:
        regrade(sys.argv[2], sys.argv[3])
        measure_print(sys.argv[3])
        return
    for p in sys.argv[1:]:
        measure_print(p)


def measure_print(p):
        m = measure(p)
        if m is None:
            print(f"{p}: prazdne")
            return
        rt, rl, rr = m["ratio"]
        svetlo = "zleva" if rl > rr + 4 else ("zprava" if rr > rl + 4 else "ploche")
        odchylka = max(abs(rl - TARGET[1]), abs(rr - TARGET[2]))
        print(f"{m['name']}")
        print(f"  platno {m['canvas'][0]}x{m['canvas'][1]}  obsah {m['content'][0]}x{m['content'][1]}"
              f"  bok {m['skirt']} px")
        print(f"  vrch {m['top']:.0f}  levy {m['left']:.0f}  pravy {m['right']:.0f}"
              f"   (px {m['px'][0]}/{m['px'][1]}/{m['px'][2]})")
        print(f"  POMER {rt:.0f} : {rl:.0f} : {rr:.0f}   bible chce 100 : 70 : 45"
              f"   svetlo {svetlo}   odchylka {odchylka:.0f}")


if __name__ == "__main__":
    main()
