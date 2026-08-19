# Klient k PixelLab MCP — bez MCP.
#
# PROC TENHLE SOUBOR EXISTUJE
#
# PixelLab nabizi MCP server a `claude mcp list` ho hlasi jako pripojeny, jenze jeho
# nastroje se do session nenactou (znamy problem s velikosti pismen v ceste). Cekat na to
# nema smysl: MCP je pod pokrickou obycejne JSON-RPC pres HTTP, takze se s nim da mluvit
# primo. Tenhle soubor je ta prima cesta a funguje bez ohledu na to, co dela MCP vrstva.
#
# DVE PASTI, KTERE STOJI HODINU, KDYZ SE NA NE PRIJDE SAMO
#
# 1. Odkazy na obrazky vraci HTTP 403, dokud posilas vychozi User-Agent Pythonu.
#    Backblaze ho blokuje. Staci JAKYKOLIV bezny UA — token s tim nema nic spolecneho
#    a pridavat ho do stahovani je zbytecne (overeno: 403 i s Bearerem, 200 jen s UA).
# 2. Odpoved chodi bud jako JSON, nebo jako SSE ramce (`data: {...}`), podle nalady
#    serveru. Kdo cte jen JSON, dostane obcas prazdno.
#
# TOKEN
#
# Nikdy v kodu. Bere se z promenne PIXELLAB_TOKEN, jinak ze souboru .pixellab_token
# v korenu projektu (ten je v .gitignore).
#
# POUZITI
#
#   python tools/pixellab.py list
#   python tools/pixellab.py get <character_id>
#   python tools/pixellab.py pull <character_id> --out build/pixellab/boss
#   python tools/pixellab.py pull <character_id> --out ... --anim td_walk --dir south
import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
URL = "https://api.pixellab.ai/mcp"

# Backblaze odmita vychozi UA Pythonu. Viz hlavicka.
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"


def token():
    t = os.environ.get("PIXELLAB_TOKEN", "").strip()
    if t:
        return t
    p = os.path.join(PROJ, ".pixellab_token")
    if os.path.isfile(p):
        t = open(p, encoding="utf-8").read().strip()
        if t:
            return t
    raise SystemExit(
        "Chybí token. Nastav PIXELLAB_TOKEN, nebo ho vlož do .pixellab_token "
        "v kořeni projektu (soubor je v .gitignore)."
    )


# ------------------------------------------------------------------ JSON-RPC


def _parse(raw):
    """Odpoved je bud JSON, nebo proud SSE ramcu. Zvladni oboji."""
    s = raw.lstrip()
    if s.startswith("event:") or s.startswith("data:") or "\ndata:" in raw:
        out = []
        for line in raw.splitlines():
            if line.startswith("data:"):
                try:
                    out.append(json.loads(line[5:].strip()))
                except ValueError:
                    pass
        return out[-1] if out else {}
    try:
        return json.loads(raw)
    except ValueError:
        return {"_raw": raw[:500]}


class Client:
    def __init__(self, tok=None):
        self.tok = tok or token()
        self._ready = False

    def rpc(self, method, params=None, notify=False, timeout=180):
        body = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            body["params"] = params
        if not notify:
            body["id"] = 1
        req = urllib.request.Request(
            URL, json.dumps(body).encode(),
            {"Content-Type": "application/json",
             "Accept": "application/json, text/event-stream",
             "Authorization": f"Bearer {self.tok}"},
            method="POST")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return _parse(r.read().decode("utf-8", "replace"))
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")[:300]
            raise SystemExit(f"PixelLab HTTP {e.code}: {detail}")

    def ready(self):
        if self._ready:
            return
        self.rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                "clientInfo": {"name": "td-project", "version": "1"}})
        self.rpc("notifications/initialized", {}, notify=True)
        self._ready = True

    def call(self, tool, args=None, **kw):
        """-> (text, [bytes obrazku]). Nastroje vraci popis textem a nahled obrazkem.

        Argumenty jdou bud slovnikem, nebo pojmenovane -- a to POJMENOVANE nestaci.
        Puvodne to byl jen `call(self, name, **args)`, jenze PixelLab ma vlastni
        parametr "name" u create_character, animate_character i update_*_tags, takze
        `c.call("create_character", name="Rytir", ...)` skoncilo na
        "got multiple values for argument 'name'" -- tedy prave u nastroju, ktere
        clovek pouziva nejcasteji. Prvni parametr se proto jmenuje `tool` a slovnik
        ma prednost; pojmenovana varianta zustava, aby nespadla starsi volani."""
        self.ready()
        merged = dict(args or {})
        merged.update(kw)
        r = self.rpc("tools/call", {"name": tool, "arguments": merged})
        res = r.get("result", r)
        if res.get("isError"):
            raise SystemExit(f"{tool}: {json.dumps(res)[:400]}")
        import base64
        text, imgs = [], []
        for c in res.get("content", []):
            if c.get("type") == "text":
                text.append(c["text"])
            elif c.get("type") == "image":
                imgs.append(base64.b64decode(c["data"]))
        return "\n".join(text), imgs


# ------------------------------------------------- modulove API (jeden klient)
#
# Kratce tu byly DVA klienty: tenhle a pixellab_client.py, kazdy objeveny nezavisle a
# kazdy narazil na tutez past s velikosti pismene v ceste k MCP. Dva klienty se ale
# nutne rozejdou — jeden dostane opravu strankovani, druhy ne — takze zbyl jeden a
# druhy tu po sobe nechal tohle funkcni rozhrani, aby se nemusela prepisovat volajici
# mista. Nova prace at pouziva Client() primo; tohle je most, ne doporuceny styl.

_SHARED = None


def _shared():
    global _SHARED
    if _SHARED is None:
        _SHARED = Client()
    return _SHARED


def init():
    c = _shared()
    c.ready()
    return {"result": {"ok": True}}


def call(name, args=None):
    """Vraci SYROVOU odpoved JSON-RPC, jak ji cekal puvodni pixellab_client."""
    c = _shared()
    c.ready()
    return c.rpc("tools/call", {"name": name, "arguments": args or {}})


def text_of(resp):
    """Textovy obsah z odpovedi tools/call. Obrazky se zminí jen znackou <image>,
    protoze volajici tuhle funkci pouzivaji na parsovani, ne na data."""
    try:
        parts = resp["result"]["content"]
    except (KeyError, TypeError):
        return json.dumps(resp, ensure_ascii=False)[:4000]
    return "\n".join(p.get("text", "") if p.get("type") == "text"
                     else "<" + p.get("type", "?") + ">" for p in parts)


# ------------------------------------------------------------------ parsovani

# "  south: https://..."  i  "  west: https://.../0.png, https://.../1.png, ..."
#
# Rotace ma na radku JEDEN odkaz, animace jich ma tolik, kolik ma snimku, oddelenych
# carkou. Proto se bere cely zbytek radku a rozdeli az potom — regularni vyraz koncici
# na \S+$ tise sebral jen prvni snimek a zbytek animace zmizel bez chybove hlasky.
LINK_RE = re.compile(r"^\s*([\w\-]+):\s*(https?://.+)$")
# "  td_attack — 2 dir (west, east), 7f ..." — em pomlcka i obycejna.
ANIM_RE = re.compile(r"^\s{0,4}(\w[\w\-]*)\s+[—-]\s+\d+\s*dir")


def parse_character(text):
    """Textovy vypis get_character -> {'rotations': {...}, 'animations': {jmeno: {...}}}

    Hodnota je vzdy SEZNAM odkazu: rotace ma jeden prvek, animace jeden na snimek.
    Jednotny tvar proto, aby volajici nemusel resit dva pripady.

    Parsuje se text, protoze strukturovanou odpoved tenhle nastroj nevraci.
    """
    out = {"rotations": {}, "animations": {}, "size": None, "name": None}
    section, anim = None, None
    for line in text.splitlines():
        if line.startswith("size:"):
            out["size"] = line.split(":", 1)[1].strip()
            continue
        if line.startswith("name:"):
            out["name"] = line.split(":", 1)[1].strip()[:120]
            continue
        if line.startswith("rotations:"):
            section, anim = "rot", None
            continue
        if line.startswith("animations"):
            section, anim = "anim", None
            continue
        if section == "anim":
            m = ANIM_RE.match(line)
            if m and "http" not in line:
                anim = m.group(1)
                out["animations"].setdefault(anim, {})
                continue
        m = LINK_RE.match(line)
        if not m:
            continue
        key = m.group(1)
        # `download:` je odkaz na ZIP cele postavy, ne smer. Bez tehle vyjimky se z nej
        # stane osmy "smer" jmenem download a skonci mezi snimky animace.
        if key == "download":
            continue
        urls = [u.strip() for u in m.group(2).split(",") if u.strip().startswith("http")]
        if not urls:
            continue
        if section == "rot":
            out["rotations"][key] = urls
        elif section == "anim" and anim:
            out["animations"][anim][key] = urls
    return out


# ------------------------------------------------------------------ stahovani


def fetch(url, timeout=120):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


# ------------------------------------------------------------------ prikazy


# "  <uuid> | <jmeno> | 8dir 64x64 | 5anim"  — pocet animaci na konci nemusi byt.
#
# Prvni verze vyzadovala uzaviraci `|` a padala i na zalomeni: dlouha jmena (cele prompty)
# server zalomi a zbytek radku posle jako `| 8dir 64x64 | 1anim`. Tise to sezralo deset
# postav z osmatriceti — proto se radky nejdriv slepi a teprve pak parsuji.
ROW_RE = re.compile(r"^\s*([0-9a-f]{8}-[0-9a-f-]{27,})\s*\|\s*(.*?)\s*\|\s*(\d+dir)\s+(\S+)")

PAGE = 10


def _rows(text):
    """Slepi zalomene radky a vrati jen ty, ktere popisuji postavu."""
    joined = []
    for line in text.splitlines():
        if line.lstrip().startswith("|") and joined:
            joined[-1] += " " + line.strip()
        else:
            joined.append(line)
    out = []
    for line in joined:
        m = ROW_RE.match(line)
        if m:
            out.append({"id": m.group(1), "name": m.group(2),
                        "dirs": m.group(3), "size": m.group(4)})
    return out


def all_characters(c):
    """Vsechny postavy pres strankovani. -> [{'id','name','dirs','size'}]

    Strankuje se podle HLASENEHO POCTU, ne podle toho, kolik radku se povedlo prelozit.
    Kdyz jedna stranka nedá nic (jiny format, chyba parsovani), pokracuje se dal misto
    aby se tise skoncilo — presne tahle "chytrost" driv usekla seznam na 28 z 38.
    """
    out, seen, off, total = [], set(), 0, None
    while True:
        text, _ = c.call("list_characters", offset=off) if off else c.call("list_characters")
        if total is None:
            m = re.search(r"characters:\s*(\d+)\s*total", text)
            total = int(m.group(1)) if m else None
        for r in _rows(text):
            if r["id"] not in seen:
                seen.add(r["id"])
                out.append(r)
        off += PAGE
        if total is None or off >= total:
            break
    if total is not None and len(out) != total:
        print(f"  ! pozor: server hlásí {total} postav, přečetl jsem {len(out)}")
    return out


def slug(name, cid):
    """Jmeno slozky. Jmena byvaji cele prompty na tisic znaku, takze se zkracuji —
    a doplnuji kouskem id, aby dve postavy se stejnym zacatkem nespadly do jedne."""
    s = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
    return (s[:40].rstrip("_") or "postava") + "__" + cid[:8]


# ================================================================== UTRACENI
#
# Vsechno vys jen CTE. Od tehle cary se PLATI, a proto tu plati jina pravidla.
#
# KDE MIZI KREDITY. Zmereno a sepsane v docs/PIXELLAB.md; tady je to vymahane kodem,
# protoze dokumentace, kterou clovek musi mit v hlave, nikoho neochrani:
#
#   1. Postava stoji 1 generaci, ANIMACE CTYRI. Chuze je 1 generace NA SMER (jih, sever,
#      vychod) a smrt jednu. Kdyz je zaklad spatny, prijdes o ctyri naraz, ne o jednu —
#      proto je mezi `new` a `anim` BRANA a bez verdiktu se animovat neda.
#   2. Nad 64 px si `animate_character` sam zvoli rezim `pro`, coz je 20 AZ 40 GENERACI
#      NA SMER. U bosse ve 128 px se tak spustila zakazka, kterou nikdo nechtel. Proto se
#      `mode:"v3"` posila vzdycky a natvrdo.
#   3. Zapad se negeneruje. Hra si ho zrcadli sama (`distraction_animator.gd`,
#      `defender_unit.gd:415`), takze kazdy zaplaceny zapad je vyhozeny.
#   4. Souběžnych jobu je nejvys deset a jedenacty se vrati jako TEXT, ne jako vyjimka —
#      skript si toho nemusi vsimnout a tvari se to jako selhani generatoru.
#
# Cokoli, co plati, se proto pta pred utracenim a zapisuje do uctu.

UCET = os.path.join(PROJ, "build", "pixellab", "_ucet.json")

# Kolik generaci co stoji. Cisla z docs/PIXELLAB.md, ne odhad.
CENA_POSTAVA = 1
CENA_ZA_SMER = 1
PRO_ZA_SMER = 30          # stred rozsahu 20-40; jen pro odhad skody, kdyz se rezim ujede
SMERY_HRA = ["south", "north", "east"]   # zapad si hra zrcadli


def ucet_nacti():
    try:
        with open(UCET, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {"zaznamy": [], "celkem_generaci": 0}


def ucet_zapis(zaznam):
    """Prida radek do uctu. Vraci nove celkove cislo.

    Ucet neni ucetnictvi pro ucetnictvi: bez nej se za tyden zaplati podruhe za neco, co uz
    lezi v build/pixellab, a nikdo to nepozna, protoze slozka se jmenuje podle promptu."""
    u = ucet_nacti()
    u["zaznamy"].append(zaznam)
    u["celkem_generaci"] = u.get("celkem_generaci", 0) + int(zaznam.get("generaci", 0))
    os.makedirs(os.path.dirname(UCET), exist_ok=True)
    with open(UCET, "w", encoding="utf-8") as f:
        json.dump(u, f, indent=2, ensure_ascii=False)
    return u["celkem_generaci"]


def verdikt(character_id):
    """Posledni verdikt brany pro postavu, nebo None."""
    for z in reversed(ucet_nacti()["zaznamy"]):
        if z.get("character_id") == character_id and z.get("verdikt"):
            return z
    return None


def potvrd(kolik, co, ano=False):
    """Zeptej se pred utracenim. `--yes` to preskoci, ale musi se napsat vedome."""
    print(f"\n  STOJÍ TO {kolik} generací: {co}")
    if ano:
        print("  (--yes, jedu)")
        return True
    try:
        return input("  pokračovat? [a/N] ").strip().lower() in ("a", "ano", "y", "yes")
    except EOFError:
        print("  není terminál a nebylo --yes → neutrácím")
        return False


def volne_sloty(c):
    """Kolik z deseti soubeznych jobu je volnych. -1 = nepodarilo se zjistit.

    Cte se to PRED zadanim, protoze jedenacty job se vrati jako text odpovedi
    ("need 1 job slots but only 0 available"), ne jako chyba — a zakazka se tvari jako
    zadana, i kdyz nikdy nevznikla."""
    try:
        text, _ = c.call("list_jobs")
    except SystemExit:
        return -1
    m = re.search(r"(\d+)\s*/\s*10", text)
    if m:
        return 10 - int(m.group(1))
    # Bez explicitniho pomeru se spocitaji radky, ktere jeste bezi.
    bezi = len(re.findall(r"\b(running|creating|processing|queued)\b", text, re.I))
    return max(0, 10 - bezi) if bezi else -1


def cmd_new(c, args):
    """create_character — 1 generace. Zaklad, ze ktereho se pak teprve animuje."""
    if not potvrd(CENA_POSTAVA, f"nová postava „{args.name}“", args.yes):
        return
    call = {"description": args.description, "name": args.name,
            "mode": "v3", "n_directions": args.dirs, "view": args.view}
    if args.ref:
        call["reference_image_url"] = args.ref
    if args.dry:
        print("\n--dry, POSLALO BY SE:\n" + json.dumps(call, indent=2, ensure_ascii=False))
        return
    text, _ = c.call("create_character", call)
    print(text)
    m = re.search(r"([0-9a-f]{8}-[0-9a-f-]{27,})", text)
    cid = m.group(1) if m else None
    celkem = ucet_zapis({"co": "create_character", "character_id": cid,
                         "jmeno": args.name, "prompt": args.description,
                         "generaci": CENA_POSTAVA})
    print(f"\núčet: +{CENA_POSTAVA}, celkem {celkem} generací")
    if cid:
        print(f"\nDALŠÍ KROK — NE animace, ale brána:\n"
              f"  python tools/pixellab.py check {cid}\n"
              f"Animace stojí 4 generace. Bez brány je vyhodíš za základ, "
              f"který jsi neviděl.")


def cmd_check(c, args):
    """BRÁNA. Stáhne rotace, změří je a donutí se na ně podívat — pak teprve smí animace.

    Nerozhoduje za tebe: sprite muze projit vsemi merenimi a stejne byt spatne (a naopak).
    Smysl je, aby mezi zaplacenim postavy a zaplacenim ctyr animaci bylo misto, kde se
    clovek PODIVA. Verdikt se zapise do uctu a `anim` ho vyzaduje."""
    text, _ = c.call("get_character", {"character_id": args.id})
    info = parse_character(text)
    rot = info["rotations"]
    if not rot:
        print("žádné rotace — postava možná ještě běží. Zkus to za chvíli.")
        return
    out = args.out or os.path.join(PROJ, "build", "pixellab", "_brana", args.id[:8])
    os.makedirs(out, exist_ok=True)

    from PIL import Image, ImageDraw
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import numpy as np

    hotove = {}
    for smer, urls in sorted(rot.items()):
        p = os.path.join(out, f"{smer}.png")
        if not os.path.isfile(p):
            save(p, fetch(urls[0]))
        hotove[smer] = Image.open(p).convert("RGBA")
    print(f"staženo {len(hotove)} rotací -> {os.path.relpath(out, PROJ)}")

    # Znamkovani tymz meritkem jako lokalni generator, at se cisla daji porovnavat.
    znamky = {}
    try:
        import gen
        for smer, im in hotove.items():
            a = np.array(im)
            znamky[smer] = gen.score(a, max(a.shape[:2]))["grade"]
    except Exception as e:
        print(f"  (známkování přeskočeno: {type(e).__name__})")

    Z = 4
    w = max(i.width for i in hotove.values()) * Z
    sheet = Image.new("RGB", (8 + len(hotove) * (w + 8), w + 30), (24, 22, 30))
    dr = ImageDraw.Draw(sheet)
    for i, (smer, im) in enumerate(sorted(hotove.items())):
        x = 8 + i * (w + 8)
        r = im.resize((w, w), Image.NEAREST)
        sheet.paste(r, (x, 6), r)
        popis = smer + (f"  {znamky[smer]:.1f}" if smer in znamky else "")
        dr.text((x, w + 12), popis, fill=(200, 195, 210))
    list_path = os.path.join(out, "_list.png")
    sheet.save(list_path)
    print(f"kontaktní list: {os.path.relpath(list_path, PROJ)}")
    if znamky:
        print("  známky: " + "  ".join(f"{k} {v:.1f}" for k, v in sorted(znamky.items())))

    if args.verdict:
        v = args.verdict
    else:
        print("\nPODÍVEJ SE NA TEN LIST. Teprve pak rozhoduj — animace stojí 4 generace.")
        try:
            v = "ok" if input("  je základ dobrý? [a/N] ").strip().lower() in (
                "a", "ano", "y", "yes") else "zamitnuto"
        except EOFError:
            print("  není terminál → nezapisuji verdikt")
            return
    celkem = ucet_zapis({"co": "check", "character_id": args.id, "verdikt": v,
                         "znamky": znamky, "generaci": 0})
    print(f"\nverdikt „{v}“ zapsán (účet beze změny, celkem {celkem})")
    if v == "ok":
        print(f"\n  python tools/pixellab.py anim {args.id}")


def cmd_anim(c, args):
    """animate_character — 4 generace na příšeru. Bez schváleného základu odmítne."""
    z = verdikt(args.id)
    if not args.force and (not z or z.get("verdikt") != "ok"):
        stav = z.get("verdikt") if z else "žádný"
        sys.exit(f"Základ neprošel bránou (verdikt: {stav}).\n"
                 f"  python tools/pixellab.py check {args.id}\n"
                 f"Tohle je tu schválně: animace stojí 4 generace a za neviděný "
                 f"základ je to nejdražší způsob, jak přijít o kredity.\n"
                 f"(Vážně to chceš? --force.)")

    smery = [s.strip() for s in args.dirs.split(",") if s.strip()] if args.dirs else SMERY_HRA
    if "west" in smery:
        print("POZOR: západ si hra zrcadlí sama — je to zaplacená generace navíc.")

    text, _ = c.call("get_character", {"character_id": args.id})
    velikost = parse_character(text).get("size") or "?"
    px = max([int(n) for n in re.findall(r"\d+", velikost)] or [0])
    if px > 64:
        print(f"POZOR: postava je {velikost}. Nad 64 px si animace umí sama zvolit režim "
              f"'pro' — to je {PRO_ZA_SMER}× dráž na směr (~{PRO_ZA_SMER * len(smery)} "
              f"generací místo {len(smery)}). Posílám mode='v3' natvrdo.")

    volne = volne_sloty(c)
    if volne >= 0 and volne < len(smery):
        sys.exit(f"Volných jobů je jen {volne}, potřebuješ {len(smery)}. "
                 f"Jedenáctý job se vrátí jako text, ne jako chyba — počkej.")

    cena = CENA_ZA_SMER * len(smery) + (CENA_ZA_SMER if not args.no_death else 0)
    popis = f"chůze {'+'.join(smery)}" + ("" if args.no_death else " + smrt south")
    if not potvrd(cena, popis, args.yes):
        return

    zakazky = [{"character_id": args.id, "template_animation_id": args.walk,
                "animation_name": args.name_walk, "directions": smery, "mode": "v3"}]
    if not args.no_death:
        zakazky.append({"character_id": args.id, "template_animation_id": args.death,
                        "animation_name": args.name_death, "directions": ["south"],
                        "mode": "v3"})
    if args.dry:
        print("\n--dry, POSLALO BY SE:\n" + json.dumps(zakazky, indent=2, ensure_ascii=False))
        return
    for zak in zakazky:
        t, _ = c.call("animate_character", zak)
        print(t)
    celkem = ucet_zapis({"co": "animate_character", "character_id": args.id,
                         "smery": smery, "generaci": cena})
    print(f"\núčet: +{cena}, celkem {celkem} generací")


def cmd_ucet(c, args):
    u = ucet_nacti()
    if not u["zaznamy"]:
        print(f"účet je prázdný ({os.path.relpath(UCET, PROJ)})")
        return
    print(f"{len(u['zaznamy'])} záznamů, celkem {u['celkem_generaci']} generací\n")
    for z in u["zaznamy"][-args.n:]:
        cid = (z.get("character_id") or "")[:8]
        extra = z.get("verdikt") or z.get("jmeno") or ""
        print(f"  {z.get('generaci', 0):>3}g  {z['co']:<20} {cid:<9} {str(extra)[:44]}")


def cmd_list(c, args):
    if not args.all:
        text, _ = c.call("list_characters")
        print(text)
        return
    rows = all_characters(c)
    print(f"{len(rows)} postav\n")
    for r in rows:
        print(f"  {r['id']}  {r['dirs']:<6} {r['size']:<9} {r['name'][:70]}")


def cmd_pull_all(c, args):
    rows = all_characters(c)
    print(f"{len(rows)} postav ke stažení -> {os.path.relpath(args.out, PROJ)}\n")
    done = skipped = 0
    for i, r in enumerate(rows, 1):
        d = os.path.join(args.out, slug(r["name"], r["id"]))
        if args.skip_existing and os.path.isdir(d) and os.listdir(d):
            print(f"[{i:>2}/{len(rows)}] {os.path.basename(d):<52} už staženo")
            skipped += 1
            continue
        print(f"[{i:>2}/{len(rows)}] {os.path.basename(d):<52} {r['size']}", flush=True)
        sub = argparse.Namespace(id=r["id"], out=d, anim=None, dir=None, quiet=True)
        try:
            cmd_pull(c, sub)
        except SystemExit as e:
            print(f"     ! {e}")
            continue
        # Jmeno a id vedle artu — bez toho se za tyden neda zjistit, ze slozka
        # `64x64_pixel_art_character_sprite_colossal__8bf0cd70` je boss.
        with open(os.path.join(d, "character.json"), "w", encoding="utf-8") as f:
            json.dump(r, f, ensure_ascii=False, indent=2)
        done += 1
    print(f"\nstaženo {done}, přeskočeno {skipped}")


def cmd_get(c, args):
    text, imgs = c.call("get_character", character_id=args.id)
    print(text)
    if imgs and args.out:
        save(os.path.join(args.out, "preview.png"), imgs[0])
        print(f"\nnáhled -> {args.out}/preview.png")


def cmd_pull(c, args):
    text, _ = c.call("get_character", character_id=args.id)
    info = parse_character(text)
    print(f"{info['name']}\nrozlišení: {info['size']}   "
          f"rotací: {len(info['rotations'])}   animací: {len(info['animations'])}\n")

    todo = []
    if not args.anim:
        for d, urls in info["rotations"].items():
            if args.dir and d != args.dir:
                continue
            todo.append((f"rotace/{d}", urls))
    for a, dirs in info["animations"].items():
        if args.anim and a != args.anim:
            continue
        for d, urls in dirs.items():
            if args.dir and d != args.dir:
                continue
            todo.append((f"{a}/{d}", urls))

    if not todo:
        raise SystemExit("nic k stažení (zkontroluj --anim / --dir)")

    total, failed = 0, 0
    for label, urls in todo:
        group, d = label.split("/", 1)
        got = 0
        for i, u in enumerate(urls, 1):
            # Cislovani od 1, at sedi na konvenci hry (<stem>_frame_1.png). PixelLab
            # cisluje soubory od nuly, takze prevzit jeho jmena by posunulo cely cyklus.
            name = f"{d}.png" if len(urls) == 1 else f"{d}_frame_{i}.png"
            try:
                save(os.path.join(args.out, group, name), fetch(u))
            except Exception as e:                                # noqa: BLE001
                print(f"  ! {label} #{i}: {type(e).__name__} {getattr(e, 'code', e)}")
                failed += 1
                continue
            got += 1
        total += got
        if not getattr(args, "quiet", False):
            print(f"  {label:<26} {got:>3} PNG")
    print(f"\nhotovo, {total} PNG v {os.path.relpath(args.out, PROJ)}"
          + (f"   ({failed} selhalo)" if failed else ""))


def main():
    ap = argparse.ArgumentParser(description="Přímý klient k PixelLab MCP (bez MCP vrstvy).")
    sub = ap.add_subparsers(dest="cmd", required=True)

    # --- co PLATÍ (viz sekce UTRACENI) -------------------------------------
    p = sub.add_parser("new", help="nová postava (1 generace)")
    p.add_argument("description", help="anglický prompt — plnou podobu dá prompt_assist")
    p.add_argument("--name", required=True)
    p.add_argument("--ref", metavar="URL", help="reference_image_url (otočí HOTOVÝ sprite)")
    p.add_argument("--dirs", type=int, default=8, help="n_directions (default 8)")
    p.add_argument("--view", default="low top-down")
    p.add_argument("--yes", action="store_true", help="neptej se před utracením")
    p.add_argument("--dry", action="store_true", help="jen ukaž, co by se poslalo")
    p.set_defaults(fn=cmd_new)

    p = sub.add_parser("check", help="BRÁNA: stáhni, změř a podívej se, než platíš animace")
    p.add_argument("id")
    p.add_argument("--out")
    p.add_argument("--verdict", choices=["ok", "zamitnuto"], help="bez ptaní")
    p.set_defaults(fn=cmd_check)

    p = sub.add_parser("anim", help="animace (4 generace) — vyžaduje schválený základ")
    p.add_argument("id")
    p.add_argument("--dirs", help=f"směry chůze (default {','.join(SMERY_HRA)})")
    p.add_argument("--walk", default="sad-walk", help="šablona chůze")
    p.add_argument("--death", default="falling-back-death", help="šablona smrti")
    p.add_argument("--name-walk", default="td_walk")
    p.add_argument("--name-death", default="td_death")
    p.add_argument("--no-death", action="store_true", help="jen chůze")
    p.add_argument("--force", action="store_true", help="i bez schváleného základu")
    p.add_argument("--yes", action="store_true")
    p.add_argument("--dry", action="store_true")
    p.set_defaults(fn=cmd_anim)

    p = sub.add_parser("ucet", help="co se zatím utratilo")
    p.add_argument("--n", type=int, default=20)
    p.set_defaults(fn=cmd_ucet)

    # --- co jen ČTE --------------------------------------------------------
    p = sub.add_parser("list", help="vypsat postavy")
    p.add_argument("--all", action="store_true", help="projít všechny stránky")
    p.set_defaults(fn=cmd_list)

    p = sub.add_parser("get", help="detail postavy (odkazy na rotace a animace)")
    p.add_argument("id")
    p.add_argument("--out", help="uložit sem i náhled")
    p.set_defaults(fn=cmd_get)

    p = sub.add_parser("pull-all", help="stáhnout VŠECHNY postavy (záloha + dataset)")
    p.add_argument("--out", default=os.path.join(PROJ, "build", "pixellab"))
    p.add_argument("--skip-existing", action="store_true", default=True)
    p.add_argument("--force", dest="skip_existing", action="store_false")
    p.set_defaults(fn=cmd_pull_all)

    p = sub.add_parser("pull", help="stáhnout rotace a animace do složky")
    p.add_argument("id")
    p.add_argument("--out", required=True)
    p.add_argument("--anim", help="jen tahle animace")
    p.add_argument("--dir", help="jen tenhle směr (south/east/…)")
    p.set_defaults(fn=cmd_pull)

    args = ap.parse_args()
    args.fn(Client(), args)


if __name__ == "__main__":
    main()
