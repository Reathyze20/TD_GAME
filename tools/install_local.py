"""Instalace priser z UZ STAZENE knihovny PixelLabu, v nativnich 64 px.

    python tools/install_local.py                 # ukaze, co by udelal
    python tools/install_local.py --apply
    python tools/install_local.py --only notification,jackpot --apply

PROC TENHLE SOUBOR VUBEC EXISTUJE

install_pixellab.py stahoval postavu a na radku 115 delal tohle:

    out.append(sprite_16.halve(im, 32) if im.width != 32 else im)

Kazdy sprite, ktery PixelLab vygeneroval v 64 px, se pri instalaci zmensil na 32.
Tehdy to davalo smysl -- bunka merila 48 px obrazovky a 16 px artu, takze 32 px byly
presne dve bunky. Po prechodu na 32 px artu na bunku (tools/raster_x2.py) uz jsou dve
bunky 64 px, tedy presne to, co PixelLab dodava. To zmenseni ted uz jen zahazuje
informaci, za kterou je zaplaceno.

Kolik informace: mereno na latce, 64px original ma znamku 8.5, izolovanych pixelu
0.227 a hustotu 19 nesoucich barev na 1000 pixelu. Tyz sprite po halve() na 32: 6.7,
0.412 a 54.9. Vsechny tri miry se zhorsily dvakrat az trikrat, a nic z toho nezpusobil
model -- zpusobilo to zmenseni.

A NESTAHUJE SE ZNOVU. V build/pixellab/ lezi 39 postav vcetne animaci; sit ani kredity
nejsou potreba. Sada se hleda podle konvence td_<id>, kterou uz knihovna ma.

DVE PRAVIDLA, KTERA TENHLE SKRIPT NIKDY NEPORUSI

1. PIXELY SE NEPREPOCITAVAJI. Nektere sady chodi z PixelLabu na zvetsenem platne
   (76, 80, 84 nebo 88 px) -- typicky smrt, protoze mrtvola lezi siroko. Takovy snimek
   se ORIZNE na obalku neprusvitnych pixelu a vlozi doprostred platna, ktere je
   nasobkem 32. Kdyz se obsah vejde do 64, plati 64 (dve bunky); kdyz ne, 96 (tri).
   Zadny resize, zadna interpolace, zadny nearest -- puvodni pixely doslova.

2. NIC SE NEMAZE, DOKUD NENI NAHRADA HOTOVA. Poradi je nacist -> zpracovat ->
   zkontrolovat -> teprve pak smazat stary art a zapsat. Drivejsi verze mazala hned
   na zacatku a kdyz neco selhalo, prisera zmizela z disku uplne.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mj_to_sprite as M
import install_pixellab as I

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(PROJ, "build", "pixellab")
DEST = os.path.join(PROJ, "assets", "distractions")

import game_raster                                             # noqa: E402

CELL_ART_PX = game_raster.ART_PX   # Data.TERRAIN_ART_PX, cteno ze scripts/data.gd

## Standardni prisera ma 48 px artu. To cislo je vytvarne, ne odvozene od bunky: 64 z
## PixelLabu snese jedine zmenseni na 48 (viz COLORS_DOWNSCALE nize), takze 48 je dane
## a pocet bunek se z nej dopocita, ne naopak. Pri bunce 16 px artu jsou to tri bunky.
CREATURE_ART_PX = 48
TARGET = CREATURE_ART_PX

# PixelLab dodava 64. Cesta 64 -> 48 neni libovolny resize, je to JEDINE zmenseni,
# ktere podle mereni (111 spritu) kvalitu udrzi: NEAREST -> clean(24) -> outline_sprite
# dalo znamku 9.00, sum 0.200 a obrys +0.191, tedy nad latkou. Tataz cesta na 32 px
# spadne na 7.8 a proste halve() na 6.7. Proto se rozpocet barev bere 24, i kdyz latka
# na teto velikosti nese kolem 44 -- 24 je cislo, ktere bylo overene PRO TENHLE KROK.
COLORS_DOWNSCALE = 24

# Prahy z mj_to_sprite jsou odectene na 32px spritech ("Mer na 32 px" primo v audit()).
# Prenasobit je odhadem nestaci -- prvni pokus (thin=4, pieces=1) odmitl skoro vsechno,
# vcetne artu, ktery je zjevne v poradku. Proto zmereno na LATCE: M.audit() na 160
# nativnich 64px rotacich z build/pixellab.
#
#   metrika   min     p10    median   p90    p99
#   colors     10      -       32      47      64
#   outline    -7     6.8      59     103     160
#   pieces      1      -        1       7      19
#   thin        0      -        3      13      75
#   h          41     56       59      61      62
#
# Dve prekvapeni, kvuli kterym byl prvni pokus tak spatny:
#
#   pieces: latka ma v desetine pripadu SEDM kusu. Drzeny telefon, odlepeny odznak
#   nebo odstrikla jiskra nejsou uletly fragment, je to zamer. Prah 1 tedy netrestal
#   vadu, trestal detail -- a na 32 px prosel jen proto, ze se pri zmenseni slil.
#
#   thin: p90 je 13. Na 64 px jsou tenke segmenty (prsty, tykadla, nohy) normalni
#   kresba; na 32 px zadny takovy detail neprezije, proto tam prah 2 fungoval.
#
# Prah se sazi na tolerantni konec latky (p90 u maxim, p10 u minim): kontrola ma
# hlasit, co je neobvykle i na latce, ne vsechno bohate.
# height=48 je p01 latky, ne p10. Duvod: pohled ZEZADU je z principu o par pixelu
# nizsi nez zepredu (necni z nej oblicej ani drzeny predmet), takze prah odecteny
# z jizniho pohledu odmita severni u kazde druhe prisery. Merena skutecnost: 49, 50
# a 51 px u tri priser, ktere jsou jinak v poradku.
# Prahy skaluji s velikosti spritu: latka mereno na 64 px dala h medianu 59 (p01 48),
# thin p90 13, pieces p90 7. Co je v PIXELECH, jde krat TARGET/64; co je v jasu nebo
# v poctu kusu, zustava.
_K = TARGET / 64.0
GATES_64 = dict(colors=COLORS_DOWNSCALE + 8, outline=6, pieces=8,
                thin=int(14 * _K), height=int(48 * _K))

# Sada v knihovne -> pripona ve hre. Poradi rozhoduje: prvni nalezena vyhrava, takze
# u priser, ktere maji td_attack i td_attack_pro, se vezme to novejsi (pro).
SETS = [
    (["td_walk", "td_walking", "junk_walk"], ""),         # jde do south/north/east
    (["td_attack_pro", "td_attack", "td_atk2"], "_attack"),
    (["td_death", "junk_death"], "_death"),
]

# Smer ve jmene snimku -> pripona ve hre. Zapad hra zrcadli z vychodu sama.
DIRS = {"south": "", "north": "_north", "east": "_east"}

FRAME_RE = re.compile(r"^([a-z-]+)_frame_(\d+)\.png$")


def knihovna() -> dict:
    """Jmeno slozky -> {"id": herni id nebo "", "sety": {jmeno: [cesty]}}.

    Herni id se cte z KONVENCE JMENA SLOZKY (td_<id>__<uuid>), ne z popisu postavy:
    popisy jsou volny text v anglictine a par postav ho ma prazdny nebo uriznuty.
    """
    out = {}
    for d in sorted(glob.glob(os.path.join(LIB, "*"))):
        if not os.path.isdir(d):
            continue
        base = os.path.basename(d)
        m = re.match(r"^td_([a-z_]+?)(?:_v\d)?(?:_mj(?:_\d+)?)?(?:__[0-9a-f]+)?$", base)
        hid = m.group(1) if m else ""
        sety = {}
        for sub in sorted(os.listdir(d)):
            p = os.path.join(d, sub)
            if os.path.isdir(p):
                fs = sorted(glob.glob(os.path.join(p, "*.png")))
                if fs:
                    sety[sub] = fs
        out[base] = {"id": hid, "sety": sety}
    return out


def vyber(kandidati: list, hid: str) -> str:
    """Ze slozek se stejnym hernim id vybere tu s NEJVIC animacnimi sadami.

    Knihovna ma casto vic pokusu o tutez priseru (td_notification, _mj, _32).
    Rozhoduje pocet sad krome rotace -- verze s chuzi, utokem i smrti je vzdycky
    ta, kterou nekdo dotahl.
    """
    def skore(k):
        s = knihovna_cache[k]["sety"]
        return (sum(1 for n in s if n != "rotace"), sum(len(v) for v in s.values()))
    return max(kandidati, key=skore)


def na_platno(im: Image.Image) -> Image.Image | None:
    """Orez na obsah a vlozeni doprostred platna, ktere je nasobkem bunky.

    Vraci None, kdyz je snimek prazdny. NIKDY neprepocitava pixely -- viz hlavicka.
    """
    a = np.asarray(im.convert("RGBA"))
    m = a[..., 3] > 16
    if not m.any():
        return None
    ys, xs = np.nonzero(m)
    orez = im.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))

    # Obsah se vejde na TARGET, nebo se na nej ZMENSI. Zvetsovat platno na 72 px (tri
    # bunky) by znamenalo, ze prisera je o pulku vetsi nez ostatni jen proto, ze ji
    # PixelLab poslal na sirsim platne -- coz je typicky u smrti, kde mrtvola lezi.
    # Zmenseni jde NEAREST, bez interpolace; jemnost pak vraci clean+outline v zpracuj().
    if max(orez.width, orez.height) > TARGET:
        k = TARGET / float(max(orez.width, orez.height))
        orez = orez.resize((max(1, round(orez.width * k)),
                            max(1, round(orez.height * k))), Image.NEAREST)

    strana = TARGET
    platno = Image.new("RGBA", (strana, strana), (0, 0, 0, 0))
    # Vodorovne na stred, svisle NA PATU: prisera stoji na zemi, takze spolecna musi
    # byt spodni hrana. Centrovat i svisle znamena, ze pri chuzi poskakuje o pixely,
    # o ktere se zrovna lisi vyska pozy.
    platno.alpha_composite(orez, ((strana - orez.width) // 2, strana - orez.height))
    return platno


def nacti(fs: list) -> dict:
    """[cesty] -> {smer: [snimky serazene podle cisla]}."""
    po_smerech: dict[str, list] = {}
    for f in fs:
        m = FRAME_RE.match(os.path.basename(f))
        if not m:
            continue
        po_smerech.setdefault(m.group(1), []).append((int(m.group(2)), f))
    out = {}
    for d, items in po_smerech.items():
        ims = []
        for _n, f in sorted(items):
            im = na_platno(Image.open(f))
            if im is not None:
                ims.append(im)
        if ims:
            out[d] = ims
    return out


def zpracuj(ims, rim, gamma):
    """Tentyz retez jako install_pixellab.process, jen s rozpoctem barev pro 64 px."""
    return I.process(ims, rim, gamma, colors=COLORS_DOWNSCALE)


def brany(ims) -> list:
    # M.audit() pocita bbox z nenulovych pixelu, takze na uplne prazdnem snimku spadne
    # na xs.max() prazdneho pole. Prazdny snimek TU VZNIKNOUT MUZE: largest_piece na
    # sprite, ktery se po lift+outline rozpadl na same drobky, nevrati nic. Je to vada,
    # ne vyjimka -- proto se hlasi, misto aby shodila cely beh.
    plne = [i for i in ims if np.asarray(i.convert("RGBA"))[..., 3].max() > 128]
    if not plne:
        return ["po zpracování nezbyl žádný neprůhledný pixel"]
    vady = []
    if len(plne) != len(ims):
        vady.append(f"{len(ims) - len(plne)} snímků vyšlo prázdných")
    old = dict(M.GATES)
    try:
        M.GATES.update(GATES_64)
        return vady + I.check(plne)
    finally:
        M.GATES.clear()
        M.GATES.update(old)


def priprav(slozka: str, hid: str) -> tuple[dict, list]:
    """-> ({pripona: [snimky]}, [problemy])"""
    sety = knihovna_cache[slozka]["sety"]
    vybrane = {}
    for jmena, pripona in SETS:
        for j in jmena:
            if j in sety:
                vybrane[pripona] = nacti(sety[j])
                break

    if "" not in vybrane or "south" not in vybrane.get("", {}):
        return {}, [f"{hid}: chybí chůze na jih"]

    # Gama a barva obrysu se pocitaji JEDNOU z prvniho snimku chuze na jih -- stejne
    # jako v install_pixellab. Per-snimek by sprite pri chuzi pulzoval.
    etalon = vybrane[""]["south"][0]
    gamma, rim = I.solve(etalon)

    hotovo, problemy = {}, []
    for pripona, po_smerech in vybrane.items():
        for smer, ims in po_smerech.items():
            if pripona == "":
                if smer not in DIRS:
                    continue
                klic = DIRS[smer]
            else:
                if smer != "south":
                    continue          # utok a smrt hra kresli jen zepredu
                klic = pripona
            hotove = zpracuj(ims, rim, gamma)
            vady = brany(hotove)
            if vady:
                problemy.append(f"{hid}{klic or ' (jih)'}: " + "; ".join(vady))
            hotovo[klic] = hotove
    return hotovo, problemy


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Instalace příšer z build/pixellab v 64 px.")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--only", default="", help="čárkami oddělená herní id")
    ap.add_argument("--ignoruj-brany", action="store_true", dest="force",
                    help="nainstaluj i to, co neprošlo kontrolou")
    args = ap.parse_args(argv)

    global knihovna_cache
    knihovna_cache = knihovna()

    podle_id: dict[str, list] = {}
    for k, v in knihovna_cache.items():
        if v["id"]:
            podle_id.setdefault(v["id"], []).append(k)

    herni = {os.path.basename(p)[:-5] for p in glob.glob(os.path.join(PROJ, "data", "distractions", "*.tres"))}
    chci = {s.strip() for s in args.only.split(",") if s.strip()} or herni

    print(f"{'ZAPISUJI' if args.apply else 'ZKUŠEBNÍ BĚH'} — cíl {TARGET}×{TARGET} px "
          f"({TARGET // CELL_ART_PX} buňky)\n")

    vsechny_problemy, planovano = [], 0
    for hid in sorted(chci):
        if hid not in podle_id:
            print(f"  {hid:<20} — v knihovně není, nechávám beze změny")
            continue
        slozka = vyber(podle_id[hid], hid)
        hotovo, problemy = priprav(slozka, hid)
        if not hotovo:
            print(f"  {hid:<20} — {'; '.join(problemy)}")
            continue

        velikosti = sorted({im.width for ims in hotovo.values() for im in ims})
        popis = ", ".join(f"{k or 'jih'}:{len(v)}" for k, v in sorted(hotovo.items()))
        znacka = "!" if problemy else " "
        print(f" {znacka}{hid:<20} {popis}   [{'/'.join(str(v) for v in velikosti)} px]")
        for p in problemy:
            print(f"      brána: {p}")
        vsechny_problemy += problemy
        planovano += sum(len(v) for v in hotovo.values())

        if args.apply and (not problemy or args.force):
            smazano = I.cleanup(hid)
            for pripona, ims in hotovo.items():
                for i, im in enumerate(ims, 1):
                    im.save(os.path.join(DEST, f"{hid}{pripona}_frame_{i}.png"))
            print(f"      smazáno {smazano}, zapsáno {sum(len(v) for v in hotovo.values())}")

    print(f"\n  snímků celkem: {planovano}")
    if vsechny_problemy:
        print(f"  neprošlo branami: {len(vsechny_problemy)} sad"
              + ("  (zapsáno stejně, --ignoruj-brany)" if args.force else
                 "  (NEZAPSÁNO — projdi je, nebo --ignoruj-brany)"))
    if not args.apply:
        print("\nNic se nezapsalo. Spusť s --apply.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
