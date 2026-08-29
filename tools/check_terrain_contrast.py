"""Overi, ze barvy terenu v tools/flat_terrain.py splnuji brany z docs/art/STYLE_BIBLE.md.

    python tools/check_terrain_contrast.py     # 0 = OK, 1 = nesplneno

PROC TO EXISTUJE

Od 29. 8. 2026 se teren negeneruje -- instaluje ho tools/flat_terrain.py jako ploche
barvy, za 0 generaci. Tim padem uz neni zadne kolo generovani, ve kterem by se kontrast
zmeril; brany v STYLE_BIBLE.md §4 by zustaly jako proza, kterou nikdo neoveruje, a prvni
kdo by GROUND o kousek zesvetlil, by tise smazal jediny rozdil, na kterem stoji citelnost
desky pod brainfogem.

Skript proto cte OBOJI z primarniho zdroje: prahy z bible (blok <!-- gen:contrast -->),
hodnoty z flat_terrain.py. Nic si nedrzi vlastni kopii, takze se nemuze rozejit ani
s jednim.

Metrika je soucet RGB (0-765), stejna jako u kazdeho jineho auditu v tomhle repu --
ne relativni luminance, ne Lab. Merit se ma tim, cim se merilo dosud, jinak se cisla
nedaji srovnat se starsimi.
"""
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIBLE = os.path.join(ROOT, "docs", "art", "STYLE_BIBLE.md")
FLAT = os.path.join(ROOT, "tools", "flat_terrain.py")

fails = 0


def check(label, ok, detail=""):
    global fails
    if ok:
        print("  ok   %s %s" % (label, detail))
    else:
        fails += 1
        print("  FAIL %s %s" % (label, detail))


def rgb_sum(c):
    return sum(c)


def hue(c):
    """Odstin ve stupnich, 0-360. Sedy vrati 0."""
    r, g, b = [x / 255.0 for x in c]
    hi, lo = max(r, g, b), min(r, g, b)
    d = hi - lo
    if d == 0:
        return 0.0
    if hi == r:
        h = 60.0 * (((g - b) / d) % 6.0)
    elif hi == g:
        h = 60.0 * (((b - r) / d) + 2.0)
    else:
        h = 60.0 * (((r - g) / d) + 4.0)
    return h % 360.0


def hue_gap(a, b):
    """Kruhovy rozdil odstinu -- pres 0/360 se pocita tou kratsi cestou."""
    d = abs(hue(a) - hue(b)) % 360.0
    return min(d, 360.0 - d)


def saturation(c):
    hi = max(c)
    return 0.0 if hi == 0 else (hi - min(c)) / float(hi)


def flat_colors():
    """GROUND / LANE / TOP primo z tools/flat_terrain.py, ne z kopie."""
    text = io.open(FLAT, encoding="utf-8").read()
    out = {}
    for name in ("GROUND", "LANE", "TOP"):
        m = re.search(r"^%s\s*=\s*\((\d+),\s*(\d+),\s*(\d+)\)" % name, text, re.M)
        if not m:
            raise SystemExit("tools/flat_terrain.py: nenasel jsem konstantu %s" % name)
        out[name] = tuple(int(g) for g in m.groups())
    return out


def bible_gates():
    """Prahy z bloku <!-- gen:contrast -->, vytazene z textu pravidla."""
    text = io.open(BIBLE, encoding="utf-8").read()
    m = re.search(r"<!--\s*gen:contrast\s*-->(.*?)<!--\s*/gen:contrast\s*-->", text, re.S)
    if not m:
        raise SystemExit("STYLE_BIBLE.md: chybi blok <!-- gen:contrast -->")
    gates = {}
    for line in m.group(1).splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 2:
            continue
        rule = cells[1]
        g = re.search(r">=\s*(\d+)", rule) or re.search(r"<=\s*([\d.]+)", rule)
        if g:
            gates[cells[0]] = float(g.group(1))
    return gates


def main():
    c = flat_colors()
    gates = bible_gates()
    ground, lane, top = c["GROUND"], c["LANE"], c["TOP"]

    print("hodnoty z tools/flat_terrain.py:")
    for name, v in (("tkan  (GROUND)", ground), ("cesta (LANE)", lane), ("zdi   (TOP)", top)):
        print("  %-15s rgb%-16s soucet %3d  odstin %5.1f  sytost %.3f"
              % (name, v, rgb_sum(v), hue(v), saturation(v)))

    print("\nbrany z STYLE_BIBLE.md §4:")
    for k, v in sorted(gates.items()):
        print("  %-28s %s" % (k, v))

    print("\nvyhodnoceni:")
    need = gates.get("cesta vs. tkáň, jas")
    got = rgb_sum(lane) - rgb_sum(ground)
    check("cesta je o dost svetlejsi nez tkan", need is not None and got >= need,
          "%d, pozadovano >= %s" % (got, need))

    need = gates.get("cesta vs. tkáň, odstín")
    got = hue_gap(lane, ground)
    check("cesta a tkan jsou odstinem daleko od sebe", need is not None and got >= need,
          "%.1f stupnu, pozadovano >= %s" % (got, need))

    need = gates.get("zdi vs. cesta, jas")
    got = rgb_sum(top) - rgb_sum(lane)
    check("zdi jsou nejsvetlejsi plocha zeme", need is not None and got >= need,
          "%d, pozadovano >= %s" % (got, need))

    need = gates.get("zdi, matnost")
    got = saturation(top)
    check("zdi jsou odbarvene, tedy matne", need is not None and got <= need,
          "%.3f, pozadovano <= %s" % (got, need))

    check("tkan je uvnitr pasma 60-110", 60 <= rgb_sum(ground) <= 110, str(rgb_sum(ground)))
    check("cesta je uvnitr pasma 120-160", 120 <= rgb_sum(lane) <= 160, str(rgb_sum(lane)))

    print("\n%s (%d failures)" % ("PASSED" if fails == 0 else "FAILED", fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
