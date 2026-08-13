class_name Barracks
extends BaseHabit
## Ally training barracks. Spawns and manages blocking Allies instead of firing.

var owned_allies: Array = []
var _ally_spawn_timer: float = 0.0

const _FORMATION_OFFSETS := [Vector2(0, 0), Vector2(-16, 14), Vector2(16, 14)]  # small triangle

func _setup_specific(_initial_facing: float, _initial_arc: float) -> void:
	_ally_spawn_timer = def.ally_spawn_cooldown
	_spawn_one_ally()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for a in owned_allies:
			if is_instance_valid(a):
				a.queue_free()

func _process(delta: float) -> void:
	if not game.started or game.between_waves:
		return

	if owned_allies.size() < def.ally_count:
		_ally_spawn_timer -= delta
		if _ally_spawn_timer <= 0.0:
			_spawn_one_ally()
			_ally_spawn_timer = def.ally_spawn_cooldown

func _draw() -> void:
	# Rally point is the barracks center
	draw_circle(Vector2.ZERO, 3.0, Color.WHITE)
	
	# Guard zone rendering (faint normally, bright when selected/hovered)
	if show_range_indicator:
		draw_arc(Vector2.ZERO, def.guard_radius, 0, TAU, 32, Color(1.0, 1.0, 1.0, 0.4), 2.0)
		draw_circle(Vector2.ZERO, def.guard_radius, Color(1.0, 1.0, 1.0, 0.05))
	else:
		draw_arc(Vector2.ZERO, def.guard_radius, 0, TAU, 32, Color(1.0, 1.0, 1.0, 0.08), 1.0)

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
