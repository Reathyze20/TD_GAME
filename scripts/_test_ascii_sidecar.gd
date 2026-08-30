extends Node
## Round-trip proof for the level side-cars (docs/refactor/PATHFINDING.MD P0b).
##
## The `.tres` is authoritative and `docs/levels/<id>.md` is derived, so the one thing
## that can go wrong is the derived half quietly saying something else. This parses each
## generated side-car back and compares it to the resource GODOT loaded — not to the
## Python parser's own idea of the file, which would only prove the tool agrees with
## itself.
##
## Two separate checks, because they fail for different reasons:
##
##  1. FIELDS round-trip exactly, order and duplicates included. `level_98.path_cells`
##     lists Vector2i(25, 2) twice and does not run row-major, so a set-shaped or
##     re-sorted side-car fails here — which is the point: P0b asks for that duplicate to
##     stay visible, and P0c decides whether it is a bug.
##  2. The GRID renders exactly those fields, cell by cell, under the documented glyph
##     precedence. The picture is redundant with the field list on purpose; this is what
##     stops the redundancy from rotting into a lie.

const SIDECAR_DIR := "res://docs/levels/"

## Highest precedence first — must match tools/level_to_ascii.py's GLYPHS.
const GLYPH_OBJECTIVE := "O"
const GLYPH_HIGH := "#"
const GLYPH_SPAWN := "S"
const GLYPH_PATH := "~"
const GLYPH_EMPTY := "."

var completed := false
var fails := 0

func _ok(label: String, cond: bool, detail: String = "") -> void:
	if not cond:
		fails += 1
	print(("  OK   " if cond else "  FAIL ") + label + ("  " + detail if detail != "" else ""))

func _cells_str(cells: Array) -> String:
	var parts: PackedStringArray = []
	for c in cells:
		parts.append("(%d,%d)" % [c.x, c.y])
	return " ".join(parts)

## Splits "objective: (28,7)" style sections, joining indented continuation lines.
func _parse_sidecar(text: String, cols: int, rows: int) -> Dictionary:
	var fields := {}
	var grid: PackedStringArray = []
	var section := ""
	var last_key := ""
	var row_re := RegEx.new()
	row_re.compile("^[%s%s%s%s\\%s]{%d}$" % [GLYPH_OBJECTIVE, GLYPH_HIGH, GLYPH_SPAWN,
		GLYPH_PATH, GLYPH_EMPTY, cols])
	var field_re := RegEx.new()
	field_re.compile("^([a-z_]+): (.*)$")

	for raw_line in text.split("\n"):
		var line := String(raw_line).trim_suffix("\r")
		if line.begins_with("## "):
			section = line.substr(3).strip_edges()
			last_key = ""
			continue
		if section == "Grid":
			if row_re.search(line) != null:
				grid.append(line)
			continue
		if section == "Fields":
			var m := field_re.search(line)
			if m != null:
				last_key = m.get_string(1)
				fields[last_key] = m.get_string(2)
			elif last_key != "" and line.begins_with(" ") and line.strip_edges() != "":
				fields[last_key] = String(fields[last_key]) + " " + line.strip_edges()
			elif line.strip_edges() == "":
				last_key = ""
	return {"fields": fields, "grid": grid}

func _read_cells(raw: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var re := RegEx.new()
	re.compile("\\((-?\\d+),(-?\\d+)\\)")
	for m in re.search_all(raw):
		out.append(Vector2i(int(m.get_string(1)), int(m.get_string(2))))
	return out

func _read_rects(raw: String) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var re := RegEx.new()
	re.compile("\\((-?\\d+),(-?\\d+),(-?\\d+),(-?\\d+)\\)")
	for m in re.search_all(raw):
		out.append(Rect2i(int(m.get_string(1)), int(m.get_string(2)),
			int(m.get_string(3)), int(m.get_string(4))))
	return out

func _expected_glyph(cell: Vector2i, level: LevelData, high: Dictionary, spawn: Dictionary,
		path: Dictionary) -> String:
	if cell == level.objective:
		return GLYPH_OBJECTIVE
	if high.has(cell):
		return GLYPH_HIGH
	if spawn.has(cell):
		return GLYPH_SPAWN
	if path.has(cell):
		return GLYPH_PATH
	return GLYPH_EMPTY

func _check_level(level: LevelData, cols: int, rows: int) -> void:
	var path := SIDECAR_DIR + "%d.md" % level.id
	print("--- level %d (%s) -> %s" % [level.id, level.display_name, path])
	if not FileAccess.file_exists(path):
		_ok("side-car exists", false, path)
		return
	_ok("side-car exists", true)

	var f := FileAccess.open(path, FileAccess.READ)
	var parsed := _parse_sidecar(f.get_as_text(), cols, rows)
	f.close()
	var fields: Dictionary = parsed["fields"]
	var grid: PackedStringArray = parsed["grid"]

	# --- 1. fields round-trip, exactly
	var got_obj := _read_cells(String(fields.get("objective", "")))
	_ok("objective round-trips", got_obj.size() == 1 and got_obj[0] == level.objective,
		"%s vs %s" % [str(got_obj), str(level.objective)])

	var got_zones := _read_rects(String(fields.get("spawn_zones", "")))
	var zones_ok := got_zones.size() == level.spawn_zones.size()
	if zones_ok:
		for i in range(got_zones.size()):
			if got_zones[i] != level.spawn_zones[i]:
				zones_ok = false
	# Verbatim rects, NOT re-derived from the grid: level_1 carries Rect2i(0, 5, 1, 4) and
	# level_98 Rect2i(0, 6, 1, 2), neither block-aligned, so a re-blocking reader would
	# hand back different rectangles than the ones that were baked.
	_ok("spawn_zones round-trip verbatim", zones_ok,
		"%s vs %s" % [str(got_zones), str(level.spawn_zones)])

	for key in ["high_ground", "path_cells"]:
		var got := _read_cells(String(fields.get(key, "")))
		var want: Array[Vector2i] = level.get(key)
		var same := got.size() == want.size()
		var first_diff := -1
		if same:
			for i in range(got.size()):
				if got[i] != want[i]:
					same = false
					first_diff = i
					break
		var detail := "%d vs %d entries" % [got.size(), want.size()]
		if first_diff >= 0:
			detail = "differ at index %d: %s vs %s" % [first_diff, str(got[first_diff]),
				str(want[first_diff])]
		_ok("%s round-trips in order, with duplicates" % key, same, detail)

	# --- 2. the grid renders exactly those fields
	_ok("grid has %d rows" % rows, grid.size() == rows, "%d" % grid.size())
	if grid.size() != rows:
		return

	var high := {}
	for c: Vector2i in level.high_ground:
		high[c] = true
	var spawn := {}
	for r: Rect2i in level.spawn_zones:
		for dy in range(maxi(r.size.y, 1)):
			for dx in range(maxi(r.size.x, 1)):
				spawn[Vector2i(r.position.x + dx, r.position.y + dy)] = true
	var lanes := {}
	for c: Vector2i in level.path_cells:
		lanes[c] = true

	var mismatches: Array[String] = []
	for y in range(rows):
		var row := String(grid[y])
		for x in range(cols):
			var cell := Vector2i(x, y)
			var want_glyph := _expected_glyph(cell, level, high, spawn, lanes)
			var got_glyph := row.substr(x, 1)
			if got_glyph != want_glyph:
				mismatches.append("(%d,%d) drawn '%s', fields say '%s'"
					% [x, y, got_glyph, want_glyph])
	_ok("grid matches the field list cell by cell", mismatches.is_empty(),
		"; ".join(mismatches.slice(0, 4)) if not mismatches.is_empty() else "")

func _ready() -> void:
	var t := Timer.new()
	t.wait_time = 30.0
	t.one_shot = true
	add_child(t)
	t.timeout.connect(func():
		if not completed:
			print("FAILED: watchdog")
			get_tree().quit(1))
	t.start()

	await get_tree().process_frame

	var cols: int = int(Data.GRID["cols"])
	var rows: int = int(Data.GRID["rows"])
	print("=== ascii side-car round-trip (grid %dx%d) ===" % [cols, rows])

	var count := Data.get_level_count()
	_ok("there are levels to check", count > 0, "%d" % count)
	for i in range(count):
		_check_level(Data.get_level(i), cols, rows)

	# An orphan side-car keeps describing a level that no longer exists — the same
	# "looks like coverage, verifies nothing" failure as an orphaned _test_*.gd script.
	var ids := {}
	for i in range(count):
		ids["%d.md" % Data.get_level(i).id] = true
	var orphans: Array[String] = []
	var dir := DirAccess.open(SIDECAR_DIR)
	if dir != null:
		for fname in dir.get_files():
			if fname.ends_with(".md") and not ids.has(fname):
				orphans.append(fname)
	_ok("no orphan side-cars in docs/levels/", orphans.is_empty(), ", ".join(orphans))

	completed = true
	if fails > 0:
		print("SOME CHECKS FAILED (%d)" % fails)
		get_tree().quit(1)
	else:
		print("ALL OK")
		get_tree().quit(0)
