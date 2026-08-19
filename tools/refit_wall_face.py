# -*- coding: utf-8 -*-
"""Prevede dlazdice celni steny zdi na rastr x1 (24x12 art -> 16x24 art).

    python tools/refit_wall_face.py [--apply]

PROC TO NEJDE NECHAT BYT

Celo zdi kresli kod (class WallFace v game.gd) do bunky POD zdi, obdelnikem
`tile x WALL_FACE_H`. Pri bunce 48 px to bylo 48x24 obrazovky z artu 24x12, tedy x2.
Po zjemneni mrizky (18. 8. 2026) je bunka 16 px, takze tyz obdelnik je 16x24 -- a art
24x12 se do nej natahoval nerovnomerne (uzsi a zaroven vyssi). Na snimku to delalo
hreben pod kazdou zdi.

CO SE DELA A CO SE TIM ZTRACI

  sirka   24 -> 16   NEAREST, tedy se kazdy treti sloupec zahodi. Material steny je sum,
                     takze se to nepozna; kresba tam zadna neni.
  vyska   12 -> 24   presne x2, takze svetelny pruh po vysce (LIGHT_TOP -> LIGHT_BOTTOM
                     v build_wall_face.py) se zachova bez interpolace.

Vysledek je 16x24 artu kresleneho 1:1, cili x1 jako zbytek sveta, a stena zustava na
obrazovce presne tak vysoka (24 px) jako pred zjemnenim.

SPRAVNE BY SE MELA PREGENEROVAT ROVNOU V 16x24, ne prepocitavat. Zdrojove pruhy
z generatoru uz ale v repu nejsou (assets/src/ je nema), takze tohle je nejlepsi, co
jde udelat z toho, co je na disku. Az budou zdroje, spust build_wall_face.py
s ART_W, ART_H = 16, 24 a ZOOM = 1.
"""
import glob
import os
import shutil
import sys

from PIL import Image

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FACE_DIR = os.path.join(PROJ, "assets", "terrain", "face")
NEW_W, NEW_H = 16, 24

apply = "--apply" in sys.argv
files = sorted(glob.glob(os.path.join(FACE_DIR, "*.png")))
if not files:
    sys.exit("v %s nejsou zadne dlazdice" % FACE_DIR)

for f in files:
    im = Image.open(f).convert("RGBA")
    if im.size == (NEW_W, NEW_H):
        print("  %-14s uz je %dx%d, preskakuji" % (os.path.basename(f), NEW_W, NEW_H))
        continue
    # Dva kroky, ne jeden resize: vyska musi jit presne x2 (bez interpolace), sirka se
    # jen proredi. Jednim volanim by se obe osy michaly do stejneho filtru.
    tall = im.resize((im.width, im.height * 2), Image.NEAREST)
    out = tall.resize((NEW_W, NEW_H), Image.NEAREST)
    print("  %-14s %s -> %s" % (os.path.basename(f), im.size, out.size))
    if apply:
        bak = f + ".bak_x2"
        if not os.path.exists(bak):
            shutil.copy2(f, bak)
        out.save(f)

print("zapsano" if apply else "(nic se nezapsalo, spust s --apply)")
