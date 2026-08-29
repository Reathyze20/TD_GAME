# Postavi prvni iso level jako HADA (serpentine) a zapise ho do data/levels/level_iso_1.tres.
#
# PROC HAD A NE OKRUH
#
# Puvodni level 98 byl jeden velky obdelnikovy okruh: dlouhy, ale bez rozhodovani. Vez
# postavena kdekoli videla jeden usek cesty a hotovo. Had (tam - dolu - zpet - dolu)
# dava vezi postavene V ZUBU mezi dvema zatackami DVA useky naraz. To je ta volba, kvuli
# ktere se level hraje: siroky zaber za cenu horsi pozice, nebo naopak.
#
# PROC SE KRESLI V BLOCICH A NE V BUNKACH
#
# Stavebni misto vznikne jen tam, kde cell.x % 3 == 1 a cell.y % 3 == 1 A VSECH DEVET
# bunek kolem je vysoka zem (game.gd _build_field). Kreslit po bunkach znamena to pravidlo
# porusovat omylem; kreslit po blocich 3x3 znamena, ze jeden blok = jedno zarucene
# stavebni misto. Mrizka 24x24 dava presne 8x8 bloku.
#
#   python tools/build_level_first.py [--dry]
import os
import re
import sys

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEVEL = os.path.join(PROJ, "data", "levels", "level_iso_1.tres")
B = 3          # Data.BUILD_BLOCK
N = 8          # 24 / 3

# L = pruh (volna zem, horda ji preferuje)   H = vysoka zem (zed + stavebni misto)
# . = volna zem MIMO pruh (prujezdna za 4x cenu -- tudy vede budouci trod)
# @ = jadro
#
# Sachta ve sloupci 3 je zamerna: az se otevre trod, horda pujde rovnou dolu misto
# hadem. Veze u sachty (sloupce 2 a 4) si hodnotu nechaji, veze u vnejsich okraju ne --
# takze se level pta "stavis siroko, nebo blizko stredu?" a odpoved ma az ve vlne 4.
PLAN = [
    "LLLLLLLL",
    "HHH.HHHL",
    "LLLLLLLL",
    "LHH.HHHH",
    "LLLLLLLL",
    "HHH.HHHL",
    "LLLLLLLL",
    # Posledni rada NEMA sachtu: pod ni uz nic neni, takze by to byla slepa kapsa a
    # telegraf by sliboval cestu, ktera nikam nevede. Horda se ze sachty vzdy vynori
    # v rade 6 a odtud jde na zapad k jadru -- coz je tentyz zaverecny usek jako u hada,
    # a prave to drzi konvergencni pravidlo (scripts/resources/trod_data.gd).
    "@HHHHHHH",
]

# Vlevo NAHORE, ne vpravo: pri spawnu vpravo nahore vede prvni sestup hned dolu
# (radek 1 ma pruh prave ve sloupci 7) a cela horni rada hada se nepouzije.
SPAWN_BLOCK = (0, 0)
CORE_BLOCK = (0, 7)      # vlevo dole, na konci hada


def cells_of(bx, by):
    return [(bx * B + dx, by * B + dy) for dy in range(B) for dx in range(B)]


def build():
    high, lane, free = [], [], []
    for by, row in enumerate(PLAN):
        for bx, ch in enumerate(row):
            cs = cells_of(bx, by)
            if ch == "H":
                high += cs
            elif ch == "L":
                lane += cs
            elif ch == "@":
                # Jadro sedi v PRUHU, ne v masivu. game.gd vyjima z vysoke zeme jen
                # samotnou bunku jadra -- kdyz je cely blok zed, jsou vsichni ctyri
                # sousede jadra zed a level je zapecetěny (zmereno: trasa 0 bunek).
                lane += cs
            else:
                free += cs
    core = (CORE_BLOCK[0] * B + 1, CORE_BLOCK[1] * B + 1)
    trod = [c for by, row in enumerate(PLAN) for bx, ch in enumerate(row)
            if ch == "." for c in cells_of(bx, by)]
    sz = cells_of(*SPAWN_BLOCK)
    spawn = (sz[0][0], sz[0][1], B, B)
    return high, lane, free, core, trod, spawn


def vec(cs):
    return ", ".join(f"Vector2i({x}, {y})" for x, y in cs)


def main():
    high, lane, free, core, trod, spawn = build()
    src = open(LEVEL, encoding="utf-8").read()

    def put(key, val):
        """Prepise klic, nebo ho PRIDA, kdyz v .tres neni.

        Godot do .tres zapisuje jen to, co se lisi od vychozi hodnoty -- takze klic,
        ktery nikdo nemenil (path_off_lane_cost), tam proste chybi. Prvni verze na tom
        spadla s "klic v .tres neni", coz vypadalo jako rozbity soubor, a pritom to byl
        normalni stav."""
        nonlocal src
        pat = rf"^{key} = .*?$"
        if re.search(pat, src, re.M):
            src = re.sub(pat, f"{key} = {val}", src, count=1, flags=re.M)
            return
        nl = chr(10)
        anchor = nl + "[resource]" + nl
        i = src.index(anchor) + len(anchor)
        j = src.index(nl, i) + 1        # za prvni radek (script = ...)
        src = src[:j] + key + " = " + val + nl + src[j:]

    put("objective", f"Vector2i({core[0]}, {core[1]})")
    put("spawn_zones", f"Array[Rect2i]([Rect2i({spawn[0]}, {spawn[1]}, {spawn[2]}, {spawn[3]})])")
    put("high_ground", f"Array[Vector2i]([{vec(high)}])")
    put("path_cells", f"Array[Vector2i]([{vec(lane)}])")
    put("display_name", '"First Light"')
    # Had je dlouhy; sachta je kratka. Bez vyssi ceny mimo pruh by horda sla sachtou
    # rovnou od zacatku a trod by nemel co otevrit. Zmereno nize v testu.
    put("path_off_lane_cost", "8.0")
    src = re.sub(r"^cells = Array\[Vector2i\]\(\[.*?\]\)$",
                 f"cells = Array[Vector2i]([{vec(trod)}])", src, count=1, flags=re.M | re.S)

    print(f"bloky: {sum(r.count('H') for r in PLAN)} zdi, "
          f"{sum(r.count('L') for r in PLAN)} pruhu, {sum(r.count('.') for r in PLAN)} sachty")
    print(f"bunky: high {len(high)}, lane {len(lane)}, trod {len(trod)}")
    print(f"jadro {core}, spawn {spawn}")
    if "--dry" in sys.argv:
        print("(nasucho, nezapsano)")
        return
    open(LEVEL, "w", encoding="utf-8", newline="\n").write(src)
    print(f"zapsano -> {os.path.relpath(LEVEL, PROJ)}")


if __name__ == "__main__":
    main()
