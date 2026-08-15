"""Install the regenerated tower art: 8 pieces (base + 7 heads) at 24px source, replacing
the 16px originals. See docs/PIXELLAB.md for why 24px: tower.gd fits head/base art to the
cell with `zoom = floor(48 / tex_width)`, so 16px -> x3 and 24px -> x2 land on the same
48px on-screen footprint — only the pixel density changes. 24px matches the enemies' art
pixel : screen pixel ratio (they moved to 32px source at x2 in the same pass).

Run from the scratchpad session that generated tower_out/ and tower_anim/, e.g.:
    python tools/install_towers.py <scratchpad>/tower_out <scratchpad>/tower_anim
"""
import os
import sys
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import sprite_16 as S

DEST = os.path.join(os.path.dirname(__file__), "..", "assets", "towers")

FRAME_COUNTS = {
    "head_focus_timer": 9, "head_focus_timer_2": 7, "head_anchor": 9,
    "head_mindfulness": 9, "head_exercise": 7, "head_accountability": 7,
    "head_real_hobby": 9,
}


def install(static_dir, anim_dir):
    written = []

    # tower_base has no animation — the single static piece.
    src = Image.open(os.path.join(static_dir, "tower_base_210.png")).convert("RGBA")
    S.halve(src, 24).save(os.path.join(DEST, "tower_base.png"))
    written.append("tower_base.png")

    for name, n in FRAME_COUNTS.items():
        static_src = Image.open(os.path.join(static_dir, "%s.png" % name)).convert("RGBA")
        S.halve(static_src, 24).save(os.path.join(DEST, "%s.png" % name))
        written.append("%s.png" % name)
        for i in range(n):
            im = Image.open(os.path.join(anim_dir, "%s_%d.png" % (name, i))).convert("RGBA")
            S.halve(im, 24).save(os.path.join(DEST, "%s_frame_%d.png" % (name, i + 1)))
            written.append("%s_frame_%d.png" % (name, i + 1))

    return written


def sweep(written):
    """Old 16px frame counts differ from the new ones (all now n+1 from animate_image's
    input-frame-included output), so stale extra frames must go or a shorter loop plays
    a leftover 16px frame at the tail."""
    gone = []
    keep_bases = {"tower_base"} | set(FRAME_COUNTS)
    for f in os.listdir(DEST):
        if f.endswith(".import"):
            continue
        base = f.split("_frame_")[0]
        if base in keep_bases and f not in written:
            os.remove(os.path.join(DEST, f))
            imp = os.path.join(DEST, f + ".import")
            if os.path.exists(imp):
                os.remove(imp)
            gone.append(f)
    return gone


if __name__ == "__main__":
    static_dir, anim_dir = sys.argv[1], sys.argv[2]
    w = install(static_dir, anim_dir)
    g = sweep(w)
    print("wrote %d files" % len(w))
    print("removed %d stale files: %s" % (len(g), " ".join(sorted(g)[:10])))
