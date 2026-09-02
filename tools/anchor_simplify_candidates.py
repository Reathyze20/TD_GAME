#!/usr/bin/env python3
"""Jednorázová sonda: obstojí broccoli knight s ořezanou siluetou jako NOVÁ kotva?

    python tools/anchor_simplify_candidates.py balance   # zůstatek, nic neutrácí
    python tools/anchor_simplify_candidates.py dry        # co by se poslalo, nic neutrácí
    python tools/anchor_simplify_candidates.py queue --yes  # ZAFRONTUJE (platí se)
    python tools/anchor_simplify_candidates.py status     # dopolluje, stáhne hotové kandidáty
    python tools/anchor_simplify_candidates.py sheet       # kontaktní list cand_03 vs. kandidáti

PROC TENHLE SOUBOR EXISTUJE

`§6a` (`tools/anchor_flat_candidates.py`) zkusila plošší styl bez kotvy a zjistila,
že bez `style_character_id` se ztrácí IDENTITA tvora (žádná zelená, žádný
zeleninový motiv) -- ta sonda tedy netestovala "plošší brokolicový rytíř",
testovala "plošší obecná postava". Tahle sonda jde jinou osou: NECHÁVÁ
dithering/stínování/texturu (přesně to, co §6a odstranila), a mění jen počet
prvků, které lámou siluetu -- méně nýtů/přezek/drobného lemu, tři silné tvary
místo mnoha malých. Bez `style_character_id` ze stejného důvodu jako §6a:
tohle je kandidát na NOVOU kotvu, ne variace staré.

PROC SE NEPOUŽÍVÁ `bible["suffix"]` / `bible["design_constraints"]` DOSLOVA

Mechanický pipeline (`gen_art_prompts.py`) lepí STYLE_BIBLE.md §7 (suffix) a
§7b (design constraints) za KAŽDÝ prompt, včetně postav. U bohatě zbrojené
postavy to vyrábí spor: §7b's "detail" řádek říká "no dithering" a §7 to říká
DRUHÝ KRÁT ("no dithering, no anti-aliasing, no gradient banding") -- a §7
zároveň říká "organic neural tissue, ... no mechanical parts, no panels or
screws", zatímco forma rytíře žádá "riveted armour" (nýtovaná zbroj). Zbroj
se tu poptává a ve stejné větě zakazuje jako "mechanická". Na 64px bohatě
zdobené postavě to zplošťuje kresbu a zabíjí objem/čitelnost.

Tahle sonda proto NEpoužívá §7 ani §7b's "detail" řádek doslovně -- schválně,
protože to je přesně ten spor, který se tu testuje pryč. Drží se zbytek §7b
(oči/obličej, končetiny, tón, postoj, perspektiva) a standardní rámování/zákaz
textu, protože ty si nekonfliktují s ničím výše.

NENÍ součástí bible/plánu -- stejná poznámka jako u `anchor_flat_candidates.py`:
pokud se ukáže, že tohle sedí, teprve pak se `gen:anchors` v STYLE_BIBLE.md
přepne na nové id a tenhle soubor dosloužil.

Parametry se validují proti ŽIVÉMU schématu stejně jako v `gen_art_prompts.py`
(`adapt_to_schema`) -- žádná druhá, nezávislá kopie stejné logiky. Schéma
(`tools/pixellab_schema.json`) NEMÁ `negative_description` ani
`color_image_url` na `create_character` (ověřeno A0b, `adapt_to_schema`'s
docstring) -- `negative_description` se sem přesto dává, aby `dry` ukázal
ZÁMĚR před osekem, ale `adapt_to_schema` ho tiše zahodí, stejně jako to dělá
`gen_art_prompts.py`'s `build()` pro celý zbytek rejstříku.
"""
import argparse
import json
import os
import re
import sys

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_DIR = os.path.join(PROJ, "assets", "raw", "anchor_simplify")
STATE = os.path.join(PROJ, "build", "anchor_simplify_job.json")
SHEET_OUT = os.path.join(PROJ, ".dev", "screenshots", "anchor_simplify_candidates.png")
CAND_03 = os.path.join(PROJ, "assets", "raw", "broccoli_knight", "cand_03.png")

sys.path.insert(0, os.path.join(PROJ, "tools"))
import pixellab  # noqa: E402
import gen_art_prompts as gap  # noqa: E402

# Popis. Napsáno kladně, s bany jen pro kameru/rámování -- viz hlavička souboru
# a docs/art/STYLE_BIBLE.md §6b pro plné odůvodnění každé věty.
DESCRIPTION = (
    "a broccoli knight defender, florets first, a wall that soaks hits and pins "
    "whole clumps in place; large continuous armour plates cover the body, with "
    "no rivets, straps, buckles, or small trim anywhere; the silhouette is "
    "broken by exactly three strong shapes and nothing else: a rounded "
    "floret-crowned head, a single held weapon, and a broad shield; standing "
    "on two legs, holding its weapon and shield in visible arms; no eyes and "
    "no face anywhere on the head; reads warm, calm and inviting, like the "
    "other habits and defenders; stands planted and grounded, anchored to the "
    "ground, not floating or hovering; gritty pixel dithering and three "
    "shading tones give the armour weight and volume, the shadow tone "
    "hue-shifted at least 20 degrees toward cool; visible material texture "
    "across the armour and floret surfaces; 1px outline in a darker shade of "
    "the same hue, never black; colours taken only from the supplied "
    "reference palette image; camera is a low top-down view straight at the "
    "subject, front-facing, zero isometric tilt, no camera pitch; centered, "
    "full object visible, margin on all sides; no text, no numbers, no UI, "
    "no logo, no frame, no baked drop shadow"
)

# Stejné pevné parametry jako u `defender` v gen:tools (view/outline) -- testuje se
# obsah promptu, ne rámování, které je pro celý projekt jednotné.
FIXED = {"view": "low top-down", "outline": "single color black outline"}


def build_params():
    bible = gap.load_bible()
    schema = gap.load_schema()
    params = dict(FIXED)
    params.update({
        "description": DESCRIPTION,
        "name": "anchor_simplify_probe",
        "mode": "pro",
        "size": 64,
        # negative_description zustava v params az do filtru nize -- schema ho
        # na create_character nema (A0b), takze `adapt_to_schema` ho vyhodi;
        # necha se tu, aby `dry` ukazal zamer pred osekem (stejny vzor jako
        # gen_art_prompts.py's build()).
        "negative_description": bible["negative"],
        # ZAMERNE zadne style_character_id -- viz hlavicka souboru.
    })
    payload, dropped = gap.adapt_to_schema("mcp__pixellab__create_character", params, schema)
    return payload, dropped


def cmd_balance(_args):
    print(pixellab.text_of(pixellab.call("get_balance")))


def cmd_dry(_args):
    payload, dropped = build_params()
    if dropped:
        print("VYHOZENO (schema je nezna): %s" % ", ".join(dropped))
    print(json.dumps(payload, indent=2, ensure_ascii=False))


def cmd_queue(args):
    if not args.yes:
        raise SystemExit("chybí --yes (tohle utrácí generace)")
    payload, _dropped = build_params()
    resp = pixellab.call("create_character", payload)
    text = pixellab.text_of(resp)
    m = re.search(r"([0-9a-f]{8}-[0-9a-f-]{27,})", text)
    job = {"id": m.group(1) if m else None, "raw": text[:400]}
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w", encoding="utf-8") as f:
        json.dump(job, f, indent=2, ensure_ascii=False)
    print("zafrontovano anchor_simplify_probe -> %s" % (job["id"] or "SELHALO: " + text[:200]))


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


def _silhouette(im, color=(90, 200, 190)):
    """Alpha-threshold na jednu plochou barvu -- pro srovnani slozitosti obrysu."""
    from PIL import Image
    a = im.split()[-1] if im.mode == "RGBA" else Image.new("L", im.size, 255)
    mask = a.point(lambda p: 255 if p > 24 else 0)
    flat = Image.new("RGBA", im.size, (0, 0, 0, 0))
    solid = Image.new("RGBA", im.size, color + (255,))
    flat.paste(solid, (0, 0), mask)
    return flat


def cmd_sheet(_args):
    from PIL import Image, ImageDraw

    if not os.path.isfile(CAND_03):
        raise SystemExit("chybí %s -- broccoli_knight/cand_03.png musí zůstat na disku"
                          % os.path.relpath(CAND_03, PROJ))
    if not os.path.isdir(RAW_DIR):
        raise SystemExit("neni %s -- nejdriv `status` (stahuje kandidaty)"
                          % os.path.relpath(RAW_DIR, PROJ))

    names = ["cand_03 (ziva kotva)"] + sorted(
        f for f in os.listdir(RAW_DIR) if f.lower().endswith(".png"))
    paths = [CAND_03] + [os.path.join(RAW_DIR, n) for n in names[1:]]
    if len(paths) < 2:
        raise SystemExit("v %s zatim nejsou zadni kandidati" % os.path.relpath(RAW_DIR, PROJ))

    imgs = [Image.open(p).convert("RGBA") for p in paths]
    Z = 4
    cell = max(i.width for i in imgs) * Z
    pad = 10
    label_h = 20
    row_h = cell + label_h + pad
    sheet_w = pad + len(imgs) * (cell + pad)
    sheet_h = pad + 2 * row_h + pad  # barevny radek + silueta

    sheet = Image.new("RGB", (sheet_w, sheet_h), (24, 22, 30))
    dr = ImageDraw.Draw(sheet)
    dr.text((pad, 2), "anchor_simplify probe -- barva (radek 1) a silueta (radek 2), "
             "cand_03 = ziva kotva pro srovnani", fill=(200, 195, 210))

    for i, (name, im) in enumerate(zip(names, imgs)):
        x = pad + i * (cell + pad)
        y0 = pad + 16
        r = im.resize((cell, cell), Image.NEAREST)
        # sachovnice pod pruhlednosti, at je videt okraj siluety
        bg = Image.new("RGB", (cell, cell), (40, 38, 46))
        bg.paste(r, (0, 0), r)
        sheet.paste(bg, (x, y0))
        dr.text((x, y0 + cell + 2), name[:24], fill=(210, 205, 220))

        sil = _silhouette(im).resize((cell, cell), Image.NEAREST)
        y1 = y0 + row_h
        bg2 = Image.new("RGB", (cell, cell), (18, 17, 22))
        bg2.paste(sil, (0, 0), sil)
        sheet.paste(bg2, (x, y1))

    os.makedirs(os.path.dirname(SHEET_OUT), exist_ok=True)
    sheet.save(SHEET_OUT)
    print("kontaktni list -> %s" % os.path.relpath(SHEET_OUT, PROJ))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("balance").set_defaults(fn=cmd_balance)
    sub.add_parser("dry").set_defaults(fn=cmd_dry)
    p = sub.add_parser("queue")
    p.add_argument("--yes", action="store_true")
    p.set_defaults(fn=cmd_queue)
    sub.add_parser("status").set_defaults(fn=cmd_status)
    sub.add_parser("sheet").set_defaults(fn=cmd_sheet)
    a = ap.parse_args(argv)
    a.fn(a)


if __name__ == "__main__":
    main()
