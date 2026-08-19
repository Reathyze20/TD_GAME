# Sprite Studio: prohlizec a generator artu v prohlizeci.
#
#   python tools/gen_ui.py            # nastartuje a otevre http://localhost:8777
#   python tools/gen_ui.py --port 9000 --no-open
#
# PROC PROHLIZEC A NE DALSI DOCK V GODOTU
#
# Animation Lab umi jednu vec dobre: ladit zarovnani proti tomu, jak to kresli hra. Na
# prohlizeni celeho artu je ale dock spatne misto — je uzky, neumi mrizku a generovat z
# nej nejde, protoze generator je Python. Prohlizec zvladne oboje a nic se neinstaluje.
#
# CO TO UMI
#
#   Hra        Vsechen art po rodinach. Klik na priseru -> jeji sady (south, north,
#              east, attack, death), kazda se prehrava, da se krokovat po framech a
#              zvetsit. Znamky a miry z art_check.py u kazdeho framu.
#   Generator  Prompt -> N kandidatu vedle sebe. Klik na kandidata -> detail s paletou a
#              merami. Odtud se da nainstalovat do hry.
#   PixelLab   Stazena knihovna (build/pixellab) jako REFERENCNI LATKA. Vlastni vytvory
#              a placena sluzba vedle sebe, ve stejnem meritku a se stejnymi merami —
#              jinak se "je to skoro ono" neda overit.
#   Iterace    V detailu: „Doladit promptem" udela z kandidata jeho DITE (img2img z jeho
#              vlastnich pixelu). Kdo z koho vznikl, drzi meta.json v „lineage" a v
#              detailu se to kresli jako proužek predku — bez nej je slozka po peti
#              krocich hromada spritu, o kterych nikdo nevi, ze spolu souvisi.
#   Animace    Chuze, idle nebo VLASTNI pozy z JEDNOHO kandidata: vsechny framy maji
#              stejneho rodice, takze konzistence neni odhad, ale konstrukce.
#   Rotace     8 smeru z jednoho kandidata, vedle sebe v mrizce. Tam se pozna, jestli je
#              to porad tentyz tvor, nebo osm pribuznych priser.
#
# TRI VECI, KTERE TENHLE SOUBOR ROZHODUJE (a proc prave tak)
#
# 1. NERADIT KANDIDATY PODLE ZNAMKY. score() trestá prekroceni rozpoctu palety tak tvrde,
#    ze pouhym pridanim barev spadla znamka z 8.1 na 3.4. Razeni podle ni tedy davalo
#    nahoru nejPLOSSI sprite — presny opak toho, co hledas. Vychozi poradi je proto poradi
#    vzniku; podle znamky se da seradit rucne a je to oznacene jako pomocna mira.
# 2. VELIKOST JE DVOJICE, ne cislo. Hra ma dlazdice 16x8 i bosse 64x64, takze rozliseni
#    prochazi gen_ref.parse_size a render se pocita z pomeru stran (gen_ref.render_size).
# 3. INSTALACE SE PTA. Sprite, jehoz strana neni nasobek 16 ani jeho delitel, rozbije
#    rastr (bunka = 48 px na obrazovce pri meritku x3, tedy 16 px artu). Takovy se
#    nenainstaluje potichu — rekne se to a rozhodne uzivatel.
#
# Zadny externi balicek: server je stdlib http.server, frontend je jeden HTML soubor bez
# CDN. Mereni a cisteni se importuji z art_check.py, gen.py, gen_ref.py a sprite_cleanup.py
# — ctvrta kopie tehle matematiky by se rozesla se zbytkem pipeline.
import argparse
import json
import os
import re
import sys
import threading
import time
import webbrowser
from collections import Counter, defaultdict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, quote, unquote, urlparse

import numpy as np
from PIL import Image

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import game_raster                                                      # noqa: E402
import gen_ref                                                          # noqa: E402
from art_check import (DISTRACTION_SUFFIXES, VARIANTS, isolated_ratio,  # noqa: E402
                       live_ids, palette_budget, split_family)
from sprite_cleanup import (CHROMA_WEIGHT, load_palette_file,           # noqa: E402
                            palette_error, remap, to_oklab)

GEN_DIR = os.path.join(PROJ, "build", "gen")
ART_DIR = os.path.join(PROJ, "assets", "distractions")
LIB_DIR = os.path.join(PROJ, "build", "pixellab")
MASTER_PAL = os.path.join(PROJ, "docs", "art", "palette_48.hex")

# Rastr hry se CTE ze scripts/data.gd, neopisuje se — viz game_raster.py. Drive tu stalo
# CELL=16, SCALE=3; data.gd se 17. 8. 2026 presunulo na 24/x2 a tenhle soubor o tom nevedel,
# takze brana schvalovala sprity podle rastru, ktery uz neplati.
CELL = game_raster.ART_PX
SCALE = game_raster.SCALE

# Vychozi sila LoRA pro posuvnik. Autoritou je gen.LORA_WEIGHT, jenze hlavicka se kresli
# driv, nez se generator vubec dotkne — tohle je jen cislo, na kterem posuvnik stoji, nez
# uzivatel neco posle.
DEFAULT_LORA = 0.55

# Poradi smeru pro ZOBRAZENI a pro poznani, ze soubor je rotace, ne kandidat. Autoritou
# pro generovani je gen.DIRECTIONS (rotate se vola s dirs=None, tedy at si vybere sam) —
# tenhle seznam existuje proto, aby sla mrizka nakreslit a soubory roztridit bez nacteni
# generatoru; /api/state se ptat modelu nesmi.
DIRS = ("south", "south-east", "east", "north-east",
        "north", "north-west", "west", "south-west")

# Generator se natahuje az pri prvnim pouziti — nacteni SDXL trva pul minuty a zabere
# 7 GB VRAM, coz je zbytecne, kdyz si jen prohlizis hotovy art.
_PIPE = None
_PIPE_W = None          # sila LoRA, se kterou je _PIPE postavena
_IMG2IMG = None
_INPAINT = None
_PIPE_LOCK = threading.Lock()
# "cand" nese jmeno spritu, ktery uloha vyrobila — dolaďovani jinak nema jak rict, na
# ktere dite se ma detail po dobehnuti prepnout.
JOB = {"state": "idle", "msg": "", "done": 0, "total": 0, "set": "", "cand": "",
       # URL rozpracovaneho obrazku (viz _write_preview). Prazdne = neni co ukazat;
       # prohlizec podle toho zivy pruh schovava, misto aby drzel starou fotku.
       "preview": ""}

# Rozpracovany obrazek lezi ve slozce sady, aby ho obslouzila tataz cesta jako
# kandidaty (/img/gen/<sada>/<soubor>) a nemusela vznikat druha. Podtrzitko na
# zacatku ho drzi mimo vypis: kandidati jsou "cand_*".
PREVIEW_NAME = "_preview.png"

FRAME_RE = re.compile(r"^(.*)_frame_(\d+)\.png$")
# id postavy z PixelLabu jde do sitoveho volani i do jmena slozky. Pousti se dal jen tvar
# uuid — jinak by "id" z pozadavku rozhodovalo, kam se na disk zapise.
UUID_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F-]{20,50}$")


# ------------------------------------------------------------------ mereni


def measure(path):
    try:
        a = np.array(Image.open(path).convert("RGBA"))
    except Exception:
        return None
    m = a[..., 3] > 32
    opaque = int(m.sum())
    h, w = a.shape[:2]
    grid, gnote = grid_check(w, h)
    if opaque == 0:
        return {"w": w, "h": h, "cols": 0, "iso": 0, "budget": 0, "pal": [],
                "grid": grid, "gridnote": gnote}
    cols = top_colors(a, m)
    return {"w": w, "h": h, "cols": len(cols),
            "iso": round(isolated_ratio(a) * 100), "budget": palette_budget(opaque),
            "pal": ["#%02x%02x%02x" % c for c, _ in cols[:24]],
            "grid": grid, "gridnote": gnote}


def top_colors(a, m):
    """Barvy od nejcastejsi — v detailu se z nich kresli paleta, takze poradi nese
    informaci: prvni je ta, ktere je na spritu nejvic."""
    return Counter(map(tuple, a[..., :3][m])).most_common()


def grid_side(n):
    return n > 0 and (n % CELL == 0 or CELL % n == 0)


def grid_check(w, h):
    """Sedi sprite na rastr hry? -> (ok, veta pro cloveka).

    Kontroluje se KAZDA strana zvlast, protoze 16x8 je platna dlazdice cesty, kdezto
    24x20 je preklep, ktery se ve hre projevi az jako o pixel posunuta vez."""
    bad = [f"{lbl} {n} px" for n, lbl in ((w, "šířka"), (h, "výška")) if not grid_side(n)]
    if not bad:
        return True, f"sedí na rastr (buňka = {CELL} px artu, ×{SCALE} na obrazovce)"
    return False, (" a ".join(bad) + f" — není násobek {CELL} ani jeho dělitel; "
                   f"buňka hry je {CELL} px artu (×{SCALE} na obrazovce)")


def size_info(spec, source="sdxl"):
    """Rozliseni z hlavicky -> co to znamena. Pocita Python, ne JavaScript: kdyby si
    prohlizec pomer stran a render dopocitaval sam, rozesel by se s tim, co se opravdu
    vygeneruje.

    A prave proto to musi vedet, KTERY generator se pta. Oba maji jinou cestu z platna
    na sprite (SDXL 1024 px a median, RD 512 px a k-centroid), takze jedno cislo pro
    oba by u jednoho z nich bylo tise spatne — a spatny udaj v hlavicce je horsi nez
    zadny, protoze podle nej clovek rozhoduje o velikosti."""
    try:
        w, h = gen_ref.parse_size(spec)
    except ValueError as e:
        return {"ok": False, "note": str(e)}
    grid, gnote = grid_check(w, h)

    if source == "rd":
        rw, rh, ps, _model = _rd().plan_size((w, h))
        ppsp = float(ps)
        note = f"{w}×{h} · plátno {rw}×{rh} · {ps} px na pixel spritu (k-centroid)"
    else:
        rw, rh = gen_ref.render_size(w, h)
        ppsp = gen_ref.px_per_sprite_pixel(w, h)
        note = f"{w}×{h} · render {rw}×{rh} · {ppsp:.0f} px zdroje na pixel spritu"
    if ppsp < 8:
        note += " — pod 8 mizí detail rychleji, než ho model stihne nakreslit"
    return {"ok": True, "w": w, "h": h, "rw": rw, "rh": rh, "ppsp": round(ppsp, 1),
            "note": note, "grid": grid, "gridnote": gnote}


# ------------------------------------------------------------------ sken


def scan_art():
    """assets/distractions -> [{id, sets:{suffix:[soubory]}}] ve stejnem cleneni,
    jake pouziva hra i Animation Lab."""
    ids = live_ids("distractions")
    fams = defaultdict(lambda: defaultdict(list))
    if not os.path.isdir(ART_DIR):
        return []
    for f in sorted(os.listdir(ART_DIR)):
        m = FRAME_RE.match(f)
        if not m:
            continue
        fam, anim = split_family(m.group(1), ids, DISTRACTION_SUFFIXES + ("",), VARIANTS)
        if fam is None:
            continue
        fams[fam][anim].append((int(m.group(2)), f))
    out = []
    for fam in sorted(fams):
        sets = {}
        for anim, lst in fams[fam].items():
            sets[(anim or "south").lstrip("_")] = [f for _, f in sorted(lst)]
        out.append({"id": fam, "sets": sets})
    return out


def read_meta(d):
    """meta.json sady se zpetnou kompatibilitou.

    Sady vygenerovane driv nemaji „lineage", „anims" ani „dirs" a nikdy je mit nebudou —
    cteni proto musi projit i bez nich. Kdyby se na ne spolehalo, prvni spusteni nove
    verze by rozbilo prohlizeni vseho, co uz na disku je. Chybejici klice se doplni
    prazdne, takze zbytek kodu uz muze psat meta["lineage"][x] bez zjistovani, jak stara
    sada to je."""
    meta = {}
    p = os.path.join(d, "meta.json")
    if os.path.exists(p):
        try:
            meta = json.load(open(p, encoding="utf-8"))
        except Exception:
            meta = {}
    if not isinstance(meta, dict):
        meta = {}
    meta["prompt"] = meta.get("prompt") or ""
    for k in ("scores", "lineage", "anims", "dirs", "gen"):
        if not isinstance(meta.get(k), dict):
            meta[k] = {}
    return meta


def write_meta(d, meta):
    json.dump(meta, open(os.path.join(d, "meta.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)


def is_rotation(fn, rotfiles):
    """Je tenhle soubor rotace, a ne kandidat?

    Prvni odpoved je meta.json (tam se rotace zapisuji pri vzniku), druha je jmeno. Sama
    meta by nestacila: kdo si soubor zkopiruje rucne, dostal by cand_03_east.png mezi
    kandidaty jako devatou „novou priseru"."""
    if fn in rotfiles:
        return True
    return any(fn.endswith("_" + d + ".png") for d in DIRS)


def scan_gen():
    out = []
    if not os.path.isdir(GEN_DIR):
        return out
    for d in sorted(os.listdir(GEN_DIR)):
        p = os.path.join(GEN_DIR, d)
        if not os.path.isdir(p):
            continue
        meta = read_meta(p)
        rotfiles = {f for m in meta["dirs"].values() for f in m.values()}
        # Framy animace se jmenuji cand_03_walk_frame_1.png a rotace cand_03_east.png,
        # takze by jinak vlezly do mrizky kandidatu jako dalsi sprity — a osm framu chuze
        # by vypadalo jako osm novych priser. Do mrizky patri jen ten jeden sprite, ze
        # ktereho vznikly.
        cands = sorted(f for f in os.listdir(p)
                       if f.startswith("cand_") and "_frame_" not in f
                       and not is_rotation(f, rotfiles))
        out.append({"name": d, "cands": cands, "prompt": meta["prompt"],
                    "scores": meta["scores"], "lineage": meta["lineage"],
                    "anims": meta["anims"], "dirs": meta["dirs"], "gen": meta["gen"]})
    return out


# ------------------------------------------------------------------ knihovna PixelLabu


def scan_lib():
    """build/pixellab -> [{slug, name, id, size, dirs, thumb, groups}]

    character.json nemusi existovat — slozky stazene rucne driv (`boss`, `pixellab_boss`)
    ho nemaji. Jmeno ma proto zalohu ve jmenu slozky; jinak by referencni knihovna tise
    zapomnela prave ty postavy, ktere v projektu lezi nejdyl."""
    out = []
    if not os.path.isdir(LIB_DIR):
        return out
    for d in sorted(os.listdir(LIB_DIR)):
        p = os.path.join(LIB_DIR, d)
        if not os.path.isdir(p):
            continue
        info = {}
        cj = os.path.join(p, "character.json")
        if os.path.isfile(cj):
            try:
                info = json.load(open(cj, encoding="utf-8"))
            except Exception:
                info = {}
        if not isinstance(info, dict):
            info = {}
        groups = sorted(x for x in os.listdir(p) if os.path.isdir(os.path.join(p, x)))
        out.append({"slug": d, "name": str(info.get("name") or d)[:90],
                    "id": str(info.get("id") or "")[:64],
                    "size": str(info.get("size") or "")[:16],
                    "dirs": str(info.get("dirs") or "")[:16],
                    "thumb": lib_thumb(p, groups),
                    "groups": [g for g in groups if g != "rotace"]})
    return out


def lib_thumb(p, groups):
    """Nahled postavy: south z rotaci, jinak cokoliv. Jizni pohled zamerne — v mrizce se
    postavy porovnavaji mezi sebou a osm ruznych uhlu se porovnat neda."""
    for g in ["rotace"] + list(groups):
        gd = os.path.join(p, g)
        if not os.path.isdir(gd):
            continue
        files = sorted(f for f in os.listdir(gd) if f.lower().endswith(".png"))
        if not files:
            continue
        pref = [f for f in files if f.startswith("south")]
        return f"{g}/{(pref or files)[0]}"
    return ""


def lib_detail(slug):
    """Jedna postava -> {rot: {smer: soubor}, anims: {animace: {smer: [framy]}}}"""
    d = os.path.join(LIB_DIR, os.path.basename(slug))
    if not os.path.isdir(d):
        return {"err": "neznámá postava"}
    rot, anims = {}, {}
    for g in sorted(os.listdir(d)):
        gd = os.path.join(d, g)
        if not os.path.isdir(gd):
            continue
        files = sorted(f for f in os.listdir(gd) if f.lower().endswith(".png"))
        if g == "rotace":
            for f in files:
                rot[f[:-4]] = f"{g}/{f}"
            continue
        by = defaultdict(list)
        for f in files:
            m = FRAME_RE.match(f)
            # Radit podle jmena znamena frame_10 pred frame_2 — a to uz neni chuze, ale
            # skubani. Cislo se proto tahá z nazvu a radi se cislem.
            by[m.group(1) if m else f[:-4]].append((int(m.group(2)) if m else 0, f"{g}/{f}"))
        anims[g] = {k: [x for _, x in sorted(v)] for k, v in sorted(by.items())}
    return {"slug": os.path.basename(slug), "rot": rot, "anims": anims}


# Seznam postav na serveru PixelLabu. Drzi se v pameti, protoze jedno vypsani je nekolik
# sitovych volani (strankuje se po deseti) — a mezi „nacti seznam" a „stahni tuhle" musi
# byt jmeno postavy porad k dispozici, jinak se slozka pojmenuje jen podle id.
_REMOTE = {"rows": [], "t": 0.0, "err": ""}


def run_remote_list():
    import pixellab
    try:
        c = pixellab.Client()
        JOB.update(state="running", msg="ptám se PixelLabu…", done=0, total=0)
        rows = pixellab.all_characters(c)
        _REMOTE.update(rows=rows, t=time.time(), err="")
        JOB.update(state="done", msg=f"na serveru je {len(rows)} postav")
    except SystemExit as e:
        # pixellab.py hlasi chybejici token a HTTP chyby pres SystemExit, a to NENI
        # potomek Exception — bez tehle vetve by vlakno tise umrelo a UI cekalo navzdy.
        _REMOTE["err"] = str(e)
        JOB.update(state="error", msg=str(e))
    except Exception as e:
        _REMOTE["err"] = f"{type(e).__name__}: {e}"
        JOB.update(state="error", msg=_REMOTE["err"])


def run_pull(cid):
    """Stazeni jedne postavy do build/pixellab/. pixellab.py se pouziva jako MODUL —
    subprocess by znamenal druhy interpret, druhe cteni tokenu a chybu jen na stdoutu."""
    import pixellab
    try:
        row = next((r for r in _REMOTE["rows"] if r["id"] == cid), None)
        name = (row or {}).get("name") or "postava"
        slug = os.path.basename(pixellab.slug(name, cid))
        d = os.path.join(LIB_DIR, slug)
        JOB.update(state="running", msg=f"stahuji {name[:40]}…", done=0, total=1)
        c = pixellab.Client()
        args = argparse.Namespace(id=cid, out=d, anim=None, dir=None, quiet=True)
        pixellab.cmd_pull(c, args)
        if row:
            with open(os.path.join(d, "character.json"), "w", encoding="utf-8") as f:
                json.dump(row, f, ensure_ascii=False, indent=2)
        JOB.update(state="done", done=1, msg=f"staženo do build/pixellab/{slug}")
    except SystemExit as e:
        JOB.update(state="error", msg=str(e))
    except Exception as e:
        JOB.update(state="error", msg=f"{type(e).__name__}: {e}")


# ------------------------------------------------------------------ reference

# Prohledani assets/ a build/ je ~3400 souboru; delat to pri kazdem psani do vyhledavaciho
# policka by z UI udelalo diskovou zatez. Vysledek se proto drzi minutu — nove vygenerovany
# sprite se v nabidce objevi se zpozdenim, coz je levnejsi nez os.walk na kazdou klavesu.
_REFS = {"list": [], "t": 0.0}
REF_TTL = 60.0


def ref_index():
    if time.time() - _REFS["t"] < REF_TTL and _REFS["list"]:
        return _REFS["list"]
    found = []
    for root in gen_ref.REF_ROOTS:
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, files in os.walk(root):
            dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
            for f in sorted(files):
                if f.lower().endswith(".png"):
                    rel = os.path.relpath(os.path.join(dirpath, f), PROJ)
                    found.append(rel.replace("\\", "/"))
    _REFS.update(list=found, t=time.time())
    return found


def list_refs(q, limit=250):
    """Reference odpovidajici dotazu. Hleda se po SLOVECH kdekoliv v ceste, takze
    „energy east" najde assets/.../energy_drink_east_frame_1.png i bez presneho poradi."""
    terms = [t for t in (q or "").lower().split() if t]
    hits = [p for p in ref_index() if all(t in p.lower() for t in terms)]
    return {"total": len(hits), "items": hits[:limit]}


def ref_path(rel):
    """Relativni cesta z UI -> absolutni, nebo "" kdyz je mimo assets/ a build/.

    Dve zavory zamerne. Rucni kontrola komponent odmitne "..", absolutni cesty i
    "C:" driv, nez se cokoliv slozi; gen_ref.resolve_ref to pak overi jeste jednou pres
    realpath, cimz padne i pripad, kdy by symlink uvnitr assets/ ukazoval ven."""
    rel = (rel or "").replace("\\", "/").strip()
    if not rel:
        return ""
    parts = [x for x in rel.split("/") if x not in ("", ".")]
    if not parts or any(x == ".." or ":" in x for x in parts):
        return ""
    if parts[0] not in ("assets", "build"):
        return ""
    try:
        return gen_ref.resolve_ref("/".join(parts))
    except ValueError:
        return ""


# ------------------------------------------------------------------ roury


def text_pipe(w=None):
    """Textova roura pro danou silu LoRA.

    Sila se zapeka pri stavbe (gen.build_pipe(lora_weight=...)), takze jina sila znamena
    postavit rouru ZNOVU — a s ni zahodit img2img, ktera z ni vychazi. Uzivatel to musi
    poznat, proto se to hlasi jako „prestavuji"; posunuti posuvniku stoji stejne cekani
    jako prvni spusteni.

    w=None znamena „co je prave nactene". Doladovani, animace ani rotace na silu nesahaji
    schvalne: tahani za posuvnik v hlavicce by jinak uprostred iterovani shodilo model a
    dalsi krok rodokmenu by vznikl v jinem stylu nez predchozi."""
    global _PIPE, _PIPE_W, _IMG2IMG, _INPAINT
    import gen
    with _PIPE_LOCK:
        if w is None:
            w = _PIPE_W if _PIPE is not None else gen.LORA_WEIGHT
        w = round(float(w), 3)
        if _PIPE is not None and _PIPE_W == w:
            return _PIPE
        
        # Bleskove prenastaveni vahy bez znovu-nacitani 7 GB z disku:
        if _PIPE is not None:
            try:
                _PIPE.set_adapters([gen.LORA_ADAPTER], adapter_weights=[w])
                _PIPE_W = w
                _PIPE.lora_weight = w
                return _PIPE
            except Exception:
                pass

        JOB.update(state="running",
                   msg=("Načítám model z lokálního disku do paměti GPU…" if _PIPE is None
                        else f"Nastavuji LoRA váhu na {w}…"))
        _IMG2IMG = None
        _INPAINT = None
        _PIPE, _PIPE_W = None, None
        _PIPE = gen.build_pipe(lora_weight=w)
        _PIPE_W = w
    return _PIPE


def img2img():
    """Lazy img2img roura VEDLE textove, ne misto ni.

    Obe roury sdileji tytez vahy (gen.build_img2img), takze doladeni prvniho spritu
    nenacte model podruhe."""
    global _IMG2IMG
    import gen
    pipe = text_pipe(None)              # zamek si bere text_pipe sama
    with _PIPE_LOCK:
        if _IMG2IMG is None:
            JOB.update(state="running", msg="připravuji img2img…")
            _IMG2IMG = gen.build_img2img(pipe)
    return _IMG2IMG


def inpaint_pipe():
    """Lazy inpaint roura ze STEJNYCH vah jako textova roura."""
    global _INPAINT
    import gen
    pipe = text_pipe(None)
    with _PIPE_LOCK:
        if _INPAINT is None:
            JOB.update(state="running", msg="připravuji inpaint…")
            _INPAINT = gen.build_inpaint(pipe)
    return _INPAINT


def to_sprite(a, w, h):
    """Render -> sprite w×h, jedinym zmensenim rovnou na cilovy obdelnik.

    Drive se tu obdelnik odvozoval zmackem NEAREST ze ctverce o delsi strane, protoze
    puvodni docstring predpokladal, ze gen.py umí jen ctverec. Neumel to jen tenhle
    predpoklad: gen.downscale si velikost rozbaluje pres _pair(), takze (16, 8) bere
    nativne uz od zacatku. Objizdka tedy zahazovala kazdy druhy radek zbytecne — zmereno
    na dlazdici 16x8: osm plnych radku pres CLI proti ctyrem pres studio."""
    import gen
    return gen.downscale(a, (w, h))


def score_of(a, wh):
    """gen.score s CILOVOU velikosti jako dvojici (w, h) — stejny tvar, jaky vraci
    gen_ref.parse_size. Jedno misto proto, aby se pri zmene kontraktu opravovalo jednou."""
    import gen
    return gen.score(a, size=wh)


# ------------------------------------------------------------------ generovani


def safe_set(name):
    """Jmeno sady -> jmeno slozky. Slozka vznika z retezce z pozadavku, takze bez tehle
    filtrace by „../../assets/distractions" rozhodovalo, kam se zapisuji PNG."""
    s = "".join(ch if (ch.isalnum() or ch in "_-") else "_" for ch in (name or ""))
    return os.path.basename(s)[:40].strip("_") or "sada"


def run_generate(prompt, name, n, size, colors, steps, seed, lora,
                 ref="", ref_mode="zaklad", ref_strength=0.6):
    import gen
    try:
        w, h = gen_ref.parse_size(size)
        rw, rh = gen_ref.render_size(w, h)

        init, pal, ip, refnote = None, None, None, ""
        if ref:
            ra = gen_ref.load_ref(ref)          # sama si overi, ze lezi v assets/ nebo build/
            if ref_mode in ("zaklad", "oboji"):
                init = gen_ref.ref_init(ra, rw, rh, gen.MAGENTA)
            if ref_mode in ("paleta", "oboji"):
                pal = gen_ref.ref_palette(ra, colors)
            if ref_mode == "identita":
                # Posuvnik "sila reference" slouzi obema rezimum: u zakladu rika, kolik smi
                # model prepsat, u identity, jak silne ma referenci drzet. Je to tataz
                # otazka ("kolik z reference zustane"), jen jinym mechanismem — druhy
                # posuvnik by uzivatele nutil vedet, ktery z nich je zrovna aktivni.
                ip = gen_ref.ref_identity(ra, bg=gen.MAGENTA, neutral=gen.IP_NEUTRAL)
            refnote = gen_ref.describe(ref, ref_mode, colors)

        pipe = text_pipe(lora)
        if ip is not None:
            gen.load_ip_adapter(pipe, ref_strength)
        d = os.path.join(GEN_DIR, name)
        os.makedirs(d, exist_ok=True)
        JOB.update(state="running", msg="generuji", done=0, total=n, set=name, cand="")

        meta = read_meta(d)
        meta["prompt"] = prompt or meta["prompt"]
        meta["gen"] = {"size": f"{w}x{h}", "render": f"{rw}x{rh}", "lora": lora,
                       "colors": colors, "steps": steps, "seed": seed,
                       "ref": ref, "ref_mode": ref_mode if ref else "",
                       "ref_strength": ref_strength if (ref and (init is not None
                                                                or ip is not None)) else None}
        first = ""
        for i in range(n):
            imgs = gen.generate(pipe, prompt, 1, steps, seed + i, size=(rw, rh),
                                init=init, strength=ref_strength, ip_image=ip)
            a = gen.cut_background(imgs[0])
            a = gen.strip_shadow(a)
            # aspect POVINNE: bez nej se dlazdice 16x8 orizne do ctverce a pri zmenseni
            # svisle zmackne na polovinu. CLI ho predava, tahle cesta ho drive vynechavala.
            a = gen.crop_to_subject(a, aspect=w / float(h))
            a = to_sprite(a, w, h)
            a = gen.outline_sprite(a)
            if pal is not None:
                a = gen_ref.apply_palette(a, pal)
            a = gen.clean(a, colors)
            sc = score_of(a, (w, h))
            # Cislovani od toho, co uz na disku JE: druhe spusteni do teze sady nesmi
            # prepsat prvni kandidaty a s nimi cely jejich rodokmen.
            fn = next_cand(d)
            Image.fromarray(a, "RGBA").save(os.path.join(d, fn))
            meta["scores"][fn] = sc
            first = first or fn
            write_meta(d, meta)
            JOB.update(done=i + 1, cand=first,
                       msg=f"kandidát {i + 1}/{n} — známka {sc['grade']}")

        JOB.update(state="done", cand=first,
                   msg=f"hotovo — {n} kandidátů{(' · ' + refnote) if refnote else ''}")
    except Exception as e:
        JOB.update(state="error", msg=f"{type(e).__name__}: {e}")


# ------------------------------------------------------------------ Retro Diffusion


def _rd():
    """Klient k Retro Diffusion se importuje az pri pouziti.

    Tahne s sebou 'websockets', ktere nemusi byt nainstalovane, a hledani instalace
    saha na disk. Prohlizeni artu se to netyka, takze at to nezdrzuje start."""
    import retrodiffusion
    return retrodiffusion


def rd_status():
    """Stav Retro Diffusion pro hlavicku: je nainstalovany, bezi, jake ma LoRA.

    Vsechny tri odpovedi musi prijit RYCHLE — vola se to pri kazdem prekresleni
    hlavicky. Proto jen sonda na port (ne handshake) a vypis slozky, zadne
    nacitani modelu."""
    try:
        rd = _rd()
    except Exception as e:
        return {"ok": False, "running": False, "loras": [], "err": f"klient nejde načíst: {e}"}
    try:
        root = rd.find_rd_root()
        if root is None:
            return {"ok": False, "running": False, "loras": [],
                    "err": "instalaci jsem nenašel (Aseprite extension RetroDiffusionLite)"}
        loras = sorted(p.stem for p in rd.lora_dir().glob("*.pxlm")) if rd.lora_dir().is_dir() else []
        return {"ok": True, "running": rd.is_running(), "loras": loras,
                "version": rd.server_version(), "root": str(root), "err": ""}
    except Exception as e:
        return {"ok": False, "running": False, "loras": [], "err": f"{type(e).__name__}: {e}"}


def run_rd_start():
    try:
        rd = _rd()
        if rd.is_running():
            JOB.update(state="done", msg="Retro Diffusion už běží.")
            return
        JOB.update(state="running", total=0, done=0,
                   msg="Startuji Retro Diffusion — import knihoven a načtení modelu trvá minuty. "
                       "Průběh je v jeho vlastním okně konzole.")
        t0 = time.time()
        rd.start_server(quiet=True)
        JOB.update(state="done", msg=f"Retro Diffusion odpovídá (start trval {time.time() - t0:.0f} s).")
    except Exception as e:
        JOB.update(state="error", msg=f"{type(e).__name__}: {e}")


BATCH_RE = re.compile(r"batch\s+(\d+)\s*/\s*(\d+)")


def _write_preview(by_batch, w, h, d, setname, tick):
    """Rozpracovane obrazky -> jeden PNG proužek, na ktery se prohlizec smi ptat.

    CTYRI VECI, KTERE TADY MUSI SEDET:

    1. VELIKOST. Nahled ze serveru neni v rozliseni spritu. U pixel_size > 8 si ho
       fastRender() (image_server.py:597) zmensi na W//pixel_size, ale pak ho jeste
       zvetsi na hranu aspon 48 px, "aby ho Aseprite dekodoval rychle" -- takze
       32x32 sprite prijde jako 64x64 (overeno). U pixel_size <= 8 (boss 64x64) se
       nezmensuje vubec a prijde cele platno 512x512. Srovnavame to na CILOVOU
       velikost, aby nahled ukazoval to, co doopravdy vznikne, a ne mekci obrazek,
       ktery se pak "nevysvetlitelne" zmeni.
       U bosse to neni tentyz vypocet jako finalni: my bereme kazdy osmy pixel,
       server pousti k-centroid. Nahled proto bude zrnitejsi nez hotovy sprite.

    2. JEDEN OBRAZEK NA DAVKU, NE VSECHNY NARAZ. Server nepocita n kandidatu
       soubezne -- jede "batch 1/4", "batch 2/4" za sebou a v kazde zprave posila
       jen tu jednu rozpracovanou. Kdybychom kreslili jen prave prichozi, pruh by
       po kazdem kandidatovi zhasl a zacal od zacatku. Proto si drzime posledni
       snimek z KAZDE davky a kreslime je vedle sebe: vlevo hotove, vpravo ta,
       na ktere se prave pracuje.

    3. ZAPIS PRES DOCASNE JMENO. Prohlizec se pta kazdych 600 ms a klidne trefi
       okamzik, kdy je soubor rozepsany. os.replace je atomicky, takze precte bud
       cely stary, nebo cely novy -- nikdy pulku PNG. Format se PIL predava rucne;
       z pripony ".png.tmp" ho odvodit neumi a spadne na ValueError.

    4. NAVRATOVA HODNOTA NESE PORADOVE CISLO. Bez menici se query by prohlizec
       drzel prvni nahled z cache a zdalo by se, ze se generovani zaseklo.
    """
    tiles = []
    for _idx, a in sorted(by_batch.items()):
        im = Image.fromarray(np.asarray(a), "RGBA")
        if (im.width, im.height) != (w, h):
            im = im.resize((w, h), Image.NEAREST)
        tiles.append(im)
    if not tiles:
        return ""

    gap = 1
    sheet = Image.new("RGBA", (w * len(tiles) + gap * (len(tiles) - 1), h), (0, 0, 0, 0))
    for i, im in enumerate(tiles):
        sheet.paste(im, (i * (w + gap), 0))

    path = os.path.join(d, PREVIEW_NAME)
    tmp = path + ".tmp"
    sheet.save(tmp, format="PNG")
    os.replace(tmp, path)
    return f"/img/gen/{quote(setname)}/{PREVIEW_NAME}?t={tick}"


def run_generate_rd(prompt, name, n, size, colors, seed, quality, loras, negative=""):
    """Generovani pres Retro Diffusion do TYCHZ slozek jako lokalni SDXL.

    Zamerne to nema vlastni sekci v UI ani vlastni format meta.json. Kandidat z RD
    je obycejny kandidat: da se z nej delat dite (run_refine), animace, rotace i
    instalace, a rodokmen si sedne do stejneho retezu. Kdyby mel RD vlastni svet,
    kazda z tech funkci by potrebovala druhou variantu.

    ROZDIL PROTI run_generate JE V UKLIDU, NE V UKLADANI:
      SDXL kresli obrazek, KTERY VYPADA jako pixel art na platne 1024 px, takze po
      nem uklizime cely retez (cut_background -> strip_shadow -> crop -> median ->
      outline). RD pocita na platne 512 px, ale stahne si ho SAM k-centroidem na
      cilovy rastr a pozadi odmaze rembg segmentaci. Poustet na to jeste jednou
      nase zmensovani by znamenalo zmensovat uz zmensene.

    Co po nem ZBYVA udelat, je paleta. Merenim na prvnich vysledcich: sprite 32x32
    mel 263 barev na 288 neprusvitnych pixelech, cili skoro kazdy pixel vlastni
    odstin. To neni chyba RD — kcentroid michá barvy, kdyz zmensuje — ale do hry,
    kde je rozpocet palety mira kvality, to takhle nesmi. Proto gen.clean().
    """
    import gen
    try:
        rd = _rd()
        w, h = gen_ref.parse_size(size)

        if not rd.is_running():
            JOB.update(state="running", msg="Retro Diffusion neběží — startuji ho (trvá minuty)…")
            rd.start_server(quiet=True)

        d = os.path.join(GEN_DIR, name)
        os.makedirs(d, exist_ok=True)
        JOB.update(state="running", msg="generuji přes Retro Diffusion", done=0, total=n,
                   set=name, cand="")

        meta = read_meta(d)
        meta["prompt"] = prompt or meta["prompt"]
        meta["gen"] = {"source": "rd", "size": f"{w}x{h}", "colors": colors,
                       "quality": quality, "seed": seed, "loras": list(loras),
                       "negative": negative}

        tick = [0]
        by_batch = {}
        last_batch = [1]
        prev_err = []

        def progress(title, imgs):
            # Titulek serveru je "Generating... 7/11 steps in batch 2/4" — presne to,
            # co uzivatel potrebuje vedet, a nemame jak to spocitat sami. Zaroven je
            # to JEDINE misto, kde se dozvime cislo davky: zprava s obrazkem ho
            # neveze, takze se cte odsud a pamatuje si do dalsi zpravy.
            if title:
                JOB.update(msg=title)
                m = BATCH_RE.search(title)
                if m:
                    last_batch[0] = int(m.group(1))
            if not imgs:
                return
            # Nahled nesmi shodit generovani: kdyz zapis selze (plny disk, zamceny
            # soubor), je spravna reakce ukazat o obrazek min, ne zahodit praci,
            # ktera uz stala minutu GPU. Ale MLCET taky nesmi -- prave tise spolknuta
            # vyjimka (PIL neumi format z pripony ".png.tmp") stala za tim, ze zivy
            # pruh poprve nefungoval a nebylo podle ceho hledat. Duvod se schova do
            # zaverecneho hlaseni, jednou.
            try:
                by_batch[last_batch[0]] = imgs[0]
                tick[0] += 1
                JOB.update(preview=_write_preview(by_batch, w, h, d, name, tick[0]))
            except Exception as e:
                if not prev_err:
                    prev_err.append(f"{type(e).__name__}: {e}")

        imgs = rd.txt2img(prompt, negative=negative, size=(w, h), n=n, seed=seed,
                          quality=quality, loras=list(loras), rembg=True,
                          on_progress=progress)
        # Od tehle chvile uz jsou hotove sprity a zivy pruh by ukazoval starsi stav
        # nez mrizka pod nim.
        JOB.update(preview="")

        first = ""
        for i, a in enumerate(imgs):
            a = gen.clean(a, colors)
            sc = score_of(a, (w, h))
            fn = next_cand(d)
            Image.fromarray(a, "RGBA").save(os.path.join(d, fn))
            meta["scores"][fn] = sc
            first = first or fn
            write_meta(d, meta)
            JOB.update(done=i + 1, cand=first,
                       msg=f"kandidát {i + 1}/{len(imgs)} — známka {sc['grade']}")

        hlaska = f"hotovo — {len(imgs)} kandidátů z Retro Diffusion"
        if prev_err:
            hlaska += f" · živý náhled nešel: {prev_err[0]}"
        JOB.update(state="done", cand=first, msg=hlaska)
    except Exception as e:
        # Pruh musi zmizet i pri chybe, jinak zustane viset posledni rozpracovany
        # obrazek u cerveneho hlaseni a vypada to, ze neco vzniklo.
        JOB.update(state="error", preview="", msg=f"{type(e).__name__}: {e}")


# ------------------------------------------------------------------ iterace a animace


def load_cand(setname, cand):
    p = os.path.join(GEN_DIR, os.path.basename(setname), os.path.basename(cand))
    if not os.path.isfile(p):
        return None
    return np.array(Image.open(p).convert("RGBA"))


def next_cand(d):
    """Prvni volne cand_NN.png.

    Cislo se bere z toho, co na disku JE, ne z poctu polozek: kdyz nekoho z prostredku
    smazes, novy kandidat nesmi prepsat toho, ktery zbyl — a s nim i cely jeho rodokmen."""
    n = 0
    for f in os.listdir(d):
        if f.startswith("cand_") and f.endswith(".png") and "_frame_" not in f:
            head = f[len("cand_"):-len(".png")].split("_")[0]
            try:
                n = max(n, int(head))
            except ValueError:
                pass
    return "cand_%02d.png" % (n + 1)


def lineage_chain(setname, cand):
    """Retez predku od korene k tomuhle kandidatovi.

    Kandidat bez zaznamu je koren — tak vypadaji vsichni, kdo vznikli prvnim generovanim
    i cela stara meta.json. Pojistka proti cyklu tu je proto, ze meta.json je obycejny
    soubor na disku: staci rucni uprava na „rodic sam sebe" a server by se zatocil."""
    meta = read_meta(os.path.join(GEN_DIR, os.path.basename(setname)))
    lin = meta["lineage"]
    chain, seen, cur = [], set(), cand
    while cur and cur not in seen:
        seen.add(cur)
        rec = lin.get(cur) or {}
        chain.append({"cand": cur, "prompt": rec.get("prompt") or meta["prompt"],
                      "strength": rec.get("strength"),
                      # Rucni premalovani prepisuje kandidata na miste, takze deti pod nim
                      # uz nevznikly z techhle pixelu. Retez to musi rict nahlas.
                      "hand_edited": bool(rec.get("hand_edited")),
                      "edits": int(rec.get("edits") or 0)})
        cur = rec.get("parent")
    chain.reverse()
    return chain


def base_prompt(setname, cand):
    """Prompt, ze ktereho kandidat vznikl. Bere se z rodokmenu, ne z pole v hlavicce:
    animace i rotace maji vzniknout z TOHO, co je na spritu videt, ne z toho, co bylo
    naposledy napsane nahore."""
    chain = lineage_chain(setname, cand)
    return chain[-1]["prompt"] if chain else ""


def run_refine(setname, cand, prompt, strength):
    """Z kandidata udelej jeho dite a zapis, ze z nej vzniklo.

    Rodic, prompt i sila jdou do „lineage" hned pri vzniku. Doplnovat je pozdeji nejde —
    za tyden uz nikdo nevi, ze cand_07 je vylepsene cand_03, a hromada spritu ve slozce
    prestane davat smysl."""
    import gen
    try:
        d = os.path.join(GEN_DIR, os.path.basename(setname))
        parent = load_cand(setname, cand)
        if parent is None:
            JOB.update(state="error", msg="rodič neexistuje")
            return
        pipe2 = img2img()
        JOB.update(state="running", msg="dolaďuji", done=0, total=1, set=setname, cand="")
        ph, pw = parent.shape[:2]
        a = gen.refine(pipe2, parent, prompt, strength=float(strength), size=max(pw, ph))
        sc = score_of(a, (pw, ph))
        fn = next_cand(d)
        Image.fromarray(a, "RGBA").save(os.path.join(d, fn))
        meta = read_meta(d)
        meta["scores"][fn] = sc
        meta["lineage"][fn] = {"parent": cand, "prompt": prompt, "strength": float(strength)}
        write_meta(d, meta)
        JOB.update(state="done", done=1, cand=fn,
                   msg=f"hotovo — {fn}, známka {sc['grade']}")
    except Exception as e:
        JOB.update(state="error", msg=f"{type(e).__name__}: {e}")


def anim_label(meta, stem, kind):
    """Volny nazev sady framu. Vlastni pozy se daji pustit vickrat za sebou a druhy pokus
    nesmi prepsat prvni — jinak neni co s cim porovnat."""
    base = kind
    i = 1
    while f"{stem}_{base}" in meta["anims"]:
        i += 1
        base = f"{kind}{i}"
    return base


def run_animate(setname, cand, kind, strength, poses=None):
    """Animace z jednoho kandidata — framy vedle nej, ne do assets/."""
    import gen
    try:
        d = os.path.join(GEN_DIR, os.path.basename(setname))
        base = load_cand(setname, cand)
        if base is None:
            JOB.update(state="error", msg="kandidát neexistuje")
            return
        prompt = base_prompt(setname, cand)
        if poses:
            phrases, kind = poses, "vlastni"
        else:
            phrases = gen.POSES.get(kind)
            if not phrases:
                JOB.update(state="error", msg=f"neznámý druh animace: {kind}")
                return
        # gen.animate chce HOTOVE prompty poz, ne druh animace. Slozit je musi volajici,
        # protoze jen ten zna prompt rodice. Predat misto toho retezec by nechalo
        # `for pose in prompt` iterovat po PISMENECH a vyrobit frame na kazde z nich.
        pipe2 = img2img()
        pose_prompts = [f"{prompt}, {ph}" if prompt else ph for ph in phrases]
        JOB.update(state="running", msg="animuji", done=0, total=len(pose_prompts),
                   set=setname, cand="")
        bh, bw = base.shape[:2]
        frames = gen.animate(pipe2, base, pose_prompts, strength=float(strength),
                             size=max(bw, bh),
                             on_frame=lambda i, n: JOB.update(done=i, msg=f"frame {i}/{n}"))
        stem = cand[:-len(".png")] if cand.endswith(".png") else cand
        meta = read_meta(d)
        label = anim_label(meta, stem, kind)
        names = []
        for i, a in enumerate(frames, 1):
            fn = f"{stem}_{label}_frame_{i}.png"
            Image.fromarray(a, "RGBA").save(os.path.join(d, fn))
            names.append(fn)
        meta["anims"][f"{stem}_{label}"] = names
        if poses:
            meta.setdefault("poses", {})[f"{stem}_{label}"] = list(poses)
        write_meta(d, meta)
        JOB.update(state="done", cand=cand, msg=f"hotovo — {len(names)} framů ({label})")
    except Exception as e:
        JOB.update(state="error", msg=f"{type(e).__name__}: {e}")


def run_rotate(setname, cand, strength):
    """Osm smeru z jednoho kandidata.

    Ukladá se jako <stem>_<smer>.png vedle rodice, at je v jedne slozce videt cely tvor.
    dirs=None schvalne: seznam smeru patri generatoru (gen.DIRECTIONS), tady se jen
    kresli, co prislo zpatky."""
    import gen
    try:
        d = os.path.join(GEN_DIR, os.path.basename(setname))
        base = load_cand(setname, cand)
        if base is None:
            JOB.update(state="error", msg="kandidát neexistuje")
            return
        prompt = base_prompt(setname, cand)
        pipe2 = img2img()
        bh, bw = base.shape[:2]
        JOB.update(state="running", msg="otáčím", done=0, total=len(DIRS),
                   set=setname, cand="")

        # Kolik argumentu on_dir dostane, kontrakt nerika — proto *a. Pevna arita by pri
        # neshode spadla az UPROSTRED osmi minut generovani, tedy v tom nejdrazsim miste.
        def tick(*a):
            JOB.update(done=min(len(DIRS), JOB["done"] + 1),
                       msg=f"směr {JOB['done'] + 1}/{len(DIRS)}")

        res = gen.rotate(pipe2, base, prompt, dirs=None, strength=float(strength),
                         size=max(bw, bh), on_dir=tick)
        stem = cand[:-len(".png")] if cand.endswith(".png") else cand
        meta = read_meta(d)
        got = {}
        for dname, a in res.items():
            safe = re.sub(r"[^a-z0-9\-]", "", str(dname).lower()) or "dir"
            fn = f"{stem}_{safe}.png"
            Image.fromarray(np.asarray(a), "RGBA").save(os.path.join(d, fn))
            got[safe] = fn
            meta["lineage"][fn] = {"parent": cand, "prompt": f"rotace: {dname}",
                                   "strength": float(strength)}
        meta["dirs"][stem] = got
        write_meta(d, meta)
        JOB.update(state="done", cand=cand, msg=f"hotovo — {len(got)} směrů")
    except Exception as e:
        JOB.update(state="error", msg=f"{type(e).__name__}: {e}")


def run_rotate_ip(setname, cand, strength):
    """Osm smeru s IP-Adapterem pro drzeni identity.

    Pouziva gen.rotate_ip misto gen.rotate: IP-Adapter prida jizni pohled do
    cross-attention, takze model VIDI barvy a doplnky originálu po celou dobu.
    Vysledek je jedna prisera otocena, ne osm ruznych priser."""
    import gen
    try:
        d = os.path.join(GEN_DIR, os.path.basename(setname))
        base = load_cand(setname, cand)
        if base is None:
            JOB.update(state="error", msg="kandidát neexistuje")
            return
        prompt = base_prompt(setname, cand)
        pipe = text_pipe(None)
        bh, bw = base.shape[:2]
        JOB.update(state="running", msg="otáčím (IP-Adapter)", done=0,
                   total=len(DIRS), set=setname, cand="")

        def tick(*a):
            JOB.update(done=min(len(DIRS), JOB["done"] + 1),
                       msg=f"IP směr {JOB['done'] + 1}/{len(DIRS)}")

        res = gen.rotate_ip(pipe, base, prompt, dirs=None, strength=float(strength),
                            size=max(bw, bh), on_dir=tick)
        stem = cand[:-len(".png")] if cand.endswith(".png") else cand
        meta = read_meta(d)
        got = {}
        for dname, a in res.items():
            safe = re.sub(r"[^a-z0-9\-]", "", str(dname).lower()) or "dir"
            fn = f"{stem}_{safe}.png"
            Image.fromarray(np.asarray(a), "RGBA").save(os.path.join(d, fn))
            got[safe] = fn
            meta["lineage"][fn] = {"parent": cand, "prompt": f"rotace: {dname}",
                                   "strength": float(strength)}
        meta["dirs"][stem] = got
        write_meta(d, meta)
        JOB.update(state="done", cand=cand, msg=f"hotovo — {len(got)} směrů (IP-Adapter)")
    except Exception as e:
        JOB.update(state="error", msg=f"{type(e).__name__}: {e}")


def run_rotate_pose(setname, cand, strength):
    """Osm smeru pres KOSTRU a ControlNet — jedina varianta, ktera pohled opravdu meni.

    run_rotate a run_rotate_ip prekresluji celni sprite, a zmerilo se, ze pohled zustane
    celni (docs/art/rotace.md): vyrobi varianty tehoz pohledu, ne otoceni. Tady urcuje
    pohled kostra kreslena z uhlu, identitu drzi reference a text uz jen rika, co to je.

    `strength` je tu SILA REFERENCE (identita), ne sila prekresleni — u kostrove cesty
    zadne prekresleni neni, zacina se od sumu. Posuvnik ve studiu je tentyz, vyznam jiny;
    proto to stoji tady, at se to necte jako preklep."""
    import gen
    try:
        d = os.path.join(GEN_DIR, os.path.basename(setname))
        base = load_cand(setname, cand)
        if base is None:
            JOB.update(state="error", msg="kandidát neexistuje")
            return
        prompt = base_prompt(setname, cand)
        pipe = text_pipe(None)
        bh, bw = base.shape[:2]
        JOB.update(state="running", msg="otáčím (kostra)", done=0,
                   total=len(DIRS), set=setname, cand="")

        def tick(*a):
            JOB.update(done=min(len(DIRS), JOB["done"] + 1),
                       msg=f"kostra směr {JOB['done'] + 1}/{len(DIRS)}")

        res = gen.rotate_pose(pipe, base, prompt, dirs=None, ip_scale=float(strength),
                              size=max(bw, bh), on_dir=tick)
        stem = cand[:-len(".png")] if cand.endswith(".png") else cand
        meta = read_meta(d)
        got = {}
        for dname, a in res.items():
            safe = re.sub(r"[^a-z0-9\-]", "", str(dname).lower()) or "dir"
            fn = f"{stem}_{safe}.png"
            Image.fromarray(np.asarray(a), "RGBA").save(os.path.join(d, fn))
            got[safe] = fn
            meta["lineage"][fn] = {"parent": cand, "prompt": f"kostra: {dname}",
                                   "ip_scale": float(strength),
                                   "control_scale": gen.CONTROL_SCALE,
                                   "canon": gen.gen_pose.CANON}
        meta["dirs"][stem] = got
        write_meta(d, meta)
        JOB.update(state="done", cand=cand, msg=f"hotovo — {len(got)} směrů (kostra)")
    except Exception as e:
        JOB.update(state="error", msg=f"{type(e).__name__}: {e}")


def run_inpaint(setname, cand, mask_data_url, prompt, strength):
    """Pregeneruje jen maskovanou oblast spritu, zbytek zustane na pixel presne stejny.

    Maska prichazi jako data URL z canvasu Pixel Editoru. Bíle pixely = pregenerovat,
    černé = nechat. Nový sprite se uloží jako kandidát s lineage (rodič = originál)."""
    import gen
    import base64
    from io import BytesIO
    try:
        d = os.path.join(GEN_DIR, os.path.basename(setname))
        base = load_cand(setname, cand)
        if base is None:
            JOB.update(state="error", msg="kandidát neexistuje")
            return
        bh, bw = base.shape[:2]

        # Dekoduj masku z data URL
        encoded = mask_data_url.split(",", 1)[1] if "," in mask_data_url else mask_data_url
        raw = base64.b64decode(encoded)
        mask_img = Image.open(BytesIO(raw)).convert("L")
        if mask_img.size != (bw, bh):
            mask_img = mask_img.resize((bw, bh), Image.NEAREST)
        mask_bool = np.array(mask_img) > 128

        if not mask_bool.any():
            JOB.update(state="error", msg="maska je prázdná — označ oblast k přegenerování")
            return

        JOB.update(state="running", msg="inpaint — generuji", done=0, total=1,
                   set=setname, cand="")

        pipe_inp = inpaint_pipe()

        a = gen.inpaint(pipe_inp, base, mask_bool, prompt,
                        strength=float(strength), size=(bw, bh))

        fn = next_cand(d)
        Image.fromarray(a, "RGBA").save(os.path.join(d, fn))
        sc = score_of(a, (bw, bh))
        meta = read_meta(d)
        meta["scores"][fn] = sc
        meta["lineage"][fn] = {"parent": cand, "prompt": f"inpaint: {prompt}",
                               "strength": float(strength)}
        write_meta(d, meta)
        JOB.update(state="done", cand=fn,
                   msg=f"hotovo — inpaint {fn} (známka {sc['grade']})")
    except Exception as e:
        JOB.update(state="error", msg=f"{type(e).__name__}: {e}")


def run_full_character(setname, cand, include_dirs=False):
    """Sestavi kompletni sadu puppet animaci z jednoho kandidata jednim klikem.

    Walk (8f) + Idle (4f) + Attack (7f) + Death (10f) = 29 framů za < 1 sekundu.
    Pokud include_dirs a existuji rotace, prida walk i pro east/north/west.

    Zadna GPU, zadne cekani. Vysledek je okamzity a s nulovym pixel-boilem."""
    import puppet_anim
    try:
        d = os.path.join(GEN_DIR, os.path.basename(setname))
        base = load_cand(setname, cand)
        if base is None:
            return {"ok": False, "msg": "kandidát neexistuje"}
        stem = cand[:-len(".png")] if cand.endswith(".png") else cand
        meta = read_meta(d)
        total_frames = 0

        # Standardni 4 animace z jihniho pohledu
        for kind, n_frames in [("walk", 8), ("idle", 4), ("attack", 7), ("death", 10)]:
            frames = puppet_anim.puppet_animate(base, kind)
            label = anim_label(meta, stem, f"p{kind}")
            names = []
            for i, a in enumerate(frames, 1):
                fn = f"{stem}_{label}_frame_{i}.png"
                Image.fromarray(a, "RGBA").save(os.path.join(d, fn))
                names.append(fn)
            meta["anims"][f"{stem}_{label}"] = names
            total_frames += len(names)

        # Volitelne: walk z rotaci (east, north, west)
        if include_dirs:
            dirs_dict = meta.get("dirs", {}).get(stem, {})
            dir_walk_map = {"east": "walk_side", "north": "walk_north", "west": "walk_side"}
            for dname, walk_kind in dir_walk_map.items():
                fn_rot = dirs_dict.get(dname)
                if not fn_rot:
                    continue
                rot_path = os.path.join(d, fn_rot)
                if not os.path.isfile(rot_path):
                    continue
                rot_arr = np.array(Image.open(rot_path).convert("RGBA"))
                frames = puppet_anim.puppet_animate(rot_arr, walk_kind)
                label = anim_label(meta, stem, f"p{walk_kind}_{dname}")
                names = []
                for i, a in enumerate(frames, 1):
                    fn = f"{stem}_{label}_frame_{i}.png"
                    Image.fromarray(a, "RGBA").save(os.path.join(d, fn))
                    names.append(fn)
                meta["anims"][f"{stem}_{label}"] = names
                total_frames += len(names)

        write_meta(d, meta)
        return {"ok": True, "count": total_frames,
                "msg": f"{total_frames} framů — kompletní postava sestavena"}
    except Exception as e:
        return {"ok": False, "msg": f"{type(e).__name__}: {e}"}


def run_puppet(setname, cand, kind, intensity):
    """Proceduralni animace bez AI: posun vrstev spritu podle sablony.

    Na rozdil od run_animate nepotrebuje GPU, model ani pipe — pracuje ciste
    s pixely vstupniho spritu. Vysledek je za milisekundy, ne minuty."""
    import puppet_anim
    try:
        d = os.path.join(GEN_DIR, os.path.basename(setname))
        base = load_cand(setname, cand)
        if base is None:
            return {"ok": False, "msg": "kandidát neexistuje"}
        frames = puppet_anim.puppet_animate(base, kind, intensity)
        stem = cand[:-len(".png")] if cand.endswith(".png") else cand
        meta = read_meta(d)
        label = anim_label(meta, stem, f"p{kind}")
        names = []
        for i, a in enumerate(frames, 1):
            fn = f"{stem}_{label}_frame_{i}.png"
            Image.fromarray(a, "RGBA").save(os.path.join(d, fn))
            names.append(fn)
            meta["lineage"][fn] = {"parent": cand, "prompt": f"loutka: {kind}",
                                   "strength": 0.0}
        meta["anims"][f"{stem}_{label}"] = names
        write_meta(d, meta)
        return {"ok": True, "label": label, "count": len(names),
                "msg": f"{len(names)} framů ({label})"}
    except Exception as e:
        return {"ok": False, "msg": f"{type(e).__name__}: {e}"}


def run_recolor(setname, cand, mode, target_color="#ff3b30", hue_shift=0.0):
    """Paletove promeny a varianty: prebarveni a tier upgrady bez AI."""
    import palette_morph
    try:
        d = os.path.join(GEN_DIR, os.path.basename(setname))
        base = load_cand(setname, cand)
        if base is None:
            return {"ok": False, "msg": "kandidát neexistuje"}
        if mode == "target":
            res = palette_morph.recolor_target(base, target_color)
        elif mode == "shift":
            res = palette_morph.recolor_shift(base, float(hue_shift))
        elif mode == "tier2":
            res = palette_morph.tier_upgrade(base, tier=2)
        elif mode == "tier3":
            res = palette_morph.tier_upgrade(base, tier=3)
        else:
            return {"ok": False, "msg": f"neznámý režim: {mode}"}

        fn = next_cand(d)
        Image.fromarray(res, "RGBA").save(os.path.join(d, fn))
        sc = score_of(res, (res.shape[1], res.shape[0]))
        meta = read_meta(d)
        meta["scores"][fn] = sc
        meta["lineage"][fn] = {"parent": cand, "prompt": f"recolor:{mode}", "strength": 0.0}
        write_meta(d, meta)
        return {"ok": True, "cand": fn, "msg": f"vytvořen {fn} (známka {sc['grade']})"}
    except Exception as e:
        return {"ok": False, "msg": f"{type(e).__name__}: {e}"}


def save_edited_sprite(setname, cand, data_url):
    """Ulozi upraveny sprite z Pixel Editoru primo do kandidata."""
    import base64
    from io import BytesIO
    try:
        d = os.path.join(GEN_DIR, os.path.basename(setname))
        p = os.path.join(d, os.path.basename(cand))
        if not os.path.isfile(p):
            return {"ok": False, "msg": "kandidát neexistuje"}
        encoded = data_url.split(",", 1)[1] if "," in data_url else data_url
        raw_bytes = base64.b64decode(encoded)
        im = Image.open(BytesIO(raw_bytes)).convert("RGBA")
        im.save(p)
        arr = np.array(im)
        fn = os.path.basename(cand)
        sc = score_of(arr, (arr.shape[1], arr.shape[0]))
        meta = read_meta(d)
        meta["scores"][fn] = sc
        # Rucni editace prepisuje kandidata NA MISTE. Deti, ktere z nej uz vznikly, tim
        # zacnou ukazovat na jine pixely, nez ze kterych se narodily — rodokmen zacne lhat
        # a nikde to neni videt. Zaznam to nevrati, ale udela to VIDITELNYM.
        prev = meta["lineage"].get(fn, {})
        meta["lineage"][fn] = {**prev, "hand_edited": True,
                               "edits": int(prev.get("edits", 0)) + 1}
        write_meta(d, meta)
        n = meta["lineage"][fn]["edits"]
        note = "" if n == 1 else f", {n}. úprava"
        return {"ok": True, "msg": f"uloženo (známka {sc['grade']}{note})"}
    except Exception as e:
        return {"ok": False, "msg": f"{type(e).__name__}: {e}"}


# ------------------------------------------------------------------ instalace


def lock_master(a):
    """Premapuj sprite na master paletu projektu (docs/art/palette_48.hex).

    CHROMA_WEIGHT tu neni ozdoba: pri SDILENE palete lezi sedy pixel v Oklabu blizko
    stredu a od stredu je stejne daleko na vsechny strany, takze bez durazu na barevne osy
    spadne na nejblizsi SYTOU barvu — takhle dostal ruzovy clickbait zelene flicky na telo.

    Vraci i cenu premapovani: prumernou vzdalenost v Oklabu. Nad ~0.03 je posun videt,
    kolem 0.06 uz prisera meni barvu — proto se to ukazuje uzivateli, ne loguje."""
    pal = load_palette_file(MASTER_PAL)
    m = a[..., 3] > 32
    if not m.any():
        return a, 0.0, len(pal)
    pool = Counter(map(tuple, a[..., :3][m]))
    err = palette_error(pool, pal, CHROMA_WEIGHT)
    rgb = remap(a[..., :3].astype(np.int64), m, pal, to_oklab(pal), CHROMA_WEIGHT)
    out = np.dstack([rgb.astype(np.uint8), a[..., 3]])
    used = len({tuple(c) for c in out[..., :3][m]})
    return out, err, used


def install(setname, cand, target, force=False, lock=False):
    """Kandidat -> assets/distractions/<target>_frame_1.png.

    Zamerne jen JEDEN frame. Kandidati z jednoho promptu nejsou animace — je to N pokusu
    o tutez pozu, ne osm framu chuze. Tvarit se, ze z nich cyklus slozim, by vyrobilo
    presne to kmitani, ktere celou dobu meríme a opravujeme. Animace se resi zvlast.

    Cil byl sanitizovany od zacatku, ZDROJ ne — a pritom prave ten rozhoduje, co se do
    assets/ zkopiruje. install("..\\..", "README.md", "x") soubor opravdu vyrobil.

    Rastr se KONTROLUJE, ale nezakazuje: „force" je vedomé rozhodnuti uzivatele, ne
    obejiti. Tise nainstalovat sprite, ktery rozbije mrizku, je horsi nez oboje."""
    src = os.path.join(GEN_DIR, os.path.basename(setname), os.path.basename(cand))
    if not os.path.exists(src):
        return {"ok": False, "msg": "kandidát neexistuje"}
    safe = "".join(ch for ch in (target or "") if ch.isalnum() or ch == "_")
    if not safe:
        return {"ok": False, "msg": "neplatné jméno"}
    dst = os.path.join(ART_DIR, f"{safe}_frame_1.png")
    if os.path.exists(dst):
        return {"ok": False, "msg": f"{os.path.basename(dst)} už existuje — zvol jiné jméno"}

    a = np.array(Image.open(src).convert("RGBA"))
    h, w = a.shape[:2]
    ok, gnote = grid_check(w, h)
    if not ok and not force:
        return {"ok": False, "ask": True,
                "msg": f"{w}×{h}: {gnote}. Ve hře se to projeví posunem o půl buňky."}

    note = []
    if lock:
        try:
            a, err, used = lock_master(a)
            cena = ("beze změny" if err < 0.015 else
                    "posun je vidět" if err < 0.045 else "barva se mění")
            note.append(f"master paleta: {used} barev, odchylka {err:.3f} ({cena})")
        except Exception as e:
            return {"ok": False, "msg": f"paleta selhala: {type(e).__name__}: {e}"}
    if not ok:
        note.append("rastr NESEDÍ — instalováno na tvoji odpovědnost")

    # Snimek PRED zapisem. Instalace je jediné misto, kde tenhle nastroj sahá do
    # assets/, cili do veci, ktera je ve hre videt — a bez zpatecky se clovek boji
    # zkouset. Snimek se dela i kdyz cil jeste neexistuje: art_undo si pamatuje i
    # "tenhle soubor tu nebyl", takze restore umi novy soubor zase odstranit.
    # Selhani snimku instalaci NEZASTAVI: horsi nez chybejici zaloha je nefunkcni
    # tlacitko, a duvod se uzivatel dozvi v poznamce.
    try:
        import art_undo
        snap = art_undo.snapshot([dst], f"install-{safe}", quiet=True)
        note.append(f"zpátečka: snímek {snap}")
    except Exception as e:
        note.append(f"zpátečka SELHALA ({type(e).__name__}) — vracet se bude ručně")

    # Zapisuje se pole, ne shutil.copyfile: pri lock=True uz `a` NENI to, co lezi na
    # disku ve zdroji, a kopie souboru by zamek palety tise zahodila.
    Image.fromarray(a, "RGBA").save(dst)
    return {"ok": True, "msg": os.path.relpath(dst, PROJ), "note": " · ".join(note)}


def run_export_sheet(setname, anim_key):
    """Sestavi vsechny framy dane animace do jednoho horizontalniho spritesheetu PNG."""
    try:
        d = os.path.join(GEN_DIR, os.path.basename(setname))
        meta = read_meta(d)
        frames = meta.get("anims", {}).get(anim_key, [])
        if not frames:
            return {"ok": False, "msg": f"animace {anim_key} nemá žádné framy"}
        imgs = []
        for fn in frames:
            p = os.path.join(d, fn)
            if os.path.isfile(p):
                imgs.append(Image.open(p).convert("RGBA"))
        if not imgs:
            return {"ok": False, "msg": "framy na disku neexistují"}
        fw, fh = imgs[0].size
        sheet = Image.new("RGBA", (fw * len(imgs), fh), (0, 0, 0, 0))
        for i, im in enumerate(imgs):
            sheet.paste(im, (i * fw, 0))
        out_fn = f"{anim_key}_sheet.png"
        out_path = os.path.join(d, out_fn)
        sheet.save(out_path)
        return {"ok": True, "sheet": out_fn, "w": fw * len(imgs), "h": fh, "count": len(imgs),
                "url": f"/img/gen/{quote(setname)}/{quote(out_fn)}",
                "msg": f"spritesheet ({len(imgs)} framů, {fw*len(imgs)}×{fh} px) uložen"}
    except Exception as e:
        return {"ok": False, "msg": f"{type(e).__name__}: {e}"}


def run_install_set(setname, cand, target, lock=False, force=False, create_tres=False):
    """Nainstaluje CELOU sadu (chuzi, smery, utok, smrt) jednim kliknutim do assets/distractions/."""
    try:
        d = os.path.join(GEN_DIR, os.path.basename(setname))
        meta = read_meta(d)
        safe = "".join(ch for ch in (target or "") if ch.isalnum() or ch == "_")
        if not safe:
            return {"ok": False, "msg": "neplatné id postavy"}
        os.makedirs(ART_DIR, exist_ok=True)
        installed = []
        stem = cand[:-len(".png")] if cand.endswith(".png") else cand

        # Snimek CELE slozky, ne jen souboru, ktere se chystame prepsat: jmena
        # cilu vznikaji az v prubehu (z animaci a smeru v meta.json), takze v
        # tuhle chvili jeste nevime, do ceho sahneme. Na rozdil od install()
        # tenhle beh PREPISUJE bez ptani a klidne deset souboru najednou.
        #
        # Neni to tak drahe, jak to vypada: art_undo preskoci kazdy soubor, ktery
        # uz ma git v HEAD, a zkopiruje jen to, co je rozpracovane. U zacommitovaneho
        # artu je snimek tedy skoro zadarmo.
        snap_note = ""
        try:
            import art_undo
            snap_note = f" · zpátečka: snímek {art_undo.snapshot([ART_DIR], f'install-set-{safe}', quiet=True)}"
        except Exception as e:
            snap_note = f" · zpátečka SELHALA ({type(e).__name__})"

        # 1. Base frame 1
        base_src = os.path.join(d, os.path.basename(cand))
        if os.path.isfile(base_src):
            dst = os.path.join(ART_DIR, f"{safe}_frame_1.png")
            im = Image.open(base_src).convert("RGBA")
            if lock:
                arr, _, _ = lock_master(np.array(im))
                im = Image.fromarray(arr, "RGBA")
            im.save(dst)
            installed.append(f"{safe}_frame_1.png")

        # 2. Animations
        anims_dict = meta.get("anims", {})
        for anim_key, frame_list in anims_dict.items():
            if not anim_key.startswith(stem + "_"):
                continue
            anim_suffix = anim_key[len(stem) + 1:].lower()
            prefix = ""
            if "pwalk" in anim_suffix or "walk" in anim_suffix:
                if "north" in anim_suffix: prefix = "_north"
                elif "east" in anim_suffix: prefix = "_east"
                elif "west" in anim_suffix: prefix = "_west"
                else: prefix = ""
            elif "attack" in anim_suffix or "pattack" in anim_suffix:
                prefix = "_attack"
            elif "death" in anim_suffix or "pdeath" in anim_suffix:
                prefix = "_death"
            elif "idle" in anim_suffix or "pidle" in anim_suffix:
                prefix = "_idle"
            else:
                prefix = f"_{anim_suffix}"

            for i, fn in enumerate(frame_list, 1):
                f_path = os.path.join(d, fn)
                if os.path.isfile(f_path):
                    target_fn = f"{safe}{prefix}_frame_{i}.png"
                    dst = os.path.join(ART_DIR, target_fn)
                    im = Image.open(f_path).convert("RGBA")
                    if lock:
                        arr, _, _ = lock_master(np.array(im))
                        im = Image.fromarray(arr, "RGBA")
                    im.save(dst)
                    installed.append(target_fn)

        # 3. Directions
        dirs_dict = meta.get("dirs", {}).get(stem, {})
        for dname, fn in dirs_dict.items():
            f_path = os.path.join(d, fn)
            if os.path.isfile(f_path):
                dir_suffix = f"_{dname.replace('-', '_')}" if dname != "south" else ""
                target_fn = f"{safe}{dir_suffix}_frame_1.png"
                dst = os.path.join(ART_DIR, target_fn)
                im = Image.open(f_path).convert("RGBA")
                if lock:
                    arr, _, _ = lock_master(np.array(im))
                    im = Image.fromarray(arr, "RGBA")
                im.save(dst)
                installed.append(target_fn)

        # 4. Create .tres
        if create_tres:
            data_dir = os.path.join(PROJ, "data", "distractions")
            os.makedirs(data_dir, exist_ok=True)
            tres_path = os.path.join(data_dir, f"{safe}.tres")
            if not os.path.exists(tres_path):
                tres_content = f"""[gd_resource type="Resource" script_class="DistractionData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/resources/distraction_data.gd" id="1_data"]

[resource]
script = ExtResource("1_data")
id = "{safe}"
display_name = "{safe.replace('_', ' ').title()}"
hp = 100.0
speed = 60.0
block_weight = 1
color = Color(1, 0.23, 0.19, 1)
"""
                with open(tres_path, "w", encoding="utf-8") as f:
                    f.write(tres_content)
                installed.append(f"data/distractions/{safe}.tres")

        installed = sorted(set(installed))
        godot_bin = r"C:\Users\reath\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe"
        if os.path.isfile(godot_bin):
            import subprocess
            try:
                subprocess.Popen([godot_bin, "--headless", "--path", PROJ, "--import"],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception:
                pass

        return {"ok": True, "count": len(installed), "files": installed,
                "msg": f"Nainstalováno {len(installed)} souborů do assets/distractions/ "
                       f"pro '{safe}'{snap_note}"}
    except Exception as e:
        return {"ok": False, "msg": f"{type(e).__name__}: {e}"}


# ------------------------------------------------------------------ server

HTML = r"""<!doctype html><html lang="cs"><meta charset="utf-8">
<title>Sprite Studio</title><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#14131a;color:#dcdce4;font:14px/1.5 system-ui,-apple-system,sans-serif;
 display:grid;grid-template-columns:210px 1fr;grid-template-rows:auto auto 1fr;height:100vh}
/* Zivy pruh je VLASTNI radek mrizky, ne plovouci vrstva pres obsah: kdyz se objevi,
   mrizka kandidatu se posune dolu misto aby se schovala. Behem generovani je to jedina
   vec, kterou clovek sleduje, a nesmi prekryvat to, co uz vzniklo. */
#live{grid-column:1/3;display:none;gap:14px;align-items:center;padding:10px 14px;
 background:#191822;border-bottom:1px solid #2a2935}
#live img{image-rendering:pixelated;height:96px;width:auto;background:#0e0d13;
 border-radius:6px;padding:4px}
#live .t{font-size:12px;color:#8d8d9e;line-height:1.7}
#live .t b{color:#c8c8d6;font-weight:600;display:block;font-size:13px}
header{grid-column:1/3;display:flex;flex-direction:column;gap:7px;padding:9px 14px;
 background:#1b1a23;border-bottom:1px solid #2a2935}
.hrow{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
header b{font-size:15px;margin-right:6px}
input,select,button{background:#24232e;color:#dcdce4;border:1px solid #34333f;
 border-radius:6px;padding:6px 10px;font:inherit}
input:focus,select:focus{outline:1px solid #6d7cff}
button{cursor:pointer}button:hover{background:#2e2d3a}
button.p{background:#4d5bd6;border-color:#5b68e0}button.p:hover{background:#5b68e0}
button:disabled{opacity:.45;cursor:default}
button.sm{padding:3px 8px;font-size:12px}
#prompt{flex:1;min-width:180px}
label.f{display:flex;gap:6px;align-items:center;font-size:12px;color:#8d8d9e}
label.f input[type=range]{width:120px;padding:0;accent-color:#6d7cff}
nav{background:#191822;border-right:1px solid #2a2935;overflow:auto;padding:8px}
nav h3{font-size:11px;text-transform:uppercase;color:#7a7a8c;margin:12px 6px 6px;
 letter-spacing:.04em}
nav a{display:block;padding:6px 9px;border-radius:6px;color:#c2c2d0;cursor:pointer;
 text-decoration:none;font-size:13px;overflow:hidden;text-overflow:ellipsis;
 white-space:nowrap}
nav a:hover{background:#23222e}nav a.on{background:#333150;color:#fff}
main{overflow:auto;padding:16px 18px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(132px,1fr));gap:12px}
.card{background:#1d1c26;border:1px solid #2a2935;border-radius:9px;padding:9px;
 cursor:pointer;text-align:center}
.card:hover{border-color:#4d5bd6}
.card img,.big img,.strip img,.rg img,.ref img{image-rendering:pixelated;display:block}
.card img{width:100%;background:#0e0d13;border-radius:5px}
.card .n{font-size:12px;margin-top:6px;color:#a8a8ba;display:flex;
 justify-content:space-between;align-items:center;gap:6px}
.card .n span{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.badge{font-size:11px;font-weight:700;padding:1px 6px;border-radius:4px}
.g-hi{background:#1e4630;color:#7ee2a8}.g-mid{background:#4a3c1a;color:#ffcf7a}
.g-lo{background:#4a1f1f;color:#ff9188}
h2{font-size:17px;margin-bottom:4px}.sub{color:#7a7a8c;font-size:12px;margin-bottom:14px}
.row{display:flex;gap:22px;flex-wrap:wrap;margin-bottom:22px}
.setbox{background:#1d1c26;border:1px solid #2a2935;border-radius:9px;padding:10px}
.setbox h4{font-size:12px;color:#9a9aac;margin-bottom:7px;text-transform:uppercase}
.big{background:#0e0d13;border-radius:6px;display:grid;place-items:center;padding:10px}
.strip{display:flex;gap:4px;margin-top:8px;flex-wrap:wrap}
.strip img{width:38px;background:#0e0d13;border-radius:3px;border:2px solid transparent}
.strip img.on{border-color:#6d7cff}
.rg{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin-top:8px}
.rg figure{background:#0e0d13;border-radius:6px;padding:6px;text-align:center}
.rg img{width:100%;max-width:96px;margin:0 auto}
.rg figcaption{font-size:11px;color:#7a7a8c;margin-top:4px}
.meta{font-size:12px;color:#8d8d9e;margin-top:8px;line-height:1.7}
.meta b{color:#c8c8d6;font-weight:600}
.pal{display:flex;flex-wrap:wrap;gap:3px;margin-top:6px}
.pal i{width:15px;height:15px;border-radius:3px;display:block;border:1px solid #00000060}
.ped{display:flex;align-items:center;gap:5px;flex-wrap:wrap;margin-bottom:10px}
.ped img{width:34px;height:34px;background:#0e0d13;border-radius:5px;cursor:pointer;
 border:2px solid #2a2935;image-rendering:pixelated}
.ped img:hover{border-color:#4d5bd6}.ped img.on{border-color:#6d7cff}
.ped img.he{border-color:#d6a24d}
.ped .hem{color:#d6a24d;font-size:12px;margin-left:-4px;margin-right:2px;align-self:flex-start}
.ped s{color:#5c5c6b;text-decoration:none;font-size:13px}
.ped span{color:#7a7a8c;font-size:12px;margin-left:6px}
.box{background:#191822;border:1px solid #2a2935;border-radius:8px;padding:10px;margin-top:14px}
.box h5{font-size:11px;text-transform:uppercase;color:#7a7a8c;letter-spacing:.04em;
 margin-bottom:8px;font-weight:700}
.rowf{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.rowf input[type=range]{flex:1;min-width:120px;padding:0;accent-color:#6d7cff}
.hint{font-size:12px;color:#8d8d9e;min-width:190px}
dialog{background:#1d1c26;color:#dcdce4;border:1px solid #34333f;border-radius:12px;
 padding:18px;max-width:660px}
dialog::backdrop{background:#000a}
.warn{background:#3a2a14;border:1px solid #6b4d1c;color:#ffcf8a;padding:8px 11px;
 border-radius:7px;font-size:13px;margin-top:8px}
.err{background:#3a1717;border:1px solid #6b2222;color:#ff9188}
.okmsg{background:#16311f;border:1px solid #24593a;color:#7ee2a8;padding:8px 11px;
 border-radius:7px;font-size:13px;margin-top:8px}
#status{font-size:12px;color:#8d8d9e}
.reflist{max-height:230px;overflow:auto;border:1px solid #2a2935;border-radius:7px;
 margin-top:8px}
.reflist a{display:block;padding:4px 8px;font-size:12px;color:#c2c2d0;cursor:pointer;
 white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.reflist a:hover{background:#23222e}.reflist a.on{background:#333150;color:#fff}
.ref{display:flex;gap:8px;align-items:center}
.ref img{width:34px;height:34px;background:#0e0d13;border-radius:5px}
table.lib{border-collapse:collapse;font-size:12px;margin-top:8px;width:100%}
table.lib td{padding:3px 8px 3px 0;border-bottom:1px solid #23222e;color:#a8a8ba}
.ed-wrap{display:flex;flex-direction:column;gap:8px;margin-top:10px}
.ed-bar{display:flex;gap:6px;align-items:center;flex-wrap:wrap}
.ed-tool{padding:4px 9px;font-size:12px;border-radius:5px;cursor:pointer;background:#24232e;border:1px solid #34333f;color:#dcdce4}
.ed-tool:hover{background:#2e2d3a}
.ed-tool.on{background:#4d5bd6;color:#fff;border-color:#5b68e0}
.ed-canvas-box{position:relative;background:#0e0d13;border:1px solid #2a2935;border-radius:6px;display:flex;justify-content:center;align-items:center;padding:12px;overflow:hidden;background-image:linear-gradient(45deg,#1b1a23 25%,transparent 25%),linear-gradient(-45deg,#1b1a23 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#1b1a23 75%),linear-gradient(-45deg,transparent 75%,#1b1a23 75%);background-size:16px 16px;background-position:0 0,0 8px,8px -8px,-8px 0}
#ed-canvas{image-rendering:pixelated;cursor:crosshair;box-shadow:0 4px 20px #0008;border:1px solid #444}
.pal-chip{width:18px;height:18px;border-radius:3px;cursor:pointer;border:2px solid transparent;display:inline-block}
.pal-chip.on{border-color:#fff;transform:scale(1.2)}
.qchip{width:16px;height:16px;border-radius:3px;cursor:pointer;display:inline-block;border:1px solid #00000060}
</style>
<header>
 <div class="hrow">
  <b>Sprite Studio</b>
  <input id="prompt" placeholder="energy drink creature with legs — anglicky">
  <input id="name" placeholder="jméno sady" style="width:120px">
  <select id="n"><option>4</option><option selected>6</option><option>8</option><option>12</option></select>
  <div style="display:flex;flex-direction:column;align-items:stretch;gap:2px">
   <span class="hint" id="cost" style="min-width:auto;text-align:center"></span>
   <button class="p" id="go">Generovat</button>
  </div>
  <button class="sm" id="btn-open-padlg" title="Převede český nápad na přesný SDXL pixel-art prompt">✨ Asistent promptu</button>
  <span id="status"></span>
 </div>
 <div class="hrow" id="row-warn" style="display:none">
  <span id="pwarn" style="background:#3a2a14;border:1px solid #6b4d1c;color:#ffcf8a;
   padding:5px 10px;border-radius:6px;font-size:12.5px;line-height:1.6"></span>
 </div>
 <div class="hrow">
  <label class="f">rozlišení
   <input id="size" list="sizes" value="32x32" style="width:96px"></label>
  <datalist id="sizes"></datalist>
  <span class="hint" id="sizeh" style="min-width:300px"></span>
  <label class="f">barev
   <input id="colors" type="number" min="4" max="96" value="40" style="width:64px"></label>
  <span class="hint" id="colh" style="min-width:230px"></span>
  <label class="f">zdroj
   <select id="src">
    <option value="rd">Retro Diffusion</option>
    <option value="sdxl">lokální SDXL</option>
   </select></label>
  <span class="hint" id="srch" style="flex:1"></span>
 </div>
 <div class="hrow" id="row-sdxl">
  <label class="f">LoRA <input type="range" id="lora" min="0" max="100" value="55"></label>
  <span class="hint" id="lorah" style="min-width:260px"></span>
 </div>
 <div class="hrow" id="row-rd">
  <span id="rdstate" class="hint" style="min-width:auto"></span>
  <button class="sm" id="rdstart">spustit server</button>
  <label class="f">kvalita <input type="range" id="rdq" min="1" max="8" value="6"></label>
  <span class="hint" id="rdqh" style="min-width:190px"></span>
  <span id="rdloras" style="display:flex;gap:8px;flex-wrap:wrap;align-items:center"></span>
 </div>
 <div class="hrow" id="row-ref">
  <label class="f">reference</label>
  <div class="ref"><img id="refthumb" style="display:none"><span class="hint"
    id="refname" style="min-width:auto">žádná</span></div>
  <button class="sm" id="refpick">vybrat…</button>
  <button class="sm" id="refoff">zrušit</button>
  <select id="refmode"></select>
  <span class="hint" id="refh" style="flex:1"></span>
 </div>
</header>
<div id="live">
 <img id="liveimg" alt="">
 <div class="t"><b id="livemsg"></b><span id="livenote"></span></div>
</div>
<nav id="nav"></nav>
<main id="main"></main>
<dialog id="dlg"></dialog>
<dialog id="rdlg">
 <h2>Reference</h2>
 <div class="sub">Jen soubory z assets/ a build/. Klikni na cestu, vybere se.</div>
 <input id="rq" placeholder="hledat v cestě, např. energy east" style="width:100%">
 <div class="reflist" id="rlist"></div>
 <div class="big" style="margin-top:10px"><img id="rprev" style="width:160px"></div>
 <div class="meta" id="rinfo"></div>
 <div style="margin-top:14px;text-align:right"><button onclick="rdlg.close()">Hotovo</button></div>
</dialog>
<dialog id="padlg" style="max-width:560px">
 <h2>✨ Gemini Prompt Asistent</h2>
 <div class="sub">Napiš český popis příšery (např. <i>fialový boss s monitory a velkým okem</i>). Asistent vytvoří přesný prompt pro SDXL pixel art podle pravidel hry.</div>
 <textarea id="pa-input" style="width:100%;height:80px;background:#24232e;color:#dcdce4;border:1px solid #34333f;border-radius:6px;padding:8px;font:inherit;margin-top:8px" placeholder="např. zelená energetická plechovka s pavoučíma nohama"></textarea>
 <div class="rowf" style="margin-top:10px">
   <button class="p" id="pa-go">✨ Vytvořit prompt</button>
   <span id="pa-status" class="hint"></span>
 </div>
 <div id="pa-result-box" style="display:none;margin-top:12px">
   <div style="font-size:12px;color:#8d8d9e">Výsledný SDXL prompt:</div>
   <div id="pa-res" style="background:#0e0d13;border:1px solid #2a2935;border-radius:6px;padding:9px;font-family:monospace;font-size:13px;color:#7ee2a8;margin-top:4px;word-break:break-word"></div>
   <div class="rowf" style="margin-top:8px">
     <button class="p sm" id="pa-apply">Použít v generátoru</button>
   </div>
 </div>
 <div style="margin-top:14px;text-align:right"><button onclick="padlg.close()">Zavřít</button></div>
</dialog>
<script>
const CFG=__CFG__;
let ST={art:[],gen:[],lib:[]}, sel=null, timers=[], sortByGrade=false;
let REF={path:'',mode:CFG.refmodes[0]};
const $=s=>document.querySelector(s);
const gcls=g=>g>=7?'g-hi':g>=4?'g-mid':'g-lo';
const esc=t=>String(t==null?'':t).replace(/[&<>"]/g,
  c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const enc=encodeURIComponent;
const post=async(u,b)=>(await fetch(u,{method:'POST',body:JSON.stringify(b)})).json();
const getj=async u=>(await fetch(u)).json();

async function load(){
  ST=await getj('/api/state');
  drawNav(); if(sel) open(sel.kind,sel.key); else if(ST.gen[0]) open('gen',ST.gen[0].name);
  else if(ST.art[0]) open('art',ST.art[0].id);
}
function drawNav(){
  let h='<h3>Generátor</h3>';
  h+=ST.gen.length?ST.gen.map(s=>`<a data-k="gen" data-i="${esc(s.name)}">${esc(s.name)}</a>`).join('')
    :'<a style="color:#5c5c6b;cursor:default">zatím nic</a>';
  h+='<h3>Hra</h3>'+ST.art.map(a=>`<a data-k="art" data-i="${esc(a.id)}">${esc(a.id)}</a>`).join('');
  h+=`<h3>PixelLab — laťka</h3><a data-k="lib" data-i="*">▦ všech ${ST.lib.length}</a>`
    +ST.lib.map(c=>`<a data-k="lib" data-i="${esc(c.slug)}" title="${esc(c.slug)}"
      >${esc(c.name)}</a>`).join('');
  $('#nav').innerHTML=h;
  document.querySelectorAll('nav a[data-k]').forEach(a=>
    a.onclick=()=>open(a.dataset.k,a.dataset.i));
  mark();
}
function mark(){document.querySelectorAll('nav a').forEach(a=>
  a.classList.toggle('on',sel&&a.dataset.k===sel.kind&&a.dataset.i===sel.key));}

function open(kind,key){
  sel={kind,key}; mark(); timers.forEach(clearInterval); timers=[];
  if(kind==='art')drawArt(key); else if(kind==='gen')drawGen(key); else drawLib(key);
}

// Prehravac: velky obrazek + prouzek framu, kazda sada bezi svym tempem jako ve hre.
function player(id,title,urls,animKey,setname){
  const expBtn=setname&&animKey?`<button class="sm" onclick="exportSheet('${esc(setname)}','${esc(animKey)}')" style="margin-left:auto;padding:2px 6px;font-size:11px">🎞️ Spritesheet</button>`:'';
  return `<div class="setbox"><div style="display:flex;align-items:center"><h4>${esc(title)}</h4>${expBtn}</div>
    <div class="big"><img id="pl-${id}" src="${urls[0]}" style="width:128px"></div>
    <div class="strip" id="st-${id}">${urls.map((u,i)=>
      `<img src="${u}" data-i="${i}" class="${i?'':'on'}">`).join('')}</div></div>`;
}
async function exportSheet(setname, animKey){
  const r = await post('/api/export-sheet', {set: setname, anim_key: animKey});
  if(r.ok){
    window.open(r.url, '_blank');
  } else {
    alert(r.msg || 'Chyba exportu');
  }
}
function runPlayer(id,urls,fps,bag){
  if(urls.length<2)return; let i=0;
  bag.push(setInterval(()=>{
    const im=$('#pl-'+id); if(!im)return;
    i=(i+1)%urls.length; im.src=urls[i];
    document.querySelectorAll(`#st-${id} img`).forEach((e,j)=>e.classList.toggle('on',i===j));
  },1000/(fps||12)));
}
function wireStrips(root){
  document.querySelectorAll(root+' .strip img').forEach(im=>im.onclick=e=>{
    e.stopPropagation(); detail(new URL(im.src).pathname,null,null);});
}

function drawArt(id){
  const a=ST.art.find(x=>x.id===id); if(!a)return;
  const order=['south','north','east','west','attack','death'];
  const keys=Object.keys(a.sets).sort((x,y)=>order.indexOf(x)-order.indexOf(y));
  let h=`<h2>${esc(id)}</h2><div class="sub">${keys.length} sad — klikni na frame pro detail</div><div class="row">`;
  keys.forEach(k=>{h+=player('a'+k,`${k} · ${a.sets[k].length} framů`,
    a.sets[k].map(n=>'/img/art/'+n));});
  $('#main').innerHTML=h+'</div>';
  keys.forEach(k=>runPlayer('a'+k,a.sets[k].map(n=>'/img/art/'+n),12,timers));
  wireStrips('#main');
}

function drawGen(name){
  const s=ST.gen.find(x=>x.name===name); if(!s)return;
  const g=s.gen||{};
  const line=[s.prompt,g.size?`${g.size}`:'',g.lora!=null?`LoRA ${g.lora}`:'',
    g.ref?`ref ${g.ref} (${g.ref_mode})`:''].filter(Boolean).map(esc).join(' · ');
  // POZOR: vychozi poradi je poradi VZNIKU, ne podle znamky. score() trestá prekroceni
  // rozpoctu palety tak tvrde, ze razeni podle ni davalo nahoru nejplossi sprite.
  const cands=[...s.cands];
  if(sortByGrade)cands.sort((a,b)=>(s.scores[b]?.grade||0)-(s.scores[a]?.grade||0));
  let h=`<h2>${esc(name)}</h2><div class="sub">${line||''}</div>
   <div class="hrow" style="margin-bottom:12px">
    <button class="sm" id="srt">${sortByGrade?'řadit podle vzniku':'řadit podle známky'}</button>
    <span class="hint" style="flex:1">Známka je pomocná míra použitelnosti (barvy, šum,
      plocha), ne kvalita kresby — nejvyšší mívá ten nejplošší sprite.</span></div>
   <div class="grid">`;
  cands.forEach(c=>{const gr=s.scores[c]?.grade;
    h+=`<div class="card" data-c="${esc(c)}"><img src="/img/gen/${enc(name)}/${enc(c)}">
      <div class="n"><span>${esc(c.replace('cand_','#').replace('.png',''))}</span>
      ${gr!=null?`<span class="badge ${gcls(gr)}">${gr}</span>`:''}</div></div>`;});
  $('#main').innerHTML=h+'</div>';
  $('#srt').onclick=()=>{sortByGrade=!sortByGrade;drawGen(name);};
  document.querySelectorAll('.card').forEach(c=>c.onclick=()=>
    detail('/img/gen/'+enc(name)+'/'+enc(c.dataset.c),name,c.dataset.c));
}

// ------------------------------------------------------------------ knihovna PixelLabu

async function drawLib(key){
  if(key==='*')return drawLibAll();
  const c=ST.lib.find(x=>x.slug===key); if(!c)return drawLibAll();
  const d=await getj('/api/lib?slug='+enc(key));
  const u=f=>'/img/lib/'+enc(key)+'/'+f.split('/').map(enc).join('/');
  let h=`<h2>${esc(c.name)}</h2><div class="sub">${esc(c.size)} · ${esc(c.dirs)} ·
    build/pixellab/${esc(c.slug)} — klikni na frame pro míry</div>`;
  const rot=CFG.dirs.filter(x=>d.rot&&d.rot[x]).concat(
    Object.keys(d.rot||{}).filter(x=>CFG.dirs.indexOf(x)<0));
  if(rot.length)h+=`<div class="setbox"><h4>rotace · ${rot.length} směrů</h4>
    <div class="rg">${rot.map(k=>`<figure><img src="${u(d.rot[k])}">
      <figcaption>${esc(k)}</figcaption></figure>`).join('')}</div></div>`;
  const players=[];
  h+='<div class="row" style="margin-top:16px">';
  Object.entries(d.anims||{}).forEach(([an,dirs])=>{
    Object.entries(dirs).forEach(([dir,files])=>{
      const id='l'+players.length, urls=files.map(u);
      players.push([id,urls]);
      h+=player(id,`${an} · ${dir} · ${files.length}f`,urls);
    });
  });
  $('#main').innerHTML=h+'</div>';
  players.forEach(([id,urls])=>runPlayer(id,urls,10,timers));
  wireStrips('#main');
}

async function drawLibAll(){
  let h=`<h2>PixelLab — referenční laťka</h2>
   <div class="sub">${ST.lib.length} postav v build/pixellab. Tohle je cíl, ne inspirace:
     vedle vlastních výtvorů má být vidět, na co se míří.</div>
   <div class="box"><h5>Stáhnout další</h5>
    <div class="rowf"><button id="lls">Načíst seznam ze serveru</button>
     <span class="hint" id="llh" style="flex:1">Použije se token z .pixellab_token
       (nebo PIXELLAB_TOKEN).</span></div>
    <div id="llist"></div></div>
   <div class="grid" style="margin-top:16px">`;
  ST.lib.forEach(c=>{
    const src=c.thumb?'/img/lib/'+enc(c.slug)+'/'+c.thumb.split('/').map(enc).join('/'):'';
    h+=`<div class="card" data-s="${esc(c.slug)}">
      ${src?`<img src="${src}">`:'<div class="big" style="height:80px">bez náhledu</div>'}
      <div class="n"><span title="${esc(c.name)}">${esc(c.name)}</span>
        <span class="badge g-mid">${esc(c.size||'?')}</span></div></div>`;});
  $('#main').innerHTML=h+'</div>';
  document.querySelectorAll('.card[data-s]').forEach(c=>c.onclick=()=>
    open('lib',c.dataset.s));
  $('#lls').onclick=async()=>{
    $('#lls').disabled=true;
    const r=await post('/api/pull',{action:'list'});
    if(r.err){$('#llh').textContent=r.err;$('#lls').disabled=false;return;}
    pollJob(async()=>{$('#lls').disabled=false;await showRemote();});
  };
}

async function showRemote(){
  const r=await getj('/api/remote');
  if(r.err){$('#llh').textContent=r.err;return;}
  const have=new Set(ST.lib.map(c=>c.id).filter(Boolean));
  $('#llh').textContent=`${r.rows.length} postav na serveru, ${have.size} už doma`;
  $('#llist').innerHTML='<table class="lib">'+r.rows.map(x=>
    `<tr><td>${esc(x.name.slice(0,70))}</td><td>${esc(x.size)}</td>
     <td>${have.has(x.id)?'<span style="color:#7ee2a8">doma</span>':
      `<button class="sm" data-id="${esc(x.id)}">stáhnout</button>`}</td></tr>`).join('')
    +'</table>';
  document.querySelectorAll('#llist button[data-id]').forEach(b=>b.onclick=async()=>{
    b.disabled=true;
    const q=await post('/api/pull',{action:'pull',id:b.dataset.id});
    if(q.err){$('#llh').textContent=q.err;b.disabled=false;return;}
    pollJob(async()=>{await load();await drawLibAll();await showRemote();});
  });
}

// ------------------------------------------------------------------ detail kandidata

// Sila prepisu neni cislo, ktere by nekomu neco rikalo — popisek rika, co se stane.
const sLabel=v=>v<.25?'drobná úprava, tvar zůstane':v<.4?'znatelná změna, silueta se drží'
  :v<.5?'velká změna, zůstane barevnost':'skoro nový sprite';
// Prehravani v dialogu ma vlastni timery: ty v `timers` maze prepnuti v levem sloupci,
// ale dialog se otevira a zavira nezavisle na nem.
let dtimers=[];
function stopD(){dtimers.forEach(clearInterval);dtimers=[];}
function busy(x){['#go','#rgo','#aw','#ai','#ac','#rot'].forEach(s=>{
  const e=$(s);if(e)e.disabled=x;});}

async function detail(src,setname,cand){
  stopD();
  const m=await getj('/api/measure?src='+enc(src));
  const s=setname?ST.gen.find(x=>x.name===setname):null;
  const stem=cand?cand.replace(/\.png$/,''):'';
  const anims=s?Object.entries(s.anims||{}).filter(
    ([k,f])=>k.indexOf(stem+'_')===0&&f.length):[];
  const rots=s&&s.dirs?(s.dirs[stem]||{}):{};
  let chain=[];
  if(setname&&cand)chain=(await getj('/api/lineage?set='+enc(setname)+
    '&cand='+enc(cand))).chain||[];
  const gu=f=>'/img/gen/'+enc(setname)+'/'+enc(f);

  const ped=chain.length?`<div class="ped">`+chain.map((c,i)=>(i?'<s>→</s>':'')+
      `<img src="${gu(c.cand)}" data-c="${esc(c.cand)}"
        class="${c.cand===cand?'on':''}${c.hand_edited?' he':''}"
        title="${esc(c.prompt)}${c.strength!=null?' · síla '+c.strength:''}${
        c.hand_edited?' · RUČNĚ PŘEMALOVÁNO '+c.edits+'× (potomci vznikli z jiných pixelů)':''}">`
      +(c.hand_edited?'<b class="hem" title="ručně přemalováno">✎</b>':'')).join('')+
      `<span>${chain.length>1?'rodokmen — klikni na předka'
        :'kořen rodokmenu'}</span></div>`:'';

  const tune=setname?`<div class="box"><h5>Doladit promptem</h5>
    <input id="rp" style="width:100%" placeholder="co změnit — anglicky, např. bigger angry eyes">
    <div class="rowf" style="margin-top:8px">
      <input type="range" id="rs" min="15" max="60" value="35">
      <span class="hint" id="rsl"></span>
      <button class="p" id="rgo">Doladit</button></div>
    <div class="meta">Vznikne <b>dítě</b> tohohle spritu: model dostane jeho pixely jako
      předlohu a přepíše z nich jen tolik, kolik dovolí síla. Paleta se zamkne na rodiče,
      aby se příšera po pár krocích nezměnila v jinou.</div></div>`:'';

  const dirKeys=CFG.dirs.filter(k=>rots[k]).concat(
    Object.keys(rots).filter(k=>CFG.dirs.indexOf(k)<0));
  const rotbox=setname?`<div class="box"><h5>Rotace</h5>
    <div class="rowf"><button id="rot">8 směrů</button>
      <select id="rot-mode" style="width:auto">
        <option value="pose" selected>kostra — pohled se opravdu změní</option>
        <option value="ip">IP-Adapter — varianty téhož pohledu</option>
        <option value="plain">bez reference — varianty téhož pohledu</option>
      </select>
      <span class="hint" style="flex:1">Pohled mění jen <b>kostra</b>: ta ho určuje z úhlu a ControlNet ho vynutí. Zbylé dvě volby překreslují čelní sprite, takže vyrobí varianty téhož pohledu — změřeno, viz docs/art/rotace.md.</span></div>
    ${dirKeys.length?`<div class="rg">${dirKeys.map(k=>`<figure>
      <img src="${gu(rots[k])}"><figcaption>${esc(k)}</figcaption></figure>`).join('')}
      </div>`:''}</div>`:'';

  const puppet=setname?`<div class="box"><h5>Procedurální animace (bez AI, okamžitě)</h5>
     <div class="rowf" style="flex-wrap:wrap;gap:6px">
       <button id="pw">chůze (jih)</button>
       <button id="pws">chůze (bok)</button>
       <button id="pwn">chůze (záda)</button>
       <button id="pi">idle</button>
       <button id="pa">útok</button>
       <button id="pd">smrt</button>
       <button id="ph">zásah</button>
       <label class="f">intenzita <input type="range" id="pint" min="1" max="5" value="2"></label>
       <span class="hint" id="pintl" style="min-width:40px">2 px</span>
     </div>
     <div class="rowf" style="margin-top:8px">
       <button class="p" id="p-full" style="background:#4a3fb5;border-color:#5c50d6">🎬 Sestavit kompletní postavu (všechny animace)</button>
       <label class="f"><input type="checkbox" id="p-full-dirs" style="width:auto"> včetně rotací (bok/záda)</label>
     </div>
     <div class="meta">Rozřeže sprite na vrstvy (hlava/trup/nohy) a pohybuje jimi podle šablony. <b>Žádná GPU, žádné čekání</b> — hotovo za milisekundy, nulový pixel boiling.</div></div>`:'';

  const anim=setname?`<div class="box"><h5>AI Animace (vyžaduje GPU)</h5>
     <div class="rowf"><button id="aw">chůze</button>
       <button id="ai">idle</button>
       <span class="hint" style="flex:1">Všechny framy vznikají z tohohle spritu, takže
         si zůstanou podobné.</span></div>
     <div class="rowf" style="margin-top:8px">
       <input id="ap" style="flex:1;min-width:220px"
         placeholder="vlastní pózy, oddělené středníkem — anglicky">
       <button id="ac">Vlastní</button></div>
     <div class="meta">Např. <b>crouching low; jumping, legs tucked; landing, knees
       bent</b> — každá póza je jeden frame, v tomhle pořadí.</div>
     ${anims.map(([k,f])=>player('d'+k.replace(/[^a-zA-Z0-9]/g,''),
       k.slice(stem.length+1)+' · '+f.length+' framů',f.map(gu),k,setname)).join('')}</div>`:'';

   // Reference comparison options
   const artRefs = ST.art.map(a => ({name: 'Hra: ' + a.id, src: '/img/art/' + (a.sets.south ? a.sets.south[0] : (Object.values(a.sets)[0]||[])[0])})).filter(x => x.src);
   const libRefs = ST.lib.filter(l => l.thumb).map(l => ({name: 'PixelLab: ' + l.name, src: '/img/lib/' + enc(l.slug) + '/' + l.thumb.split('/').map(enc).join('/')}));
   const genRefs = s ? s.cands.filter(c => c !== cand).map(c => ({name: 'Kandidát: ' + c, src: gu(c)})) : [];
   const allRefs = [...genRefs, ...artRefs, ...libRefs];

   const cmpbox = `<div class="box"><h5>Porovnání s referencí (Side-by-Side & Overlay)</h5>
     <div class="rowf">
       <select id="cmp-pick" style="flex:1">
         <option value="">-- Vyber referenční sprite k porovnání --</option>
         ${allRefs.map(r => `<option value="${esc(r.src)}">${esc(r.name)}</option>`).join('')}
       </select>
       <label class="f">Průhlednost <input type="range" id="cmp-alpha" min="0" max="100" value="0"></label>
     </div>
     <div id="cmp-view" style="display:none;margin-top:10px">
       <div class="row" style="margin-bottom:0">
         <div style="flex:1;text-align:center">
           <div style="font-size:11px;color:#7a7a8c;margin-bottom:4px">TENTO KANDIDÁT</div>
           <div class="big" style="position:relative;min-height:160px">
             <img src="${src}" id="cmp-img-cand" style="width:160px;image-rendering:pixelated">
             <img src="" id="cmp-img-over" style="width:160px;image-rendering:pixelated;position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);opacity:0;pointer-events:none">
           </div>
         </div>
         <div style="flex:1;text-align:center">
           <div style="font-size:11px;color:#7a7a8c;margin-bottom:4px" id="cmp-ref-title">REFERENCE</div>
           <div class="big" style="min-height:160px">
             <img src="" id="cmp-img-ref" style="width:160px;image-rendering:pixelated">
           </div>
         </div>
       </div>
       <div class="meta" id="cmp-metrics"></div>
     </div>
   </div>`;

  const editbox=setname?`<div class="box">
    <div class="rowf"><button id="btn-open-editor" class="p">✏️ Pixel Editor (oprava pixelů & inpaint maska)</button>
      <span class="hint" style="flex:1">Tužka, guma, kapátko, výplň, maska pro inpaint a zrcadlení pro ruční úpravy detailů.</span></div>
    <div id="editor-area" style="display:none" class="ed-wrap">
      <div class="ed-bar">
        <button class="ed-tool on" data-tool="pen" id="tool-pen">✏️ Tužka</button>
        <button class="ed-tool" data-tool="eraser" id="tool-eraser">🧽 Guma</button>
        <button class="ed-tool" data-tool="picker" id="tool-picker">💧 Kapátko</button>
        <button class="ed-tool" data-tool="fill" id="tool-fill">🪣 Výplň</button>
        <button class="ed-tool" data-tool="mask" id="tool-mask" style="color:#ff6b6b">🎭 Maska</button>
        <button class="sm" id="btn-clear-mask" title="Smazat masku">🧹 Smazat masku</button>
        <button class="ed-tool" data-tool="flip" id="tool-flip">↔️ Převrátit</button>
        <span style="flex:1"></span>
        <button class="sm" id="btn-undo" title="Zpět (Ctrl+Z)">↩️ Zpět</button>
        <button class="sm" id="btn-redo" title="Vpřed (Ctrl+Y)">↪️ Vpřed</button>
      </div>
      <div class="ed-canvas-box"><canvas id="ed-canvas"></canvas></div>
      <div class="ed-bar" style="align-items:center">
        <label class="f" style="color:#dcdce4">Barva: <input type="color" id="ed-col" value="#ffffff" style="width:32px;height:24px;padding:0;cursor:pointer"></label>
        <div id="ed-pal-list" style="display:flex;gap:3px;flex-wrap:wrap;align-items:center"></div>
        <span style="flex:1"></span>
        <button class="p sm" id="btn-save-edit">💾 Uložit úpravy</button>
        <button class="sm" id="btn-close-editor">❌ Zavřít editor</button>
      </div>
      <div id="ed-inpaint-bar" style="display:flex;gap:6px;align-items:center;margin-top:8px;padding-top:8px;border-top:1px solid #363644;flex-wrap:wrap">
        <span style="font-size:12px;color:#ff9d9d;font-weight:bold">🎭 Inpaint:</span>
        <input id="ed-inpaint-prompt" placeholder="co nakreslit do označené masky — např. skull helmet with horns" style="flex:1;min-width:180px">
        <label class="f" style="font-size:12px">síla <input type="range" id="ed-inpaint-str" min="30" max="95" value="75" style="width:60px"></label>
        <span class="hint" id="ed-inpaint-str-l" style="min-width:28px">0.75</span>
        <button class="p sm" id="btn-do-inpaint" style="background:#7c3aed;border-color:#8b5cf6">🎨 Přegenerovat masku</button>
      </div>
    </div></div>`:'';

  const variantbox=setname?`<div class="box"><h5>Paletové proměny & Varianty (bez AI)</h5>
    <div class="rowf">
      <input type="color" id="vcol" value="#ff3b30" style="width:36px;height:28px;padding:0;cursor:pointer">
      <div style="display:flex;gap:4px;align-items:center" id="quickchips">
        <i class="qchip" data-c="#ff3b30" style="background:#ff3b30" title="Oheň"></i>
        <i class="qchip" data-c="#34c759" style="background:#34c759" title="Kyselina"></i>
        <i class="qchip" data-c="#007aff" style="background:#007aff" title="Kybernetická"></i>
        <i class="qchip" data-c="#ff9500" style="background:#ff9500" title="Elektrická"></i>
        <i class="qchip" data-c="#af52de" style="background:#af52de" title="Temnota / Void"></i>
        <i class="qchip" data-c="#ffcc00" style="background:#ffcc00" title="Zlatá"></i>
      </div>
      <button id="vbtn-target">Přebarvit na odstín</button>
      <button id="vbtn-t2">Tier 2 (+kontrast & zlato)</button>
      <button id="vbtn-t3">Tier 3 (Boss aura)</button>
    </div>
    <div class="rowf" style="margin-top:8px">
      <label class="f">Posun Hue <input type="range" id="vshift" min="0" max="360" value="60"></label>
      <span class="hint" id="vshiftl" style="min-width:60px">60°</span>
      <button id="vbtn-shift">Posunout odstín</button>
    </div>
    <div class="meta">Oklch přemapování: <b>zachová přesný plastický tvar, světlo a stín</b>.
      Obrysy a odlesky zůstanou chráněné. Vznikne nová varianta připravená k použití.</div></div>`:'';

  const gnote=m.grid?'':`<div class="warn">${esc(m.gridnote||'')}</div>`;

  $('#dlg').innerHTML=ped+`<div class="big"><img src="${src}" style="width:min(340px,60vw)"></div>
   <div class="meta"><b>${m.w}×${m.h}</b> · <b>${m.cols}</b> barev
     (rozpočet ${m.budget}) · <b>${m.iso}%</b> šumu
     <div class="pal">${(m.pal||[]).map(c=>`<i style="background:${esc(c)}"></i>`).join('')}</div></div>
   ${editbox}${variantbox}${cmpbox}${gnote}${tune}${rotbox}${puppet}${anim}
   ${setname?`<div class="box"><h5>Do hry</h5>
     <div class="rowf">
       <input id="tgt" placeholder="id do hry, např. energy_drink_b" style="flex:1" value="${esc(setname)}">
       <label class="f"><input type="checkbox" id="lockp" style="width:auto"> zamknout na master paletu</label>
       <label class="f"><input type="checkbox" id="ctres" checked style="width:auto"> vytvořit .tres</label>
       <button class="p" id="inst">Nainstalovat frame</button>
       <button class="p" id="inst-set" style="background:#2a7a4c;border-color:#389a62">📦 Nainstalovat celou sadu</button>
     </div>
     <div class="meta" id="imsg">Nainstaluje základní frame, všechny animace (chůze, útok, smrt) i směry podle schématu hry do assets/distractions/.</div></div>`:''}
   <div style="margin-top:16px;text-align:right"><button onclick="dlg.close()">Zavřít</button></div>`;
  // showModal na uz otevrenem dialogu vyhodi vyjimku, a rodokmen se prepina PRAVE
  // uvnitr otevreneho dialogu.
  if(!$('#dlg').open)$('#dlg').showModal();
  $('#dlg').onclose=stopD;

  anims.forEach(([k,f])=>runPlayer('d'+k.replace(/[^a-zA-Z0-9]/g,''),f.map(gu),10,dtimers));
  document.querySelectorAll('#dlg .strip img').forEach(im=>im.onclick=e=>{
    e.stopPropagation();});

  if(!setname)return;
  document.querySelectorAll('.ped img').forEach(im=>im.onclick=()=>
    detail(gu(im.dataset.c),setname,im.dataset.c));

  const sl=$('#rs'), lab=()=>$('#rsl').textContent=
    (sl.value/100).toFixed(2)+' — '+sLabel(sl.value/100);
  sl.oninput=lab; lab();

  const again=(j,fallback)=>detail(gu(j.cand||fallback),setname,j.cand||fallback);
  $('#rgo').onclick=async()=>{
    const pr=$('#rp').value.trim();
    if(!pr){$('#rp').focus();return;}
    const r=await post('/api/refine',{set:setname,cand,prompt:pr,strength:sl.value/100});
    if(r.err){$('#status').textContent=r.err;return;}
    busy(true);
    // Detail se prepne na dite: dalsi doladeni uz pokracuje z nej, ne z rodice.
    pollJob(async j=>{busy(false); await load(); again(j,cand);});
  };
  const startAnim=async body=>{
    const r=await post('/api/animate',Object.assign({set:setname,cand,strength:0.3},body));
    if(r.err){$('#status').textContent=r.err;return;}
    busy(true);
    pollJob(async()=>{busy(false); await load(); detail(src,setname,cand);});
  };
  $('#aw').onclick=()=>startAnim({kind:'walk'});
  $('#ai').onclick=()=>startAnim({kind:'idle'});
  $('#ac').onclick=()=>{
    const p=$('#ap').value.split(';').map(x=>x.trim()).filter(Boolean);
    if(!p.length){$('#ap').focus();return;}
    startAnim({poses:p});
  };
  $('#rot').onclick=async()=>{
    const mode = $('#rot-mode') ? $('#rot-mode').value : 'pose';
    // Sila znamena u kazdeho rezimu neco jineho: u kostry je to sila REFERENCE (identita),
    // u zbylych dvou sila prekresleni. Proto tri cisla a ne jedno.
    const sila = {pose:0.60, ip:0.50, plain:0.45}[mode];   // pose = gen.POSE_IP_SCALE
    const r=await post('/api/rotate',{set:setname,cand,strength:sila,mode:mode});
    if(r.err){$('#status').textContent=r.err;return;}
    busy(true);
    pollJob(async()=>{busy(false); await load(); detail(src,setname,cand);});
  };

  // Proceduralni animace
  const pintsl=$('#pint'), pintlab=()=>$('#pintl').textContent=pintsl.value+' px';
  if(pintsl){pintsl.oninput=pintlab; pintlab();}
  const startPuppet=async kind=>{
    const r=await post('/api/puppet-animate',{set:setname,cand,kind,
      intensity:+$('#pint').value});
    if(!r.ok){$('#status').textContent=r.msg;return;}
    $('#status').textContent='hotovo — '+r.msg;
    await load(); detail(src,setname,cand);
  };
  if($('#pw'))$('#pw').onclick=()=>startPuppet('walk');
  if($('#pws'))$('#pws').onclick=()=>startPuppet('walk_side');
  if($('#pwn'))$('#pwn').onclick=()=>startPuppet('walk_north');
  if($('#pi'))$('#pi').onclick=()=>startPuppet('idle');
  if($('#pa'))$('#pa').onclick=()=>startPuppet('attack');
  if($('#pd'))$('#pd').onclick=()=>startPuppet('death');
  if($('#ph'))$('#ph').onclick=()=>startPuppet('hit');
  if($('#p-full'))$('#p-full').onclick=async()=>{
    $('#p-full').disabled=true;
    const r=await post('/api/full-character',{set:setname,cand,
      include_dirs:$('#p-full-dirs')?$('#p-full-dirs').checked:false});
    $('#p-full').disabled=false;
    if(!r.ok){$('#status').textContent=r.msg;return;}
    $('#status').textContent='hotovo — '+r.msg;
    await load(); detail(src,setname,cand);
  };

  // Varianty a prebarveni
  const vshift=$('#vshift'), vshiftl=()=>$('#vshiftl').textContent=vshift.value+'°';
  if(vshift){vshift.oninput=vshiftl; vshiftl();}
  document.querySelectorAll('.qchip').forEach(c=>c.onclick=()=>{
    $('#vcol').value=c.dataset.c;
  });
  const doRecolor=async(mode,params)=>{
    const r=await post('/api/recolor',Object.assign({set:setname,cand,mode},params));
    if(!r.ok){$('#status').textContent=r.msg;return;}
    $('#status').textContent='hotovo — '+r.msg;
    await load(); detail(gu(r.cand),setname,r.cand);
  };
  if($('#vbtn-target'))$('#vbtn-target').onclick=()=>doRecolor('target',{target_color:$('#vcol').value});
  if($('#vbtn-t2'))$('#vbtn-t2').onclick=()=>doRecolor('tier2',{});
  if($('#vbtn-t3'))$('#vbtn-t3').onclick=()=>doRecolor('tier3',{});
  if($('#vbtn-shift'))$('#vbtn-shift').onclick=()=>doRecolor('shift',{hue_shift:+$('#vshift').value});

  // Pixel Editor Logic
  let edState = null;
  const initEditor=()=>{
    const cvs=$('#ed-canvas'), ctx=cvs.getContext('2d');
    const w=m.w||32, h=m.h||32;
    const scale = Math.max(6, Math.min(14, Math.floor(320 / Math.max(w, h))));
    cvs.width = w * scale; cvs.height = h * scale;
    cvs.style.width = (w * scale) + 'px'; cvs.style.height = (h * scale) + 'px';

    const offC = document.createElement('canvas');
    offC.width = w; offC.height = h;
    const offCtx = offC.getContext('2d');

    const maskC = document.createElement('canvas');
    maskC.width = w; maskC.height = h;
    const maskCtx = maskC.getContext('2d');

    const img = new Image();
    img.crossOrigin = "anonymous";
    img.onload = () => {
      offCtx.clearRect(0, 0, w, h);
      offCtx.drawImage(img, 0, 0, w, h);
      maskCtx.clearRect(0, 0, w, h);
      edState = {
        w, h, scale, cvs, ctx, offC, offCtx, maskC, maskCtx,
        tool: 'pen', color: $('#ed-col').value,
        history: [offCtx.getImageData(0, 0, w, h)],
        histIdx: 0, drawing: false
      };
      renderCanvas();
      renderEdPalette();
    };
    img.src = src;

    const renderCanvas = () => {
      if(!edState) return;
      ctx.imageSmoothingEnabled = false;
      ctx.clearRect(0, 0, cvs.width, cvs.height);
      ctx.drawImage(offC, 0, 0, cvs.width, cvs.height);
      // Maska overlay (cervena polopruhledna)
      ctx.save();
      ctx.globalAlpha = 0.55;
      ctx.drawImage(maskC, 0, 0, cvs.width, cvs.height);
      ctx.restore();
      // Pixel grid
      ctx.strokeStyle = "rgba(255, 255, 255, 0.12)";
      ctx.lineWidth = 1;
      for(let x=0; x<=w; x++) {
        ctx.beginPath(); ctx.moveTo(x*scale+0.5, 0); ctx.lineTo(x*scale+0.5, h*scale); ctx.stroke();
      }
      for(let y=0; y<=h; y++) {
        ctx.beginPath(); ctx.moveTo(0, y*scale+0.5); ctx.lineTo(w*scale, y*scale+0.5); ctx.stroke();
      }
    };

    const pushHist = () => {
      if(!edState) return;
      edState.history = edState.history.slice(0, edState.histIdx + 1);
      edState.history.push(offCtx.getImageData(0, 0, w, h));
      if(edState.history.length > 30) edState.history.shift();
      edState.histIdx = edState.history.length - 1;
    };

    const applyPixel = (px, py) => {
      if(px < 0 || px >= w || py < 0 || py >= h) return;
      if(edState.tool === 'mask') {
        maskCtx.fillStyle = '#ff2222';
        maskCtx.fillRect(px, py, 1, 1);
      } else if(edState.tool === 'pen') {
        offCtx.fillStyle = edState.color;
        offCtx.fillRect(px, py, 1, 1);
      } else if(edState.tool === 'eraser') {
        offCtx.clearRect(px, py, 1, 1);
      } else if(edState.tool === 'picker') {
        const id = offCtx.getImageData(px, py, 1, 1).data;
        if(id[3] > 0) {
          const hex = "#" + ((1<<24)+(id[0]<<16)+(id[1]<<8)+id[2]).toString(16).slice(1);
          edState.color = hex;
          $('#ed-col').value = hex;
          renderEdPalette();
        }
      } else if(edState.tool === 'fill') {
        floodFill(px, py, edState.color);
      }
      renderCanvas();
    };

    const floodFill = (startX, startY, fillHex) => {
      const imgData = offCtx.getImageData(0, 0, w, h);
      const data = imgData.data;
      const idx = (startY * w + startX) * 4;
      const sr = data[idx], sg = data[idx+1], sb = data[idx+2], sa = data[idx+3];
      const fr = parseInt(fillHex.slice(1,3), 16), fg = parseInt(fillHex.slice(3,5), 16), fb = parseInt(fillHex.slice(5,7), 16), fa = 255;
      if(sr === fr && sg === fg && sb === fb && sa === fa) return;
      const match = (x, y) => {
        const i = (y * w + x) * 4;
        return data[i]===sr && data[i+1]===sg && data[i+2]===sb && data[i+3]===sa;
      };
      const q = [[startX, startY]];
      const seen = new Uint8Array(w * h);
      while(q.length) {
        const [x, y] = q.pop();
        const pidx = y * w + x;
        if(seen[pidx]) continue;
        seen[pidx] = 1;
        const i = pidx * 4;
        data[i] = fr; data[i+1] = fg; data[i+2] = fb; data[i+3] = fa;
        if(x > 0 && match(x-1, y)) q.push([x-1, y]);
        if(x < w-1 && match(x+1, y)) q.push([x+1, y]);
        if(y > 0 && match(x, y-1)) q.push([x, y-1]);
        if(y < h-1 && match(x, y+1)) q.push([x, y+1]);
      }
      offCtx.putImageData(imgData, 0, 0);
    };

    const getCoords = e => {
      const r = cvs.getBoundingClientRect();
      const clientX = e.clientX || (e.touches && e.touches[0].clientX);
      const clientY = e.clientY || (e.touches && e.touches[0].clientY);
      const x = Math.floor((clientX - r.left) / scale);
      const y = Math.floor((clientY - r.top) / scale);
      return [x, y];
    };

    cvs.onmousedown = e => {
      if(!edState) return;
      edState.drawing = true;
      const [x, y] = getCoords(e);
      applyPixel(x, y);
    };
    window.onmousemove = e => {
      if(!edState || !edState.drawing) return;
      if(edState.tool === 'fill' || edState.tool === 'picker') return;
      const [x, y] = getCoords(e);
      applyPixel(x, y);
    };
    window.onmouseup = () => {
      if(edState && edState.drawing) {
        edState.drawing = false;
        if(edState.tool !== 'mask') pushHist();
      }
    };

    const renderEdPalette = () => {
      const palBox = $('#ed-pal-list'); if(!palBox) return;
      palBox.innerHTML = (m.pal||[]).map(c =>
        `<i class="pal-chip ${c===edState.color?'on':''}" style="background:${esc(c)}" data-c="${esc(c)}"></i>`
      ).join('');
      palBox.querySelectorAll('.pal-chip').forEach(chip => {
        chip.onclick = () => {
          edState.color = chip.dataset.c;
          $('#ed-col').value = chip.dataset.c;
          renderEdPalette();
        };
      });
    };

    document.querySelectorAll('.ed-tool').forEach(b => {
      b.onclick = () => {
        document.querySelectorAll('.ed-tool').forEach(x => x.classList.remove('on'));
        b.classList.add('on');
        const tool = b.dataset.tool;
        if(tool === 'flip') {
          // Flip horizontal immediately
          const cur = offCtx.getImageData(0, 0, w, h);
          const next = offCtx.createImageData(w, h);
          for(let y=0; y<h; y++) {
            for(let x=0; x<w; x++) {
              const srcI = (y * w + x) * 4;
              const dstI = (y * w + (w - 1 - x)) * 4;
              next.data[dstI] = cur.data[srcI];
              next.data[dstI+1] = cur.data[srcI+1];
              next.data[dstI+2] = cur.data[srcI+2];
              next.data[dstI+3] = cur.data[srcI+3];
            }
          }
          offCtx.putImageData(next, 0, 0);
          renderCanvas();
          pushHist();
        } else {
          edState.tool = tool;
        }
      };
    });

    if($('#btn-clear-mask')) {
      $('#btn-clear-mask').onclick = () => {
        maskCtx.clearRect(0, 0, w, h);
        renderCanvas();
      };
    }
    if($('#ed-inpaint-str')) {
      $('#ed-inpaint-str').oninput = () => {
        $('#ed-inpaint-str-l').textContent = (+$('#ed-inpaint-str').value / 100).toFixed(2);
      };
    }
    if($('#btn-do-inpaint')) {
      $('#btn-do-inpaint').onclick = async () => {
        const pr = ($('#ed-inpaint-prompt').value || '').trim();
        if(!pr) { $('#ed-inpaint-prompt').focus(); return; }
        const mData = maskCtx.getImageData(0, 0, w, h).data;
        let hasMask = false;
        for(let i=3; i<mData.length; i+=4) {
          if(mData[i] > 0) { hasMask = true; break; }
        }
        if(!hasMask) {
          alert('Nejdříve označ maskou (nástroj 🎭 Maska) oblast, kterou chceš přegenerovat.');
          return;
        }
        const maskDataUrl = maskC.toDataURL('image/png');
        const str = (+$('#ed-inpaint-str').value) / 100;
        $('#btn-do-inpaint').disabled = true;
        const r = await post('/api/inpaint', {set: setname, cand, mask_data_url: maskDataUrl, prompt: pr, strength: str});
        $('#btn-do-inpaint').disabled = false;
        if(r.err) { $('#status').textContent = r.err; return; }
        busy(true);
        pollJob(async j => { busy(false); await load(); again(j, cand); });
      };
    }

    $('#ed-col').oninput = () => {
      if(edState) { edState.color = $('#ed-col').value; renderEdPalette(); }
    };
    $('#btn-undo').onclick = () => {
      if(edState && edState.histIdx > 0) {
        edState.histIdx--;
        offCtx.putImageData(edState.history[edState.histIdx], 0, 0);
        renderCanvas();
      }
    };
    $('#btn-redo').onclick = () => {
      if(edState && edState.histIdx < edState.history.length - 1) {
        edState.histIdx++;
        offCtx.putImageData(edState.history[edState.histIdx], 0, 0);
        renderCanvas();
      }
    };
    $('#btn-save-edit').onclick = async () => {
      const dataUrl = offC.toDataURL('image/png');
      const r = await post('/api/edit-sprite', {set: setname, cand, data_url: dataUrl});
      if(r.ok) {
        $('#status').textContent = 'úpravy uloženy: ' + r.msg;
        await load(); detail(src, setname, cand);
      } else {
        $('#status').textContent = r.msg || 'chyba při ukládání';
      }
    };
  };

  if($('#btn-open-editor')) {
    $('#btn-open-editor').onclick = () => {
      $('#editor-area').style.display = 'flex';
      $('#btn-open-editor').style.display = 'none';
      initEditor();
    };
  }
  if($('#btn-close-editor')) {
    $('#btn-close-editor').onclick = () => {
      $('#editor-area').style.display = 'none';
      $('#btn-open-editor').style.display = '';
    };
  }

  const doInstall=async force=>{
    const r=await post('/api/install',{set:setname,cand,target:$('#tgt').value,
      lock:$('#lockp').checked,force:!!force});
    if(r.ok){$('#imsg').className='okmsg';
      $('#imsg').textContent='nainstalováno: '+r.msg+(r.note?' · '+r.note:'');
      load(); return;}
    $('#imsg').className='warn';
    $('#imsg').textContent=r.msg;
    if(r.ask){
      const b=document.createElement('button');
      b.className='sm'; b.textContent='Vím to, nainstalovat i tak';
      b.style.marginLeft='8px'; b.onclick=()=>doInstall(true);
      $('#imsg').appendChild(b);
    }
  };
  $('#inst').onclick=()=>doInstall(false);

  if($('#inst-set')){
    $('#inst-set').onclick=async()=>{
      const target = $('#tgt').value.trim();
      if(!target){$('#tgt').focus();return;}
      const r = await post('/api/install-set', {
        set: setname, cand, target,
        lock: $('#lockp').checked,
        create_tres: $('#ctres').checked
      });
      if(r.ok){
        $('#imsg').className = 'okmsg';
        $('#imsg').textContent = r.msg;
        load();
      } else {
        $('#imsg').className = 'warn';
        $('#imsg').textContent = r.msg;
      }
    };
  }

  // Side-by-side compare logic
  if($('#cmp-pick')){
    $('#cmp-pick').onchange = async () => {
      const u = $('#cmp-pick').value;
      if(!u) { $('#cmp-view').style.display = 'none'; return; }
      $('#cmp-view').style.display = 'block';
      $('#cmp-img-ref').src = u;
      $('#cmp-img-over').src = u;
      const mRef = await getj('/api/measure?src=' + enc(u));
      if(mRef.ok !== false) {
        $('#cmp-metrics').innerHTML = `<b>Porovnání:</b> Kandidát <b>${m.w}×${m.h}</b> (${m.cols} barev, ${m.iso}% šumu) vs Reference <b>${mRef.w}×${mRef.h}</b> (${mRef.cols} barev, ${mRef.iso}% šumu)`;
      }
    };
    $('#cmp-alpha').oninput = () => {
      $('#cmp-img-over').style.opacity = $('#cmp-alpha').value / 100;
    };
  }
}

// ------------------------------------------------------------------ hlavicka

$('#sizes').innerHTML=CFG.sizes.map(([s,d])=>
  `<option value="${esc(s)}">${esc(d)}</option>`).join('');
$('#refmode').innerHTML=CFG.refmodes.map(m=>`<option>${esc(m)}</option>`).join('');
const REFH={zaklad:'předloha do img2img — drží pózu a obrys, prompt mění detaily',
  paleta:'jen barevný svět reference, kompozice volná — takhle se vynucuje styl bible',
  oboji:'kompozice i barvy'};
function refhint(){$('#refh').textContent=REF.path?REFH[REF.mode]||'':'bez reference se '
  +'generuje čistě z promptu';}
$('#refmode').onchange=()=>{REF.mode=$('#refmode').value;refhint();};

// Sila LoRA je hlavni paka na DETAIL, ne na "kvalitu" — popisek proto rika, co se stane,
// misto aby ukazoval holé cislo.
function lorah(){
  const v=$('#lora').value/100;
  const t=v<0.15?'model přestává kreslit plochou magentu — rozbije se odstranění pozadí'
    :v<0.45?'slabá — detaily z promptu přežijí, styl je volnější'
    :v<0.75?'vyvážená — drobnosti z promptu se objeví'
    :'silná — model zjednodušuje a prvky z promptu (blesk na plechovce) zahazuje';
  $('#lorah').textContent=v.toFixed(2)+' — '+t;
}
$('#lora').oninput=lorah; lorah();

// ---- zdroj: Retro Diffusion vs lokalni SDXL -------------------------------
// Prepinac neprepina jen endpoint, prepina CELOU spodni cast hlavicky. Kazdy
// zdroj ma jine paky (RD: kvalita a jeho LoRA soubory; SDXL: sila LoRA a
// reference) a ukazovat obe sady najednou by znamenalo, ze polovina ovladacich
// prvku na obrazovce nic nedela — a nebylo by videt ktera.
let RD={ok:false,running:false,loras:[],err:''};

// Cena je CAS, ne kredity. Mereno na teto masine: RD 4 sprity 32x32 za 17 s,
// lokalni SDXL ~40 s za jeden. Ta hodnota patri NAD tlacitko (viz studio_ui.md),
// protoze rozhoduje driv, nez na nej clovek sahne.
function costline(){
  const n=+$('#n').value, rd=$('#src').value==='rd';
  $('#cost').textContent=rd?('~'+Math.max(5,Math.round(n*4.3))+' s'):('~'+Math.round(n*40)+' s');
  $('#cost').title=rd?'lokální, zaplaceno jednou':'lokální, ale načtení modelu stojí ještě ~30 s navíc';
}

// Kroky vzorkovace = round(3.4 + q*q/2) — vzorec ze serveru (image_server.py:2085).
// Model je LCM-destilovany, takze nad 6 uz kroky pridavaji cas a ne detail.
function rdqh(){
  const q=+$('#rdq').value, steps=Math.round(3.4+q*q/2);
  const t=q<=3?'málo kroků — tvar drží, ale povrch zůstane hladký'
    :q<=6?'sladké místo — struktura se objeví (růžičky, nýty, oči)'
    :'nad šest už model jen počítá déle, detailu nepřibývá';
  $('#rdqh').textContent=steps+' kroků — '+t;
}
$('#rdq').oninput=rdqh; rdqh();

// Počet barev je páka na PLASTIČNOST, ne na "čistotu". Dlouho tu byla napevno 16 a
// nešla vidět — a právě ta dělala náš art plošší než laťka. Změřeno na 1623 originálech
// z PixelLabu: medián 41 barev, p90 55, a skoro nezávisle na velikosti spritu.
function colh(){
  const v=+$('#colors').value;
  const t=v<16?'ploché — vypadá to čistě, ale ve hře to splyne'
    :v<28?'pod laťkou — PixelLab má na téhle velikosti kolem 40'
    :v<=56?'v pásmu laťky (medián 41, p90 55)'
    :'nad laťkou — zkontroluj, jestli to není šum místo odstínů';
  $('#colh').textContent=v+' barev — '+t;
  $('#colh').style.color=(v<28||v>56)?'#ffcf8a':'#8d8d9e';
}
$('#colors').oninput=colh; colh();

// Varování, která by jinak stála hodinu GPU a vypadala jako "ten model je k ničemu".
// Obojí je změřené (docs/art/retrodiffusion.md), ne domněnka, a obojí platí JEN pro
// Retro Diffusion — SDXL na plátně 1024 px a s vlastní LoRA se chová jinak.
function promptCheck(){
  if($('#src').value!=='rd'){$('#row-warn').style.display='none';return;}
  const p=$('#prompt').value.trim();
  const words=p?p.split(/\s+/).length:0;
  const m=/(\d+)\s*[x×]\s*(\d+)|^\s*(\d+)\s*$/.exec($('#size').value.trim());
  const side=m?Math.max(+(m[1]||m[3]||0),+(m[2]||m[3]||0)):0;
  const w=[];
  // Nejdrazsi chyba: prompt psany pro SDXL. Model se poctive snazi nakreslit LIST
  // osmi fazi do jednoho obrazku, takze vyjde symetricka slatanina — a vypada to
  // jako porucha modelu, ne jako spatne zadani.
  if(/\bframes?\s*\d|\bframe\s*\d|animation sheet|sprite sheet/i.test(p))
    w.push('Prompt popisuje <b>animační list</b>. Model nakreslí jeden obrázek, '
      +'takže se pokusí nacpat všechny fáze do něj. Animace se dělá z hotového '
      +'spritu (Doladit → Animace), ne promptem.');
  if(words>40)
    w.push(`Prompt má <b>${words} slov</b>. Retro Diffusion je SD 1.5 + ELLA a na `
      +'dlouhé strukturované zadání nemá — drž se jedné bytosti a pár znaků. '
      +'(Ty dlouhé prompty patří lokálnímu SDXL.)');
  if(side&&side<=32&&words>3)
    w.push(`<b>${side} px je málo na postavu.</b> Změřeno dnes: týž prompt dá na `
      +'64×64 tělo s nohama, na 32×32 kaši. Dlaždice a dekorace na 32 fungují.');
  $('#pwarn').innerHTML=w.join('<br>');
  $('#row-warn').style.display=w.length?'':'none';
}

function drawRD(){
  const on=$('#src').value==='rd';
  $('#row-rd').style.display=on?'':'none';
  $('#row-sdxl').style.display=on?'none':'';
  // Reference je zatim jen SDXL cesta (img2img pres gen_ref). U RD ji schovavam
  // misto zasedeni: neni to "docasne nedostupne", je to "jeste nenapojene".
  $('#row-ref').style.display=on?'none':'';
  $('#srch').textContent=on
    ?'kreslí rovnou v cílovém rastru (512 px → k-centroid → 32 px), takže se po něm nezmenšuje'
    :'SDXL + pixel-art LoRA na plátně 1024 px, výsledek se zmenšuje mediánem a čistí';
  if(on){
    $('#rdstate').textContent=!RD.ok?('Retro Diffusion: '+RD.err)
      :RD.running?'server běží':'server neběží — první generace ho spustí (trvá minuty)';
    $('#rdstate').style.color=!RD.ok?'#ff9d9d':RD.running?'#7ee2a8':'#ffcf8a';
    $('#rdstart').style.display=(RD.ok&&!RD.running)?'':'none';
    if(!$('#rdloras').dataset.filled&&RD.loras.length){
      $('#rdloras').dataset.filled='1';
      $('#rdloras').innerHTML='<span class="hint" style="min-width:auto">LoRA:</span>'+
        RD.loras.map(l=>`<label class="f" style="gap:3px"><input type="checkbox" class="rdl" value="${esc(l)}">${esc(l)}</label>`).join('');
    }
  }
  costline();
  sizeh();     // render/plátno se počítá jinak podle zdroje
  promptCheck();
}
$('#src').onchange=drawRD;
$('#prompt').oninput=promptCheck;
$('#n').onchange=costline;
$('#rdstart').onclick=async()=>{
  $('#rdstart').disabled=true;
  const r=await post('/api/rd',{action:'start'});
  if(r.err){$('#status').textContent=r.err;$('#rdstart').disabled=false;return;}
  pollJob(async()=>{$('#rdstart').disabled=false;RD=await getj('/api/rd');drawRD();});
};
(async()=>{RD=await getj('/api/rd');drawRD();})();

// Kdyz se stranka nacte, zatimco uloha bezi (obnoveni, druha zalozka), navazeme na ni.
// Bez toho by zivy pruh videl jen ten, kdo tlacitko zmackl.
(async()=>{
  const j=await getj('/api/job');
  if(j.state==='running')pollJob(async jj=>{await load(); if(jj.set)open('gen',jj.set);});
})();

let sizeT=null;
async function sizeh(){
  const r=await getj('/api/size?s='+enc($('#size').value)+'&src='+enc($('#src').value));
  $('#sizeh').textContent=r.ok?(r.note+(r.grid?'':' · '+r.gridnote)):r.note;
  $('#sizeh').style.color=(r.ok&&r.grid)?'#8d8d9e':'#ffcf8a';
}
$('#size').oninput=()=>{clearTimeout(sizeT);sizeT=setTimeout(sizeh,300);promptCheck();};
sizeh();

async function refs(){
  const r=await getj('/api/refs?q='+enc($('#rq').value));
  $('#rlist').innerHTML=r.items.map(p=>
    `<a data-p="${esc(p)}" class="${p===REF.path?'on':''}">${esc(p)}</a>`).join('')
    +(r.total>r.items.length?`<a style="color:#5c5c6b">…a dalších ${r.total-r.items.length}
      — upřesni hledání</a>`:'');
  document.querySelectorAll('#rlist a[data-p]').forEach(a=>a.onclick=()=>pickRef(a.dataset.p));
}
async function pickRef(p){
  REF.path=p;
  const u='/img/ref/'+p.split('/').map(enc).join('/');
  $('#rprev').src=u; $('#refthumb').src=u; $('#refthumb').style.display='';
  $('#refname').textContent=p.split('/').slice(-2).join('/');
  const m=await getj('/api/measure?src='+enc(u));
  $('#rinfo').textContent=`${m.w}×${m.h} · ${m.cols} barev`;
  document.querySelectorAll('#rlist a').forEach(a=>
    a.classList.toggle('on',a.dataset.p===p));
  refhint();
}
$('#refpick').onclick=()=>{rdlg.showModal();refs();};
$('#refoff').onclick=()=>{REF.path='';$('#refthumb').style.display='none';
  $('#refname').textContent='žádná';$('#rprev').removeAttribute('src');refhint();};
let rqT=null;
$('#rq').oninput=()=>{clearTimeout(rqT);rqT=setTimeout(refs,250);};
refhint();

// Prompt Asistent
if($('#btn-open-padlg')){
  $('#btn-open-padlg').onclick = () => {
    $('#padlg').showModal();
    $('#pa-input').focus();
  };
  $('#pa-go').onclick = async () => {
    const txt = $('#pa-input').value.trim();
    if(!txt) return;
    $('#pa-status').textContent = 'převádím na SDXL prompt…';
    const r = await post('/api/enhance-prompt', {text: txt});
    if(r.ok && r.prompt) {
      $('#pa-status').textContent = '';
      $('#pa-res').textContent = r.prompt;
      $('#pa-result-box').style.display = 'block';
    } else {
      $('#pa-status').textContent = 'Chyba při generování promptu';
    }
  };
  $('#pa-apply').onclick = () => {
    $('#prompt').value = $('#pa-res').textContent;
    $('#padlg').close();
  };
}

// Zivy pruh: rozpracovany obrazek primo z modelu, jeden za druhym.
// Src se prepisuje jen kdyz se ADRESA zmenila — server k ni pripina poradove cislo,
// takze stejna adresa znamena "od minule nic noveho" a prirazeni by jen zablikalo.
function drawLive(j){
  const el=$('#live'), im=$('#liveimg');
  if(!j.preview){el.style.display='none'; im.removeAttribute('src'); return;}
  el.style.display='flex';
  if(im.getAttribute('src')!==j.preview)im.setAttribute('src',j.preview);
  $('#livemsg').textContent=j.msg||'';
  // Bez tehle vety je prvni otazka vzdycky "proc ma nahled pozadi a vysledek ne":
  // rembg bezi az po VSECH davkach, jednim vrzem, takze rozpracovany sprite ho ma.
  $('#livenote').textContent='rozpracované — model počítá jednu dávku po druhé, vlevo '
    +'jsou hotové. Ve výsledné velikosti spritu; pozadí se odmazává až úplně nakonec.';
}

async function pollJob(done){
  const j=await getj('/api/job');
  $('#status').textContent=j.state==='idle'?'':
    (j.msg+(j.total?` (${j.done}/${j.total})`:''));
  $('#status').style.color=j.state==='error'?'#ff9188':'#8d8d9e';
  drawLive(j);
  // Rychleji nez server posila nahledy nema smysl se ptat: u platna 512 px je to
  // kazdy druhy krok (image_server.py:2239), cili radove desetina sekundy az sekunda.
  if(j.state==='running'){setTimeout(()=>pollJob(done),600);return;}
  if(done)done(j);
}

$('#go').onclick=async()=>{
  const p=$('#prompt').value.trim(); if(!p)return;
  $('#go').disabled=true;
  const src=$('#src').value;
  const r=await post('/api/generate',{prompt:p,name:$('#name').value.trim(),
    n:+$('#n').value,size:$('#size').value,source:src,colors:+$('#colors').value,
    lora:$('#lora').value/100,ref:REF.path,ref_mode:REF.mode,
    quality:+$('#rdq').value,
    loras:[...document.querySelectorAll('.rdl:checked')].map(c=>({name:c.value,weight:100}))});
  if(r.err){$('#status').textContent=r.err;$('#go').disabled=false;return;}
  pollJob(async j=>{$('#go').disabled=false;
    if(j.state==='done'){await load(); if(j.set)open('gen',j.set);}});
};
load();
</script></html>"""


def page():
    """HTML s nastavenim, ktere zna server. Nabidka velikosti, rezimy reference i poradi
    smeru maji jediny zdroj pravdy v Pythonu — druhy seznam v JavaScriptu by se rozesel
    hned, jak se v gen_ref.py neco pridá."""
    cfg = {"sizes": gen_ref.TARGET_SIZES, "refmodes": list(gen_ref.REF_MODES),
           "dirs": list(DIRS), "lora": DEFAULT_LORA, "cell": CELL}
    return HTML.replace("__CFG__", json.dumps(cfg, ensure_ascii=False).replace("</", "<\\/"))


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode("utf-8")
        elif isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _file(self, path):
        if not path or not os.path.isfile(path):
            self._send(404, {"err": "nenalezeno"})
            return
        with open(path, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        u = urlparse(self.path)
        p = unquote(u.path)
        q = parse_qs(u.query)
        if p == "/":
            return self._send(200, page(), "text/html; charset=utf-8")
        if p == "/api/state":
            return self._send(200, {"art": scan_art(), "gen": scan_gen(), "lib": scan_lib()})
        if p == "/api/job":
            return self._send(200, JOB)
        if p == "/api/size":
            return self._send(200, size_info((q.get("s") or [""])[0],
                                             (q.get("src") or ["sdxl"])[0]))
        if p == "/api/refs":
            return self._send(200, list_refs((q.get("q") or [""])[0]))
        if p == "/api/lib":
            return self._send(200, lib_detail(os.path.basename((q.get("slug") or [""])[0])))
        if p == "/api/remote":
            return self._send(200, {"rows": _REMOTE["rows"], "err": _REMOTE["err"]})
        if p == "/api/rd":
            return self._send(200, rd_status())
        if p == "/api/measure":
            return self._send(200, measure(self._resolve((q.get("src") or [""])[0])) or {})
        if p == "/api/lineage":
            s = os.path.basename((q.get("set") or [""])[0])
            c = os.path.basename((q.get("cand") or [""])[0])
            # Prazdny retez misto chyby: kandidat ze sekce Hra zadny rodokmen nema a
            # prohlizec ho smi zobrazovat stejnym kodem jako ten z generatoru.
            return self._send(200, {"set": s, "cand": c,
                                    "chain": lineage_chain(s, c) if s and c else []})
        if p.startswith("/img/"):
            return self._file(self._resolve(p))
        self._send(404, {"err": "nenalezeno"})

    def _resolve(self, src):
        """URL obrazku -> cesta na disku, nebo "" (a volajici da 404).

        Prijima cestu i absolutni URL: <img>.src je v prohlizeci VZDY absolutni, takze
        porovnavat ho proti "/img/..." tise selze a detail ukaze undefined u vsech mer.

        Kazda komponenta jde pres basename — cesta uz je po unquote, takze %5c je tady
        zpetne lomitko a bez zavory na VSECH castech sel pres jednu z nich precist
        libovolny soubor na disku (overeno: /img/gen/..%5c..%5cWindows/win.ini vratilo
        200 a obsah). U referenci basename nestaci (jsou vicepatrove), proto ref_path."""
        if "://" in src:
            src = urlparse(src).path
        src = unquote(src)
        bn = os.path.basename
        if src.startswith("/img/art/"):
            return os.path.join(ART_DIR, bn(src))
        if src.startswith("/img/gen/"):
            r = src[len("/img/gen/"):].split("/")
            if len(r) == 2:
                return os.path.join(GEN_DIR, bn(r[0]), bn(r[1]))
        if src.startswith("/img/lib/"):
            r = src[len("/img/lib/"):].split("/")
            if len(r) == 3:
                return os.path.join(LIB_DIR, bn(r[0]), bn(r[1]), bn(r[2]))
        if src.startswith("/img/ref/"):
            return ref_path(src[len("/img/ref/"):])
        return ""

    def do_POST(self):
        # Frontend posila JSON bez hlavicek, takze Content-Type je text/plain a prohlizec
        # to bere jako "simple request" — zadny preflight. Libovolna otevrena stranka by
        # tedy mohla poslat /api/install nebo rozjet generovani na localhost:8777.
        # Vlastni fetch Origin neposila (same-origin), takze prazdny je v poradu.
        origin = self.headers.get("Origin")
        if origin and urlparse(origin).hostname not in ("localhost", "127.0.0.1", "::1"):
            return self._send(403, {"err": "cizí origin"})
        n = int(self.headers.get("Content-Length", 0))
        try:
            body = json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            return self._send(400, {"err": "špatný JSON"})
        if not isinstance(body, dict):
            return self._send(400, {"err": "čekám objekt"})
        p = urlparse(self.path).path
        if p == "/api/generate":
            return self._generate(body)
        if p in ("/api/refine", "/api/animate", "/api/rotate"):
            return self._iterate(p, body)
        if p == "/api/puppet-animate":
            s = os.path.basename(body.get("set") or "")
            c = os.path.basename(body.get("cand") or "")
            if not s or not c:
                return self._send(400, {"err": "chybí sada nebo kandidát"})
            if not os.path.isfile(os.path.join(GEN_DIR, s, c)):
                return self._send(404, {"err": "kandidát neexistuje"})
            kind = body.get("kind") or "walk"
            intensity = max(1, min(5, int(body.get("intensity", 2))))
            r = run_puppet(s, c, kind, intensity)
            return self._send(200, r)
        if p == "/api/recolor":
            s = os.path.basename(body.get("set") or "")
            c = os.path.basename(body.get("cand") or "")
            if not s or not c:
                return self._send(400, {"err": "chybí sada nebo kandidát"})
            if not os.path.isfile(os.path.join(GEN_DIR, s, c)):
                return self._send(404, {"err": "kandidát neexistuje"})
            mode = body.get("mode") or "target"
            target_color = body.get("target_color") or "#ff3b30"
            hue_shift = float(body.get("hue_shift", 0.0))
            r = run_recolor(s, c, mode, target_color, hue_shift)
            return self._send(200, r)
        if p == "/api/inpaint":
            s = os.path.basename(body.get("set") or "")
            c = os.path.basename(body.get("cand") or "")
            mask_data_url = body.get("mask_data_url") or ""
            prompt = (body.get("prompt") or "").strip()
            if not s or not c or not mask_data_url or not prompt:
                return self._send(400, {"err": "chybí sada, kandidát, maska nebo prompt"})
            if not os.path.isfile(os.path.join(GEN_DIR, s, c)):
                return self._send(404, {"err": "kandidát neexistuje"})
            if JOB["state"] == "running":
                return self._send(409, {"err": "už běží"})
            strength = max(0.05, min(1.0, float(body.get("strength", 0.75))))
            JOB.update(state="running", msg="startuji inpaint…", done=0, total=0, preview="", set=s, cand="")
            threading.Thread(target=run_inpaint, args=(s, c, mask_data_url, prompt, strength), daemon=True).start()
            return self._send(200, {"ok": True, "set": s})
        if p == "/api/full-character":
            s = os.path.basename(body.get("set") or "")
            c = os.path.basename(body.get("cand") or "")
            include_dirs = bool(body.get("include_dirs"))
            if not s or not c:
                return self._send(400, {"err": "chybí sada nebo kandidát"})
            if not os.path.isfile(os.path.join(GEN_DIR, s, c)):
                return self._send(404, {"err": "kandidát neexistuje"})
            r = run_full_character(s, c, include_dirs=include_dirs)
            return self._send(200, r)
        if p == "/api/edit-sprite":
            s = os.path.basename(body.get("set") or "")
            c = os.path.basename(body.get("cand") or "")
            data_url = body.get("data_url") or ""
            if not s or not c or not data_url:
                return self._send(400, {"err": "chybí parametry"})
            r = save_edited_sprite(s, c, data_url)
            return self._send(200, r)
        if p == "/api/export-sheet":
            s = os.path.basename(body.get("set") or "")
            k = (body.get("anim_key") or "").strip()
            if not s or not k:
                return self._send(400, {"err": "chybí sada nebo klíč animace"})
            r = run_export_sheet(s, k)
            return self._send(200, r)
        if p == "/api/install-set":
            s = os.path.basename(body.get("set") or "")
            c = os.path.basename(body.get("cand") or "")
            target = (body.get("target") or "").strip()
            lock = bool(body.get("lock"))
            force = bool(body.get("force"))
            create_tres = bool(body.get("create_tres"))
            r = run_install_set(s, c, target, lock=lock, force=force, create_tres=create_tres)
            return self._send(200, r)
        if p == "/api/enhance-prompt":
            import prompt_assist
            text = (body.get("text") or "").strip()
            res_prompt = prompt_assist.enhance_prompt(text)
            return self._send(200, {"ok": True, "prompt": res_prompt})
        if p == "/api/install":
            r = install(body.get("set", ""), body.get("cand", ""), body.get("target", ""),
                        force=bool(body.get("force")), lock=bool(body.get("lock")))
            return self._send(200, r)
        if p == "/api/pull":
            return self._pull(body)
        if p == "/api/rd":
            act = body.get("action") or ""
            if act == "start":
                if JOB["state"] == "running":
                    return self._send(409, {"err": "už běží"})
                JOB.update(state="running", msg="startuji…", done=0, total=0, preview="", set="", cand="")
                threading.Thread(target=run_rd_start, daemon=True).start()
                return self._send(200, {"ok": True})
            if act == "stop":
                # Zastaveni se NEDELA ve vlakne a nesahá na JOB: server ma vlastni
                # korektni shutdown a trva sekundy, ne minuty. Kdyby to bezelo jako
                # uloha, prepsalo by to hlaseni o prave dobehle generaci.
                try:
                    return self._send(200, {"ok": True, "stopped": _rd().stop_server()})
                except Exception as e:
                    return self._send(500, {"err": f"{type(e).__name__}: {e}"})
            return self._send(400, {"err": "neznámá akce"})
        self._send(404, {"err": "nenalezeno"})

    def _generate(self, body):
        if JOB["state"] == "running":
            return self._send(409, {"err": "už běží"})
        prompt = (body.get("prompt") or "").strip()
        if not prompt:
            return self._send(400, {"err": "chybí prompt"})
        # Jmeno sady je jmeno SLOZKY, takze musi projit filtrem driv, nez se z nej stane
        # cesta — jinak o miste zapisu rozhoduje retezec z pozadavku.
        name = safe_set(body.get("name") or prompt)
        try:
            gen_ref.parse_size(body.get("size") or "32")
        except ValueError as e:
            return self._send(400, {"err": str(e)})

        if (body.get("source") or "sdxl") == "rd":
            # LoRA jmena jdou do cesty na disk (lora_dir()/<jmeno>.pxlm), takze
            # projdou basename driv, nez se z nich stane soubor.
            loras = []
            for item in (body.get("loras") or [])[:4]:
                nm = os.path.basename(str(item.get("name") or ""))
                if not nm:
                    continue
                loras.append({"file": nm, "weight": max(-50, min(100, int(item.get("weight", 100))))})
            t = threading.Thread(target=run_generate_rd, kwargs=dict(
                prompt=prompt, name=name, n=max(1, min(24, int(body.get("n", 6)))),
                size=body.get("size") or "32", colors=int(body.get("colors", 40)),
                seed=int(body.get("seed", 1)),
                quality=max(1, min(10, int(body.get("quality", 6)))),
                loras=loras, negative=(body.get("negative") or "").strip()), daemon=True)
            JOB.update(state="running", msg="startuji…", done=0, total=0, preview="", set=name, cand="")
            t.start()
            return self._send(200, {"ok": True, "set": name})

        ref = (body.get("ref") or "").strip()
        if ref and not ref_path(ref):
            return self._send(400, {"err": "reference musí ležet v assets/ nebo build/"})
        mode = body.get("ref_mode") or gen_ref.REF_MODES[0]
        if ref and mode not in gen_ref.REF_MODES:
            return self._send(400, {"err": f"neznámý režim reference: {mode}"})
        try:
            lora = float(body.get("lora", DEFAULT_LORA))
            strength = float(body.get("ref_strength", 0.6))
        except (TypeError, ValueError):
            return self._send(400, {"err": "neplatné číslo"})
        t = threading.Thread(target=run_generate, kwargs=dict(
            prompt=prompt, name=name, n=max(1, min(24, int(body.get("n", 6)))),
            size=body.get("size") or "32", colors=int(body.get("colors", 40)),
            steps=int(body.get("steps", 28)), seed=int(body.get("seed", 1)),
            lora=max(0.0, min(1.0, lora)), ref=ref, ref_mode=mode,
            ref_strength=max(0.05, min(0.95, strength))), daemon=True)
        JOB.update(state="running", msg="startuji…", done=0, total=0, preview="", set=name, cand="")
        t.start()
        return self._send(200, {"ok": True, "set": name})

    def _iterate(self, p, body):
        """Doladeni, animace i rotace: vsechny berou sadu + kandidata a vsechny zaberou
        celou kartu.

        JOB se prepne na "running" uz TADY, ne az ve vlaknu. Prohlizec se zepta na stav
        hned po odpovedi a to je driv, nez se vlakno rozbehne — bez toho by uvidel "idle",
        usoudil, ze je hotovo, a prekreslil detail dav pred tim, nez neco vzniklo."""
        if JOB["state"] == "running":
            return self._send(409, {"err": "už běží"})
        s = os.path.basename(body.get("set") or "")
        c = os.path.basename(body.get("cand") or "")
        if not s or not c:
            return self._send(400, {"err": "chybí sada nebo kandidát"})
        if not os.path.isfile(os.path.join(GEN_DIR, s, c)):
            return self._send(404, {"err": "kandidát neexistuje"})
        try:
            strength = float(body.get("strength", 0.35))
        except (TypeError, ValueError):
            return self._send(400, {"err": "neplatná síla"})
        strength = max(0.05, min(0.9, strength))

        if p == "/api/refine":
            prompt = (body.get("prompt") or "").strip()
            if not prompt:
                return self._send(400, {"err": "chybí prompt"})
            t = threading.Thread(target=run_refine, args=(s, c, prompt, strength),
                                 daemon=True)
        elif p == "/api/rotate":
            # `mode` je novejsi nez `use_ip` a `use_ip` se drzi kvuli starym klientum.
            # Vychozi je "pose", protoze je to jedina varianta, u ktere se pohled skutecne
            # zmeni — ostatni dve vyrabeji varianty tehoz pohledu.
            mode = str(body.get("mode") or "").strip().lower()
            if not mode:
                mode = "ip" if body.get("use_ip", True) else "plain"
            target_fn = {"pose": run_rotate_pose, "ip": run_rotate_ip,
                         "plain": run_rotate}.get(mode)
            if target_fn is None:
                return self._send(400, {"err": f"neznámý režim otáčení: {mode}"})
            t = threading.Thread(target=target_fn, args=(s, c, strength), daemon=True)
        else:
            poses = body.get("poses") or None
            if poses is not None:
                if not isinstance(poses, list):
                    return self._send(400, {"err": "pózy čekám jako seznam"})
                poses = [str(x).strip()[:300] for x in poses if str(x).strip()][:16]
                if not poses:
                    return self._send(400, {"err": "prázdné pózy"})
            kind = body.get("kind") or "walk"
            if not poses and kind not in ("walk", "idle"):
                return self._send(400, {"err": "neznámý druh animace"})
            t = threading.Thread(target=run_animate, args=(s, c, kind, strength, poses),
                                 daemon=True)
        JOB.update(state="running", msg="startuji…", done=0, total=0, preview="", set=s, cand="")
        t.start()
        return self._send(200, {"ok": True, "set": s})

    def _pull(self, body):
        if JOB["state"] == "running":
            return self._send(409, {"err": "už běží"})
        action = body.get("action") or "list"
        if action == "list":
            t = threading.Thread(target=run_remote_list, daemon=True)
        elif action == "pull":
            cid = str(body.get("id") or "")
            # id jde do sitoveho volani i do jmena slozky — pousti se dal jen tvar uuid.
            if not UUID_RE.match(cid):
                return self._send(400, {"err": "neplatné id postavy"})
            t = threading.Thread(target=run_pull, args=(cid,), daemon=True)
        else:
            return self._send(400, {"err": "neznámá akce"})
        JOB.update(state="running", msg="startuji…", done=0, total=0, preview="", set="", cand="")
        t.start()
        return self._send(200, {"ok": True})


def main():
    ap = argparse.ArgumentParser(description="Sprite Studio — prohlížeč a generátor artu.")
    ap.add_argument("--port", type=int, default=8777)
    ap.add_argument("--no-open", action="store_true")
    args = ap.parse_args()
    url = f"http://localhost:{args.port}"
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"Sprite Studio běží na {url}   (Ctrl+C ukončí)")
    if not args.no_open:
        threading.Timer(0.6, lambda: webbrowser.open(url)).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nkonec")


if __name__ == "__main__":
    main()
