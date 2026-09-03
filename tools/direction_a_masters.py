"""Vygeneruj DVA mastery smeru A: jednu distrakci a jeden habit.

    python tools/direction_a_masters.py balance      # zustatek PRED davkou (CLAUDE.md)
    python tools/direction_a_masters.py dry          # co by se poslalo, nic neutraci
    python tools/direction_a_masters.py queue --yes  # UTRACI ~40 generaci
    python tools/direction_a_masters.py status       # pollni a stahni kandidaty
    python tools/direction_a_masters.py sheet        # kontaktni list (barva + silueta)

PROC TENHLE NASTROJ EXISTUJE

STYLE_BIBLE.md §12f zadava presne dva sprity, ne osm a ne cely rejstrik: jeden master
distraction a jeden master habit. Az je uzivatel schvali, stanou se style referenci pro
fazi 1 a teprve tehdy se zapisuje radek do `gen:direction_a` a prepisuje `gen:anchors`.
Do te doby se negeneruje nic dalsiho.

Vzor je `tools/anchor_simplify_candidates.py` (§6b) -- stejne subprikazy, stejny stavovy
soubor, stejny curl na download URL. Rozdil je, ze tady jedou DVA joby dvema RUZNYMI
nastroji: distrakce je postava (`create_character`), habit je objekt
(`create_1_direction_object`), presne podle `gen:tools` v §9.

CO SE BERE Z BIBLE A CO JE TADY

Z bible se cte `design_constraints` (§7b) a `suffix` (§7) -- doslova, pres
`gen_art_prompts.load_bible()`, aby se tenhle soubor nemohl rozejit s tim, co jde do
zbytku rejstriku. Slepuje se stejne jako v `gen_art_prompts.build()`:
`forma; design_constraints; suffix`. Tady v souboru je JEN forma obou masteru -- to je
to jedine, co je pro ne specificke.

TRI VEDOME ODCHYLKY OD `gen:tools`, kazda s duvodem

1. **Zadne `style_character_id`.** Kotva `fa8294b1-...` je figuralni a smerem A opustena
   (§12c, ART_DEBT.md). Cilem je NOVA reference, ne varianta stare. §6a merila, ze bez
   kotvy se ztraci i barva a tema, ne jen hustota kresby -- u abstraktniho beztvareho
   shluku ale neni zadna "identita tvora", kterou by slo ztratit, takze to riziko je tu
   radove mensi nez u brokolicoveho rytire.
2. **`outline` se NEPOSILA.** §12b zaznamenava, ze si bible v tehle ose odporuje: §7
   (v promptu) rika "never black", §9 (`pevne_parametry`) posila
   `single color black outline`, research navrhuje treti hodnotu `selective outline`.
   Rozhodnout to ma uzivatel jednou pro vsechny tri, takze tenhle probe si stranu
   nevybira -- parametr vynechava a obrys nechava na slovnim popisu ze suffixu.
3. **Habit dostava `view="top-down"`, ne `"low top-down"`.** Neni to nedbalost:
   `create_1_direction_object` ma jiny enum a "low top-down" mu poslat NEJDE (§9, past).
   Perspektivu proto u nej nese vyhradne text promptu -- presne proto §7b existuje.
"""
import argparse
import io
import json
import os
import re
import subprocess
import sys

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE = os.path.join(PROJ, ".dev", "direction_a_masters.json")
SHEET = os.path.join(PROJ, ".dev", "screenshots", "direction_a_masters.png")

sys.path.insert(0, os.path.join(PROJ, "tools"))
import pixellab  # noqa: E402
import gen_art_prompts as gap  # noqa: E402

# Jen FORMA. Design constraints (§7b) a suffix (§7) se lepi z bible nize -- nepis je sem.
#
# Distrakce: §12's "amorfni jev". Zadny obliceji, zadne koncetiny, nepravidelny
# rozpadajici se okraj, TEPLA syta dopaminova zona (od 2. 9. 2026 prohozeno, §2 bod 0).
FORMS = {
    "master_distraction_a": {
        "kind": "distraction",
        "tool": "create_character",
        "form": (
            "an amorphous organic mass with no face and no limbs, wider than tall "
            "and top-heavy, its outline irregular and dissolving with no two edges "
            "alike, a single warm saturated magenta and orange body in flat colour "
            "fields with no inner detail, flowing low and in contact with the surface"
        ),
    },
    # Habit: §12's "geometrie". Jedina pravidelna vec na desce -- proto rovne plochy,
    # symetrie a ostre rezana hrana, a CHLADNA ticha zona.
    "master_habit_a": {
        "kind": "habit",
        "tool": "create_1_direction_object",
        "form": (
            "a geometric habit core on a square base, built from flat faces and "
            "clean arcs, symmetrical about its vertical axis, with hard cut edges "
            "and no organic curves anywhere, taller than wide, cool steel and teal "
            "in flat colour fields with one small bright accent node, sitting still "
            "and rooted to the ground"
        ),
    },
}


def raw_dir(name):
    return os.path.join(PROJ, "assets", "raw", name)


# Klauzule z §7b, ktere se do promptu MASTERU vedome nedavaji, a proc. Vzor prevzat
# z §6b, ktera tentyz krok udelala a zapsala ("Co se proto v promptu vedome NEpouzilo
# doslova") -- neni to obchazeni bible, je to zaznamenana odchylka jedne sondy.
#
# Duvod je merene chovani, ne vkus: `gen_art_prompts.build()` lepi CELY blok §7b za
# kazdy prompt, takze prompt na beztvarou distrakci nese i vetu "every habit is
# geometric, built from flat faces ... hard cut edges". Presne tenhle druh sporu
# (forma zada A, pripojeny blok zada zaroven ne-A) §6b namerila u `broccoli_knight`.
# U masteru, ktery ma teprve DEFINOVAT rodinu, je to nejdrazsi mozne misto, kde to
# nechat probublat -- proto se kazdemu masteru necha jen klauzule o jeho vlastni rodine.
DROP_FOR = {
    "master_distraction_a": ("every habit is geometric",),
    "master_habit_a": ("every distraction, including the boss,",),
}
# Vyjimka na koncetiny mluvi o ctyrech obrancich Nutrition Guild -- figuralni rodine,
# kterou smer A opousti (§12c) a ktera s zadnym z masteru nesouvisi. V promptu by
# jen nabizela "except ...", tedy duvod koncetiny nakreslit. Plati pro oba mastery.
DROP_ALWAYS = ("no arms and no legs anywhere, except",)


def _constraints_for(bible, name):
    """§7b doslova, minus klauzule o DRUHE rodine -- viz DROP_FOR."""
    drop = DROP_FOR.get(name, ()) + DROP_ALWAYS
    kept = [c.strip() for c in bible["design_constraints"].split(";")
            if not any(c.strip().startswith(d) for d in drop)]
    # Zakaz koncetin se vraci bez te "except" vetve, ne aby zmizel uplne.
    if any(d.startswith("no arms and no legs") for d in DROP_ALWAYS):
        kept.insert(1, "no arms and no legs anywhere")
    return "; ".join(kept)


def build_prompt(bible, name):
    """forma; design_constraints; suffix -- stejne poradi jako gen_art_prompts.build()."""
    return "%s; %s; %s" % (FORMS[name]["form"], _constraints_for(bible, name),
                           bible["suffix"])


def build_params(name):
    bible = gap.load_bible()
    schema = gap.load_schema()
    spec = FORMS[name]
    prompt = build_prompt(bible, name)
    if spec["tool"] == "create_character":
        params = {
            "description": prompt,
            "name": name,
            "mode": "pro",
            "size": 64,
            "view": "low top-down",
            # Hordova hra -> nejnizsi detail a nejmene barev (§12d's barevne brany).
            # V `pro` rezimu je model muze ignorovat; posilaji se proto, ze vyjadruji
            # zamer a nic nestoji, ne proto, ze by na ne bylo spolehnuti.
            "shading": "basic shading",
            "detail": "low detail",
            # ZAMERNE zadne `outline` (duvod 2 v hlavicce) a zadne style_character_id.
            "negative_description": bible["negative"],
        }
    else:
        params = {
            "description": prompt,
            "item_descriptions": [prompt],
            "size": 64,
            "view": "top-down",   # jeho enum "low top-down" nezna (duvod 3 v hlavicce)
            "negative_description": bible["negative"],
        }
    payload, dropped = gap.adapt_to_schema(
        "mcp__pixellab__%s" % spec["tool"], params, schema)
    return payload, dropped


def cmd_balance(_args):
    print(pixellab.text_of(pixellab.call("get_balance")))


def cmd_dry(_args):
    for name in sorted(FORMS):
        payload, dropped = build_params(name)
        print("=== %s (%s, %s) ===" % (name, FORMS[name]["kind"], FORMS[name]["tool"]))
        if dropped:
            print("VYHOZENO (zive schema je nezna): %s" % ", ".join(dropped))
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        print()


def cmd_queue(args):
    if not args.yes:
        raise SystemExit("chybi --yes (tohle utraci ~40 generaci)")
    jobs = {}
    if os.path.isfile(STATE):
        jobs = json.load(io.open(STATE, encoding="utf-8"))
    for name in sorted(FORMS):
        if jobs.get(name, {}).get("id"):
            print("preskakuji %s -- uz ma job %s" % (name, jobs[name]["id"]))
            continue
        payload, _dropped = build_params(name)
        text = pixellab.text_of(pixellab.call(FORMS[name]["tool"], payload))
        m = re.search(r"([0-9a-f]{8}-[0-9a-f-]{27,})", text)
        jobs[name] = {"id": m.group(1) if m else None, "tool": FORMS[name]["tool"],
                      "raw": text[:400]}
        print("zafrontovano %s -> %s"
              % (name, jobs[name]["id"] or "SELHALO: " + text[:200]))
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with io.open(STATE, "w", encoding="utf-8") as f:
        f.write(json.dumps(jobs, indent=2, ensure_ascii=False, sort_keys=True))


def cmd_status(_args):
    if not os.path.isfile(STATE):
        raise SystemExit("neni %s -- nejdriv `queue`" % os.path.relpath(STATE, PROJ))
    jobs = json.load(io.open(STATE, encoding="utf-8"))
    poll = {"create_character": ("get_character", "character_id"),
            "create_1_direction_object": ("get_object", "object_id")}
    for name in sorted(jobs):
        job = jobs[name]
        if not job.get("id"):
            print("%s: job nikdy nevznikl -- %s" % (name, job.get("raw", "")[:160]))
            continue
        method, key = poll[job["tool"]]
        text = pixellab.text_of(pixellab.call(method, {key: job["id"]}))
        urls = sorted(set(re.findall(r"https://\S+\.png", text)))
        if not urls:
            print("%s: jeste neni hotovo (%s)" % (name, text[:120]))
            continue
        out_dir = raw_dir(name)
        os.makedirs(out_dir, exist_ok=True)
        got = 0
        for i, u in enumerate(urls):
            out = os.path.join(out_dir, "cand_%02d.png" % i)
            r = subprocess.run(["curl", "-sS", "-A", pixellab.UA, "-o", out, u],
                               capture_output=True)
            if r.returncode == 0 and os.path.exists(out) and os.path.getsize(out) > 0:
                got += 1
        print("%s: stazeno %d kandidatu -> %s"
              % (name, got, os.path.relpath(out_dir, PROJ)))


def _silhouette(im, color=(20, 20, 20)):
    """Alfa prah na jednu plochou barvu -- siluetovy test (§12d) delany okem."""
    from PIL import Image
    a = im.split()[-1] if im.mode == "RGBA" else Image.new("L", im.size, 255)
    mask = a.point(lambda p: 255 if p > 24 else 0)
    flat = Image.new("RGBA", im.size, (0, 0, 0, 0))
    flat.paste(Image.new("RGBA", im.size, color + (255,)), (0, 0), mask)
    return flat


def cmd_sheet(_args):
    """Kontaktni list: barevny radek a pod nim siluetovy, oboji v hernim meritku.

    Silueta je pod barvou schvalne -- §12d's hlavni brana je "poznas habit od distrakce
    jako CERNY TVAR", a to se neda posoudit, kdyz je vedle barva, ktera odpoved
    napovi."""
    from PIL import Image
    groups = []
    for name in sorted(FORMS):
        d = raw_dir(name)
        if not os.path.isdir(d):
            continue
        paths = [os.path.join(d, p)
                 for p in sorted(f for f in os.listdir(d) if f.endswith(".png"))]
        if paths:
            groups.append((name, paths))
    if not groups:
        raise SystemExit("zadni kandidati -- nejdriv `status`")

    scale = 4                      # 480x270 se prezentuje pres integer 4x (§12a)
    cell = 64 * scale
    pad = 8
    per_row = 8                    # jinak je list sirsi nez kterykoli monitor
    band = cell * 2 + pad          # barva + silueta pod ni
    rows = []                      # (name, radek cest)
    for name, paths in groups:
        for i in range(0, len(paths), per_row):
            rows.append((name, paths[i:i + per_row]))

    w = per_row * (cell + pad) + pad
    h = len(rows) * (band + pad * 3) + pad
    sheet = Image.new("RGBA", (w, h), (20, 17, 41, 255))          # tkan §4
    y = pad
    for _name, paths in rows:
        for i, path in enumerate(paths):
            im = Image.open(path).convert("RGBA").resize((cell, cell), Image.NEAREST)
            x = pad + i * (cell + pad)
            sheet.paste(im, (x, y), im)
            sil = _silhouette(im)
            sheet.paste(sil, (x, y + cell + pad), sil)
        y += band + pad * 3
    os.makedirs(os.path.dirname(SHEET), exist_ok=True)
    sheet.save(SHEET)
    print("zapsano %s (%d rad, %d kandidatu)"
          % (os.path.relpath(SHEET, PROJ), len(rows), sum(len(p) for _n, p in groups)))
    for name, paths in groups:
        print("  %s: %d" % (name, len(paths)))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("balance").set_defaults(fn=cmd_balance)
    sub.add_parser("dry").set_defaults(fn=cmd_dry)
    q = sub.add_parser("queue")
    q.add_argument("--yes", action="store_true", help="potvrzeni, ze se smi utracet")
    q.set_defaults(fn=cmd_queue)
    sub.add_parser("status").set_defaults(fn=cmd_status)
    sub.add_parser("sheet").set_defaults(fn=cmd_sheet)
    args = ap.parse_args(argv)
    return args.fn(args) or 0


if __name__ == "__main__":
    sys.exit(main())
