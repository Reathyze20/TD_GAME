import os
import glob
from PIL import Image, ImageFilter
import numpy as np
from collections import deque

def remove_background(img: Image.Image, bg_thresh=4) -> Image.Image:
    img = img.convert("RGBA")
    arr = np.array(img)
    h, w, _ = arr.shape
    
    # Identify background starting from borders
    visited = np.zeros((h, w), dtype=bool)
    q = deque()
    
    # Border sampling
    for y in range(h):
        for x in [0, w-1]:
            if (arr[y, x, :3] < bg_thresh).all():
                q.append((y, x))
                visited[y, x] = True
    for x in range(w):
        for y in [0, h-1]:
            if not visited[y, x] and (arr[y, x, :3] < bg_thresh).all():
                q.append((y, x))
                visited[y, x] = True
                
    while q:
        cy, cx = q.popleft()
        arr[cy, cx, 3] = 0
        for dy, dx in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            ny, nx = cy + dy, cx + dx
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx]:
                if (arr[ny, nx, :3] < bg_thresh).all():
                    visited[ny, nx] = True
                    q.append((ny, nx))
                    
    # Soft alpha feather on edge
    alpha = arr[:, :, 3]
    result = Image.fromarray(arr)
    return result

def extract_top_diamond(img_clean: Image.Image, out_size=(64, 32)) -> Image.Image:
    # Crop the top diamond region from the 1024x1024 slab
    # Top diamond roughly occupies x: [150, 874], y: [130, 580]
    w, h = img_clean.size
    # Bounding box of the slab
    bbox = img_clean.getbbox()
    if not bbox:
        return img_clean.resize(out_size, Image.Resampling.LANCZOS)
    
    # Top diamond center is around top 40% of the slab
    top_region = img_clean.crop((bbox[0] + 40, bbox[1] + 10, bbox[2] - 40, bbox[1] + int((bbox[3] - bbox[1]) * 0.52)))
    # Resize to exact 64x32
    diamond_tile = top_region.resize(out_size, Image.Resampling.LANCZOS)
    
    # Mask to exact 64x32 2:1 diamond
    mask = Image.new("L", out_size, 0)
    m_arr = np.array(mask)
    for y in range(32):
        for x in range(64):
            # Distance from center in diamond metric
            # normalized: |x - 31.5| / 32 + |y - 15.5| / 16 <= 1.0
            dx = abs(x - 31.5) / 32.0
            dy = abs(y - 15.5) / 16.0
            if dx + dy <= 1.02:
                m_arr[y, x] = 255
    diamond_tile.putalpha(Image.fromarray(m_arr))
    return diamond_tile

def extract_wall_texture(img_clean: Image.Image, out_size=(128, 64)) -> Image.Image:
    bbox = img_clean.getbbox()
    # Crop the front wall face (lower half of the slab)
    wall_crop = img_clean.crop((bbox[0] + 60, bbox[1] + int((bbox[3] - bbox[1]) * 0.40), bbox[2] - 60, bbox[3] - 10))
    wall_tex = wall_crop.resize(out_size, Image.Resampling.LANCZOS)
    return wall_tex

def main():
    os.makedirs("assets/terrain/iso", exist_ok=True)
    os.makedirs("assets/iso_pilot", exist_ok=True)
    
    slabs = sorted(glob.glob("assets/src/incoming_tiles/new_mj/slab_*.png"))
    print(f"Processing {len(slabs)} slabs...")
    
    for i, slab_path in enumerate(slabs, 1):
        raw = Image.open(slab_path)
        clean = remove_background(raw, bg_thresh=22)
        
        # Save transparent clean full-res
        clean.save(f"assets/terrain/iso/synaptic_slab_{i}_clean.png")
        
        # Save scaled 3D pedestal (192x192 - perfect for 3x3 build block preview or tower base)
        bbox = clean.getbbox()
        cropped = clean.crop(bbox)
        # Pad to square
        max_dim = max(cropped.width, cropped.height)
        sq = Image.new("RGBA", (max_dim, max_dim), (0, 0, 0, 0))
        sq.paste(cropped, ((max_dim - cropped.width) // 2, (max_dim - cropped.height) // 2))
        pedestal_192 = sq.resize((192, 192), Image.Resampling.LANCZOS)
        pedestal_192.save(f"assets/terrain/iso/pedestal_synaptic_{i}.png")
        
        # Extract 64x32 floor diamond tile
        tile_64x32 = extract_top_diamond(clean, (64, 32))
        tile_64x32.save(f"assets/terrain/iso/floor_synaptic_{i}.png")
        
        if i == 1:
            tile_64x32.save("assets/iso_pilot/floor_tile.png")
        elif i == 2:
            tile_64x32.save("assets/iso_pilot/floor_tile_v2.png")
        elif i == 3:
            tile_64x32.save("assets/iso_pilot/floor_tile_v3.png")
            
        # Extract wall texture from slab 1 and 2
        if i in [1, 2]:
            wall_tex = extract_wall_texture(clean, (128, 64))
            wall_tex.save(f"assets/terrain/iso/wall_synaptic_{i}.png")
            if i == 1:
                wall_tex.save("assets/iso_pilot/wall_material.png")
                
        print(f"Processed slab {i}: Saved clean, pedestal, floor tile, and wall textures.")

if __name__ == "__main__":
    main()
