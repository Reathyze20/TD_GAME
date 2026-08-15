class_name Barracks
extends BaseHabit
## Ally training barracks. Spawns and manages blocking Allies instead of firing.

var owned_allies: Array = []
var _ally_spawn_timer: float = 0.0

const _FORMATION_OFFSETS := [Vector2(0, 0), Vector2(-16, 14), Vector2(16, 14)]  # small triangle

## Body sprite, same file scheme as tower.gd heads (head_<type_key>.png + _frame_N) with
## the tier-2 fallback. The barracks used to render as a bare 3px rally dot — the only
## habit with no body at all.
var _base_tex: Texture2D
var _body_tex: Texture2D
var _body_frames: Array[Texture2D] = []
var _anim_t := 0.0
const BODY_FPS := 8.0

func _setup_specific(_initial_facing: float, _initial_arc: float) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if FileAccess.file_exists("res://assets/towers/tower_base.png"):
		_base_tex = load("res://assets/towers/tower_base.png")
	var key := type_key
	if not FileAccess.file_exists("res://assets/towers/head_%s.png" % key) \
			and not FileAccess.file_exists("res://assets/towers/head_%s_frame_1.png" % key):
		key = key.trim_suffix("_2")
	var static_path := "res://assets/towers/head_%s.png" % key
	if FileAccess.file_exists(static_path):
		_body_tex = load(static_path)
	for i in range(1, 33):
		var p := "res://assets/towers/head_%s_frame_%d.png" % [key, i]
		if not FileAccess.file_exists(p):
			break
		_body_frames.append(load(p))
	if _body_tex == null and not _body_frames.is_empty():
		_body_tex = _body_frames[0]

	_ally_spawn_timer = def.ally_spawn_cooldown
	_spawn_one_ally()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for a in owned_allies:
			if is_instance_valid(a):
				a.queue_free()

func _process(delta: float) -> void:
	# Body animation runs even between waves — the kiosk flag should wave while building.
	if not _body_frames.is_empty():
		_anim_t += delta
		queue_redraw()
	if not game.started or game.between_waves:
		return

	if owned_allies.size() < def.ally_count:
		_ally_spawn_timer -= delta
		if _ally_spawn_timer <= 0.0:
			_spawn_one_ally()
			_ally_spawn_timer = def.ally_spawn_cooldown

func _draw() -> void:
	var tile: int = Data.GRID.tile

	# Socket base + kiosk body, native size x whole zoom like every other habit.
	if _base_tex != null:
		var b_zoom := maxf(1.0, floorf(float(tile) / _base_tex.get_width()))
		var b_size := Vector2(_base_tex.get_size()) * b_zoom
		draw_texture_rect(_base_tex, Rect2(-b_size / 2.0, b_size), false, Color.WHITE)
	var body := _body_tex
	if not _body_frames.is_empty():
		body = _body_frames[int(_anim_t * BODY_FPS) % _body_frames.size()]
	if body != null:
		var zoom := maxf(1.0, floorf(float(tile) / body.get_width()))
		var size := Vector2(body.get_size()) * zoom
		draw_texture_rect(body, Rect2(-size / 2.0, size), false, Color.WHITE)
	else:
		# No art on disk: at least mark the rally point, as before.
		draw_circle(Vector2.ZERO, 3.0, Color.WHITE)

	# Guard zone in raster blocks (faint normally, bright when selected/hovered)
	if show_range_indicator:
		PixelDraw.arc(self, Vector2.ZERO, def.guard_radius, Color(1.0, 1.0, 1.0, 0.4), 1.0, 2.0)
		draw_circle(Vector2.ZERO, def.guard_radius, Color(1.0, 1.0, 1.0, 0.05))
	else:
		PixelDraw.arc(self, Vector2.ZERO, def.guard_radius, Color(1.0, 1.0, 1.0, 0.08), 1.0, 3.0)

# --- Ally management ------------------------------------------------------------

func _spawn_one_ally() -> void:
	var a = Ally.new()
	var slot := _next_free_slot()
	a.slot_index = slot
	a.setup(game, global_position + _FORMATION_OFFSETS[slot], def.ally_health, def.ally_damage, def.ally_attack_cooldown, def.guard_radius)
	a.died.connect(_on_ally_died)
	
	a.global_position = global_position # spawn at the barracks
	
	owned_allies.append(a)
	game.entities.add_child(a)

func _on_ally_died(ally) -> void:
	owned_allies.erase(ally)

func _next_free_slot() -> int:
	var used := {}
	for a in owned_allies:
		if is_instance_valid(a):
			used[a.slot_index] = true
	for i: int in range(_FORMATION_OFFSETS.size()):
		if not used.has(i):
			return i
	return owned_allies.size() % _FORMATION_OFFSETS.size()
