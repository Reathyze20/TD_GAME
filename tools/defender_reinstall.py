"""Prevod 64px animaci obrancu z PixelLabu na 48px herni framy.

    python tools/defender_reinstall.py --stage build/obranci_novi
    python tools/defender_reinstall.py --stage build/obranci_novi --apply

PROC TENHLE SOUBOR EXISTUJE

Sady obrancu se do hry nainstalovaly SPATNE: broccoli_knight/attack pochazi z uplne jine
brokolice nez zbytek postavy, chilli_berserker/attack ma 3 framy misto devitistupnoveho
utoku, ktery na PixelLabu lezi, a garlic_mage cestou ztratil hul. Spravny art existuje —
nic se negeneruje, jen se prevede znovu a poradne.

ZMENSENI 64 -> 48 JE TU JADRO VECI

Pomer 0.75 neni celociselny, takze na nem zalezi vic nez obvykle:

  sprite_16.halve(im, 48)   ROZBITE. Pocita `n = im.width // size`, coz je pro 64/48
                            rovno 1, takze blokove vzorkovani degeneruje na jediny pixel
                            a funkce cte jen levy horni roh zdroje. Vysledkem je cerny
                            klin pres pravou polovinu platna. Funkce je psana na 2x
                            zmenseni (64 -> 32) a mimo nej se pouzivat nesmi.
  NEAREST -> gen.clean      Co se pouziva. Sum 42 % (zdroj sam ma 34 %), paleta 16 barev.
  LANCZOS -> gen.clean      ZAMITNUTO, i kdyz udrzi hul (266 px proti 147). Zaplati se za
                            to mezibarvami: sum vyskoci na 51-59 % a art_check to hlasi
                            jako "zbytek po zmenseni renderu" u kazdeho prevedeneho framu.
                            Zkousene i clean(12): cislo kleslo na 43 %, ale v cibuli
                            zustaly bile kazy — cislo se zlepsilo a kresba zhorsila.

TENKA HUL SE NA 48 px NEVEJDE, A JE TO ROZHODNUTI, NE NEDODELEK

Hul garlic_mage je pri 64 px siroka 1 px, tedy pri prevodu na 48 px 0,75 px. Zadny retez
ji neudrzi ostrou — bud ji rastr zahodi (NEAREST), nebo ji rozmaze antialiasing (LANCZOS).
Prednost dostala CISTOTA KRESBY: jeden mag s holi nestoji za to, aby vsechny prevedene
sady dostaly renderovy sum. Kdyz se rozhodne jinak, staci prohodit RESAMPLE nize.

CO SE NEDELA

Nesaha se na sady, ktere jsou v poradku (idle, chuze, smrt u brokolice a chilli). Kdyz
uz je neco spravne, prevadet to znovu znamena jen riskovat, ze se to zhorsi.
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen                                                   # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEST = os.path.join(PROJ, "assets", "defenders")
TARGET = 48

## Co se prevadi. (herni_sada, zdrojova_slozka, kolik_framu, proc)
##
## Zdroje jsou stazene skupiny animaci z PixelLabu, pojmenovane <group8>_<Nf>_<smer>.
## Smer `east` je zamerny: DefenderUnit kresli attack i hurt otocene k cili a zapad si
## zrcadli sam, takze vychodni sada je ta, kterou hra opravdu potrebuje.
PLAN = {
    "broccoli_knight": [
        ("attack", "b6926161_7f_east", 7,
         "skutecny svih s dopadem; stavajici sada je NAKRESLENA JINA brokolice"),
        ("hurt", "ca1bf779_5f_south", 5,
         "skubnuti s opadanim listu; stavajici ma magentovy artefakt a mizici stit"),
    ],
    "chilli_berserker": [
        ("attack", "a9a086aa_9f_east", 9,
         "devitiframova serie seku, ktera drzi barvu; stavajici ma 3 framy"),
    ],
    "garlic_mage": [
        ("walk_east", "823446b8_east", 6, "s holi (stavajici sada hul ztratila)"),
        ("attack", "47dde3a1_east", 9, "svih holi (stavajici sada hul ztratila)"),
    ],
}

## garlic_mage/hurt se NEBERE z PixelLabu, protoze tam zadne skubnuti neni: vsechny ctyri
## skupiny mага jsou kouzla nebo smrt (e1b07808 je vyboj s bilym zablesknutim, 18f38b39
## svih holi dopredu). Pouzit kouzlo jako reakci na zasah by hraci lhalo — mag by pri
## kazde rane vypadal, ze utoci.
##
## Zaroven ale hurt nejde nechat byt: kdyz chuze a utok hul nove maji a hurt ne, hul bude
## pri zasahu problikavat, coz je prave ta vada, kterou tenhle skript odstranuje. Reseni
## je skubnuti vyrobit z NOVEHO spritu s holi — puppet_hit posouva jeho vlastni pixely,
## takze hul ani identita nemuzou ujet.
PUPPET_HURT = {"garlic_mage": ("walk_east", 6)}


## Prohod na Image.LANCZOS, kdyz je tenka rekvizita dulezitejsi nez cistota kresby.
## Duvody obou stran jsou v hlavicce souboru; tohle je to jedine misto, kde se to meni.
RESAMPLE = Image.NEAREST
PALETTE = 16


def to_game(src: Image.Image) -> Image.Image:
    """64px PixelLab -> 48px herni platno. Jen zmenseni a tvrda alfa; paletu a odsumeni
    dela az unify_palette(), protoze obojI musi videt celou postavu naraz."""
    im = src.convert("RGBA")
    if im.size != (TARGET, TARGET):
        im = im.resize((TARGET, TARGET), RESAMPLE)
    a = np.array(im)
    a[..., 3] = np.where(a[..., 3] > 128, 255, 0)
    return Image.fromarray(a, "RGBA")


## PALETA SE STAVI Z CELE POSTAVY, NE Z FRAMU
##
## Tohle je rozdil mezi 5 % a 30 % sumu. gen.clean() dela paletu pro kazdy frame zvlast,
## takze stejne misto na tele dostane frame od framu jiny odstin — povrch "vari" a oko to
## cte jako sum (tyz jev popisuje hlavicka sprite_cleanup.py).
##
## Pool se navic bere i ze SADY, KTERE SE NEPREVADEJI. Nove sady tim dostanou presne tu
## paletu, kterou uz postava ve hre ma, misto vlastni podobne — jinak by se brokolice pri
## prechodu z chuze do utoku nepatrne prebarvila.
def unify_palette(new_frames: dict, char: str, colors: int = 24) -> dict:
    from collections import Counter
    import sprite_cleanup as SC

    pool = Counter()
    for path in sorted(os.listdir(DEST)):
        if path.startswith(char + "_") and path.endswith(".png") \
                and os.path.join(DEST, path) not in new_frames:
            a = np.array(Image.open(os.path.join(DEST, path)).convert("RGBA"))
            m = a[..., 3] > 32
            pool.update(map(tuple, a[..., :3][m]))
    for a in new_frames.values():
        m = a[..., 3] > 32
        pool.update(map(tuple, a[..., :3][m]))
    if not pool:
        return new_frames

    pal = SC.build_palette(pool, colors, 0.5)
    pal_lab = SC.to_oklab(pal)
    lab_of = {tuple(c): l for c, l in zip(map(tuple, pal), pal_lab)}
    out = {}
    for path, a in new_frames.items():
        m = a[..., 3] > 32
        rgb = SC.remap(a[..., :3].astype(np.int64), m, pal, pal_lab)
        rgb, _, _ = SC.despeckle(rgb, m, lab_of, 5, 0.12)
        out[path] = np.dstack([rgb.astype(np.uint8), a[..., 3]])
    return out


def ground(a: np.ndarray) -> int | None:
    ys, _ = np.nonzero(a[:, :, 3] > 0)
    return int(ys.max()) if len(ys) else None


def settle(im: Image.Image, want: int = 47) -> Image.Image:
    """Postav frame na hernI linku zeme. Tuz linku hlida tools/defender_anim_fix.py —
    kdyz ji nove sady dostanou uz pri prevodu, nemusi je pak nikdo posouvat."""
    a = np.array(im)
    g = ground(a)
    if g is None:
        return im
    dy = want - g
    top = np.nonzero(a[:, :, 3] > 0)[0].min()
    dy = max(-int(top), min(dy, 47 - g))
    if dy == 0:
        return im
    out = np.zeros_like(a)
    if dy > 0:
        out[dy:, :] = a[:-dy, :]
    else:
        out[:dy, :] = a[-dy:, :]
    return Image.fromarray(out, "RGBA")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default="", required=True,
                    help="slozka se stazenymi skupinami z PixelLabu")
    ap.add_argument("--stage", default="", help="kam odlozit vysledek k posouzeni")
    ap.add_argument("--apply", action="store_true", help="zapsat rovnou do assets/defenders")
    args = ap.parse_args(argv)

    out_dir = DEST if args.apply else (args.stage or os.path.join(PROJ, "build", "obranci_novi"))
    os.makedirs(out_dir, exist_ok=True)

    total = 0
    pending: dict = {}
    for char, jobs in PLAN.items():
        for game_set, group, n, why in jobs:
            gdir = os.path.join(args.src, group)
            if not os.path.isdir(gdir):
                # garlic sady lezi o adresar vys nez broccoli/chilli
                alt = os.path.join(args.src, char.split("_")[0] + "_anim", group)
                gdir = alt if os.path.isdir(alt) else gdir
            if not os.path.isdir(gdir):
                print(f"  ! {char}/{game_set}: chybi zdroj {group}")
                continue
            files = sorted(f for f in os.listdir(gdir) if f.endswith(".png"))
            wrote = 0
            for i, f in enumerate(files[:n], 1):
                im = settle(to_game(Image.open(os.path.join(gdir, f))))
                pending.setdefault(char, {})[
                    os.path.join(out_dir, f"{char}_{game_set}_frame_{i}.png")] = np.array(im)
                wrote += 1
            # zbyle framy stare sady by po zkraceni zustaly na disku a hra by je nacetla
            stale = []
            j = wrote + 1
            while os.path.exists(os.path.join(DEST, f"{char}_{game_set}_frame_{j}.png")):
                stale.append(f"{char}_{game_set}_frame_{j}.png")
                j += 1
            print(f"  {char}_{game_set:<11} {wrote} framu  <- {group}"
                  + (f"   (k smazani: {len(stale)})" if stale else ""))
            print(f"      {why}")
            if args.apply:
                for s in stale:
                    os.remove(os.path.join(DEST, s))
            total += wrote

    # skubnuti z uz prevedeneho spritu — az ted, aby bralo NOVOU sadu, ne starou
    import puppet_anim as PA
    for char, (from_set, n) in PUPPET_HURT.items():
        base = os.path.join(out_dir, f"{char}_{from_set}_frame_1.png")
        if base not in pending.get(char, {}):
            print(f"  ! {char}/hurt: chybi {from_set} k odvozeni")
            continue
        src = pending[char][base]
        for i, f in enumerate(PA.puppet_hit(src, n_frames=n, intensity=2)[:n], 1):
            im = settle(Image.fromarray(np.asarray(f).astype(np.uint8), "RGBA"))
            pending[char][os.path.join(out_dir, f"{char}_hurt_frame_{i}.png")] = np.array(im)
        j = n + 1
        while os.path.exists(os.path.join(DEST, f"{char}_hurt_frame_{j}.png")):
            if args.apply:
                os.remove(os.path.join(DEST, f"{char}_hurt_frame_{j}.png"))
            j += 1
        print(f"  {char}_hurt        {n} framu  <- puppet_hit({from_set})")
        print("      zdroj nema skubnuti, jen kouzla; loutka drzi hul i identitu")
        total += n

    # Zapis az tady, a to je zamer: unify_palette() potrebuje videt VSECHNY nove framy
    # postavy najednou, aby jim postavila jednu spolecnou paletu.
    written = 0
    for char, frames in pending.items():
        for path, a in unify_palette(frames, char).items():
            Image.fromarray(a.astype(np.uint8), "RGBA").save(path)
            written += 1

    print(f"\n{written} framu zapsano do {os.path.relpath(out_dir, PROJ)}"
          + (f" (pripraveno {total})" if written != total else ""))
    if not args.apply:
        print("assets/ zustaly nedotcene. Posud vysledek a pak --apply.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
