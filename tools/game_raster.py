# Rastr hry — JEDNO misto, odkud ho berou vsechny nastroje.
#
# Meritko se nekopiruje, cte se ze scripts/data.gd. Duvod je zapsany primo tam:
# "Every creature, defender and tower head used to hardcode 2.0 in three separate files
# while the ground ran at 3.0." V Pythonu se totez stalo znovu — 17. 8. 2026 se data.gd
# presunulo z 16/x3 na 24/x2, ale gen_ui.py (CELL=16, SCALE=3), style_audit.py
# (CELL_ART_PX=16) a art_check.py (TARGET_SCREEN_PIXEL=3) o tom nevedely a schvalovaly
# art podle rastru, ktery uz neplati.
#
# Kdo potrebuje velikost bunky nebo meritko, importuje odsud. Vlastni konstantu si nikdo
# nezavadi — presne tahle chyba uz se v tomhle projektu stala dvakrat.
import os
import re

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_GD = os.path.join(PROJ, "scripts", "data.gd")


def _load():
    with open(DATA_GD, encoding="utf-8", errors="replace") as fh:
        txt = fh.read()
    m = re.search(r"const\s+GRID\s*:=\s*\{(.*?)\n\}", txt, re.S)
    if not m:
        raise RuntimeError(f"v {DATA_GD} nejde najit const GRID")
    grid = {k: int(v) for k, v in re.findall(r'"(\w+)"\s*:\s*(-?\d+)', m.group(1))}
    m = re.search(r"const\s+TERRAIN_ART_PX\s*:=\s*(\d+)", txt)
    if not m:
        raise RuntimeError(f"v {DATA_GD} nejde najit TERRAIN_ART_PX")
    grid["art_px"] = int(m.group(1))
    return grid


GRID = _load()

TILE = GRID["tile"]            # bunka v pixelech OBRAZOVKY
ART_PX = GRID["art_px"]        # bunka v pixelech ARTU
COLS = GRID.get("cols", 0)
ROWS = GRID.get("rows", 0)

# Tentyz vypocet jako Data.pixel_scale(): kolik pixelu obrazovky je jeden pixel artu.
SCALE = max(1, TILE // ART_PX)


def fits(n):
    """Sedne strana `n` px artu na bunku? Nasobek nebo cisty delitel."""
    return n > 0 and (n % ART_PX == 0 or ART_PX % n == 0)


def check(w, h):
    """-> (ok, veta pro cloveka). Kazda strana zvlast: 16x8 je platna dlazdice cesty,
    kdezto 24x20 je preklep, ktery se ve hre projevi az jako o pixel posunuta vez."""
    bad = [f"{lbl} {n} px" for n, lbl in ((w, "šířka"), (h, "výška")) if not fits(n)]
    if not bad:
        return True, f"sedí na rastr (buňka = {ART_PX} px artu, ×{SCALE} na obrazovce)"
    return False, (" a ".join(bad) + f" — není násobek {ART_PX} ani jeho dělitel; "
                   f"buňka hry je {ART_PX} px artu (×{SCALE} na obrazovce)")
