extends Node
## T7 (docs/refactor/MIGRATION.MD): a readability squint-test set for every level —
## a representative in-play screenshot, plus blurred, desaturated, and silhouette
## (luminance-threshold) variants of it. "NEPOSUZUJ je — to udelam ja": this only
## generates the images, it does not judge them.
##
## NOT --headless: needs a real viewport texture, same as every other _shot_*.gd.
##   godot --path <proj> --main-scene res://scenes/_shot_readability.tscn

const OUT_DIR := ".dev/screenshots"
const CHEAP_TYPE := &"focus_timer"
const SETTLE_FRAMES := 150   ## ~2.5 sim-seconds after the wave starts — enough for a few enemies to walk into frame.
const SHOT_SIZE := Vector2i(640, 360)   ## Downscaled before the per-pixel passes — a squint test wants small anyway.

func _ready() -> void:
	var wd := Timer.new()
	wd.wait_time = 300.0
	wd.one_shot = true
	add_child(wd)
	wd.timeout.connect(func():
		print("FAILED: watchdog fired")
		get_tree().quit(1))
	wd.start()
	call_deferred("_run")

func _blur(img: Image, factor: int = 10) -> Image:
	var out: Image = img.duplicate()
	var w := out.get_width()
	var h := out.get_height()
	out.resize(maxi(1, w / factor), maxi(1, h / factor), Image.INTERPOLATE_BILINEAR)
	out.resize(w, h, Image.INTERPOLATE_BILINEAR)
	return out

func _desaturate(img: Image) -> Image:
	var out: Image = img.duplicate()
	out.convert(Image.FORMAT_RGBA8)
	for y in range(out.get_height()):
		for x in range(out.get_width()):
			var c := out.get_pixel(x, y)
			var lum := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			out.set_pixel(x, y, Color(lum, lum, lum, c.a))
	return out

func _silhouette(img: Image, threshold: float = 0.45) -> Image:
	var out: Image = img.duplicate()
	out.convert(Image.FORMAT_RGBA8)
	for y in range(out.get_height()):
		for x in range(out.get_width()):
			var c := out.get_pixel(x, y)
			var lum := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			var v := 0.0 if lum < threshold else 1.0
			out.set_pixel(x, y, Color(v, v, v, c.a))
	return out

func _save(img: Image, path: String) -> void:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	if img.save_png(path) != OK:
		printerr("_shot_readability: save failed: ", path)
		return
	print("_shot_readability: %s  %dx%d" % [path, img.get_width(), img.get_height()])

## Cheapest attack habit at every currently-buildable cell — same idea as
## SimStrategyCheapEven (S2/S3), inlined directly since this tool needs the game
## node kept alive afterward for the screenshot, not a full LevelSimulator.run().
func _build_cheap_towers(game: Game) -> void:
	var cost: int = Data.get_habit(CHEAP_TYPE).build_cost
	var cells: Array = []
	for cell: Vector2i in game.build_spots:
		var spot: BuildSpot = game.build_spots[cell]
		if spot.state == BuildSpot.State.EMPTY and game._can_build(cell):
			cells.append(cell)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x)
	for cell in cells:
		if GameState.dopamine < cost:
			break
		GameState.select_habit(CHEAP_TYPE)
		game._build_on(cell)

func _shoot_level(level_id: int) -> void:
	var level_index := -1
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == level_id:
			level_index = i
			break
	if level_index < 0:
		return

	GameState.current_level_index = level_index
	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	# Survive the destructive change_scene_to_file() teardown the same way S2's
	# LevelSimulator does — a level with the known objective-out-of-bounds defect
	# (levels 1/2, docs/core/16) can otherwise end the run mid-shot.
	SignalBus.game_over.disconnect(game._on_bus_game_over)
	SignalBus.game_over.connect(func(_v: bool): game.game_ended = true)
	GameState.max_focus = 999999
	GameState.focus = 999999
	GameState.designer_mode = false

	_build_cheap_towers(game)
	game._on_start_wave_pressed()

	for _f in range(SETTLE_FRAMES):
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var full := get_viewport().get_texture().get_image()
	full.resize(SHOT_SIZE.x, SHOT_SIZE.y, Image.INTERPOLATE_BILINEAR)

	var prefix := "%s/level_%d" % [OUT_DIR, level_id]
	_save(full, prefix + "_base.png")
	_save(_blur(full), prefix + "_blur.png")
	_save(_desaturate(full), prefix + "_gray.png")
	_save(_silhouette(full), prefix + "_silhouette.png")

	game.queue_free()
	await get_tree().process_frame

func _run() -> void:
	for i in range(Data.get_level_count()):
		var lv := Data.get_level(i)
		print("-- level %d (%s) --" % [lv.id, lv.display_name])
		await _shoot_level(lv.id)
	print("\ndone")
	get_tree().quit(0)
