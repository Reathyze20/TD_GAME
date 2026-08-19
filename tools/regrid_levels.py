# -*- coding: utf-8 -*-
"""Prepocte geometrii levelu z mrizky 40x19 na 120x57 (kazda bunka -> blok 3x3).

    python tools/regrid_levels.py            # jen ukaze, co by se stalo
    python tools/regrid_levels.py --apply

PROC TO TENTOKRAT JDE, KDYZ refit_levels.py PSAL, ZE PRESKALOVAT MAPU NELZE

refit_levels.py mel pomer 30/40 = 0.75. Zed dlouha 24 bunek by vysla na 18, ale mezera
siroka 4 bunky na 3 a jednobunkovy pilir na 0.75 -- z toho vznikne nespojita kase.
Tady je pomer PRESNE 3. Kazda bunka se rozpadne na blok 3x3 a NIC se nezaokrouhluje:
zed 24 bunek -> 72, mezera 4 -> 12, pilir 1 -> 3. Prochodnost se zachova prokazatelne,
protoze topologie mrizky je totozna, jen trikrat jemneji vzorkovana.

NA OBRAZOVCE SE MAPA NEHNE. Bunka jde ze 48 px na 16, blok 3x3 = 48 px, tedy presne
tam, kde zed stala predtim, stoji i ted. Meni se JEN jemnost rastru (a s ni velikost
spritu, ktere se prestanou zvetsovat -- viz Data.pixel_scale).

Objective a stavebni mista se kladou na PROSTREDNI bunku bloku (3x+1, 3y+1). Diky tomu
vraci game.cell_center() rovnou stred bloku a nic v kodu se nemusi ucit nove souradnice.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
from collections import deque

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEVELS = os.path.join(PROJ, "data", "levels")
N = 3                      # kolikrat se mrizka zjemnuje
NEW_COLS, NEW_ROWS = 120, 57


def _vecs(txt: str) -> list[tuple[int, int]]:
    return [(int(a), int(b)) for a, b in re.findall(r"Vector2i\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)", txt)]


def _rects(txt: str) -> list[tuple[int, int, int, int]]:
    return [tuple(int(v) for v in m) for m in
            re.findall(r"Rect2i\(\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*\)", txt)]


def _expand_cells(cells):
    """Jedna bunka -> blok NxN. Poradi drzim stabilni, aby diff sel precist."""
    out = []
    for x, y in cells:
        for j in range(N):
            for i in range(N):
                out.append((x * N + i, y * N + j))
    return out


def _field(txt: str, name: str, required: bool = True) -> str:
    """Vraci "" u nepovinneho pole. level_2 zadne path_cells nema -- vrstva cest je
    dekorace, ne geometrie, takze level bez ni je v poradku a neni to chyba."""
    m = re.search(rf"^{name} = (.*)$", txt, re.M)
    if not m:
        if required:
            raise RuntimeError(f"pole {name} v levelu nenalezeno")
        return ""
    return m.group(1)


def _passable(high, spawns, objective) -> tuple[bool, int]:
    """BFS ze spawnu na cil pres NE-vysoke bunky. Kdyby prepocet neco ucpal, level by
    sel spustit a teprve pak by se ukazalo, ze distrakce nemaji kudy jit."""
    blocked = set(high) - {objective}
    start = [c for c in spawns if c not in blocked]
    seen, q = set(start), deque(start)
    while q:
        x, y = q.popleft()
        if (x, y) == objective:
            return True, len(seen)
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if not (0 <= nx < NEW_COLS and 0 <= ny < NEW_ROWS):
                continue
            if (nx, ny) in seen or (nx, ny) in blocked:
                continue
            seen.add((nx, ny))
            q.append((nx, ny))
    return False, len(seen)


def convert(path: str, apply: bool) -> bool:
    txt = open(path, encoding="utf-8").read()
    name = os.path.basename(path)

    high = _vecs(_field(txt, "high_ground"))
    paths = _vecs(_field(txt, "path_cells", required=False))
    zones = _rects(_field(txt, "spawn_zones"))
    ox, oy = _vecs(_field(txt, "objective"))[0]

    new_high = _expand_cells(high)
    new_paths = _expand_cells(paths)
    new_zones = [(x * N, y * N, w * N, h * N) for x, y, w, h in zones]
    new_obj = (ox * N + 1, oy * N + 1)

    spawn_cells = [(x, y) for zx, zy, zw, zh in new_zones
                   for x in range(zx, zx + zw) for y in range(zy, zy + zh)
                   if 0 <= x < NEW_COLS and 0 <= y < NEW_ROWS]
    ok, reached = _passable(set(new_high), spawn_cells, new_obj)

    print(f"\n{name}")
    print(f"  high_ground   {len(high):5d} -> {len(new_high):6d}")
    print(f"  path_cells    {len(paths):5d} -> {len(new_paths):6d}")
    print(f"  spawn_zones   {zones} -> {new_zones}")
    print(f"  objective     ({ox},{oy}) -> {new_obj}   [stred bloku]")
    print(f"  PRUCHOD spawn -> cil: {'OK' if ok else 'UCPANO'}  ({reached} bunek dosazeno)")
    if not ok:
        return False

    def fmt_v(cells):
        return "Array[Vector2i]([" + ", ".join(f"Vector2i({x}, {y})" for x, y in cells) + "])"

    def fmt_r(rs):
        return "Array[Rect2i]([" + ", ".join(f"Rect2i({a}, {b}, {c}, {d})" for a, b, c, d in rs) + "])"

    txt = re.sub(r"^objective = .*$", f"objective = Vector2i({new_obj[0]}, {new_obj[1]})", txt, flags=re.M)
    txt = re.sub(r"^spawn_zones = .*$", "spawn_zones = " + fmt_r(new_zones), txt, flags=re.M)
    txt = re.sub(r"^high_ground = .*$", "high_ground = " + fmt_v(new_high), txt, flags=re.M)
    if new_paths:
        txt = re.sub(r"^path_cells = .*$", "path_cells = " + fmt_v(new_paths), txt, flags=re.M)

    if apply:
        bak = path + ".bak_grid48"
        if not os.path.exists(bak):
            shutil.copy2(path, bak)
        open(path, "w", encoding="utf-8").write(txt)
        print(f"  zapsano (zaloha {os.path.basename(bak)})")
    return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()
    all_ok = True
    for f in sorted(os.listdir(LEVELS)):
        if f.endswith(".tres"):
            all_ok &= convert(os.path.join(LEVELS, f), a.apply)
    if not a.apply:
        print("\n(nic se nezapsalo, spust s --apply)")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
