#!/usr/bin/env python3
"""Stáhne živé JSON schéma vybraných PixelLab nástrojů a zapíše je do
tools/pixellab_schema.json, commitnuté a čtené offline `tools/gen_art_prompts.py`
i `scripts/_test_art_prompts.gd`.

    python tools/fetch_pixellab_schema.py           # přepíše tools/pixellab_schema.json
    python tools/fetch_pixellab_schema.py --check   # 0 = na disku sedí, 1 = zvětralo

PROC TENHLE SOUBOR EXISTUJE (A0b)

`tools/gen_art_prompts.py` psal parametry proti schématu `create_image_pixflux`
(nástroje, kterým se opravdu generoval `wall_material`), ale posílá je na
`create_character` a `create_1_direction_object` — jiné, menší schéma. Server
každé volání odmítl (3-4 validation errors), na první pokus fáze 0
(docs/refactor -- A0, PROGRESS.md).

Generátor promptů sám na síť sahat NESMÍ: musí dávat bit-identický výstup při
dvou spuštěních (vlastní docstring), běží pod `--check` ve verify.sh, a
`mcp__pixellab__*` je navíc v `settings` na deny — autonomní agent nemá se
skutečným API vůbec mluvit. Tenhle soubor je proto JEDINÉ místo, které se ptá
živého serveru, a dělá to jen když ho někdo spustí ručně. `tools/pixellab.py`
(přímý HTTP JSON-RPC klient, protože se MCP kvůli velikosti písmen v cestě
nenačítá) k tomu stačí beze změny — dotaz na `tools/list` nic negeneruje.

KDYŽ PIXELLAB PŘIDÁ NOVÝ NÁSTROJ, KTERÝ BIBLE ZAČNE POUŽÍVAT: přidej jeho
jméno do TOOLS níž a spusť tenhle skript znovu. `tools/gen_art_prompts.py`
sám hlásí SystemExit, když narazí na nástroj, který v tomhle souboru chybí —
tichý drift stejného druhu, co tenhle soubor sám opravuje, se tak nemůže
zopakovat.
"""
import argparse
import json
import os
import sys

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(PROJ, "tools", "pixellab_schema.json")

sys.path.insert(0, os.path.join(PROJ, "tools"))
import pixellab  # noqa: E402

# Každý MCP nástroj, který se dnes NEBO by se v dohledné době mohla bible naučit
# používat (gen:tools table + `tier == "tileset"` větev v gen_art_prompts.py,
# dnes nedosažitelná, protože terén je od 2026-08-29 vyříznutý celý, ale kód
# tu větev pořád má). `reduce_colors` je nástroj, kterým se paleta vynucuje AŽ
# po generování (color_image_url na žádném z generujících nástrojů neexistuje).
TOOLS = [
    "create_character",
    "create_1_direction_object",
    "create_tiles_pro",
    "reduce_colors",
]


def fetch():
    c = pixellab._shared()
    c.ready()
    resp = c.rpc("tools/list")
    by_name = {t["name"]: t for t in resp.get("result", {}).get("tools", [])}
    out = {}
    for name in TOOLS:
        if name not in by_name:
            raise SystemExit("server nezná nástroj %r (přejmenovaný/odebraný?)" % name)
        schema = by_name[name].get("inputSchema") or {}
        props = schema.get("properties") or {}
        out[name] = {
            "required": sorted(schema.get("required") or []),
            "properties": sorted(props.keys()),
        }
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args(argv)

    live = fetch()
    text = json.dumps(live, indent=2, sort_keys=True, ensure_ascii=False) + "\n"

    if args.check:
        on_disk = open(OUT, encoding="utf-8").read() if os.path.isfile(OUT) else None
        if on_disk == text:
            print("OK: tools/pixellab_schema.json sedí se živým API")
            return 0
        print("FAIL: tools/pixellab_schema.json zvětralo; spusť "
              "`python tools/fetch_pixellab_schema.py`")
        return 1

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("zapsáno %s (%d nástrojů)" % (os.path.relpath(OUT, PROJ), len(live)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
