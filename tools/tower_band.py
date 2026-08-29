# Posadi hlavy vezi do vlastniho jasoveho pasma pod terasou.
#
# PROBLEM (zmereno 21. 8. 2026 na ploche desce)
#
# 7 z 8 hlav lezi do +-60 jasu od terasy, na ktere STOJI (482-611 proti 484). Ctyri
# kostene se do ni doslova ztraci; ctyri azurove prezivaji jen ODSTINEM. To je krehke,
# protoze Tolerance barvy vysava (shaders/flatten.gdshader) -- takze prave ve chvili,
# kdy je hrac v uzkych, zmizi i ty ctyri, co dnes funguji.
#
# Je to tataz vada, kterou docs/design/fae_theme.md §1 zapsal uz na zacatku. Rozdil je,
# ze pozadi je od 21. 8. JEDNA ZNAMA HODNOTA s 0 % hran, takze se cil da napsat presne.
#
# RESENI: nasobeni, ne krivka -- ale JEN NA TELO, ne na akcent
#
# Tataz uvaha jako u terasy (docs/art/iso_bible.md kap. 2b): linearni nasobeni zachova
# POMERY uvnitr spritu, tedy tvar a smer svetla. Krivka nebo posun by hlavu zplostily --
# a hlava je herec, ten detail si ma nechat (viz "ploche je jen pozadi" tamtez).
#
# Prvni verze nasobila VSECHNO a vysledek byl spravny cislem, ale sedivy: zlate vejce
# focus_timeru zhnedlo a azurove krystaly zmatnely. Bible pritom pro veze predepisuje
# presne opak -- "utvary vyrostle z tkane s jednim bioluminiscencnim akcentem"
# (docs/art/iso_bible.md kap. 1b). Akcent MA zarit; splyva s terasou TELO, ne on.
#
# Deli se proto podle SYTOSTI: kostene a krémové telo ma sytost nizkou, oranzove/zlate/
# azurove akcenty vysokou. Telo se ztmavi na cil, akcent si jas nechá. Vysledek je
# "tmavy tvar s jednim svetlem", coz je zaroven lepsi silueta -- oko chyta akcent.
#
#   python tools/tower_band.py             # posadi na TARGET
#   python tools/tower_band.py --target 320
#   python tools/tower_band.py --restore
import argparse
import os
import shutil

import numpy as np
from PIL import Image

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOW = os.path.join(PROJ, "assets", "towers")
BACKUP = os.path.join(PROJ, "build", "_tower_backup")

## Terasa ma 484. 300 je od ni 184 daleko, tedy 38 % -- zretelny schod i kdyz odstin
## odejde. Zaroven to neni tak tmave, aby hlava splynula se stinovou stenou terasy (218).
TARGET = 300.0


def heads():
    return sorted(f for f in os.listdir(TOW) if f.startswith("head_") and f.endswith(".png"))


def median_val(path):
    a = np.array(Image.open(path).convert("RGBA"))
    m = a[..., 3] > 8
    return float(np.median(a[..., :3][m].sum(1))) if m.any() else 0.0


def backup():
    if os.path.isdir(BACKUP):
        print(f"zaloha uz existuje: {os.path.relpath(BACKUP, PROJ)} (nechavam)")
        return
    os.makedirs(BACKUP, exist_ok=True)
    for f in heads():
        shutil.copy2(os.path.join(TOW, f), os.path.join(BACKUP, f))
    print(f"zaloha -> {os.path.relpath(BACKUP, PROJ)}")


def restore():
    if not os.path.isdir(BACKUP):
        raise SystemExit("zadna zaloha")
    for f in os.listdir(BACKUP):
        shutil.copy2(os.path.join(BACKUP, f), os.path.join(TOW, f))
    print(f"vraceno {len(os.listdir(BACKUP))} hlav")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", type=float, default=TARGET)
    ## Prah sytosti, kde telo prechazi v akcent. Zmereno na dnesnich hlavach: kostene
    ## telo lezi pod 0,25, oranzove/zlate/azurove akcenty nad 0,45.
    ap.add_argument("--sat-lo", type=float, default=0.25, dest="sat_lo")
    ap.add_argument("--sat-hi", type=float, default=0.45, dest="sat_hi")
    ap.add_argument("--restore", action="store_true")
    a = ap.parse_args()
    if a.restore:
        restore()
        return
    backup()
    print(f"{'hlava':22s} {'celek':>5s} {'telo':>5s} {'k':>5s} {'telo po':>7s} {'akcent px':>9s}")
    for f in heads():
        src = os.path.join(BACKUP, f)          # vzdy ze zalohy, at neni nasobeni kumulativni
        p = os.path.join(TOW, f)
        before = median_val(src)
        if before <= 0:
            continue
        im = Image.open(src).convert("RGBA")
        arr = np.array(im).astype(float)
        m = arr[..., 3] > 8
        rgb = arr[..., :3]

        # Sytost bez prevodu po pixelu: (max-min)/max je tatáž velicina jako v HSV.
        mx = rgb.max(2)
        mn = rgb.min(2)
        sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0.0)

        # Vaha 0 = plne telo (ztmavit), 1 = plny akcent (nechat). Prechod je mekky, aby
        # na hranici akcentu nevznikl tvrdy lem.
        w = np.clip((sat - a.sat_lo) / max(a.sat_hi - a.sat_lo, 1e-6), 0.0, 1.0)

        body = m & (w < 0.5)
        base_val = float(np.median(rgb[body].sum(1))) if body.any() else before
        k_body = a.target / max(base_val, 1e-6)

        kk = k_body + (1.0 - k_body) * w          # telo -> k_body, akcent -> 1.0
        rgb[m] = np.clip(rgb[m] * kk[m][:, None], 0, 255)
        Image.fromarray(arr.astype("uint8"), "RGBA").save(p)

        after_body = float(np.median(np.array(Image.open(p).convert("RGBA"))[..., :3][body].sum(1)))
        print(f"{f[5:-4]:22s} {before:5.0f} {base_val:5.0f} {k_body:5.2f} {after_body:5.0f}"
              f" {int((w[m] >= 0.5).sum()):6d}")


if __name__ == "__main__":
    main()
