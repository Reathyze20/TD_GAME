#!/usr/bin/env python3
"""Spustí dávku fáze 0 podle docs/art/GENERATION_PLAN.md.

    python tools/phase0_batch.py balance          # zůstatek, nic neutrácí
    python tools/phase0_batch.py dry              # co by se poslalo, nic neutrácí
    python tools/phase0_batch.py queue            # ZAFRONTUJE všechny tři naráz (platí se)
    python tools/phase0_batch.py status           # dopolluje rozdělané joby
    python tools/phase0_batch.py pull             # stáhne hotové do assets/raw/

PROC TENHLE SOUBOR EXISTUJE

`tools/pixellab.py new` plán vygenerovat NEUMÍ a je to tichá vada, ne kosmetika:
posílá `mode:"v3"` natvrdo, neposílá `style_character_id`, `color_image_url`,
`negative_description` ani `size`, a zná jen `create_character`. Kotvu bere
VÝHRADNĚ `mode:"pro"`, takže přes `new` by vznikly sprity bez kotvy, bez palety
a v defaultní velikosti — tedy mimo rodinu, za peníze.

Parametry se proto NEOPISUJÍ. Čtou se z `GENERATION_PLAN.md`, kde je pro každou
z 37 entit kompletní JSON blok, který vygeneroval `tools/gen_art_prompts.py` ze
style bible. Když se má něco změnit, mění se bible a přegeneruje plán; tenhle
soubor se nemění. Totéž pravidlo, na kterém stojí sám generátor promptů.
"""
import argparse
import json
import os
import re
import sys

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAN = os.path.join(PROJ, "docs", "art", "GENERATION_PLAN.md")
RAW = os.path.join(PROJ, "assets", "raw")

sys.path.insert(0, os.path.join(PROJ, "tools"))
import pixellab  # noqa: E402

# Fáze 0 přesně jak ji vyjmenovává plán. Držené jako seznam id, ne jako "prvních N
# sekcí" — pořadí v plánu se může přegenerováním změnit, členství ve fázi ne.
PHASE0 = ["prop_focus_core", "focus_timer", "broccoli_knight"]

# Kde si držíme id vrácená frontou, aby `status`/`pull` běžely v jiném procesu.
STATE = os.path.join(PROJ, "build", "phase0_jobs.json")


def _sections(text):
    """{id: {'tool':…, 'params':{…}, 'cena':int}} ze všech '### n. `id` — …' bloků."""
    out = {}
    parts = re.split(r"^### \d+\. `([^`]+)`", text, flags=re.M)
    # parts = [pre, id1, body1, id2, body2, …]
    for i in range(1, len(parts) - 1, 2):
        eid, body = parts[i], parts[i + 1]
        m_tool = re.search(r"\|\s*nástroj\s*\|\s*`mcp__pixellab__(\w+)`\s*\|", body)
        m_json = re.search(r"\*\*Parametry\*\*\s*\n+```json\n(.*?)\n```", body, re.S)
        m_cena = re.search(r"\|\s*cena\s*\|\s*(\d+)\s*generac", body)
        if not (m_tool and m_json):
            continue
        out[eid] = {
            "tool": m_tool.group(1),
            "params": json.loads(m_json.group(1)),
            "cena": int(m_cena.group(1)) if m_cena else 0,
        }
    return out


def plan():
    with open(PLAN, encoding="utf-8") as f:
        secs = _sections(f.read())
    missing = [e for e in PHASE0 if e not in secs]
    if missing:
        raise SystemExit("v plánu chybí sekce pro: %s" % ", ".join(missing))
    return [(e, secs[e]) for e in PHASE0]


_SCHEMA_CACHE = {}


def _schema(tool):
    """Živé schéma nástroje ze serveru. Cachované v procesu."""
    if not _SCHEMA_CACHE:
        c = pixellab._shared()
        c.ready()
        for t in c.rpc("tools/list").get("result", {}).get("tools", []):
            _SCHEMA_CACHE[t.get("name")] = t.get("inputSchema") or {}
    if tool not in _SCHEMA_CACHE:
        raise SystemExit("server nezná nástroj %s" % tool)
    return _SCHEMA_CACHE[tool]


def adapt(tool, params):
    """Přizpůsobí parametry z plánu ŽIVÉMU schématu. Vrací (payload, vyhozené).

    Plán vznikl proti schématu `create_image_pixflux` (ten se opravdu použil na
    wall_material), jenže `create_character` a `create_1_direction_object` mají jiné,
    menší schéma: `color_image_url`, `seed` ani `negative_description` na nich
    neexistují a server celé volání odmítne. Filtruje se proto proti tomu, co server
    o sobě SÁM tvrdí — ne proti pevnému seznamu, který by zase zvětral.

    Dvě náhrady, obě vynucené API, ne volba:
    * paleta: `color_image_url` neexistuje → vynutí se až po generování přes
      `reduce_colors(palette_image_url=palette_48.png)`, což je i to, co říká
      CLAUDE.md ("každý asset jde přes reduce_colors s palette_48").
    * negativy: `negative_description` neexistuje → povinný suffix promptu je ale
      už dnes obsahuje slovně ("no dithering, no anti-aliasing, no text, no numbers,
      no UI, no logo, no frame, no baked drop shadow"), takže se neztrácí obsah,
      jen samostatné pole.
    `seed` náhradu nemá — postavy a objekty prostě nejsou seedovatelné.
    """
    schema = _schema(tool)
    allowed = set((schema.get("properties") or {}).keys())
    required = set(schema.get("required") or [])

    p = {k: v for k, v in params.items() if k in allowed}
    dropped = sorted(set(params) - allowed)

    # `create_1_direction_object` má POVINNÉ `description` (jednotné), zatímco plán
    # nese text v `item_descriptions`. Jeden objekt = jeden popis, takže se přenese.
    if "description" in required and "description" not in p:
        items = params.get("item_descriptions") or []
        if items:
            p["description"] = items[0]
    return p, dropped


def _resolve_paths(params):
    """Ponecháno kvůli `dry`: ověří, že cesta na paletu v plánu existuje."""
    ci = params.get("color_image_url")
    if ci and not ci.startswith("http"):
        full = os.path.join(PROJ, ci.replace("/", os.sep))
        if not os.path.isfile(full):
            raise SystemExit("color_image_url neukazuje na existující soubor: %s" % ci)
    return params


def cmd_balance(_args):
    resp = pixellab.call("get_balance")
    print(pixellab.text_of(resp))


def cmd_schema(args):
    """Skutečné schéma nástrojů ze serveru (tools/list). Čte, neutrácí.

    Existuje proto, že plán byl psaný proti katalogu z dokumentace, ne proti živému
    API — a rozešly se. Tohle je jediný zdroj pravdy o tom, co server přijme."""
    c = pixellab._shared()
    c.ready()
    resp = c.rpc("tools/list")
    tools = resp.get("result", {}).get("tools", [])
    want = set(args.only.split(",")) if args.only else None
    for t in tools:
        if want and t.get("name") not in want:
            continue
        print("=== %s" % t.get("name"))
        schema = t.get("inputSchema") or {}
        props = schema.get("properties") or {}
        req = set(schema.get("required") or [])
        for k in sorted(props):
            typ = props[k].get("type") or props[k].get("anyOf") or "?"
            print("   %-26s %-28s %s" % (
                k + (" *" if k in req else ""), str(typ)[:28],
                str(props[k].get("description", ""))[:70]))
        print()


def cmd_dry(_args):
    total = 0
    for eid, spec in plan():
        total += spec["cena"]
        _resolve_paths(spec["params"])
        payload, dropped = adapt(spec["tool"], spec["params"])
        print("=== %s  ->  %s   (%d generaci)" % (eid, spec["tool"], spec["cena"]))
        if dropped:
            print("    VYHOZENO (schema je nezna): %s" % ", ".join(dropped))
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        print()
    print("celkem faze 0: %d generaci" % total)


def cmd_queue(args):
    if not args.yes:
        raise SystemExit("chybí --yes (tohle utrácí generace)")
    jobs = {}
    spent = 0
    # Zafrontovat VŠECHNO naráz a teprve pak pollovat — sériové čekání na každý job
    # zvlášť je to, co plán §4 výslovně zakazuje. Fronta se drží pod deseti (tři).
    for eid, spec in plan():
        payload, dropped = adapt(spec["tool"], spec["params"])
        resp = pixellab.call(spec["tool"], payload)
        text = pixellab.text_of(resp)
        m = re.search(r"([0-9a-f]{8}-[0-9a-f-]{27,})", text)
        jid = m.group(1) if m else None
        # Cena se počítá JEN když job vážně vznikl. Dřív se sčítal plán bez ohledu na
        # výsledek, takže odmítnutá dávka hlásila "utraceno 80" při skutečných nule —
        # tichá lež přesně tam, kde na číslech záleží nejvíc.
        if jid:
            spent += spec["cena"]
        jobs[eid] = {"tool": spec["tool"], "id": jid, "cena": spec["cena"] if jid else 0,
                     "dropped": dropped, "raw": text[:400]}
        print("zafrontovano %-18s %s" % (eid, jid or "SELHALO: " + text[:200]))
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w", encoding="utf-8") as f:
        json.dump(jobs, f, indent=2, ensure_ascii=False)
    ok = sum(1 for j in jobs.values() if j["id"])
    print("\nstav v %s; vzniklo %d/%d jobu, utraceno %d generaci" % (
        os.path.relpath(STATE, PROJ), ok, len(jobs), spent))


def _load_jobs():
    if not os.path.isfile(STATE):
        raise SystemExit("není %s — nejdřív `queue`" % os.path.relpath(STATE, PROJ))
    with open(STATE, encoding="utf-8") as f:
        return json.load(f)


# Id se mezi voláním a vyzvednutím přejmenovává (plán §6): objekt se vyzvedává
# get_object(object_id), postava get_character(character_id).
GETTER = {
    "create_character": ("get_character", "character_id"),
    "create_1_direction_object": ("get_object", "object_id"),
}


def cmd_status(_args):
    for eid, j in _load_jobs().items():
        if not j.get("id"):
            print("%-18s BEZ ID — viz raw v %s" % (eid, os.path.relpath(STATE, PROJ)))
            continue
        getter, key = GETTER[j["tool"]]
        text = pixellab.text_of(pixellab.call(getter, {key: j["id"]}))
        state = "creating" if "creating" in text else "hotovo?"
        print("%-18s %-10s %s" % (eid, state, j["id"]))
        print("    " + text[:300].replace("\n", "\n    "))


def cmd_pull(_args):
    """Stáhne VŠECHNY vrácené snímky do assets/raw/<entita>/ a projede reduce_colors.

    Objekty se vracejí jako `review (N candidates)` — výběr jednoho z nich je vizuální
    rozhodnutí, takže se tu NEDĚLÁ: stáhne se všechno a vybere člověk.
    Backblaze odmítá výchozí UA Pythonu (403), proto curl s běžným UA — viz hlavička
    pixellab.py. Paleta se vynucuje až tady, protože `color_image_url` na generujících
    nástrojích neexistuje (viz adapt()).
    """
    import base64
    import subprocess
    pal = os.path.join(PROJ, "docs", "art", "palette_48.png")
    with open(pal, "rb") as f:
        pal_b64 = base64.b64encode(f.read()).decode()

    for eid, j in _load_jobs().items():
        if not j.get("id"):
            print("%-18s preskakuji (nevznikl)" % eid)
            continue
        getter, key = GETTER[j["tool"]]
        text = pixellab.text_of(pixellab.call(getter, {key: j["id"]}))
        urls = re.findall(r"https://\S+\.png", text)
        if not urls:
            print("%-18s zadne URL (stav: %s)" % (eid, text[:80].replace("\n", " ")))
            continue
        dst = os.path.join(RAW, eid)
        os.makedirs(dst, exist_ok=True)
        got = []
        for i, u in enumerate(sorted(set(urls))):
            out = os.path.join(dst, "cand_%02d.png" % i)
            r = subprocess.run(["curl", "-sS", "-A", pixellab.UA, "-o", out, u],
                               capture_output=True)
            if r.returncode == 0 and os.path.getsize(out) > 0:
                got.append(out)
        print("%-18s stazeno %d snimku -> %s" % (
            eid, len(got), os.path.relpath(dst, PROJ)))

        # reduce_colors na palette_48 — CLAUDE.md: "vse jde pres reduce_colors".
        for src in got:
            with open(src, "rb") as f:
                img_b64 = base64.b64encode(f.read()).decode()
            resp = pixellab.call("reduce_colors", {
                "images_base64": [img_b64],
                "palette_image_base64": pal_b64,
                "dithering": "none"})
            rtext = pixellab.text_of(resp)
            rurls = re.findall(r"https://\S+\.png", rtext)
            if not rurls:
                print("    reduce_colors bez URL pro %s: %s" % (
                    os.path.basename(src), rtext[:120].replace("\n", " ")))
                continue
            red = src.replace(".png", "_pal48.png")
            subprocess.run(["curl", "-sS", "-A", pixellab.UA, "-o", red, rurls[0]],
                           capture_output=True)
        print("    paleta hotova")


def cmd_palette(args):
    """reduce_colors na palette_48 nad JEDNÍM reprezentativním snímkem každé entity.

    `reduce_colors` je ASYNCHRONNÍ — vrací job id, ne URL (plán §6: stav, na který se
    čeká, je `creating`, a vyzvedává se `get_image(job_id=…)`). První verze pull() to
    přehlédla a hlásila "bez URL" u každého snímku.
    Jede se jen nad jedním kandidátem na entitu, ne nad všemi: výběr kandidáta je
    vizuální rozhodnutí uživatele, a klampovat paletou všech 28 by platilo za snímky,
    které se zahodí.
    """
    import base64
    import subprocess
    import time
    pal = os.path.join(PROJ, "docs", "art", "palette_48.png")
    with open(pal, "rb") as f:
        pal_b64 = base64.b64encode(f.read()).decode()

    jobs = {}
    for eid in PHASE0:
        src = os.path.join(RAW, eid, "cand_%02d.png" % args.cand)
        if not os.path.isfile(src):
            print("%-18s neni %s" % (eid, os.path.relpath(src, PROJ)))
            continue
        with open(src, "rb") as f:
            img_b64 = base64.b64encode(f.read()).decode()
        text = pixellab.text_of(pixellab.call("reduce_colors", {
            "images_base64": [img_b64], "palette_image_base64": pal_b64,
            "dithering": "none"}))
        m = re.search(r"id:\s*([0-9a-f-]{30,})", text)
        jobs[eid] = (m.group(1) if m else None, src)
        print("%-18s reduce_colors -> %s" % (eid, jobs[eid][0] or text[:100]))

    for attempt in range(20):
        pending = [e for e, (jid, _) in jobs.items()
                   if jid and not os.path.isfile(jobs[e][1].replace(".png", "_pal48.png"))]
        if not pending:
            break
        time.sleep(6)
        for eid in pending:
            jid, src = jobs[eid]
            text = pixellab.text_of(pixellab.call("get_image", {"job_id": jid}))
            urls = re.findall(r"https://\S+\.png", text)
            if not urls:
                continue
            dst = src.replace(".png", "_pal48.png")
            subprocess.run(["curl", "-sS", "-A", pixellab.UA, "-o", dst, urls[0]],
                           capture_output=True)
            if os.path.isfile(dst) and os.path.getsize(dst) > 0:
                print("%-18s paleta -> %s" % (eid, os.path.relpath(dst, PROJ)))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("balance").set_defaults(fn=cmd_balance)
    p = sub.add_parser("schema")
    p.add_argument("--only", help="jen tyhle nástroje, oddělené čárkou")
    p.set_defaults(fn=cmd_schema)
    sub.add_parser("dry").set_defaults(fn=cmd_dry)
    p = sub.add_parser("queue")
    p.add_argument("--yes", action="store_true")
    p.set_defaults(fn=cmd_queue)
    sub.add_parser("status").set_defaults(fn=cmd_status)
    sub.add_parser("pull").set_defaults(fn=cmd_pull)
    p = sub.add_parser("palette")
    p.add_argument("--cand", type=int, default=0)
    p.set_defaults(fn=cmd_palette)
    a = ap.parse_args(argv)
    a.fn(a)


if __name__ == "__main__":
    main()
