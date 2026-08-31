"""Overi, ze deklarovana barva (pole `color` v data/distractions|defenders|habits/*.tres)
a barva popsana v STYLE_BIBLE.md §8 sedi s tim, jakou barvu ma tvor/obrance/habit
na SVEM SKUTECNE SHIPNUTEM PNG.

    python tools/check_art_colors.py     # 0 = OK, 1 = novy nezdokumentovany nesoulad

PROC TO EXISTUJE

29. 8. 2026 review z live gameplay screenshotu zjistil, ze `doomscroll` je na obrazovce
jantarovo-hnedy, i kdyz `data/distractions/doomscroll.tres` rika `color = "33cc77"`
(zelena) a `STYLE_BIBLE.md` ho popisuje jako "a long green ciliated ribbon". Pricina:
`distraction_animator.gd` — art na disku vzdy vyhraje nad procedural fallbackem, a pole
`color` z `.tres` po tu dobu ridi uz jen zarivku (glow halo), NIKDY telo pixelu. Sprite
se tedy muze vymenit (napr. za pozustatek zruseneho junk-food smeru) a `.tres`/bible
zustanou tise nepravdive — nic to nehlida.

Tenhle skript je to hlidani. Meri DOMINANTNI ODSTIN skutecneho PNG a porovnava ho s tim,
co tvrdi `.tres` (a, kdyz to jde, s tim, co tvrdi bible) — stejnym zpusobem, jakym
tools/check_terrain_contrast.py hlida kontrast terenu proti bible misto toho, aby mu
proza v §4 verila na slovo.

METODA (kalibrovano na doomscroll case + rucni vizualni kontrole vsech kandidatu)

Dominantni odstin = KRUHOVY PRUMER odstinu pres vsechny JASNE A SYTE nepruhledne pixely
zakladni sady snimku (idle/chuze, NE death/attack/efekty). "Jasny a syty" filtr (sytost
>= 0.35, max kanal >= 140) je nutny: bez nej vyhraje kazdemu spritu poctem pixelu skoro
cerny 1px obrys nebo stinovany tón, a signal je pryc. Kruhovy prumer (ne "nejcetnejsi
jedna RGB hodnota") kvuli tomu, ze pixel-art stinovani rozbiji jeden vizualni odstin do
desitek blizkych-ale-ruznych RGB hodnot — "nejcetnejsi jedna barva" pak muze prohrat s
mensinovym akcentem, ktery ma nahodou presnejsi shodu (zmereno na energy_drink: bez
prumerovani vyhral zluty highlight nad tealovym telem, ktere melo dohromady vic pixelu,
jen rozprostrenych do vice odstinu). Stejna technika jako `style_audit.hue_shift()` v
tomhle repu, jen bez vahy sytosti navic.

HUE_GAP_THRESHOLD je volne schvalne (viz nize) — tohle ma chytit doomscroll (zelena vs.
jantarova, ~180° od sebe), ne ztrestat stin nebo rozsviceny/zhasnuty odstin te same
barvy. `.tres` barva blizko neutralni (sytost <= 0.15) se nesrovnava vubec — hodnota
odstinu u skoro sede barvy nic neznamena (stejna branka jako `saturation()` v
check_terrain_contrast.py).

Bible dava specificke slovo barvy jen u casti entit (§8, sloupec `form`) — kde ho nema,
skript to hlasi jako "bible: zadny zaznam" a NEVYMYSLI si ocekavani, ktere tam neni.
Slova jako "ivory"/"bleached"/"hollow" jsou z COLOR_WORDS zamerne vynechana: popisuji
skoro odbarveny tón, u ktereho je odstin ze stejneho duvodu nestabilni.

Pole `projectile_color` (habity) NENI v teto kontrole — je to barva letici strely,
samostatny vizualni kanal, ktery se schvalne muze od tela lisit (kontrast na desce).
Srovnavat ho s dominantni barvou tela by bylo vynucene srovnani, ktere nic negarantuje.

ART_DEBT.md JAKO JEDINY ZDROJ PRAVDY O ZNAMYCH NALEZECH

Skript sam o sobe NEROZHODUJE, co je "OK" navzdory nesouladu — parsuje
`docs/art/ART_DEBT.md` (nadpisy `## <id>` a radky `**Affected ids:** ...`) a kazdy
nesoulad, jehoz ID uz tam je zapsane, hlasi jako KNOWN (informativni, nepocita se do
exit kodu). Nezdokumentovany novy nesoulad je FAIL. Zadna kopie seznamu tady v kodu —
presne filozofie, kterou uz check_terrain_contrast.py popisuje u sve dvojice se
STYLE_BIBLE.md a roster.py u sve dvojice s ROSTER.md.
"""
import colorsys
import io
import math
import os
import re
import sys

try:
    import numpy as np
    from PIL import Image
except ImportError as e:                                    # pragma: no cover
    raise SystemExit(
        "tools/check_art_colors.py potrebuje Pillow a numpy (stejne jako "
        "tools/style_audit.py a tools/art_check.py): %s" % e)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
DATA = os.path.join(ROOT, "data")
BIBLE = os.path.join(ROOT, "docs", "art", "STYLE_BIBLE.md")
DEBT = os.path.join(ROOT, "docs", "art", "ART_DEBT.md")

fails = 0
known_count = 0


# --------------------------------------------------------- hue/hue_gap/saturation
# Mirrored 1:1 z tools/check_terrain_contrast.py -- stejne vzorce, at cisla z obou
# kontrol zustanou navzajem srovnatelna.


def hue(c):
    """Odstin ve stupnich, 0-360. Sedy vrati 0."""
    r, g, b = [x / 255.0 for x in c]
    hi, lo = max(r, g, b), min(r, g, b)
    d = hi - lo
    if d == 0:
        return 0.0
    if hi == r:
        h = 60.0 * (((g - b) / d) % 6.0)
    elif hi == g:
        h = 60.0 * (((b - r) / d) + 2.0)
    else:
        h = 60.0 * (((r - g) / d) + 4.0)
    return h % 360.0


def hue_gap(a, b):
    """Kruhovy rozdil odstinu -- pres 0/360 se pocita tou kratsi cestou."""
    d = abs(hue(a) - hue(b)) % 360.0
    return min(d, 360.0 - d)


def saturation(c):
    hi = max(c)
    return 0.0 if hi == 0 else (hi - min(c)) / float(hi)


def hexcol(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hue_to_rgb(h):
    """Plne syta zastupna barva pro dany odstin -- prevadi bibli/prumerny odstin
    zpatky na RGB, aby s nim slo pocitat hue_gap()."""
    r, g, b = colorsys.hsv_to_rgb(h / 360.0, 1.0, 1.0)
    return (r * 255.0, g * 255.0, b * 255.0)


ALPHA_MIN = 32       # stejny prah jako art_check.py/style_audit.py -- pod tim uz pixel
                      # v pixel artu prakticky neexistuje
SAT_MIN = 0.35        # "jasny a syty" filtr, viz hlavicka souboru
VAL_MIN = 140
HUE_GAP_THRESHOLD = 100.0     # volne, viz hlavicka -- chyta zelenou-vs-hnedou, ne stin


def dominant_hue(paths):
    """Kruhovy prumer odstinu pres vsechny jasne+syte nepruhledne pixely napric
    danymi soubory. None, kdyz zadny soubor neexistuje nebo nema kvalifikujici pixel.

    Vektorizovano pres numpy (stejny vzor jako tools/style_audit.py a
    tools/art_check.py) -- ta sama scalar formule jako hue() nahore, jen na cele
    pole najednou; na stovkach snimku je smycka pres getdata() znatelne pomalejsi."""
    sx = sy = 0.0
    n = 0
    for p in paths:
        if not os.path.isfile(p):
            continue
        a = np.asarray(Image.open(p).convert("RGBA")).astype(np.float64)
        rgb, alpha = a[..., :3], a[..., 3]
        mx, mn = rgb.max(axis=-1), rgb.min(axis=-1)
        sat = np.divide(mx - mn, mx, out=np.zeros_like(mx), where=mx > 0)
        mask = (alpha > ALPHA_MIN) & (mx >= VAL_MIN) & (sat >= SAT_MIN)
        if not mask.any():
            continue
        r, g, b = rgb[..., 0][mask], rgb[..., 1][mask], rgb[..., 2][mask]
        mxm, d = mx[mask], (mx - mn)[mask]
        d_safe = np.where(d == 0, 1.0, d)
        is_r = mxm == r
        is_g = (mxm == g) & ~is_r
        is_b = ~is_r & ~is_g
        h = np.zeros_like(mxm)
        h[is_r] = 60.0 * (((g[is_r] - b[is_r]) / d_safe[is_r]) % 6.0)
        h[is_g] = 60.0 * (((b[is_g] - r[is_g]) / d_safe[is_g]) + 2.0)
        h[is_b] = 60.0 * (((r[is_b] - g[is_b]) / d_safe[is_b]) + 4.0)
        rad = np.radians(np.mod(h, 360.0))
        sx += float(np.cos(rad).sum())
        sy += float(np.sin(rad).sum())
        n += int(h.size)
    if n == 0:
        return None
    return math.degrees(math.atan2(sy, sx)) % 360.0


# --------------------------------------------------------------------- .tres cteni

ID_RE = re.compile(r'^id\s*=\s*&"([^"]+)"', re.M)
COLOR_RE = re.compile(r'^color\s*=\s*"([0-9a-fA-F]{6})"', re.M)
UPGRADES_RE = re.compile(r'^upgrades\s*=.*?\((.*?)\)\s*$', re.M)

# Vychozi hodnota pole `color`, kdyz v .tres vubec neni (Godot neuklada property,
# ktera se rovna vychozi hodnote skriptu) -- viz scripts/resources/*_data.gd.
SCRIPT_DEFAULT_COLOR = {
    "distractions": "ff5566",
    "defenders": "7cffb2",
    "habits": "4aa3ff",
}


def read_tres(path):
    text = io.open(path, encoding="utf-8", errors="ignore").read()
    m = ID_RE.search(text)
    aid = m.group(1) if m else os.path.splitext(os.path.basename(path))[0]
    m = COLOR_RE.search(text)
    color = m.group(1) if m else None
    m = UPGRADES_RE.search(text)
    upgrades = re.findall(r'&?"([^"]+)"', m.group(1)) if m else []
    return aid, color, upgrades


def scan_tres(folder):
    out = {}
    d = os.path.join(DATA, folder)
    if not os.path.isdir(d):
        return out
    for f in sorted(os.listdir(d)):
        if not f.endswith(".tres"):
            continue
        aid, color, upgrades = read_tres(os.path.join(d, f))
        out[aid] = {"color": color or SCRIPT_DEFAULT_COLOR[folder], "upgrades": upgrades}
    return out


def habit_roots(habits):
    """id -> koren upgradovaci linie -- stejny vypocet jako Data.habit_family()
    (scripts/data.gd) a tools/art_check.py habit_roots(), tady nad textem .tres,
    protoze GDScript odsud nejde volat."""
    parent = {}
    for me, info in habits.items():
        for child in info["upgrades"]:
            parent[child] = me
    roots = {}
    for i in habits:
        r, seen = i, {i}
        while r in parent and parent[r] not in seen:
            r = parent[r]
            seen.add(r)
        roots[i] = r
    return roots


# ------------------------------------------------------------- shipnute cesty k artu

def distraction_frames(aid):
    out = []
    for i in range(1, 33):
        p = os.path.join(ASSETS, "distractions", "%s_frame_%d.png" % (aid, i))
        if not os.path.isfile(p):
            break
        out.append(p)
    return out


def defender_frames(aid):
    for setn in ("idle", "walk_south"):
        out = []
        for i in range(1, 17):
            p = os.path.join(ASSETS, "defenders", "%s_%s_frame_%d.png" % (aid, setn, i))
            if not os.path.isfile(p):
                break
            out.append(p)
        if out:
            return out
    return []


def habit_head_paths(aid, roots):
    """Stejny fallback jako tower.gd's _head_art_key(): kdyz tenhle habit nema
    vlastni hlavu na disku, hra pouzije hlavu koreni jeho upgradovaci linie -- takze
    i my musime, jinak bychom srovnavali s neexistujicim souborem."""
    key = aid
    if not (os.path.isfile(os.path.join(ASSETS, "towers", "head_%s.png" % aid))
            or os.path.isfile(os.path.join(ASSETS, "towers", "head_%s_frame_1.png" % aid))):
        key = roots.get(aid, aid)
    static = os.path.join(ASSETS, "towers", "head_%s.png" % key)
    if os.path.isfile(static):
        return [static], key
    out = []
    for i in range(1, 33):
        p = os.path.join(ASSETS, "towers", "head_%s_frame_%d.png" % (key, i))
        if not os.path.isfile(p):
            break
        out.append(p)
    return out, key


# --------------------------------------------------------------- STYLE_BIBLE.md §8

# Kazde slovo -> reprezentativni odstin. POZOR: zamerne tu NEJSOU slova jako
# "ivory"/"bleached"/"hollow" -- popisuji skoro neutralni/odbarveny tón, u ktereho je
# odstin nestabilni (stejny duvod, proc ma check_terrain_contrast.py branku na sytost).
# Zahrnout by je znamenalo vymyslet ocekavani, ktere bible fakticky nedava.
COLOR_WORDS = [
    ("crimson", 348), ("magenta", 300), ("violet", 270), ("indigo", 265),
    ("pink", 330), ("red", 0), ("blue", 215), ("teal", 175), ("cyan", 185),
    ("green", 130), ("amber", 40), ("orange", 30), ("golden", 45), ("gold", 45),
    ("yellow", 55), ("purple", 280),
]


def bible_forms():
    text = io.open(BIBLE, encoding="utf-8").read()
    m = re.search(r"<!--\s*gen:forms\s*-->(.*?)<!--\s*/gen:forms\s*-->", text, re.S)
    if not m:
        raise SystemExit("STYLE_BIBLE.md: chybi blok <!-- gen:forms -->")
    forms = {}
    for line in m.group(1).splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < 5 or cells[0] in ("id", "") or set(cells[0]) <= {"-"}:
            continue
        forms[cells[0]] = cells[4]
    return forms


def bible_hue_for(form_text):
    if not form_text:
        return None, None
    low = form_text.lower()
    for word, h in COLOR_WORDS:
        if re.search(r'\b' + re.escape(word) + r'\b', low):
            return h, word
    return None, None


# ---------------------------------------------------------- docs/art/ART_DEBT.md

def known_ids():
    """Ktera ID uz maji zaznam v ART_DEBT.md -- ta se hlasi jako KNOWN, ne FAIL.
    Parsuje nadpisy `## <id>` a radky `**Affected ids:** id1, id2` (pro rodiny, kde
    jedno PNG shipuje vic .tres ID, napr. tier-2 habit bez vlastniho artu). Jediny
    zdroj pravdy je ten soubor sam -- zadna kopie seznamu tady v kodu."""
    if not os.path.isfile(DEBT):
        return set()
    text = io.open(DEBT, encoding="utf-8").read()
    ids = set(re.findall(r'^##\s+(\S+)', text, re.M))
    for m in re.finditer(r'^\*\*Affected ids:\*\*\s*(.+)$', text, re.M):
        for tok in re.split(r'[,\s]+', m.group(1)):
            tok = tok.strip('`, ')
            if tok:
                ids.add(tok)
    return ids


# ------------------------------------------------------------------------- audit

def audit_one(paths, tres_hex, bible_word_hue):
    """(mismatch, detail). mismatch je None, kdyz neni co srovnavat (zadny shipnuty
    PNG, zadny kvalifikujici pixel, nebo je .tres barva i bible prilis neutralni/
    nezname na to, aby mel odstin smysl)."""
    if not paths:
        return None, "zadny shipnuty PNG (jen procedural fallback) -- nic ke srovnani"
    mean = dominant_hue(paths)
    if mean is None:
        return None, "zadny jasny/syty pixel v shipnutem artu -- nic ke zmereni"

    tres_rgb = hexcol(tres_hex)
    bh, bw = bible_word_hue
    gap_tres = hue_gap(hue_to_rgb(mean), tres_rgb) if saturation(tres_rgb) > 0.15 else None
    gap_bible = hue_gap(hue_to_rgb(mean), hue_to_rgb(bh)) if bh is not None else None

    # Branka: primarne .tres barva. Kdyz je .tres prilis neutralni na srovnani (a
    # bible ma slovo), spadni na bibli -- at se aspon jedno smysluplne srovnani
    # provede misto zahozeni cele kontroly.
    gap = gap_tres if gap_tres is not None else gap_bible
    bible_txt = ("bible=%s(~%d°)" % (bw, bh)) if bw else "bible=zadny zaznam"
    if gap is None:
        return None, ("tres #%s i %s -- oboji prilis neutralni/chybi, neni co "
                       "srovnat" % (tres_hex, bible_txt))

    detail = "sprite ~%.0f°  tres #%s(~%.0f°) gap %.0f°  %s" % (
        mean, tres_hex, hue(tres_rgb), gap, bible_txt)
    return gap >= HUE_GAP_THRESHOLD, detail


def emit(label, mismatch, detail, ids_for_lookup, known_set):
    """Vytiskne jeden radek a aktualizuje globalni pocitadla. `ids_for_lookup` je
    seznam ID, ktere se maji zkusit proti ART_DEBT.md (typicky [asset_id], u habitu
    navic i resolved art-key, kdyby zaznam byl veden pod korenem rodiny)."""
    global fails, known_count
    if mismatch is None:
        print("  --   %-22s %s" % (label, detail))
        return
    if not mismatch:
        print("  ok   %-22s %s" % (label, detail))
        return
    if any(i in known_set for i in ids_for_lookup):
        known_count += 1
        print("  KNOWN %-21s %s" % (label, detail))
    else:
        fails += 1
        print("  FAIL %-22s %s  (nezdokumentovano v docs/art/ART_DEBT.md)" % (label, detail))


def main():
    forms = bible_forms()
    known_set = known_ids()
    dist = scan_tres("distractions")
    defn = scan_tres("defenders")
    hab = scan_tres("habits")
    roots = habit_roots(hab)

    print("distrakce (data/distractions -> assets/distractions):")
    for aid in sorted(dist):
        paths = distraction_frames(aid)
        mismatch, detail = audit_one(paths, dist[aid]["color"], bible_hue_for(forms.get(aid)))
        emit(aid, mismatch, detail, [aid], known_set)

    print("\nobranci (data/defenders -> assets/defenders):")
    for aid in sorted(defn):
        paths = defender_frames(aid)
        mismatch, detail = audit_one(paths, defn[aid]["color"], bible_hue_for(forms.get(aid)))
        emit(aid, mismatch, detail, [aid], known_set)

    print("\nhabity (data/habits -> assets/towers, s fallbackem na koren linie):")
    for aid in sorted(hab):
        paths, key = habit_head_paths(aid, roots)
        mismatch, detail = audit_one(paths, hab[aid]["color"], bible_hue_for(forms.get(aid)))
        label = aid if key == aid else "%s (art:%s)" % (aid, key)
        emit(label, mismatch, detail, [aid, key], known_set)

    print("\n%s -- %d FAIL, %d KNOWN, prah %.0f°" %
          ("PASSED" if fails == 0 else "FAILED", fails, known_count, HUE_GAP_THRESHOLD))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
