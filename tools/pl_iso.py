# Driver pro ISO art batch — zadava joby do PixelLabu a vede o nich ucetnictvi.
#
# PROC SAMOSTATNY SOUBOR A NE JEDNORAZOVE VOLANI
#
# Generovani je asynchronni a trva 1-3 minuty na job. Kdyz se ID jobu drzi jen v hlave
# sezeni, prvni preruseni znamena, ze zaplacene generovani zmizi a musi se objednat
# znovu. Ledger `build/iso_art/jobs.json` je proto povinny mezikrok: zada se, ulozi se
# ID, teprve pak se ceka. Odtud jde kdykoliv navazat (`python tools/pl_iso.py poll`).
#
# POUZITI
#   python tools/pl_iso.py submit <batch>   # zada davku podle receptu nize
#   python tools/pl_iso.py poll             # zjisti stav vseho rozdelaneho
#   python tools/pl_iso.py pull             # stahne hotove do build/iso_art/
#   python tools/pl_iso.py ls               # vypis ledgeru
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pixellab  # noqa: E402

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(PROJ, "build", "iso_art")
LEDGER = os.path.join(OUT, "jobs.json")

# ---------------------------------------------------------------- art direction
#
# "Deep Focus — Cortex Terrace". Cela paleta je v docs/art/iso_bible.md; tady jsou
# jen ty vety, ktere jdou do generatoru, aby se recept nedal ztratit prepisem chatu.
#
# Hodnotova hierarchie, na ktere cela deska stoji (soucet RGB):
#   prazdno 20 < tkan 60-110 < pruh 120-160 < zed stin 70 / svetlo 150 < terasa 400+
# Terasa je NEJSVETLEJSI plocha ve hre krome jadra. To je ta cela informace: kde je
# svetlo, tam se da stavet.

RECIPES = {
    # ---- davka 1: zeme -------------------------------------------------------
    # ---- terasa v duchu Settlers (21. 8. 2026) ------------------------------
    #
    # PROC NOVY RECEPT A NE UPRAVA STAREHO
    #
    # Stara terasa ("smooth pale bone-white ceramic") vysla technicky spravne, ale
    # ctla plocho. Duvod se ale ZMERIL SPATNE, a to je na tomhle receptu to poucne:
    #
    #   puvodne zde stalo "vrch 484, oba boky 321, tedy 100 : 66 : 66, steny jsou
    #   stejne" -- to cislo vzniklo rozdelenim dlazdice na VODOROVNA PASMA, coz u
    #   kosoctverce michá vrch do boku. Geometricky spravne (tools/iso_faces.py) vychazi
    #   vrch 484, levy 400, pravy 298, tedy 100 : 83 : 62, SVETLO ZLEVA.
    #
    # Tri tony tam tedy byly a smer svetla take. Vada byla jen STLACENY ROZSAH -- a to
    # je prebarveni, ne duvod k novemu artu. Chybne mereni stalo ctyri generovani.
    #
    # Zadani proto rika hodnotovy vztah PRIMO v obou popisech, misto aby doufalo, ze
    # generator sam pochopi, ze podlaha ma byt svetlejsi nez stena.
    #
    # Druha zmerena vada byla hustota detailu (hlavy vezi 35,5 hrany/px proti 10,9 u
    # cesty). Proto "a few large slabs" a "no fine masonry" -- min tvaru, nez pusobi
    # spravne pri pohledu zblizka.
    #
    # Co se schvalne NEMENI proti stare davce: tile_size 64, wall_tiles 1,
    # outline_mode segmentation a nenastaveny tile_view_angle. Ta kombinace se zmerila
    # jako mrizkove presna (skirt zakryje sparu, 0 uzavrenych der) a menit vic promennych
    # najednou znamena nevedet, ktera za vysledek muze.
    "terrace_settlers": (
        "create_building_kit",
        dict(
            floor_description=(
                "top of a stone plateau lit from above, large weathered pale limestone "
                "flagstones with soft rounded edges, only three or four slabs across, "
                "thin darker seams, a little muted sage moss in the seams, "
                "warm friendly hand-painted medieval settlement game art, "
                "flat blocked shading with no gradients, "
                "this is the BRIGHTEST surface in the scene"
            ),
            wall_description=(
                "side of a stone plateau in shadow, three large stacked limestone "
                "blocks with soft weathered edges, cool grey shadow, "
                "CLEARLY AND OBVIOUSLY DARKER than the sunlit floor above it, "
                "the right-facing side darker still than the left-facing side, "
                "warm friendly hand-painted medieval settlement game art, "
                "flat blocked shading, no moss, no bricks, no fine masonry, no cracks"
            ),
            tile_type="isometric",
            tile_size=64,
            wall_tiles=1,
            outline_mode="segmentation",
            seed=8811,
        ),
    ),
    # Druhy los tehoz zadani. Jas se z promptu vytahnout neda (na jednom cili vyslo
    # 400 / 524 / 606), takze dva losy nejsou plytvani -- je to jediny zpusob, jak mit
    # z ceho vybrat, aniz by se zadani menilo.
    "terrace_settlers_b": (
        "create_building_kit",
        dict(
            floor_description=(
                "top of a stone plateau lit from above, large weathered pale limestone "
                "flagstones with soft rounded edges, only three or four slabs across, "
                "thin darker seams, a little muted sage moss in the seams, "
                "warm friendly hand-painted medieval settlement game art, "
                "flat blocked shading with no gradients, "
                "this is the BRIGHTEST surface in the scene"
            ),
            wall_description=(
                "side of a stone plateau in shadow, three large stacked limestone "
                "blocks with soft weathered edges, cool grey shadow, "
                "CLEARLY AND OBVIOUSLY DARKER than the sunlit floor above it, "
                "the right-facing side darker still than the left-facing side, "
                "warm friendly hand-painted medieval settlement game art, "
                "flat blocked shading, no moss, no bricks, no fine masonry, no cracks"
            ),
            tile_type="isometric",
            tile_size=64,
            wall_tiles=1,
            outline_mode="segmentation",
            seed=4207,
        ),
    ),
    # ---- terasa jako TERENNI PRECHOD, ne architektura (21. 8. 2026) ---------
    #
    # POUCENI Z PREDCHOZI DAVKY: `create_building_kit` udelal cihlove zdi, schody a
    # sloupy -- hrad. Delal presne to, k cemu je: MISTNOSTI. Prompt "side of a stone
    # plateau" na tom nic nezmenil, protoze nastroj neni od terenu.
    #
    # Building kit to sam rika ve svem popisu: "Not a terrain set: for grass-meets-water
    # use create_tiles_pro(tile_feature='tileset')". Vyvysena zem POTKAVAJICI nizkou je
    # presne grass-meets-water, jen svisle.
    #
    # 16-dilna rohova sada zaroven resi to, ze dnesni terasa vypada jako sachovnice z
    # opakovanych ctverecku: kazda bunka dostane vlastni block.png a chybi rohy a hrany.
    "terrace_plateau": (
        "create_tiles_pro",
        dict(
            description=(
                "1). raised plateau of warm weathered limestone, sunlit flat top with "
                "a few large slabs, soft rounded edges, muted sage moss in the seams, "
                "the side drops away in shadow and is clearly darker than the top "
                "2). dark low ground of deep indigo-violet soil, quiet and almost flat, "
                "no detail. Warm friendly hand-painted medieval settlement game art, "
                "flat blocked shading with no gradients, no bricks, no masonry, "
                "no walls, no stairs, no buildings"
            ),
            tile_type="isometric",
            tile_size=64,
            tile_feature="tileset",
            tile_flat_top_px=2,
            outline_mode="segmentation",
            seed=5150,
        ),
    ),
    # ---- plosina, druhy pokus: VYSSI BOK + vetsi kameny (21. 8. 2026) -------
    #
    # Prvni pokus (terrace_plateau, seed 5150) vysel merenim dobre -- po zrcadleni
    # 100 : 70 : 52 proti starym 100 : 83 : 62 -- ale OBRAZEM spatne:
    #   * bok jen 16 px proti 32 px u stare terasy, takze plosina cetla jako deska
    #     polozena na zem, ne jako vyvysena zem. Vyska je pritom ta informace, kvuli
    #     ktere terasa existuje ("sem se da stavet").
    #   * drobne kameny se na kazde bunce opakovaly a vznikla z toho mrizka.
    #
    # Proto se meni PRESNE DVE veci a nic jineho: tile_height na 64 (dlazdice 64x64,
    # tedy vrch 32 + bok 32 jako u stare) a popis na velke kusy pres celou dlazdici.
    # Vic promennych naraz znamena nevedet, ktera za vysledek muze.
    "terrace_plateau2": (
        "create_tiles_pro",
        dict(
            description=(
                "1). raised plateau of warm weathered limestone, one or two BIG slabs "
                "filling the whole top, very few seams, muted sage moss in the seams, "
                "a TALL rock face dropping away below the top, clearly darker than the "
                "top, layered strata in the rock face "
                "2). dark low ground of deep indigo-violet soil, quiet and flat, "
                "no detail. Warm friendly hand-painted medieval settlement game art, "
                "flat blocked shading with no gradients, no small cobbles, no bricks, "
                "no masonry, no walls, no stairs, no buildings"
            ),
            tile_type="isometric",
            tile_size=64,
            tile_height=64,
            tile_feature="tileset",
            tile_flat_top_px=2,
            outline_mode="segmentation",
            seed=5151,
        ),
    ),
    # ---- terasa nastrojem, ktery ma VYSKU jako parametr (21. 8. 2026) ------
    #
    # POUCENI ZE TRI PREDCHOZICH POKUSU: `create_tiles_pro` ma bok napevno 16 px pri
    # dlazdici 64 a `tile_height` ignoruje (zmereno na terrace_plateau i _plateau2).
    # `create_building_kit` udelal hrad. Ani jeden z nich neumi rict, jak ma byt blok
    # vysoky -- a prave vyska je ta informace, kvuli ktere terasa existuje.
    #
    # `create_isometric_tile` ma `tile_shape` jako vyslovny stupen: thin ~10 % vysky
    # platna, thick ~25 %, block ~50 %. Pri size=64 vychazi block na ~32 px boku, coz
    # je zhruba tech 33 px, ktere ma stara block.png. Aritmetika sedi; jestli sedi i
    # obraz, rozhodne mereni po stazeni, ne tenhle komentar.
    #
    # VYSLEDEK (zmereno tools/iso_faces.py, 21. 8. 2026): bok 32 px u OBOU losu, tedy
    # PRESNE to, co zadny jiny nastroj neumel. Vyska je tim vyresena.
    #
    # A presto se to NEINSTALOVALO, protoze tohle kresli JEDEN OBJEKT, ne dilek sady:
    #   * hrany na vrchu 48 % (A) a 35 % (B) proti 25,5 % u stare block.png, rozptyl
    #     jasu 227 a 142 proti 32. Vydlazdene 3x3 z toho je vaflovy plat -- kazda bunka
    #     vlastni polstar s vlastnim obrysem, misto jednoho vyvyseneho masivu.
    #   * steny ujely do purpuru: vrch 22/31 stupnu, steny 299-329.
    #
    # Odstin i pomer se sesadit DAJI (iso_faces.py --regrade + sesazeni odstinu) a bylo
    # to vyzkouseno -- blok po tom porad cetl jako vafle. Hustota detailu je ta smrtelna
    # vada a promptem se neda vzit dolu, `detail`/`shading` jsou dle schematu jen
    # "weakly guiding".
    #
    # Nechava se tu jako ZMERENY protipriklad: az nekdo priste bude chtit vyvysenou zem
    # z PixelLabu, tohle uz je zaplacene a zodpovezene.
    #
    # Nastroj bere KRATKY popis ("grass on top of dirt"), takze hodnotovy vztah se rika
    # jednou vetou a zbytek nesou parametry:
    #   outline "lineless"    -- bible nechce obrysy
    #   shading "flat shading" -- "plosne tonovani, zadne prechody" (fae_theme 1b)
    #   detail  "low detail"   -- zmerena vada byla hustota detailu, ne jeho nedostatek
    #
    # Dva losy tehoz zadani ze stejneho duvodu jako u davky "settlers": jas ani pomer
    # tonu se promptem vynutit nedaji, da se z nich jen vybrat.
    "terrace_block_a": (
        "create_isometric_tile",
        dict(
            description=(
                "pale warm limestone flat top on top of a tall rock face, "
                "the top is bright and sunlit, the rock face below is clearly much "
                "darker, one or two big slabs, muted sage moss in the seams, "
                "no bricks, no masonry, no stairs"
            ),
            size=64,
            tile_shape="block",
            outline="lineless",
            shading="flat shading",
            detail="low detail",
            seed=5160,
        ),
    ),
    "terrace_block_b": (
        "create_isometric_tile",
        dict(
            description=(
                "pale warm limestone flat top on top of a tall rock face, "
                "the top is bright and sunlit, the rock face below is clearly much "
                "darker, one or two big slabs, muted sage moss in the seams, "
                "no bricks, no masonry, no stairs"
            ),
            size=64,
            tile_shape="block",
            outline="lineless",
            shading="flat shading",
            detail="low detail",
            seed=5161,
        ),
    ),
    "terrace": (
        "create_building_kit",
        dict(
            wall_description=(
                "smooth pale bone-white ceramic wall, carved horizontal strata bands, "
                "cool grey-blue shadowed side, clean and man-made, no bricks, no moss"
            ),
            floor_description=(
                "smooth pale bone-white ceramic floor panels, faint hairline seams, "
                "polished, cool neutral grey-white, clean and quiet, no cracks"
            ),
            tile_type="isometric",
            tile_size=64,
            wall_tiles=1,
            outline_mode="segmentation",
            seed=7301,
        ),
    ),
    "lane": (
        "create_path_tiles",
        dict(
            description=(
                "very dark indigo-violet neural tissue ground with a worn "
                "amber-bronze walkway trodden into it, dull matte metal, "
                "no glow, no grass"
            ),
            tile_type="isometric",
            tile_size=64,
            outline_mode="segmentation",
            seed=7302,
        ),
    ),
    "tissue": (
        "create_tiles_pro",
        dict(
            description=(
                "1). very dark indigo neural tissue, quiet and smooth "
                "2). very dark indigo neural tissue with faint violet mottling "
                "3). very dark indigo neural tissue with shallow folds "
                "4). very dark indigo neural tissue with one thin cyan synapse filament"
            ),
            tile_type="isometric",
            tile_size=64,
            tile_view="top-down",
            outline_mode="segmentation",
            seed=7303,
        ),
    ),
}

BATCHES = {
    "ground": ["terrace", "lane", "tissue"],
    # Dva losy tehoz zadani, at je z ceho vybrat -- jas se z promptu vytahnout neda.
    "settlers": ["terrace_settlers", "terrace_settlers_b"],
    "plateau": ["terrace_plateau"],
    "plateau2": ["terrace_plateau2"],
    "block": ["terrace_block_a", "terrace_block_b"],
}


def load_ledger():
    if os.path.isfile(LEDGER):
        return json.load(open(LEDGER, encoding="utf-8"))
    return {}


def save_ledger(d):
    os.makedirs(OUT, exist_ok=True)
    json.dump(d, open(LEDGER, "w", encoding="utf-8"), indent=1, ensure_ascii=False)


ID_KEYS = ("tile_id", "character_id", "object_id", "image_id", "id")


def extract_id(text):
    """Vytahne UUID z textove odpovedi. Nastroje ho vraci ruzne pojmenovane a nekdy
    jen v prose, takze se hleda nejdriv podle klice a pak jako holy UUID."""
    import re

    for k in ID_KEYS:
        m = re.search(rf"{k}[\"']?\s*[:=]\s*[\"']?([0-9a-f-]{{36}})", text, re.I)
        if m:
            return m.group(1)
    m = re.search(r"\b([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\b", text, re.I)
    return m.group(1) if m else None


def submit(batch):
    c = pixellab.Client()
    led = load_ledger()
    for name in BATCHES[batch]:
        if name in led and led[name].get("id"):
            print(f"skip {name} (uz zadano: {led[name]['id']})")
            continue
        tool, args = RECIPES[name]
        text, _ = c.call(tool, args)
        jid = extract_id(text)
        led[name] = {"tool": tool, "args": args, "id": jid, "raw": text[:1200],
                     "submitted": time.strftime("%Y-%m-%d %H:%M:%S")}
        save_ledger(led)
        print(f"submit {name}: tool={tool} id={jid}")
        if not jid:
            print("  !! ID se nenaslo, syrova odpoved:")
            print("  " + text[:600].replace("\n", "\n  "))


GETTER = {
    "create_building_kit": ("get_tiles_pro", "tile_id"),
    "create_path_tiles": ("get_tiles_pro", "tile_id"),
    "create_tiles_pro": ("get_tiles_pro", "tile_id"),
    "create_isometric_tile": ("get_isometric_tile", "tile_id"),
    "create_map_object": ("get_map_object", "object_id"),
    "create_1_direction_object": ("get_object", "object_id"),
    "create_8_direction_object": ("get_object", "object_id"),
    "create_character": ("get_character", "character_id"),
    # POZOR: get_image chce `job_id`, ne `image_id` -- schema tri obrazkovych nastroju
    # vraci ID pod jinym jmenem, nez pod jakym ho getter prijima. Odhaleno az prvnim
    # skutecnym pouzitim (21. 8. 2026), protoze do te doby se tudy nic negenerovalo.
    "create_image_pixflux": ("get_image", "job_id"),
    "create_image_pixen": ("get_image", "job_id"),
    "create_image_pro": ("get_image", "job_id"),
    "create_ui_asset": ("get_ui_asset", "asset_id"),
}


def poll(only=None):
    c = pixellab.Client()
    led = load_ledger()
    for name, rec in led.items():
        if only and name not in only:
            continue
        if not rec.get("id"):
            continue
        getter, key = GETTER[rec["tool"]]
        text, _ = c.call(getter, {key: rec["id"]})
        rec["status_text"] = text
        head = " | ".join(text.splitlines()[:4])
        print(f"{name:14s} {head[:200]}")
    save_ledger(led)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "ls"
    if cmd == "submit":
        submit(sys.argv[2])
    elif cmd == "poll":
        poll(sys.argv[2:] or None)
    elif cmd == "pull":
        pull(sys.argv[2:] or None)
    elif cmd == "check":
        check(sys.argv[2:] or None)
    elif cmd == "sheet":
        sheet(sys.argv[3:], sys.argv[2])
    elif cmd == "ls":
        led = load_ledger()
        for k, v in led.items():
            print(f"{k:14s} {v.get('tool'):26s} {v.get('id')}")
    else:
        raise SystemExit(__doc__ or "neznamy prikaz")


# ------------------------------------------------------------------ stahovani
#
# URL se parsuji z textu `get_*`, protoze strukturovanou odpoved tyhle nastroje
# nevraci (stejne jako u postav, viz pixellab.parse_character).

def _urls(text):
    import re
    out = {}
    for line in text.splitlines():
        m = re.match(r"^\s{2,}([\w\-]+):\s*(https?://\S+)\s*$", line)
        if m and m.group(1) != "download":
            out[m.group(1)] = m.group(2)
    return out


def pull(only=None):
    import re
    led = load_ledger()
    for name, rec in led.items():
        if only and name not in only:
            continue
        text = rec.get("status_text", "")
        if "status: completed" not in text:
            continue
        urls = _urls(text)
        if not urls:
            # map_object / ui_asset nevraci seznam `storage_urls` jako dlazdicove sady,
            # jen jedno `download:`. Stahne se primo -- muze to byt PNG i ZIP, pozna se
            # podle magickych bajtu, ne podle pripony v URL (ta tam neni).
            m = re.search(r"^download:\s*(https?://\S+)", text, re.M)
            if not m:
                print(f"{name}: hotovo, ale zadne URL v odpovedi")
                continue
            blob = pixellab.fetch(m.group(1))
            d = os.path.join(OUT, name)
            os.makedirs(d, exist_ok=True)
            if blob[:2] == b"PK":
                import io, zipfile
                z = zipfile.ZipFile(io.BytesIO(blob))
                png = [n for n in z.namelist() if n.lower().endswith(".png")]
                for n in png:
                    open(os.path.join(d, os.path.basename(n)), "wb").write(z.read(n))
                print(f"{name}: zip, {len(png)} png -> {d}")
            else:
                pixellab.save(os.path.join(d, "object.png"), blob)
                print(f"{name}: 1 soubor -> {d}")
            continue
        d = os.path.join(OUT, name)
        os.makedirs(d, exist_ok=True)
        # Hotove soubory se preskakuji jen v ramci TEHOZ jobu. Bez toho razitka to byla
        # past, ktera stala jedno cele kolo (22. 8. 2026): druhy beh pod tymz klicem
        # (obj_focus_timer) nasel osm PNG z prvniho jobu, vsechna preskocil a vypsal
        # "8 souboru" -- o souborech, ktere odmitl prepsat. Merena data pak sedela na
        # starou sadu a vypadalo to, ze generator ignoroval novou predlohu.
        stamp = os.path.join(d, ".job")
        prev = open(stamp, encoding="utf-8").read().strip() if os.path.isfile(stamp) else ""
        same_job = prev == str(rec.get("id", ""))
        got = 0
        for key, url in urls.items():
            p = os.path.join(d, key + ".png")
            if same_job and os.path.isfile(p):
                got += 1
                continue
            pixellab.save(p, pixellab.fetch(url))
            got += 1
        open(stamp, "w", encoding="utf-8").write(str(rec.get("id", "")))
        print(f"{name}: {got} souboru -> {d}"
              + ("" if same_job else "  (nova uloha, prepsano)"))


# ------------------------------------------------------------------- mereni
#
# Rastr se NEZJISTUJE prectenim parametru, ale zmerenim souboru. Tenhle projekt uz
# jednou mesic bezel na rozejitem rastru, protoze cislo v data.gd nesouhlasilo s tim,
# co lezi na disku (viz data.gd, historie TERRAIN_ART_PX). Tohle je ta pojistka.

def check(only=None):
    from PIL import Image
    import numpy as np
    led = load_ledger()
    for name in sorted(led):
        if only and name not in only:
            continue
        d = os.path.join(OUT, name)
        if not os.path.isdir(d):
            continue
        files = sorted(f for f in os.listdir(d) if f.endswith(".png"))
        print(f"\n=== {name} ({len(files)} dlazdic) ===")
        for f in files[:40]:
            im = Image.open(os.path.join(d, f)).convert("RGBA")
            a = np.array(im)
            alpha = a[..., 3] > 8
            if not alpha.any():
                print(f"  {f:14s} {im.width}x{im.height}  PRAZDNE")
                continue
            ys, xs = np.where(alpha)
            bw, bh = xs.max() - xs.min() + 1, ys.max() - ys.min() + 1
            rgb = a[..., :3][alpha].astype(int).sum(1)
            print(f"  {f:14s} canvas {im.width}x{im.height}  obsah {bw}x{bh} "
                  f"@({xs.min()},{ys.min()})  RGB med {int(np.median(rgb)):4d} "
                  f"p95 {int(np.percentile(rgb,95)):4d}")


def sheet(names, out_path, cols=6, scale=2, bg=(10, 12, 20)):
    """Kontaktni list — art se posuzuje okem, ale az po zvetseni na herni meritko."""
    from PIL import Image
    tiles = []
    for name in names:
        d = os.path.join(OUT, name)
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d), key=lambda s: (len(s), s)):
            if f.endswith(".png"):
                tiles.append((name + "/" + f, Image.open(os.path.join(d, f)).convert("RGBA")))
    if not tiles:
        raise SystemExit("nic ke slozeni")
    tw = max(t.width for _, t in tiles) * scale
    th = max(t.height for _, t in tiles) * scale
    rows = (len(tiles) + cols - 1) // cols
    sheet_img = Image.new("RGBA", (cols * tw, rows * th), bg + (255,))
    for i, (_, t) in enumerate(tiles):
        t = t.resize((t.width * scale, t.height * scale), Image.NEAREST)
        sheet_img.alpha_composite(t, ((i % cols) * tw, (i // cols) * th))
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    sheet_img.save(out_path)
    print(f"{out_path}  {sheet_img.width}x{sheet_img.height}  {len(tiles)} dlazdic")

if __name__ == "__main__":
    main()
