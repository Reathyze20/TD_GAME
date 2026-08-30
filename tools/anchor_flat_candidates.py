#!/usr/bin/env python3
"""Jednorázová sonda: má plošší styl šanci fungovat jako nová kotva projektu?

    python tools/anchor_flat_candidates.py balance   # zůstatek, nic neutrácí
    python tools/anchor_flat_candidates.py dry        # co by se poslalo, nic neutrácí
    python tools/anchor_flat_candidates.py queue      # ZAFRONTUJE (platí se)
    python tools/anchor_flat_candidates.py status     # dopolluje, stáhne hotové kandidáty

PROC TENHLE SOUBOR EXISTUJE

Současná kotva (`fa8294b1-…`, Broccoli Knight) je výrazně detailnější než
`prop_focus_core`/`focus_timer` (fáze 0) a na jednom boardu podle uživatele
nesedí. Tohle je zkouška plošší alternativy -- STEJNÁ postava (broccoli
knight), jiný důraz v promptu (flat shading, minimal dithering, limited
detail). NENÍ součástí bible/plánu: pokud se ukáže, že to sedí, teprve pak se
`gen:anchors` v STYLE_BIBLE.md přepne na nové id a tenhle soubor dosloužil.
Proto se sem ukládá popis natvrdo, ne přes `docs/art/GENERATION_PLAN.md`.

Žádný `style_character_id` se neposílá schválně: cílem je kandidát na NOVOU
kotvu, ne variace staré -- kdyby volání ukazovalo na starou kotvu, žádalo by
model napodobit detailní styl a zároveň "plochý", protichůdně.

Parametry se validují proti ŽIVÉMU schématu stejně jako v `gen_art_prompts.py`
(`adapt_to_schema`) -- žádná druhá, nezávislá kopie stejné logiky.
"""
import argparse
import json
import os
import re
import sys

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_DIR = os.path.join(PROJ, "assets", "raw", "anchor_flat")
STATE = os.path.join(PROJ, "build", "anchor_flat_job.json")

sys.path.insert(0, os.path.join(PROJ, "tools"))
import pixellab  # noqa: E402
import gen_art_prompts as gap  # noqa: E402

# Stejný tvor jako `broccoli_knight` (STYLE_BIBLE.md, defender), jen s důrazem
# na jednoduchost místo detailu -- to je přesně ta jedna proměnná, která se testuje.
FORM = ("a broccoli knight in riveted armour, florets first, a wall that soaks "
        "hits and pins whole clumps in place")
STYLE_PUSH = ("flat shading, minimal dithering, clean readable shapes, limited "
              "detail, bold silhouette, no texture noise")

# Stejné pevné parametry jako u `defender` v gen:tools (view/outline) -- testuje se
# detail promptu, ne rámování, které je pro celý projekt jednotné.
FIXED = {"view": "low top-down", "outline": "single color black outline"}


def build_params():
    bible = gap.load_bible()
    schema = gap.load_schema()
    description = "%s; %s; %s" % (FORM, STYLE_PUSH, bible["suffix"])
    params = dict(FIXED)
    params.update({
        "description": description,
        "name": "anchor_flat_probe",
        "mode": "pro",
        "size": 64,
        # ZÁMĚRNĚ žádné style_character_id -- viz hlavička souboru.
    })
    payload, dropped = gap.adapt_to_schema("mcp__pixellab__create_character", params, schema)
    return payload, dropped, description


def cmd_balance(_args):
    print(pixellab.text_of(pixellab.call("get_balance")))


def cmd_dry(_args):
    payload, dropped, _desc = build_params()
    if dropped:
        print("VYHOZENO (schema je nezna): %s" % ", ".join(dropped))
    print(json.dumps(payload, indent=2, ensure_ascii=False))


def cmd_queue(args):
    if not args.yes:
        raise SystemExit("chybí --yes (tohle utrácí generace)")
    payload, _dropped, _desc = build_params()
    resp = pixellab.call("create_character", payload)
    text = pixellab.text_of(resp)
    m = re.search(r"([0-9a-f]{8}-[0-9a-f-]{27,})", text)
    job = {"id": m.group(1) if m else None, "raw": text[:400]}
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w", encoding="utf-8") as f:
        json.dump(job, f, indent=2, ensure_ascii=False)
    print("zafrontovano anchor_flat_probe -> %s" % (job["id"] or "SELHALO: " + text[:200]))


def cmd_status(_args):
    import subprocess
    if not os.path.isfile(STATE):
        raise SystemExit("neni %s -- nejdriv `queue`" % os.path.relpath(STATE, PROJ))
    job = json.load(open(STATE, encoding="utf-8"))
    if not job.get("id"):
        raise SystemExit("job nikdy nevznikl: %s" % job.get("raw"))
    text = pixellab.text_of(pixellab.call("get_character", {"character_id": job["id"]}))
    print(text[:200])
    urls = re.findall(r"https://\S+\.png", text)
    if not urls:
        print("jeste neni hotovo (nebo zadne URL v odpovedi)")
        return
    os.makedirs(RAW_DIR, exist_ok=True)
    got = 0
    for i, u in enumerate(sorted(set(urls))):
        out = os.path.join(RAW_DIR, "cand_%02d.png" % i)
        r = subprocess.run(["curl", "-sS", "-A", pixellab.UA, "-o", out, u],
                           capture_output=True)
        if r.returncode == 0 and os.path.getsize(out) > 0:
            got += 1
    print("stazeno %d kandidatu -> %s" % (got, os.path.relpath(RAW_DIR, PROJ)))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("balance").set_defaults(fn=cmd_balance)
    sub.add_parser("dry").set_defaults(fn=cmd_dry)
    p = sub.add_parser("queue")
    p.add_argument("--yes", action="store_true")
    p.set_defaults(fn=cmd_queue)
    sub.add_parser("status").set_defaults(fn=cmd_status)
    a = ap.parse_args(argv)
    a.fn(a)


if __name__ == "__main__":
    main()
