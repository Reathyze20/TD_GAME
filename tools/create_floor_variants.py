"""Generates subtle floor tile variants to prevent wallpaper repetition in iso grid."""
from PIL import Image, ImageDraw
import random

def create_variants():
    base = Image.open("assets/iso_pilot/floor_tile.png").convert("RGBA")
    w, h = base.size
    
    # Variant 2: subtle warm tint / tiny flecks
    v2 = base.copy()
    v2_pixels = v2.load()
    random.seed(42)
    for y in range(h):
        for x in range(w):
            r, g, b, a = v2_pixels[x, y]
            if a > 0:
                noise = random.randint(-4, 4)
                v2_pixels[x, y] = (
                    max(0, min(255, r + noise + 2)),
                    max(0, min(255, g + noise)),
                    max(0, min(255, b + noise - 2)),
                    a
                )
    v2.save("assets/iso_pilot/floor_tile_v2.png")
    
    # Variant 3: subtle cool grain / small fissure line
    v3 = base.copy()
    v3_pixels = v3.load()
    random.seed(1337)
    for y in range(h):
        for x in range(w):
            r, g, b, a = v3_pixels[x, y]
            if a > 0:
                noise = random.randint(-5, 5)
                # Small faint fissure near middle
                if abs((x - 32) - (y - 16)*1.5) < 1.0 and 10 < x < 50:
                    noise -= 12
                v3_pixels[x, y] = (
                    max(0, min(255, r + noise - 2)),
                    max(0, min(255, g + noise)),
                    max(0, min(255, b + noise + 3)),
                    a
                )
    v3.save("assets/iso_pilot/floor_tile_v3.png")
    print("Created floor_tile_v2.png and floor_tile_v3.png")

if __name__ == "__main__":
    create_variants()
