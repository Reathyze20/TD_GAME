"""Instalace PixelLab postavy (64 px) do assets/distractions/ jako 32px snimky.

    get_character  ->  stahnout  ->  halve 64->32  ->  rozjasnit  ->  obnovit obrys
    ->  srovnat paletu  ->  ZKONTROLOVAT brany  ->  teprve pak mazat a zapisovat

Poradi je zamerne. Drivejsi verze mazala stary art hned na zacatku, a kdyz se pak
nepodarilo stahnout nahradu, prisera zmizela z disku uplne (216 souboru u notifikace).

Pouziti (potrebuje PIXELLAB_TOKEN v promennych prostredi):
    import install_pixellab as I, pixellab_client as pl
    pl.init()
    I.run("<character-uuid>", "notification", [
        (WALK_GID, "south", ""), (WALK_GID, "north", "_north"),
        (WALK_GID, "east", "_east", {"thin": 4}),
        (DEATH_GID, "south", "_death", {"outline": 0}),
    ])
"""
import glob
import hashlib
import os
import re
import subprocess
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sprite_16
import mj_to_sprite as M
# Jediny klient v projektu. Drive tu byl vlastni pixellab_client.py; slouceno,
# protoze dva klienty tehoz API se rozejdou (jeden dostal opravu strankovani,
# ktera tise usekavala seznam postav na 28 z 38, druhy ne).
import pixellab as pl

DEST = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "assets", "distractions")
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".dl_cache")


def parse_by_group(text):
    """get_character -> {group_uuid: {"name": ..., "dirs": {smer: [[url, ...]]}}}

    Klicuje se **group uuid**, ne jmeno: uzivatelske skupiny nesou vlastni jmena nebo
    jsou vsechny pojmenovane stejnou uriznutou vetou a slepily by se do jednoho klice.
    `dirs[d]` je seznam sad, protoze jeden smer se ve skupine muze opakovat
    (`5 dir (east, north, west, east, south)`).
    """
    groups, cur, sec = {}, None, False
    for line in text.splitlines():
        if line.startswith("animations"):
            sec = True
            continue
        if line.startswith(("pending", "download:")):
            sec = False
            continue
        if not sec:
            continue
        m = re.match(r"\s{2}(.+?) — (\d+) dir .*?\[group: ([0-9a-f-]+)\]", line)
        if m:
            cur = m.group(3)
            groups[cur] = {"name": m.group(1).strip(), "dirs": {}}
            continue
        m = re.match(r"\s{4}([a-z-]+): (https.+)$", line)
        if m and cur:
            groups[cur]["dirs"].setdefault(m.group(1), []).append(
                [u.strip() for u in m.group(2).split(",")])
    return groups


def download(url, path):
    """curl, ne urllib: backblaze vraci urllib 403 kvuli user-agentu."""
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return path
    os.makedirs(CACHE, exist_ok=True)
    r = subprocess.run(["curl", "-sSfL", "-o", path, url], capture_output=True)
    if r.returncode != 0:
        raise RuntimeError("curl selhal: " + r.stderr.decode()[:200])
    return path


def cache_name(base_id, url):
    """Klic cache MUSI byt z URL, ne z logickeho jmena.

    Puvodne to bylo `<base_id><dir><kind>_<i>.png` — a kdyz se prisera pregenerovala
    jako v2, cache vratila snimky v1 a na disk se zapsala stara podoba, zatimco
    PixelLab uz mel novou. Chyba se navic tvarila jako selhani generatoru.
    """
    os.makedirs(CACHE, exist_ok=True)
    key = hashlib.sha1(url.split("?")[0].encode()).hexdigest()[:16]
    return os.path.join(CACHE, f"{base_id}_{key}.png")


def cleanup(base_id):
    """Smaze stary art teto prisery VCETNE variant (_b/_c/_d).

    Nutne ze dvou duvodu: DistractionAnimator nacita snimky, dokud jeden nechybi, takze
    stara devitisnimkova chuze by se michala s novou osmisnimkovou; a varianty by
    nechaly ve vlnach chodit stary vytvarny styl vedle noveho.
    """
    killed = 0
    for p in glob.glob(os.path.join(DEST, base_id + "*_frame_*.png*")):
        os.remove(p)
        killed += 1
    return killed


def raw(urls, tag):
    """Stahne a zmensi na 32 px. Cache je klicovana URL, takze druhe volani je zdarma."""
    out = []
    for u in urls:
        p = cache_name(tag, u)
        download(u, p)
        im = Image.open(p).convert("RGBA")
        out.append(sprite_16.halve(im, 32) if im.width != 32 else im)
    return out


def process(ims, rim, gamma, colors=24, panel=False):
    """Poradi je zavazne: rozjasnit PRED obrysem, jinak se rozjasni i obrys.

    `panel` je zamerne VYPNUTE by default. `strip_panel` floodne od okraje pres tmave
    pixely, coz je spravne u clickbaita (tmavy panel za postavou), ale destruktivni u
    notifikace: ta ma tmave TELO a v rozkrocenych pozach se okraje platna dotyka, takze
    flood pokracoval do ni a v nekolika snimcich behu zbyla jen hlava. Zapinej to jen
    tam, kde jsi videl, ze tam panel je.
    """
    # largest_piece rovnou, ne jen v branach: uletly fragment je vzdycky vada a
    # da se odstranit deterministicky, takze nema smysl kvuli nemu zastavovat
    out = [M.largest_piece(M.restore_outline(
               M.lift(M.strip_shadow(M.strip_panel(i, 0.80) if panel else i), gamma), rim))
           for i in ims]
    return repalette(out, colors)


def repalette(ims, colors=24):
    """Srovna paletu CELE sady najednou.

    Rozjasneni gamou vyrobi nove odstiny (u clickbaitova vychodu 34 barev proti prahu
    32). Kvantizovat po snimcich nelze — kazdy by dostal vlastni paletu a barvy by pri
    chuzi poskakovaly. Proto se snimky slepi do pasu, kvantizuji jednou a rozreznou.
    """
    if not ims:
        return ims
    w, h = ims[0].size
    strip = Image.new("RGBA", (w * len(ims), h), (0, 0, 0, 0))
    for i, im in enumerate(ims):
        strip.alpha_composite(im, (i * w, 0))
    q = M.quantize(strip, colors)
    return [q.crop((i * w, 0, (i + 1) * w, h)) for i in range(len(ims))]


def check(ims, relax=None):
    """Brany pres cely cyklus, ne pres prvni snimek.

    Behova poza je z principu nizsi a uzsi nez stoj — prvni snimek notifikace mel
    vysku 24 proti prahu 26, i kdyz cyklus jako celek byl v poradku. Proto median.

    `relax` prepisuje jednotlive prahy. Legitimni duvody, ktere jsme narazili:
      thin  u hubeneho behouna z profilu — sprintujici nohy MAJI byt 1px, prah 2
            je odectenej ze stojici brokolice a na beh z boku nesedi
      outline u smrti — mrtvola lezi na zemi a je tmava, takze rozdil telo/obrys
            21 po ni chtit nejde; telo samo ma mensi jas nez ten rozdil
    """
    ks = [M.audit(i) for i in ims]
    med = lambda k: sorted(x[k] for x in ks)[len(ks) // 2]
    k = dict(colors=med("colors"), outline=med("outline"),
             pieces=max(x["pieces"] for x in ks),
             thin=med("thin"), h=max(x["h"] for x in ks), w=med("w"))
    old = dict(M.GATES)
    try:
        M.GATES.update(relax or {})
        return M.passes(k)
    finally:
        M.GATES.clear()
        M.GATES.update(old)


def solve(etalon, target=30.0, panel=False):
    """Najde gamu proti HOTOVEMU snimku, ne proti surovemu.

    Naivni `lift_gamma(raw)` mine cil: tmavy obrys se pridava az po rozjasneni a
    prumer zase stahne dolu (gama 0,913 mela dat +32, dala +27,3). Kontrast je v gamme
    monotonni, takze staci pulit interval nad celym retezcem.
    """
    def contrast(gm):
        rim = M.outline_color(M.lift(etalon, gm))
        a = np.asarray(process([etalon], rim, gm, panel=panel)[0].convert("RGBA"))
        m = a[..., 3] > 128
        return ((a[..., :3].astype(float) @ [0.299, 0.587, 0.114])[m].mean() - M.BG_LUM), rim

    c, rim = contrast(1.0)
    if c >= target:
        return 1.0, rim
    lo, hi = 0.25, 1.0
    for _ in range(14):
        gm = (lo + hi) / 2
        c, _ = contrast(gm)
        if c >= target:
            lo = gm
        else:
            hi = gm
    _, rim = contrast(lo)
    return lo, rim


def run(character_id, base_id, groups, dry=False, panel=False):
    """groups: [(group_uuid, smer, pripona[, relax])] — PRVNI je chuze a slouzi za etalon."""
    t = pl.text_of(pl.call("get_character", {"character_id": character_id}))
    g = parse_by_group(t)

    fetched, bad = {}, []
    for gid, d, suffix, *_ in groups:
        if gid not in g or d not in g[gid]["dirs"]:
            bad.append(f"chybi {suffix or 'south'} ({gid[:8]})")
            continue
        fetched[suffix] = raw(g[gid]["dirs"][d][0], base_id + suffix)
    if bad:
        return f"{base_id}: NEINSTALUJI — " + " | ".join(bad)

    # Obrys i rozjasneni se pocitaji JEDNOU, a to z prvniho snimku CHUZE, ne z rotace:
    # rotace je stojici poza a je svetlejsi, takze gama z ni spocitana nechala beh pod
    # prahem kontrastu (+27,8 misto +30). Per-snimek to pocitat nelze vubec — sprite by
    # pri chuzi pulzoval a smrt by se barevne rozesla s chuzi.
    etalon = fetched[groups[0][2]][0]
    gamma, rim = solve(etalon, panel=panel)
    print(f"  rozjasneni gama={gamma}, obrys={rim}")

    built = {}
    for gid, d, suffix, *rest in groups:
        ims = process(fetched[suffix], rim, gamma, panel=panel)
        problems = check(ims, rest[0] if rest else None)
        if problems:
            bad.append(f"{suffix or 'chuze'}: " + "; ".join(problems))
        built[suffix] = ims

    if bad:
        return f"{base_id}: NEINSTALUJI — " + " | ".join(bad)
    if dry:
        return f"{base_id}: dry-run ok — " + ", ".join(f"{k or 'south'}:{len(v)}" for k, v in built.items())

    removed = cleanup(base_id)
    rep = [f"smazano {removed}"]
    for suffix, ims in built.items():
        for i, im in enumerate(ims, 1):
            im.save(os.path.join(DEST, f"{base_id}{suffix}_frame_{i}.png"))
        rep.append(f"{suffix or 'south'}:{len(ims)}")
    return f"{base_id}: " + ", ".join(rep)
