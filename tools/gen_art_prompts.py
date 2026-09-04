"""Vygeneruj docs/art/GENERATION_PLAN.md ze STYLE_BIBLE.md a z obsahu data/.

    python tools/gen_art_prompts.py            # zapiš docs/art/GENERATION_PLAN.md
    python tools/gen_art_prompts.py --stdout   # vypiš, nic nezapisuj
    python tools/gen_art_prompts.py --check    # 0 = plán na disku sedí, 1 = je zvětralý

PROC TENHLE NASTROJ EXISTUJE

Prompty psane rucne do chatu se ztrati pri prvnim /clear. Prompty psane natvrdo do
skriptu se rozejdou se stylovou bibli, protoze nikdo neaktualizuje dve mista naraz.
Tenhle generator je proto CISTA TRANSFORMACE: vsechna vytvarna rozhodnuti zijou
v docs/art/STYLE_BIBLE.md ve strojove ctenych blocich `<!-- gen:klic -->`, vsechna
obsahova v data/*.tres, a tady je jen slepovani. Kdyz se ma zmenit prompt, meni se
bible; kdyz se ma pridat entita, pridava se .tres. Tenhle soubor se nemeni ani v
jednom pripade.

DETERMINISMUS JE POZADAVEK, NE VLASTNOST
Dvakrat spusteny generator musi dat BIT-IDENTICKY vystup, jinak `--check` nema smysl
a diff v gitu lze. Proto: zadny time/datum ve vystupu, zadny `hash()` (per-proces
solene v Pythonu 3.3+ -- pouziva se hashlib), vsechny globy pres sorted(), vsechny
dicty serializovane se sort_keys, a zapis vzdy s newline="\\n", aby to nezaviselo na
tom, ze tohle je Windows.

CO TENHLE SKRIPT NEDELA: nic negeneruje a nikam nevola. Vyrabi TEXT.
"""
import argparse
import glob
import hashlib
import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIBLE = os.path.join(ROOT, "docs", "art", "STYLE_BIBLE.md")
PLAN = os.path.join(ROOT, "docs", "art", "GENERATION_PLAN.md")
SCHEMA = os.path.join(ROOT, "tools", "pixellab_schema.json")

# Slozky v data/, ktere maji vizualni protejsek. Zamerne NENI seznam vseho pod data/:
# ads/cards/interventions/growth/insight_cards nemaji pole na texturu a nekresli se ze
# spritu (AdOverlay je dokonce schvalne mimo styl projektu) -- viz STYLE_BIBLE.md §8.
DATA_KINDS = {
    "distractions": ("distraction", "distraction_boss"),
    "habits": ("habit",),
    "defenders": ("defender",),
}

PALETTE_URL = "docs/art/palette_48.png"


# ---------------------------------------------------------------- bible parsing

def _block(text, key):
    """Syrovy obsah mezi <!-- gen:key --> a <!-- /gen:key -->."""
    m = re.search(
        r"<!--\s*gen:%s\s*-->(.*?)<!--\s*/gen:%s\s*-->" % (re.escape(key), re.escape(key)),
        text, re.S)
    if not m:
        raise SystemExit("STYLE_BIBLE.md: chybi blok <!-- gen:%s -->" % key)
    return m.group(1)


def _table(text, key):
    """Markdown tabulka z bloku -> list dictu klicovanych zahlavim."""
    rows = [ln.strip() for ln in _block(text, key).splitlines() if ln.strip().startswith("|")]
    if len(rows) < 2:
        raise SystemExit("STYLE_BIBLE.md: blok gen:%s neni tabulka" % key)

    def cells(line):
        return [c.strip() for c in line.strip().strip("|").split("|")]

    head = cells(rows[0])
    out = []
    for line in rows[1:]:
        c = cells(line)
        if all(set(x) <= set("-: ") for x in c):   # oddelovaci radek
            continue
        if len(c) != len(head):
            raise SystemExit("STYLE_BIBLE.md: gen:%s ma radek s %d sloupci misto %d: %s"
                             % (key, len(c), len(head), line[:70]))
        out.append(dict(zip(head, c)))
    return out


def _fence(text, key, lang):
    """Obsah ```lang bloku uvnitr <!-- gen:key -->, bez koncoveho newline."""
    m = re.search(r"```%s\n(.*?)\n```" % re.escape(lang), _block(text, key), re.S)
    if not m:
        raise SystemExit("STYLE_BIBLE.md: v gen:%s chybi ```%s blok" % (key, lang))
    return m.group(1).strip()


def _kv(spec):
    """'a=1, b=2 3' -> {'a': '1', 'b': '2 3'}; poradi se drzi pres sorted az pri vypisu."""
    out = {}
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        k, _, v = part.partition("=")
        out[k.strip()] = v.strip()
    return out


def load_bible(path=BIBLE):
    text = io.open(path, encoding="utf-8").read()
    b = {
        "sizes": {r["kind"]: r for r in _table(text, "sizes")},
        "anchors": {r["rodina"]: r for r in _table(text, "anchors")},
        "tools": {r["kind"]: r for r in _table(text, "tools")},
        "batching": {r["kind"]: r for r in _table(text, "batching")},
        "pricing": {r["tier"]: r for r in _table(text, "pricing")},
        "forms": _table(text, "forms"),
        "phases": _table(text, "phases"),
        "selected": {r["id"]: r for r in _table(text, "selected")},
        "contrast": _table(text, "contrast"),
        "vocabulary": _table(text, "vocabulary"),
        "suffix": _fence(text, "suffix", "suffix"),
        "design_constraints": _fence(text, "design_constraints", "design_constraints"),
        "negative": _fence(text, "negative", "negative"),
        "why0": _block(text, "why0").strip(),
        "gate0": _block(text, "gate0").strip(),
    }
    for r in b["forms"]:
        if r["kind"] not in b["sizes"]:
            raise SystemExit("STYLE_BIBLE.md: %s ma kind '%s', ktery neni v gen:sizes"
                             % (r["id"], r["kind"]))
        if r["kind"] not in b["tools"]:
            raise SystemExit("STYLE_BIBLE.md: kind '%s' neni v gen:tools" % r["kind"])
        if r["family"] != "-" and r["family"] not in b["anchors"]:
            raise SystemExit("STYLE_BIBLE.md: %s ma rodinu '%s', ktera neni v gen:anchors"
                             % (r["id"], r["family"]))
    return b


# ---------------------------------------------------------------- data/ inventory

_ID_RE = re.compile(r'^id\s*=\s*&?"([^"]+)"', re.M)


def data_ids(folder):
    """Ziva id z data/<folder>/*.tres.

    Fallback na jmeno souboru je nutny, ne kosmeticky: Godot vynechava vlastnost, ktera
    se rovna defaultu ve skriptu, takze notification.tres nema radku `id` vubec a jeho
    cele telo je `[resource]` + `script = ExtResource(...)`.
    """
    out = {}
    for p in sorted(glob.glob(os.path.join(ROOT, "data", folder, "*.tres"))):
        text = io.open(p, encoding="utf-8").read()
        m = _ID_RE.search(text)
        out[m.group(1) if m else os.path.basename(p)[:-5]] = os.path.relpath(p, ROOT).replace("\\", "/")
    return out


def check_bijection(bible):
    """Kazda entita z data/ ma prave jeden zaznam v bibli a naopak.

    Plati jen pro kindy, ktere z data/ pochazeji -- teren, rekvizity a Focus core zadny
    .tres nemaji a mit nemaji.
    """
    problems = []
    by_kind = {}
    for r in bible["forms"]:
        by_kind.setdefault(r["kind"], []).append(r["id"])

    seen = [r["id"] for r in bible["forms"]]
    for dup in sorted({i for i in seen if seen.count(i) > 1}):
        problems.append("gen:forms ma id '%s' vickrat" % dup)

    for folder, kinds in sorted(DATA_KINDS.items()):
        on_disk = set(data_ids(folder))
        in_plan = set()
        for k in kinds:
            in_plan |= set(by_kind.get(k, []))
        for missing in sorted(on_disk - in_plan):
            problems.append("data/%s/%s.tres nema zaznam v gen:forms" % (folder, missing))
        for extra in sorted(in_plan - on_disk):
            problems.append("gen:forms ma '%s' (kind %s), ale zadne data/%s/*.tres"
                            % (extra, "/".join(kinds), folder))
    return problems


# ---------------------------------------------------------------- record building

def _phase_of(entity_id, kind, phases):
    """Prvni faze, ktera entitu vybere. 'id:x' vybira konkretni kus, holy nazev cely kind."""
    for ph in phases:
        for sel in [s.strip() for s in ph["kinds"].split(",")]:
            if sel.startswith("id:"):
                if sel[3:] == entity_id:
                    return ph
            elif sel == kind:
                return ph
    raise SystemExit("STYLE_BIBLE.md: %s (kind %s) nespada do zadne faze" % (entity_id, kind))


def _order_within(rows, eff_base):
    """Seradi fazi podle HLOUBKY zavislosti, uvnitr hloubky abecedne.

    Ciste topologicke razeni by proslo, ale davkovani by na nem selhalo: seradilo by
    `accountability` a hned za nim `accountability_2`, takze by oba spadly do TEHOZ
    volani -- a tier 2 potrebuje `init_image_url` z hotoveho PNG tier 1, ktere v tu
    chvili jeste neexistuje. Hloubka udela to, ze cela vrstva 0 se vygeneruje driv, nez
    zacne vrstva 1, a davky se tim rozdeli spravne samy.
    """
    ids = {r["id"] for r in rows}
    by_id = {r["id"]: r for r in rows}

    def depth(r, seen=frozenset()):
        b = eff_base(r)
        if b in ("-", "") or b not in ids or b in seen:   # cizi faze nebo cyklus
            return 0
        return 1 + depth(by_id[b], seen | {r["id"]})

    return sorted(rows, key=lambda r: (depth(r), r["id"]))


def terrain_riders(bible):
    """Kdo se veze v cizim tileset volani.

    `tile_feature="tileset"` kresli DVA tereny naraz a nedá se kombinovat se
    `style_images`, takze kazde volani vyrobi svuj teren i `terrain_tissue` jako druhy.
    Koren rodiny (teren bez `base`) tedy vlastni volani nema a nesmi ho platit -- vznikne
    v prvnim volani, ktere ho jako druhy teren pouzije. Bez tohohle by faze 0 stala 80
    generaci misto 40 za neco, co uz jednou vzniklo.
    """
    terr = [r for r in bible["forms"] if r["kind"] == "terrain"]
    roots = [r["id"] for r in terr if r["base"] in ("-", "")]
    out = {}
    for root in sorted(roots):
        leaders = sorted(r["id"] for r in terr if r["base"] == root)
        if leaders:
            out[root] = leaders[0]
    return out


def _seed(entity_id):
    """Stabilni seed. hashlib, ne hash() -- ten je od Pythonu 3.3 solen per proces."""
    return int(hashlib.sha1(entity_id.encode("utf-8")).hexdigest()[:6], 16) % 100000


def _price(bible, tier):
    return int(bible["pricing"][tier]["generaci"])


def load_schema(path=SCHEMA):
    """Zivé JSON schéma vybraných PixelLab nástrojů, ZAMRAZENÉ v tools/pixellab_schema.json
    (`tools/fetch_pixellab_schema.py` — jediné místo v repu, které smí mluvit se
    serverem). Tahle funkce na síť NESAHÁ, jen čte commitnutou kopii; generátor sám
    musí zůstat čistou transformací (vlastní docstring, DETERMINISMUS JE POZADAVEK)."""
    if not os.path.isfile(path):
        raise SystemExit("chybí %s -- spusť `python tools/fetch_pixellab_schema.py`"
                          % os.path.relpath(path, ROOT))
    with io.open(path, encoding="utf-8") as f:
        return json.load(f)


def adapt_to_schema(mcp_tool, params, schema):
    """Osekej `params` na to, co dané MCP volání OPRAVDU přijme, podle živého schématu
    zamrazeného v `tools/pixellab_schema.json` -- ne podle katalogu z dokumentace,
    který se s API rozešel (A0/PROGRESS.md: fáze 0 dostala na první pokus 3-4
    validation errors na volání a 0 utracených generací, protože `color_image_url`,
    `seed` a `negative_description` na `create_character`/`create_1_direction_object`
    vůbec neexistují -- psalo se to proti `create_image_pixflux`).

    Kromě filtru na jména hlídá i dvě věci, které živé schéma nese v próze svých
    `description` a `tools/fetch_pixellab_schema.py` z nich vytahuje do strojového
    tvaru (`enums`, `conflicts`) -- žádná z nich se sem neopisuje jako konstanta:

    * **vzájemně se vylučující pole** (`conflicts`). `create_1_direction_object`
      říká doslova "Cannot be set together with style_images -- when style_images
      are provided, the largest style image determines the output size", takže
      `size` + `style_images` v jednom volání je odmítnutí, ne kompromis. Padá to
      tvrdě: kdyby se jedno z dvojice tiše zahodilo, plán by tvrdil něco jiného,
      než co se pošle, a to je přesně ta třída chyby, kvůli které tenhle filtr
      vznikl.
    * **neplatné hodnoty enumu** (`enums`). Filtr na jména pustí `body_type` dál,
      protože pole existuje -- ale hodnota mimo `["humanoid", "quadruped"]` se
      pozná až na serveru. Plán je poslední místo, kde to nic nestojí.

    Vrací (payload, vyhozené pole). SystemExit, když po oseku chybí povinné pole --
    lepší nahlas selhat při generování plánu, než tiše poslat neplatné volání
    o dávky později (A0b, docs/refactor/-- "tohle se nesmí opakovat u Phase 1")."""
    name = mcp_tool.rsplit("__", 1)[-1]
    if name not in schema:
        raise SystemExit(
            "tools/pixellab_schema.json nezná nástroj '%s' -- spusť "
            "`python tools/fetch_pixellab_schema.py`" % name)
    spec = schema[name]
    allowed = set(spec["properties"])
    required = set(spec["required"])
    payload = {k: v for k, v in params.items() if k in allowed}
    missing = required - set(payload)
    if missing:
        raise SystemExit(
            "%s: po oseku na živé schéma chybí povinné pole %s (entita ho musí "
            "dodat před filtrací)" % (name, sorted(missing)))
    for pair in spec.get("conflicts", []):
        if all(k in payload for k in pair):
            raise SystemExit(
                "%s: %s se podle živého schématu nesmí poslat současně -- "
                "volající musí jedno z nich vynechat, filtr to za něj neuhodne"
                % (name, " + ".join(sorted(pair))))
    for key, values in sorted(spec.get("enums", {}).items()):
        if key in payload and str(payload[key]) not in [str(v) for v in values]:
            raise SystemExit(
                "%s: %s=%r není v živém enumu %s" % (name, key, payload[key], values))
    return payload, sorted(set(params) - allowed)


def style_images_payload(bible, items, size, root=ROOT):
    """Referenční položky z plánu -> to, co API opravdu bere.

    V plánu je style reference zapsaná JMÉNEM ENTITY (`{"entity": "focus_timer",
    "format": "png"}`), ne cestou ani daty. Tři důvody, všechny tvrdé:

    1. Cestu ke konkrétnímu vybranému kandidátovi vlastní `gen:selected` v bibli
       (STYLE_BIBLE.md) -- kdyby ji plán nesl podruhé, rozešly by se v okamžiku,
       kdy uživatel vybere jiného kandidáta.
    2. API bere `style_images` VÝHRADNĚ jako base64 (`{"base64": ..., "format":
       "png"}`, max 256x256 px). Base64 nesmí do kontextu ani do dokumentu
       (CLAUDE.md) -- vzniká proto až tady, v paměti, těsně před voláním.
    3. `size` se se `style_images` poslat nedá (viz `adapt_to_schema`) a výstupní
       velikost určuje NEJVĚTŠÍ style image. Kontrola nad rozměrem tedy zbývá
       jediná: zmenšit referenci na `size` (= `gen_px` daného kindu) dřív, než se
       odešle. Proto je `size` povinný argument, ne volitelný -- bez něj by
       32px rekvizita zdědila 96px rozměr Focus core a nikdo by si toho nevšiml
       až do stažení výsledku.

    Vrací seznam ve tvaru, který schéma přijímá. SystemExit, když entita ještě
    nemá vybraného kandidáta -- objednat dědičnost z něčeho, co si uživatel
    nevybral, nejde."""
    import base64
    from PIL import Image

    out = []
    for item in items:
        eid = item["entity"]
        sel = bible["selected"].get(eid)
        if not sel:
            raise SystemExit(
                "style reference '%s' nemá řádek v gen:selected -- uživatel z něj "
                "ještě nevybral kandidáta, takže není z čeho dědit" % eid)
        path = os.path.join(root, sel["soubor"].replace("/", os.sep))
        if not os.path.isfile(path):
            raise SystemExit("gen:selected říká %s, ale ten soubor neexistuje"
                             % sel["soubor"])
        im = Image.open(path).convert("RGBA")
        if im.size != (size, size):
            im = im.resize((size, size), Image.NEAREST)
        buf = io.BytesIO()
        im.save(buf, format="PNG")
        out.append({"type": "base64", "format": "png",
                    "base64": base64.b64encode(buf.getvalue()).decode("ascii")})
    return out


def build(bible, schema):
    """Zaznamy v poradi generovani, uz se spoctenymi davkami a cenami."""
    forms = {r["id"]: r for r in bible["forms"]}
    phases = bible["phases"]
    riders = terrain_riders(bible)              # koren terenu -> volani, ve kterem se veze

    def eff_base(r):
        """Poradi kresleni. Koren terenu jde AZ ZA volanim, ktere ho vyrobi."""
        return riders.get(r["id"], r["base"])

    buckets = {}
    for r in bible["forms"]:
        ph = _phase_of(riders.get(r["id"], r["id"]), r["kind"], phases) \
            if r["id"] in riders else _phase_of(r["id"], r["kind"], phases)
        buckets.setdefault(ph["phase"], []).append(r)

    records, index = [], 0
    batch_no = 0
    for ph in phases:
        rows = _order_within(buckets.get(ph["phase"], []), eff_base)
        open_batches = {}                       # kind -> (batch_id, [ids], zdroj stylu)
        for r in rows:
            kind, eid = r["kind"], r["id"]
            # `size` je cil na disku, `gen` je to, co se objedna. Lisi se u vseho, co se
            # pulí (postavy) nebo co se pod svou cilovou velikosti negeneruje cistě.
            size = int(bible["sizes"][kind]["art_px"])
            gen = int(bible["sizes"][kind]["gen_px"])
            tool = bible["tools"][kind]
            fixed = _kv(tool["pevne_parametry"])
            maxbatch = int(bible["batching"][kind]["max_v_davce"])

            # Cena se ridi objednanou velikosti, ne cilovou -- boss stoji 40 proto,
            # ze se objednava na 128, ne proto, ze na disku ma 64.
            tier = "tileset" if tool["mcp_tool"].endswith("create_tiles_pro") else (
                "pro" if gen <= 64 else "pro_velky")

            # Po kom se dedi styl. Teren se sem nepocita (`tile_feature` a
            # `style_images` se podle ziveho schematu vylucuji, viz terrain_riders()),
            # stejne tak koren rodiny a ten, kdo se veze v cizim volani. Musi se to
            # vedet uz TADY, protoze podle toho se deli davky (nize).
            style_from = None
            if eid not in riders and tier != "tileset" and r["base"] not in ("-", ""):
                style_from = r["base"]

            # Davka: az `maxbatch` polozek sdili jedno volani. Kdo davku otevre, plati.
            batch_id, leads = None, True
            if eid in riders:
                batch_id, leads = "tileset_%s" % riders[eid], False
            elif kind == "terrain":
                batch_id = "tileset_%s" % eid
            elif maxbatch > 1:
                cur = open_batches.get(kind)
                # Do jedne davky nesmi spadnout entita se svym vlastnim `base`: jedno
                # volani vznika naraz, takze by se odkazovalo na PNG, ktere jeste neni.
                #
                # A nesmi se michat ZDROJE STYLU. `style_images` je parametr VOLANI, ne
                # polozky -- jedno volani umi nest jedinou stylovou referenci, at uz v
                # `item_descriptions` sedi ctyri objekty nebo jeden. Do 2026-09-04 to
                # nevadilo jen proto, ze reference nikde v parametrech nebyla (byla to
                # veta ve sloupci "zavislost"); jakmile v parametrech je, davka
                # `habit_05` (accountability_2 + exercise_2 + mindfulness_2 +
                # real_hobby_2, kazdy dedici po JINEM tier 1) je objednavka, kterou API
                # splnit neumi. Deli se proto podle zdroje -- draz, ale objednatelne.
                if (cur and len(cur[1]) < maxbatch and r["base"] not in cur[1]
                        and cur[2] == style_from):
                    batch_id, members, _src = cur
                    members.append(eid)
                    leads = False
                else:
                    batch_no += 1
                    batch_id = "%s_%02d" % (kind, batch_no)
                    open_batches[kind] = (batch_id, [eid], style_from)

            # Design constraints (STYLE_BIBLE.md §7b) jdou hned za formu, PRED technicky
            # suffix (§7) -- obsah driv, technika kresby az po nem. Je to jedina cesta,
            # jak dostat perspektivu do promptu pro `create_1_direction_object`: ten
            # nastroj ma jiny enum `view` a "low top-down" mu poslat nejde (§9).
            prompt = "%s; %s; %s" % (r["form"], bible["design_constraints"], bible["suffix"])

            # negative_description/color_image_url zustavaji v `params` az do filtru
            # nize -- ne proto, ze by je nektery ze tri skutecnych nastroju prijal
            # (nepřijme, viz `adapt_to_schema`'s docstring), ale aby `--stdout`/dry
            # nastroje nize videly, CO by se poslalo pred osekem, ne uz jen vysledek.
            # Zivy dopad: paleta se vynucuje AZ PO generovani pres reduce_colors
            # (docs/art/GENERATION_PLAN.md bod 2), negativy uz nese slovne povinny
            # suffix (STYLE_BIBLE.md §7) -- zadny obsah se filtraci neztraci.
            params = dict(fixed)
            params["negative_description"] = bible["negative"]
            params["color_image_url"] = PALETTE_URL
            # Seed preziva filtr JEN u tileset tier -- `create_tiles_pro` ho zna,
            # `create_character`/`create_1_direction_object` ne (tools/pixellab_schema.json).
            # Kdo se veze v cizim volani, musi mit i jeho seed -- jinak by tabulka
            # tvrdila, ze jde o dve ruzna volani, a nekdo by je oba objednal.
            params["seed"] = _seed(riders.get(eid, eid))

            if tier == "tileset":
                # Dva terény v jednom volání; nastavený bit je PRVNÍ terén (PIXELLAB.md).
                # Kořen rodiny je v každém volání druhý, takže se sady drží pohromadě
                # i bez style_images, které tile_feature="tileset" stejně zakazuje.
                if eid in riders:
                    first, second = forms[riders[eid]]["form"], r["form"]
                else:
                    first, second = r["form"], forms[r["base"]]["form"]
                params["description"] = "1). %s 2). %s; %s; %s" % (
                    first, second, bible["design_constraints"], bible["suffix"])
                params["tile_size"] = gen
                prompt = params["description"]
            elif tool["mcp_tool"].endswith("create_1_direction_object"):
                # `description` je u tohohle nastroje POVINNE (tools/pixellab_schema.json),
                # a plan drzel jen `item_descriptions` -- presne to, co fazi 0 na prvni
                # pokus odmitlo (A0b). `item_descriptions` zustava taky: nezavazny
                # per-kus popis pro pripad, ze `size` vyrobi vic objektu najednou.
                params["description"] = prompt
                params["item_descriptions"] = [prompt]
                # `size` JEN kdyz se nededi styl: zive schema obe pole vylucuje a
                # velikost pak urcuje nejvetsi style image (viz style_images nize).
                if style_from is None:
                    params["size"] = gen
            else:
                params["description"] = prompt
                params["name"] = eid
                params["mode"] = tool["mode"]
                params["size"] = gen

            anchor = None
            if r["family"] != "-":
                anchor = bible["anchors"][r["family"]]
                params["style_character_id"] = anchor["style_character_id"]

            # Dedicnost stylu patri do PARAMETRU volani. Do 2026-09-04 se zapisovala
            # jen jako veta do sloupce "zavislost" -- dokument tvrdil "style_images =
            # hotove PNG entity X", ale v `params` nic takoveho nebylo, takze
            # objednavka by dedila NIC a rozdil by se poznal az na stazenem vysledku.
            # Nastroj rozhoduje, KTERYM parametrem styl cestuje, a rozhoduje o tom
            # zive schema, ne domenka:
            #   * `create_1_direction_object` ma `style_images` -> jde tudy
            #   * `create_character` `style_images` NEMA; u postav nese rodinu
            #     `style_character_id` z gen:anchors (nastavene o par radku vys)
            if style_from is not None and "style_images" in schema[
                    tool["mcp_tool"].rsplit("__", 1)[-1]]["properties"]:
                # Jmeno entity, ne cesta a uz vubec ne base64 -- prevod na to, co bere
                # API, dela `style_images_payload()` az pri volani (viz jeho docstring).
                params["style_images"] = [{"entity": style_from, "format": "png"}]

            # Osek na to, co dane MCP volani OPRAVDU prijme -- viz adapt_to_schema().
            params, _dropped = adapt_to_schema(tool["mcp_tool"], params, schema)

            # Veta ve sloupci "zavislost" popisuje TENTYZ parametr, ktery je o kus vys
            # v `params` -- nikdy jiny. Drive tu stalo `init_image_url` u tier 2 habitu;
            # takovy parametr `create_1_direction_object` v zivem schematu NEMA (jeho
            # pole jsou description/item_descriptions/size/style_images/view), takze
            # to byl slib, ktery API neumi splnit. Tier 2 dedi toutez cestou jako
            # zbytek objektu -- pres `style_images`.
            depends = ""
            if eid in riders:
                depends = ("vzniká jako druhý terén ve volání entity %s — vlastní volání "
                           "nemá a neplatí se" % riders[eid])
            elif tier == "tileset" and r["base"] not in ("-", ""):
                depends = "%s je v tomhle volání druhý terén" % r["base"]
            elif style_from is not None:
                if "style_images" in params:
                    depends = ("`style_images` = vybraný kandidát entity %s "
                               "(gen:selected), zmenšený na %d px — velikost výstupu "
                               "určuje největší style image, proto se `size` neposílá"
                               % (style_from, gen))
                elif "style_character_id" in params:
                    depends = ("rodinu drží `style_character_id` (%s); %s je v plánu "
                               "kořen téže rodiny, ne parametr volání"
                               % (r["family"], style_from))
                else:
                    depends = ("dědí po %s, ale %s pro to nemá parametr — styl nese "
                               "jen text promptu" % (style_from, tool["mcp_tool"]))

            index += 1
            records.append({
                "order": index,
                "phase": ph["phase"],
                "id": eid,
                "kind": kind,
                "size": size,
                "gen": gen,
                "tool": tool["mcp_tool"],
                "poll": tool["poll"],
                "mode": tool["mode"],
                "tier": tier,
                "cost": _price(bible, tier) if leads else 0,
                "batch": batch_id,
                "leads": leads,
                "anchor": anchor,
                "base": r["base"],
                "style_from": style_from,
                "co_produced": riders.get(r["base"]) == eid or eid in riders,
                "depends": depends,
                "prompt": prompt,
                "params": params,
            })
    return records


# ---------------------------------------------------------------- rendering

def _json(obj):
    return json.dumps(obj, indent=2, ensure_ascii=False, sort_keys=True)


def render(bible, records):
    o = []
    w = o.append
    phases = bible["phases"]
    by_phase = {}
    for r in records:
        by_phase.setdefault(r["phase"], []).append(r)

    w("# GENERATION_PLAN.md — kompletní plán generování artu")
    w("")
    w("> **GENEROVÁNO** `python tools/gen_art_prompts.py` ze `docs/art/STYLE_BIBLE.md`")
    w("> a z obsahu `data/`. **Needituj ručně** — přepiš bibli a přegeneruj.")
    w("> `python tools/gen_art_prompts.py --check` vrátí 1, když je tenhle soubor zvětralý.")
    w(">")
    w("> Tenhle dokument **nic negeneruje**. Je to nákupní seznam a rozpočet.")
    w("> `mcp__pixellab__*` je v `settings` na deny a zůstává tam.")
    w("")

    total_calls = sum(1 for r in records if r["leads"])
    total_cost = sum(r["cost"] for r in records)

    w("## Souhrn")
    w("")
    w("| fáze | název | entit | volání | generací |")
    w("|---|---|---|---|---|")
    for ph in phases:
        rows = by_phase.get(ph["phase"], [])
        w("| %s | %s | %d | %d | %d |" % (
            ph["phase"], ph["title"], len(rows),
            sum(1 for r in rows if r["leads"]), sum(r["cost"] for r in rows)))
    w("| **celkem** | | **%d** | **%d** | **%d** |" % (len(records), total_calls, total_cost))
    w("")
    w("**%d entit, %d volání, %d generací** (pesimisticky — horní hranice každého pásma,"
      % (len(records), total_calls, total_cost))
    w("viz STYLE_BIBLE.md §9). Animace se sem nepočítají, jsou vlastní kolo.")
    w("")
    w("Rozpad podle druhu:")
    w("")
    w("| kind | entit | volání | generací | velikost |")
    w("|---|---|---|---|---|")
    for kind in sorted({r["kind"] for r in records}):
        rows = [r for r in records if r["kind"] == kind]
        w("| %s | %d | %d | %d | %d px |" % (
            kind, len(rows), sum(1 for r in rows if r["leads"]),
            sum(r["cost"] for r in rows), rows[0]["size"]))
    w("")

    w("## Co platí pro každé jedno volání")
    w("")
    w("1. **Design constraints** jsou hned za formou entity, doslova, v KAŽDÉM")
    w("   `description` / `item_description`. Zdroj: STYLE_BIBLE.md §7b — je to jediná")
    w("   cesta, jak dostat perspektivu (\"low top-down, zero isometric tilt\") do")
    w("   promptu pro `create_1_direction_object`, jehož `view` parametr \"low top-down\"")
    w("   neumí (§9).")
    w("2. **Povinný suffix** je na konci každého `description` / `item_description`,")
    w("   doslova, za design constraints. Zdroj: STYLE_BIBLE.md §7.")
    w("3. **Paleta se vynucuje AŽ PO generování**, ne v tomhle volání. Ověřeno proti")
    w("   živému schématu (`tools/pixellab_schema.json`): `color_image_url` na")
    w("   `create_character` ani `create_1_direction_object` neexistuje — postava a")
    w("   objekt ho po odeslání tiše zahodí. Paleta se vynutí zvlášť přes")
    w("   `reduce_colors(palette_image_url=%s)` na staženém výsledku (A0/PROGRESS.md)." % PALETTE_URL)
    w("   Žádný prompt neobsahuje hex ani vlastní seznam barev, a 32barevná varianta")
    w("   palety (ta, co podle měření škodí 6 z 10 příšer) se sem nedostane ani jednou.")
    w("4. **`get_balance` před dávkou.** Kvóta se počítá po generacích, ne po voláních.")
    w("5. **Fronta pod deset.** Jedenáctý souběžný job se vrátí *jako text, ne jako")
    w("   chyba* — tělo odpovědi se musí číst, jinak skript čeká na job, který nevznikl.")
    w("6. **Výsledky drží ~8 hodin.** Stáhni hned, `curl` na download URL")
    w("   (nekončí na `.png`), `Authorization: Bearer`. Žádný base64 do kontextu.")
    w("7. **Id se mezi voláním a vyzvednutím přejmenovává:** `get_image(job_id=…)`,")
    w("   `get_tiles_pro(tile_id=…)`, `get_character(character_id=…)`,")
    w("   `get_object(object_id=…)`. Stav, na který se čeká, je `creating`, ne")
    w("   `processing`.")
    w("8. **Po výměně PNG na disku `--headless --import`**, jinak hra tiše kreslí")
    w("   staré textury z cache.")
    w("9. **Objednávka může být větší než cíl.** U postav se generuje na dvojnásobku")
    w("   a půlí se **přesně jednou** — dvakrát půlený obrázek se rozpadne, a `size`")
    w("   menší než obsah kotvy job rovnou odmítne. Každý záznam má obě čísla zvlášť.")
    w("10. **`animate_character` nad 64 px tiše eskaluje na `pro`** = 20–40 generací")
    w("    *na směr*, když se nepošle `mode:\"v3\"` výslovně. Do animací se nesahá dřív,")
    w("    než statická sada projde bránou fáze 3.")
    w("11. **Dědičnost stylu je PARAMETR, ne poznámka.** Entita, která v")
    w("    `STYLE_BIBLE.md` §12 dědí po jiné, to má v `params` níž: objekty přes")
    w("    `style_images`, postavy přes `style_character_id`. `style_images` se v tomhle")
    w("    dokumentu píše jako JMÉNO ENTITY; na base64, které API vyžaduje, ho převede")
    w("    `gen_art_prompts.style_images_payload()` až při volání, ze souboru")
    w("    vybraného v `gen:selected`. Dvě věci z toho plynou a obě jsou měřitelné:")
    w("    dědit jde jen z entity, ze které už uživatel vybral kandidáta, a **`size`")
    w("    se u takového volání neposílá vůbec** — živé schéma obě pole vylučuje a")
    w("    výstupní rozměr určuje největší style image, takže se reference před")
    w("    odesláním zmenší na velikost objednávky.")
    w("12. **`create_character` a `create_1_direction_object` NEMAJÍ žádný parametr pro")
    w("    seed ani jinou formu determinismu** — ověřeno proti živému schématu")
    w("    (`tools/pixellab_schema.json`, A0b). Objednávka stejné postavy/objektu")
    w("    podruhé dá JINÝ výsledek, ne reprodukci. `seed` v `params` níže u nich")
    w("    proto nikdy nedorazí k serveru (filtruje se, viz bod 3) — je to jen")
    w("    stabilní identifikátor záznamu v tomhle plánu, ne kontrola nad generováním.")
    w("    Výjimka je terén (`create_tiles_pro`, dnes v plánu nepoužitý): ten `seed`")
    w("    ve svém živém schématu MÁ, takže by u něj reprodukovatelný byl.")
    w("")
    # Zakazana kotva se tu SCHVALNE necituje. `_test_art_prompts.gd` overuje, ze se
    # jeji uuid nevyskytuje nikde v celem souboru -- kdyby ho sem vypsal i tenhle
    # odstavec, kontrola by padala na vlastni vetu a musela by se oslabit na "jen
    # v promptech". Slabsi kontrola je presne to, co by opustenou kotvu jednou pustilo
    # do parametru. Totez plati pro nazev 32barevne palety o dva odstavce vys.
    w("Kotva označená v `STYLE_BIBLE.md` §6 jako `FORBIDDEN` (opuštěná rodina) se")
    w("v tomhle plánu neobjevuje ani jednou — a `scenes/_test_art_prompts.tscn` to")
    w("ověřuje na celém souboru, ne jen na promptech.")
    w("")

    for ph in phases:
        rows = by_phase.get(ph["phase"], [])
        w("---")
        w("")
        w("## Fáze %s — %s" % (ph["phase"], ph["title"]))
        w("")
        w("**Cena:** %d generací · **volání:** %d · **entit:** %d"
          % (sum(r["cost"] for r in rows), sum(1 for r in rows if r["leads"]), len(rows)))
        w("")
        w("**Brána, než se pustí další fáze:** %s" % ph["gate"])
        w("")
        if ph["phase"] == "0":
            w(bible["why0"])
            w("")
            w(bible["gate0"])
            w("")
        for r in rows:
            w("### %d. `%s` — %s, %d px" % (r["order"], r["id"], r["kind"], r["size"]))
            w("")
            w("| | |")
            w("|---|---|")
            w("| nástroj | `%s` |" % r["tool"])
            w("| mode | `%s` |" % r["mode"])
            w("| vyzvednutí | `%s` |" % r["poll"])
            w("| velikost na disku | %d art px (STYLE_BIBLE.md §5, kind `%s`) |"
              % (r["size"], r["kind"]))
            w("| velikost objednávky | %s |" % (
                "%d px — a pak **půlit přesně jednou** na %d" % (r["gen"], r["size"])
                if r["gen"] != r["size"] else "%d px, bez půlení" % r["gen"]))
            w("| kotva | %s |" % (
                "`%s` (%s)" % (r["anchor"]["style_character_id"], r["anchor"]["rodina"])
                if r["anchor"] else "žádná — není to postava, rodinu drží dědičnost níž"))
            w("| závislost | %s |" % (r["depends"] or "žádná, tohle je kořen rodiny"))
            w("| dávka | %s |" % (
                "samostatné volání" if not r["batch"] else
                "`%s`%s" % (r["batch"], "" if r["leads"] else " — jede v už otevřeném volání")))
            w("| cena | %s |" % (
                "%d generací (tier `%s`)" % (r["cost"], r["tier"]) if r["leads"]
                else "0 — placeno v dávce `%s`" % r["batch"]))
            w("")
            w("**Parametry**")
            w("")
            w("```json")
            w(_json(r["params"]))
            w("```")
            w("")
            w("**Prompt**")
            w("")
            w("```text")
            w(r["prompt"])
            w("```")
            w("")
            sel = bible["selected"].get(r["id"])
            if sel:
                w("**Vybraný kandidát:** `%s` — `%s`" % (sel["kandidat"], sel["soubor"]))
                w("")
                w("%s" % sel["poznamka"])
                w("")

    w("---")
    w("")
    w("## Pořadí a závislosti")
    w("")
    w("| # | fáze | id | závisí na | dávka |")
    w("|---|---|---|---|---|")
    for r in records:
        w("| %d | %s | `%s` | %s | %s |" % (
            r["order"], r["phase"], r["id"],
            ("`%s`" % r["base"]) if r["base"] not in ("-", "") else "—",
            ("`%s`" % r["batch"]) if r["batch"] else "—"))
    w("")
    return "\n".join(o) + "\n"


# ---------------------------------------------------------------- entry point

def check_order(records):
    """Nic se nesmi vazat na neco, co vznikne az pozdeji.

    Bez teto kontroly by plan tise shipnul poradi, ktere nejde provest -- napriklad
    rekvizitu ve fazi 1, jejiz `style_images` maji prijit z Focus core, ktery se
    generuje az ve fazi 2. Na papire to vypada v poradku; pri objednavani to spadne.
    """
    seen, problems = set(), []
    for r in records:
        if r["co_produced"]:
            # Teren a jeho koren vznikaji v JEDNOM volani, takze se na sebe smi vazat
            # navzajem -- neni to poradi, je to jeden nakup.
            seen.add(r["base"])
        if r["base"] not in ("-", "") and r["base"] not in seen:
            problems.append("%s (#%d, faze %s) se vaze na %s, ktery vznikne az pozdeji"
                            % (r["id"], r["order"], r["phase"], r["base"]))
        seen.add(r["id"])
    return problems


def generate():
    bible = load_bible()
    schema = load_schema()
    problems = check_bijection(bible)
    if problems:
        raise SystemExit("STYLE_BIBLE.md vs data/ se rozesly:\n  " + "\n  ".join(problems))
    records = build(bible, schema)
    problems = check_order(records)
    if problems:
        raise SystemExit("STYLE_BIBLE.md: poradi neni proveditelne:\n  " + "\n  ".join(problems))
    return render(bible, records)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--stdout", action="store_true", help="vypis, nezapisuj")
    ap.add_argument("--check", action="store_true",
                    help="over, ze plan na disku sedi a ze je generator deterministicky")
    args = ap.parse_args(argv)

    text = generate()

    if args.check:
        again = generate()
        if again != text:
            print("FAIL: generator neni deterministicky -- dva behy daly ruzny vystup")
            return 1
        if not os.path.exists(PLAN):
            print("FAIL: %s neexistuje; spust `python tools/gen_art_prompts.py`"
                  % os.path.relpath(PLAN, ROOT))
            return 1
        on_disk = io.open(PLAN, encoding="utf-8", newline="").read().replace("\r\n", "\n")
        if on_disk != text:
            print("FAIL: %s je zvetraly; spust `python tools/gen_art_prompts.py`"
                  % os.path.relpath(PLAN, ROOT))
            return 1
        print("OK: plan sedi se STYLE_BIBLE.md i s data/, generator je deterministicky")
        return 0

    if args.stdout:
        out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", newline="\n")
        out.write(text)
        out.flush()
        return 0

    io.open(PLAN, "w", encoding="utf-8", newline="\n").write(text)
    print("zapsano %s" % os.path.relpath(PLAN, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
