# Paletovy pruchod pres kandidaty masteru smeru A -- lokalne, offline, deterministicky.
#
# PROC TENHLE SOUBOR EXISTUJE
#
# Barevne brany (STYLE_BIBLE.md SS12d) dnes neprojde 0 z 24 masteru. Ale to, co se meri,
# je SYROVY vystup PixelLabu, ktery nikdy nesel pres reduce_colors -- takze se meri neco,
# co do hry stejne nepujde. M0 to sam oznacil za "pravdepodobne pipeline, ne navrh".
# Dokud tenhle krok nikdo neudela, je barevna cast M-SEZENI rozhodovani nad barvami,
# ktere hrac nikdy neuvidi.
#
# SS12d popisuje presne dve kola a nabizi je i lokalne:
#
#   1. Snap na palette_48. Strop 48 barev, ne rozpocet 6 -- shipnute distrakce proto maji
#      22-24 unikatnich RGB a zadna by branou neprosla.
#   2. Druhe, prisnejsi kolo: vybrat PODMNOZINU uz nasnapovane palety, "takze se z ni
#      neda vypadnout".
#
# Bod 2 je tu doslova. `sprite_cleanup.build_palette()` vraci jako reprezentanta shluku
# jeho nejcastejsi SKUTECNOU barvu, ne prumer -- takze kdyz mu na vstup dam pool uz
# nasnapovany na palette_48, je jeho vystup podmnozinou palette_48 z KONSTRUKCE, ne
# shodou okolnosti. Zadny dalsi snap uz neni potreba a nemuze vzniknout barva mimo paletu.
#
# CO SE TU NEOPISUJE
#
# CLAUDE.md: "Nikdy neopisuj konstantu, ktera ma jediny zdroj pravdy jinde ... i
# v jednorazovem harnessu." Ctyri zaznamenane pripady v tomhle repu. Tenhle nastroj tedy
# nema JEDINOU vlastni kopii:
#
#   barevne rozpocty (8 / 6)      <- check_style_failure_modes.bible_gates(), tj. z bible
#   prahy siluety a odstupu       <- tatáz funkce
#   definice "nepruhledny pixel"  <- check_style_failure_modes.ALPHA_THRESH
#   kompaktnost, pocet barev      <- check_style_failure_modes.compactness/unique_colors
#   cesta k master palete         <- gen_ui.MASTER_PAL
#   Oklab remap a jeho CHROMA_WEIGHT <- sprite_cleanup (tam, kde uz je zmereny)
#
# Merim tedy TOUTEZ funkci, jakou pouziva brana. Druha kopie vzorce by branu a nastroj
# rozvedla presne tak, jak na to varuje CLAUDE.md.
#
# CO TENHLE NASTROJ NEUMI A RIKA TO NAHLAS
#
# Paletovy pruchod nesaha na alfu, takze NEMUZE zmenit kompaktnost ani odstup rodin.
# Silueta zustane presne tam, kde byla -- a to je duvod, proc master distraction stejne
# potrebuje pregenerovat. Aby to nebylo tvrzeni, ale dukaz, nastroj kompaktnost pred a po
# porovna a kdyz se lisi, skonci chybou.
#
# POUZITI
#
#   python tools/master_palette_pass.py              # zapise soubory a vypise tabulku
#   python tools/master_palette_pass.py --dry-run    # jen zmeri, nic nezapise
import argparse
import os
import sys
from collections import Counter

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import check_style_failure_modes as G  # noqa: E402
import sprite_cleanup as S  # noqa: E402
from gen_ui import MASTER_PAL  # noqa: E402

ROOT = G.ROOT

# Rodiny, ktere se meri. Klic je jmeno rodiny tak, jak ho pouziva bible v gen:failure_modes
# ("silueta, habit" / "styl, barvy habitu"), aby se prahy hledaly beze jmenne mapy navic.
FAMILIES = (
    ("habit", os.path.join(G.ASSETS, "raw", "master_habit_a")),
    ("distraction", os.path.join(G.ASSETS, "raw", "master_distraction_a")),
)


def gate(gates, key):
    """Prah z bible, nebo srozumitelna smrt. Chybejici radek je vada bible, ne default."""
    if key not in gates:
        raise SystemExit(
            "STYLE_BIBLE.md gen:failure_modes nema radek %r -- bez nej nevim, "
            "proti cemu merit." % key)
    return gates[key]


def passes(value, spec):
    op, thr = spec
    if value is None:
        return False
    return value <= thr if op == "<=" else value >= thr if op == ">=" else value == thr


def candidates(folder):
    """cand_*.png, bez uz vyrobenych vystupu. Tridene, at jsou behy reprodukovatelne."""
    if not os.path.isdir(folder):
        return []
    out = []
    for fn in sorted(os.listdir(folder)):
        if not fn.startswith("cand_") or not fn.endswith(".png"):
            continue
        if "_pal48" in fn:          # vystup predchoziho behu, ne vstup
            continue
        out.append(os.path.join(folder, fn))
    return out


def pool_of(rgb, mask):
    """barva -> pocet pixelu, jen pres nepruhledne. Vstup pro build_palette()."""
    return Counter(map(tuple, rgb[mask]))


def snap(rgb, mask, pal):
    return S.remap(rgb.astype(np.int64), mask, pal, S.to_oklab(pal), S.CHROMA_WEIGHT)


def process(path, budget, pal48, write=True):
    """Dve kola SS12d nad jednim kandidatem. Vraci merení pred a po."""
    rgba = G.load_rgba(path)
    mask = G.opaque_mask(rgba)
    rgb0 = rgba[..., :3]

    before_colors = G.unique_colors(rgb0, mask)
    before_comp = G.compactness(mask)

    # 1. kolo -- snap na palette_48.
    rgb1 = snap(rgb0, mask, pal48)
    mid_colors = G.unique_colors(rgb1.astype(np.uint8), mask)

    # 2. kolo -- podmnozina uz nasnapovane palety o velikosti rozpoctu rodiny.
    sub = S.build_palette(pool_of(rgb1.astype(np.uint8), mask), int(budget))
    rgb2 = S.remap(rgb1, mask, sub, S.to_oklab(sub), S.CHROMA_WEIGHT)
    after_colors = G.unique_colors(rgb2.astype(np.uint8), mask)

    # Dukaz, ne tvrzeni: podmnozina opravdu lezi v palette_48.
    pal_set = {tuple(c) for c in pal48.tolist()}
    stray = [tuple(c) for c in sub.tolist() if tuple(c) not in pal_set]
    if stray:
        raise SystemExit("%s: 2. kolo vyrobilo barvu mimo palette_48: %s" % (path, stray))

    out_paths = []
    if write:
        for suffix, arr in (("_pal48", rgb1), ("_pal48_k%d" % int(budget), rgb2)):
            dst = path.replace(".png", suffix + ".png")
            img = np.dstack([arr.astype(np.uint8), rgba[..., 3]])
            Image.fromarray(img, mode="RGBA").save(dst)
            out_paths.append(dst)

        # Alfa se nesmi hnout -- jinak by se zmenila silueta a merení by lhalo.
        check = G.load_rgba(out_paths[-1])
        if G.compactness(G.opaque_mask(check)) != before_comp:
            raise SystemExit("%s: paletovy pruchod zmenil siluetu -- to nesmi." % path)

    return {
        "path": os.path.relpath(path, ROOT).replace("\\", "/"),
        "colors": (before_colors, mid_colors, after_colors),
        "compactness": before_comp,
        "outputs": out_paths,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true",
                    help="jen zmer a vypis, nic nezapisuj")
    args = ap.parse_args()

    gates = G.bible_gates()
    pal48 = S.load_palette_file(MASTER_PAL)
    print("paleta      : %s (%d barev)" % (
        os.path.relpath(MASTER_PAL, ROOT).replace("\\", "/"), len(pal48)))
    print("prahy        : z docs/art/STYLE_BIBLE.md gen:failure_modes\n")

    rows = []
    comp_by_family = {}
    for family, folder in FAMILIES:
        budget_spec = gate(gates, "styl, barvy %s" % (
            "habitu" if family == "habit" else "distrakce"))
        sil_spec = gate(gates, "silueta, %s" % family)
        budget = budget_spec[1]

        print("== %s -- rozpocet %s %g barev, silueta %s %g" % (
            family, budget_spec[0], budget, sil_spec[0], sil_spec[1]))
        comps = []
        for path in candidates(folder):
            r = process(path, budget, pal48, write=not args.dry_run)
            b, m, a = r["colors"]
            comps.append(r["compactness"])
            rows.append((family, r, budget_spec, sil_spec))
            print("   %-42s barvy %3d -> %3d -> %3d  %s   silueta %5.3f %s" % (
                os.path.basename(r["path"]), b, m, a,
                "OK " if passes(a, budget_spec) else "FAIL",
                r["compactness"], "OK" if passes(r["compactness"], sil_spec) else "FAIL"))
        comp_by_family[family] = comps
        print()

    # Souhrn -- kolik projde po pruchodu proti tomu, co hlasi brana dnes.
    print("---- souhrn ----")
    for family, _ in FAMILIES:
        fam_rows = [r for f, r, *_ in rows if f == family]
        if not fam_rows:
            continue
        bspec = [b for f, _, b, _ in rows if f == family][0]
        sspec = [s for f, _, _, s in rows if f == family][0]
        col_ok = sum(1 for r in fam_rows if passes(r["colors"][2], bspec))
        col_was = sum(1 for r in fam_rows if passes(r["colors"][0], bspec))
        sil_ok = sum(1 for r in fam_rows if passes(r["compactness"], sspec))
        print("%-12s barvy %2d/%2d -> %2d/%2d      silueta %2d/%2d (pruchod na ni nesaha)"
              % (family, col_was, len(fam_rows), col_ok, len(fam_rows),
                 sil_ok, len(fam_rows)))

    # Soudrznost rodiny a odstup rodin -- obojí z bible, obojí po pruchodu.
    coh_spec = gate(gates, "styl, soudržnost rodiny")
    for family, _ in FAMILIES:
        fam = [r["colors"][2] for f, r, *_ in rows if f == family]
        if fam:
            spread = max(fam) - min(fam)
            print("%-12s soudrznost %d (%s %g) %s" % (
                family, spread, coh_spec[0], coh_spec[1],
                "OK" if passes(spread, coh_spec) else "FAIL"))

    sep_spec = gate(gates, "silueta, odstup rodin")
    if comp_by_family.get("habit") and comp_by_family.get("distraction"):
        sep = min(comp_by_family["distraction"]) - max(comp_by_family["habit"])
        print("odstup rodin %.3f (%s %g) %s   -- nezmeneny, paleta na alfu nesaha" % (
            sep, sep_spec[0], sep_spec[1],
            "OK" if passes(sep, sep_spec) else "FAIL"))

    if args.dry_run:
        print("\n--dry-run: nic se nezapsalo.")


if __name__ == "__main__":
    main()
