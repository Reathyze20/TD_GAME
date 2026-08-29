extends Node
## Snimek STRELBY: vez, ktera prave pali, i s letici strelou.
##
## Existuje proto, ze tri veci se daji posoudit jedine na obrazku, kde uz neco leti:
##   * zablesk u USTI hlavne (ne na zemi pod vezi)  -- tower.gd, muzzle flash
##   * zpetny raz osmismerne hlavy                   -- driv ho dostavaly jen head_aims
##   * rajcatko jako projektil                       -- assets/towers/shot_focus_timer.png
##
## NE --headless, je to na divani. A POUSTET V 1920x1080, viz nize.
##   godot --path <proj> --main-scene res://scenes/_shot_fire.tscn --resolution 1920x1080

var _done := false
var _splat_at := Vector2.ZERO

## Prave hrajici ImpactFX v prvni tretine zivota -- tam je splat nejvic videt.
func _live_splat(game: Game) -> Node2D:
	for n in game.get_children():
		if n is ImpactFX and n.visible and n._progress > 0.04 and n._progress < 0.45:
			return n
	for holder in game.get_children():
		for n in holder.get_children():
			if n is ImpactFX and n.visible and n._progress > 0.04 and n._progress < 0.45:
				return n
	return null

func _ready() -> void:
	GameState.max_focus = 999999
	GameState.focus = 999999
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == 98:
			GameState.current_level_index = i
			break
	GameState.designer_mode = true
	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	var wd := Timer.new(); wd.wait_time = 90.0; wd.one_shot = true
	wd.timeout.connect(func():
		if not _done: print("SHOT FAILED"); get_tree().quit(1))
	add_child(wd); wd.start()
	await get_tree().process_frame

	GameState.dopamine = 100000
	GameState.bandwidth_used = 0
	# Vsechna mista, at je sance, ze nekterá vez na cestu dosahne.
	var built := 0
	for sp: Vector2i in game.build_spots.keys():
		if built >= 10:
			break
		GameState.selected_habit = "focus_timer"
		game._hover_cell = sp
		if not game._can_build(sp):
			continue
		game._build_on(sp)
		if game.is_aiming:
			game._end_aiming()
		built += 1
	print("postaveno %d vezi" % built)

	# Vlnu spousti _on_start_wave_pressed(), ne _start_wave(): teprve ta nastavi
	# started/between_waves, a bez nich je board_live nepravda a veze nesmi palit.
	game._on_start_wave_pressed()
	# Ceka se na PROJEKTIL, ne na cas: snimek bez letici strely tenhle harness nema smysl.
	var frames := 0
	var peak := 0
	while frames < 3600:
		await get_tree().process_frame
		frames += 1
		peak = maxi(peak, game._live_projectiles.size())
		if frames % 300 == 0:
			var lit := 0
			var rest := 0
			for sp in game.build_spots.values():
				if sp.state == BuildSpot.State.BUILT and is_instance_valid(sp.current_habit):
					if sp.current_habit.in_routine: lit += 1
					if sp.current_habit.has_method("is_resting") and sp.current_habit.is_resting(): rest += 1
			print("  f%4d  nepratel %d  videt %s  started %s  mezi vlnami %s  projektilu %d (max %d)  Routine %d"
				% [frames, game.get_live_distractions().size(),
				   str(game.has_visible_distraction()), str(game.started),
				   str(game.between_waves), game._live_projectiles.size(), peak, lit])
		# Ceka se na ZASAH, ne na strelu: splat je to, co se ma posoudit.
		var hit := _live_splat(game)
		if hit != null:
			print("splat @ %d,%d" % [hit.global_position.x, hit.global_position.y])
			_splat_at = hit.global_position
			break
	print("snimek pri %d projektilech (po %d snimcich)" % [game._live_projectiles.size(), frames])
	for p in game._live_projectiles:
		if is_instance_valid(p):
			print("  projektil @ %d,%d" % [p.global_position.x, p.global_position.y])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/_fire_board.png")
	print("SPLAT_AT %d,%d" % [_splat_at.x, _splat_at.y])
	print("SHOT build/_fire_board.png")
	_done = true
	get_tree().quit(0)
