# Co je stylova bible tehle hry — merene, ne vymyslene.
#
# art_check.py je linter: bere pravidla jako dana a hleda soubory, ktere je porusuji.
# Tenhle nastroj dela opak. Nema zadna pravidla a z hotoveho artu odvozuje, jaka
# pravidla uz de facto plati. Teprve z toho se da napsat bible, ktera nebude
# zboznym pranim rozchazejicim se s tisicem souboru.
#
# Meri sest os, ktere stylovou bibli tvori:
#
#   1 ROZLISENI   Platno je lehka otazka (precte se z hlavicky). Tezka je LOGICKY PIXEL:
#                 32x32 PNG, kde je kazdy pixel zdvojeny, je ve skutecnosti 16x16 art
#                 roztazeny na dvojnasobek. Oko to pozna okamzite, hlavicka souboru ne.
#   2 PALETA      Barvy na sprite a barvy celeho projektu. Prekryv mezi tvory rika,
#                 jestli existuje spolecny svet, nebo jestli si kazdy tvor privezl vlastni.
#   3 OBRYS       Jsou okrajove pixely tmavsi nez vnitrek? O kolik? Mit obrys nekde
#                 a jinde ne je horsi nez nemit ho nikde.
#   4 STINOVANI   Kolik tonu a jestli se s jasem posouva ODSTIN. Ztmavovani do cerne
#                 vs. hue shift je nejvetsi rozdil mezi "amatersky" a "zivy".
#   5 ANIMACE     Pocty snimku podle akce a naladene FPS. Nekonzistentni tempo mezi
#                 tvory je videt driv nez nekonzistentni kresba.
#   6 PROPORCE    Vyska subjektu v logickych pixelech a pomer stran. Rika, jestli
#                 rodina prisery drzi jedno meritko.
#
# Vsechna cisla se meri jen na NEPRUSVITNYCH pixelech (alpha > 32). Pozadi by jinak
# taahlo kazdou statistiku k sobe.
#
# Spusteni:  python tools/style_audit.py            cely shipped art
#            python tools/style_audit.py --only distractions
#            python tools/style_audit.py --html      + build/style_audit.html
import argparse
import os
import re
import sys
from collections import Counter, defaultdict

import numpy as np
from PIL import Image

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from sprite_cleanup import build_palette, to_oklab   # noqa: E402

# Jen to, co jde do hry. assets/src/ je zdrojovy material ve vyssim rozliseni a
# michat ho do statistik by rozmazalo prave to, co chceme zmerit.
SHIPPED = {
    "distractions": "assets/distractions",
    "defenders": "assets/defenders",
    "towers": "assets/towers",
    "decor": "assets/decor",
    "terrain": "assets/terrain",
}

ALPHA_MIN = 32          # pod tim uz je pixel prakticky neviditelny
FRAME_RE = re.compile(r"^(?P<stem>.+?)_frame_(?P<n>\d+)$")

# Akce, jejichz delku ma smysl srovnavat napric tvory. Poradi = poradi ve vypisu.
ACTIONS = ["chuze (jih)", "_north", "_east", "_west", "_attack", "_death"]


# --------------------------------------------------------------------- nacteni


def load(path):
    return np.array(Image.open(path).convert("RGBA"))


def opaque(a):
    return a[..., 3] > ALPHA_MIN


def each_png(roots):
    for name, rel in sorted(roots.items()):
        base = os.path.join(PROJ, rel)
        for dirpath, _, files in os.walk(base):
            for f in sorted(files):
                if f.lower().endswith(".png"):
                    yield name, os.path.join(dirpath, f)


# ------------------------------------------------------------------ 1 rozliseni


def logical_pixel(a):
    """Kolikanasobne je zvetseny logicky pixel.

    Zkousi mrizku n x n a pta se, jestli jsou uvnitr bloku vsechny pixely stejne.
    Bere NEJVETSI n, ktere jeste sedi — u ×4 artu sedi i ×2 a ×1, ale pravda je 4.

    Meri se na RGBA vcetne alfy zamerne: prava hranice spritu je casto prave tam,
    kde konci alfa, a ta zdvojeni prozradi i na jednobarevne plose.
    """
    h, w = a.shape[:2]
    best = 1
    for n in range(2, 9):
        if h % n or w % n:
            continue
        b = a.reshape(h // n, n, w // n, n, 4)
        # blok je jednolity, kdyz se kazdy jeho pixel rovna levemu hornimu
        if np.all(b == b[:, :1, :, :1, :]):
            best = n
    return best


# --------------------------------------------------------------------- 3 obrys


def outline_strength(a):
    """O kolik jsou okrajove pixely tmavsi nez vnitrek, v Oklab L (0..1).

    Okraj = neprusvitny pixel, ktery ma aspon jednoho pruhledneho souseda ve 4-okoli.
    Vraci None, kdyz je sprite prilis maly na to, aby okraj a vnitrek davaly smysl.

    Kladne cislo = tmavy obrys. Kolem nuly = zadny obrys. Zaporne = svetly lem,
    coz obvykle znamena, ze pri zmensovani zbyl polopruhledny bordel.
    """
    m = opaque(a)
    if m.sum() < 24:
        return None
    pad = np.pad(m, 1, constant_values=False)
    nb = (pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    edge = m & ~nb
    inner = m & nb
    if edge.sum() < 4 or inner.sum() < 4:
        return None
    lab = to_oklab(a[..., :3].reshape(-1, 3).astype(np.int64)).reshape(a.shape[0], a.shape[1], 3)
    return float(lab[..., 0][inner].mean() - lab[..., 0][edge].mean())


# ----------------------------------------------------------------- 4 stinovani


def hue_shift(a, k=8):
    """Posouva se s jasem odstin? Vraci rozdil odstinu (stupne) mezi tmavou a
    svetlou tretinou palety spritu.

    Pod ~8° je to ztmavovani do cerne. Nad ~15° uz je to hue shift — barva se
    do stinu odklani, coz je presne ta technika, kterou clanek jmenuje jako #1.

    Odstin se bere jako uhel v rovine (a, b) Oklabu; prumeruje se vektorove, aby
    se odstiny kolem 0°/360° nesecetly na nesmysl.
    """
    m = opaque(a)
    px = a[..., :3][m]
    if len(px) < 32:
        return None
    pool = Counter(map(tuple, px))
    if len(pool) < 4:
        return None
    pal = build_palette(pool, min(k, len(pool)), 0.5)
    lab = to_oklab(pal)
    chroma = np.hypot(lab[:, 1], lab[:, 2])
    # Sedou a skoro sedou vyhodit — odstin u nich neznamena nic a jen sumi.
    keep = chroma > 0.02
    if keep.sum() < 4:
        return None
    lab, chroma = lab[keep], chroma[keep]
    order = np.argsort(lab[:, 0])
    third = max(1, len(order) // 3)
    dark, light = order[:third], order[-third:]

    def mean_hue(idx):
        # vektorovy prumer vazeny sytosti: bledsi barvy maji mensi vliv
        v = np.array([(lab[idx, 1] * chroma[idx]).sum(), (lab[idx, 2] * chroma[idx]).sum()])
        return np.degrees(np.arctan2(v[1], v[0]))

    d = abs(mean_hue(dark) - mean_hue(light)) % 360
    return float(min(d, 360 - d))


# ---------------------------------------------------------------- 6 proporce


def subject_box(a):
    """Ohraniceni neprusvitneho obsahu -> (sirka, vyska) v pixelech platna."""
    m = opaque(a)
    if not m.any():
        return None
    ys, xs = np.where(m)
    return int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)


# ------------------------------------------------------------------ 5 animace


def load_tuning():
    """FPS z data/anim_tuning.tres. Cte se textove — nacitat kvuli tomu Godot
    by bylo deset vterin startu za tri cisla."""
    p = os.path.join(PROJ, "data", "anim_tuning.tres")
    if not os.path.isfile(p):
        return {}
    txt = open(p, encoding="utf-8", errors="replace").read()
    m = re.search(r"fps\s*=\s*\{(.*?)\n\}", txt, re.S)
    if not m:
        return {}
    out = {}
    for key, val in re.findall(r'"([^"]+)"\s*:\s*([0-9.]+)', m.group(1)):
        out[key] = float(val)
    return out


# ------------------------------------------------------------------- sber dat


def audit(roots):
    rows = []
    for group, path in each_png(roots):
        try:
            a = load(path)
        except Exception as e:                                  # noqa: BLE001
            print(f"  ! nelze precist {os.path.relpath(path, PROJ)}: {e}")
            continue
        m = opaque(a)
        if not m.any():
            continue
        px = a[..., :3][m]
        rows.append({
            "group": group,
            "path": path,
            "rel": os.path.relpath(path, PROJ).replace("\\", "/"),
            "stem": os.path.splitext(os.path.basename(path))[0],
            "canvas": (a.shape[1], a.shape[0]),
            "lp": logical_pixel(a),
            "colors": len({tuple(c) for c in px}),
            "outline": outline_strength(a),
            "hue": hue_shift(a),
            "box": subject_box(a),
            "pool": Counter(map(tuple, px)),
        })
    return rows


def pct(vals, q):
    return float(np.percentile(vals, q)) if vals else float("nan")


def bar(n, total, width=28):
    if total <= 0:
        return ""
    return "#" * max(1, round(n / total * width))


# ------------------------------------------------------------------- vypis


def report(rows, tuning):
    total = len(rows)
    print(f"\n=== STYLOVY AUDIT — {total} shipped PNG ===\n")

    # ---------------------------------------------------------- 1 rozliseni
    print("1) ROZLISENI A LOGICKY PIXEL")
    by_group = defaultdict(list)
    for r in rows:
        by_group[r["group"]].append(r)
    for g in sorted(by_group):
        rs = by_group[g]
        canv = Counter(f'{w}x{h}' for w, h in (r["canvas"] for r in rs))
        lps = Counter(r["lp"] for r in rs)
        eff = Counter(f'{w // r["lp"]}x{h // r["lp"]}'
                      for r in rs for (w, h) in [r["canvas"]])
        print(f"  {g:<13} {len(rs):>4} souboru")
        print(f"     platno    {', '.join(f'{k}×{v}' for k, v in canv.most_common(4))}")
        print(f"     logicky px {', '.join(f'×{k}: {v}' for k, v in sorted(lps.items()))}")
        print(f"     REALNE     {', '.join(f'{k} ({v})' for k, v in eff.most_common(4))}")
    print()

    # ------------------------------------------------------------- 2 paleta
    print("2) PALETA")
    for g in sorted(by_group):
        cs = [r["colors"] for r in by_group[g]]
        print(f"  {g:<13} barev/sprite  median {int(np.median(cs)):>4}   "
              f"90. pct {int(pct(cs, 90)):>4}   max {max(cs):>4}")
    world = Counter()
    for r in rows:
        world.update(r["pool"])
    print(f"\n  Cely projekt: {len(world)} unikatnich barev.")
    for k in (16, 32, 48):
        pal = build_palette(world, k, 0.5)
        lab = to_oklab(pal)
        # Jak daleko je prumerny pixel od nejblizsi barvy master palety?
        # Nad ~0.03 v Oklab uz je rozdil videt.
        err, n = 0.0, 0
        for r in rows[::7]:                                   # vzorek, staci
            pts = np.array(list(r["pool"].keys()), dtype=np.int64)
            w = np.array(list(r["pool"].values()), dtype=float)
            pl = to_oklab(pts)
            d = np.sqrt(((pl[:, None, :] - lab[None, :, :]) ** 2).sum(-1)).min(1)
            err += float((d * w).sum())
            n += float(w.sum())
        print(f"    master paleta {k:>2} barev -> prumerna odchylka {err / max(n, 1):.4f} Oklab")
    print()

    # -------------------------------------------------------------- 3 obrys
    print("3) OBRYS  (rozdil jasu vnitrek - okraj, Oklab L)")
    for g in sorted(by_group):
        vals = [r["outline"] for r in by_group[g] if r["outline"] is not None]
        if not vals:
            continue
        strong = sum(1 for v in vals if v > 0.10)
        weak = sum(1 for v in vals if -0.02 <= v <= 0.10)
        light = sum(1 for v in vals if v < -0.02)
        print(f"  {g:<13} median {np.median(vals):+.3f}   "
              f"tmavy obrys {strong * 100 // len(vals):>3}%   "
              f"zadny {weak * 100 // len(vals):>3}%   svetly lem {light * 100 // len(vals):>3}%")
    print()

    # ---------------------------------------------------------- 4 stinovani
    print("4) STINOVANI  (posun odstinu mezi tmavou a svetlou tretinou)")
    for g in sorted(by_group):
        vals = [r["hue"] for r in by_group[g] if r["hue"] is not None]
        if not vals:
            continue
        shifted = sum(1 for v in vals if v > 15)
        flat = sum(1 for v in vals if v < 8)
        print(f"  {g:<13} median {np.median(vals):>5.1f}°   "
              f"hue shift (>15°) {shifted * 100 // len(vals):>3}%   "
              f"ztmavovani (<8°) {flat * 100 // len(vals):>3}%")
    print()

    # ------------------------------------------------------------ 5 animace
    print("5) ANIMACE")
    sets = defaultdict(set)
    for r in rows:
        m = FRAME_RE.match(r["stem"])
        if m:
            sets[(r["group"], m.group("stem"))].add(int(m.group("n")))
    lens = Counter()
    for (g, stem), frames in sets.items():
        lens[(g, len(frames))] += 1
    for g in sorted({k[0] for k in lens}):
        got = sorted(((n, c) for (gg, n), c in lens.items() if gg == g), key=lambda x: -x[1])
        print(f"  {g:<13} delky cyklu: {', '.join(f'{n}f ×{c}' for n, c in got)}")
    if tuning:
        vals = sorted(tuning.values())
        print(f"\n  FPS naladeno u {len(tuning)} sad: "
              f"{vals[0]:g}–{vals[-1]:g}, median {np.median(vals):g}")
        odd = {k: v for k, v in tuning.items() if v != np.median(vals)}
        if odd:
            print(f"    mimo median: {', '.join(f'{k}={v:g}' for k, v in sorted(odd.items())[:8])}"
                  + (" …" if len(odd) > 8 else ""))
    else:
        print("\n  data/anim_tuning.tres: zadne FPS -> vsechno bezi na vychozich 12")
    print()

    # ----------------------------------------------------------- 6 proporce
    print("6) PROPORCE  (vyska subjektu v logickych pixelech)")
    for g in sorted(by_group):
        hs = [r["box"][1] / r["lp"] for r in by_group[g] if r["box"]]
        ws = [r["box"][0] / r["lp"] for r in by_group[g] if r["box"]]
        if not hs:
            continue
        print(f"  {g:<13} vyska {min(hs):>4.0f}–{max(hs):<4.0f} median {np.median(hs):>4.1f}   "
              f"sirka median {np.median(ws):>4.1f}")
    # Rozptyl uvnitr jedne rodiny je zajimavejsi nez rozptyl napric kategoriemi:
    # ctyri obranci maji byt stejne velci, ctyri kategorie ne.
    fam = defaultdict(list)
    for r in rows:
        if r["group"] != "distractions" or not r["box"]:
            continue
        base = FRAME_RE.match(r["stem"])
        stem = base.group("stem") if base else r["stem"]
        for suf in ("_north", "_east", "_west", "_attack", "_death"):
            if stem.endswith(suf):
                stem = stem[: -len(suf)]
                break
        fam[re.sub(r"_[b-f]$", "", stem)].append(r["box"][1] / r["lp"])
    print("\n  jednotlive prisery (vyska median / rozptyl):")
    for name in sorted(fam):
        v = fam[name]
        print(f"    {name:<22} {np.median(v):>5.1f}   rozptyl {max(v) - min(v):>4.1f}")


# --------------------------------------------------------------- master paleta


# Atlasy a zdrojove listy nesmi do master palety. Jeden 1024x1024 atlas nese vic
# pixelu nez vsechny sprity dohromady a k-means by paletu utahl k nemu.
ATLAS_PX = 256 * 256


def master_palette(rows, k=32):
    """Spolecna paleta celeho projektu.

    Vaha barvy je pocet pixelu na SPRITE, ne v projektu — jinak by paletu urcilo
    to, ceho je nejvic (sto snimku chuze jedne prisery), misto toho, co je videt.
    Kazdy soubor tedy prispiva stejnym dilem.
    """
    pool = Counter()
    used = 0
    for r in rows:
        w, h = r["canvas"]
        if w * h > ATLAS_PX:
            continue
        tot = sum(r["pool"].values()) or 1
        for c, n in r["pool"].items():
            pool[c] += n / tot          # kazdy soubor dohromady vaha 1.0
        used += 1
    return build_palette(pool, k, 0.5), used


def write_palette(pal, k):
    """Ulozi paletu jako .hex (Aseprite/Lospec) a jako PNG proužek."""
    out = os.path.join(PROJ, "docs", "art")
    os.makedirs(out, exist_ok=True)
    hexes = ["%02X%02X%02X" % tuple(int(v) for v in c) for c in pal]
    hp = os.path.join(out, f"palette_{k}.hex")
    with open(hp, "w", encoding="utf-8") as f:
        f.write("\n".join(hexes) + "\n")
    sw = 16
    img = Image.new("RGB", (sw * len(pal), sw))
    for i, c in enumerate(pal):
        img.paste(tuple(int(v) for v in c), (i * sw, 0, (i + 1) * sw, sw))
    pp = os.path.join(out, f"palette_{k}.png")
    img.save(pp)
    return hexes, hp, pp


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="jen jedna kategorie (distractions/defenders/towers/…)")
    ap.add_argument("--palette", type=int, metavar="N",
                    help="spocitat master paletu N barev a vypsat hexy")
    ap.add_argument("--write", action="store_true",
                    help="s --palette: ulozit docs/art/palette_N.hex a .png")
    args = ap.parse_args()
    roots = SHIPPED
    if args.only:
        if args.only not in SHIPPED:
            raise SystemExit(f"neznama kategorie {args.only!r}; mam {', '.join(SHIPPED)}")
        roots = {args.only: SHIPPED[args.only]}
    print("ctu art…", flush=True)
    rows = audit(roots)

    if args.palette:
        pal, used = master_palette(rows, args.palette)
        # Setridit podle jasu, at je proužek citelny a poradi stabilni.
        lab = to_oklab(pal)
        pal = pal[np.argsort(lab[:, 0])]
        print(f"\nMASTER PALETA {args.palette} barev (z {used} spritu, atlasy vynechany)\n")
        for i, c in enumerate(pal):
            r_, g_, b_ = (int(v) for v in c)
            print(f"  {i:>2}  #{r_:02X}{g_:02X}{b_:02X}   rgb({r_:>3},{g_:>3},{b_:>3})")
        if args.write:
            _, hp, pp = write_palette(pal, args.palette)
            print(f"\n  -> {os.path.relpath(hp, PROJ)}\n  -> {os.path.relpath(pp, PROJ)}")
        return

    report(rows, load_tuning())


if __name__ == "__main__":
    main()
