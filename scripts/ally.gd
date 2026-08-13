class_name Ally
extends Node2D
# Trained by an Accountability barracks at some production rate (see Habit._spawn_one_ally).
# On spawn a soldier immediately seeks out the nearest live enemy anywhere on the field and
# marches to meet it — once in melee range the enemy is held in place (is_blocked), diverting
# it from the Focus core, and both sides trade damage every attack_cooldown until one dies.
#
# State machine: SEEKING (idle at rally or chasing a locked target) <-> ENGAGING. On death the
# Ally is freed for good; the Habit's production timer trains a replacement up to its cap.

enum State { SEEKING, ENGAGING }

signal died(ally: Ally)

var game  # Game node reference
var rally_point: Vector2
var current_state: State = State.SEEKING
var slot_index: int = 0   # formation slot owned within the parent barracks

var max_health: int
var current_health: int
var attack_damage: int
var attack_cooldown: float
var move_speed: float = 90.0      # walk back to the rally point — no need to hurry
var guard_radius: float = 240.0   # patrol zone, measured from rally_point

## Chase speed while closing on a target. Must comfortably exceed the fastest GROUND
## distraction (notification, 140 px/s) or the chase never resolves: the old value of
## move_speed * 1.6 = 144 closed at 4 px/s — a pursuit that looked alive and caught
## nothing before the target left the guard zone.
const CHASE_SPEED := 200.0

# Temporary Allies (Call a Friend, 12) expire on their own; 0.0 means permanent.
var lifetime: float = 0.0
var _life_left: float = 0.0

var engaged_target: Distraction = null
var attack_timer: float = 0.0

const _COLOR := Color("2bd6c0")

## Explicit typed fields rather than a duck-typed def Dictionary/Resource — Allies are
## trained by a Barracks (HabitData has no ally_lifetime: permanent) or summoned by the
## Call a Friend intervention (InterventionData sets ally_lifetime > 0: temporary). Those
## two data types share no common base beyond Resource, so the caller passes the fields
## through explicitly instead of Ally trying to duck-type whichever one it was handed.
func setup(_game, _rally_point: Vector2, _ally_health: int, _ally_damage: int,
		_ally_attack_cooldown: float, _guard_radius: float, _ally_lifetime: float = 0.0) -> void:
	game = _game
	rally_point = _rally_point
	max_health = _ally_health
	current_health = max_health
	attack_damage = _ally_damage
	attack_cooldown = _ally_attack_cooldown
	guard_radius = _guard_radius
	lifetime = _ally_lifetime
	_life_left = lifetime
	global_position = rally_point
	queue_redraw()

func _process(delta: float) -> void:
	if lifetime > 0.0:
		_life_left -= delta
		if _life_left <= 0.0:
			_die()
			return

	match current_state:
		State.SEEKING:
			# Drop a chased target that has since left the zone, so a distraction
			# walking past the edge can't tow the Ally off its post.
			if is_instance_valid(engaged_target) and not engaged_target.dead \
					and not _in_guard_zone(engaged_target):
				engaged_target = null
			if not is_instance_valid(engaged_target) or engaged_target.dead:
				engaged_target = _find_target()
			if engaged_target:
				if global_position.distance_to(engaged_target.global_position) <= 6.0:
					_execute_clash(engaged_target)
				else:
					# move_toward clamps to the remaining distance — a raw
					# normalized() * speed * delta step overshoots on long frames
					# and can jitter around the target without ever closing.
					global_position = global_position.move_toward(
						engaged_target.global_position, CHASE_SPEED * delta)
			elif global_position.distance_to(rally_point) > 2.0:
				global_position = global_position.move_toward(rally_point, move_speed * delta)
		State.ENGAGING:
			_process_melee(delta)
	queue_redraw()

## Distance is measured from rally_point, never from the Ally's own position — chaining
## "nearest to me" would let it creep across the whole map one target at a time, abandoning
## the chokepoint its barracks was built to hold.
func _in_guard_zone(d: Distraction) -> bool:
	return rally_point.distance_to(d.global_position) <= guard_radius

## Nearest live enemy inside the guard zone. Already-blocked targets count too, so several
## Allies can pile onto one distraction.
func _find_target() -> Distraction:
	if game == null:
		return null
	var nearest: Distraction = null
	var nearest_dist := INF
	for d in game.get_live_distractions():
		if is_instance_valid(d) and not d.dead and not d.is_flying and _in_guard_zone(d):
			var dist := global_position.distance_to(d.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = d
	return nearest

func _execute_clash(target: Distraction) -> void:
	target.add_blocker(self)
	current_state = State.ENGAGING
	attack_timer = 0.0

	# Juicy knockback on the distraction's own position — safe to tween directly
	# now that is_blocked has halted its cell-path movement in _process().
	var knockback_dir := (target.global_position - global_position).normalized()
	var original_pos := target.position
	var tw := target.create_tween()
	tw.tween_property(target, "position", original_pos + knockback_dir * 6.0, 0.1) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(target, "position", original_pos, 0.08)

func _process_melee(delta: float) -> void:
	if not is_instance_valid(engaged_target) or engaged_target.dead:
		_disengage()
		return
	attack_timer -= delta
	if attack_timer <= 0.0:
		attack_timer = attack_cooldown
		var counter_damage: int = engaged_target.def.melee_damage
		engaged_target.take_damage(attack_damage, 0)
		take_damage(counter_damage)

func _disengage() -> void:
	if is_instance_valid(engaged_target):
		engaged_target.remove_blocker(self)
	engaged_target = null
	current_state = State.SEEKING

func take_damage(amount: int) -> void:
	current_health -= amount
	queue_redraw()
	if current_health <= 0:
		_die()

func _die() -> void:
	died.emit(self)
	queue_free()

## Single cleanup point for every removal path — lifetime expiry, death in melee, or a
## barracks being sold/upgraded mid-fight (which frees its Allies outright, bypassing
## _die()). Releasing the melee hold here is what stops a freed blocker from pinning a
## distraction as permanently halted.
func _exit_tree() -> void:
	_disengage()

func _draw() -> void:
	var r := 10.0
	draw_circle(Vector2.ZERO, r, _COLOR)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 16, Color(1, 1, 1, 0.4), 2.0)
	# Small cross mark — support/aid iconography, distinct from habit/distraction shapes.
	draw_line(Vector2(-4, 0), Vector2(4, 0), Color.WHITE, 2.0)
	draw_line(Vector2(0, -4), Vector2(0, 4), Color.WHITE, 2.0)

	# Temporary Allies show a draining ring so their remaining time is readable at a glance.
	if lifetime > 0.0:
		var left: float = clampf(_life_left / lifetime, 0.0, 1.0)
		draw_arc(Vector2.ZERO, r + 4.0, -PI / 2.0, -PI / 2.0 + TAU * left, 24,
			Color(1.0, 0.82, 0.4, 0.9), 2.0)

	if current_health < max_health:
		var w := r * 2.0
		var y := -r - 6.0
		draw_rect(Rect2(-w / 2.0 - 1.0, y - 1.0, w + 2.0, 4.0), Color(0, 0, 0, 0.6))
		var ratio: float = clampf(float(current_health) / float(max_health), 0.0, 1.0)
		draw_rect(Rect2(-w / 2.0, y, w * ratio, 2.0), Color("2bd6c0"))
