"""Postav podklad pro schvaleni masteru smeru A (STYLE_BIBLE.md SS12f) V HERNIM MERITKU.

    python tools/master_scale_sheet.py             # vsechny tri listy
    python tools/master_scale_sheet.py scale       # jen a) meritko
    python tools/master_scale_sheet.py podstavec   # jen b) podstavec vs MODE_SQUARE
    python tools/master_scale_sheet.py dvojice     # jen c) nejlepsi 3 + 3

NEGENERUJE NIC. Cte vyhradne to, co uz lezi v assets/raw/master_*.

PROC TENHLE NASTROJ EXISTUJE

`tools/direction_a_masters.py sheet` uz kontaktni list dela a je dobry na to, na co je:
barva a silueta vedle sebe, kandidat velky pres pul obrazovky. Rozhodnuti podle SS12f se
ale nedela na kandidatovi velkem 200 px -- dela se na tom, jak vypada NA DESCE. A tam je
distrakce siroka 1,60 dlazdice a habit 4,00 dlazdice (zmereno
`scenes/_shot_scale_audit.tscn`, ne odhadnuto). To je desetinasobny rozdil proti
kontaktnimu listu.

Druhy duvod: **obe rodiny se kresli JINYM vzorcem** a ten rozdil neni nikde videt.
Distrakce jde pres `Data.UNIT_ART_SCALE` (0,4), habit ne -- `tower.gd` kresli hlavu jako
`get_size() * pixel_scale()` bez dalsiho faktoru, protoze `UNIT_ART_SCALE` se v hlavicce
sam omezuje na "a moving combat unit's sprite (enemy Distraction and DefenderUnit)".
Tentyz 64px sprite je tedy jako distrakce 1,6 dlazdice a jako habit 4,0 dlazdice.

Treti duvod (list b): vsech 16 habit kandidatu ma IZOMETRICKY podstavec, zatimco deska
jede `GridProjection.active_mode = MODE_SQUARE` -- plochou top-down mrizku, vychozi od
T5. Jestli kosoctvercova zakladna na ctvercove bunce funguje, je soud oka; ale bez
vykreslene hranice bunky pod ni ho nejde udelat vubec.

ZADNA KONSTANTA SE TU NEOPISUJE

CLAUDE.md, "Konstantu neopisuj -- odvod ji": kazde cislo, ktere popisuje geometrii, se
cte ze zdroje (`scripts/data.gd`, `scripts/game.gd`) a kdyz se nenajde, nastroj SPADNE
misto aby dosadil zastaralou kopii. Porad radek kandidatu se navic NESERADUJE podle oka:
kompaktnost se pocita `tools/check_style_failure_modes.py`, importem te same funkce,
kterou pouziva brana -- ne druhou kopii vzorce.

JEDINE cislo, ktere tady zdroj NEMA, je HABIT_ART_SCALE: v kodu zatim NEEXISTUJE, je to
navrh z BLOCKED.md. Proto je oznaceny jako navrh a hlida ho assert proti odvozenemu
BLOCK_PX -- kdyby se BUILD_BLOCK nebo tile zmenily, nastroj spadne misto aby tise
vykreslil lez.
"""

import io
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_style_failure_modes import (  # noqa: E402  (az po sys.path)
    bible_gates, compactness, load_rgba, opaque_mask, unique_colors,
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, ".dev", "screenshots")
ZOOM = 4        # stejny integer upscale, jakym hru zvetsuje project.godot
ZOOM_DETAIL = 8  # list b) je inspekcni, ne nahled hry -- vic priblizeny zamerne


def _read(rel):
    with io.open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def _num(src, pattern, what, cast=int):
    m = re.search(pattern, src)
    if m is None:
        sys.exit("NENALEZENO ve zdroji: %s  (vzor %r)" % (what, pattern))
    return cast(m.group(1))


def _color8(src, name):
    m = re.search(r"const\s+%s\s*:=\s*Color8\(\s*(\d+),\s*(\d+),\s*(\d+)\s*\)" % name, src)
    if m is None:
        sys.exit("NENALEZENO ve zdroji: %s" % name)
    return tuple(int(g) for g in m.groups())


data_gd = _read("scripts/data.gd")
game_gd = _read("scripts/game.gd")

TILE = _num(data_gd, r'"tile":\s*(\d+)', "Data.GRID.tile")
BUILD_BLOCK = _num(data_gd, r"const\s+BUILD_BLOCK\s*:=\s*(\d+)", "Data.BUILD_BLOCK")
UNIT_ART_SCALE = _num(data_gd, r"const\s+UNIT_ART_SCALE\s*:=\s*([0-9.]+)",
                      "Data.UNIT_ART_SCALE", float)
ISO_PIXEL_SCALE = _num(data_gd, r"const\s+ISO_PIXEL_SCALE\s*:=\s*([0-9.]+)",
                       "Data.ISO_PIXEL_SCALE", float)
GROUND = _color8(game_gd, "SQUARE_GROUND_COLOR")
TOP = _color8(game_gd, "SQUARE_TOP_COLOR")

BLOCK_PX = BUILD_BLOCK * TILE
DOT = (0x3b, 0x45, 0x61)      # game.gd _draw_static_field(), tecka po blocich
INK = (0xdc, 0xe3, 0xf2)      # popisky
INK_DIM = (0x8a, 0x95, 0xad)
CELL_LINE = (0x4f, 0x5d, 0x80)

## NAVRH, ne zdroj pravdy: HABIT_ART_SCALE v kodu neexistuje (viz BLOCKED.md, "Habit se
## kresli 4,00 dlazdice"). Assert nize je duvod, proc se sem smi napsat cislo: sviazuje
## ho s odvozenym BLOCK_PX, takze kdyby se BUILD_BLOCK nebo tile pohnuly, nastroj spadne.
HABIT_ART_SCALE_PROPOSED = 0.75


def font(size):
    return ImageFont.load_default(size=size)


def candidates(rel_dir):
    d = os.path.join(ROOT, rel_dir)
    if not os.path.isdir(d):
        sys.exit("chybi adresar %s" % rel_dir)
    return [os.path.join(d, f) for f in sorted(os.listdir(d)) if f.endswith(".png")]


def scaled(path, px):
    """Nearest-neighbour na presnou herni velikost -- stejny filtr, jaky pouziva engine."""
    im = Image.open(path).convert("RGBA")
    px = max(1, int(round(px)))
    return im.resize((px, px), Image.NEAREST)


def silhouette(path, px, color=(0x0d, 0x0b, 0x1c)):
    """Alfa maska vyplnena naplno -- co z tvaru zbyde, kdyz zmizi barva."""
    im = Image.open(path).convert("RGBA")
    a = im.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    out = Image.new("RGBA", im.size, color + (0,))
    out.putalpha(a)
    solid = Image.new("RGBA", im.size, color + (255,))
    solid.putalpha(a)
    px = max(1, int(round(px)))
    return solid.resize((px, px), Image.NEAREST)


def board(width, height, cell_grid=False):
    """Kus desky: plocha barva, tecka na stred kazdeho stavebniho bloku, volitelne
    mrizka jednotlivych bunek MODE_SQUARE."""
    im = Image.new("RGBA", (width, height), GROUND + (255,))
    px = im.load()
    if cell_grid:
        for y in range(height):
            for x in range(width):
                if x % TILE == 0 or y % TILE == 0:
                    px[x, y] = CELL_LINE + (110,)
    half = BUILD_BLOCK // 2
    for by in range(height // TILE + 1):
        for bx in range(width // TILE + 1):
            if bx % BUILD_BLOCK == half and by % BUILD_BLOCK == half:
                cx, cy = bx * TILE + TILE // 2, by * TILE + TILE // 2
                for dy in range(-1, 2):
                    for dx in range(-1, 2):
                        if 0 <= cx + dx < width and 0 <= cy + dy < height:
                            px[cx + dx, cy + dy] = DOT + (180,)
    return im


def outline(im, x, y, side, color=None, alpha=110):
    """Referencni ctverec. Habit stoji na stavebnim bloku 3x3, distrakce chodi a zabira
    zhruba jednu bunku -- kazda rada tedy dostava svuj vlastni, spravny referent."""
    d = im.load()
    col = (color or TOP) + (alpha,)
    for i in range(side):
        for (px_, py_) in ((x + i, y), (x + i, y + side - 1),
                           (x, y + i), (x + side - 1, y + i)):
            if 0 <= px_ < im.width and 0 <= py_ < im.height:
                d[px_, py_] = col


def strip(paths, draw_px, ref_side, render=scaled, pad=None, cell_grid=False):
    """Jedna rada kandidatu na desce, vsichni v jednom hernim meritku."""
    pad = TILE if pad is None else pad
    cell = max(int(round(draw_px)), ref_side) + pad
    im = board(cell * len(paths) + pad, cell + pad, cell_grid=cell_grid)
    for i, p in enumerate(paths):
        cx = pad + i * cell + cell // 2
        base = pad + cell - pad // 2          # spolecna linka zeme
        outline(im, cx - ref_side // 2, base - ref_side, ref_side)
        s = render(p, draw_px)
        im.alpha_composite(s, (cx - s.width // 2, base - s.height))
    return im


def up(im, zoom):
    return im.resize((im.width * zoom, im.height * zoom), Image.NEAREST)


def captioned(im, title, sub=""):
    """Popisek NAD uz zvetsenym pasem, aby text nebyl schodovity."""
    th, sh = 26, (20 if sub else 0)
    head = th + sh + 10
    out = Image.new("RGBA", (im.width, im.height + head), GROUND + (255,))
    d = ImageDraw.Draw(out)
    d.text((10, 6), title, font=font(20), fill=INK)
    if sub:
        d.text((10, 6 + th), sub, font=font(15), fill=INK_DIM)
    out.alpha_composite(im, (0, head))
    return out


def stack(images, gap=10):
    w = max(i.width for i in images)
    h = sum(i.height for i in images) + gap * (len(images) - 1)
    out = Image.new("RGBA", (w, h), GROUND + (255,))
    y = 0
    for i in images:
        out.alpha_composite(i, (0, y))
        y += i.height + gap
    return out


def save(im, name):
    os.makedirs(OUT_DIR, exist_ok=True)
    p = os.path.join(OUT_DIR, name)
    im.save(p)
    print("  ulozeno %s  %dx%d" % (os.path.relpath(p, ROOT), im.width, im.height))


# ---------------------------------------------------------------- metriky kandidatu

def metric(path):
    """Kompaktnost a pocet barev TOUZ funkci, kterou pouziva brana -- import, ne kopie."""
    rgba = load_rgba(path)          # numpy HxWx4, ne PIL Image
    mask = opaque_mask(rgba)
    return compactness(mask), unique_colors(rgba[..., :3], mask)


def ranked(paths, want_high):
    """Poradi podle kompaktnosti. U distrakci se chce VYSOKA (roztrepeny beztvary jev),
    u habitu NIZKA (kompaktni geometrie) -- prahy jsou v bibli, nikoli tady."""
    scored = [(metric(p)[0], p) for p in paths]
    scored.sort(key=lambda t: t[0], reverse=want_high)
    return scored


DIS = candidates("assets/raw/master_distraction_a")
HAB = candidates("assets/raw/master_habit_a")
RAW = Image.open(DIS[0]).size[0]

DIS_PX = RAW * ISO_PIXEL_SCALE * UNIT_ART_SCALE
HAB_NOW = RAW * ISO_PIXEL_SCALE
HAB_FIT = RAW * ISO_PIXEL_SCALE * HABIT_ART_SCALE_PROPOSED
assert abs(HAB_FIT - BLOCK_PX) < 0.01, (
    "HABIT_ART_SCALE %.3f uz nedava presne stavebni blok (%.1f px vs %d px) -- "
    "BUILD_BLOCK/tile se zmenily, prepocitej navrh v BLOCKED.md"
    % (HABIT_ART_SCALE_PROPOSED, HAB_FIT, BLOCK_PX))

GATES = bible_gates()


def _gate(key):
    v = GATES.get(key)
    return "" if v is None else "  (prah bible: %s)" % _fmt(v)


def _fmt(v):
    return ("%g" % v) if isinstance(v, float) else str(v)


# ---------------------------------------------------------------- a) SCALE

def sheet_scale():
    print("a) SCALE")
    rows = [
        (DIS, DIS_PX, TILE, "distrakce", "referent = 1 bunka"),
        (HAB, HAB_NOW, BLOCK_PX, "habit, jak to engine kresli DNES",
         "referent = stavebni blok 3x3, ktery pretekaji"),
        (HAB, HAB_FIT, BLOCK_PX,
         "habit pri navrhovanem HABIT_ART_SCALE %g" % HABIT_ART_SCALE_PROPOSED,
         "referent = tentyz blok, tentokrat sedi"),
    ]
    out = []
    for paths, px, ref, title, note in rows:
        ratio = px / DIS_PX
        sub = "%.1f px = %.2f dlazdice  |  %.2fx distrakce  |  %s" % (
            px, px / TILE, ratio, note)
        out.append(captioned(up(strip(paths, px, ref), ZOOM), title, sub))
    save(stack(out), "master_scale_sheet.png")


# ---------------------------------------------------------------- b) PODSTAVEC

def sheet_podstavec():
    print("b) PODSTAVEC")
    per_row = 8
    bands = []
    for start in range(0, len(HAB), per_row):
        chunk = HAB[start:start + per_row]
        band = strip(chunk, HAB_FIT, BLOCK_PX, pad=TILE, cell_grid=True)
        bands.append(up(band, ZOOM_DETAIL))
    body = stack(bands)
    save(captioned(
        body,
        "Podstavec vs MODE_SQUARE: sedi kosoctverec na ctvercovou bunku?",
        "vsech %d habit kandidatu pri %.0f px (%.0f dlazdice), zvetseno %dx; "
        "tenka mrizka = bunky %dpx, silny ctverec = stavebni blok %dpx"
        % (len(HAB), HAB_FIT, HAB_FIT / TILE, ZOOM_DETAIL, TILE, BLOCK_PX)),
        "master_podstavec.png")


# ---------------------------------------------------------------- c) DVOJICE

def sheet_dvojice(n=3):
    print("c) DVOJICE")
    dis_rank = ranked(DIS, want_high=True)    # distrakce: chce se VYSOKA kompaktnost
    hab_rank = ranked(HAB, want_high=False)   # habit: chce se NIZKA
    top_dis = [p for _, p in dis_rank[:n]]
    top_hab = [p for _, p in hab_rank[:n]]

    sep = min(c for c, _ in dis_rank[:n]) - max(c for c, _ in hab_rank[:n])
    print("   distrakce (kompaktnost, chce se vysoka): %s" % ", ".join(
        "%s %.2f" % (os.path.basename(p), c) for c, p in dis_rank[:n]))
    print("   habit     (kompaktnost, chce se nizka) : %s" % ", ".join(
        "%s %.2f" % (os.path.basename(p), c) for c, p in hab_rank[:n]))
    print("   odstup rodin na tehle trojici: %.2f%s" % (
        sep, _gate("silueta, odstup rodin")))

    pairs = top_dis + top_hab
    px = [DIS_PX] * n + [HAB_FIT] * n
    refs = [TILE] * n + [BLOCK_PX] * n

    def mixed(render):
        pad = TILE
        cell = max(int(round(max(px))), max(refs)) + pad
        im = board(cell * len(pairs) + pad, cell + pad)
        for i, p in enumerate(pairs):
            cx = pad + i * cell + cell // 2
            base = pad + cell - pad // 2
            outline(im, cx - refs[i] // 2, base - refs[i], refs[i])
            s = render(p, px[i])
            im.alpha_composite(s, (cx - s.width // 2, base - s.height))
        return im

    barvy = captioned(up(mixed(scaled), ZOOM), "Barva",
                      "%d nejlepsi distrakce (%.2f dlazdice) + %d nejlepsi habit "
                      "(%.2f dlazdice), v hernim meritku" % (
                          n, DIS_PX / TILE, n, HAB_FIT / TILE))
    silu = captioned(up(mixed(silhouette), ZOOM), "Silueta",
                     "totez bez barvy -- co z tvaru zbyde; odstup rodin %.2f%s"
                     % (sep, _gate("silueta, odstup rodin")))
    save(stack([barvy, silu]), "master_dvojice.png")


def main():
    print("odvozeno ze zdroje: tile=%d build_block=%d (=%d px) pixel_scale=%.2f "
          "unit_art_scale=%.2f" % (TILE, BUILD_BLOCK, BLOCK_PX, ISO_PIXEL_SCALE,
                                   UNIT_ART_SCALE))
    print("kandidat %dx%d -> distrakce %.1f px (%.2f dl) | habit dnes %.1f px (%.2f dl) "
          "| habit navrh %.1f px (%.2f dl)" % (
              RAW, RAW, DIS_PX, DIS_PX / TILE, HAB_NOW, HAB_NOW / TILE,
              HAB_FIT, HAB_FIT / TILE))
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    if which in ("all", "scale"):
        sheet_scale()
    if which in ("all", "podstavec"):
        sheet_podstavec()
    if which in ("all", "dvojice"):
        sheet_dvojice()
    if which not in ("all", "scale", "podstavec", "dvojice"):
        sys.exit("neznamy list %r -- scale | podstavec | dvojice | (nic = vsechny)"
                 % which)


if __name__ == "__main__":
    main()
