"""Dorovnani zbytku artu na rastr 24 px na bunku (meritko x2).

    python tools/raster_to_24.py            # ukaze, co by udelal
    python tools/raster_to_24.py --apply

PROC TENHLE KROK EXISTUJE

tools/raster_x2.py zvetsil vsechen art x2 v domnence, ze se ma zdvojnasobit rozliseni
pri zachovanem meritku x3. To byla chyba v zadani: pixel na obrazovce zustal tri
pixely siroky a misto jemnejsi kresby z toho byly o tretinu vetsi prisery.

Sprava je v Data.TERRAIN_ART_PX: 24 px artu na bunku pri bunce 48 px obrazovky, tedy
meritko x2. Pixel na obrazovce je tim o tretinu mensi, deska i rozhrani zustavaji.

Art musi na tenhle rastr dosednout. Puvodni velikost byla A pri x3, po raster_x2 je
2A pri x2 -- na obrazovce tedy 4A/3, o tretinu vic. Cil je 1.5A, aby na obrazovce
vyslo zase 3A. Odtud faktor 0.75.

    veze      48/64/80  ->  36/48/60
    obranci   64        ->  48
    dekorace  32        ->  24
    dlazdice  32        ->  24   (cesty i celni steny)

Prisery uz tudy nesly -- ty se nainstalovaly znovu z knihovny (tools/install_local.py),
coz je lepsi cesta: bere se nativni 64px original, ne dvakrat prepocitany sprite.
Veze a dekorace zadny takovy zdroj nemaji, proto zmenseni.

CO SE (NE)DELA S OBRYSEM

Retez, ktery se meril jako nejlepsi pro 64 -> 48, byl NEAREST -> clean -> outline_sprite.
Tady je outline_sprite VYNECHANY zamerne: veze a dekorace uz svuj obrys maji a druhy
prstenec by kolem nich udelal dvojitou linku. clean() zustava -- srovna paletu, kterou
zmenseni rozstrili.
"""
from __future__ import annotations

import argparse
import glob
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FAKTOR = 0.75

# (vzorec, rozpocet barev). Rozpocet je nizsi u drobnych veci: dlazdice cesty ma
# 24x24 px a dvacet barev v ni uz neni odstineni, ale sum.
# (vzorec, rozpocet barev, preskocit-uz-hotove).
#
# Posledni pole je jen pro DISTRAKCE. Vetsina z nich uz je preinstalovana z knihovny
# rovnou v 48 px (tools/install_local.py) a druhe zmenseni by je zabilo; zbytek
# (boss na 128, adult_content na 64) tudy jeste musi projit. Poznaji se podle strany:
# 48 a 96 jsou cele nasobky bunky, 64 a 128 nejsou.
#
# U VEZI se tenhle filtr pouzit NESMI, i kdyz 48 nasobek je: veze mely odjakziva
# 1.5 bunky (24 px pri x3) a maji ji mit dal, tedy 36 px pri x2. Kdyby se "uz sedi"
# vztahlo i na ne, zustaly by o tretinu vetsi -- coz je presne to, ceho si uzivatel
# vsiml.
SKUPINY = [
    ("assets/towers/**/*.png", 24, False),
    ("assets/defenders/**/*.png", 24, False),
    ("assets/decor/**/*.png", 16, False),
    ("assets/markers/**/*.png", 16, False),
    ("assets/terrain/path/**/*.png", 16, False),
    ("assets/terrain/face/**/*.png", 16, False),
    ("assets/distractions/*.png", 24, True),
]

# Soubory, ktere se tvari jako PNG a nejsou to PNG (JPEG s prehozenou priponou, v repu
# od prvniho commitu). Hra je nenacita a Pillow je precte, takze by se tise "prevedly"
# na neco, co uz nikdo nepotrebuje.
MRTVE = {"phantom_buzz_spritesheet.png"}


def _uz_sedi(w: int, h: int) -> bool:
    return w % 24 == 0 and h % 24 == 0


def zmensi(path: str, colors: int, apply: bool, preskocit_hotove: bool):
    if os.path.basename(path) in MRTVE:
        return None
    with Image.open(path) as im:
        w, h = im.size
        if preskocit_hotove and _uz_sedi(w, h):
            return None
        nw, nh = max(1, round(w * FAKTOR)), max(1, round(h * FAKTOR))
        if not apply:
            return w, h, nw, nh
        a = np.array(im.convert("RGBA").resize((nw, nh), Image.NEAREST))
    a = gen.clean(a, colors)
    Image.fromarray(a, "RGBA").save(path)
    return w, h, nw, nh


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Dorovnani artu na 24 px na buňku.")
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args(argv)

    print(f"{'ZAPISUJI' if args.apply else 'ZKUŠEBNÍ BĚH'} — faktor ×{FAKTOR}\n")
    celkem = 0
    for vzorec, colors, preskocit in SKUPINY:
        zmeny: dict[str, int] = {}
        for p in glob.glob(os.path.join(PROJ, vzorec), recursive=True):
            r = zmensi(p, colors, args.apply, preskocit)
            if r is None:
                continue
            w, h, nw, nh = r
            k = f"{w}×{h} → {nw}×{nh}"
            zmeny[k] = zmeny.get(k, 0) + 1
            celkem += 1
        if zmeny:
            skupina = vzorec.split("/**")[0].replace("assets/", "")
            popis = ", ".join(f"{v}× {k}" for k, v in sorted(zmeny.items(), key=lambda kv: -kv[1]))
            print(f"  {skupina:<16} {popis}   (paleta {colors})")

    print(f"\n  celkem: {celkem} souborů")
    if not args.apply:
        print("\nNic se nezapsalo. Spusť s --apply.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
