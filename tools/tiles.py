# Tilesety: z Aseprite do hry a zpatky.
#
#   python tools/tiles.py instaluj tileset.png          # teren (zdi + podlaha)
#   python tools/tiles.py instaluj cesty.png --cesty    # dlazdice cest
#   python tools/tiles.py uprav                         # atlas ze hry -> sesit pro Aseprite
#   python tools/tiles.py zpet                          # upraveny sesit -> zpatky do hry
#   python tools/tiles.py nahled                        # vykresli zkusebni mapu ke kontrole
#
# JEDNO CISLO SI PAMATUJ: 16.
# Herni bunka je 16 px obrazovky a 16 px artu, cili meritko x1 -- jeden pixel artu je
# jeden pixel obrazovky. PixelLab tilesety v 16 UMI, takze se nic nedotahuje rucne;
# staci "tile size = 16" a export "Tileset 15".
#
# HISTORIE, at se to nezkousi potreti: 16 px artu na x3 (bunka 48) -> "24 na x2"
# (18. 8. 2026 zmereno, ze to nikdy neplatilo, atlas zustal 16) -> 16 px artu na x1
# (bunka 16, mrizka 120x57). Deska na obrazovce je porad 1920x912 a rozhrani se nehnulo;
# zmenila se jen jemnost rastru.
#
# POZOR, ATLAS SE UKLADA V PIXELECH OBRAZOVKY, NE ARTU.
# 4 dlazdice na sirku krat CELL, cili 192 px pri bunce 48. Neni to totez jako sprity,
# ktere lezi v pixelech artu a engine je zvetsuje sam. Kdo bude atlas hromadne
# preskalovavat s ostatnim artem, prepocita ho spatne -- prave na tomhle se pri
# prechodu na 64px rastr rozsypal teren a vypadalo to jako chyba enginu.
#
# V PixelLabu tedy: tile size = 32 a dotahni na 24, nebo kresli rovnou. Pri exportu
# vyber layout "Tileset 15".
# "Tileset 15" je proste mrizka 4x4 s maskami 0..15 za sebou - presne to, co hra chce,
# jen v jinem poradi bitu. Prevod resi tenhle skript, ty se o nej nemusis starat.
import os
import shutil
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ATLAS = os.path.join(PROJ, "assets", "terrain", "high_ground_atlas.png")
BG = os.path.join(PROJ, "assets", "background.png")
PATH_DIR = os.path.join(PROJ, "assets", "terrain", "path")
EDIT = os.path.join(PROJ, "assets", "src", "pixel", "atlas_edit.png")
PREVIEW = os.path.join(PROJ, "assets", "src", "pixel", "_kontrola_mapy.png")

# Rastr se CTE ze scripts/data.gd, neopisuje se. Presne tady se to uz jednou rozeslo:
# data.gd se 17. 8. 2026 presunulo na 24 px artu, tenhle soubor to mel prepsane taky,
# ale ATLAS NA DISKU zustal 16px -- takze cislo v kodu a obrazek v assets/ tvrdily
# kazdy neco jineho a teren cely mesic bezel na jinem meritku nez sprity.
import game_raster                                             # noqa: E402

CELL = game_raster.TILE       # herni bunka v pixelech obrazovky (Data.GRID.tile)
ART = game_raster.ART_PX      # v cem se kresli (Data.TERRAIN_ART_PX)
ZOOM = game_raster.SCALE      # CELL / ART, cele cislo


# Nase maska: bit 1 = SZ bunka je zed, 2 = SV, 4 = JZ, 8 = JV. Atlas je mrizka 4x4,
# dlazdice pro masku m lezi na x = m%4, y = m/4.
#
# --------------------------------------------------- cteni rozlozeni z obrazku
#
# PixelLab exportuje ve trech rozlozenich ("Tileset 15", "Tileset Wang", "Tileset 3x3")
# a kazde ma jine poradi dlazdic. Drzet si na to tabulky znamena, ze staci jedna zmena
# v rozsireni a je to rozbite - a hlavne to nefunguje pro rucne nakresleny list.
#
# Proto se poradi necte z tabulky, ale z obrazku: u kazde dlazdice se ohledaji ctyri rohy
# a z nich se spocita, ktera maska to je. Funguje to na jakekoliv rozlozeni vcetne toho,
# ktere si nakreslis sam.
VELIKOSTI = (16, 24, 32, 48, 64)


def _velikost_dlazdice(img: Image.Image) -> int:
    for t in sorted(VELIKOSTI, reverse=True):
        if img.width % t == 0 and img.height % t == 0:
            if (img.width // t) * (img.height // t) >= 16:
                return t
    raise SystemExit(
        "Nepoznavam mrizku v obrazku %dx%d.\n"
        "Cekam list ctvercovych dlazdic o strane 16, 24, 32, 48 nebo 64 px,\n"
        "dohromady aspon 16 kusu." % (img.width, img.height))


def _jas(pixely) -> float:
    hodnoty = sorted(0.299 * r + 0.587 * g + 0.114 * b for r, g, b, a in pixely if a > 8)
    if not hodnoty:
        return 0.0
    return hodnoty[len(hodnoty) // 2]      # median snese cerny obrys po okrajich


def _rohy(tile: Image.Image) -> list:
    """Median jasu ve ctyrech rozich, v poradi SZ, SV, JZ, JV."""
    t = tile.width
    k = max(2, t // 3)
    px = tile.load()
    out = []
    for ox, oy in ((0, 0), (t - k, 0), (0, t - k), (t - k, t - k)):
        out.append(_jas([px[ox + x, oy + y] for y in range(k) for x in range(k)]))
    return out


def _rozdel_na_masky(img: Image.Image, t: int, zed_je_tmava: bool) -> tuple:
    """Vrati (dlazdice podle nasi masky, pouzity prah) nebo skonci s chybou.

    Prah se nehada, ale hleda: projede se cely rozsah jasu a vezme se ten, pri kterem
    vyjde vsech sestnact masek. To je samo o sobe silna kontrola - kdyby cetl rohy spatne,
    nektera kombinace by chybela nebo se objevila dvakrat.

    Proc nestaci rozdelit jas v polovine: sten ma u spodni hrany svislou stenu, ktera
    precniva pres sousedni dlazdici. Ta stena je namalovana TAM, KDE JE PODLAHA, takze
    se musi pocitat jako podlaha - jenze jasem lezi mezi obema materialy. Prah proto
    konci blizko tmave strany.
    """
    cols, rows = img.width // t, img.height // t

    # Prazdna policka se musi vyhodit driv, nez se cokoliv pocita. List z Aseprite
    # (File -> Export Sprite Sheet) je mivá po okrajich a pruhledny roh by se pri cteni
    # jasu tvaril jako uplna tma, tedy jako zed - a do sady by se dostala dira.
    def obsazene(c, r):
        px = _tile(img, t, c, r).load()
        pruhledne = sum(1 for y in range(t) for x in range(t) if px[x, y][3] <= 8)
        return pruhledne <= t * t * 0.25

    policka = [(c, r) for r in range(rows) for c in range(cols) if obsazene(c, r)]
    if len(policka) < 16:
        raise SystemExit(
            "Na listu je jen %d neprazdnych dlazdic, potrebuju aspon 16." % len(policka))
    rohy = {p: _rohy(_tile(img, t, p[0], p[1])) for p in policka}

    vsechny = sorted(v for ctverice in rohy.values() for v in ctverice)
    if not vsechny or vsechny[-1] - vsechny[0] < 30:
        raise SystemExit(
            "Oba tereny maji skoro stejny jas (rozsah %.0f..%.0f).\n"
            "Popis je tak, aby se lisily i svetlosti - pridej do jednoho 'dark'\n"
            "a do druheho 'pale' nebo 'clearly lighter than the floor'."
            % (vsechny[0] if vsechny else 0, vsechny[-1] if vsechny else 0))

    # Kazda maska si nese SEZNAM policek: prvni je zakladni dlazdice, dalsi jsou
    # alternativni varianty tehoz napojeni. Hra je umi - atlas se sklada do vrstev
    # (4x4 blok na variantu) a kazda bunka si losuje. Zahazovat je byla skoda:
    # rucne kresleny list jich mel 42 a 26 se ztratilo.
    def zkus(prah):
        nalezene = {}
        for p in policka:
            maska = 0
            for bit, hodnota in zip((1, 2, 4, 8), rohy[p]):
                if (hodnota < prah) == zed_je_tmava:
                    maska |= bit
            nalezene.setdefault(maska, []).append(p)
        return nalezene

    sedici = []
    for prah in range(int(vsechny[0]) + 1, int(vsechny[-1]) + 1):
        nalezene = zkus(prah)
        if len(nalezene) == 16:
            sedici.append((prah, nalezene))

    if not sedici:
        nejlepsi = max((len(zkus(p)) for p in range(int(vsechny[0]) + 1, int(vsechny[-1]) + 1)),
                       default=0)
        raise SystemExit(
            "Nedokazu z listu precist vsech 16 kombinaci rohu - nejlip vyslo %d.\n"
            "Nejcastejsi priciny:\n"
            "  - neni to napojovaci sada (zkontroluj, ze jsi exportoval tileset)\n"
            "  - tereny se prilis podobaji jasem (rozsah %.0f..%.0f)\n"
            "  - zed je svetlejsi nez podlaha -> pridej prepinac --svetla-zed"
            % (nejlepsi, vsechny[0], vsechny[-1]))

    # Ze vsech prahu, ktere projdou, se bere prostredni - nejdal od obou hranic,
    # kde uz by se cteni zacalo lamat.
    prah, nalezene = sedici[len(sedici) // 2]
    return nalezene, prah


def _grid_size(img: Image.Image, cols: int, rows: int) -> int:
    # Plátno, na kterém PixelLab generuje, je 8x8 dlaždic poskládaných do souvislé mapy -
    # ne mřížka jednotlivých kusů. Uložit ho rovnou přes File -> Save As je nejsnazší omyl,
    # jaký tu jde udělat, a bez téhle hlášky by z toho vyšel nesmysl.
    # Poznají se podle velikosti dlaždice: export 4x4 s dlaždicí, která dělí 48, je platný
    # (64x64 = 16px). Když 4x4 nevychází, ale 8x8 dá 16/32/64, je to plátno.
    ctverec = img.width == img.height
    export_sedi = ctverec and img.width % cols == 0 and CELL % max(1, img.width // cols) == 0
    if not export_sedi and ctverec and img.width % 8 == 0 and (img.width // 8) in (16, 32, 64):
        raise SystemExit(
            "Tohle vypada na generovaci platno (8x8 dlazdic po %d px), ne na hotovy tileset.\n"
            "Je to mapa poskladana tak, aby na sebe kousky navazovaly - proto to vypada\n"
            "jako souvisly tvar a ne jako mrizka.\n"
            "\n"
            "V Aseprite: Edit -> PixelLab -> Open plugin -> Create tileset (pro),\n"
            "a v tom dialogu je tlacitko 'Export as tileset'.\n"
            "Target Layout nastav na 'Tileset 15' a uloz jako PNG (bude %dx%d)."
            % (img.width // 8, img.width // 2, img.width // 2))
    if img.width % cols or img.height % rows or img.width != img.height:
        raise SystemExit(
            "Obrazek %dx%d nejde rozdelit na mrizku %dx%d.\n"
            "Cekam export 'Tileset 15' - ctverec, strana = 4x velikost dlazdice\n"
            "(pri dlazdici 16 px tedy 64x64).\n"
            "\n"
            "Nejcastejsi pricina: Wall style = Hill nebo Cliff. Ty maji hloubku pres 0.4,\n"
            "takze PixelLab vyrobi platno dvojnasobne vysky a export nesedi.\n"
            "Prepni Wall style na Ledge (nebo Flat) a vygeneruj znovu."
            % (img.width, img.height, cols, rows))
    t = img.width // cols
    if img.height // rows != t:
        raise SystemExit("Dlazdice nejsou ctvercove (%dx%d)." % (t, img.height // rows))
    return t


def _tile(img: Image.Image, t: int, col: int, row: int) -> Image.Image:
    return img.crop((col * t, row * t, col * t + t, row * t + t))


def _edge_extend(tile: Image.Image) -> Image.Image:
    """Prekryje krajni radku/sloupec sousedni.

    Kazda dlazdice od generatoru si nese vlastni tmavy obrys. Kdyz se poskladaji
    vedle sebe, ty obrysy vytvori viditelnou mrizku pres celou mapu. Tohle ji smaze.
    """
    px = tile.load()
    w, h = tile.size
    for x in range(w):
        px[x, 0] = px[x, 1]
        px[x, h - 1] = px[x, h - 2]
    for y in range(h):
        px[0, y] = px[1, y]
        px[w - 1, y] = px[w - 2, y]
    return tile


# ------------------------------------------------------------------ instaluj
def instaluj(src_path: str, jako_cesty: bool = False, zed_je_tmava: bool = True) -> None:
    if not os.path.exists(src_path):
        raise SystemExit("Soubor neexistuje: %s" % src_path)
    src = Image.open(src_path).convert("RGBA")

    if jako_cesty:
        _instaluj_cesty(src)
        return

    t = _velikost_dlazdice(src)
    if CELL % t:
        raise SystemExit(
            "Dlazdice ma %d px a to nedeli 48 beze zbytku.\n"
            "V PixelLabu prepni tile size na 16." % t)
    zoom = CELL // t

    nalezene, prah = _rozdel_na_masky(src, t, zed_je_tmava)

    # Vrstvy variant: blok 4x4 na kazdou. Maska s mene variantami opakuje svou prvni,
    # takze kazda vrstva je kompletni a hra muze losovat naslepo.
    varianty = max(len(nalezene[m]) for m in range(16))
    atlas = Image.new("RGBA", (CELL * 4, CELL * 4 * varianty), (0, 0, 0, 0))
    podlaha = None
    for v in range(varianty):
        for m in range(16):
            sez = nalezene[m]
            col, row = sez[v % len(sez)]
            big = _edge_extend(_tile(src, t, col, row).copy()) \
                .resize((t * zoom, t * zoom), Image.NEAREST)
            atlas.paste(big, ((m % 4) * CELL, (v * 4 + m // 4) * CELL))
            if v == 0 and m == 0:
                podlaha = big
    _zaloha()
    atlas.save(ATLAS)
    _zapis_pozadi(podlaha)
    navic = sum(len(nalezene[m]) for m in range(16)) - 16
    print("-> %s" % ATLAS)
    print("   dlazdice %dpx, zvetseno x%d, %d dlazdic na listu"
          % (t, zoom, len(sum(nalezene.values(), []))))
    print("   variant na masku: max %d (alternativnich dlazdic navic: %d)"
          % (varianty, navic))
    print("   za zed povazuji %s material (prah jasu %.0f)"
          % ("tmavsi" if zed_je_tmava else "svetlejsi", prah))
    print("   kdyby to bylo naopak, pridej prepinac --svetla-zed")
    nahled()
    _hotovo()


def _instaluj_cesty(src: Image.Image) -> None:
    """Cesty NEJSOU napojovaci sada.

    Hra si z nich pro kazdou bunku vylosuje jednu nahodne (`rng.randi() % variants`),
    takze kazda dlazdice musi davat smysl sama o sobe a navazovat na kteroukoliv jinou.
    Staci ctyri, sestnact je uz luxus. Bere se poradi ve kterem jsou, zadne prehazovani.
    """
    w, h = src.size
    if w == h:
        t, cols, rows = w // 4, 4, 4         # mrizka 4x4
    elif w % h == 0:
        t, cols, rows = h, w // h, 1          # vodorovny pruh
    else:
        raise SystemExit(
            "Cekam bud ctverec (mrizka 4x4) nebo vodorovny pruh ctvercovych dlazdic.\n"
            "Dostal jsem %dx%d." % (w, h))

    os.makedirs(PATH_DIR, exist_ok=True)
    for stary in os.listdir(PATH_DIR):
        if stary.startswith("path_") and stary.endswith(".png"):
            os.remove(os.path.join(PATH_DIR, stary))

    n = 0
    for row in range(rows):
        for col in range(cols):
            piece = _edge_extend(_tile(src, t, col, row).copy())
            piece.save(os.path.join(PATH_DIR, "path_%02d.png" % n))
            n += 1
    print("-> %d dlazdic cest do %s (po %dpx, hra si je zvetsi na %d)"
          % (n, PATH_DIR, t, CELL))
    _hotovo()


def _zaloha() -> None:
    """Dve generace zaloh atlasu.

    Prepis atlasu je nevratny a jedna zaloha nestaci - druhy beh by ji prepsal uz
    tou rozbitou verzi. Presne tak se v tomhle projektu jednou prislo o mapu.
    """
    if not os.path.exists(ATLAS):
        return
    bak, bak2 = ATLAS + ".bak", ATLAS + ".bak2"
    if os.path.exists(bak):
        if os.path.exists(bak2):
            os.remove(bak2)
        os.rename(bak, bak2)
    shutil.copy2(ATLAS, bak)


def _zapis_pozadi(floor_tile: Image.Image) -> None:
    """Maska 0 je cista podlaha, takze slouzi zaroven jako pozadi hraciho pole."""
    bg = Image.new("RGBA", (1920, 1080), (0, 0, 0, 255))
    for j in range(1080 // CELL + 1):
        for i in range(1920 // CELL + 1):
            bg.alpha_composite(floor_tile, (i * CELL, j * CELL))
    bg.convert("RGB").save(BG)


# --------------------------------------------------------------- uprav / zpet
def uprav() -> None:
    a = Image.open(ATLAS).convert("RGBA")
    step = a.width // 4
    varianty = max(1, a.height // (step * 4))
    out = Image.new("RGBA", (ART * 4, ART * 4 * varianty), (0, 0, 0, 0))
    for v in range(varianty):
        for mask in range(16):
            piece = _tile(a, step, mask % 4, v * 4 + mask // 4)
            out.paste(piece.resize((ART, ART), Image.NEAREST),
                      ((mask % 4) * ART, (v * 4 + mask // 4) * ART))
    os.makedirs(os.path.dirname(EDIT), exist_ok=True)
    out.save(EDIT)
    print("-> %s  (%dx%d, dlazdice %dpx, %d vrstev variant)"
          % (EDIT, out.width, out.height, ART, varianty))
    print("   Otevri v Aseprite. NEMEN velikost platna.")
    print("   Kazdy blok 4x4 je jedna vrstva variant; vlevo nahore v bloku je podlaha,")
    print("   vpravo dole cela zed.")


def zpet() -> None:
    if not os.path.exists(EDIT):
        raise SystemExit("Chybi %s - nejdriv spust: uprav" % EDIT)
    src = Image.open(EDIT).convert("RGBA")
    t = src.width // 4
    if src.width != t * 4 or src.height % (t * 4) != 0:
        raise SystemExit(
            "Cekam sirku 4 dlazdice a vysku v nasobcich 4 (vrstvy variant),\n"
            "dostal %dx%d - nemen velikost platna." % (src.width, src.height))
    if CELL % t:
        raise SystemExit("Dlazdice ma %d px a to nedeli 48 beze zbytku." % t)
    zoom = CELL // t
    varianty = src.height // (t * 4)
    atlas = Image.new("RGBA", (CELL * 4, CELL * 4 * varianty), (0, 0, 0, 0))
    for v in range(varianty):
        for mask in range(16):
            big = _tile(src, t, mask % 4, v * 4 + mask // 4) \
                .resize((t * zoom, t * zoom), Image.NEAREST)
            atlas.paste(big, ((mask % 4) * CELL, (v * 4 + mask // 4) * CELL))
    _zaloha()
    atlas.save(ATLAS)
    _zapis_pozadi(_tile(src, t, 0, 0).resize((t * zoom, t * zoom), Image.NEAREST))
    print("-> %s zapsan zpatky (%d vrstev variant)." % (ATLAS, varianty))
    nahled()
    _hotovo()


# ------------------------------------------------------------------- kontrola
# Zkusebni mapa: mistnost, chodba, ostrustek a diagonala. Pokud sedi prevod masek,
# zdi na sebe navazuji. Pokud ne, uvidis rozsypany caj a nemusis nic spoustet.
TESTMAPA = [
    "................",
    ".####......##...",
    ".#..#....####...",
    ".#..#....##.....",
    ".####...........",
    "........####....",
    "..#####....#....",
    "......#....#....",
    "......######....",
    "................",
    "...##...........",
    "....##..#####...",
    ".....##.....#...",
    "........#####...",
    "................",
]


def nahled() -> None:
    import random
    atlas = Image.open(ATLAS).convert("RGBA")
    step = atlas.width // 4
    varianty = max(1, atlas.height // (step * 4))
    rows, cols = len(TESTMAPA), len(TESTMAPA[0])
    rng = random.Random(42)      # pevny seed: dve kontroly po sobe vypadaji stejne

    def zed(r, c):
        if r < 0 or c < 0 or r >= rows or c >= cols:
            return False
        return TESTMAPA[r][c] == "#"

    out = Image.new("RGBA", (cols * CELL, rows * CELL), (0, 0, 0, 255))
    floor = _tile(atlas, step, 0, 0)
    for r in range(rows):
        for c in range(cols):
            out.alpha_composite(floor, (c * CELL, r * CELL))
    # Teren sedi na rozich bunek, ne na bunkach - proto o pul bunky vlevo nahoru
    # a o jeden vrchol navic v obou smerech. Varianty se losuji jako ve hre, aby
    # kontrolni mapa ukazala i alternativni dlazdice.
    for i in range(rows + 1):
        for j in range(cols + 1):
            mask = ((1 if zed(i - 1, j - 1) else 0)
                    | (2 if zed(i - 1, j) else 0)
                    | (4 if zed(i, j - 1) else 0)
                    | (8 if zed(i, j) else 0))
            if mask == 0:
                continue
            v = rng.randrange(varianty)
            piece = _tile(atlas, step, mask % 4, v * 4 + mask // 4)
            out.alpha_composite(piece, (j * CELL - CELL // 2, i * CELL - CELL // 2))
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    out.convert("RGB").save(PREVIEW)
    print("-> kontrolni mapa: %s (%d vrstev variant)" % (PREVIEW, varianty))


def _hotovo() -> None:
    print("")
    print("Jeste v Godotu: Project -> Reload Current Project (nebo --import),")
    print("aby si vsiml zmenenych PNG.")


VERBS = {"instaluj", "uprav", "zpet", "nahled"}

if __name__ == "__main__":
    args = sys.argv[1:]
    cmd = args[0] if args else ""
    if cmd not in VERBS:
        raise SystemExit(
            "Pouziti:\n"
            "  tiles.py instaluj <soubor.png>           teren z PixelLabu (kterykoliv layout)\n"
            "  tiles.py instaluj <...> --svetla-zed     kdyz je zed svetlejsi nez podlaha\n"
            "  tiles.py instaluj <soubor.png> --cesty   dlazdice cest\n"
            "  tiles.py uprav                           atlas ze hry -> sesit pro Aseprite\n"
            "  tiles.py zpet                            upraveny sesit -> zpatky do hry\n"
            "  tiles.py nahled                          jen prekreslit kontrolni mapu")
    if cmd == "instaluj":
        prepinace = ("--cesty", "--svetla-zed")
        rest = [a for a in args[1:] if a not in prepinace]
        if not rest:
            raise SystemExit("Chybi cesta k PNG.")
        instaluj(rest[0], jako_cesty="--cesty" in args,
                 zed_je_tmava="--svetla-zed" not in args)
    elif cmd == "uprav":
        uprav()
    elif cmd == "zpet":
        zpet()
    else:
        nahled()
