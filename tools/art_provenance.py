# Odkud pochazi art ve hre a jak moc se od zdroje lisi.
#
# PROC
#
# Boss social_media_binge vypada ve hre jinak nez tataz postava v PixelLabu. Otazka
# "poskodil to nas import, nebo je to jen starsi generace?" se neda zodpovedet od stolu —
# a je to dulezita otazka, protoze v prvnim pripade je vadna PIPELINE (a mohla poskodit
# i zbytek), kdezto ve druhem staci stahnout novejsi verzi.
#
# Tenhle nastroj hleda ke kazdemu spritu ve hre jeho nejblizsi originalni predlohu mezi
# vsim, co je stazene z PixelLabu (tools/pixellab.py pull-all), a rekne, jak dobre sedi.
#
# JAK SE TO POCITA
#
# Naivni porovnani "kazdy s kazdym na kazdem posunu" je 700 spritu x 5000 originalu x
# tisice posunu. Proto dve kola:
#
#   1. SITO. Kazdy obrazek se orizne na svuj obsah a zmensi na 16x16. Tim se zbavi
#      posunu i rozdilu platna (PixelLab dava animace na 88x88, hra je ma 64x64), takze
#      se daji porovnat hrubou silou v jedne matici. Vezme se nejlepsich N kandidatu.
#   2. PRESNE MERENI. Jen na tech N se hleda skutecny posun a spocita, jaky PODIL
#      neprusvitnych pixelu spritu predloha doopravdy vysvetli.
#
# CO TO CISLO ZNAMENA — A CO NEZNAMENA
#
# Vysledek je "kolik procent neprusvitnych pixelu spritu predloha vysvetli". Svadi to
# cist jako pravdepodobnost, ze jde o tyz art. NENI TO ONO a stalo to uz tri chybne
# zavery, takze tady jsou namerena cisla misto dojmu.
#
# Kalibrace (40 originalu prevedenych VLASTNIMI cestami projektu — NEAREST, LANCZOS,
# median-blok, median+kvantizace palety — proti 190 nahodnym cizim dvojicim, tol 56):
#
#     pravdive dvojice    min 45 %   p10 58 %   median 69 %   p90 86 %
#     cizi dvojice        p50 19 %   p99 50 %   max 55 %
#
# NEJHORSI PRAVDIVA (45 %) LEZI POD NEJLEPSI CIZI (55 %). Pasma se prekryvaji pri
# kazde vyzkousene toleranci (24, 40, 56, 72). Zadny prah je tedy neoddeli a nastroj
# NEMUZE rozhodovat sam. Umi radit — nejblizsi predlohu najde spolehlive (sito ji dostane
# do sestice v 60 z 60 pripadu) — ale verdikt "je to tyz art" musi dat oko.
#
# Proto se vysledek deli na tri pasma a prostredni se PRIZNAVA jako nevedomost:
#
#     >= SURE_SAME    cizi dvojice sem nikdy nedosahla       -> tyz art
#     <= SURE_DIFF    pravdiva dvojice sem nikdy neklesla    -> jiny art
#     mezi tim        prekryv, musi se na to podivat clovek
#
#   python tools/art_provenance.py
#   python tools/art_provenance.py --only social_media --sheet build/puvod.png
import argparse
import os
import re

import numpy as np
from PIL import Image

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_ROOT = os.path.join(PROJ, "build", "pixellab")
GAME_DIRS = ["assets/distractions", "assets/defenders", "assets/towers", "assets/decor"]

ALPHA_MIN = 32
THUMB = 16
SHORTLIST = 6
# Tolerance barvy na kanal. Zmensovani spritu meni barvy i kdyz je art tentyz:
# median-blok i LANCZOS michaji sousedy, takze rozdil 30-60 je bezny u PRAVDIVE
# dvojice. Prisna tolerance 24 z prvni verze proto zabijela legitimni shody.
COLOR_TOL = 56
# Meze obou pasem. Nejsou zvolene, jsou odectene z kalibrace v hlavicce: cizi dvojice
# nedosahla vys nez 55 %, pravdiva neklesla niz nez 45 %.
SURE_SAME = 0.70
SURE_DIFF = 0.35
FRAME_RE = re.compile(r"^(.*)_frame_(\d+)$")


def load(p):
    return np.array(Image.open(p).convert("RGBA"))


def content_box(a):
    m = a[..., 3] > ALPHA_MIN
    if not m.any():
        return None
    ys, xs = np.where(m)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def descriptor(a):
    """Orez na obsah -> 16x16 RGB, alfa jako ctvrty kanal. Nezavisle na platne i posunu."""
    b = content_box(a)
    if b is None:
        return None
    im = Image.fromarray(a, "RGBA").crop(b).resize((THUMB, THUMB), Image.BILINEAR)
    d = np.asarray(im, dtype=np.float32) / 255.0
    # Alfa vahuje barvu: pruhledne misto nema barvu, kterou by melo smysl porovnavat.
    d[..., :3] *= d[..., 3:4]
    return d.reshape(-1)


def index_sources(root):
    paths, descs = [], []
    for dirpath, _, files in os.walk(root):
        for f in sorted(files):
            if not f.lower().endswith(".png"):
                continue
            p = os.path.join(dirpath, f)
            try:
                a = load(p)
            except Exception:                                     # noqa: BLE001
                continue
            if a.shape[0] > 256 or a.shape[1] > 256:
                continue
            d = descriptor(a)
            if d is None:
                continue
            paths.append(p)
            descs.append(d)
    return paths, (np.stack(descs) if descs else np.zeros((0, THUMB * THUMB * 4), np.float32))


# Meritka, ktera v tomhle projektu doopravdy nastavaji: 64->32 je pulka, 88->64 a 96->64
# jsou dve tretiny, 24->16 taky. Zbytek je tam pro jistotu.
CAND_SCALES = (0.25, 1.0 / 3.0, 0.5, 2.0 / 3.0, 0.75, 1.0, 4.0 / 3.0, 1.5, 2.0, 3.0, 4.0)


def scale_candidates(src, tgt):
    """Meritka, ktera stoji za vyzkouseni. Vraci serazeny seznam.

    PROC SEZNAM A NE JEDNO CISLO. Prvni verze pocitala jeden pomer z ohraniceni obsahu.
    Znelo to presne a bylo to spatne: obsah siroky 57 px se pri puleni orizne na 29, ne
    na 28,5, takze vyjde k = 0.5085 misto 0.5. Predloha se pak zvetsi na 45x45 misto
    44x44, mrizka pixelu se rozejde o jeden pixel a shoda spadne ze 100 % na 60 %.
    Zmereno na 60 dvojicich: prokazatelne odvozeny sprite mel median 53 % a prahem 70 %
    proslo devet z sedesati. Osmdesat pet procent spravne vyrobeneho artu by nastroj
    oznacil za cizi.

    Odhad z ohraniceni je proto jen jeden kandidat vedle cistych zlomku. Bere se
    NEJLEPSI vysledek — spravne meritko pozna vysledek sam, hadat ho dopredu netreba.
    """
    out = set()
    sb, tb = content_box(src), content_box(tgt)
    if sb is not None and tb is not None:
        sw, sh = sb[2] - sb[0], sb[3] - sb[1]
        tw, th = tb[2] - tb[0], tb[3] - tb[1]
        if sw > 0 and sh > 0:
            out.add(min(tw / float(sw), th / float(sh)))
    if src.shape[1] > 0:
        out.add(tgt.shape[1] / float(src.shape[1]))       # pomer platen
    for k in list(out):
        for c in CAND_SCALES:
            if abs(c - k) < 0.15:
                out.add(c)
    return sorted(k for k in out if 0.1 <= k <= 8.0)


def rescaled(src, k):
    """Predloha v danem meritku. NEAREST, ne BILINEAR: cil je pixel art a interpolace
    by vyrobila mezibarvy, ktere by porovnani barev jen sumely."""
    if abs(k - 1.0) < 1e-6:
        return src
    nh = max(4, int(round(src.shape[0] * k)))
    nw = max(4, int(round(src.shape[1] * k)))
    return np.array(Image.fromarray(src, "RGBA").resize((nw, nh), Image.NEAREST))


def overlap(src, tgt, tol=None):
    """Nejlepsi shoda pres vsechna rozumna meritka -> (podil, posun, meritko)."""
    best = (0.0, (0, 0), 1.0)
    for k in scale_candidates(src, tgt):
        sc, off = _overlap_fixed(rescaled(src, k), tgt, tol)
        if sc > best[0]:
            best = (sc, off, k)
    return best


def _overlap_fixed(src, tgt, tol=None):
    """Nejlepsi posun predlohy pres cil -> (podil vysvetlenych pixelu cile, posun).

    Pocita se vuci NEPRUSVITNYM pixelum CILE: zajima nas, kolik ze spritu ve hre
    predloha vysvetli, ne naopak. Predloha byva na vetsim platne a mit ji "nevyuzitou"
    je v poradku — chybejici kus cile uz v poradku neni.
    """
    tol = COLOR_TOL if tol is None else tol
    sm = src[..., 3] > ALPHA_MIN
    tm = tgt[..., 3] > ALPHA_MIN
    need = int(tm.sum())
    if need == 0:
        return 0.0, (0, 0)
    sh, sw = src.shape[:2]
    th, tw = tgt.shape[:2]
    # Zarovnat tezistem a hledat jen v malem okoli — hrube zarovnani uz udelalo sito.
    sy, sx = np.nonzero(sm)
    ty, tx = np.nonzero(tm)
    cy = int(round(ty.mean() - sy.mean()))
    cx = int(round(tx.mean() - sx.mean()))
    best = (0.0, (0, 0))
    for dy in range(cy - 6, cy + 7):
        for dx in range(cx - 6, cx + 7):
            ys0, ys1 = max(0, -dy), min(sh, th - dy)
            xs0, xs1 = max(0, -dx), min(sw, tw - dx)
            if ys1 <= ys0 or xs1 <= xs0:
                continue
            s = src[ys0:ys1, xs0:xs1]
            t = tgt[ys0 + dy:ys1 + dy, xs0 + dx:xs1 + dx]
            both = (s[..., 3] > ALPHA_MIN) & (t[..., 3] > ALPHA_MIN)
            if not both.any():
                continue
            diff = np.abs(s[..., :3].astype(np.int16) - t[..., :3].astype(np.int16)).max(-1)
            ok = int((both & (diff <= tol)).sum())
            sc = ok / need
            if sc > best[0]:
                best = (sc, (dy, dx))
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="jen cesty obsahující tenhle řetězec")
    ap.add_argument("--sheet", help="vizuální list nejhorších shod")
    ap.add_argument("--limit", type=int, default=0, help="jen prvních N spritů (rychlý test)")
    args = ap.parse_args()

    if not os.path.isdir(SRC_ROOT):
        raise SystemExit(f"chybí {os.path.relpath(SRC_ROOT, PROJ)} — spusť "
                         "`python tools/pixellab.py pull-all`")
    print("indexuji originály…", flush=True)
    spaths, sdesc = index_sources(SRC_ROOT)
    print(f"  {len(spaths)} originálů")
    if not spaths:
        raise SystemExit("žádné originály")

    targets = []
    for d in GAME_DIRS:
        root = os.path.join(PROJ, d)
        if not os.path.isdir(root):
            continue
        for f in sorted(os.listdir(root)):
            if not f.lower().endswith(".png"):
                continue
            p = os.path.join(root, f)
            if args.only and args.only not in f:
                continue
            targets.append(p)
    if args.limit:
        targets = targets[:args.limit]
    print(f"  {len(targets)} spritů ve hře\n")

    rows = []
    for i, p in enumerate(targets):
        a = load(p)
        if a.shape[0] > 256:
            continue
        d = descriptor(a)
        if d is None:
            continue
        dist = np.linalg.norm(sdesc - d[None, :], axis=1)
        cand = np.argsort(dist)[:SHORTLIST]
        best = (0.0, None, None, 1.0)
        for j in cand:
            sc, off, k = overlap(load(spaths[j]), a)
            if sc > best[0]:
                best = (sc, spaths[j], off, k)
        rows.append({"game": p, "score": best[0], "src": best[1], "off": best[2],
                     "scale": best[3]})
        if (i + 1) % 50 == 0:
            print(f"    {i + 1}/{len(targets)}", flush=True)

    rows.sort(key=lambda r: r["score"])
    same = sum(1 for r in rows if r["score"] >= SURE_SAME)
    diff = sum(1 for r in rows if r["score"] <= SURE_DIFF)
    grey = len(rows) - same - diff
    print(f"\n{len(rows)} spritů:  {same} týž art (≥{SURE_SAME:.0%}),  "
          f"{diff} jiný art (≤{SURE_DIFF:.0%}),  {grey} NEVÍME — na ty se musí "
          f"podívat oko\n")

    from collections import defaultdict
    by = defaultdict(list)
    for r in rows:
        stem = os.path.splitext(os.path.basename(r["game"]))[0]
        m = FRAME_RE.match(stem)
        by[m.group(1) if m else stem].append(r)
    print(f"{'sada':<40}{'shoda medián':>14}{'nejhorší':>10}   nejbližší originál")
    for g in sorted(by, key=lambda g: np.median([r['score'] for r in by[g]])):
        v = by[g]
        med = float(np.median([r["score"] for r in v]))
        wor = min(r["score"] for r in v)
        src = os.path.relpath(min(v, key=lambda r: r["score"])["src"] or "", PROJ) \
            if v[0]["src"] else "-"
        mark = ("" if med >= SURE_SAME else
                "  jiný art" if med <= SURE_DIFF else "  ? nevíme")
        print(f"  {g:<38}{med:>12.0%}{wor:>10.0%}   "
              f"{os.path.basename(os.path.dirname(src))}{mark}")


if __name__ == "__main__":
    main()
