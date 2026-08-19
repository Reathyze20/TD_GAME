# Izo dlaždice ze švové (tileable) čtvercové textury.
#
# CO SE ZKOUŠELO A NEFUNGOVALO (19. 8. 2026, pilot terénu):
#
#   1. PixelLab "Generate tileset (pro)" pro izometrii NEPOUŽÍVAT. Ten nástroj je
#      strukturálně top-down (lower/upper terrain, wall style, view = side/low top-down/
#      high top-down) — o izometrii vůbec neví. Viz docs/TILESETY.md, tam platí pro
#      čtvercové top-down dlaždice buňky 16px.
#
#   2. Přímé generování "isometric floor tile" v create_image_pixflux taky nefungovalo —
#      model to čte jako SAMOSTATNÝ OBJEKT (izolovaná plošina s vlastní boční stěnou na
#      černém pozadí, viz assets/src/pixel/iso_pilot/_rejected_pixflux_tiles/ pokud tam
#      ještě jsou), ne jako dlaždici zapadající do mřížky. Vydlážděním vznikaly mezery.
#
# CO FUNGUJE: generátor dodá ŠVOVÝ (seamless/tileable) čtvercový MATERIÁL, tenhle skript
# z něj vyřízne izometrický diamant. Stejný princip jako u zdi (wall_material.png) —
# generátor = materiál, kód = tvar. Diamant nemůže mít mezeru, protože se řeže podle
# přesně stejné 2:1 masky jako TileSet v iso_pilot.gd.
#
# ZDROJ: MidJourney s příponou --tile (bezešvá dlaždicovatelná textura), NE RD/PixelLab —
# na plochý materiál bez postavy je čistý BOX downscale lepší než RD (žádné halucinované
# detaily, žádný pixel-art postprocess co by sežral jemnou strukturu).
#
# PAST, KTERÁ STÁLA JEDNO KOLO: rotace o 45° natažená přes okraj zdrojového obrázku
# vtahuje ČERNOU z rohů dovnitř — na vydlážděném poli to vypadalo jako tmavá mřížka mezi
# dlaždicemi, i když ve skutečnosti žádná mezera nebyla (změřeno: pokrytí masky 53 %,
# 0 % děr). Oprava: než se otočí, zdroj se 3x3 zopakuje (funguje jen proto, že je opravdu
# švový), takže rotace má vždycky co vzorkovat a černá se do výřezu nikdy nedostane.

from PIL import Image
import numpy as np


def iso_mask(w: int = 64, h: int = 32) -> Image.Image:
    """Pixel-přesná 2:1 diamantová maska. Nekreslí se geometricky (anti-aliased polygon),
    ale po řádcích - stejný krok, jaký musí sedět na TileSet TILE_SHAPE_ISOMETRIC."""
    m = Image.new("L", (w, h), 0)
    px = m.load()
    for y in range(h):
        yy = y if y < h // 2 else h - 1 - y
        half = (yy + 1) * (w // h) // 2
        for x in range(w // 2 - half, w // 2 + half):
            px[x, y] = 255
    return m


def diamond_from_seamless(src: Image.Image, box: tuple[int, int, int, int],
                           tile_size: tuple[int, int] = (64, 32)) -> Image.Image:
    """Vyřízne jeden izo diamant ze čtvercového výřezu švové textury.

    src: celá zdrojová textura (musí být opravdu tileable, jinak vyjdou švy na 3x3 poli)
    box: (x0, y0, x1, y1) čtvercový výřez ve zdrojovém rozlišení
    """
    crop = src.crop(box)
    n = crop.size[0]
    # 3x3 dlaždice, ať má rotace vždycky co vzorkovat - viz past výš
    tiled = Image.new("RGB", (n * 3, n * 3))
    for gy in range(3):
        for gx in range(3):
            tiled.paste(crop, (gx * n, gy * n))
    rot = tiled.rotate(45, resample=Image.BICUBIC)  # bez expand - platno zůstává n*3
    c = n * 3 // 2
    half = n // 2
    center = rot.crop((c - half, c - half, c + half, c + half))
    w, h = tile_size
    squashed = center.resize((w, h), Image.LANCZOS)  # 2:1 = izo průmět na zem
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(squashed, (0, 0), iso_mask(w, h))
    return out


def make_variants(src_path: str, crops: list[tuple[int, int]], crop_size: int = 512,
                   tile_size: tuple[int, int] = (64, 32)) -> list[Image.Image]:
    src = Image.open(src_path).convert("RGB")
    out = []
    for cx, cy in crops:
        box = (cx, cy, cx + crop_size, cy + crop_size)
        out.append(diamond_from_seamless(src, box, tile_size))
    return out


def median_brightness(tile_rgba: Image.Image) -> float:
    a = np.array(tile_rgba)
    opaque = a[:, :, 3] > 0
    return float(np.median(a[:, :, :3][opaque].reshape(-1, 3).sum(axis=1)))


if __name__ == "__main__":
    import sys
    if len(sys.argv) < 3:
        print("použití: python iso_diamond_cut.py <zdroj.png> <out_dir> [pocet_variant]")
        raise SystemExit(1)
    src_path, out_dir = sys.argv[1], sys.argv[2]
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    import os
    os.makedirs(out_dir, exist_ok=True)
    src_im = Image.open(src_path).convert("RGB")
    W, H = src_im.size
    step = W // n
    crops = [(min(i * step, W - 512), min(0 if i % 2 == 0 else H - 512, H - 512)) for i in range(n)]
    variants = make_variants(src_path, crops)
    for i, v in enumerate(variants):
        p = os.path.join(out_dir, f"floor_variant_{i+1}.png")
        v.save(p)
        print(f"{p}  median sum(RGB)={median_brightness(v):.0f}")
