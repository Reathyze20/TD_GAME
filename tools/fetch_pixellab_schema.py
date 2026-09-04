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

CO SE ZE SCHÉMATU BERE A PROČ ZROVNA TOHLE

Do 2026-09-04 se zamrazovala jen jména polí (`properties`) a povinnost
(`required`). To stačí na otázku „projde tenhle parametr filtrem?", ale ne na
otázku „smí se poslat SPOLU s tamtím?" ani „je tahle hodnota vůbec platná?".
Obě odpovědi v živém schématu JSOU, jen ne ve strojovém tvaru: sedí v prose
`description` jednotlivých polí. Vytahují se proto tady, mechanicky, a ukládají
vedle jmen:

  enums      — `enum` daného pole. Bez nich by `body_type="amorphous"` prošel
               generátorem a spadl až na serveru, za peníze.
  defaults   — `default` daného pole. Parametr, který se NEPOŠLE, není „prázdný":
               server za něj dosadí tohle. `create_character` má
               `body_type` default `humanoid`, takže mlčení == „bipedál".
  conflicts  — dvojice polí, která se navzájem vylučují. Odvozuje se z vět typu
               „Cannot be set together with X" / „Cannot be combined with X" tak,
               že se ve větě hledají JMÉNA JINÝCH POLÍ TÉHOŽ nástroje. Věty jsou
               psané symetricky (`num_colors` × `palette_image_base64` se zmiňují
               navzájem), takže se dvojice chytí, i když ji jedna strana pojmenuje
               jen prózou („a palette image").

Žádná z těch tří věcí se tedy nikde v repu neopisuje jako konstanta — přepíšou se
při každém `fetch`, stejně jako jména polí (CLAUDE.md, „Konstantu neopisuj").
"""
import argparse
import json
import os
import re
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


# Věta, kterou PixelLab popisuje vzájemné vyloučení dvou polí. Obě formulace jsou
# v dnešním schématu doložené: `create_1_direction_object.size` říká "Cannot be set
# together with style_images", `create_tiles_pro.tile_feature` a
# `reduce_colors.palette_image_base64` říkají "Cannot be combined with ...".
_CONFLICT_RE = re.compile(
    r"[Cc]annot be (?:set together with|combined with)\b([^.]*)", re.S)


def _conflicts(props):
    """Dvojice vzájemně se vylučujících polí, vyčtené z prose `description`.

    Hledá se JMÉNO JINÉHO POLE TÉHOŽ nástroje jako celé slovo uvnitř té věty --
    proto se dvojice nedá vymyslet, jen najít. Když věta pojmenuje protějšek jen
    prózou ("a palette image"), z týhle strany nevznikne nic; chytí se z druhé,
    protože jsou psané symetricky. Vrací setříděný seznam setříděných dvojic, aby
    byl výstup deterministický."""
    names = set(props)
    pairs = set()
    for name, spec in props.items():
        text = (spec or {}).get("description") or ""
        for m in _CONFLICT_RE.finditer(text):
            for other in names:
                if other == name:
                    continue
                if re.search(r"\b%s\b" % re.escape(other), m.group(1)):
                    pairs.add(tuple(sorted((name, other))))
    return [list(p) for p in sorted(pairs)]


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
            "enums": {k: v["enum"] for k, v in sorted(props.items())
                      if isinstance(v, dict) and v.get("enum")},
            "defaults": {k: v["default"] for k, v in sorted(props.items())
                         if isinstance(v, dict) and v.get("default") is not None},
            "conflicts": _conflicts(props),
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
