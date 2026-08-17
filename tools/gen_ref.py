# Cilove rozliseni a referencni obrazek pro generator.
#
# Samostatny modul zamerne: gen.py resi model a gen_ui.py resi server, tohle je logika
# mezi nimi a nesmi zaviset ani na jednom (jinak vznikne kruhovy import a nedá se to
# otestovat bez sedmigigove roury v pameti).
#
# ROZLISENI
#
# Hra nema jednu velikost. Prisery jsou 32x32, boss 64x64, hlavy vezi 24, 32 i 40, dekorace
# a dlazdice 16x16 a nektere dlazdice dokonce 16x8. Generator proto musi umet obdelnik, ne
# jen ctverec — a k tomu spocitat, v jakem rozliseni se ma RENDEROVAT, coz je jina otazka
# nez jak velky ma byt vysledny sprite:
#
#   render 1024 -> sprite 32   znamena 32 px zdroje na jeden pixel spritu
#   render 512  -> sprite 32   znamena 16 px, mene detailu prezije zmenseni, ale je to 4x
#                              rychlejsi a lacinejsi na VRAM
#
# SDXL chce strany delitelne 64 a plochu kolem 1024x1024; jinde ztraci kompozici. Proto se
# pomer stran spritu prevede na nejblizsi takovy obdelnik, misto aby se renderoval ctverec
# a pak deformoval.
#
# REFERENCNI OBRAZEK
#
# Tri rezimy, protoze "podle tohohle" znamena pokazde neco jineho:
#
#   zaklad   Reference jde do img2img jako vychozi obraz. Drzi KOMPOZICI — novy sprite ma
#            tutez pozu a obrys, prompt mení detaily.
#   paleta   Z reference se vezme jen barevny svet a vysledek se na nej premapuje.
#            Kompozice je volna. Tohle je vynucovani stylove bible: nova prisera se
#            NARODI v tychz barvach jako junk-foodova rodina, misto aby se do nich
#            pak opravovala.
#   oboji    Zaklad i paleta.
#
# Reference se bere ze SOUBORU V PROJEKTU (assets/ nebo build/gen/) — v UI se vybira z
# artu, ktery uz je videt v sekci Hra. Cesty se overuji proti tem dvema korenum, aby
# nesla pres UI precist libovolny soubor na disku.
import os
import sys

import numpy as np
from PIL import Image

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from sprite_cleanup import build_palette, remap, to_oklab   # noqa: E402

# Odkud smi reference pochazet. Cokoli mimo tyhle koreny se odmitne.
REF_ROOTS = (os.path.join(PROJ, "assets"), os.path.join(PROJ, "build"))

# Velikosti, ktere v tehle hre doopravdy neco znamenaji. UI z toho dela nabidku, aby se
# nemuselo hadat — cislo mimo seznam jde porad zadat rucne.
TARGET_SIZES = [
    ("16x16", "dlaždice, dekorace"),
    ("16x8", "dlaždice cest"),
    ("24x24", "hlava věže"),
    ("32x32", "příšera, obránce"),
    ("40x40", "větší hlava věže"),
    ("64x64", "boss"),
]

REF_MODES = ("zaklad", "paleta", "oboji")

# SDXL ztraci kompozici, kdyz strana neni delitelna 64.
RENDER_STEP = 64
RENDER_MIN = 512
RENDER_MAX = 1536


def parse_size(spec, default=(32, 32)):
    """'32' -> (32,32);  '16x8' -> (16,8);  '' -> default. Vraci vzdy kladny par."""
    if spec is None:
        return default
    s = str(spec).strip().lower().replace("×", "x")
    if not s:
        return default
    try:
        if "x" in s:
            w, h = s.split("x", 1)
            w, h = int(w), int(h)
        else:
            w = h = int(s)
    except ValueError:
        raise ValueError(f"nesrozumitelné rozlišení: {spec!r} (čekám '32' nebo '16x8')")
    if w < 4 or h < 4 or w > 512 or h > 512:
        raise ValueError(f"rozlišení mimo rozsah 4–512: {w}×{h}")
    return w, h


def render_size(w, h, budget=1024):
    """Rozliseni renderu pro sprite w×h.

    Zachova pomer stran spritu, zaokrouhli strany na nasobky 64 a udrzi plochu kolem
    budget². Renderovat ctverec a pak ho zmackat na 16x8 by dlazdici svisle rozmazalo —
    kazdy zdrojovy pixel by pokryval dvakrat vic vysky nez sirky."""
    if w <= 0 or h <= 0:
        return budget, budget
    aspect = w / float(h)
    rh = (budget ** 2 / aspect) ** 0.5
    rw = rh * aspect

    def snap(v):
        v = int(round(v / RENDER_STEP)) * RENDER_STEP
        return max(RENDER_MIN, min(RENDER_MAX, v))

    return snap(rw), snap(rh)


def px_per_sprite_pixel(w, h, budget=1024):
    """Kolik zdrojovych pixelu pripadne na jeden pixel spritu. Pod ~8 zacina zmenseni
    hazet pryc detail rychleji, nez ho model stihne nakreslit."""
    rw, rh = render_size(w, h, budget)
    return min(rw / float(w), rh / float(h))


# ------------------------------------------------------------------ reference


def resolve_ref(spec):
    """Vstup z UI/CLI -> absolutni cesta, nebo vyjimka.

    Prijima cestu relativni k projektu i absolutni, ale vysledek MUSI lezet pod assets/
    nebo build/. Bez tehle kontroly by sel pres pole 'reference' v UI precist libovolny
    soubor na disku."""
    if not spec:
        raise ValueError("nezadaná reference")
    p = spec if os.path.isabs(spec) else os.path.join(PROJ, spec)
    p = os.path.realpath(p)
    if not any(p.startswith(os.path.realpath(r) + os.sep) for r in REF_ROOTS):
        raise ValueError("reference musí ležet v assets/ nebo build/")
    if not os.path.isfile(p):
        raise ValueError(f"reference neexistuje: {spec}")
    return p


def load_ref(spec):
    """-> RGBA numpy pole."""
    return np.array(Image.open(resolve_ref(spec)).convert("RGBA"))


def ref_palette(a, colors=16, weight_exp=0.5):
    """Barevny svet reference. Stejny vypocet, jakym sprite_cleanup dela paletu prisery,
    takze 'v paletě téhle příšery' znamena presne totez v obou nastrojich."""
    from collections import Counter
    m = a[..., 3] > 32
    if not m.any():
        raise ValueError("reference je celá průhledná")
    pool = Counter(map(tuple, a[..., :3][m]))
    return build_palette(pool, colors, weight_exp)


def apply_palette(a, pal):
    """Premapuje neprusvitne pixely na danou paletu (Oklab, bez ditheringu)."""
    m = a[..., 3] > 32
    if not m.any():
        return a
    rgb = remap(a[..., :3].astype(np.int64), m, pal, to_oklab(pal))
    return np.dstack([rgb.astype(np.uint8), a[..., 3]])


def ref_init(a, rw, rh, bg=(255, 0, 255)):
    """Reference -> PIL obraz rw×rh pro img2img.

    NEAREST a slozeni na plnou barvu pozadi. Nearest proto, aby model videl pixelovou
    strukturu; kdyby dostal vyhlazenou predlohu, vrati vyhlazenou kresbu. Pozadi plnou
    barvou proto, ze model je promptem ucen kreslit prave na ni — pruhlednost by
    do latentniho prostoru vnesla cernou plochu, kterou by zacal kreslit jako stin."""
    h, w = a.shape[:2]
    if w == 0 or h == 0:
        raise ValueError("prázdná reference")
    # Vepsat se zachovanim pomeru, zbytek doplnit pozadim — jinak by se ctvercova
    # prisera na obdelnikovem platne roztahla.
    scale = min(rw / float(w), rh / float(h))
    nw, nh = max(1, int(w * scale)), max(1, int(h * scale))
    im = Image.fromarray(a, "RGBA").resize((nw, nh), Image.NEAREST)
    canvas = Image.new("RGB", (rw, rh), bg)
    canvas.paste(im, ((rw - nw) // 2, (rh - nh) // 2), im)
    return canvas


def describe(spec, mode, colors=16):
    """Jednoradkovy popis pro log a pro UI, at je videt, co se z reference vzalo."""
    a = load_ref(spec)
    n = len({tuple(c) for c in a[..., :3][a[..., 3] > 32]})
    m = {"zaklad": "kompozice", "paleta": f"paleta ({colors} z {n} barev)",
         "oboji": f"kompozice + paleta ({colors} z {n} barev)"}.get(mode, mode)
    return f"{os.path.relpath(resolve_ref(spec), PROJ)} → {m}"
