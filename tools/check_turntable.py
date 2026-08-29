# Overi, jestli osmismerna sada je OTOCNY STUL, nebo jen osm variaci.
#
# PROC TAHLE MIRA A NE UHEL HLAVNE
#
# 22. 8. 2026 jsem na tomtez problemu spalil dve merid1a. Obe pocitala uhel hlavne --
# jedno z teziste mosazi, druhe z nejvzdalenejsiho mosazneho pixelu -- a neshodla se:
# prvni reklo "obrat 307 stupnu" (skoro cely), druhe "0 stupnu" (zadny). Duvod je u
# obou stejny: mosaz neni jen hlaven, je z ni i prstenec, a ten je v kazdem snimku jinde.
#
# Tahle mira se hlavne vubec nedota. Mericka otazka se otoci naruby: otocny stul ma osm
# RUZNYCH snimku. Kdyz jsou dva skoro stejne, sada je vadna, at uz hlaven miri kamkoli.
# To je presne ta vada, ktera se pozna okem ("nektere smery neodpovidaji") -- jen ted
# ma cislo.
#
# KALIBRACE na dvou znamych sadach teze veze (namereno, ne odhadnuto):
#
#                                      nejnizsi dvojice   dvojic pod 0,040
#   sada 1 (nozky, poctivy otocny stul)      0,041               0
#   sada 3 (prstenec, ctyri duplikaty)       0,032               2
#
# Brana je POCET dvojic pod prahem, ne to nejnizsi cislo: samotne minimum deli obe sady
# jen o 0,009, kdezto pocet je 0 proti 2. Odpovida to i tomu, co bylo videt okem --
# vadna nebyla jedna dvojice, ale ctyri snimky, ktere splynuly dohromady.
#
# POZOR: kalibrovano na DVOU sadach. Je to nejlepsi hranice, jakou zatim mame, ne
# univerzalni konstanta -- s dalsimi vezemi ji prepocitej.
#
# DRUHA BRANA: `sheet` -- MIRI TAM, KAM SLIBUJE JMENO?
#
# Odlisnost snimku je nutna, ne postacujici. Sada muze mit osm ruznych pohledu a pritom
# spatne prirazena jmena, nebo ji muzou nektere pozy uplne chybet. Zmereno 22. 8. 2026:
# jedna sada prosla branou odlisnosti a presto mela `south-east` i `south-west` hlaven
# NAHORU misto dolu k divakovi -- generator ji v te sade nikdy nesklopil ke kamere.
#
# Tohle vykresli osm nainstalovanych spritu a pres kazdy nakresli sipku smeru, ktery
# jeho jmeno slibuje (tower.gd mapuje screen_aim 0 stupnu na "east", pak po 45). Sipka
# a hlaven se musi shodovat. Odpoved da oko za pet sekund; automat by potreboval
# spolehlivy detektor hlavne, a ten se mi dvakrat nepovedl (viz hlavicka vyse).
#
#   python tools/check_turntable.py build/iso_art/obj_focus_timer
#   python tools/check_turntable.py sheet focus_timer
import os
import sys

import numpy as np
from PIL import Image

DIRS = ["east", "south-east", "south", "south-west",
        "west", "north-west", "north", "north-east"]
THRESHOLD = 0.040


def load(d):
    out = []
    for n in DIRS:
        p = os.path.join(d, n + ".png")
        if not os.path.isfile(p):
            raise SystemExit("chybi %s" % p)
        a = np.asarray(Image.open(p).convert("RGBA")).astype(float) / 255.0
        # Alpha se pronasobi do barev, aby prazdno bylo prazdno a ne cerna.
        out.append(a[..., :3] * a[..., 3:4])
    return out


def check(d):
    ims = load(d)
    n = len(ims)
    worst = (1.0, None)
    print("%-12s %s" % ("", "  ".join("%-6s" % x[:6] for x in DIRS)))
    for i in range(n):
        row = []
        for j in range(n):
            if i == j:
                row.append("  --  ")
                continue
            diff = float(np.abs(ims[i] - ims[j]).mean())
            row.append("%6.3f" % diff)
            if j > i and diff < worst[0]:
                worst = (diff, (DIRS[i], DIRS[j]))
        print("%-12s %s" % (DIRS[i][:12], "  ".join(row)))
    low = sorted((float(np.abs(ims[i] - ims[j]).mean()), DIRS[i], DIRS[j])
                 for i in range(n) for j in range(i + 1, n))
    bad = [x for x in low if x[0] < THRESHOLD]
    print("")
    print("tri nejpodobnejsi dvojice:")
    for v, a, b in low[:3]:
        print("  %-12s %-12s %.3f%s"
              % (a, b, v, "   <-- pod prahem" if v < THRESHOLD else ""))
    if bad:
        print("")
        print("VADNA SADA: %d dvojic pod prahem %.3f -- ty smery jsou tentyz obrazek."
              % (len(bad), THRESHOLD))
        print("Prejmenovani to nespravi, osm smeru tam neni. Pust rotaci znovu.")
        return 1
    print("")
    print("OK: zadna dvojice pod prahem %.3f, vsech osm smeru je odlisnych." % THRESHOLD)
    return 0


def sheet(key, out=None):
    import math
    from PIL import ImageDraw
    proj = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    z, side = 4, 68 * 4
    img = Image.new("RGB", (side * 4, (side + 26) * 2), (58, 50, 40))
    dr = ImageDraw.Draw(img)
    for i, n in enumerate(DIRS):
        p = os.path.join(proj, "assets", "towers", "head_%s_%s.png" % (key, n))
        if not os.path.isfile(p):
            raise SystemExit("chybi " + p)
        im = Image.open(p).convert("RGBA")
        # Pozadi je vrch terasy (docs/art/iso_bible.md) -- sprite se soudi na tom,
        # na cem bude stat, ne na sachovnici.
        bg = Image.new("RGBA", im.size, (184, 165, 135, 255))
        bg.alpha_composite(im)
        px, py = (i % 4) * side, (i // 4) * (side + 26)
        img.paste(bg.resize((side, side), Image.NEAREST).convert("RGB"), (px, py + 26))
        dr.text((px + 6, py + 7), "%s  (sipka = slib jmena)" % n, fill=(255, 240, 200))
        a = math.radians(i * 45.0)          # y roste dolu, jako na obrazovce
        cx, cy = px + side / 2, py + 26 + side / 2
        ex, ey = cx + math.cos(a) * side * 0.42, cy + math.sin(a) * side * 0.42
        dr.line((cx, cy, ex, ey), fill=(0, 255, 120), width=5)
        dr.ellipse((ex - 7, ey - 7, ex + 7, ey + 7), fill=(0, 255, 120))
    out = out or os.path.join(proj, "build", "_dir_check.png")
    img.save(out)
    print("arch -> %s   (hlaven musi souhlasit se sipkou ve vsech osmi)" % out)
    return 0


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "sheet":
        sys.exit(sheet(sys.argv[2]))
    sys.exit(check(sys.argv[1] if len(sys.argv) > 1 else "build/iso_art/obj_focus_timer"))
