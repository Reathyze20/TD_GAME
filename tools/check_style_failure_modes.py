"""Overi tri automatizovatelne failure-mode testy smeru A (STYLE_BIBLE.md SS12d) na
skutecnych PNG souborech.

    python tools/check_style_failure_modes.py          # gatuje jen gen:direction_a
    python tools/check_style_failure_modes.py --all     # gatuje i cely legacy rejstrik

PROC TO EXISTUJE

Smer A (2.9.2026) rozdeluje habity a distrakce na dva kategoricky odlisne jazyky --
habity geometrie, distrakce beztvare organicke jevy (STYLE_BIBLE.md SS0, SS12). Tri z
sesti navrzenych testu jdou zmerit na souboru misto na dojmu ze screenshotu: silueta
(kompaktnost alfa masky), stylova soudrznost ("pet stylu" -- pocet unikatnich barev) a
citelnost v horde (kolik jednotek z dopocitaneho N pri cilove hustote 0.30 zustane
vlastni komponentou, viz SS12g).
Zbyle tri (squint test, fog test, drift napric smery animace) jsou soud o dojmu z
obrazovky a zustavaji na uzivateli -- viz SS12d, "Tri testy z researche se
zautomatizovat nedaji".

Prahy se CTOU z STYLE_BIBLE.md (blok <!-- gen:failure_modes -->), nikdy se sem
neopisuji jako cislo -- stejna stavba jako tools/check_terrain_contrast.py vuci SS4.
Kdyby se prah v bibli zmenil, tenhle skript ho zmeri znovu, ne poprve.

GATOVANI -- KTERE SOUBORY SE POCITAJI DO EXIT KODU

STYLE_BIBLE.md's <!-- gen:direction_a --> (SS12e) je jediny seznam souboru, ktere tenhle
skript smi nechat spadnout na exit kod. Dneska je ta tabulka PRAZDNA -- zadny master
smeru A jeste neexistuje (SS12f ceka na schvaleni uzivatelem) -- takze vychozi beh gatuje
NULA souboru a rika to nahlas (aby se prazdna brana nedala splest se splnenou).

Cely dnesni rejstrik (kazda habit hlava v assets/towers/head_*.png, kazdy distraction
snimek v assets/distractions/*_frame_1.png) vznikl PRED smerem A a zmereny testem by
neprosel -- to neni bug testu, to je presne ta vada, kvuli ktere se smer meni (SS12d to
uz zmerilo: dnesni habity 1.08-2.50, distrakce 1.24-3.64, rozsahy se prekryvaji). Gatovat
ho by nechalo verify.sh cervene od tohohle commitu az do konce faze 1 a prestalo by
hlidat cokoli jineho -- stejna uvaha jako KNOWN_BROKEN_TESTS ve verify.sh a allowlist v
docs/art/ART_DEBT.md. Rejstrik se proto MERI a TISKNE, oznaceny LEGACY, ale do exit kodu
nepocita. --all prepne LEGACY soubory do gatovaneho rezimu (diagnosticky pohled na to,
co by realny rejstrik dnes udelal branam), ale tenhle rezim NENI to, co spousti
verify.sh.

METODA

1. Silueta: alfa maska = alpha >= 128; kompaktnost = obvod^2 / (4*pi*plocha), kde
   obvodovy pixel je nepruhledny pixel se >=1 ctyrsousedem, ktery je pruhledny nebo mimo
   platno. Kruh ~ 1.0, roztrepeny tvar roste.
2. Stylova soudrznost ("pet stylu"): pocet unikatnich RGB trojic mezi nepruhlednymi
   pixely.
3. Horda: N kopii distraction spritu v herni velikosti (Data.pixel_scale() je dnes 1.0,
   viz STYLE_BIBLE.md SS5 -- soubor na disku uz JE herni velikost) rozmistenych FIXNIM
   seedem na plose 480x270. **N NENI pevnych 200** (SS12g, doplneno po prvni verzi
   tohohle skriptu): pole 480x270 = 129 600 px je pro dnesni sprity (660-1540 px
   nepruhledne plochy) pri N=200 PRESYCENE -- i dokonaly kruh vyjde 0.000 a brana
   nerozlisuje nic. N se proto DOPOCITAVA z cilove hustoty (`gen:failure_modes`, radek
   "horda, hustota" -- cislo samo se sem NEOPISUJE, cte se odtud za behu, viz
   compute_n()): `N = clamp(round(hustota * 129600 / unit_opaque_area), 8, 200)`,
   stejne N pro sprite i pro kontrolni disk (viz nize), aby zustal pomer
   jablka-jablkum. Meri se podil jednotek, ktere v alfa kompozitu preziji jako VLASTNI
   4-souvisla komponenta (plocha 0.5x-2.0x plochy jedne jednotky), deleno N -- a totez
   cislo pro kontrolni plny kotouc STEJNE plochy na STEJNYCH pozicich (stejny seed,
   stejny bounding box -> totozne souradnice, stejne N). Nez se pomeru veri, prochazi
   `control_share` branou "horda, platnost kontroly" (>= 0.50): kdyz neuspeje ani
   idealni kruh, pole je presycene a vysledek se hlasi jako **INCONCLUSIVE** -- nikdy
   jako pass, a u gatovaneho (direction_a) souboru se INCONCLUSIVE pocita jako FAIL,
   aby se presycene pole nikdy nedalo splest se splnenou branou. Jen kdyz je kontrola
   platna, pocita se pomer sprite/kontrola >= 0.70 ("horda, citelnost"). Druha, na
   hustote nezavisla cast hordy je kontrast: |prumer souctu RGB nepruhlednych pixelu
   spritu - soucet RGB GROUND| >= 60 -- GROUND se cte z tools/flat_terrain.py, ne
   kopiruje sem (stejny pristup jako check_terrain_contrast.py's flat_colors()).
   Vypocitane N se tiskne u kazdeho radku hordoveho testu -- nikdy neviditelne cislo.
   **Boss-class sprity (gen:forms's kind == 'distraction_boss', dnes jen
   `social_media_binge`) se hordovym testem neresi vubec** -- Data.build_waves() jim
   dava natvrdo `count = 1` (scripts/data.gd:475), takze nikdy nestoji vedle kopie sebe
   sama; vypisuje se explicitni "SKIP (boss, count=1 per wave)", ne ticha absence,
   a nepocita se ani jako pass ani jako fail (SS12g).

Vsechny tri testy pouzivaji ALPHA_THRESH=128 (SS1, "alpha mask = alpha >= 128") jako
jednotnou definici "nepruhledny pixel".

scipy.ndimage.label dela souvislé komponenty pro test hordy -- scipy uz je v tomhle
repu pouzivane zavislosti (tools/mj_to_sprite.py, tools/gen.py), takze to neni novy
pozadavek na prostredi.

DETERMINISMUS

Zadne casove razitko, seedy fixni (HORDE_SEED), globy tridene -- dva behy davaji
bajtove identicky vystup (Definition of done to vyzaduje).
"""
import argparse
import io
import math
import os
import re
import sys

try:
    import numpy as np
    from PIL import Image
    from scipy import ndimage
except ImportError as e:                                    # pragma: no cover
    raise SystemExit(
        "tools/check_style_failure_modes.py potrebuje Pillow, numpy a scipy "
        "(scipy uz pouziva tools/mj_to_sprite.py a tools/gen.py): %s" % e)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIBLE = os.path.join(ROOT, "docs", "art", "STYLE_BIBLE.md")
FLAT = os.path.join(ROOT, "tools", "flat_terrain.py")
ASSETS = os.path.join(ROOT, "assets")

ALPHA_THRESH = 128     # SS1: "alpha mask = alpha >= 128" -- jednotna definice "nepruhledny"

FIELD_W, FIELD_H = 480, 270    # zadani ukolu: "480x270 field"
# N se od SS12g DOPOCITAVA z cilove hustoty (gen:failure_modes, "horda, hustota"), ne
# drzi pevne na 200 -- viz main()'s compute_n(). Strop a dno jsou z bible doslovne
# ("strop 200, dno 8"), samy o sobe nejsou merene cislo k parsovani odsud.
HORDE_N_FLOOR, HORDE_N_CEIL = 8, 200
# Fixni seed, at jsou behy bajtove reprodukovatelne (zadani ukolu). Datum, kdy smer A
# dostal svuj SS12 (2.9.2026) -- libovolna konstanta by fungovala stejne, tahle je aspon
# k necemu privazana misto "nahodneho" cisla.
HORDE_SEED = 20260902

fails = 0


def check(label, ok, detail=""):
    """Stejny tvar jako tools/check_terrain_contrast.py's check() -- jen GATOVANE
    vysledky (gen:direction_a, nebo --all) smi tudy projit; pocitaji se do exit kodu."""
    global fails
    if ok:
        print("  ok    %s  %s" % (label, detail))
    else:
        fails += 1
        print("  FAIL  %s  %s" % (label, detail))


def legacy(label, hypothetical_ok, detail=""):
    """Zmereno, vytisteno, NEPOCITA se do exit kodu -- cely dnesni rejstrik (SS12b, viz
    hlavicka souboru). "would PASS"/"would MISS" schvalne neobsahuje podretezec "FAIL":
    verify.sh na tenhle log spousti `grep FAIL` jen kdyz skript spadne na exit != 0,
    coz se v defaultnim rezimu stat nemuze (LEGACY nikdy nezmeni exit kod) -- ale az
    gen:direction_a prestane byt prazdna, stejny log ponese i skutecne FAIL radky pro
    gatovane soubory, a LEGACY radky se nesmi plest do toho grepu."""
    word = "would PASS" if hypothetical_ok else "would MISS"
    print("  LEGACY %s  %s  (%s)" % (label, detail, word))


def legacy_inconclusive(label, detail=""):
    """Stejna NEGATOVANA konvence jako legacy(), ale pro treti moznou odpoved hordoveho
    testu (SS12d/SS12g, brana 'horda, platnost kontroly'): kontrolni disk sam nedosahl
    prahu platnosti, takze pole je presycene a vysledek nelze cist ani jako pass ani
    jako fail -- 'would MISS' by tu lhalo stejne jako tichy pass. Nepocita se do exit
    kodu (presne jako legacy())."""
    print("  LEGACY %s  %s  (INCONCLUSIVE -- control below validity threshold)" % (label, detail))


def skip(label, reason):
    """Neni co merit/srovnat -- stejna konvence jako '--' v check_art_colors.py."""
    print("  --    %s  %s" % (label, reason))


def skip_boss(label):
    """Boss-class sprity (gen:forms's kind == 'distraction_boss') se hordovym testem
    nemeri VUBEC -- ani citelnost/N, ani kontrast (SS12g, 'Boss se hordovym testem
    nemeri vubec'): Data.build_waves() mu dava natvrdo count=1
    (scripts/data.gd:475), takze nikdy nestoji vedle kopie sebe sama, a pri 96px by
    dolni hranice N=8 stejne tlacila hustotu zpet k saturaci. Explicitni radek misto
    ticheho vynechani -- nepocita se ani jako pass, ani jako fail, v zadnem rezimu
    (gated i legacy, --all i default)."""
    print("  SKIP  %s  boss, count=1 per wave (scripts/data.gd:475) -- horde test does not apply" % label)


# --------------------------------------------------------------- STYLE_BIBLE.md parsing

def _block(text, key):
    m = re.search(r"<!--\s*%s\s*-->(.*?)<!--\s*/%s\s*-->" % (re.escape(key), re.escape(key)),
                  text, re.S)
    if not m:
        raise SystemExit("STYLE_BIBLE.md: chybi blok <!-- %s -->" % key)
    return m.group(1)


def _table_rows(block):
    """Radky markdown tabulky jako seznam bunek, ESCAPE-AWARE na '|'.

    gen:failure_modes's radek "horda, kontrast vuci tkani" ma ve sloupci "metrika"
    doslovne '\\|soucet RGB jednotky - soucet RGB tkane\\|' -- escapovane svisitka,
    aby se v renderovanem markdownu zobrazila jako '|' misto jako oddelovac sloupcu.
    Obycejny `line.split("|")`, jaky pouzivaji check_terrain_contrast.py a
    check_art_colors.py, by je presto rozstepil (split neresi escapovani) a posunul
    indexy bunek napravo od nej. Rozdil je '(?<!\\\\)\\|' -- rozdel jen na '|', pred
    kterym NENI zpetne lomitko.
    """
    rows = []
    for line in block.splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue
        parts = re.split(r"(?<!\\)\|", line)
        if parts and parts[0] == "":
            parts = parts[1:]
        if parts and parts[-1] == "":
            parts = parts[:-1]
        cells = [c.strip() for c in parts]
        if cells:
            rows.append(cells)
    return rows


def _fmt_num(v):
    return "%d" % v if float(v).is_integer() else "%.2f" % v


def bible_gates():
    """Prahy z <!-- gen:failure_modes --> (SS12d), klic je doslovny text sloupce
    'brana'. Header a oddelovaci radek se preskoci sami -- ani 'prah' (header text) ani
    '---' (oddelovac) nesplni regex na cislo s <=/=/>=, presne jako
    check_terrain_contrast.py's bible_gates(). '=' (SS12g, radek 'horda, hustota' --
    cilova hustota pole, ne pass/fail prah) musi byt v alternaci AZ ZA '<='/'>=', jinak
    by regex na '<= 1.60' chytil jen '=' a zahodil '<'."""
    text = io.open(BIBLE, encoding="utf-8").read()
    gates = {}
    for cells in _table_rows(_block(text, "gen:failure_modes")):
        if len(cells) < 3:
            continue
        m = re.search(r"(<=|>=|=)\s*([\d.]+)", cells[2])
        if m:
            gates[cells[0]] = (m.group(1), float(m.group(2)))
    return gates


REQUIRED_GATES = (
    "silueta, habit", "silueta, distraction", "silueta, odstup rodin",
    "styl, barvy habitu", "styl, barvy distrakce", "styl, soudržnost rodiny",
    "horda, hustota", "horda, platnost kontroly",
    "horda, čitelnost", "horda, kontrast vůči tkáni",
)


def direction_a_entries():
    """Radky <!-- gen:direction_a --> (SS12e): id | rodina | soubor. Prazdna tabulka
    (dnesni stav, viz hlavicka souboru) da prazdny seznam -- to je spravny vysledek,
    ne chyba parsovani."""
    text = io.open(BIBLE, encoding="utf-8").read()
    out = []
    for cells in _table_rows(_block(text, "gen:direction_a")):
        if len(cells) < 3 or cells[0] in ("", "id") or set(cells[0]) <= {"-"}:
            continue
        aid, rodina, soubor = cells[0], cells[1], cells[2]
        if rodina not in ("habit", "distraction"):
            raise SystemExit(
                "STYLE_BIBLE.md gen:direction_a: radek '%s' ma rodinu '%s', "
                "cekano 'habit' nebo 'distraction' -- neparsovatelne, hlaste zpet, "
                "needituju bibli sam." % (aid, rodina))
        out.append({"id": aid, "rodina": rodina, "soubor": soubor})
    return out


def bible_boss_ids():
    """Ids z <!-- gen:forms --> (SS8), jejichz `kind` je 'distraction_boss' -- data-driven
    zdroj pravdy pro to, kdo je boss, misto hardcodovaneho retezce jako 'social_media_binge'
    primo v tomhle skriptu (CLAUDE.md: obsah je data, ne kod). Sloupce jsou
    id | kind | family | base | form; kind je cells[1]. Dnes vrati {'social_media_binge'},
    ale novy boss v bibli se prijme sam, bez zasahu do skriptu."""
    text = io.open(BIBLE, encoding="utf-8").read()
    ids = set()
    for cells in _table_rows(_block(text, "gen:forms")):
        if len(cells) < 2 or cells[0] in ("", "id") or set(cells[0]) <= {"-"}:
            continue
        if cells[1] == "distraction_boss":
            ids.add(cells[0])
    return ids


def _is_boss(aid, boss_ids):
    """`aid` je bud primo boss id (gen:direction_a master), nebo odvozeny z legacy
    nazvu souboru (napr. 'social_media_binge_attack_frame_1'), ktery zacina boss id +
    '_'. Presna shoda i prefix, aby chytilo obe podoby."""
    return any(aid == bid or aid.startswith(bid + "_") for bid in boss_ids)


def parse_file_args(raw_list):
    """--file RODINA=CESTA -> [(id, rodina, absolutni_cesta), ...]. Zadani koordinatora
    (SS12f: master se meri PRED tim, nez se zapise do gen:direction_a a ukaze
    uzivateli): kandidat jeste nema radek v bibli, takze se musi dat gatovat rucne.
    Neznama rodina i chybejici soubor jsou tvrda chyba (SystemExit), nikdy tiche
    preskoceni -- stejny standard jako direction_a_entries()."""
    out = []
    for raw in raw_list:
        rodina, sep, cesta = raw.partition("=")
        if not sep:
            raise SystemExit(
                "--file '%s': cekan tvar RODINA=CESTA, napr. "
                "distraction=assets/raw/master_distraction_a/cand_00.png" % raw)
        if rodina not in ("habit", "distraction"):
            raise SystemExit(
                "--file '%s': neznama rodina '%s', cekano 'habit' nebo "
                "'distraction'" % (raw, rodina))
        # relativni cesta je od korene repa -- stejna konvence jako sloupec `soubor`
        # v gen:direction_a ("cesta od korene repa", SS12e).
        path = cesta if os.path.isabs(cesta) else os.path.normpath(os.path.join(ROOT, cesta))
        if not os.path.isfile(path):
            raise SystemExit("--file '%s': soubor neexistuje: %s" % (raw, cesta))
        aid = os.path.splitext(os.path.basename(path))[0]
        out.append((aid, rodina, path))
    return out


def ground_color():
    """GROUND primo z tools/flat_terrain.py -- stejny regex jako
    check_terrain_contrast.py's flat_colors(), zadna vlastni kopie cisla."""
    text = io.open(FLAT, encoding="utf-8").read()
    m = re.search(r"^GROUND\s*=\s*\((\d+),\s*(\d+),\s*(\d+)\)", text, re.M)
    if not m:
        raise SystemExit("tools/flat_terrain.py: nenasel jsem konstantu GROUND")
    return tuple(int(g) for g in m.groups())


# ------------------------------------------------------------------------- mereni

def load_rgba(path):
    return np.asarray(Image.open(path).convert("RGBA"))


def opaque_mask(rgba):
    return rgba[..., 3] >= ALPHA_THRESH


def _perimeter_mask(mask):
    """4-sousedni okraj nepruhledne oblasti -- pixely s >=1 sousedem, ktery je
    pruhledny nebo mimo platno. Stejna myslenka jako flat_terrain.py's _edge_mask,
    zobecnena na libovolnou masku misto pevne alfy dlazdice."""
    p = np.pad(mask, 1, constant_values=False)
    interior = mask & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]
    return mask & ~interior


def compactness(mask):
    """obvod^2 / (4*pi*plocha). Kruh ~ 1.0, roztrepeny tvar roste (SS12d). None, kdyz
    je maska prazdna (nic nepruhledneho na souboru)."""
    area = int(mask.sum())
    if area == 0:
        return None
    perimeter = int(_perimeter_mask(mask).sum())
    return (perimeter ** 2) / (4.0 * math.pi * area)


def unique_colors(rgb, mask):
    """Pocet unikatnich RGB trojic mezi nepruhlednymi pixely."""
    pix = rgb[mask]
    if pix.size == 0:
        return 0
    return int(np.unique(pix.astype(np.uint8), axis=0).shape[0])


def mean_rgb_sum(rgb, mask):
    if not mask.any():
        return None
    return float(rgb[mask].astype(np.float64).sum(axis=-1).mean())


# --------------------------------------------------------------------- test hordy

def _placements(w, h, seed, n):
    """`n` nahodnych top-left pozic, ktere drzi sprite w x h cely uvnitr FIELD_W x
    FIELD_H. Zavisi jen na (w, h, seed, n) -- realny sprite a kontrolni kotouc stejne
    velikosti bounding boxu a se stejnym dopocitanym N tak dostanou BAJTOVE stejne
    souradnice ('same placements' ze zadani), aniz by se musely predavat rucne."""
    rng = np.random.default_rng(seed)
    max_x, max_y = FIELD_W - w, FIELD_H - h
    if max_x < 0 or max_y < 0:
        return None
    xs = rng.integers(0, max_x + 1, size=n)
    ys = rng.integers(0, max_y + 1, size=n)
    return xs, ys


_STRUCT4 = np.array([[0, 1, 0], [1, 1, 1], [0, 1, 0]])   # 4-souvislost, ne 8


def _separable_share(mask, xs, ys, unit_area):
    """Podil jednotek z N (= len(xs), SS12g dopocitane per-sprite -- viz compute_n()),
    ktere v kompozitu preziji jako vlastni 4-souvisla komponenta o plose 0.5x-2.0x
    plochy jedne jednotky."""
    field = np.zeros((FIELD_H, FIELD_W), dtype=bool)
    h, w = mask.shape
    for x, y in zip(xs.tolist(), ys.tolist()):
        field[y:y + h, x:x + w] |= mask
    labeled, num = ndimage.label(field, structure=_STRUCT4)
    if num == 0:
        return 0.0
    sizes = np.bincount(labeled.ravel())[1:]   # index 0 = pozadi
    lo, hi = 0.5 * unit_area, 2.0 * unit_area
    survivors = int(np.count_nonzero((sizes >= lo) & (sizes <= hi)))
    return survivors / float(len(xs))


def _control_disc(h, w, area):
    """Plny kotouc s presne `area` pixely, uprostred stejneho w x h boxu jako sprite --
    diky stejnemu boxu dostane z _placements() STEJNE souradnice jako sprite sam.
    kind='stable' drzi vyber deterministicky pri remizach ve vzdalenosti od stredu."""
    yy, xx = np.mgrid[0:h, 0:w]
    cy, cx = (h - 1) / 2.0, (w - 1) / 2.0
    dist2 = (yy - cy) ** 2 + (xx - cx) ** 2
    order = np.argsort(dist2, axis=None, kind="stable")
    disc = np.zeros(h * w, dtype=bool)
    disc[order[:area]] = True
    return disc.reshape(h, w)


def compute_n(unit_area, density):
    """N = clamp(round(density * FIELD_W*FIELD_H / unit_area), floor, ceil) -- SS12g.
    Nahrazuje pevnych 200: pri N=200 je pole pro dnesni sprity presycene (i idealni
    kruh vyjde 0.000, viz PROGRESS.md/report z prvni verze tohohle skriptu), takze se
    N misto toho dopocitava tak, aby jednotky pokryvaly stale STEJNY podil pole bez
    ohledu na to, jak velky sprite testujeme."""
    raw = density * FIELD_W * FIELD_H / float(unit_area)
    n = int(round(raw))
    return max(HORDE_N_FLOOR, min(HORDE_N_CEIL, n))


def horde_readability(mask, density):
    """dict s klici n/area/sprite_share/control_share, nebo None, kdyz sprite nema
    zadny nepruhledny pixel nebo se nevejde do FIELD_W x FIELD_H (samotne posouzeni
    validity/ratio je na volajicim -- main() to potrebuje rozlisit od INCONCLUSIVE,
    ktere je platny vysledek testu, jen negativni)."""
    h, w = mask.shape
    area = int(mask.sum())
    if area == 0:
        return None
    n = compute_n(area, density)
    placed = _placements(w, h, HORDE_SEED, n)
    if placed is None:
        return None
    xs, ys = placed
    sprite_share = _separable_share(mask, xs, ys, area)
    control_share = _separable_share(_control_disc(h, w, area), xs, ys, area)
    return {"n": n, "area": area, "sprite_share": sprite_share, "control_share": control_share}


def horde_contrast(rgba, ground_rgb):
    mask = opaque_mask(rgba)
    m = mean_rgb_sum(rgba[..., :3], mask)
    if m is None:
        return None
    return abs(m - sum(ground_rgb))


# --------------------------------------------------------------- rejstrik na disku

def _rel(path):
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


def legacy_habit_files():
    d = os.path.join(ASSETS, "towers")
    if not os.path.isdir(d):
        return []
    return sorted(
        os.path.join(d, f) for f in os.listdir(d)
        if f.startswith("head_") and f.endswith(".png")
    )


def legacy_distraction_files():
    d = os.path.join(ASSETS, "distractions")
    if not os.path.isdir(d):
        return []
    return sorted(
        os.path.join(d, f) for f in os.listdir(d)
        if f.endswith("_frame_1.png")
    )


def _gate_ok(op, threshold, value):
    if op == "<=":
        return value <= threshold
    if op == ">=":
        return value >= threshold
    if op == "=":
        return value == threshold
    raise SystemExit("check_style_failure_modes.py: neznamy operator branky '%s'" % op)


def _gate_str(op, threshold):
    return "%s %s" % (op, _fmt_num(threshold))


# ------------------------------------------------------------------------------ main

def main():
    ap = argparse.ArgumentParser(
        description="Meri silhouette/style/horde failure-mode brany smeru A "
                    "(STYLE_BIBLE.md SS12d) na PNG souborech.")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--all", action="store_true",
                       help="gatuj i cely legacy rejstrik (assets/towers/head_*.png, "
                            "assets/distractions/*_frame_1.png), ne jen "
                            "gen:direction_a -- diagnosticky pohled, verify.sh tohle "
                            "nepouziva")
    mode.add_argument("--file", action="append", default=[], metavar="RODINA=CESTA",
                       help="zmer VYHRADNE tenhle soubor jako gatovany kandidat "
                            "(stejne brany a stejne pocitani do exit kodu jako radek "
                            "v gen:direction_a) -- opakovatelne, pro master pred "
                            "schvalenim, kdy jeste nema radek v bibli (SS12f). "
                            "RODINA je 'habit' nebo 'distraction', CESTA je cesta od "
                            "korene repa (nebo absolutni). Priklad: --file "
                            "distraction=assets/raw/master_distraction_a/cand_00.png "
                            "--file habit=assets/raw/master_habit_a/cand_00.png. "
                            "Kdyz je zadano, negatuji se legacy globy ani "
                            "gen:direction_a -- jen presne tyhle soubory.")
    args = ap.parse_args()

    gates = bible_gates()
    missing = [k for k in REQUIRED_GATES if k not in gates]
    if missing:
        raise SystemExit(
            "STYLE_BIBLE.md gen:failure_modes: nejde naparsovat prah pro %s -- "
            "hlaste zpet, needituju bibli sam." % ", ".join(missing))
    ground = ground_color()
    boss_ids = bible_boss_ids()
    file_entries = parse_file_args(args.file)

    if file_entries:
        # --file: VYHRADNE tyhle soubory, se stejnym src="direction_a" znackou jako
        # radek v gen:direction_a -- boss-skip, INCONCLUSIVE=FAIL a vsechny ostatni
        # gatovane vetve nize se pak chovaji identicky, bez duplikovane logiky.
        gated_entries = [(aid, rodina, path, "direction_a") for aid, rodina, path in file_entries]
        legacy_entries = []
        pool = sorted(gated_entries, key=lambda e: (e[1], e[0]))
        printed_legacy = []
    else:
        direction_a = direction_a_entries()
        gated_paths = set()
        gated_entries = []
        for e in direction_a:
            p = os.path.normpath(os.path.join(ROOT, e["soubor"]))
            gated_paths.add(p)
            gated_entries.append((e["id"], e["rodina"], p, "direction_a"))

        legacy_entries = []
        for p in legacy_habit_files():
            if os.path.normpath(p) in gated_paths:
                continue
            aid = os.path.splitext(os.path.basename(p))[0]
            legacy_entries.append((aid, "habit", p, "legacy"))
        for p in legacy_distraction_files():
            if os.path.normpath(p) in gated_paths:
                continue
            aid = os.path.basename(p)[:-4]   # strip ".png", keep the "_frame_1" suffix
            legacy_entries.append((aid, "distraction", p, "legacy"))

        if args.all:
            pool = sorted(gated_entries + legacy_entries, key=lambda e: (e[1], e[0]))
            printed_legacy = []
        else:
            pool = sorted(gated_entries, key=lambda e: (e[1], e[0]))
            printed_legacy = sorted(legacy_entries, key=lambda e: (e[1], e[0]))

    print("STYLE_BIBLE.md SS12d failure-mode brany")
    print("GROUND (tools/flat_terrain.py) = rgb%s, soucet %d" % (ground, sum(ground)))
    if file_entries:
        print("--file: gatuji VYHRADNE %d zadany soubor(u) (%d habit, %d distraction) "
              "-- zadne legacy globy, zadna gen:direction_a. Kandidat pred schvalenim "
              "(SS12f)." % (len(pool),
                             sum(1 for e in pool if e[1] == "habit"),
                             sum(1 for e in pool if e[1] == "distraction")))
        for aid, rodina, path, src in pool:
            print("  %-11s %-20s %s" % (rodina, aid, _rel(path)))
    elif args.all:
        print("--all: gatuji VSECHNO -- gen:direction_a (%d) + legacy rejstrik (%d) "
              "= %d souboru." % (len(gated_entries), len(legacy_entries), len(pool)))
    else:
        print("gatuji %d soubor(u) z gen:direction_a (STYLE_BIBLE.md SS12e)." % len(pool))
        if not pool:
            print("  -> gen:direction_a je PRAZDNA: smer A nema zadny schvaleny "
                  "master (SS12f). Tenhle beh proto ZAMERNE gatuje NULU souboru --")
            print("  -> prazdna brana neni splnena brana, jen se na nic nevztahuje.")
        print("Zbytek rejstriku (%d souboru: %d habit hlav, %d distraction snimku) "
              "se meri a tiskne jako LEGACY, do exit kodu se nepocita -- SS12b, "
              "viz hlavicka skriptu." % (
                  len(printed_legacy),
                  sum(1 for e in printed_legacy if e[1] == "habit"),
                  sum(1 for e in printed_legacy if e[1] == "distraction")))

    def measure(entries):
        """id -> (rgba, mask) pro kazdy soubor v `entries`, s FAIL/skip pro chybejici
        nebo prazdne soubory (posila se pres `report`, ne pres `legacy`, protoze
        'soubor uveden v gen:direction_a neexistuje' je chyba dat, ne legacy stav)."""
        out = []
        for aid, fam, path, src in entries:
            label = "%-11s %-40s" % (fam, aid)
            if not os.path.isfile(path):
                if src == "direction_a":
                    check(label, False, "soubor neexistuje: %s" % _rel(path))
                else:
                    skip(label, "soubor neexistuje: %s" % _rel(path))
                continue
            rgba = load_rgba(path)
            mask = opaque_mask(rgba)
            if not mask.any():
                if src == "direction_a":
                    check(label, False, "zadny nepruhledny pixel (alpha>=%d): %s" %
                          (ALPHA_THRESH, _rel(path)))
                else:
                    skip(label, "zadny nepruhledny pixel (alpha>=%d): %s" %
                         (ALPHA_THRESH, _rel(path)))
                continue
            out.append((aid, fam, path, src, label, rgba, mask))
        return out

    gated_m = measure(pool)
    legacy_m = measure(printed_legacy)

    # ----------------------------------------------------------------- silueta
    print()
    print("== silhouette (compactness = perimeter^2 / (4*pi*area)) ==")
    sil_by_fam = {"habit": {}, "distraction": {}}
    for aid, fam, path, src, label, rgba, mask in gated_m:
        c = compactness(mask)
        op, th = gates["silueta, habit" if fam == "habit" else "silueta, distraction"]
        ok = _gate_ok(op, th, c)
        check(label, ok, "compactness=%.2f (%s)" % (c, _gate_str(op, th)))
        sil_by_fam[fam][aid] = c
    for aid, fam, path, src, label, rgba, mask in legacy_m:
        c = compactness(mask)
        op, th = gates["silueta, habit" if fam == "habit" else "silueta, distraction"]
        legacy(label, _gate_ok(op, th, c), "compactness=%.2f (%s)" % (c, _gate_str(op, th)))

    op, th = gates["silueta, odstup rodin"]
    hab_c, dist_c = sil_by_fam["habit"], sil_by_fam["distraction"]
    if hab_c and dist_c:
        sep = min(dist_c.values()) - max(hab_c.values())
        check("silhouette family separation", _gate_ok(op, th, sep),
              "min(distraction)-max(habit)=%.2f (%s)" % (sep, _gate_str(op, th)))
    else:
        skip("silhouette family separation",
             "potrebuje >=1 gatovany habit a >=1 gatovanou distraction "
             "(ma %d habitu, %d distrakci)" % (len(hab_c), len(dist_c)))

    # ------------------------------------------------------------ styl (pet stylu)
    print()
    print("== style cohesion (unique RGB among opaque pixels) ==")
    col_by_fam = {"habit": {}, "distraction": {}}
    for aid, fam, path, src, label, rgba, mask in gated_m:
        n = unique_colors(rgba[..., :3], mask)
        op, th = gates["styl, barvy habitu" if fam == "habit" else "styl, barvy distrakce"]
        ok = _gate_ok(op, th, n)
        check(label, ok, "colours=%d (%s)" % (n, _gate_str(op, th)))
        col_by_fam[fam][aid] = n
    for aid, fam, path, src, label, rgba, mask in legacy_m:
        n = unique_colors(rgba[..., :3], mask)
        op, th = gates["styl, barvy habitu" if fam == "habit" else "styl, barvy distrakce"]
        legacy(label, _gate_ok(op, th, n), "colours=%d (%s)" % (n, _gate_str(op, th)))

    op, th = gates["styl, soudržnost rodiny"]
    for fam in ("habit", "distraction"):
        counts = col_by_fam[fam]
        if len(counts) >= 2:
            spread = max(counts.values()) - min(counts.values())
            check("style family spread (%s)" % fam, _gate_ok(op, th, spread),
                  "max-min colours=%d (%s)" % (spread, _gate_str(op, th)))
        else:
            skip("style family spread (%s)" % fam,
                 "potrebuje >=2 gatovane soubory v rodine %s (ma %d)" % (fam, len(counts)))

    # -------------------------------------------------------- horda (jen distraction)
    print()
    print("== horde legibility (distraction only -- habits never swarm) ==")
    density_op, DENSITY = gates["horda, hustota"]
    if density_op != "=":
        raise SystemExit(
            "STYLE_BIBLE.md gen:failure_modes 'horda, hustota': cekan operator '=', "
            "mam '%s' -- nejde interpretovat jako cilovou hustotu, hlaste zpet, "
            "needituju bibli sam." % density_op)
    op_v, th_v = gates["horda, platnost kontroly"]
    op_r, th_r = gates["horda, čitelnost"]
    op_c, th_c = gates["horda, kontrast vůči tkáni"]
    print("  (cilova hustota=%s, N = clamp(round(hustota*%d/plocha_jednotky), %d, %d) -- SS12g)"
          % (_fmt_num(DENSITY), FIELD_W * FIELD_H, HORDE_N_FLOOR, HORDE_N_CEIL))

    def horde_row(aid, fam, path, src, label, rgba, mask, report, report_inconclusive):
        res = horde_readability(mask, DENSITY)
        if res is None:
            msg = "sprite nelze rozmistit na %dx%d pole (moc velky, nebo prazdny)" % (FIELD_W, FIELD_H)
            if src == "direction_a":
                check(label, False, msg)   # gatovany soubor, ktery se ani nevejde, je FAIL
            else:
                skip(label, msg)
        else:
            n, area = res["n"], res["area"]
            sprite_share, control_share = res["sprite_share"], res["control_share"]
            base = "N=%d (area=%d, hustota=%s)  sprite_share=%.3f control_share=%.3f" % (
                n, area, _fmt_num(DENSITY), sprite_share, control_share)
            if not _gate_ok(op_v, th_v, control_share):
                # Pojistka proti ticho nule (SS12g/SS12d "horda, platnost kontroly"):
                # kdyz neuspeje ani idealni kruh, pole je presycene a pomer by lhal --
                # ani jednomu z obou vysledku (report/report_inconclusive) se tu nesmi
                # vratit "ok=True", protoze presycene pole neni prokazana kvalita.
                report_inconclusive(label, "%s  (control_share fails validity %s)" % (base, _gate_str(op_v, th_v)))
            else:
                ratio = sprite_share / control_share
                ok = _gate_ok(op_r, th_r, ratio)
                report(label, ok, "%s ratio=%.3f (%s)" % (base, ratio, _gate_str(op_r, th_r)))
        contrast = horde_contrast(rgba, ground)
        if contrast is None:
            skip(label + " contrast", "zadny nepruhledny pixel")
        else:
            ok = _gate_ok(op_c, th_c, contrast)
            report(label + " contrast", ok, "|unit-GROUND|=%.1f (%s)" % (contrast, _gate_str(op_c, th_c)))

    dist_gated = [e for e in gated_m if e[1] == "distraction"]
    dist_legacy = [e for e in legacy_m if e[1] == "distraction"]
    hab_gated = sum(1 for e in gated_m if e[1] == "habit")
    hab_legacy = sum(1 for e in legacy_m if e[1] == "habit")
    if hab_gated or hab_legacy:
        print("  (%d gated + %d legacy habit file(s) skipped -- horde gate is "
              "distraction-only, habits are stationary towers)" % (hab_gated, hab_legacy))

    for aid, fam, path, src, label, rgba, mask in dist_gated:
        if _is_boss(aid, boss_ids):
            # SS12g "Boss se hordovym testem nemeri vubec": count=1 za level, nikdy
            # nestoji vedle kopie sebe sama. Plati stejne pro gatovane i legacy --
            # neni to vlastnost diagnostickeho rezimu, je to vlastnost hry.
            skip_boss(label)
            continue
        # gatovany soubor: INCONCLUSIVE se pocita jako FAIL (check(False)), ne jako
        # zvlastni netrestany stav -- presycene pole se nesmi splest se splnenou branou
        # (zadani koordinatora, SS12g).
        horde_row(aid, fam, path, src, label, rgba, mask,
                  lambda l, ok, d: check(l, ok, d),
                  lambda l, d: check(l, False, d))
    for aid, fam, path, src, label, rgba, mask in dist_legacy:
        if _is_boss(aid, boss_ids):
            skip_boss(label)
            continue
        horde_row(aid, fam, path, src, label, rgba, mask,
                  lambda l, ok, d: legacy(l, ok, d),
                  lambda l, d: legacy_inconclusive(l, d))

    print()
    print("%s (%d failures)" % ("PASSED" if fails == 0 else "FAILED", fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
