extends Node
## Maze-validity smoke test (docs/refactor/MIGRATION.MD T10). Render-independent — no
## Game instantiation, unlike scripts/_test_levels.gd's live A* check of the same
## underlying question. See scripts/level_validator.gd's header for why "the player
## can wall off the path" is a structural property of AUTHORED high_ground, not a
## live mechanic to simulate.
##
## Levely, o kterych uz vime, ze jsou rozbite, jsou v KNOWN_BROKEN — stejny dluh, stejny
## duvod, jako v _test_levels.gd. Nejsou to vyjimky pro pohodli, je to seznam dluhu,
## ktery ma jednou byt prazdny; drzet ho v obou souborech synchronizovany je zamerne
## levnejsi nez sdilet ho pres preload, protoze kazdy soubor zustava citelny sam o sobe.

## 2026-08-29: both entries removed. id 2's level (level_2.tres) no longer exists at
## all (T5 topdown migration deleted every pre-migration level, see BLOCKED.md's T5
## entry), and id 1 is now a freshly-built placeholder with a valid in-bounds
## objective — neither is "the same debt, still there", so keeping either row would
## have this dict silently skip validating levels that are not actually broken.
const KNOWN_BROKEN := {}

var completed := false
var fails := 0

func _ready() -> void:
	var wd := Timer.new()
	wd.wait_time = 30.0
	wd.one_shot = true
	add_child(wd)
	wd.timeout.connect(func():
		if not completed:
			print("FAILED: watchdog fired")
			get_tree().quit(1))
	wd.start()
	call_deferred("_run")

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok   %s %s" % [label, detail])
	else:
		fails += 1
		print("  FAIL %s %s" % [label, detail])

func _run() -> void:
	print("== every level in data/levels/ ==")
	var broken_seen := {}
	for i in range(Data.get_level_count()):
		var lv: LevelData = Data.get_level(i)
		print("\n-- [%d] %s (id %d)" % [i, lv.display_name, lv.id])

		if KNOWN_BROKEN.has(lv.id):
			broken_seen[lv.id] = true
			print("     ZNAMY DLUH: %s" % KNOWN_BROKEN[lv.id])
			continue

		var bad := LevelValidator.unreachable_spawn_cells(lv)
		_check("kazda spawn bunka ma cestu do cile", bad.is_empty(),
			"" if bad.is_empty() else "%d bunek bez cesty: %s" % [bad.size(), bad.slice(0, 5)])

	print("")
	for id in KNOWN_BROKEN.keys():
		var still: bool = broken_seen.has(id)
		_check("znamy dluh id %d je stale v datech" % id, still,
			"" if still else "uz neexistuje - smaz radek z KNOWN_BROKEN (v obou testech)")

	print("\n== validator actually detects a sealed maze (not just a rubber stamp) ==")
	# A synthetic level, built in memory: 10x10 usable area (Data.GRID is 24x24, so
	# these coordinates are safely inside it), objective at (5,5), a spawn zone at
	# (0,0)-(1,1), and a high_ground wall that COMPLETELY encircles the objective
	# except the test below opens/closes one gap in it.
	var objective := Vector2i(5, 5)
	var sealed := LevelData.new()
	sealed.objective = objective
	sealed.spawn_zones = [Rect2i(0, 0, 1, 1)]
	var ring: Array[Vector2i] = []
	for x in range(4, 7):
		for y in range(4, 7):
			var c := Vector2i(x, y)
			if c != objective:
				ring.append(c)
	sealed.high_ground = ring
	var sealed_bad := LevelValidator.unreachable_spawn_cells(sealed)
	_check("a spawn cell fully walled off from the objective IS flagged",
		sealed_bad.has(Vector2i(0, 0)), str(sealed_bad))
	_check("is_fully_reachable agrees the sealed level is broken",
		not LevelValidator.is_fully_reachable(sealed))

	var open_level := LevelData.new()
	open_level.objective = objective
	open_level.spawn_zones = [Rect2i(0, 0, 1, 1)]
	var ring_with_gap: Array[Vector2i] = ring.duplicate()
	ring_with_gap.erase(Vector2i(5, 4))  # one gap directly north of the objective
	open_level.high_ground = ring_with_gap
	_check("opening exactly one gap in the same ring makes it reachable again",
		LevelValidator.is_fully_reachable(open_level),
		str(LevelValidator.unreachable_spawn_cells(open_level)))

	completed = true
	print("\n%s (%d failures)" % ["PASSED" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
