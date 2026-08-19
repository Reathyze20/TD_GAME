# Paletove promeny a varianty: prebarveni a tier upgrady bez AI.
#
#   from palette_morph import recolor_target, tier_upgrade, recolor_shift, skin_swap
#   new_sprite = recolor_target(sprite_rgba, "#ff3b30")
#   tier2_sprite = tier_upgrade(sprite_rgba, tier=2)
#
# PROC OKLCH A NE RGB / HSV
#
# V RGB nebo HSV zmena Hue znici vnimany jas (perceived lightness): zluta je vnimana
# jako mnohem svetlejsi nez modra pri stejne "value". V Oklch je L (Lightness) skutecny
# vnimany jas a C (Chroma) sytost. Zmenou Hue v Oklch zustane svetlo a stin presne
# zachovano — plasticky tvar spritu se nezhrouti.
#
# ZACHOVANI ANATOMIE
#
# - Obrysy (L < 0.18): zustavaji tmave, neobarvuji se do kriklavych barev.
# - Odlesky (L > 0.92): zustavaji ciste bile/svetle.
# - Neutraly (Chroma < 0.025): sede/cerne plochy se netonuji, pokud to neni zamer.
import os
import sys

import numpy as np

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from sprite_cleanup import _M1, _M2, to_oklab  # noqa: E402

_M1_INV = np.linalg.inv(_M1)
_M2_INV = np.linalg.inv(_M2)


def from_oklab(lab: np.ndarray) -> np.ndarray:
    """Oklab (...,3) -> sRGB (...,3) v uint8 (0-255)."""
    lms = lab @ _M2_INV.T
    lms = np.sign(lms) * (np.abs(lms) ** 3)
    lin = lms @ _M1_INV.T
    srgb = np.where(lin <= 0.0031308, lin * 12.92,
                    1.055 * (np.maximum(lin, 0) ** (1.0 / 2.4)) - 0.055)
    return np.clip(np.round(srgb * 255.0), 0, 255).astype(np.uint8)


def to_oklch(rgb: np.ndarray) -> np.ndarray:
    """RGB (...,3) -> Oklch (...,3) [L (0..1), C (0..~0.4), h_rad (-pi..pi)]."""
    lab = to_oklab(rgb)
    L = lab[..., 0]
    a = lab[..., 1]
    b = lab[..., 2]
    C = np.sqrt(a * a + b * b)
    h = np.arctan2(b, a)
    return np.stack([L, C, h], axis=-1)


def from_oklch(lch: np.ndarray) -> np.ndarray:
    """Oklch (...,3) -> RGB (...,3) v uint8."""
    L = lch[..., 0]
    C = lch[..., 1]
    h = lch[..., 2]
    a = C * np.cos(h)
    b = C * np.sin(h)
    lab = np.stack([L, a, b], axis=-1)
    return from_oklab(lab)


def parse_hex_color(hex_str: str) -> np.ndarray:
    """'#ff3b30' nebo 'ff3b30' -> np.array([255, 59, 48], dtype=np.uint8)."""
    s = hex_str.strip().lstrip("#")
    if len(s) == 3:
        s = "".join(c * 2 for c in s)
    if len(s) != 6:
        raise ValueError(f"neplatná hex barva: {hex_str!r}")
    return np.array([int(s[:2], 16), int(s[2:4], 16), int(s[4:6], 16)], dtype=np.uint8)


def rgb_to_hex(rgb) -> str:
    """[255, 59, 48] -> '#ff3b30'."""
    return f"#{int(rgb[0]):02x}{int(rgb[1]):02x}{int(rgb[2]):02x}"


# ------------------------------------------------------------------ prebarveni


def recolor_shift(a: np.ndarray, delta_deg: float, preserve_neutrals: bool = True) -> np.ndarray:
    """Posun odstinu celeho spritu o `delta_deg` stupnu.

    Zachovava puvodni kontrasty a rozdily mezi castmi tela (napr. cervene oci zustanou
    o stejny uhel jinde nez zelene telo)."""
    out = a.copy()
    m = out[..., 3] > 32
    if not m.any():
        return out

    rgb = out[..., :3][m]
    lch = to_oklch(rgb)

    delta_rad = np.deg2rad(delta_deg)

    if preserve_neutrals:
        # Menit jen pixely, ktere maji barvu (chroma >= 0.025) a nejsou ciste cerny obrys
        color_mask = (lch[..., 1] >= 0.025) & (lch[..., 0] >= 0.16) & (lch[..., 0] <= 0.94)
        lch[color_mask, 2] = (lch[color_mask, 2] + delta_rad + np.pi) % (2 * np.pi) - np.pi
    else:
        lch[..., 2] = (lch[..., 2] + delta_rad + np.pi) % (2 * np.pi) - np.pi

    out[..., :3][m] = from_oklch(lch)
    return out


def recolor_target(a: np.ndarray, target_hex: str, preserve_accents: bool = True) -> np.ndarray:
    """Prebarvi dominantni barevnou rodinu spritu na cilovou barvu.

    Cilovy odstin (hue) a sytost se prenesou na barevne pixely, ale jejich jas (L)
    se zachova, takze stinovani zustane plasticke.

    `preserve_accents=True` chrani drobne akcenty (oci, zuby, odlesky), jejichz
    odstin se vyrazne lisi od puvodniho tela spritu."""
    target_rgb = parse_hex_color(target_hex)
    target_lch = to_oklch(target_rgb.reshape(1, 3))[0]
    target_h = target_lch[2]
    target_c = target_lch[1]

    out = a.copy()
    m = out[..., 3] > 32
    if not m.any():
        return out

    rgb = out[..., :3][m]
    lch = to_oklch(rgb)

    # Najdi dominantni odstin tela
    colored = lch[..., 1] >= 0.03
    if not colored.any():
        return out

    # Vazeny kruhovy prumer hue
    sin_sum = (lch[colored, 1] * np.sin(lch[colored, 2])).sum()
    cos_sum = (lch[colored, 1] * np.cos(lch[colored, 2])).sum()
    dom_h = np.arctan2(sin_sum, cos_sum)

    # Rozdil odstinu od dominantniho
    h_diff = np.abs((lch[..., 2] - dom_h + np.pi) % (2 * np.pi) - np.pi)

    # Ktere pixely prebarvit: maji barvu, nejsou cerny obrys (L < 0.16) ani zarivy odlesk (L > 0.94)
    eligible = (lch[..., 1] >= 0.025) & (lch[..., 0] >= 0.16) & (lch[..., 0] <= 0.94)

    if preserve_accents:
        # Akcent = odlisuje se od tela o vic nez 65 stupnu (~1.13 rad)
        eligible &= (h_diff < 1.13)

    if eligible.any():
        # Prevezmi cilovy hue
        lch[eligible, 2] = target_h
        # Prizpusob sytost: zachovej pomer, ale posun k cilove sytosti
        if target_c > 0.01:
            lch[eligible, 1] = np.clip(lch[eligible, 1] * (target_c / max(0.04, lch[eligible, 1].mean())),
                                       0.02, 0.38)

    out[..., :3][m] = from_oklch(lch)
    return out


def skin_swap(a: np.ndarray, from_hex: str, to_hex: str, tol_deg: float = 40.0) -> np.ndarray:
    """Prebarvi jen pixely blizke barve `from_hex` na novou barvu `to_hex`."""
    from_rgb = parse_hex_color(from_hex)
    to_rgb = parse_hex_color(to_hex)

    from_lch = to_oklch(from_rgb.reshape(1, 3))[0]
    to_lch = to_oklch(to_rgb.reshape(1, 3))[0]

    out = a.copy()
    m = out[..., 3] > 32
    if not m.any():
        return out

    rgb = out[..., :3][m]
    lch = to_oklch(rgb)

    h_diff = np.abs((lch[..., 2] - from_lch[2] + np.pi) % (2 * np.pi) - np.pi)
    tol_rad = np.deg2rad(tol_deg)

    sel = (h_diff <= tol_rad) & (lch[..., 1] >= 0.02) & (lch[..., 0] >= 0.15)
    if sel.any():
        lch[sel, 2] = to_lch[2]
        # Prizpusobit chromu
        if to_lch[1] > 0.01:
            lch[sel, 1] = np.clip(lch[sel, 1] * (to_lch[1] / max(0.04, from_lch[1])), 0.02, 0.38)

    out[..., :3][m] = from_oklch(lch)
    return out


# ------------------------------------------------------------------ tier upgrady


def tier_upgrade(a: np.ndarray, tier: int = 2) -> np.ndarray:
    """Vygeneruje silnejsi/elitni variantu spritu (Tier 2 / Tier 3).

    Tier 2:
      - Zvysi kontrast a sytost (+20% chroma)
      - Zvyrazni oci a svetelne body
      - Jemny zlaty/plamenny odlesk na ramenou/vrsku

    Tier 3 (Boss / Elite):
      - Zvysi sytost (+40% chroma) s dramatickym posunem do purpurove/ohnive/elektricke
      - Prida 1px svetelny lem (corona/aura) podel horniho a leveho okraje siluety
      - Oci zazi (maximalni jas a sytost)
    """
    out = a.copy()
    m = out[..., 3] > 32
    if not m.any():
        return out

    h, w = out.shape[:2]
    rgb = out[..., :3][m]
    lch = to_oklch(rgb)

    if tier == 2:
        # Zvyseni kontrastu a chromy
        body = (lch[..., 1] >= 0.025) & (lch[..., 0] >= 0.16)
        lch[body, 1] = np.clip(lch[body, 1] * 1.25, 0.0, 0.38)
        # Zvyrazneni svetel (L > 0.65 se mirne prosvetli)
        high = lch[..., 0] > 0.65
        lch[high, 0] = np.clip(lch[high, 0] * 1.08, 0.0, 0.98)

        out[..., :3][m] = from_oklch(lch)

        # Pridej zlaty akcent na hornich 30 % siluety (ramena/koruna)
        ys, xs = np.nonzero(m)
        if len(ys):
            y_top = ys.min()
            y_cutoff = y_top + max(2, (ys.max() - y_top) // 4)
            top_mask = m.copy()
            top_mask[y_cutoff:] = False
            # Najdi nejjasnejsi pixely v teto horni oblasti a dej jim zlaty nadech
            top_ys, top_xs = np.nonzero(top_mask)
            if len(top_ys):
                gold = np.array([255, 204, 0], dtype=np.uint8)
                # Vyber 2-4 nejjasnejsi pixely
                top_rgbs = out[top_ys, top_xs, :3]
                top_l = to_oklab(top_rgbs)[..., 0]
                brightest_idx = np.argsort(top_l)[-max(1, len(top_l) // 6):]
                out[top_ys[brightest_idx], top_xs[brightest_idx], :3] = gold

    elif tier >= 3:
        # Tier 3 — Elite / Boss
        body = (lch[..., 1] >= 0.025) & (lch[..., 0] >= 0.16)
        lch[body, 1] = np.clip(lch[body, 1] * 1.45, 0.0, 0.42)
        # Posun jemne do sytosti a dramatu
        lch[body, 0] = np.clip(np.where(lch[body, 0] > 0.5, lch[body, 0] * 1.12, lch[body, 0] * 0.92), 0.10, 0.98)

        out[..., :3][m] = from_oklch(lch)

        # 1px svetelny lem na horni/leve strane (rim light)
        ys, xs = np.nonzero(m)
        if len(ys):
            # Pro kazdy pixel na okraji, ktery ma volno nahore nebo vlevo
            aura_color = np.array([255, 235, 120], dtype=np.uint8)  # zariva aura
            for y, x in zip(ys, xs):
                is_top_or_left_edge = (y == 0 or not m[y - 1, x]) or (x == 0 or not m[y, x - 1])
                if is_top_or_left_edge and out[y, x, 3] > 32:
                    # Jen na ne-obrysovych nebo vnejsich obrysovych pixelech
                    cur_l = to_oklab(out[y:y+1, x:x+1, :3])[0, 0, 0]
                    if cur_l > 0.15:
                        out[y, x, :3] = aura_color

    return out


# ------------------------------------------------------------------ CLI


def main():
    import argparse
    from PIL import Image

    ap = argparse.ArgumentParser(description="Paletové proměny a varianty spritů bez AI.")
    ap.add_argument("sprite", help="cesta ke sprite PNG")
    ap.add_argument("mode", choices=["target", "shift", "tier2", "tier3", "swap"],
                    help="režim proměny")
    ap.add_argument("param", nargs="?", default="",
                    help="hex barva pro target/swap, stupně pro shift")
    ap.add_argument("--to", dest="to_color", default="", help="cílová barva pro swap")
    ap.add_argument("--out", "-o", default=None, help="výstupní soubor")
    args = ap.parse_args()

    a = np.array(Image.open(args.sprite).convert("RGBA"))

    if args.mode == "target":
        res = recolor_target(a, args.param or "#ff3b30")
    elif args.mode == "shift":
        deg = float(args.param or 60.0)
        res = recolor_shift(a, deg)
    elif args.mode == "tier2":
        res = tier_upgrade(a, tier=2)
    elif args.mode == "tier3":
        res = tier_upgrade(a, tier=3)
    elif args.mode == "swap":
        res = skin_swap(a, args.param, args.to_color or "#00ffcc")
    else:
        sys.exit(f"neznámý režim: {args.mode}")

    out_path = args.out or os.path.splitext(args.sprite)[0] + f"_{args.mode}.png"
    Image.fromarray(res, "RGBA").save(out_path)
    print(f"uloženo do: {out_path}")


if __name__ == "__main__":
    main()
