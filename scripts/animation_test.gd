extends Node2D

# Testovací Level pro Animace Nepřátel (Animation Test Scene)
# Zobrazuje všechny typy nepřátel vedle sebe, umožňuje testovat jejich
# vektorové animace, pohyb po trati, spouštění zásahových bliknutí a aplikaci statusů.

var _distraction_keys: Array[String] = [
	"notification",
	"phantom_buzz",
	"autoplay",
	"doomscroll",
	"adult_content",
	"clickbait",
	"energy_drink",
	"jackpot",
	"social_media_binge"
]

var _spawned_enemies: Array[Distraction] = []
var _is_marching := false
var objective_pos: Vector2 = Vector2.ZERO

# Duck-typed as a "game" for Distraction (setup(mock_game, key) below) — P4 (docs/
# refactor/PATHFINDING.MD) moved live movement onto Game.flow_field, so this manual
# harness needs the same three fields Game exposes. `high_ground` stays empty (no walls
# in this showcase); `_march_field` is built once and only ASSIGNED to `flow_field`
# while marching — swapping it out again on pause reproduces the old set_cell_path([])
# "stop everyone in place" behaviour without a per-distraction pause flag.
var objective_cell: Vector2i = Vector2i(37, 9)
var high_ground := {}
var flow_field: FlowField = null
var _march_field: FlowField = null

# Node references
var _hud_layer: CanvasLayer
var _status_label: Label

func _ready() -> void:
	# Ensure Data autoload is ready
	GameState.current_level_index = 0

	# Row-9 corridor from col 2 to col 37 — wider than the real Data.GRID (30 cols), which
	# is fine: FlowField only needs bounds wide enough for ITS OWN board, not the live
	# game's.
	_march_field = FlowField.build(40, 12, objective_cell, {})

	objective_pos = cell_center(objective_cell)

	_setup_ui()
	_spawn_showcase_line()
	set_process(true)

func world_to_cell(pos: Vector2) -> Vector2i:
	return Data.world_to_cell(pos)

func spawn_distraction(type_key: String, spawn_cell: Vector2i) -> void:
	var enemy: Distraction = Distraction.new()
	if type_key == "social_media_binge":
		enemy = Boss.new()
	add_child(enemy)
	enemy.setup(self, type_key)
	enemy.position = cell_center(spawn_cell)
	enemy.current_cell = spawn_cell
	_spawned_enemies.append(enemy)

func _setup_ui() -> void:
	_hud_layer = CanvasLayer.new()
	add_child(_hud_layer)

	# Control Panel Container
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(400, 220)
	_hud_layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "🎬 TESTOVACÍ LEVEL ANIMACÍ & DETAILŮ (PIXEL ART)"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	var btn_hbox1 := HBoxContainer.new()
	btn_hbox1.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_hbox1)

	var btn_march := Button.new()
	btn_march.text = "▶ Spustit Pohyb (March)"
	btn_march.pressed.connect(_on_toggle_march)
	btn_hbox1.add_child(btn_march)

	var btn_reset := Button.new()
	btn_reset.text = "🔄 Obnovit Pozice"
	btn_reset.pressed.connect(_spawn_showcase_line)
	btn_hbox1.add_child(btn_reset)

	var btn_hbox2 := HBoxContainer.new()
	btn_hbox2.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_hbox2)

	var btn_hit := Button.new()
	btn_hit.text = "⚡ Zásahový Flash"
	btn_hit.pressed.connect(_on_trigger_hit_flash)
	btn_hbox2.add_child(btn_hit)

	var btn_slow := Button.new()
	btn_slow.text = "❄ Status Slow (Calm)"
	btn_slow.pressed.connect(_on_apply_slow)
	btn_hbox2.add_child(btn_slow)

	var btn_reframe := Button.new()
	btn_reframe.text = "💥 Status Reframe"
	btn_reframe.pressed.connect(_on_apply_reframe)
	btn_hbox2.add_child(btn_reframe)

	_status_label = Label.new()
	_status_label.text = "Stav: Zobrazeno 9 nepřátel s kompletním pixel artem a stíny."
	_status_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_status_label)

func cell_center(cell: Vector2i) -> Vector2:
	return Data.cell_center(cell)

func _spawn_showcase_line() -> void:
	# Clear existing
	for e in _spawned_enemies:
		if is_instance_valid(e):
			e.queue_free()
	_spawned_enemies.clear()
	_is_marching = false

	# Mock Game object expected by Distraction.setup()
	var mock_game = self
	
	# Position enemies evenly across grid row 9
	var spacing_cols := 4
	var start_col := 2

	for i in range(_distraction_keys.size()):
		var key: String = _distraction_keys[i]
		var col := start_col + i * spacing_cols
		var cell := Vector2i(col, 9)

		var enemy: Distraction = Distraction.new()
		if key == "social_media_binge":
			enemy = Boss.new()

		add_child(enemy)
		enemy.setup(mock_game, key)
		enemy.position = cell_center(cell)
		enemy.current_cell = cell
		_spawned_enemies.append(enemy)

	if _status_label != null:
		_status_label.text = "Stav: Všech 9 typů vyrušení zobrazeno vedle sebe."

func _on_toggle_march() -> void:
	_is_marching = not _is_marching
	# One shared flow_field flip pauses/resumes every enemy at once (they all read
	# `flow_field` off this same mock game each frame) — same effect the old
	# set_cell_path([]) toggle had, without a per-distraction pause flag.
	flow_field = _march_field if _is_marching else null

	if _status_label != null:
		_status_label.text = "Stav: Pohyb %s" % ("SPUŠTĚN" if _is_marching else "POZASTAVEN")

func _on_trigger_hit_flash() -> void:
	for enemy in _spawned_enemies:
		if is_instance_valid(enemy) and enemy.animator != null:
			enemy.animator.trigger_hit_flash()
	if _status_label != null:
		_status_label.text = "Stav: Spuštěn zásahový červeno-bílý flash."

func _on_apply_slow() -> void:
	for enemy in _spawned_enemies:
		if is_instance_valid(enemy):
			enemy.apply_slow(0.4, 4.0)
	if _status_label != null:
		_status_label.text = "Stav: Aplikován Slow / Calm status (60% zpomalení na 4s)."

func _on_apply_reframe() -> void:
	for enemy in _spawned_enemies:
		if is_instance_valid(enemy):
			enemy.apply_reframe(5, 4.0)
	if _status_label != null:
		_status_label.text = "Stav: Aplikován Reframe status (prolomený prstenec na 4s)."

func _draw() -> void:
	# Draw background mřížku pro vizuální orientaci
	var tile: float = Data.GRID.tile
	var cols: int = Data.GRID.cols
	var rows: int = Data.GRID.rows
	var ox: float = Data.GRID.origin_x
	var oy: float = Data.GRID.origin_y

	# Dark Canvas BG
	draw_rect(Rect2(0, 0, 1920, 1080), Color(0.08, 0.09, 0.12), true)

	# Grid Lines
	for c in range(cols + 1):
		draw_line(Vector2(ox + c * tile, oy), Vector2(ox + c * tile, oy + rows * tile), Color(1, 1, 1, 0.05), 1.0)
	for r in range(rows + 1):
		draw_line(Vector2(ox, oy + r * tile), Vector2(ox + cols * tile, oy + r * tile), Color(1, 1, 1, 0.05), 1.0)

	# Preview Track Line
	var p1 := cell_center(Vector2i(2, 9))
	var p2 := cell_center(Vector2i(37, 9))
	draw_line(p1, p2, Color(0.3, 0.8, 1.0, 0.3), 3.0)
