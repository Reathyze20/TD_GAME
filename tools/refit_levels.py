"""Presadi geometrii levelu z mrizky 40x19 na 30x14.

    python tools/refit_levels.py            # ukaze mapy pred a po
    python tools/refit_levels.py --apply

PROC PRESADIT A NE PRESKALOVAT

Prechod na 32 px artu na bunku (tools/raster_x2.py) zmensil desku ze 40x19 na 30x14 --
bunka na obrazovce vyrostla ze 48 na 64 px, takze se jich vejde min. Cil levelu 1 lezel
na x=36 a levelu 2 na x=35; obe cisla jsou mimo novou sirku, takze mapy MUSI ven tak
jako tak.

Preskalovat souradnice pomerem 30/40 nejde. Zed dlouha 24 bunek by vysla na 18,
ale mezera siroka 4 bunky na 3, jednobunkovy pilir na 0.75 -- a z toho vznikne
nesouvisla kase, ne mapa. Bludiste neni obrazek, je to graf pruchodnosti; kdyz se
zmensi neceloCiselnym pomerem, prochodnost se rozpadne na nahodnych mistech.

Presazujeme proto NAVRH, ne souradnice: stejny rytmus pasu zdi, stejne koridory mezi
nimi, spawn na levem okraji, cil vpravo. Puvodni level 1 mel ctyri pasy zdi po dvou
radcich (y=2,6,10,14) a mezi nimi koridory; do ctrnacti radku se vejdou tri pasy a
ctyri koridory, coz je tentyz zpusob hrani o jeden pas mene.

KAZDA VYSLEDNA MAPA SE OVERUJE PRUCHODEM. Nize je zamerne primitivni prohledavani do
sirky ze spawnu na cil -- kdyby presazeni nekde ucpalo jedinou cestu, level by se dal
spustit a teprve pak by se ukazalo, ze distrakce nemaji kudy jit.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from collections import deque

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEVELS = os.path.join(PROJ, "data", "levels")

COLS, ROWS = 30, 14

# ------------------------------------------------------------------ nove navrhy
#
# Zed jde od x=4 do x=21, pak mezera, pak samostatny pilir -- stejny tvar jako puvodne,
# jen uzsi. Pilir tam je proto, aby posledni usek pred cilem nebyl uplne volny.
ZED_OD, ZED_DO = 4, 21
PILIR_X = 25
PASY_Y = (2, 6, 10)          # kazdy pas je dva radky vysoky


def navrh_level_1() -> dict:
    hg = []
    for y0 in PASY_Y:
        for y in (y0, y0 + 1):
            for x in range(ZED_OD, ZED_DO + 1):
                hg.append((x, y))
            hg.append((PILIR_X, y))
    return {"high_ground": hg,
            "spawn": [(0, 2, 1, 12)],
            "objective": (27, 7)}


def navrh_level_2() -> dict:
    """Level 2 mel jen 19 bunek vysoke zeme a spawn i shora (Rect2i(1,0,38,1)).
    Drzime obe vlastnosti: rare zdi a druhy spawn po celem hornim okraji."""
    hg = []
    for y in (5, 6):
        for x in range(6, 18):
            hg.append((x, y))
    for y in (9, 10):
        for x in range(12, 24):
            hg.append((x, y))
    return {"high_ground": hg,
            "spawn": [(0, 1, 1, 12), (1, 0, COLS - 2, 1)],
            "objective": (27, 7)}


NAVRHY = {"level_1": navrh_level_1, "level_2": navrh_level_2}


# ------------------------------------------------------------------ kontrola
def projde(hg, spawn, obj) -> bool:
    """Dostane se distrakce ze spawnu na cil? Ctyri smery, zed neprochozi."""
    stena = set(hg)
    start = []
    for (rx, ry, rw, rh) in spawn:
        for x in range(rx, rx + rw):
            for y in range(ry, ry + rh):
                if (x, y) not in stena:
                    start.append((x, y))
    videno, fronta = set(start), deque(start)
    while fronta:
        x, y = fronta.popleft()
        if (x, y) == obj:
            return True
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if (0 <= n[0] < COLS and 0 <= n[1] < ROWS
                    and n not in videno and n not in stena):
                videno.add(n)
                fronta.append(n)
    return False


def kresli(hg, spawn, obj) -> str:
    stena = set(hg)
    sp = set()
    for (rx, ry, rw, rh) in spawn:
        for x in range(rx, rx + rw):
            for y in range(ry, ry + rh):
                sp.add((x, y))
    out = []
    for y in range(ROWS):
        row = ""
        for x in range(COLS):
            row += ("O" if (x, y) == obj else "#" if (x, y) in stena
                    else "S" if (x, y) in sp else ".")
        out.append(f"{y:2d} {row}")
    return "\n".join(out)


# ------------------------------------------------------------------ zapis
def _vec_list(pts) -> str:
    return "Array[Vector2i]([" + ", ".join(f"Vector2i({x}, {y})" for x, y in pts) + "])"


def _rect_list(rects) -> str:
    return "Array[Rect2i]([" + ", ".join(
        f"Rect2i({a}, {b}, {c}, {d})" for a, b, c, d in rects) + "])"


def patch(path: str, navrh: dict, apply: bool) -> None:
    with open(path, encoding="utf-8") as f:
        s = f.read()
    # re.DOTALL na "vsechno az po prvni ])" -- pole jsou v .tres na jednom logickem
    # radku, ale Godot je pri ukladani zalamuje, takze radkovy regex by nestacil.
    s = re.sub(r"high_ground\s*=\s*Array\[Vector2i\]\(\[.*?\]\)",
               "high_ground = " + _vec_list(navrh["high_ground"]), s, count=1, flags=re.S)
    s = re.sub(r"spawn_zones\s*=\s*Array\[Rect2i\]\(\[.*?\]\)",
               "spawn_zones = " + _rect_list(navrh["spawn"]), s, count=1, flags=re.S)
    s = re.sub(r"objective\s*=\s*Vector2i\(\d+,\s*\d+\)",
               "objective = Vector2i({}, {})".format(*navrh["objective"]), s, count=1)
    if apply:
        with open(path, "w", encoding="utf-8") as f:
            f.write(s)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Presazeni levelu na mrizku 30x14.")
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args(argv)

    spatne = 0
    for jmeno, fn in NAVRHY.items():
        path = os.path.join(LEVELS, jmeno + ".tres")
        if not os.path.isfile(path):
            print(f"{jmeno}: soubor chybí, přeskakuji")
            continue
        n = fn()
        ok = projde(n["high_ground"], n["spawn"], n["objective"])
        print(f"\n=== {jmeno} — {COLS}x{ROWS}, cesta ze spawnu na cíl: "
              f"{'PROJDE' if ok else 'NEPROJDE (!!)'}")
        print(kresli(n["high_ground"], n["spawn"], n["objective"]))
        if not ok:
            spatne += 1
            continue
        patch(path, n, args.apply)

    if spatne:
        print(f"\n{spatne} mapa/y neprochozí — nic se nezapsalo.")
        return 1
    print("\nZapsáno." if args.apply else "\nZkušební běh — nic se nezapsalo. Spusť s --apply.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
