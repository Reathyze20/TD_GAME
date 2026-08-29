# Nahled iso desky mimo Godot — slozi zem + pruh + terasu z build/iso_art/ podle
# SKUTECNYCH dat levelu.
#
# PROC TO NENI ROVNOU V GODOTU
#
# Protoze rozhodnuti, ktera se tady deli, jsou o tom, jestli art vubec sedi do rastru,
# a to se da zmerit driv, nez se cokoli nainstaluje do assets/. Instalace do assets/ je
# jednosmerka (import, .import soubory, .tres odkazy); tenhle skript necha spadnout
# spatnou davku o krok driv a zadarmo.
#
# Zrcadli PRESNE to, co dela Godot TileMapLayer:
#   TILE_SHAPE_ISOMETRIC + TILE_LAYOUT_DIAMOND_DOWN, tile_size (64,32)
#   stred bunky = ((x-y)*32, (x+y+1)*16)   <- tatáž rovnice jako Data.cell_center()
# Kresli se v poradi rostouciho x+y, coz je pro 2:1 projekci totez co y-sort.
#
#   python tools/iso_mock.py --out build/iso_art/_mock.png
import argparse
import os
import re
import sys

from PIL import Image

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(PROJ, "build", "iso_art")
TW, TH = 64, 32

# Zmereno na tile_0 stavebniho kitu: diamant podlahy lezi na x 19..82, y 41..73,
# tedy stred bunky je uvnitr platna 102x83 tady. Vsechny kusy kitu sdileji jedno
# platno i jednu kotvu, takze staci jedno cislo pro celou sadu.
KIT_ANCHOR = (50.5, 57.0)

# role -> index dlazdice, opsano z placement_rules odpovedi get_tiles_pro (terrace2).
KIT = {
    "floor": 0,
    "side": {"N": 1, "E": 2, "S": 3, "W": 4},
    "outer_corner": {"NE": 9, "SE": 10, "SW": 11, "NW": 12},
    "outer_multi": {"EW": 55, "NS": 54, "ESW": 52, "NES": 49, "NEW": 50, "NSW": 51, "NESW": 53},
    "pillar": 31,
    "stairs": 40,
}

# bit0=N bit1=E bit2=S bit3=W. Smery overeny na jednobitovych dlazdicich sady lane
# (build/iso_art/_lane_dirs.png): N mari vpravo-nahoru, E vpravo-dolu, S vlevo-dolu,
# W vlevo-nahoru -- coz presne odpovida sousedum nize v nasi mrizce.
NEIGH = {"N": (0, -1), "E": (1, 0), "S": (0, 1), "W": (-1, 0)}
BIT = {"N": 1, "E": 2, "S": 4, "W": 8}

# mask -> index dlazdice, opsano z placement_rules sady lane.
LANE_BY_MASK = {0: [0, 1], 1: [2], 2: [3], 4: [4], 8: [5], 10: [6], 5: [7], 6: [8],
                12: [9], 3: [10], 9: [11], 14: [12], 13: [13], 11: [14], 15: [15, 16]}


def load(d, i):
    return Image.open(os.path.join(ART, d, f"tile_{i}.png")).convert("RGBA")


def parse_cells(tres, key):
    """Vytahne Array[Vector2i] z .tres. Cte se skutecny soubor, ne rucne psany seznam."""
    m = re.search(rf"^{key} = Array\[Vector2i\]\(\[(.*?)\]\)", tres, re.M | re.S)
    if not m:
        return set()
    return {(int(a), int(b)) for a, b in re.findall(r"Vector2i\((-?\d+),\s*(-?\d+)\)", m.group(1))}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--level", default="data/levels/level_iso.tres")
    ap.add_argument("--out", default="build/iso_art/_mock.png")
    ap.add_argument("--ground", default="tissue2")
    ap.add_argument("--scale", type=int, default=1)
    a = ap.parse_args()

    tres = open(os.path.join(PROJ, a.level), encoding="utf-8").read()
    high = parse_cells(tres, "high_ground")
    path = parse_cells(tres, "path_cells")
    mo = re.search(r"^objective = Vector2i\((-?\d+),\s*(-?\d+)\)", tres, re.M)
    objective = (int(mo.group(1)), int(mo.group(2))) if mo else None
    solid = {c for c in high if c != objective}
    cols = max(c[0] for c in high | path) + 2
    rows = max(c[1] for c in high | path) + 2
    print(f"level: {cols}x{rows} bunek, high_ground {len(high)}, path {len(path)}")

    ground = [load(a.ground, i) for i in range(16)]
    lane = {m: [load("lane", i) for i in idx] for m, idx in LANE_BY_MASK.items()}
    lane_fill = load("lane", 17)   # plna deska, stamp-only kus sady
    kit = {}
    for i in set([KIT["floor"], KIT["pillar"], KIT["stairs"]]
                 + list(KIT["side"].values()) + list(KIT["outer_corner"].values())
                 + list(KIT["outer_multi"].values())):
        kit[i] = load("terrace2", i)

    W = (cols + rows) * TW // 2 + TW
    H = (cols + rows) * TH // 2 + TH + 96
    ox, oy = rows * TW // 2, 80
    img = Image.new("RGBA", (W, H), (8, 10, 18, 255))

    def center(x, y):
        return ox + (x - y) * (TW // 2), oy + (x + y + 1) * (TH // 2)

    def blit(im, cx, cy, anchor=None):
        if anchor is None:                      # dlazdice 64x64 s obsahem na (0,16)
            img.alpha_composite(im, (int(cx - TW // 2), int(cy - TH // 2 - 16)))
        else:
            img.alpha_composite(im, (int(cx - anchor[0]), int(cy - anchor[1])))

    # --- vrstva zeme: nejdriv tkan a pruh, cele pole, zezadu dopredu
    for s in range(cols + rows):
        for x in range(cols):
            y = s - x
            if not (0 <= y < rows):
                continue
            cx, cy = center(x, y)
            if (x, y) in path:
                mask = sum(b for d, b in BIT.items()
                           if (x + NEIGH[d][0], y + NEIGH[d][1]) in path)
                # Pruh je siroky 3 bunky, takze vnitrni bunky maji masku 15 -- a dlazdice
                # pro masku 15 je KRIZOVATKA s odrezanymi rohy, ne vypln. Vydlazdena
                # vedle sebe delala v pruhu diry. Bunka, ktere je pruh i po uhloprickach,
                # proto bere plnou desku (tile_17), ne krizovatku.
                if mask == 15 and all((x + dx, y + dy) in path
                                      for dx in (-1, 1) for dy in (-1, 1)):
                    blit(lane_fill, cx, cy)
                else:
                    pool = lane.get(mask) or lane[0]
                    blit(pool[(x * 7 + y * 13) % len(pool)], cx, cy)
            else:
                blit(ground[(x * 3 + y * 5) % len(ground)], cx, cy)

    # --- terasa: jeden HRANOL na kazdou solid bunku, zezadu dopredu.
    #
    # Kit je delany na MISTNOSTI (zdi stoupaji z podlahy), ne na vyvysenou zem, takze
    # jeho "outer" kusy vybirane podle odkrytych stran delaly z terasy vanu. Tohle je
    # jednodussi a spravnejsi: tile_53 je hotovy hranol (vyvyseny vrch + boky), a
    # protoze se kresli zezadu dopredu, VNITRNI steny prekryje soused, ktery stoji
    # pred nimi. Viditelne tak zustanou jen boky na skutecnem okraji masivu -- bez
    # jedineho testu na sousedy.
    block = kit[53]
    for s_ in range(cols + rows):
        for x in range(cols):
            y = s_ - x
            if not (0 <= y < rows) or (x, y) not in solid:
                continue
            cx, cy = center(x, y)
            blit(block, cx, cy, KIT_ANCHOR)

    if a.scale > 1:
        img = img.resize((img.width * a.scale, img.height * a.scale), Image.NEAREST)
    out = os.path.join(PROJ, a.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out)
    print(f"{a.out}  {img.width}x{img.height}")


if __name__ == "__main__":
    main()
