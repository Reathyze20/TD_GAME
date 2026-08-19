# Kontrola a oprava animaci OBRANCU (assets/defenders).
#
#   python tools/defender_anim_fix.py                 # jen zmer a vypis, nic nezapisuj
#   python tools/defender_anim_fix.py --apply         # oprav
#   python tools/defender_anim_fix.py --only garlic_mage
#
# PROC TENHLE SOUBOR EXISTUJE
#
# addons/td_anim_lab a tools/anim_autofix.gd umi presne tohle, ale ctou JEN
# assets/distractions/. Obranci Nutrition Guildy tak od zacatku nemeli zadnou kontrolu —
# a taky to na nich bylo videt. Rozsirit dock nestacilo: dock zapisuje do
# data/anim_tuning.tres a DefenderUnit zadny AnimTuning necte, takze by se posun nikde
# neprojevil. U obrancu se proto zarovnava PRIMO DO PNG.
#
# CO SE KONTROLUJE (a proc prave tohle)
#
# 1. LINKA ZEME. defender_unit.gd kresli frame vystredeny na uzel
#    (draw_texture_rect(tex, Rect2(-size/2, size))), takze o tom, kde ma postava nohy,
#    rozhoduje vyhradne obsah platna. Kdyz ma idle nohy na y=44 a chuze na y=47, postava
#    pri rozejiti poskoci o 3 px artu = 6 px na obrazovce.
#
#    Referencni linka je 47, ne "median idle". Neni to libovolna volba: vsech 329 framu
#    nepratel ma median spodni hrany presne 47, a obranci s nimi stoji na stejne podlaze.
#    Srovnat obrance sam na sebe by odstranilo poskok, ale nechalo by je viset 2 px nad
#    priserami, se kterymi se melee bijou.
#
# 2. SMRT SE ZAROVNAVA PODLE PRVNIHO FRAMU, ne podle medianu. Death cyklus se ZAMERNE
#    propada k zemi — median by tenhle pad zprumeroval a cely ho posunul nahoru, cimz by
#    se pad z animace odecetl. Stejny duvod, jaky ma anim_autofix.gd pro to, ze uvnitr
#    cyklu nesrovnava nic.
#
# 3. POSUN JE NA CELOU SADU, NIKDY NA JEDNOTLIVY FRAME. Houpani uvnitr cyklu je zamer
#    (chuze ma houpat); srovnat framy mezi sebou znamena tu chuzi smazat.
#
# 4. ZAPECENA ZEM. Siroky pas u spodni hrany, sirsi nez telo — vygenerovany kus travy
#    nebo stinu pod nohama. defender_unit.gd si kresli vlastni kontaktni stin, takze
#    zapecena zem se s nim scita a postava pak stoji ve dvou stinech naraz.
#
# CO SE ZAMERNE NEOPRAVUJE
#
# Rozdilny DESIGN mezi sadami (jina postava v attack nez v idle), chybejici rekvizita
# (mag bez hole) ani vadny frame jako celek. To nejsou posuny pixelu, to je jina kresba —
# musi se pregenerovat, a rozhodnout, ktera verze je ta spravna, je na cloveku. Skript
# je vypise jako NALEZ a tim to konci.
import argparse
import os
import re
import sys
from collections import defaultdict

import numpy as np
from PIL import Image

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(PROJ, "assets", "defenders")

FRAME_RE = re.compile(r"^(.+?)_(idle|walk_south|walk_north|walk_east|attack|hurt|death)_frame_(\d+)\.png$")

## Poradi sad. Musi sedet s DefenderUnit._ANIM_SETS.
SETS = ["idle", "walk_south", "walk_north", "walk_east", "attack", "hurt", "death"]

## Linka zeme, na ktere stoji nepratele (median spodni hrany pres vsech 329 framu
## assets/distractions). Obranci maji stat na te same.
TARGET_BASE = 47


def load(path):
    return np.array(Image.open(path).convert("RGBA"))


def bbox(a):
    ys, xs = np.nonzero(a[:, :, 3] > 0)
    if len(ys) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def scan():
    """{postava: {sada: [(cesta, pole), ...]}} serazene podle cisla framu."""
    out = defaultdict(lambda: defaultdict(list))
    for f in sorted(os.listdir(ART)):
        m = FRAME_RE.match(f)
        if not m:
            continue
        out[m.group(1)][m.group(2)].append((int(m.group(3)), os.path.join(ART, f)))
    for char in out:
        for s in out[char]:
            out[char][s].sort()
    return out


# ---------------------------------------------------------------- 1. linka zeme

def ground_shift(frames):
    """O kolik posunout celou sadu, aby stala na TARGET_BASE. Kladne = dolu.

    Vraci (posun, duvod_orezu). Posun se VZDY zkrati tak, aby zadnemu framu sady
    nevypadl pixel z platna — radeji nedokonale zarovnani nez ustrizena hlava.
    """
    boxes = [bbox(a) for _, a in frames]
    boxes = [b for b in boxes if b is not None]
    if not boxes:
        return 0, ""
    bottoms = [b[3] for b in boxes]
    tops = [b[1] for b in boxes]
    want = TARGET_BASE - int(np.median(bottoms))
    room_down = 47 - max(bottoms)     # kolik jeste muzu dolu, nez neco vypadne
    room_up = min(tops)               # kolik nahoru
    shift = max(-room_up, min(want, room_down))
    return shift, ("" if shift == want else f"orez {want:+d}->{shift:+d}")


def death_shift(frames):
    """Smrt podle PRVNIHO framu — pad k zemi je obsah animace, ne chyba zarovnani."""
    b = bbox(frames[0][1])
    if b is None:
        return 0, ""
    want = TARGET_BASE - b[3]
    boxes = [bb for bb in (bbox(a) for _, a in frames) if bb is not None]
    room_down = 47 - max(bb[3] for bb in boxes)
    room_up = min(bb[1] for bb in boxes)
    shift = max(-room_up, min(want, room_down))
    return shift, ("" if shift == want else f"orez {want:+d}->{shift:+d}")


def shift_image(a, dy):
    if dy == 0:
        return a
    out = np.zeros_like(a)
    if dy > 0:
        out[dy:, :] = a[:-dy, :]
    else:
        out[:dy, :] = a[-dy:, :]
    return out


# ---------------------------------------------------------------- 2. zapecena zem

def baked_ground(a):
    """Maska sirokeho pasu u spodni hrany, ktery je vyrazne sirsi nez telo nad nim.

    Prah 1.7x neni odhad: nejsirsi legitimni "rozkroceni" v cele sade obrancu je 1.4x
    (chilli_berserker_walk_south), zatimco vygenerovany drn u broccoli_knight_hurt vysel
    1.8x. Mezi tim je cista mezera, tak v ni prah lezi.
    """
    al = a[:, :, 3] > 0
    ys, _ = np.nonzero(al)
    if len(ys) == 0:
        return None
    y1 = int(ys.max())
    body = np.median([al[y].sum() for y in range(max(0, y1 - 20), max(1, y1 - 6))])
    if body <= 0:
        return None
    mask = np.zeros_like(al)
    hit = False
    for y in range(max(0, y1 - 4), y1 + 1):
        if al[y].sum() > body * 1.7 and al[y].sum() >= 12:
            mask[y] = al[y]
            hit = True
    if not hit:
        return None
    # Nohy z pasu vyriznout zpatky — maze se jen to, co u nohou precniva. Sloupce, ve
    # kterych telo pokracuje shora dolu, jsou noha, ne drn.
    band_top = max(0, y1 - 4)
    legs = al[max(0, band_top - 3):band_top].any(axis=0)
    mask[:, legs] = False
    return mask if mask.any() else None


# ---------------------------------------------------------------- 3. ujety jas rotaci

## Vedome, NE automaticky. Rozdil jasu mezi pohledy muze byt anatomie NEBO vada
## generatoru a rozeznat je od sebe skript neumi:
##
##   avocado_monk  walk_north -48 %  = SPRAVNE. Avokado ma svetlou duzinu vepredu a
##                                     tmavou slupku vzadu, zada proste jsou tmavsi.
##   garlic_mage   walk_north +20 %  = VADA. Cesnek je ze vsech stran stejne bledy,
##                                     takze pro svetlejsi zada neni duvod. Je to drift
##                                     rotaci popsany v docs/PIXELLAB.md.
##
## Proto se spousti jen na vyzadanou postavu: `--jas garlic_mage`.
##
## Korekce je jedno k na CELOU SADU, ne na frame. Per-frame k (jak to dela
## sprite_16.match_to_reference) srovna kazdy frame zvlast vuci referenci, cimz se
## rozdily UVNITR cyklu take srovnaji — a mirne blikani chuze, ktere bylo zamerem, zmizi.
BRIGHT_TOL = 0.10


def body_level(a):
    """Median 30 % nejsvetlejsich pixelu. Nejvyssi tony nesou identitu materialu
    (bledá cibule), zatimco prumer pres vsechno tahnou dolu boty, stiny a hul."""
    al = a[:, :, 3] > 0
    lum = a[:, :, :3][al].astype(float).mean(axis=1)
    if len(lum) == 0:
        return None
    return float(np.median(lum[lum >= np.percentile(lum, 70)]))


def rescale(a, k):
    out = a.copy()
    al = a[:, :, 3] > 0
    out[:, :, :3][al] = np.clip(a[:, :, :3][al].astype(float) * k, 0, 255).astype(np.uint8)
    return out


# ---------------------------------------------------------------- nalezy k pregenerovani

def find_reports(chars):
    """Co skript opravit NEUMI.

    Hlasi se JEN pixely mimo paletu postavy. Pokus merit i "je v attack nakreslena jina
    postava nez v idle" tady byl a letel ven: rozdil mezi bokorysem a cel(n)im pohledem
    je vetsi nez rozdil mezi dvema generacemi teze postavy, takze prah, ktery chytil
    broccoli_knight/attack, chytil zaroven kazdy legitimni bokorys — a prah, ktery
    bokorysy pustil, uz attack nenasel. Neni to mereni, je to oko; od toho je kontaktni
    list, ne tenhle vypis. Falesne klidny check je horsi nez zadny.
    """
    out = []
    for char, sets in sorted(chars.items()):
        for s in SETS:
            if s not in sets:
                continue
            for i, a in sets[s]:
                bad = odd_hue(a)
                if bad > 8:
                    out.append((char, f"{s} frame {i}", f"{bad} px mimo paletu postavy"))
    return out


def odd_hue(a):
    """Pocet syte ruzovych/magentovych pixelu — v zelenine se nevyskytuji."""
    al = a[:, :, 3] > 0
    rgb = a[:, :, :3][al].astype(float) / 255.0
    if len(rgb) == 0:
        return 0
    mx = rgb.max(axis=1)
    d = mx - rgb.min(axis=1)
    sat = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0)
    r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
    dd = np.where(d == 0, 1, d)
    h = np.select([d <= 1e-6, mx == r, mx == g, mx == b],
                  [0, ((g - b) / dd) % 6, ((b - r) / dd) + 2, ((r - g) / dd) + 4]) * 60
    return int(((h >= 290) & (h <= 350) & (sat > 0.5) & (mx > 0.4)).sum())


# ---------------------------------------------------------------- beh

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="zapsat (jinak jen vypis)")
    ap.add_argument("--only", default="", help="jen jedna postava")
    ap.add_argument("--jas", default="", metavar="POSTAVA",
                    help="srovnat jas rotaci na idle — jen u postavy, kde je rozdil "
                         "vada a ne anatomie (viz komentar u BRIGHT_TOL)")
    args = ap.parse_args()

    chars = scan()
    if args.only:
        chars = {k: v for k, v in chars.items() if args.only in k}
    if not chars:
        print("Zadny art obrancu k kontrole.")
        return 1

    # nacti pole
    loaded = {}
    for char, sets in chars.items():
        loaded[char] = {s: [(i, load(p)) for i, p in fr] for s, fr in sets.items()}

    writes = {}   # cesta -> pole
    print(f"LINKA ZEME (cil y={TARGET_BASE}, stejna jako u nepratel)")
    for char in sorted(loaded):
        moved = []
        for s in SETS:
            if s not in loaded[char]:
                continue
            fr = loaded[char][s]
            dy, note = (death_shift(fr) if s == "death" else ground_shift(fr))
            if dy == 0:
                continue
            moved.append(f"{s} {dy:+d}{(' ' + note) if note else ''}")
            for k, (i, a) in enumerate(fr):
                path = dict(chars[char][s])[i]
                writes[path] = shift_image(a, dy)
                loaded[char][s][k] = (i, writes[path])
        print(f"  {char:<20} {', '.join(moved) if moved else 'uz sedi'}")

    print("\nZAPECENA ZEM POD NOHAMA")
    hits = 0
    for char in sorted(loaded):
        for s in SETS:
            for k, (i, a) in enumerate(loaded[char].get(s, [])):
                m = baked_ground(a)
                if m is None:
                    continue
                b = a.copy()
                b[m] = 0
                writes[dict(chars[char][s])[i]] = b
                loaded[char][s][k] = (i, b)
                print(f"  {char}_{s}_frame_{i}: smazano {int(m.sum())} px drnu")
                hits += 1
    if not hits:
        print("  zadna")

    if args.jas:
        print(f"\nJAS ROTACI -> idle ({args.jas})")
        for char in sorted(loaded):
            if args.jas not in char:
                continue
            ref = np.mean([body_level(a) for _, a in loaded[char]["idle"]])
            for s in SETS:
                if s == "idle" or s not in loaded[char]:
                    continue
                fr = loaded[char][s]
                cur = np.mean([body_level(a) for _, a in fr])
                k = ref / cur
                if abs(k - 1.0) <= BRIGHT_TOL:
                    print(f"  {s:<11} {(k - 1) * 100:+5.1f} %  v toleranci, nechavam")
                    continue
                for idx, (i, a) in enumerate(fr):
                    b = rescale(a, k)
                    writes[dict(chars[char][s])[i]] = b
                    loaded[char][s][idx] = (i, b)
                print(f"  {s:<11} {(k - 1) * 100:+5.1f} %  srovnano ({len(fr)} framu)")

    reports = find_reports(loaded)
    print("\nNALEZY, KTERE SKRIPT NEOPRAVI (nutne pregenerovat)")
    if reports:
        for char, where, why in reports:
            print(f"  {char:<20} {where:<18} {why}")
    else:
        print("  zadne")

    print(f"\n{len(writes)} souboru ke zmene.")
    if not args.apply:
        print("Nic se nezapsalo. Spust s --apply.")
        return 0
    for path, a in writes.items():
        Image.fromarray(a, "RGBA").save(path)
    print(f"Zapsano {len(writes)} PNG.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
