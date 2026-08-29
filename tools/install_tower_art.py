# Nainstaluje vygenerovane hlavy vezi z build/iso_art/tower_*/ do assets/towers/.
#
# CO PRITOM DELA NAVIC
#
# 1) Zahodi ODPADLE KUSY. Generator obcas nechá vedle predmetu drobky -- u real_hobby to
#    byl zbytek nesmyslneho textu pod pultem. Zahazuji se souvisle oblasti mensi nez
#    MIN_PART podilu nejvetsi oblasti; hlavni predmet je vzdy ta nejvetsi.
# 2) NEPREPISUJE zalohu. build/_tower_backup/ drzi puvodni mysticke hlavy z doby pred
#    zmenou rejstriku (viz docs/art/iso_bible.md kap. 2c) a musi prezit i tuhle vymenu.
#
# Platno zustava 112x112, protoze na nem lezely i stare hlavy a hra podle nej kotvi.
#
# OSMISMERNE HLAVY (--dirs)
#
# `create_8_direction_object` sklada do build/iso_art/obj_<klic>/<smer>.png. Instaluji se
# jako head_<klic>_<smer>.png a plati u nich jedno pravidlo navic: BUD VSECH OSM, NEBO
# ZADNY. tower.gd pri chybejicim smeru cely slovnik zahodi a spadne zpatky na jednu
# statickou hlavu -- coz je tise horsi nez chyba, protoze vez pak funguje, jen se neotaci.
# Proto se neuplna sada odmita nahlas a nic se nezapise.
#
#   python tools/install_tower_art.py [--dry]
#   python tools/install_tower_art.py --dirs focus_timer [--dry]
import os
import shutil
import sys

import numpy as np
from PIL import Image

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(PROJ, "build", "iso_art")
DST = os.path.join(PROJ, "assets", "towers")
KEEP = os.path.join(PROJ, "build", "_tower_backup")
MIN_PART = 0.06


def components(mask):
    """Souvisle oblasti (8-okoli) bez scipy -- fronta, at nejsou dalsi zavislosti."""
    h, w = mask.shape
    lab = np.zeros((h, w), int)
    cur = 0
    for sy in range(h):
        for sx in range(w):
            if not mask[sy, sx] or lab[sy, sx]:
                continue
            cur += 1
            stack = [(sy, sx)]
            lab[sy, sx] = cur
            while stack:
                y, x = stack.pop()
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = y + dy, x + dx
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not lab[ny, nx]:
                            lab[ny, nx] = cur
                            stack.append((ny, nx))
    return lab, cur


def clean(path, out, dry=False):
    im = Image.open(path).convert("RGBA")
    a = np.array(im)
    m = a[..., 3] > 8
    lab, n = components(m)
    if n > 1:
        sizes = [(int((lab == i).sum()), i) for i in range(1, n + 1)]
        sizes.sort(reverse=True)
        big = sizes[0][0]
        dropped = 0
        for sz, i in sizes[1:]:
            if sz < big * MIN_PART:
                a[..., 3][lab == i] = 0
                dropped += sz
        if dropped and not dry:
            print(f"    zahozeno {dropped} px v {len(sizes) - 1} drobcích")
    if not dry:
        Image.fromarray(a, "RGBA").save(out)


DIRS = ["east", "south-east", "south", "south-west",
        "west", "north-west", "north", "north-east"]


## Posun jmen o N kroku po 45 stupnich. PixelLab sve smery obcas oznaci se stalym
## posunem: sada 1 (21. 8. 2026) mela jmena spravne, sada 4 (22. 8.) byla cela otocena
## o 180 stupnu -- jeji "east" mel hlaven doleva. Neni to rozdil konvence, ktery by sel
## nastavit jednou provzdy; vaze se to k obsahu nespolehlive, takze se to u kazde veze
## jednou zkontroluje okem na kontaktnim listu a posun se preda sem.
##
## Jak posun poznat: najdi snimek, kde hlaven miri VODOROVNE DOPRAVA -- to je `east`,
## protoze tower.gd mapuje screen_aim 0 stupnu na "east". Kolik kroku je od nej doleva
## soubor, ktery se jmenuje east.png, tolik je posun.
def install_dirs(key, dry=False, rotate=0):
    src = os.path.join(SRC, "obj_" + key)
    missing = [d for d in DIRS if not os.path.isfile(os.path.join(src, d + ".png"))]
    if missing:
        raise SystemExit("chybi smery: %s -- neinstaluji nic (viz hlavicka)"
                         % ", ".join(missing))
    os.makedirs(KEEP, exist_ok=True)
    sizes, sums = set(), []
    if rotate:
        print("  posun jmen o %d kroku (%d stupnu)" % (rotate, rotate * 45))
    for i, d in enumerate(DIRS):
        name = DIRS[(i + rotate) % len(DIRS)]
        s_path = os.path.join(src, d + ".png")
        dst = os.path.join(DST, "head_%s_%s.png" % (key, name))
        keep = os.path.join(KEEP, "head_%s_%s.png" % (key, name))
        if os.path.isfile(dst) and not os.path.isfile(keep):
            shutil.copy2(dst, keep)
        im = Image.open(s_path).convert("RGBA")
        sizes.add(im.size)
        a = np.array(im)
        m = a[..., 3] > 8
        sums.append(float(a[..., :3][m].sum(1).mean()))
        print("  %-12s -> %-12s %s" % (d, name, im.size), end="")
        clean(s_path, dst, dry)
        print("  jas %3.0f" % sums[-1])
    if len(sizes) > 1:
        print("  POZOR: platna se lisi %s -- hra kotvi podle velikosti, hlava bude"
              " mezi smery poskakovat" % sorted(sizes))
    lo, hi = min(sums), max(sums)
    print("%s%d smeru pro %s; jas %.0f-%.0f (rozptyl %.0f)"
          % ("(nasucho) " if dry else "", len(DIRS), key, lo, hi, hi - lo))
    # Bible kap. 2c: telo veze ma sedet na 300, terasa ma 484. Nad ni vez splyne.
    if hi > 380:
        print("  POZOR: jas %.0f > 380 -- vez splyne s terasou (docs/art/iso_bible.md 2c)"
              % hi)


def main():
    dry = "--dry" in sys.argv
    if "--dirs" in sys.argv:
        rot = int(sys.argv[sys.argv.index("--rotate") + 1]) if "--rotate" in sys.argv else 0
        install_dirs(sys.argv[sys.argv.index("--dirs") + 1], dry, rot)
        return
    os.makedirs(KEEP, exist_ok=True)
    n = 0
    for d in sorted(os.listdir(SRC)):
        if not d.startswith("tower_"):
            continue
        src = os.path.join(SRC, d, "object.png")
        if not os.path.isfile(src):
            continue
        key = d[len("tower_"):]
        dst = os.path.join(DST, f"head_{key}.png")
        keep = os.path.join(KEEP, f"head_{key}.png")
        if os.path.isfile(dst) and not os.path.isfile(keep):
            shutil.copy2(dst, keep)          # zaloha jen kdyz jeste neni
        print(f"  {key}")
        clean(src, dst, dry)
        n += 1
    print(f"{'(nasucho) ' if dry else ''}nainstalovano {n} hlav; zaloha v "
          f"{os.path.relpath(KEEP, PROJ)}")


if __name__ == "__main__":
    main()
