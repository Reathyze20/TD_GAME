"""Generate the read-only ASCII side-car for every level in data/levels/.

    python tools/level_to_ascii.py            # write docs/levels/<id>.md
    python tools/level_to_ascii.py --check    # exit 1 if any side-car is stale

WHAT THIS IS, AND WHAT IT IS NOT (docs/refactor/PATHFINDING.MD P0/P0b)

The `.tres` stays authoritative. This file is DERIVED: it exists so a level can be read
and diffed as text, and the game never loads it. That direction is the whole point of the
decision recorded in BLOCKED.md under P0 — a side-car can go stale without breaking the
game (you get a wrong diff, not a wrong game), whereas an authoritative ASCII format would
turn every gap in its coverage into silent data loss in shipped content.

SCOPE: exactly the geometry `MapEditor._bake_to_level()` owns and nothing else —
`objective`, `spawn_zones`, `high_ground`, `path_cells`. `decor` (positions are Vector2 in
field PIXELS, i.e. sub-cell) and `tile_overrides` (dozens of art names, past any glyph
alphabet) are deliberately absent; they cannot be made to fit and must not be forced.

WHY THE FILE CARRIES BOTH A GRID AND A FIELD LIST

The grid is the picture: one character per cell, so a wall moving is one character moving.
The field list is the data: the arrays exactly as the `.tres` holds them, order and
duplicates included.

The grid alone cannot be lossless, for two reasons found in the shipped data:

  * `path_cells` ORDER is not row-major. `level_98.tres` runs down the left column and
    then across the top row; a row-major scan of the grid reproduces a different array.
  * `path_cells` can hold DUPLICATES — `level_98.tres` lists `Vector2i(25, 2)` twice. A
    grid is a set and would drop that silently, which is exactly the failure P0b names.
    (Whether the duplicate is intentional is P0c's question, not this tool's. This tool's
    job is to not hide it.)

So the list is what the round-trip parser reads, and the grid is a RENDERING of the list
that `_test_ascii_sidecar` checks cell by cell. The redundancy is the feature: the picture
cannot silently disagree with the data, because a test fails when it does.
"""
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEVELS_DIR = os.path.join(ROOT, "data", "levels")
OUT_DIR = os.path.join(ROOT, "docs", "levels")

# Glyph precedence, highest first. A cell can belong to several layers at once —
# level_98's spawn rect and its lane share (0, 6) and (0, 7) — so a single grid needs a
# stated winner per cell, and the round-trip check applies the same order.
GLYPHS = [("objective", "O"), ("high_ground", "#"), ("spawn", "S"), ("path", "~")]
EMPTY = "."
ALPHABET = "".join(g for _, g in GLYPHS) + EMPTY

WRAP = 10          # entries per line in the field list; keeps a one-cell edit a one-line diff
INDENT = "    "    # continuation lines start with whitespace, so the parser can join them


def grid_dims():
    """cols/rows from scripts/data.gd's `const GRID`, so this tool cannot drift from it."""
    text = io.open(os.path.join(ROOT, "scripts", "data.gd"), encoding="utf-8").read()
    m = re.search(r"const GRID := \{(.*?)\}", text, re.S)
    if not m:
        raise SystemExit("level_to_ascii: could not find `const GRID` in scripts/data.gd")
    body = m.group(1)
    dims = {}
    for key in ("cols", "rows"):
        km = re.search(r'"%s"\s*:\s*(\d+)' % key, body)
        if not km:
            raise SystemExit("level_to_ascii: `const GRID` has no %r" % key)
        dims[key] = int(km.group(1))
    return dims["cols"], dims["rows"]


def _resource_block(path):
    text = io.open(path, encoding="utf-8").read()
    i = text.find("[resource]")
    return text[i:] if i >= 0 else text


def _field(block, name):
    """Raw right-hand side of `name = ...` in the [resource] block, or '' when absent.

    Absent means the script default applies — LevelData defaults every field this tool
    reads to zero/empty, so '' parses to the same thing Godot would load.
    """
    m = re.search(r"^%s = (.*)$" % re.escape(name), block, re.M)
    return m.group(1) if m else ""


def _vec2i_list(raw):
    return [(int(x), int(y)) for x, y in re.findall(r"Vector2i\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)", raw)]


def _rect2i_list(raw):
    return [(int(a), int(b), int(c), int(d)) for a, b, c, d in re.findall(
        r"Rect2i\(\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*\)", raw)]


def parse_level(path):
    block = _resource_block(path)
    raw_id = _field(block, "id").strip()
    raw_name = _field(block, "display_name").strip()
    obj = _vec2i_list(_field(block, "objective"))
    return {
        "file": os.path.basename(path),
        # LevelData's own defaults, for the fields a .tres may leave out entirely —
        # level_1.tres writes neither `id` nor `focus`, and reading it as 0 would name
        # its side-car docs/levels/0.md.
        "id": int(raw_id) if raw_id else 1,
        "display_name": raw_name.strip('"') if raw_name else "Level 1",
        "objective": obj[0] if obj else (0, 0),
        "spawn_zones": _rect2i_list(_field(block, "spawn_zones")),
        "high_ground": _vec2i_list(_field(block, "high_ground")),
        "path_cells": _vec2i_list(_field(block, "path_cells")),
    }


def spawn_cells(level):
    """Cells covered by the spawn rects, for RENDERING only.

    The rects themselves are written out verbatim and are what the parser reads back.
    Deriving them from the grid instead would be lossy in exactly the way P0b warns about:
    `level_1` carries Rect2i(0, 5, 1, 4) and `level_98` Rect2i(0, 6, 1, 2), neither of
    which is a 3x3 block, so a re-blocking reader would hand back different rectangles
    than the ones that were baked.
    """
    out = []
    for x, y, w, h in level["spawn_zones"]:
        for dy in range(max(h, 1)):
            for dx in range(max(w, 1)):
                out.append((x + dx, y + dy))
    return out


def render_grid(level, cols, rows):
    layers = {
        "objective": {level["objective"]},
        "high_ground": set(level["high_ground"]),
        "spawn": set(spawn_cells(level)),
        "path": set(level["path_cells"]),
    }
    lines = []
    for y in range(rows):
        row = []
        for x in range(cols):
            glyph = EMPTY
            for name, ch in GLYPHS:
                if (x, y) in layers[name]:
                    glyph = ch
                    break
            row.append(glyph)
        lines.append("".join(row))
    return lines


def _wrap(entries):
    if not entries:
        return ["(none)"]
    chunks = [entries[i:i + WRAP] for i in range(0, len(entries), WRAP)]
    return [" ".join(chunks[0])] + [INDENT + " ".join(c) for c in chunks[1:]]


def _pairs(cells):
    return ["(%d,%d)" % c for c in cells]


def _rects(rects):
    return ["(%d,%d,%d,%d)" % r for r in rects]


def render(level, cols, rows):
    out = []
    out.append("# Level %d — %s" % (level["id"], level["display_name"]))
    out.append("")
    out.append("Generated by `tools/level_to_ascii.py` from `data/levels/%s`." % level["file"])
    out.append("DO NOT EDIT. The `.tres` is authoritative; this is a read-only side-car and")
    out.append("the game never loads it. `verify.sh` fails when the two drift apart.")
    out.append("")
    out.append("- source: `data/levels/%s`" % level["file"])
    out.append("- id: %d" % level["id"])
    out.append("- grid: %dx%d" % (cols, rows))
    out.append("")

    oob = [c for c in level["high_ground"] + level["path_cells"] + [level["objective"]]
           if not (0 <= c[0] < cols and 0 <= c[1] < rows)]
    if oob:
        # Worth its own line rather than a silent omission: a geometry cell outside the
        # grid is the exact defect that made level_1/level_2 throw "out of bounds" from
        # AStarGrid2D and put seven fixtures on verify.sh's known-broken list.
        out.append("> **%d cell(s) lie outside the grid** and therefore do not appear in the"
                   % len(oob))
        out.append("> picture below. They are still listed under Fields, which is the")
        out.append("> authoritative half: %s" % " ".join(_pairs(sorted(set(oob)))))
        out.append("")

    out.append("## Grid")
    out.append("")
    out.append("One character per cell. Precedence, highest first: `O` objective, `#` high")
    out.append("ground, `S` spawn, `~` lane, `.` empty — a cell in several layers shows the")
    out.append("first of those it belongs to.")
    out.append("")
    out.append("```")
    out.extend(render_grid(level, cols, rows))
    out.append("```")
    out.append("")
    out.append("## Fields")
    out.append("")
    out.append("The arrays exactly as `data/levels/%s` holds them — original order, and" % level["file"])
    out.append("duplicates kept. This half is what the round-trip parser reads.")
    out.append("")
    out.append("objective: %s" % _pairs([level["objective"]])[0])
    for line in _wrap(_rects(level["spawn_zones"])):
        out.append(("spawn_zones: " + line) if not line.startswith(INDENT) else line)
    for key in ("high_ground", "path_cells"):
        for line in _wrap(_pairs(level[key])):
            out.append(("%s: %s" % (key, line)) if not line.startswith(INDENT) else line)
    out.append("")
    return "\n".join(out)


def level_files():
    if not os.path.isdir(LEVELS_DIR):
        return []
    return sorted(os.path.join(LEVELS_DIR, f) for f in os.listdir(LEVELS_DIR)
                  if f.endswith(".tres"))          # .bak/.bak2 are backups, not content


def build_all():
    cols, rows = grid_dims()
    out = {}
    for path in level_files():
        level = parse_level(path)
        name = "%d.md" % level["id"]
        if name in out:
            raise SystemExit("level_to_ascii: two levels claim id %d — %s and %s"
                             % (level["id"], out[name][0], level["file"]))
        out[name] = (level["file"], render(level, cols, rows))
    return out


def main(argv):
    check = "--check" in argv
    wanted = build_all()
    if not os.path.isdir(OUT_DIR):
        if check:
            print("FAIL: docs/levels/ does not exist — run `python tools/level_to_ascii.py`")
            return 1
        os.makedirs(OUT_DIR)

    on_disk = {f for f in os.listdir(OUT_DIR) if f.endswith(".md")} if os.path.isdir(OUT_DIR) else set()
    problems = []

    for name, (src, text) in sorted(wanted.items()):
        path = os.path.join(OUT_DIR, name)
        current = io.open(path, encoding="utf-8", newline="").read() if os.path.exists(path) else None
        if current == text:
            if not check:
                print("ok    docs/levels/%s (from %s)" % (name, src))
            continue
        if check:
            problems.append("docs/levels/%s is stale or hand-edited (from %s)" % (name, src))
        else:
            io.open(path, "w", encoding="utf-8", newline="").write(text)
            print("write docs/levels/%s (from %s)" % (name, src))

    for name in sorted(on_disk - set(wanted)):
        # An orphan side-car outlives the level it described and would keep claiming a
        # level that no longer exists — the same "looks like coverage, verifies nothing"
        # failure as an orphaned _test_*.gd.
        if check:
            problems.append("docs/levels/%s has no matching level in data/levels/" % name)
        else:
            os.remove(os.path.join(OUT_DIR, name))
            print("rm    docs/levels/%s (no matching level)" % name)

    if check:
        if problems:
            for p in problems:
                print("FAIL: %s" % p)
            print("Run `python tools/level_to_ascii.py` and commit the result.")
            return 1
        print("ok: %d side-car(s) match data/levels/" % len(wanted))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
