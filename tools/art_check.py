# Kontrola artu: co je rozbite, zmerene misto odhadnute.
#
#   python tools/art_check.py                  # zkontroluj vsechno, report do build/
#   python tools/art_check.py --only towers    # jen jedna kategorie
#   python tools/art_check.py --fix            # aplikuj bezpecne opravy
#   python tools/art_check.py --quiet          # jen souhrn (pro git hook / CI)
#
# PROC TENHLE NASTROJ EXISTUJE
#
# "Grafika vypada divne" neni zadani, ktere jde opravit. Tenhle skript to prevadi na
# seznam: ktery soubor, co je s nim, o kolik. Vsechny ostatni nastroje v tools/ pak maji
# proti cemu merit, jestli neco zlepsily.
#
# Delici cara je jednoducha: kontroluje se jen to, u ceho je "spravne" MERITELNE.
# Jestli prisera cte jako energy drink, tohle neresi a resit nebude.
#
# ZAVAZNOSTI
#
#   CHYBA   Mechanicky spatne, bez prostoru pro nazor. Chybejici art pro zive ID,
#           ruzny pocet framu mezi smery, poloprusvitne okraje v pixel artu.
#   VAROVANI Nejspis spatne, chce to oko. Prilis velka paleta, sum, nesedici pohledy.
#   INFO    Stoji za vedomi. Osirely soubor, ruzne zdrojove velikosti v kategorii.
#
# OSIRELE SOUBORY SE NEKONTROLUJI NA KVALITU. Soubor, na ktery hra neodkazuje, se ohlasi
# jako osirely a tim to konci - jinak by report utopily vytky k artu, ktery nikdo nevidi.
# Prave proto je tenhle nastroj prvni v rade: teprve on rekne, co je z toho vubec ve hre.
import argparse
import os
import re
import sys
from collections import Counter, defaultdict

import numpy as np
from PIL import Image

# Windows konzole jede v cp852/cp1250 a diakritika by se rozsypala na necitelne znaky.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import game_raster                                   # noqa: E402

ASSETS = os.path.join(PROJ, "assets")
DATA = os.path.join(PROJ, "data")
REPORT = os.path.join(PROJ, "build", "art_report.html")

FRAME_RE = re.compile(r"^(.*)_frame_(\d+)\.png$")
ID_RE = re.compile(r'^id\s*=\s*&?"([^"]+)"', re.M)

# Cilova velikost pixelu na obrazovce. Vsechen art by mel po vykresleni mit stejne velky
# pixel - jinak jedna prisera cte jako jemnejsi kresba nez svet, ve kterem stoji.
TARGET_SCREEN_PIXEL = game_raster.SCALE

# Kolik barev je jeste v poradku.
#
# Rozpocet se odviji od MNOZSTVI ARTU (neprusvitnych pixelu), ne od velikosti platna.
# Prvni verze pocitala z delsi strany a oznacila high_ground_atlas.png za chybu: je to
# 192x576, tedy "velky obrazek", ale je v nem patnact dlazdic, ktere spolu paletu sdileji.
# 81 barev je tam v poradku.
#
# PREPOCITANO PROTI LATCE. Do teto chvile to bylo `12 + sqrt(plocha) * 0.35`, cili
# krivka odvozena z uvahy, ne z dat -- a uvaha byla spatne. Zmereno na 1623 originalech
# z PixelLabu (build/pixellab), coz je latka, kterou jsme si sami zvolili:
#
#   pasmo    ks    med. plocha   med. barev   p90 barev   stary rozpocet
#   32-47     39       234           44           52            17
#   48-79   1022      1414           38           53            25
#   80+      562      1776           45           56            26
#
# Dve veci z toho plynou:
#   1. Pocet barev na LATCE skoro NEZAVISI na velikosti spritu -- 38 az 45 napric
#      vsemi pasmy. Odmocninova krivka tedy nesedi na nic; spravny tvar je plochy.
#   2. Stary rozpocet byl pod latkou 1,5x (median pomeru skutecnost/rozpocet 1,54,
#      p90 2,21) a 88 % originalu z PixelLabu by neproslo. Kontrola tedy netrestala
#      sum, ale BOHATOST -- a tim tlacila vlastni art k plochosti.
#
# Prah je nastaveny na p90 latky, ne na jeji median: kontrola ma hlasit, co je
# neobvykle i na latce, ne vsechno barevne. Pri 56 propadne asi desetina originalu,
# coz je presne ta desetina, kterou chceme videt.
#
# Pod 120 pixelu artu latka MLCI -- v celych 1623 originalech neni jediny sprite pod
# 32 px, takze pro dlazdice zadna data nemame. Cislo 24 je proto vedomy odhad, ne
# mereni, a je oznaceny jako takovy. Az budou dlazdice v PixelLabu, premeri se.
PALETTE_BUDGET_SMALL = 24     # ODHAD (latka nema data pod 32 px)
PALETTE_BUDGET = 56           # p90 latky, zmereno


def palette_budget(opaque_px):
    return PALETTE_BUDGET_SMALL if opaque_px < 120 else PALETTE_BUDGET


ERROR, WARN, INFO = "CHYBA", "VAROVANI", "INFO"
ORDER = {ERROR: 0, WARN: 1, INFO: 2}


class Report:
    def __init__(self):
        self.items = []

    def add(self, sev, cat, subject, code, msg, thumb=None):
        self.items.append({"sev": sev, "cat": cat, "subject": subject,
                           "code": code, "msg": msg, "thumb": thumb})

    def count(self, sev):
        return sum(1 for i in self.items if i["sev"] == sev)


# ------------------------------------------------------------------ nacitani dat


def _read_tres(folder):
    """(id, text) pro kazdy .tres ve slozce.

    ID se bere z radku `id = &"..."`, a kdyz chybi, z NAZVU SOUBORU. To neni pojistka:
    Godot neuklada vlastnost, ktera se rovna vychozi hodnote skriptu, takze
    notification.tres radek `id` vubec nema — vychozi hodnota v distraction_data.gd je
    prave &"notification". Bez tehle zalohy vypadalo 36 zivych PNG jako osirelych."""
    d = os.path.join(DATA, folder)
    if not os.path.isdir(d):
        return
    for f in sorted(os.listdir(d)):
        if not f.endswith(".tres"):
            continue
        try:
            with open(os.path.join(d, f), encoding="utf-8", errors="ignore") as fh:
                text = fh.read()
        except OSError:
            continue
        m = ID_RE.search(text)
        yield (m.group(1) if m else f[:-5]), text


def live_ids(folder):
    """ID z data/<folder>/*.tres - to jsou ta, ktera hra opravdu naklada."""
    return {i for i, _ in _read_tres(folder)}


def habit_roots():
    """id -> koren upgradovaci linie, stejne jako Data.habit_family().

    Tier-2 navyk bez vlastniho artu dedi hlavu po koreni sve linie (mindfulness_2 ->
    mindfulness). Bez tehle mapy by linter hlasil 'chybi art' u peti navyku, kterym
    art chybet MA — a hlaseni, ktere kricí na spravny stav, se prestane cist."""
    parent, ids = {}, set()
    for me, text in _read_tres("habits"):
        ids.add(me)
        # Radek zni `upgrades = Array[StringName]([&"mindfulness_2"])`. Cte se obsah
        # KULATE zavorky — hledat prvni hranatou znamena chytit "[StringName]".
        u = re.search(r"^upgrades\s*=.*?\((.*?)\)\s*$", text, re.M)
        if u:
            for child in re.findall(r'&?"([^"]+)"', u.group(1)):
                parent[child] = me
    roots = {}
    for i in ids:
        r = i
        seen = {r}
        while r in parent and parent[r] not in seen:
            r = parent[r]
            seen.add(r)
        roots[i] = r
    return roots


def load_tuning():
    """Posuny z data/anim_tuning.tres jako {klic: [(dx, dy), ...]}.

    Bez tohohle by linter nikdy nezezelenal. Zarovnani pohledu NESAHA na PNG — zapisuje
    se do dat a hra podle nich kresli. Kontrola mericí syrove obrazky by proto hlasila
    tychz 13 vad i po tom, co je Animation Lab spravil, a report by prestal cokoli
    znamenat. Merí se tedy to, co hrac VIDI: pixely plus posun."""
    out = {}
    path = os.path.join(DATA, "anim_tuning.tres")
    if not os.path.exists(path):
        return out
    try:
        with open(path, encoding="utf-8", errors="ignore") as fh:
            text = fh.read()
    except OSError:
        return out
    m = re.search(r"^offsets\s*=\s*\{(.*?)^\}", text, re.M | re.S)
    if not m:
        return out
    for key, body in re.findall(r'"([^"]+)"\s*:\s*\[(.*?)\]', m.group(1), re.S):
        out[key] = [(int(x), int(y))
                    for x, y in re.findall(r"Vector2i\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)", body)]
    return out


TUNING = {}


def load_rgba(path):
    return np.array(Image.open(path).convert("RGBA"))


# ------------------------------------------------------------------ mereni


def block_size(a):
    """Skutecna velikost logickeho pixelu: nejvetsi N, pri kterem je obraz po NxN blocich
    konstantni. Kdyz je 3, byl obrazek nakresleny mensi a nafouknuty - a jeho skutecne
    rozliseni je tretinove, coz meni vsechny ostatni uvahy o velikosti."""
    h, w = a.shape[:2]
    for n in (8, 6, 5, 4, 3, 2):
        if h % n or w % n:
            continue
        b = a.reshape(h // n, n, w // n, n, 4)
        if np.all(b == b[:, :1, :, :1]):
            return n
    return 1


def isolated_ratio(a):
    """Podil neprusvitnych pixelu, ktere nemaji ani jednoho ze 4 sousedu stejne barvy.
    Zbytek po zmenseni renderu; rucne kresleny art ma souvisle plochy."""
    rgb, al = a[..., :3], a[..., 3] > 32
    if not al.any():
        return 0.0
    h, w = al.shape
    same = np.zeros((h, w), bool)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ys, xs = slice(max(0, dy), h + min(0, dy)), slice(max(0, dx), w + min(0, dx))
        yd, xd = slice(max(0, -dy), h + min(0, -dy)), slice(max(0, -dx), w + min(0, -dx))
        sh = np.zeros((h, w), bool)
        sh[yd, xd] = (rgb[ys, xs] == rgb[yd, xd]).all(-1) & al[ys, xs]
        same |= sh
    return float((al & ~same).sum()) / float(al.sum())


def silhouette(a):
    """(spodni hrana, teziste X, sirka, vyska) siluety, nebo None u prazdneho obrazku."""
    al = a[..., 3] > 32
    ys, xs = np.nonzero(al)
    if len(ys) == 0:
        return None
    return int(ys.max()), float(xs.mean()), int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)


# ------------------------------------------------------------------ kategorie
#
# Kazda kategorie vi, jak se v ni jmenuji soubory a odkud se berou ziva ID. Diky tomu
# umi nastroj rozlisit "tenhle soubor je ve hre" od "tenhle soubor tu jen lezi".

DISTRACTION_SUFFIXES = ("_north", "_east", "_west", "_attack", "_death")
VARIANTS = ("_b", "_c", "_d", "_e", "_f")

# Obranci maji jine pojmenovani sad nez prisery: <klic>_<sada>_frame_N, kde sady jsou
# vyjmenovane v defender_unit.gd (_ANIM_SETS). Bez tohohle vyctu vypadalo vsech 162
# souboru jako osirelych, protoze "_attack" neni ani smer ani varianta.
DEFENDER_SUFFIXES = ("_idle", "_walk_south", "_walk_north", "_walk_east",
                     "_attack", "_hurt", "_death")


def split_family(stem, ids, suffixes=(), variants=()):
    """Rozlozi jmeno souboru na (rodina, animace).

    Jmeno ma tvar <id><varianta><smer_nebo_animace>. Rodina se hleda jako NEJDELSI zive
    ID, ktere je predponou — tim se `zen_pulsar_2a` nesplete se `zen_pulsar`.

    POZOR NA PORADI: pripona smeru se odlupuje ZEZADU a DRIV nez varianta. Opacne to
    nefunguje, protoze `_east` zacina na `_e` a `_death` na `_d`, coz jsou obojí platne
    varianty — `group_chat_east` se pak rozpadne na variantu `_e` plus nesmysl `ast` a
    cely soubor spadne mezi osirele. Presne pred timhle varuje komentar v
    distraction_animator.gd („`_e` by bylo k nerozeznani od pate varianty")."""
    best = None
    for i in ids:
        if stem == i or stem.startswith(i):
            if best is None or len(i) > len(best):
                best = i
    if best is None:
        return None, None
    rest = stem[len(best):]

    anim = ""
    for s in sorted((s for s in suffixes if s), key=len, reverse=True):
        if rest.endswith(s):
            anim, rest = s, rest[: -len(s)]
            break

    if rest and rest not in variants:
        return None, None
    return best + rest, anim


def _is_live(rel, live):
    """live=None znamena 'celou slozku hra prochazi' (decor). Jinak je to vycet jmen;
    polozka koncici lomitkem znamena celý podadresář."""
    if live is None:
        return True
    if rel in live:
        return True
    return any(rel.startswith(d) for d in live if d.endswith("/"))


def scan_category(name, folder, ids, kind, rep, target_files, live=None):
    """Projde jednu kategorii: roztridi soubory na zive a osirele, zmeri je a naplni report.
    Vraci {rodina: {animace: [(cesta, cislo_framu)]}} pro zive soubory."""
    d = os.path.join(ASSETS, folder)
    if not os.path.isdir(d):
        return {}
    fams = defaultdict(lambda: defaultdict(list))
    singles = []
    files = []
    for root, _, names in os.walk(d):
        for f in sorted(names):
            if f.endswith(".png"):
                rel = os.path.relpath(os.path.join(root, f), d).replace("\\", "/")
                files.append((rel, f))
    for rel, f in sorted(files):
        p = os.path.join(d, rel.replace("/", os.sep))
        target_files.add(p)
        if kind == "plain" and not _is_live(rel, live):
            rep.add(INFO, name, os.path.relpath(p, PROJ), "osirely",
                    "hra na tenhle soubor nikde neodkazuje", p)
            continue
        m = FRAME_RE.match(f)
        stem = m.group(1) if m else f[:-4]
        num = int(m.group(2)) if m else 0

        if kind == "distraction":
            fam, anim = split_family(stem, ids, DISTRACTION_SUFFIXES + ("",), VARIANTS)
        elif kind == "tower":
            if stem == "tower_base":
                singles.append((p, stem))
                continue
            if not stem.startswith("head_"):
                fam, anim = None, None
            else:
                fam, anim = split_family(stem[5:], ids, (), ())
        elif kind == "defender":
            fam, anim = split_family(stem, ids, DEFENDER_SUFFIXES, ())
        else:                                   # kategorie bez ID - vse je zive
            singles.append((p, stem))
            continue

        if fam is None:
            rep.add(INFO, name, os.path.relpath(p, PROJ), "osirely",
                    "zadne zive ID neodpovida tomuhle jmenu — hra to nekresli", p)
            continue
        fams[fam][anim].append((p, num))

    for p, stem in singles:
        fams[stem][""].append((p, 0))
    for fam in fams.values():
        for k in fam:
            fam[k].sort(key=lambda t: t[1])
    return fams


# ------------------------------------------------------------------ kontroly


def check_file(path, rep, cat):
    """Kontroly, ktere se daji udelat na jednom obrazku."""
    try:
        a = load_rgba(path)
    except Exception as e:
        rep.add(ERROR, cat, os.path.relpath(path, PROJ), "necitelny", f"nejde otevrit: {e}")
        return None
    rel = os.path.relpath(path, PROJ)
    h, w = a.shape[:2]
    al = a[..., 3]

    if not (al > 32).any():
        rep.add(ERROR, cat, rel, "prazdny", "obrazek je celý průhledný")
        return a

    soft = int(((al > 0) & (al < 255)).sum())
    if soft:
        rep.add(ERROR, cat, rel, "mekka_alfa",
                f"{soft} poloprůhledných pixelů — v pixel artu má být alfa 0 nebo 255", path)

    opaque = int((al > 32).sum())
    cols = len({tuple(c) for c in a[..., :3][al > 32]})
    budget = palette_budget(opaque)
    if cols > budget:
        sev = ERROR if cols > budget * 2.5 else WARN
        rep.add(sev, cat, rel, "paleta",
                f"{cols} barev na {w}×{h} (rozpočet {budget})", path)

    iso = isolated_ratio(a)
    if iso > 0.30:
        rep.add(WARN, cat, rel, "sum",
                f"{iso * 100:.0f} % pixelů nemá souseda stejné barvy "
                f"(zbytek po zmenšení renderu)", path)

    bs = block_size(a)
    if bs > 1:
        rep.add(INFO, cat, rel, "nafouknuty",
                f"logický pixel je {bs}× — skutečné rozlišení je {w // bs}×{h // bs}", path)
    return a


def check_family(cat, fam, anims, rep, ref_anim="", facings=True):
    """Kontroly napric framy a smery jedne rodiny. Tady bydli 'pohledy k sobe nesedi'."""
    stats = {}
    for anim, files in anims.items():
        offs = TUNING.get(f"{fam}{anim}", [])
        bases, cxs = [], []
        for idx, (p, _) in enumerate(files):
            try:
                s = silhouette(load_rgba(p))
            except Exception:
                continue
            if s:
                ox, oy = offs[idx] if idx < len(offs) else (0, 0)
                bases.append(s[0] + oy)
                cxs.append(s[1] + ox)
        if bases:
            # Median, ne prvni frame — shodne s tim, co pocita Animation Lab. Prvni frame
            # je libovolny okamzik cyklu, takze u houpajici se chuze by referencni vyska
            # zavisela na tom, ve ktere uvrati animace zrovna zacina.
            ref = sorted(bases)[len(bases) // 2]
            stats[anim] = {"n": len(files), "base": ref,
                           "wob": max(bases) - min(bases),
                           "drift": max(cxs) - min(cxs)}

    for anim, st in sorted(stats.items()):
        label = f"{fam}{anim}"
        if st["wob"] >= 3:
            rep.add(WARN, cat, label, "kmitani",
                    f"spodní hrana skáče o {st['wob']} px v rámci cyklu")
        if st["drift"] >= 2.0:
            rep.add(WARN, cat, label, "ujizdeni",
                    f"těžiště ujíždí o {st['drift']:.1f} px do strany")

    if ref_anim in stats:
        ref = stats[ref_anim]
        for anim, st in sorted(stats.items()):
            if anim == ref_anim:
                continue
            d = st["base"] - ref["base"]
            if abs(d) >= 2:
                rep.add(WARN, cat, f"{fam}{anim}", "pohled_jinde",
                        f"stojí o {d:+d} px jinde než {fam or 'základní sada'} "
                        f"— při otočení se propadne")
        if not facings:
            return
        walks = {a: s for a, s in stats.items()
                 if a in ("", "_north", "_east", "_west",
                          "_walk_south", "_walk_north", "_walk_east")}
        counts = {s["n"] for s in walks.values()}
        if len(counts) > 1:
            rep.add(ERROR, cat, fam, "pocet_framu",
                    "směry mají různý počet framů: "
                    + ", ".join(f"{a or 'south'}={s['n']}" for a, s in sorted(walks.items())))
        for want in (("_walk_north", "_walk_east") if ref_anim == "_walk_south"
                     else ("_north", "_east")):
            if ref_anim in stats and want not in stats:
                rep.add(INFO, cat, fam, "chybi_smer",
                        f"nemá sadu {want.strip('_')} — hra použije south")


def check_sizes(cat, fams, rep):
    """Ruzne zdrojove velikosti v jedne kategorii znamenaji ruzne velky pixel na obrazovce."""
    sizes = Counter()
    for anims in fams.values():
        for files in anims.values():
            for p, _ in files:
                try:
                    with Image.open(p) as im:
                        sizes[im.size] += 1
                except Exception:
                    pass
    if len(sizes) > 1:
        rep.add(INFO, cat, cat, "rozmery",
                "více zdrojových velikostí: "
                + ", ".join(f"{w}×{h} ({n}×)" for (w, h), n in sizes.most_common()))


def check_missing(cat, ids, fams, rep, fallback=None):
    """fallback: id -> jine id, ze ktereho se art dedi (upgradovaci linie u veží)."""
    for i in sorted(ids):
        if any(f == i or f.startswith(i) for f in fams):
            continue
        alt = (fallback or {}).get(i)
        if alt and alt != i and any(f == alt or f.startswith(alt) for f in fams):
            continue
        rep.add(ERROR, cat, i, "chybi_art", "žádný PNG pro živé ID z data/")


# ------------------------------------------------------------------ opravy


def fix_soft_alpha(paths):
    """Jediná oprava, u ktere neni co rozhodovat: alfa patri na 0 nebo 255.
    Vse ostatni (paleta, velikost) je volba, a ta do linteru nepatri."""
    n = 0
    for p in paths:
        try:
            a = load_rgba(p)
        except Exception:
            continue
        al = a[..., 3]
        if not ((al > 0) & (al < 255)).any():
            continue
        a[..., 3] = np.where(al >= 128, 255, 0).astype(np.uint8)
        Image.fromarray(a, "RGBA").save(p)
        n += 1
    return n


# ------------------------------------------------------------------ vystup

HTML_HEAD = """<!doctype html><meta charset="utf-8"><title>Kontrola artu</title>
<style>
 body{background:#16151c;color:#d8d8e0;font:13px/1.5 system-ui,sans-serif;margin:24px}
 h1{font-size:20px;margin:0 0 4px} .sub{color:#8b8b99;margin-bottom:20px}
 .tot{display:flex;gap:10px;margin-bottom:22px;flex-wrap:wrap}
 .tot div{padding:8px 14px;border-radius:6px;background:#20202a}
 .CHYBA{border-left:3px solid #ff6b5e} .VAROVANI{border-left:3px solid #ffb648}
 .INFO{border-left:3px solid #5aa9e6}
 table{border-collapse:collapse;width:100%;margin-bottom:26px}
 td,th{padding:5px 9px;border-bottom:1px solid #262633;text-align:left;vertical-align:middle}
 th{color:#8b8b99;font-weight:500;font-size:11px;text-transform:uppercase}
 img{image-rendering:pixelated;height:40px;background:#0d0d12;border-radius:3px}
 .sev{font-size:11px;font-weight:600;padding:2px 6px;border-radius:3px;white-space:nowrap}
 .s-CHYBA{background:#4a1f1c;color:#ff8b7e} .s-VAROVANI{background:#4a3a1c;color:#ffcb78}
 .s-INFO{background:#1c3247;color:#8ac5f0}
 code{color:#c8c8d4;font-size:12px} .code{color:#8b8b99;font-size:11px}
 h2{font-size:15px;margin:26px 0 8px;color:#b8b8c6}
</style>
"""


def write_html(rep, checked):
    os.makedirs(os.path.dirname(REPORT), exist_ok=True)
    base = os.path.dirname(REPORT)
    rows = sorted(rep.items, key=lambda i: (ORDER[i["sev"]], i["cat"], i["code"], i["subject"]))
    out = [HTML_HEAD, "<h1>Kontrola artu</h1>",
           f'<div class="sub">{checked} souborů zkontrolováno</div>', '<div class="tot">']
    for sev in (ERROR, WARN, INFO):
        out.append(f'<div class="{sev}"><b>{rep.count(sev)}</b> {sev.lower()}</div>')
    out.append("</div>")

    by_cat = defaultdict(list)
    for r in rows:
        by_cat[r["cat"]].append(r)
    for cat in sorted(by_cat):
        out.append(f"<h2>{cat}</h2><table><tr><th></th><th>závažnost</th><th>co</th>"
                   "<th>kde</th><th>popis</th></tr>")
        for r in by_cat[cat]:
            th = ""
            if r["thumb"]:
                rel = os.path.relpath(r["thumb"], base).replace("\\", "/")
                th = f'<img src="{rel}">'
            out.append(f'<tr><td>{th}</td><td><span class="sev s-{r["sev"]}">{r["sev"]}</span>'
                       f'</td><td class="code">{r["code"]}</td><td><code>{r["subject"]}</code>'
                       f'</td><td>{r["msg"]}</td></tr>')
        out.append("</table>")
    with open(REPORT, "w", encoding="utf-8") as f:
        f.write("\n".join(out))


# ------------------------------------------------------------------ main


def main():
    ap = argparse.ArgumentParser(description="Kontrola herního artu.")
    ap.add_argument("--only", help="jen kategorie obsahující tenhle řetězec")
    ap.add_argument("--fix", action="store_true", help="oprav poloprůhledné okraje")
    ap.add_argument("--quiet", action="store_true", help="jen souhrn")
    args = ap.parse_args()

    global TUNING
    TUNING = load_tuning()
    rep = Report()
    seen = set()

    # Posledni polozka je vycet ZIVYCH souboru u kategorii, ktere nemaji ID v data/.
    # None = hra prochazi celou slozku (decor). Odvozeno z cest v scripts/*.gd.
    cats = [
        ("distractions", "distractions", live_ids("distractions"), "distraction", "", None),
        ("towers", "towers", live_ids("habits"), "tower", "", None),
        ("defenders", "defenders", live_ids("defenders"), "defender", "_walk_south", None),
        ("decor", "decor", set(), "plain", None, None),
        ("markers", "markers", set(), "plain", None,
         {"spawn_portal.png", "goal_core.png"}),
        ("terrain", "terrain", set(), "plain", None,
         {"high_ground_atlas.png", "path/", "face/"}),
    ]
    roots = habit_roots()

    all_fams = {}
    for name, folder, ids, kind, ref, live in cats:
        if args.only and args.only not in name:
            continue
        fams = scan_category(name, folder, ids, kind, rep, seen, live)
        all_fams[name] = fams
        if ids:
            check_missing(name, ids, fams, rep, roots if name == "towers" else None)
        check_sizes(name, fams, rep)
        for fam, anims in sorted(fams.items()):
            for anim, files in sorted(anims.items()):
                for p, _ in files:
                    check_file(p, rep, name)
            if ref is not None:
                # Vez nema smerove sady — hlava se otaci na GPU (tower.gd ART_FACING),
                # takze "chybi sever" by u ni byla vytka k neexistujicimu problemu.
                check_family(name, fam, anims, rep, ref,
                             facings=(name in ("distractions", "defenders")))

    # Osirele soubory se na kvalitu nekontroluji - viz hlavicka.
    orphans = {i["subject"] for i in rep.items if i["code"] == "osirely"}
    rep.items = [i for i in rep.items
                 if i["code"] == "osirely" or i["subject"] not in orphans]

    checked = len(seen)
    write_html(rep, checked)

    if args.fix:
        paths = [os.path.join(PROJ, i["subject"]) for i in rep.items if i["code"] == "mekka_alfa"]
        n = fix_soft_alpha(paths)
        print(f"opraveno poloprůhledných okrajů: {n} souborů")
        if n:
            print("spusť znovu bez --fix, ať se report přepočítá")
        return

    print(f"zkontrolováno {checked} souborů\n")
    if not args.quiet:
        by = defaultdict(list)
        for i in rep.items:
            by[(i["sev"], i["cat"], i["code"])].append(i)
        for (sev, cat, code), items in sorted(by.items(),
                                              key=lambda kv: (ORDER[kv[0][0]], kv[0][1], kv[0][2])):
            head = f"  {sev:<9}{cat:<14}{code:<16}{len(items):>4}×"
            print(head)
            for i in items[:3]:
                print(f"      {i['subject']}: {i['msg']}")
            if len(items) > 3:
                print(f"      … a dalších {len(items) - 3}")
    print(f"\n  {rep.count(ERROR)} chyb, {rep.count(WARN)} varování, {rep.count(INFO)} info")
    print(f"  report: {os.path.relpath(REPORT, PROJ)}")
    sys.exit(1 if rep.count(ERROR) else 0)


if __name__ == "__main__":
    main()
