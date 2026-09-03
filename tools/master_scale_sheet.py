"""Postav kontaktni list masteru smeru A V HERNIM MERITKU.

    python tools/master_scale_sheet.py

PROC TENHLE NASTROJ EXISTUJE

`tools/direction_a_masters.py sheet` uz kontaktni list dela a je dobry na to, na co je:
barva a silueta vedle sebe, kandidat velky pres pul obrazovky. Rozhodnuti podle §12f se
ale nedela na kandidatovi velkem 200 px -- dela se na tom, jak vypada NA DESCE. A tam je
distrakce siroka 1,60 dlazdice a habit 4,00 dlazdice (zmereno
`scenes/_shot_scale_audit.tscn`, ne odhadnuto). To je desetinasobny rozdil proti
kontaktnimu listu a je to presne to pravidlo z pameti uzivatele: art zmer a vykresli
v hernim meritku driv, nez ho ukazes.

Druhy duvod: **obe rodiny se kresli JINYM vzorcem** a ten rozdil neni nikde videt.
Distrakce jde pres `Data.UNIT_ART_SCALE` (0,4), habit ne -- `tower.gd` kresli hlavu jako
`get_size() * pixel_scale()` bez dalsiho faktoru, protoze `UNIT_ART_SCALE` se v hlavicce
sam omezuje na "a moving combat unit's sprite (enemy Distraction and DefenderUnit)".
Tentyz 64px sprite je tedy jako distrakce 1,6 dlazdice a jako habit 4,0 dlazdice.

ZADNA KONSTANTA SE TU NEOPISUJE

CLAUDE.md, "Konstantu neopisuj -- odvod ji": kazde cislo, ktere popisuje geometrii, se
cte ze zdroje (`scripts/data.gd`, `scripts/game.gd`) a kdyz se nenajde, nastroj SPADNE
misto aby dosadil zastaralou kopii. Jednorazovost neni duvod opsat cislo -- pravidlo
vzniklo po ctyrech pripadech, kdy prave tohle vedlo k obrazku, ktery lhal.
"""

import io
import os
import re
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, ".dev", "screenshots", "master_scale_sheet.png")
ZOOM = 4  # stejny integer upscale, jakym hru zvetsuje project.godot (viewport/integer)


def _read(rel):
    with io.open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def _num(src, pattern, what, cast=int):
    m = re.search(pattern, src)
    if m is None:
        sys.exit("NENALEZENO v zdroji: %s  (vzor %r)" % (what, pattern))
    return cast(m.group(1))


def _color8(src, name):
    m = re.search(r"const\s+%s\s*:=\s*Color8\(\s*(\d+),\s*(\d+),\s*(\d+)\s*\)" % name, src)
    if m is None:
        sys.exit("NENALEZENO v zdroji: %s" % name)
    return tuple(int(g) for g in m.groups())


data_gd = _read("scripts/data.gd")
game_gd = _read("scripts/game.gd")

TILE = _num(data_gd, r'"tile":\s*(\d+)', "Data.GRID.tile")
COLS = _num(data_gd, r'"cols":\s*(\d+)', "Data.GRID.cols")
BUILD_BLOCK = _num(data_gd, r"const\s+BUILD_BLOCK\s*:=\s*(\d+)", "Data.BUILD_BLOCK")
UNIT_ART_SCALE = _num(data_gd, r"const\s+UNIT_ART_SCALE\s*:=\s*([0-9.]+)",
                      "Data.UNIT_ART_SCALE", float)
ISO_PIXEL_SCALE = _num(data_gd, r"const\s+ISO_PIXEL_SCALE\s*:=\s*([0-9.]+)",
                       "Data.ISO_PIXEL_SCALE", float)
GROUND = _color8(game_gd, "SQUARE_GROUND_COLOR")
TOP = _color8(game_gd, "SQUARE_TOP_COLOR")

BLOCK_PX = BUILD_BLOCK * TILE           # 3x3 bunky = stavebni blok, na kterem habit stoji
DOT = (0x3b, 0x45, 0x61)                # game.gd _draw_static_field(), tecka po blocich

print("odvozeno ze zdroje: tile=%d cols=%d build_block=%d (=%dpx) "
      "pixel_scale=%.2f unit_art_scale=%.2f"
      % (TILE, COLS, BUILD_BLOCK, BLOCK_PX, ISO_PIXEL_SCALE, UNIT_ART_SCALE))


def candidates(rel_dir):
    d = os.path.join(ROOT, rel_dir)
    if not os.path.isdir(d):
        sys.exit("chybi adresar %s" % rel_dir)
    return [os.path.join(d, f) for f in sorted(os.listdir(d)) if f.endswith(".png")]


def scaled(path, px):
    """Nearest-neighbour na presnou hernl velikost -- stejny filtr, jaky pouziva engine."""
    im = Image.open(path).convert("RGBA")
    px = max(1, int(round(px)))
    return im.resize((px, px), Image.NEAREST)


def board_strip(width, height):
    """Kus desky: plocha barva + tecka na stred kazdeho stavebniho bloku."""
    im = Image.new("RGBA", (width, height), GROUND + (255,))
    px = im.load()
    half = BUILD_BLOCK // 2
    for by in range(0, height // TILE + 1):
        for bx in range(0, width // TILE + 1):
            if bx % BUILD_BLOCK == half and by % BUILD_BLOCK == half:
                cx, cy = bx * TILE + TILE // 2, by * TILE + TILE // 2
                for dy in range(-1, 2):
                    for dx in range(-1, 2):
                        if 0 <= cx + dx < width and 0 <= cy + dy < height:
                            px[cx + dx, cy + dy] = DOT + (180,)
    return im


def outline(im, x, y, side):
    """Referencni ctverec. Habit stoji na stavebnim bloku 3x3, distrakce chodi a zabira
    zhruba jednu bunku -- kazda rada tedy dostava svuj vlastni, spravny referent."""
    d = im.load()
    for i in range(side):
        for (px_, py_) in ((x + i, y), (x + i, y + side - 1),
                           (x, y + i), (x + side - 1, y + i)):
            if 0 <= px_ < im.width and 0 <= py_ < im.height:
                d[px_, py_] = TOP + (110,)


def row(paths, draw_px, ref_side, pad=TILE):
    """Jedna rada kandidatu na desce, vsichni v jednom hernim meritku."""
    cell = max(int(round(draw_px)), ref_side) + pad
    w = cell * len(paths) + pad
    h = cell + pad
    im = board_strip(w, h)
    for i, p in enumerate(paths):
        cx = pad + i * cell + cell // 2
        base = pad + cell - pad // 2          # spolecna linka zeme
        outline(im, cx - ref_side // 2, base - ref_side, ref_side)
        s = scaled(p, draw_px)
        im.alpha_composite(s, (cx - s.width // 2, base - s.height))
    return im


def stack(images, gap=8):
    w = max(i.width for i in images)
    h = sum(i.height for i in images) + gap * (len(images) - 1)
    out = Image.new("RGBA", (w, h), GROUND + (255,))
    y = 0
    for i in images:
        out.alpha_composite(i, (0, y))
        y += i.height + gap
    return out


dis = candidates("assets/raw/master_distraction_a")
hab = candidates("assets/raw/master_habit_a")
raw = Image.open(dis[0]).size[0]

dis_px = raw * ISO_PIXEL_SCALE * UNIT_ART_SCALE      # jak se kresli distrakce
hab_now = raw * ISO_PIXEL_SCALE                      # jak se kresli habit DNES
hab_fit = float(BLOCK_PX)                            # kdyby sedel na svuj blok

print("kandidat %dx%d px  ->  distrakce %.1f px (%.2f dlazdice) | "
      "habit dnes %.1f px (%.2f) | habit na blok %.1f px (%.2f)"
      % (raw, raw, dis_px, dis_px / TILE, hab_now, hab_now / TILE,
         hab_fit, hab_fit / TILE))

sheet = stack([
    row(dis, dis_px, TILE),        # chodec: referent je jedna bunka
    row(hab, hab_now, BLOCK_PX),   # habit dnes: referent je jeho stavebni blok
    row(hab, hab_fit, BLOCK_PX),   # habit zmenseny presne na ten blok
])
sheet = sheet.resize((sheet.width * ZOOM, sheet.height * ZOOM), Image.NEAREST)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
sheet.save(OUT)
print("ulozeno %s  %dx%d" % (os.path.relpath(OUT, ROOT), sheet.width, sheet.height))
