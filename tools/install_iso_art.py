# Instalace iso artu z build/iso_art/ do assets/terrain/iso/.
#
# PROC SE SOUBORY PREJMENOVAVAJI PODLE MASKY
#
# Sada `lane` prijde z PixelLabu jako tile_0..tile_17 plus tabulka "ktera dlazdice
# patri ke ktere masce sousedu". Kdyby si tu tabulku drzel zvlast kod ve hre, je to
# dalsi misto, ktere se muze rozejit s tim, co lezi na disku -- presne ten druh
# tiche neshody, ktery tenhle projekt uz jednou stal mesic (viz TERRAIN_ART_PX
# v data.gd). Soubor se proto jmenuje `lane_06.png` pro masku 6 a hra si ho nacte
# podle cisla. Tabulka tim prestane existovat jako samostatna vec.
#
# Bity masky: bit0=N bit1=E bit2=S bit3=W, kde N=(0,-1) E=(1,0) S=(0,1) W=(-1,0).
# Overeno merenim na jednobitovych dlazdicich, ne odhadem -- viz
# build/iso_art/_lane_dirs.png a docs/art/iso_bible.md.
#
#   python tools/install_iso_art.py --lane lane3 --ground tissue2 --terrace terrace3
#   python tools/install_iso_art.py ... --dry
import argparse
import json
import os
import shutil

from PIL import Image

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(PROJ, "build", "iso_art")
DST = os.path.join(PROJ, "assets", "terrain", "iso")

# maska -> indexy dlazdic v sade path_tiles (z placement_rules; 15 a 0 maji dve varianty)
LANE_BY_MASK = {0: [0, 1], 1: [2], 2: [3], 4: [4], 8: [5], 10: [6], 5: [7], 6: [8],
                12: [9], 3: [10], 9: [11], 14: [12], 13: [13], 11: [14], 15: [15, 16]}
LANE_FILL = 17          # plna deska, "stamp-only" kus sady -- vnitrek siroke drahy

# Kusy stavebniho kitu, ktere hra opravdu pouzije. Zbytek (dvere, pricky, patra)
# je pro mistnosti a na vyvysenou zem se nehodi -- neinstaluje se, at je v assets/
# videt jen to, co se kresli.
KIT_PARTS = {"block": 53, "cap": 0, "pillar": 31, "stairs": 40}

# Nasobic odstinu terasy. Kit dava neutralni sedou; hra chce KOST, ne beton. Soucin
# slozek je zamerne ~1.0, aby posun menil barvu a ne jas -- jas resi --terrace-median.
WARM = (1.10, 1.02, 0.88)


def accent_share(path):
    """Podil vyrazne svetlych a saturovanych pixelu -- svitici synapse. Sedy zaklad
    tkane ma saturaci nizkou, takze prah oddeluje kresbu od materialu."""
    import numpy as np
    a = np.array(Image.open(path).convert("RGBA")).astype(int)
    m = a[..., 3] > 8
    if not m.any():
        return 0.0
    px = a[..., :3][m]
    mx, mn = px.max(1), px.min(1)
    return float(((mx > 110) & (mx - mn > 45)).sum()) / float(m.sum())


def tone(src, dst, target_median, dry):
    """Zkopiruje dlazdici a zaroven ji sesadi na cilovy median jasu.

    PROC NASOBENI A NE KRIVKA: pomer vrch : svetla stena : stinova stena = 100:70:45
    je cela informace o tvaru terasy (docs/art/iso_bible.md §2). Nasobeni ten pomer
    zachova PRESNE, protoze je linearni -- je to doslova "min svetla". Gamma nebo
    levels by rozdily mezi stenami stlacily a hranol by zplostl.

    Sesazuje se az PRI INSTALACI, ne v promptu: generator drzi jas jen volne (terrace2
    vyslo 400, terrace3 524, terrace5 606 na temze cili), takze doprosovat se ho v textu
    je loterie. Tady je to jedno zmerene cislo.
    """
    import numpy as np
    im = Image.open(src).convert("RGBA")
    a = np.array(im).astype(np.float32)
    m = a[..., 3] > 8
    if not m.any() or target_median <= 0:
        return copy(src, dst, dry)
    med = float(np.median(a[..., :3][m].sum(1)))
    k = 1.0 if med <= 0 else min(1.0, target_median / med)
    a[..., :3] = np.clip(a[..., :3] * k, 0, 255)
    print(f"  {os.path.relpath(dst, PROJ)}  (x{k:.3f}, med {int(med)} -> {int(med*k)})")
    if not dry:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        Image.fromarray(a.astype(np.uint8), "RGBA").save(dst)


def copy(src, dst, dry):
    print(f"  {os.path.relpath(dst, PROJ)}")
    if not dry:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(src, dst)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lane", default="lane3")
    ap.add_argument("--ground", default="tissue2")
    ap.add_argument("--terrace", default="terrace3")
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--towers", action="store_true", help="nainstalovat i veze a propy")
    ap.add_argument("--terrace-warm", action="store_true", default=True,
                    help="posunout terasu ze sede k slonovinove kosti")
    ap.add_argument("--no-terrace-warm", dest="terrace_warm", action="store_false")
    ap.add_argument("--terrace-median", type=int, default=410,
                    help="cilovy median jasu terasy (bible: 380-450); 0 = nesahat")
    a = ap.parse_args()

    print("== zem (tkan) ==")
    gdir = os.path.join(SRC, a.ground)
    quiet, accent = 0, 0
    for i in range(64):
        p = os.path.join(gdir, f"tile_{i}.png")
        if not os.path.isfile(p):
            continue
        # Dlazdice se TRIDI, nesypou se do jednoho poolu. Rovnomerne losovani z jednoho
        # poolu je konfetovy posyp a pole pusobi rusive pri JAKEMKOLI podilu -- overeno
        # na top-down desce, kde snizovani 17,6 -> 9,7 % nepomohlo a pomohlo az
        # shlukovani (viz project-art-direction-mapa). Vysledek prvniho iso kola vypadal
        # presne tak: ~ctvrtina bunek nesla synapsi, rozseto po cele desce.
        #
        # "Akcent" = dlazdice se saturovanymi svetlymi pixely (synapse svitici cyan nebo
        # zlate). Meri se, neurcuje se okem, aby to platilo i pro pristi davku.
        if accent_share(p) > 0.004:
            copy(p, os.path.join(DST, "ground", f"ground_accent_{accent:02d}.png"), a.dry)
            accent += 1
        else:
            copy(p, os.path.join(DST, "ground", f"ground_{quiet:02d}.png"), a.dry)
            quiet += 1
    print(f"  -> {quiet} tichych + {accent} s akcentem")

    print("== pruh (dopaminova draha) ==")
    ldir = os.path.join(SRC, a.lane)
    for mask, idx in sorted(LANE_BY_MASK.items()):
        for k, ti in enumerate(idx):
            suffix = "" if k == 0 else chr(ord("a") + k)
            copy(os.path.join(ldir, f"tile_{ti}.png"),
                 os.path.join(DST, "lane", f"lane_{mask:02d}{suffix}.png"), a.dry)
    copy(os.path.join(ldir, f"tile_{LANE_FILL}.png"),
         os.path.join(DST, "lane", "lane_fill.png"), a.dry)

    print("== terasa ==")
    tdir = os.path.join(SRC, a.terrace)
    import numpy as np

    # ROUBOVANI VRCHU. Hranol kitu ma vlastni vrch se stinovanym lemem. Jako samostatny
    # objekt vypada dobre, ale vydlazden 3x3 se z terasy stane HROMADA KRABIC, protoze
    # kazda bunka si sama sebe obkrouzi. `cap` (tile_0) lem nema, takze po prekryti
    # (posunutem o WALL_HEIGHT nahoru) splynou vrchy sousedu v jednu plochu a viditelne
    # zustanou jen boky na okraji masivu. Overeno vydlazdenim 5x5, ne odhadem --
    # build/iso_art/_tile_cmp.png.
    #
    # Tohle je zaroven duvod, proc v repu neni terrace5 (hezci kost): jeho podlahova
    # dlazdice je kreslena jako samostatna zaoblena deska s vlastnim okrajem, takze
    # nesplyne ani po zaroubovani. Material, ktery se neda vydlazdit, je nepouzitelny
    # bez ohledu na to, jak vypada sam o sobe.
    blk = Image.open(os.path.join(tdir, f"tile_{KIT_PARTS['block']}.png")).convert("RGBA")
    cap = Image.open(os.path.join(tdir, f"tile_{KIT_PARTS['cap']}.png")).convert("RGBA")
    grafted = blk.copy()
    grafted.alpha_composite(cap.transform(cap.size, Image.AFFINE, (1, 0, 0, 0, 1, 32)))

    # Jeden spolecny koeficient jasu pro CELOU sadu, spocitany z hranolu. Kdyby se kazdy
    # kus sesazoval na svuj vlastni median, schody a sloup by se rozesly s hranolem --
    # presne ta chyba, kterou uz jednou udelal atlas zdi (133/141/163 = patchwork se svy).
    bm = np.array(grafted)
    bmask = bm[..., 3] > 8
    bmed = float(np.median(bm[..., :3][bmask].astype(int).sum(1)))
    tk = min(1.0, a.terrace_median / bmed) if (a.terrace_median > 0 and bmed > 0) else 1.0
    print(f"  jas sady: hranol med {int(bmed)} -> cil {a.terrace_median}, koeficient x{tk:.3f}")
    if a.terrace_warm:
        print(f"  teply posun k slonovine: {WARM}")

    def write(im, dst):
        arr = np.array(im).astype(np.float32)
        rgb = arr[..., :3] * tk
        if a.terrace_warm:
            # Sedy beton -> kost. Posun je jen v ODSTINU, jas uz sesadil koeficient vys,
            # takze se nasobi kolem 1.0 a hodnotova hierarchie z bible zustava platna.
            rgb *= np.array(WARM, dtype=np.float32)
        arr[..., :3] = np.clip(rgb, 0, 255)
        print(f"  {os.path.relpath(dst, PROJ)}")
        if not a.dry:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            Image.fromarray(arr.astype(np.uint8), "RGBA").save(dst)

    write(grafted, os.path.join(DST, "terrace", "block.png"))
    for name, ti in KIT_PARTS.items():
        if name == "block":
            continue
        write(Image.open(os.path.join(tdir, f"tile_{ti}.png")).convert("RGBA"),
              os.path.join(DST, "terrace", f"{name}.png"))

    # Kotva kitu se NEZAPISUJE do kodu jako konstanta. Hra si ji spocita za behu z
    # `cap.png`: nejnizsi neprusvitny pixel podlahoveho diamantu lezi presne
    # th/2 = 16 px pod stredem bunky, a vodorovny stred obsahu je stred bunky.
    # Tim se kotva nemuze rozejit s artem pri jeho vymene -- tentyz princip jako
    # `Image.get_used_rect()` v iso_pilot.gd.
    cap = Image.open(os.path.join(tdir, f"tile_{KIT_PARTS['cap']}.png")).convert("RGBA")
    import numpy as np
    al = np.array(cap)[..., 3] > 8
    ys, xs = np.where(al)
    print(f"\nkotva odvozena z cap.png: obsah x {xs.min()}..{xs.max()} y {ys.min()}..{ys.max()}")
    print(f"  stred bunky v platne = ({(xs.min()+xs.max())/2:.1f}, {ys.max()-16:.1f})")
    block = Image.open(os.path.join(tdir, f"tile_{KIT_PARTS['block']}.png")).convert("RGBA")
    bal = np.array(block)[..., 3] > 8
    bys, _ = np.where(bal)
    print(f"  vyska hranolu (WALL_HEIGHT) = {ys.max() - bys.min() - 32} px "
          f"nad rovinou zeme; kit kresli steny 32 px")

    meta = {"lane": a.lane, "ground": a.ground, "terrace": a.terrace,
            "lane_by_mask": {str(k): v for k, v in LANE_BY_MASK.items()},
            "kit_parts": KIT_PARTS}
    if not a.dry:
        json.dump(meta, open(os.path.join(DST, "_provenance.json"), "w",
                             encoding="utf-8"), indent=1)
    if a.towers:
        install_towers(a.dry)

    print("\nhotovo" + (" (dry run, nic se nezapsalo)" if a.dry else ""))



# --------------------------------------------------------------------- veze
#
# Kam se instaluje: assets/towers/head_<type_key>.png -- tam si to tower.gd hleda samo.
#
# POZOR NA ANIMACNI SNIMKY. `_current_head_tex()` dava prednost `head_<key>_frame_N.png`
# pred statickym `head_<key>.png`, takze dokud stare snimky lezi vedle, nova iso hlava
# se VUBEC nezobrazi. Snimky se proto odsouvaji do assets/towers/_topdown_backup/.
#
# Tim se ale ztraci informace, kterou ty snimky nesly: animace byla privazana na reload
# (`_advance_charge_anim`), takze hrac videl z pouheho spritu, ze habit pracuje nebo ma
# pauzu. Nez se vygeneruji iso animace (`animate_object`), je tahle zpetna vazba pryc --
# je to znama regrese, ne prehlednuti.

TOWER_SRC = {
    "focus_timer":    ("towers_b", "cand_0.png"),
    "exercise":       ("towers_b", "cand_1.png"),
    "real_hobby":     ("towers_b", "cand_2.png"),
    "focus_pillar":   ("towers_b", "cand_3.png"),
    # towers_c, ne prvni davka: ta mela u Mindfulness a Guildu ZAPECENOU podstavu
    # primo v artu (fialova elipsa / zeleny kosoctverec). Kod uz zadnou nekresli
    # (has_own_pedestal = true na vsech habitech), takze zapecene by trcely samy.
    "mindfulness":    ("towers_c", "cand_0.png"),
    "accountability": ("towers_c", "cand_1.png"),
    "zen_pulsar":     ("towers_c", "cand_2.png"),
    "anchor":         ("towers_c", "cand_3.png"),
}
PROP_SRC = {
    "core":         ("props_b", "cand_0.png"),
    "spawn_rift":   ("props_b", "cand_1.png"),
    "decor_synapse": ("props_b", "cand_2.png"),
    "decor_knot":   ("props_b", "cand_3.png"),
}


def install_towers(dry=False):
    import glob
    towers = os.path.join(PROJ, "assets", "towers")
    backup = os.path.join(towers, "_topdown_backup")
    print("== veze ==")
    for key, (d, f) in TOWER_SRC.items():
        src = os.path.join(SRC, d, f)
        if not os.path.isfile(src):
            print(f"  ! chybi {src}")
            continue
        moved = 0
        for old in glob.glob(os.path.join(towers, f"head_{key}_frame_*.png*")):
            if not dry:
                os.makedirs(backup, exist_ok=True)
                shutil.move(old, os.path.join(backup, os.path.basename(old)))
            moved += 1
        copy(src, os.path.join(towers, f"head_{key}.png"), dry)
        if moved:
            print(f"      ({moved} starych snimku -> _topdown_backup/)")
    print("== propy ==")
    for name, (d, f) in PROP_SRC.items():
        src = os.path.join(SRC, d, f)
        if os.path.isfile(src):
            copy(src, os.path.join(DST, "props", f"{name}.png"), dry)


if __name__ == "__main__":
    main()
