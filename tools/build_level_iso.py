"""Generates data/levels/level_iso.tres for the isometric vertical slice."""
import os

def generate_level_iso():
    # 24x24 cells (8x8 blocks of 3x3)
    # Objective at block (7, 4) center => (22, 13)
    # Spawn at block (0, 3) and (0, 4) => Rect2i(0, 9, 3, 6)
    
    # High ground blocks: list of (bx, by)
    # Each block (bx, by) expands to 9 cells: (bx*3 + dx, by*3 + dy) for dx,dy in 0..2
    hg_blocks = [
        (2, 1), (2, 2), (2, 4), (2, 6),
        (3, 4), (4, 1), (4, 2), (4, 4), (4, 6),
        (5, 1), (5, 6),
        (6, 2), (6, 3), (6, 5), (6, 6)
    ]
    
    high_ground = []
    for bx, by in hg_blocks:
        for dy in range(3):
            for dx in range(3):
                high_ground.append((bx * 3 + dx, by * 3 + dy))
    
    # Path connecting spawn (0, 10..11) to objective (22, 13)
    # Path goes:
    # (0..9, 10..11) -> down/up to (9..11, 4..5) -> east to (15..17, 4..5) -> south to (15..17, 12..14) -> east to (21..23, 12..14)
    # Let's generate a clear set of path cells
    path_set = set()
    
    # Corridor 1: (0..9, 9..11)
    for x in range(0, 10):
        for y in range(9, 12):
            path_set.add((x, y))
            
    # Turn 1 North: (7..9, 3..11)
    for x in range(7, 10):
        for y in range(3, 12):
            path_set.add((x, y))
            
    # Corridor 2 East: (7..18, 3..5)
    for x in range(7, 19):
        for y in range(3, 6):
            path_set.add((x, y))
            
    # Turn 2 South: (16..18, 3..14)
    for x in range(16, 19):
        for y in range(3, 15):
            path_set.add((x, y))
            
    # Corridor 3 East to Objective: (16..23, 12..14)
    for x in range(16, 24):
        for y in range(12, 15):
            path_set.add((x, y))
            
    # Remove any overlap with high ground
    hg_set = set(high_ground)
    path_cells = [c for c in sorted(path_set) if c not in hg_set]
    
    hg_formatted = ", ".join(f"Vector2i({x}, {y})" for x, y in sorted(high_ground))
    path_formatted = ", ".join(f"Vector2i({x}, {y})" for x, y in sorted(path_cells))
    
    content = f"""[gd_resource type="Resource" script_class="LevelData" format=3]

[ext_resource type="Script" path="res://scripts/resources/level_data.gd" id="1_iso"]
[ext_resource type="Script" path="res://scripts/resources/wave_curve_entry_data.gd" id="2_curve"]
[ext_resource type="Resource" path="res://data/distractions/notification.tres" id="3_notif"]
[ext_resource type="Resource" path="res://data/distractions/energy_drink.tres" id="4_energy"]

[sub_resource type="Resource" id="Resource_notif"]
script = ExtResource("2_curve")
distraction = ExtResource("3_notif")
base_count = 6
growth_per_wave = 3.0
spacing = 0.7

[sub_resource type="Resource" id="Resource_energy"]
script = ExtResource("2_curve")
distraction = ExtResource("4_energy")
from_wave = 2
base_count = 3
growth_per_wave = 2.0
spacing = 1.2

[resource]
script = ExtResource("1_iso")
id = 99
display_name = "Isometric Vertical Slice"
start_dopamine = 350
focus = 20
quick_hit = false
objective = Vector2i(22, 13)
spawn_zones = Array[Rect2i]([Rect2i(0, 9, 3, 3)])
high_ground = Array[Vector2i]([{hg_formatted}])
path_cells = Array[Vector2i]([{path_formatted}])
wave_count = 5
wave_curve = Array[ExtResource("2_curve")]([SubResource("Resource_notif"), SubResource("Resource_energy")])
"""
    
    out_path = os.path.join(os.path.dirname(__file__), "..", "data", "levels", "level_iso.tres")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"Generated {out_path} with {len(high_ground)} hg cells and {len(path_cells)} path cells.")

if __name__ == "__main__":
    generate_level_iso()
