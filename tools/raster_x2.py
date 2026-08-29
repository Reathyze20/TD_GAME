"""Prechod hry na dvojnasobny rastr: 16 px artu na bunku -> 32 px artu na bunku.

    python tools/raster_x2.py            # ukaze, co by udelal
    python tools/raster_x2.py --apply

CO SE MENI A PROC

Hra kreslila bunku jako 48 px obrazovky a 16 px artu, tedy meritko x3. Postava mela
32 px artu = 2 bunky. Mereni proti latce (1623 originalu z PixelLabu, viz
docs/art/style_bible_measured.md) ukazalo, ze postava na latce je 59 px vysoka a nase 29 px --
a ze z teto JEDINE volby plyne skoro vsechno ostatni: dvojnasobny sum, trojnasobna
hustota detailu a obrys, ktery zabira ctvrtinu prisery misto osminy.

Novy rastr:

    bunka   48 px obrazovky  ->  64 px obrazovky
    bunka   16 px artu       ->  32 px artu
    meritko x3               ->  x2
    mrizka  40x19            ->  30x14

PULDORYS V BUNKACH SE NEMENI. Postava mela 32/16 = 2 bunky a ma 64/32 = 2 bunky.
Boss mel 64/16 = 4 bunky a ma 128/32 = 4 bunky. Meni se jen to, kolik informace se do
spritu vejde. Deska ukaze min bunek (30x14 misto 40x19), protoze bunka na obrazovce
vyrostla -- to je zoom o tretinu dovnitr a je to nevyhnutelne: x1.5 by pixel art
zniclo, takze mezi x3 a x2 neni nic.

CO TENHLE SKRIPT NEDELA

Nepridava detail. Zvetseni x2 nejblizsim sousedem je PRESNE tytez pixely, jen vetsi --
hra bude vypadat stejne jako predtim. Detail prijde az tim, ze se sprity ZNOVU
vygeneruji do noveho platna (Sprite Studio, 64 px). Tenhle skript stavi nadobu;
naplnit ji je prace pro generator.

Proto je to x2 a ne prekresleni: potrebujeme, aby hra bezela a vypadala stejne uz
ted, a aby kazdy nove vygenerovany sprite pristal do spravneho rastru.

VYJIMKY

  assets/src/**            koncepty a zdroje, do hry nejdou
  assets/terrain/brain_*   1024x1024 zdrojove textury pro tools/tiles.py, nic je
                           v behu hry nenacita (overeno grepem)
  assets/background.png    sum 1:1, ne sprite -- meni se na PRESNY novy rozmer pole
                           (960x448 art px = 1920x896 obrazovky pri x2), viz nize
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys

from PIL import Image

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(PROJ, "assets")
STAMP = os.path.join(ASSETS, ".raster.json")

FACTOR = 2
NEW_ART_PX = 32          # px artu na bunku po prechodu
NEW_COLS, NEW_ROWS = 30, 14
NEW_TILE = 64            # px obrazovky na bunku

# Slozky, ktere hra opravdu kresli. Poradi je jen kvuli vypisu.
SLOZKY = ["towers", "defenders", "distractions", "decor", "markers", "terrain"]

# Vynechavky uvnitr tech slozek.
def preskocit(rel: str) -> str:
    """Vraci duvod preskoceni, nebo "" kdyz se soubor ma zvetsit."""
    parts = rel.replace("\\", "/").split("/")
    if parts[0] == "src":
        return "zdroj/koncept, do hry nejde"
    if parts[0] == "terrain" and os.path.basename(rel).startswith("brain_"):
        return "zdrojova textura pro tools/tiles.py, hra ji nenacita"
    if os.path.basename(rel) == "phantom_buzz_spritesheet.png":
        # 1024x1024 list, ze ktereho se vyrezalo 86 jednotlivych framu vedle nej.
        # Nereferencuje ho zadny skript, data ani nastroj (overeno grepem), takze
        # zvetsovat ho na 2048x2048 by bylo jen ctyrikrat vic mrtve vahy v repu.
        return "zdrojovy list, frames vedle nej jsou to, co hra kresli"
    return ""


def pole_art_px() -> tuple[int, int]:
    """Rozmer HRACIHO POLE v pixelech artu po prechodu."""
    return NEW_COLS * NEW_ART_PX, NEW_ROWS * NEW_ART_PX


def zvetsit(path: str, apply: bool) -> tuple[int, int, int, int]:
    with Image.open(path) as im:
        w, h = im.size
        nw, nh = w * FACTOR, h * FACTOR
        if apply:
            out = im.convert("RGBA").resize((nw, nh), Image.NEAREST)
            out.save(path)
    return w, h, nw, nh


def pozadi(path: str, apply: bool) -> tuple[int, int, int, int]:
    """Pozadi je sum, ne sprite -- roztahuje se pres cele pole, takze musi mit PRESNE
    jeho rozmer v pixelech artu. Jinak ho engine natahne necelym cislem a sum zacne
    kmitat pri kazdem posunu.

    x2 by dalo 1280x608, ale pole ma nove 960x448. Prevzorkovani nejblizsim sousedem
    na necely pomer u sumu nevadi -- neni v nem struktura, kterou by slo rozbit -- a
    u cehokoli jineho by to byla chyba.
    """
    nw, nh = pole_art_px()
    with Image.open(path) as im:
        w, h = im.size
        if apply:
            im.convert("RGBA").resize((nw, nh), Image.NEAREST).save(path)
    return w, h, nw, nh


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Prechod artu na 32 px na bunku (x2).")
    ap.add_argument("--apply", action="store_true", help="opravdu zapsat")
    args = ap.parse_args(argv)

    if os.path.isfile(STAMP):
        with open(STAMP, encoding="utf-8") as f:
            st = json.load(f)
        if int(st.get("art_px", 0)) >= NEW_ART_PX:
            print(f"Art uz je na {st['art_px']} px na buňku (razítko {STAMP}).")
            print("Druhé spuštění by ho zvětšilo znovu — končím.")
            return 1

    soubory, preskoceno = [], []
    for slozka in SLOZKY:
        for p in glob.glob(os.path.join(ASSETS, slozka, "**", "*.png"), recursive=True):
            rel = os.path.relpath(p, ASSETS)
            duvod = preskocit(rel)
            (preskoceno if duvod else soubory).append((rel, duvod))

    bg = os.path.join(ASSETS, "background.png")
    print(f"{'ZKUŠEBNÍ BĚH' if not args.apply else 'ZAPISUJI'} — faktor ×{FACTOR}\n")

    zmeny: dict[str, int] = {}
    for rel, _ in sorted(soubory):
        w, h, nw, nh = zvetsit(os.path.join(ASSETS, rel), args.apply)
        zmeny[f"{w}×{h} → {nw}×{nh}"] = zmeny.get(f"{w}×{h} → {nw}×{nh}", 0) + 1

    for k, v in sorted(zmeny.items(), key=lambda kv: -kv[1]):
        print(f"  {v:4d}×   {k}")

    if os.path.isfile(bg):
        w, h, nw, nh = pozadi(bg, args.apply)
        print(f"\n  pozadí (šum, na přesný rozměr pole):  {w}×{h} → {nw}×{nh}")

    print(f"\n  přeskočeno: {len(preskoceno)} souborů")
    for rel, duvod in sorted(preskoceno)[:4]:
        print(f"    {rel}  — {duvod}")
    if len(preskoceno) > 4:
        print(f"    … a {len(preskoceno) - 4} dalších")

    print(f"\n  celkem ke zvětšení: {len(soubory)}")

    if not args.apply:
        print("\nNic se nezapsalo. Spusť s --apply.")
        return 0

    with open(STAMP, "w", encoding="utf-8") as f:
        json.dump({"art_px": NEW_ART_PX, "tile": NEW_TILE,
                   "cols": NEW_COLS, "rows": NEW_ROWS,
                   "note": "razítko proti dvojímu zvětšení; ruší se smazáním"}, f,
                  ensure_ascii=False, indent=1)
    print(f"\nHotovo. Razítko: {os.path.relpath(STAMP, PROJ)}")
    print("Teď ještě: scripts/data.gd (tile 64, TERRAIN_ART_PX 32, mřížka 30×14)")
    print("a přeimportovat: Godot --headless --path . --import")
    return 0


if __name__ == "__main__":
    sys.exit(main())
