#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Sprite posazeny na SKUTECNOU desku — tak, jak ho uvidi hrac.

PROC to existuje
----------------
Neshoda meritka byla mesice neviditelna. Prisery se kreslily x2, zeme x3, podlaha x6,
a zadne cislo v zadnem reportu to neukazalo: 32x32 je porad hezke kulate cislo, at uz
ho hra nafoukne dvakrat nebo trikrat. Videt to slo teprve ve chvili, kdy sprite stal
na dlazdicich a byl mensi nez mel byt.

Tenhle nastroj proto NEMERI sprite. On ho POSTAVI na desku slozenou z tychz PNG, ktere
naklada hra, ve stejnem poradi vrstev, se stejnym meritkem, se stejnou zari a stejnym
kontaktnim stinem. Cokoli, co tady vypada spatne, vypada spatne i ve hre — a naopak.
Kazdy rozdil proti tomu, co dela Godot, je chyba tohohle souboru.

Co se odkud bere (a kde to overit)
----------------------------------
  scripts/data.gd                    GRID + TERRAIN_ART_PX -> pixel_scale() = 3
                                     CTE SE ZE ZDROJE, necopirovana konstanta: kdyz
                                     nekdo zmeni tile nebo TERRAIN_ART_PX, nahled se
                                     posune s hrou misto aby zacal tise lhat.
  scripts/game.gd                    poradi vrstev (Z_*), pozadi x3, rohovy Wang atlas,
                                     dlazdice cest 16->48 NEAREST, celo zdi, stin zdi
  scripts/components/                zare typu, kontaktni stin, silueta v barve typu,
    distraction_animator.gd          vyber snimku podle fps/holds/offsets
  data/levels/*.tres                 high_ground, path_cells, objective
  data/distractions/<id>.tres        radius a color (obojí ridi zar i stin)
  data/anim_tuning.tres              fps, holds, offsets

CO JSEM ZJEDNODUSIL A PROC TO NEVADI
------------------------------------
1. NAHODNE VARIANTY DLAZDIC. Hra losuje variantu kazde dlazdice cesty, zdi a cela
   pres Godoti RandomNumberGenerator se seedem hash(level.id) ^ konstanta. Godoti
   hash() a jeho PCG32 tady nereprodukuju — losuje se Pythonim random.Random se
   stabilnim seedem. Rozlozeni variant tedy NENI stejne jako ve hre. Nevadi: vsechny
   varianty jsou tentyz motiv v tomtez rastru a tentyz atlas; menit se muze jen to,
   ktera z nich lezi na ktere bunce. Meritko, paleta ani hrany se tim nehnou, a to
   je jedine, na co se tady divame.
2. DEKORACE (DecorLayer, Z_DECOR) a mlha (Z_FOG) se nekresli. Dekorace je seedovany
   rozsyp rekvizit a mlha je cely herni stav; obojí by zakrylo prave to, co se ma
   merit. Podklad pod nohama tvora tim nezmeni raster.
3. MSAA. Hra ma msaa_2d=8x, takze jeji vektorove elipsy (zar, stin) maji hladke hrany.
   Tady se kresli 4x zvetsene a zmensi se box filtrem — to je totez, co dela resolve
   MSAA, jen s mensim poctem vzorku. Textury to nijak neovlivnuje: ty jdou NEAREST.
4. draw_texture_rect s desetinnym rozmerem (halo kolem tela vychazi napr. 119.04 px)
   se zaokrouhli na cely pixel. Telo samotne je vzdy presne cele (32*3 = 96), takze
   MERENE cislo je exaktni; zaokrouhluje se jen mekky zaves kolem nej.
5. Tvor stoji, nechodi. Zadny pohyb po ceste, zadne statusy (Boredom, Slow, chevrony),
   zadny hit flash — ty popisuji herni stav, ne art.

Pouziti
-------
  python tools/board_preview.py assets/distractions/clickbait_frame_1.png --out build/nahled.png
  python tools/board_preview.py --set clickbait --gif build/chuze.gif
  python tools/board_preview.py --compare clickbait energy_drink --out build/srovnani.png
  python tools/board_preview.py --set social_media_binge --level 1 --zoom 2 --out build/boss.png

Jako knihovna:
  from board_preview import render_board
  img = render_board("clickbait", compare="social_media_binge")
"""

from __future__ import annotations

import argparse
import math
import os
import random
import re
import sys

from PIL import Image, ImageDraw, ImageFont

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(PROJ, "tools")
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)

# Uz hotove nastroje, ne psat znovu: art_check umi posuny z anim_tuning, style_audit fps.
# Holds nikdo z nich necte, ty si dole parsuju sam.
from art_check import load_tuning as _load_offsets          # noqa: E402
from style_audit import load_tuning as _load_fps            # noqa: E402

ASSETS = os.path.join(PROJ, "assets")
DATA = os.path.join(PROJ, "data")

# Vzorkovani vektorovych elips. Hra ma msaa_2d=8x; 4x4 = 16 vzorku je vic nez dost.
SS = 4

# Fallback rychlost rucne kreslenych snimku — DistractionAnimator.SPRITE_FPS.
SPRITE_FPS = 12.0
DEATH_FPS = 12.0


# ===================================================================== data.gd
#
# Meritko se necopiruje, cte se. Prave tady vznikla ta chyba, kvuli ktere tenhle
# soubor existuje: tri ruzna mista mela vlastni tvrdou konstantu.


def _read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def _load_grid():
    """GRID a TERRAIN_ART_PX primo ze scripts/data.gd."""
    txt = _read(os.path.join(PROJ, "scripts", "data.gd"))
    m = re.search(r"const\s+GRID\s*:=\s*\{(.*?)\n\}", txt, re.S)
    if not m:
        raise SystemExit("board_preview: v scripts/data.gd nejde najit const GRID")
    grid = {k: int(v) for k, v in re.findall(r'"(\w+)"\s*:\s*(-?\d+)', m.group(1))}
    m = re.search(r"const\s+TERRAIN_ART_PX\s*:=\s*(\d+)", txt)
    if not m:
        raise SystemExit("board_preview: v scripts/data.gd nejde najit TERRAIN_ART_PX")
    grid["art_px"] = int(m.group(1))
    return grid


GRID = _load_grid()
TILE = GRID["tile"]
COLS = GRID["cols"]
ROWS = GRID["rows"]
ART_PX = GRID["art_px"]
FIELD_W = COLS * TILE
FIELD_H = ROWS * TILE


def pixel_scale():
    """Data.pixel_scale() — kolik bodu obrazovky je jeden ART pixel. Dnes 3."""
    return max(1.0, math.floor(TILE / float(ART_PX)))


PS = pixel_scale()


# ================================================================ .tres cteni


def _vec2i_list(txt, field):
    m = re.search(field + r"\s*=\s*Array\[Vector2i\]\(\[(.*?)\]\)", txt, re.S)
    if not m:
        return []
    return [(int(x), int(y)) for x, y in
            re.findall(r"Vector2i\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)", m.group(1))]


def parse_level(spec):
    """LevelData z .tres jako {objective, high_ground, path_cells, name}.

    `spec` je cislo levelu (1), jmeno (level_1) nebo cesta k .tres.
    """
    if isinstance(spec, int) or (isinstance(spec, str) and spec.isdigit()):
        path = os.path.join(DATA, "levels", "level_%d.tres" % int(spec))
    elif os.path.isfile(str(spec)):
        path = str(spec)
    else:
        path = os.path.join(DATA, "levels", "%s.tres" % spec)
    if not os.path.isfile(path):
        raise SystemExit("board_preview: level neexistuje: %s" % path)
    txt = _read(path)
    m = re.search(r"^objective\s*=\s*Vector2i\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)", txt, re.M)
    objective = (int(m.group(1)), int(m.group(2))) if m else (-1, -1)
    return {
        "name": os.path.splitext(os.path.basename(path))[0],
        "objective": objective,
        # Hra terén nikdy nekresli na cilove bunce (_build_corner_terrain), tak ani my.
        "solid": {c for c in _vec2i_list(txt, "high_ground") if c != objective},
        "path": set(_vec2i_list(txt, "path_cells")),
    }


def synth_level():
    """Rozumny kus mapy, kdyz zadny level nedostaneme.

    Pas cesty pres celou sirku a nad nim masa zdi s dirou — aby v jednom zaberu
    bylo videt podlahu, dlazdice cesty, celo zdi i stin, ktery zed vrha na podlahu.
    Kresli se do stejneho pole 40x19 jako opravdovy level, takze dal uz je to jedno.
    """
    solid, path = set(), set()
    wall_rows = (7, 8)
    for y in wall_rows:
        for x in range(4, COLS - 4):
            if 18 <= x <= 20:      # dira, aby zed nebyla jen rovny pruh
                continue
            solid.add((x, y))
    for y in range(9, 15):
        for x in range(COLS):
            path.add((x, y))
    return {"name": "(bez levelu)", "objective": (-1, -1), "solid": solid, "path": path}


def parse_distraction(did):
    """radius, color a is_flying z data/distractions/<id>.tres.

    Godot NEUKLADA vlastnost rovnou vychozi hodnote skriptu, takze chybejici radek
    znamena default z distraction_data.gd — ne "nemam data".
    """
    out = {"radius": 9.0, "color": "ff5566", "flying": False, "known": False}
    path = os.path.join(DATA, "distractions", "%s.tres" % did)
    if not os.path.isfile(path):
        return out
    txt = _read(path)
    out["known"] = True
    m = re.search(r"^radius\s*=\s*([0-9.]+)", txt, re.M)
    if m:
        out["radius"] = float(m.group(1))
    m = re.search(r'^color\s*=\s*"([0-9a-fA-F]{6})"', txt, re.M)
    if m:
        out["color"] = m.group(1)
    out["flying"] = bool(re.search(r"^is_flying\s*=\s*true", txt, re.M))
    return out


def _load_holds():
    """holds z data/anim_tuning.tres jako {klic: [int, ...]}.

    Offsety cte art_check.load_tuning, fps style_audit.load_tuning; holds zatim nikdo,
    a prave ony delaji z animace neco jineho nez rovnomerne prebliknuti.
    """
    path = os.path.join(DATA, "anim_tuning.tres")
    if not os.path.isfile(path):
        return {}
    m = re.search(r"^holds\s*=\s*\{(.*?)^\}", _read(path), re.M | re.S)
    if not m:
        return {}
    return {k: [int(v) for v in re.findall(r"-?\d+", body)]
            for k, body in re.findall(r'"([^"]+)"\s*:\s*\[(.*?)\]', m.group(1), re.S)}


OFFSETS = _load_offsets()
FPS = _load_fps()
HOLDS = _load_holds()


# ------------------------------------------------------- AnimTuning, 1:1 z GDScriptu


def _hold_at(arr, i):
    if i < 0 or i >= len(arr):
        return 1
    return max(1, int(arr[i]))


def hold_total(key, frame_count):
    """AnimTuning.hold_total — delka jedne smycky ve slotech, ne ve snimcich."""
    if frame_count <= 0:
        return 0
    arr = HOLDS.get(key, [])
    return sum(_hold_at(arr, i) for i in range(frame_count))


def frame_at(key, frame_count, slot, loop=True):
    """AnimTuning.frame_at — ktery snimek je na obrazovce ve slotu `slot`."""
    if frame_count <= 0:
        return 0
    arr = HOLDS.get(key, [])
    if not arr:
        return slot % frame_count if loop else max(0, min(slot, frame_count - 1))
    total = hold_total(key, frame_count)
    s = slot % total if loop else max(0, min(slot, total - 1))
    acc = 0
    for i in range(frame_count):
        acc += _hold_at(arr, i)
        if s < acc:
            return i
    return frame_count - 1


def fps_for(key, fallback):
    v = float(FPS.get(key, 0.0))
    return v if v > 0.0 else fallback


def offset_for(key, frame):
    arr = OFFSETS.get(key, [])
    if frame < 0 or frame >= len(arr):
        return (0, 0)
    return arr[frame]


# ================================================================ kresleni


def _composite(dst, src, x, y):
    """alpha_composite s orezem — src smi cucet za okraj desky."""
    if src.width <= 0 or src.height <= 0:
        return
    sx0 = max(0, -x)
    sy0 = max(0, -y)
    sx1 = min(src.width, dst.width - x)
    sy1 = min(src.height, dst.height - y)
    if sx1 <= sx0 or sy1 <= sy0:
        return
    if (sx0, sy0, sx1, sy1) != (0, 0, src.width, src.height):
        src = src.crop((sx0, sy0, sx1, sy1))
    dst.alpha_composite(src, dest=(x + sx0, y + sy0))


def _tint(img, rgba):
    """Godoti modulate: RGB se nasobi, alfa taky."""
    r, g, b, a = rgba
    if (r, g, b, a) == (255, 255, 255, 255):
        return img
    px = img.split()
    mul = lambda ch, k: ch.point(lambda v, k=k: int(v * k / 255.0 + 0.5))  # noqa: E731
    return Image.merge("RGBA", (mul(px[0], r), mul(px[1], g), mul(px[2], b),
                                mul(px[3], a)))


def _texture_rect(dst, tex, x, y, w, h, rgba=(255, 255, 255, 255)):
    """draw_texture_rect(tex, Rect2(x, y, w, h), false, modulate) s NEAREST filtrem.

    Rozmer se zaokrouhluje na cely pixel (viz zjednoduseni 4 v hlavicce): telo tvora
    ma vzdy cele meritko (32 art px * 3), tak se zaokrouhluje jen halo kolem nej.
    """
    iw, ih = max(1, int(round(w))), max(1, int(round(h)))
    im = tex.resize((iw, ih), Image.NEAREST) if (iw, ih) != tex.size else tex
    _composite(dst, _tint(im, rgba), int(round(x)), int(round(y)))


class _Fx:
    """Vrstva pro vektorove elipsy: kresli se SS-krat vetsi a na konci se zmensi.

    Poradi kresleni ma vyznam — elipsy se prekryvaji a alfa se sklada — takze kazda
    jde na vlastni pruhlednou vrstvu a slozi se hned. Downscale az uplne nakonec, aby
    to odpovidalo MSAA resolve, ktery taky resi cely hotovy obraz najednou.
    """

    def __init__(self, half):
        self.half = half
        self.size = half * 2
        self.img = Image.new("RGBA", (self.size * SS, self.size * SS), (0, 0, 0, 0))

    def ellipse(self, cx, cy, rx, ry, rgba):
        if rx <= 0 or ry <= 0 or rgba[3] <= 0:
            return
        layer = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
        x = (self.half + cx) * SS
        y = (self.half + cy) * SS
        ImageDraw.Draw(layer).ellipse(
            [x - rx * SS, y - ry * SS, x + rx * SS, y + ry * SS], fill=rgba)
        self.img.alpha_composite(layer)

    def blit(self, dst, cx, cy):
        small = self.img.resize((self.size, self.size), Image.BOX)
        _composite(dst, small, int(cx) - self.half, int(cy) - self.half)


def _hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def draw_ground_fx(board, cx, cy, vr, color_hex, flying, t, strength=1.0):
    """_draw_type_glow + _draw_contact_shadow z distraction_animator.gd.

    Obojí se v Godotu kresli pres draw_set_transform(offset, 0, scale) — bod p skonci
    na offset + p*scale, takze kruh o polomeru R je elipsa s poloosami (R*sx, R*sy)
    se stredem na offset. Offset se NESKALUJE.

    Vsimni si, ze do obou vstupuje vr (polovina SIRKY VYKRESLENEHO tela), ne def.radius.
    Radius je hitbox pro projektily; kdyby zar vychazela z nej, byla by u kazdeho tvora
    schovana pod jeho vlastnim spritem.
    """
    if vr <= 0:
        return
    half = int(math.ceil(vr * 2.8)) + 6
    fx = _Fx(half)
    col = _hex_rgb(color_hex)

    # --- zare typu: 4 kroky, vzdy alfa 0.10*sila, takze se skladaji do ~0.34 uprostred
    if strength > 0.01:
        for i in range(4):
            tt = i / 4.0
            rad = vr * (1.75 - tt * 0.95)
            a = int(round(255 * 0.10 * strength))
            fx.ellipse(0.0, vr * 0.55, rad * 1.0, rad * 0.45, col + (a,))

    # --- kontaktni stin: tri elipsy, dech podle _time (hra: 1 - |sin(t*6)| * 0.12)
    if strength > 0.01:
        drop = vr * (1.45 if flying else 0.72)
        alpha = (0.22 if flying else 0.42) * strength
        bob = 1.0 - abs(math.sin(t * 6.0)) * (0.06 if flying else 0.12)
        # Nikdy cerna: neutralne cerny stin cte jako dira, modre posunuty jako stin.
        base = (3, 7, 10)     # Color(0.01, 0.01, 0.04) po prevodu na 0..255
        for rad, k in ((1.15, 0.25), (0.85, 0.65), (0.50, 0.95)):
            a = int(round(255 * alpha * k))
            fx.ellipse(0.0, drop, vr * rad * bob, vr * rad * 0.42 * bob, base + (a,))

    fx.blit(board, cx, cy)


def draw_body(board, cx, cy, tex, off, color_hex, mirror=False):
    """_draw_texture_centred: silueta v barve typu + samotne telo.

    Halo je tentyz snimek natazeny o krok vic a obarveny def.color — silueta, ne kruh,
    aby to cetlo jako svitici tvor a ne jako lampa pod nim.
    """
    if mirror:
        tex = tex.transpose(Image.FLIP_LEFT_RIGHT)
    w = tex.width * PS
    h = tex.height * PS
    # off je v ART pixelech; hra ho nasobi (size.x / tex.width), coz je presne PS.
    sx = off[0] * PS * (-1 if mirror else 1)
    sy = off[1] * PS

    col = _hex_rgb(color_hex)
    step = max(2.0, w * 0.06)
    for ring, alpha in ((2.0, 0.09), (1.0, 0.16)):
        gw = w + step * ring * 2.0
        gh = h + step * ring * 2.0
        _texture_rect(board, tex, cx - gw * 0.5 + sx, cy - gh * 0.5 + sy, gw, gh,
                      col + (int(round(255 * alpha)),))
    _texture_rect(board, tex, cx - w * 0.5 + sx, cy - h * 0.5 + sy, w, h)
    return w, h


# ================================================================ deska


def _load_variants(folder, prefix=""):
    d = os.path.join(ASSETS, "terrain", folder)
    if not os.path.isdir(d):
        return []
    out = []
    for f in sorted(os.listdir(d)):
        if f.lower().endswith(".png") and f.startswith(prefix):
            out.append(Image.open(os.path.join(d, f)).convert("RGBA"))
    return out


def build_board(level):
    """Cele hraci pole 1920x912 ze skutecnych assetu, ve stejnem poradi vrstev jako hra.

    Z_BACKGROUND -40 -> Z_PATH -30 -> Z_WALL_SHADOW -25 -> Z_WALL_FACE -22 -> Z_TERRAIN -20
    """
    board = Image.new("RGBA", (FIELD_W, FIELD_H), (0x11, 0x14, 0x1f, 255))
    rng = random.Random(0xB0A2D)     # viz zjednoduseni 1 v hlavicce

    # --- podlaha: 640x304 nafouknuta na 1920x912, tedy presne x3, NEAREST
    bg_path = os.path.join(ASSETS, "background.png")
    if os.path.isfile(bg_path):
        bg = Image.open(bg_path).convert("RGBA")
        if (FIELD_W % bg.width) or (FIELD_H % bg.height):
            print("board_preview: POZOR, background.png %dx%d se do pole %dx%d nevejde "
                  "celym nasobkem — hra ho roztahne desetinne a pixely podlahy "
                  "prestanou byt ctvercove" % (bg.width, bg.height, FIELD_W, FIELD_H))
        board.alpha_composite(bg.resize((FIELD_W, FIELD_H), Image.NEAREST))

    # --- cesty: 16x16 dlazdice zvetsene na bunku (hra: img.resize NEAREST na 48)
    #
    # Dva bazenky podle nazvu, ne jeden michany: path_*.png je klidna podlaha,
    # accent_*.png nese synapsi. Hra je klade RUZNYMI pravidly — klid vsude, akcenty
    # v kratkych chuchvalcich — protoze rovnomerny rozsyp jasnych znacek cte jako
    # konfety. Dnes zadny accent_ soubor neexistuje a vetev je no-op; az prijde,
    # nahled se nerozejde s hrou tise.
    everything = _load_variants("path")
    accent = _load_variants("path", "accent_")
    calm = [t for t in everything if t not in accent]
    if calm:
        calm_t = [t.resize((TILE, TILE), Image.NEAREST) for t in calm]
        acc_t = [t.resize((TILE, TILE), Image.NEAREST) for t in accent]
        in_field = sorted(c for c in level["path"]
                          if 0 <= c[0] < COLS and 0 <= c[1] < ROWS)
        # level_1 ma path_cells i na rade -1 (nad polem); hra je kresli mimo vyrez.
        for (x, y) in in_field:
            board.alpha_composite(calm_t[rng.randrange(len(calm_t))],
                                  dest=(x * TILE, y * TILE))
        if acc_t and in_field:
            strands = max(1, int(len(in_field) * 0.06 / 4.0))    # ACCENT_SHARE / STRAND
            lanes = set(in_field)
            for _ in range(strands):
                head = in_field[rng.randrange(len(in_field))]
                pick = acc_t[rng.randrange(len(acc_t))]
                for _i in range(rng.randint(2, 4)):              # ACCENT_STRAND
                    if head not in lanes or head in level["solid"]:
                        break
                    board.alpha_composite(pick, dest=(head[0] * TILE, head[1] * TILE))
                    step = ((1, 0), (-1, 0), (0, 1), (0, -1))[rng.randrange(4)]
                    head = (head[0] + step[0], head[1] + step[1])

    solid = level["solid"]

    # --- stin zdi (WallShadow): pas pod jiznim okrajem masy + boci ambient occlusion
    faces = _load_variants("face")
    face_h = 24 if faces else 0          # Game.WALL_FACE_H, jen kdyz celo opravdu existuje
    shadow = Image.new("RGBA", (FIELD_W, FIELD_H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    near = (4, 7, 16, 158)               # Color(0.016, 0.027, 0.063, 0.62)
    far = (4, 7, 16, 77)                 # ... alpha 0.30
    depth, side = 12, 4
    for (x, y) in solid:
        below = (x, y + 1)
        if below not in solid and below[1] < ROWS:
            px = x * TILE
            py = below[1] * TILE + face_h
            sd.rectangle([px, py, px + TILE - 1, py + depth // 2 - 1], fill=near)
            sd.rectangle([px, py + depth // 2, px + TILE - 1, py + depth - 1], fill=far)
        for dx in (-1, 1):
            sx = x + dx
            if (sx, y) in solid or sx < 0 or sx >= COLS:
                continue
            inset = TILE - side if dx < 0 else 0
            px = sx * TILE + inset
            sd.rectangle([px, y * TILE, px + side - 1, y * TILE + TILE - 1], fill=far)
    board.alpha_composite(shadow)

    # --- celo zdi (WallFace): 16x8 art natazeny na 48x24, jen na jiznim okraji masy
    if faces:
        for (x, y) in sorted(solid):
            below = (x, y + 1)
            if below in solid or below[1] >= ROWS:
                continue
            tex = faces[rng.randrange(len(faces))]
            _texture_rect(board, tex, x * TILE, below[1] * TILE, TILE, face_h)

    # --- zdi (dual grid): dlazdice sedi na VRCHOLECH mrizky, ne v bunkach
    atlas_path = os.path.join(ASSETS, "terrain", "high_ground_atlas.png")
    if solid and os.path.isfile(atlas_path):
        atlas = Image.open(atlas_path).convert("RGBA")
        # Atlas uz je ulozeny v hernim rastru (48 px na dlazdici = 16 art px x3).
        variants = max(1, atlas.height // (TILE * 4))
        for j in range(ROWS + 1):
            for i in range(COLS + 1):
                m = 0
                if (i - 1, j - 1) in solid: m |= 1     # NW
                if (i, j - 1) in solid: m |= 2         # NE
                if (i - 1, j) in solid: m |= 4         # SW
                if (i, j) in solid: m |= 8             # SE
                if m == 0:
                    continue
                v = rng.randrange(variants)
                ax = (m % 4) * TILE
                ay = (v * 4 + m // 4) * TILE
                tile = atlas.crop((ax, ay, ax + TILE, ay + TILE))
                _composite(board, tile, i * TILE - TILE // 2, j * TILE - TILE // 2)
    return board


# ================================================================ sady spritu


DIR_SUFFIX = {"south": "", "north": "_north", "east": "_east", "west": "_west",
              "attack": "_attack", "death": "_death"}
SUFFIXES = ("_north", "_east", "_west", "_attack", "_death")
VARIANTS = ("_b", "_c", "_d", "_e", "_f")


class SpriteSet:
    """Jedna sada snimku plus vsechno, co hra potrebuje k jejimu vykresleni."""

    def __init__(self, base_id, key, frames, mirror=False, source=""):
        self.base_id = base_id          # klic do data/distractions/
        self.key = key                  # klic do anim_tuning (stem souboru)
        self.frames = frames
        self.mirror = mirror
        self.source = source
        d = parse_distraction(base_id)
        self.color = d["color"]
        self.radius = d["radius"]
        self.flying = d["flying"]
        self.known = d["known"]
        # _visual_radius bere PRVNI snimek sady _frame_textures, coz je VZDY jih —
        # i kdyz se prave kresli vychod. Bez tohohle by zar u ruzne sirokych sad
        # dychala jinak nez ve hre.
        south = _frames_for(base_id, "")
        ref = south[0] if south else (frames[0] if frames else None)
        self.vr = (ref.width * PS * 0.5) if ref is not None else 0.0
        self.fps = fps_for(self.key, DEATH_FPS if key.endswith("_death") else SPRITE_FPS)
        self.loop = not key.endswith("_death")   # smrt hraje jednou a drzi posledni snimek

    def __repr__(self):
        return "SpriteSet(%s, %d snimku)" % (self.key, len(self.frames))

    def art_size(self):
        f = self.frames[0]
        return f.width, f.height

    def drawn_size(self):
        w, h = self.art_size()
        return w * PS, h * PS

    def cells(self):
        w, h = self.drawn_size()
        return w / float(TILE), h / float(TILE)


def _frames_for(base_id, suffix):
    """<id><smer>_frame_N.png, dokud snimky nedojdou — stejne jako _load_set()."""
    out = []
    for i in range(1, 33):
        p = os.path.join(ASSETS, "distractions", "%s%s_frame_%d.png" % (base_id, suffix, i))
        if not os.path.isfile(p):
            break
        out.append(Image.open(p).convert("RGBA"))
    return out


def _split_stem(stem):
    """Ze stemu souboru udela (base_id, klic_pro_tuning). Poradi odlupovani je dulezite:
    smer se odlupuje DRIV nez varianta, protoze `_east` zacina na `_e` a to je taky
    platna varianta (viz komentar v distraction_animator.gd)."""
    rest = stem
    for s in sorted(SUFFIXES, key=len, reverse=True):
        if rest.endswith(s):
            rest = rest[: -len(s)]
            break
    for v in VARIANTS:
        if rest.endswith(v):
            rest = rest[: -len(v)]
            break
    return rest, stem


def as_sprite(spec, direction="south"):
    """spec: SpriteSet | id sady | cesta k PNG | seznam cest k PNG."""
    if isinstance(spec, SpriteSet):
        return spec

    if isinstance(spec, (list, tuple)):
        paths = [str(p) for p in spec]
        frames = [Image.open(p).convert("RGBA") for p in paths]
        stem = re.sub(r"_frame_\d+$", "", os.path.splitext(os.path.basename(paths[0]))[0])
        base, key = _split_stem(stem)
        return SpriteSet(base, key, frames, source=paths[0])

    spec = str(spec)
    if os.path.isfile(spec):
        stem = re.sub(r"_frame_\d+$", "", os.path.splitext(os.path.basename(spec))[0])
        base, key = _split_stem(stem)
        return SpriteSet(base, key, [Image.open(spec).convert("RGBA")], source=spec)

    # id sady: `west` hra kresli jako zrcadleny `east`, kdyz vlastni zapad neexistuje
    suffix = DIR_SUFFIX.get(direction, "")
    frames = _frames_for(spec, suffix)
    mirror = False
    if not frames and direction == "west":
        frames = _frames_for(spec, "_east")
        suffix, mirror = "_east", True
    if not frames and direction != "south":
        frames = _frames_for(spec, "")
        suffix = ""
    if not frames:
        raise SystemExit("board_preview: zadne snimky pro '%s' (%s). Cekal jsem "
                         "assets/distractions/%s_frame_1.png" % (spec, direction, spec))
    return SpriteSet(spec, spec + suffix, frames, mirror=mirror,
                     source="assets/distractions/%s%s_frame_1.png" % (spec, suffix))


# ================================================================ rozvrh sceny


def _reach(px):
    """Do kolika bunek na KAZDOU stranu stredove bunky sprite zasahuje.

    Ne px/TILE. Tvor stoji na STREDU bunky, takze 96px sprite ma sice plochu 2x2 bunky,
    ale zasahuje do 3x3: pulka bunky vlevo, cela uprostred, pulka vpravo. Presne o tuhle
    pulbunku byl vyrez maly a bossovi utikaly nohy z obrazku.
    """
    return max(0, math.ceil((px / 2.0 - TILE / 2.0) / TILE))


def _window(centre, reach, want, total_cells):
    """Zacatek vyrezu: vycentrovany na `centre`, ale nikdy tak, aby uriznul tvora."""
    start = centre - want // 2
    start = min(start, centre - reach)                  # horni/levy okraj tvora uvnitr
    start = max(start, centre + reach + 1 - want)       # dolni/pravy okraj tvora uvnitr
    return max(0, min(start, total_cells - want))


def pick_stage(level, actors, cols, rows):
    """Kam tvory postavit a jaky vyrez desky ukazat.

    Hleda radek s dost volneho mista v celem sloupci, ktery tvor zabere (ne jen pod
    nohama), a nejlepe se zdi o kousek vys — aby v zaberu byla i zed s celem a stinem
    a bylo videt, jak je tvor velky PROTI nemu.
    """
    reach_x = [_reach(a.drawn_size()[0]) for a in actors]
    reach_y = max(_reach(a.drawn_size()[1]) for a in actors)
    span_x = [1 + 2 * r for r in reach_x]
    need_w = sum(span_x) + (len(span_x) - 1) + 2      # 1 volna bunka mezi tvory + okraje
    cols = min(COLS, max(cols, need_w))
    rows = min(ROWS, max(rows, 1 + 2 * reach_y + 2))

    solid = level["solid"]
    best = None
    for y in range(reach_y, ROWS - reach_y):          # tvor se musi vejit do pole
        run, run_best, run_x = 0, 0, 0
        for x in range(COLS):
            free = all((x, yy) not in solid for yy in range(y - reach_y, y + reach_y + 1))
            run = run + 1 if free else 0
            if run > run_best:
                run_best, run_x = run, x - run + 1
        if run_best < need_w:
            continue
        on_path = sum(1 for x in range(run_x, run_x + run_best) if (x, y) in level["path"])
        near_wall = any((x, yy) in solid
                        for yy in range(max(0, y - reach_y - 3), max(0, y - reach_y))
                        for x in range(run_x, run_x + run_best))
        score = (2 if near_wall else 0) + (1 if on_path > run_best * 0.5 else 0)
        score = score * 1000 + run_best - abs(y - ROWS // 2)
        if best is None or score > best[0]:
            best = (score, y, run_x, run_best)
    if best is None:                                   # pole bez volneho mista: doprostred
        best = (0, ROWS // 2, 0, COLS)

    _, stage_y, run_x, run_w = best

    # tvory vedle sebe, jednou volnou bunkou mezi nimi, vycentrovane na stred behu
    total = sum(span_x) + (len(span_x) - 1)
    x = run_x + run_w // 2 - total // 2
    x = max(run_x, min(x, run_x + run_w - total))
    cells = []
    for r in reach_x:
        cells.append((x + r, stage_y))
        x += 1 + 2 * r + 1

    lo, hi = cells[0][0] - reach_x[0], cells[-1][0] + reach_x[-1]
    win_x = _window((lo + hi) // 2, (hi - lo) // 2, cols, COLS)
    win_y = _window(stage_y, reach_y, rows, ROWS)
    return cells, (win_x, win_y, cols, rows)


# ================================================================ mrizka + popisek


def _font(size):
    for p in (r"C:\Windows\Fonts\consola.ttf", r"C:\Windows\Fonts\segoeui.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"):
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            continue
    return ImageFont.load_default()


def draw_grid(img, win, actors, cells):
    """Mrizka bunek a obrys toho, co tvor doopravdy zabira.

    Bez ni se na obrazku pozna leda "vypada mensi"; s ni je videt PRESNE, kolik bunek
    tvor pokryva, a to uz je merene tvrzeni.
    """
    win_x, win_y, cols, rows = win
    over = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    for i in range(cols + 1):
        x = i * TILE
        d.line([(x, 0), (x, rows * TILE)], fill=(255, 255, 255, 38))
    for j in range(rows + 1):
        y = j * TILE
        d.line([(0, y), (cols * TILE, y)], fill=(255, 255, 255, 38))

    for spr, (cx, cy) in zip(actors, cells):
        w, h = spr.drawn_size()
        px = (cx - win_x) * TILE + TILE // 2
        py = (cy - win_y) * TILE + TILE // 2
        # presny obdelnik spritu
        d.rectangle([px - w / 2, py - h / 2, px + w / 2 - 1, py + h / 2 - 1],
                    outline=(255, 214, 92, 200))
        # a bunky, ktere prekryva
        c0x = math.floor((px - w / 2) / TILE)
        c1x = math.ceil((px + w / 2) / TILE)
        c0y = math.floor((py - h / 2) / TILE)
        c1y = math.ceil((py + h / 2) / TILE)
        d.rectangle([c0x * TILE, c0y * TILE, c1x * TILE - 1, c1y * TILE - 1],
                    outline=(92, 226, 255, 170))
    img.alpha_composite(over)


def caption_lines(level, actors, grid=True):
    head = ("deska: %s | bunka %d px | art %d px | meritko x%d | pole %dx%d"
            % (level["name"], TILE, ART_PX, int(PS), FIELD_W, FIELD_H))
    lines = [head]
    if grid:
        # Dva ramy, dve ruzna tvrzeni, a plete se to: 96px sprite ma PLOCHU 2x2 bunky,
        # ale protoze stoji na STREDU bunky, zasahuje do 3x3. Obojí je pravda a obojí
        # je potreba videt — plocha je to merene cislo, presah je to, co hrac vnima.
        lines.append("zluty ram = telo spritu (jeho plocha v bunkach nize) | "
                     "modry ram = bunky, do kterych zasahuje")
    for s in actors:
        aw, ah = s.art_size()
        dw, dh = s.drawn_size()
        cw, ch = s.cells()
        warn = ""
        if aw % ART_PX or ah % ART_PX:
            warn = "  <-- POZOR: %dx%d neni nasobek %d" % (aw, ah, ART_PX)
        elif abs(cw - round(cw)) > 1e-6 or abs(ch - round(ch)) > 1e-6:
            warn = "  <-- POZOR: nesedi na rastr bunek"
        if not s.known:
            warn += "  (bez data/distractions/%s.tres — zar/stin z defaultu)" % s.base_id
        lines.append("%-22s art %dx%d -> na desce %dx%d px = %.2f x %.2f bunky%s"
                     % (s.key, aw, ah, dw, dh, cw, ch, warn))
    return lines


def add_caption(img, lines):
    """Popisek pod obrazek. Plátno se rozsiri, kdyz je text sirsi nez vyrez desky —
    orezany popisek by z merenych cisel udelal pulku cisla, a to je horsi nez zadna."""
    f = _font(13)
    pad, lh = 8, 17
    d0 = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    text_w = max(int(d0.textlength(s, font=f)) for s in lines) + pad * 2
    w = max(img.width, text_w)
    h = pad * 2 + lh * len(lines)
    out = Image.new("RGBA", (w, img.height + h), (14, 16, 24, 255))
    out.alpha_composite(img, dest=((w - img.width) // 2, 0))
    d = ImageDraw.Draw(out)
    for i, line in enumerate(lines):
        d.text((pad, img.height + pad + i * lh), line, font=f,
               fill=(214, 220, 236, 255) if i else (140, 200, 255, 255))
    return out


# ================================================================ hlavni API


def render_board(sprites, level=None, cols=9, rows=5, grid=True, compare=None,
                 animate=False, zoom=1, caption=True, direction="south"):
    """Vykresli sprite na skutecnou desku.

    sprites   sada spritu: id ("clickbait"), cesta k PNG, seznam cest, nebo SpriteSet
    level     None | cislo levelu | jmeno | cesta k data/levels/*.tres
    cols/rows velikost vyrezu v BUNKACH (roste sama, kdyz se tvor nevejde)
    grid      mrizka bunek a obrys toho, co tvor zabira
    compare   dalsi tvor (nebo seznam) postaveny vedle, aby byla videt velikost v kontextu
    animate   True vrati SEZNAM snimku pro GIF, s casovanim z data/anim_tuning.tres
              VCETNE drzeni snimku — drzeny snimek se proste zopakuje

    Vraci PIL.Image, nebo [PIL.Image] kdyz animate=True.
    """
    actors = [as_sprite(sprites, direction)]
    if compare is not None:
        if isinstance(compare, (list, tuple)) and not all(
                isinstance(c, str) and os.path.isfile(c) for c in compare):
            actors += [as_sprite(c, direction) for c in compare]
        else:
            actors.append(as_sprite(compare, direction))

    lvl = synth_level() if level is None else parse_level(level)
    base = build_board(lvl)
    cells, win = pick_stage(lvl, actors, cols, rows)
    win_x, win_y, wcols, wrows = win
    crop = (win_x * TILE, win_y * TILE, (win_x + wcols) * TILE, (win_y + wrows) * TILE)

    # Kolik snimku vyrobit: slot je zakladni takt animace, drzeny snimek zabira vic slotu
    if animate:
        slots = max(hold_total(a.key, len(a.frames)) for a in actors)
        slots = max(1, slots)
    else:
        slots = 1

    lines = caption_lines(lvl, actors, grid) if caption else None
    out = []
    for slot in range(slots):
        board = base.copy()
        for spr, (cxc, cyc) in zip(actors, cells):
            cx = cxc * TILE + TILE // 2
            cy = cyc * TILE + TILE // 2
            n = len(spr.frames)
            idx = frame_at(spr.key, n, slot, spr.loop) if animate else 0
            # _time, ze ktereho hra pocita dech stinu; slot = int(_time * fps)
            t = slot / spr.fps if animate else 0.0
            draw_ground_fx(board, cx, cy, spr.vr, spr.color, spr.flying, t)
            draw_body(board, cx, cy, spr.frames[idx], offset_for(spr.key, idx),
                      spr.color, spr.mirror)
        img = board.crop(crop)
        if grid:
            draw_grid(img, win, actors, cells)
        if zoom > 1:
            img = img.resize((img.width * zoom, img.height * zoom), Image.NEAREST)
        if lines:
            img = add_caption(img, lines)
        out.append(img)
    return out if animate else out[0]


def save_gif(frames, path, fps):
    """GIF s casovanim animace. Paleta se bere z prvniho snimku a sdili se, jinak by
    kazdy snimek kvantoval jinak a klidna animace by blikala."""
    os.makedirs(os.path.dirname(os.path.abspath(path)) or ".", exist_ok=True)
    rgb = [f.convert("RGB") for f in frames]
    pal = rgb[0].quantize(colors=255, method=Image.MAXCOVERAGE)
    q = [im.quantize(palette=pal, dither=Image.NONE) for im in rgb]
    q[0].save(path, save_all=True, append_images=q[1:],
              duration=int(round(1000.0 / max(1.0, fps))), loop=0, disposal=2,
              optimize=False)


# ================================================================ CLI


def main():
    ap = argparse.ArgumentParser(
        description="Sprite na skutecne desce, tak jak ho uvidi hrac.")
    ap.add_argument("files", nargs="*",
                    help="cesty k PNG snimkum (nebo pouzij --set)")
    ap.add_argument("--set", dest="set_id", help="id sady, napr. clickbait")
    ap.add_argument("--compare", nargs="+", metavar="ID",
                    help="postav vedle sebe dva a vic tvoru")
    ap.add_argument("--dir", default="south",
                    choices=sorted(DIR_SUFFIX), help="ktery pohled (default south)")
    ap.add_argument("--level", help="cislo levelu, jmeno nebo cesta k .tres")
    ap.add_argument("--cols", type=int, default=9, help="sirka vyrezu v bunkach")
    ap.add_argument("--rows", type=int, default=5, help="vyska vyrezu v bunkach")
    ap.add_argument("--no-grid", action="store_true", help="bez mrizky bunek")
    ap.add_argument("--no-caption", action="store_true", help="bez popisku pod obrazkem")
    ap.add_argument("--zoom", type=int, default=1, help="zvetseni NEAREST (default 1:1)")
    ap.add_argument("--out", help="kam ulozit staticky nahled (.png)")
    ap.add_argument("--gif", help="kam ulozit animaci (.gif)")
    args = ap.parse_args()

    if args.compare:
        first, rest = args.compare[0], args.compare[1:]
    elif args.set_id:
        first, rest = args.set_id, None
    elif args.files:
        first, rest = (args.files if len(args.files) > 1 else args.files[0]), None
    else:
        ap.error("zadej PNG soubory, --set nebo --compare")

    common = dict(level=args.level, cols=args.cols, rows=args.rows,
                  grid=not args.no_grid, compare=rest, zoom=args.zoom,
                  caption=not args.no_caption, direction=args.dir)

    if not args.out and not args.gif:
        args.out = os.path.join(PROJ, "build", "board_preview.png")

    if args.out:
        img = render_board(first, animate=False, **common)
        os.makedirs(os.path.dirname(os.path.abspath(args.out)) or ".", exist_ok=True)
        img.convert("RGB").save(args.out)
        print("napsano %s (%dx%d)" % (args.out, img.width, img.height))

    if args.gif:
        frames = render_board(first, animate=True, **common)
        spr = as_sprite(first, args.dir)
        save_gif(frames, args.gif, spr.fps)
        print("napsano %s (%d snimku, %.1f fps, klic %s)"
              % (args.gif, len(frames), spr.fps, spr.key))

    # Merene tvrzeni, ne dojem: vytiskni, kolik bunek kazdy tvor doopravdy zabira.
    actors = [as_sprite(first, args.dir)] + [as_sprite(c, args.dir) for c in (rest or [])]
    for s in actors:
        aw, ah = s.art_size()
        dw, dh = s.drawn_size()
        cw, ch = s.cells()
        print("  %-22s art %dx%d -> %dx%d px -> %.2f x %.2f bunky"
              % (s.key, aw, ah, dw, dh, cw, ch))


if __name__ == "__main__":
    main()
