class_name Distraction
extends Node2D
# A digital distraction that pathfinds through the maze toward the Focus core.
# The Game node computes a cell path (AStarGrid2D routes around fixed high ground)
# and hands it over via set_cell_path(). The distraction walks it cell to cell
# with a small swarm scatter so a burst of them doesn't stack into one sprite.
#
# Two damage channels:
#   Willpower damage  — mitigated flat by compulsion
#   Awareness damage  — mitigated flat by rationalization
# Both channels are stripped by the Reframe status (future StatusManager work).

signal defeated(distraction: Distraction)
signal reached_core(distraction: Distraction)

var def: DistractionData
var type_key: String

var max_health: int
var current_health: int
var current_speed: float
var current_compulsion: int
var current_rationalization: int
var is_flying: bool

var dead := false

# --- Statuses (delegated to StatusManager component) -------------------------
# All three status effects (Calm/Slow, Reframe, Boredom) live in a StatusManager
# child node. This script keeps thin delegating wrappers so tower.gd's AoE pulse
# and game.gd's interventions call the same methods as before.
var status_manager: StatusManager
var animator: DistractionAnimator

# Blocking (06) — one or more Allies hold this distraction in melee and halt its path.
# Any number of Allies may pile onto the same distraction; it stays blocked until the
# last one disengages (dies or the distraction dies).
var is_blocked := false
var blockers: Array = []   # Array[Ally] currently engaging this distraction

var _color: Color
var game               # reference to the Game node

var cell_path: Array = []   # Array[Vector2i]
var path_index := 0
var _scatter := Vector2.ZERO # small per-distraction offset — anti-clumping

# Disruptor (support archetype, def.disrupt_interval > 0): periodically pings the
# nearest working habit in radius and stops it briefly. See _tick_disrupt().
var _disrupt_timer := 0.0
var _ping_flash := 0.0        # brief visual of the ping line, drawn in _draw()
var _ping_target := Vector2.ZERO

func setup(_game, _type_key: String) -> void:
	game = _game
	type_key = _type_key
	def = Data.get_distraction(type_key)
	# Cards can make the feed sturdier (the cost half of a two-sided card) or frailer.
	max_health = maxi(1, int(round(ModifierManager.get_modified_stat(
		float(def.max_health), ModifierManager.STAT_DISTRACTION_HEALTH))))
	current_health = max_health
	# Apply any active distraction-speed modifiers (cards drafted earlier this level).
	current_speed = ModifierManager.get_modified_stat(def.speed, ModifierManager.STAT_DISTRACTION_SPEED)
	current_compulsion = def.compulsion
	current_rationalization = def.rationalization
	is_flying = def.is_flying
	_disrupt_timer = def.disrupt_interval
	_color = Color(def.color)
	var s: float = Data.GRID.tile * 0.16
	_scatter = Vector2(randf_range(-s, s), randf_range(-s, s))

	# StatusManager component — owns Calm/Reframe/Boredom logic
	status_manager = StatusManager.new()
	status_manager.name = "StatusManager"
	status_manager.boredom_damage.connect(_on_boredom_damage)
	status_manager.reframe_changed.connect(func(_amt: int): queue_redraw())
	add_child(status_manager)

	# DistractionAnimator component — owns procedural multi-part vector animations
	animator = DistractionAnimator.new()
	animator.name = "DistractionAnimator"
	add_child(animator)
	animator.setup(self)

	add_to_group("distractions")
	queue_redraw()

func set_cell_path(p: Array) -> void:
	cell_path = p
	path_index = 1 if p.size() > 1 else 0

func add_blocker(ally) -> void:
	if not blockers.has(ally):
		blockers.append(ally)
	is_blocked = true

func remove_blocker(ally) -> void:
	blockers.erase(ally)
	is_blocked = not blockers.is_empty()

## Safety net: an Ally freed without disengaging (barracks sold / upgraded mid-fight)
## would otherwise leave a stale entry here and pin is_blocked true forever.
func _prune_blockers() -> void:
	var before: int = blockers.size()
	for i: int in range(blockers.size() - 1, -1, -1):
		if not is_instance_valid(blockers[i]):
			blockers.remove_at(i)
	if blockers.size() != before:
		is_blocked = not blockers.is_empty()

func _process(delta: float) -> void:
	if dead:
		return
	# Statuses tick before every early return below — a blocked or unrouted distraction
	# must still shed its Calm and Reframe on schedule, and still take Boredom damage.
	status_manager.tick(delta)
	if dead:
		return  # Boredom can finish it off mid-tick
	# The disruptor ticks BEFORE the blocked early-return on purpose: a pinned phone
	# still buzzes. Wave-time gated like every combat effect.
	if def.disrupt_interval > 0.0 and game != null and game.started and not game.between_waves:
		_tick_disrupt(delta)
	if _ping_flash > 0.0:
		_ping_flash = maxf(0.0, _ping_flash - delta)
		queue_redraw()
	if is_flying:
		_fly(delta)
		return
	if is_blocked:
		_prune_blockers()
		if is_blocked:
			return  # movement halted; the Allies handle the melee trade
	if cell_path.is_empty():
		return  # no route yet — idle rather than falsely reaching the core
	if path_index >= cell_path.size():
		_reach_core()
		return
	var target: Vector2 = game.cell_center(cell_path[path_index]) + _scatter
	var to: Vector2 = target - position
	var dist: float = to.length()
	var step: float = current_speed * status_manager.slow_factor * delta
	if dist <= step:
		position = target
		path_index += 1
	else:
		position += to / dist * step
	queue_redraw()

func distance_to_core() -> float:
	return position.distance_to(game.objective_pos)

# Two-channel damage: Willpower vs Compulsion, Awareness vs Rationalization.
# Each channel floors at 1 if > 0 before mitigation (can't fully negate unless
# compulsion/rationalization >= the raw damage). Reframe strips both resistances
# first, which is what turns Mindfulness into a set-up for the heavy hitters.
# `source` (the firing habit) gets credited for its panel stats; null is fine —
# interventions and burst cards deliberately credit no one.
func take_damage(willpower: int, awareness: int, source: Object = null) -> void:
	if dead:
		return
	var wp := maxi(1, willpower - effective_compulsion()) if willpower > 0 else 0
	var aw := maxi(1, awareness - effective_rationalization()) if awareness > 0 else 0
	take_direct_damage(wp + aw, source)

## Health loss that skips both mitigation channels entirely — Boredom's damage, and the
## single place death is resolved. Attribution happens here so every damage path (direct
## hits, AoE pulses, dots) credits through one gate: applied damage is clamped to health
## actually lost, and the killing blow also counts a kill.
func take_direct_damage(amount: int, source: Object = null) -> void:
	if dead or amount <= 0:
		return
	var applied: int = mini(amount, maxi(0, current_health))
	current_health -= amount
	if source is BaseHabit and is_instance_valid(source):
		source.record_damage(applied)
		if current_health <= 0:
			source.record_kill()
	if animator != null:
		animator.trigger_hit_flash()
	queue_redraw()
	if current_health <= 0:
		_die()

## The disruptor's whole job: every def.disrupt_interval seconds, stop the nearest
## habit within def.disrupt_radius for def.disrupt_duration. Only habits that are
## actually working are eligible — support projects no attack to interrupt, a resting
## or already-pinged habit is idle anyway, and one outside Routine is already stalled.
## Counterplay is built in: it telegraphs (charging ring in _draw), and the targeting
## modes give the player the tool to prioritise it.
func _tick_disrupt(delta: float) -> void:
	_disrupt_timer -= delta
	queue_redraw()   # the charging ring animates with the timer
	if _disrupt_timer > 0.0:
		return
	_disrupt_timer = def.disrupt_interval
	var best: Habit = null
	var best_dist := def.disrupt_radius
	for spot in game.build_spots.values():
		if not is_instance_valid(spot) or spot.state != BuildSpot.State.BUILT:
			continue
		var h = spot.current_habit
		if not (h is Habit) or h.def.is_support() or not h.in_routine \
				or h.is_resting() or h.disrupted_left > 0.0:
			continue
		var dist := global_position.distance_to(h.global_position)
		if dist <= best_dist:
			best_dist = dist
			best = h
	if best != null:
		best.disrupt(def.disrupt_duration)
		_ping_flash = 0.35
		_ping_target = best.global_position
		queue_redraw()

## Flyers ignore the maze completely — no cell path, straight line to the Focus core.
## That *is* the point: an urge from inside doesn't route around your structure, and no
## barricade or Ally stands between it and your attention.
func _fly(delta: float) -> void:
	var target: Vector2 = game.objective_pos + _scatter
	var to: Vector2 = target - position
	var dist: float = to.length()
	var step: float = current_speed * status_manager.slow_factor * delta
	if dist <= step:
		_reach_core()
		return
	position += to / dist * step
	queue_redraw()

## Boredom damage callback — StatusManager emits this per source, so the habit that
## applied the dot gets panel credit. Routes through take_direct_damage() so the
## mid-tick kill check is preserved. The source may have been sold/freed since it
## applied the dot; the BaseHabit check plus take_direct_damage's own
## is_instance_valid guard cover that.
func _on_boredom_damage(amount: int, source: Object) -> void:
	take_direct_damage(amount, source if source is BaseHabit else null)

# --- Status delegating wrappers -----------------------------------------------
# tower.gd's AoE pulse calls these in a specific order (Reframe before damage).
# Keeping the same method signatures means zero changes to any call site.

## Strongest Calm wins: a weaker pulse cannot dilute or cut short a stronger one
## (lower factor = stronger). Re-applying the same or stronger slow refreshes its timer.
func apply_slow(factor: float, duration: float) -> void:
	status_manager.apply_slow(factor, duration)

## Boredom stacks per source — pass the applying habit so several Real Hobbies sum
## instead of shadowing each other. See StatusManager.apply_boredom.
func apply_boredom(dps: float, duration: float, source: Object = null) -> void:
	status_manager.apply_boredom(dps, duration, source)
	queue_redraw()

## Strongest Reframe wins. One rule governs Calm and Reframe:
## **strongest wins, and duration is never truncated.**
func apply_reframe(amount: int, duration: float) -> void:
	status_manager.apply_reframe(amount, duration)
	queue_redraw()

func effective_compulsion() -> int:
	return maxi(0, current_compulsion - status_manager.reframe_amount)

func effective_rationalization() -> int:
	return maxi(0, current_rationalization - status_manager.reframe_amount)

func _die() -> void:
	if dead:
		return
	dead = true
	defeated.emit(self)
	SignalBus.distraction_defeated.emit(self, def.dopamine_reward)
	queue_free()

func _reach_core() -> void:
	if dead:
		return
	dead = true
	reached_core.emit(self)
	SignalBus.distraction_escaped.emit(def.focus_damage)
	queue_free()

func _draw() -> void:
	var r: float = def.radius

	# Disruptor tells, drawn regardless of which body renderer is active: a radius ring
	# that brightens as the ping charges, and the ping line itself when it fires. The
	# player must be able to SEE why their tower just stopped.
	if def.disrupt_interval > 0.0:
		var charge: float = 1.0 - clampf(_disrupt_timer / def.disrupt_interval, 0.0, 1.0)
		if charge > 0.6:
			draw_arc(Vector2.ZERO, def.disrupt_radius, 0.0, TAU, 48,
				Color(0.26, 0.78, 0.42, (charge - 0.6) * 0.6), 1.5)
		if _ping_flash > 0.0:
			var a: float = _ping_flash / 0.35
			draw_line(Vector2.ZERO, to_local(_ping_target), Color(0.4, 1.0, 0.55, a * 0.9), 2.5)
			draw_circle(to_local(_ping_target), 8.0 * a, Color(0.4, 1.0, 0.55, a * 0.5))

	# Fallback drawing if animator component is not attached
	if animator == null:
		if is_flying:
			draw_circle(Vector2(0, r + 12.0), r * 0.55, Color(0, 0, 0, 0.28))
			draw_line(Vector2(-r - 5.0, -2.0), Vector2(-r - 1.0, -5.0), Color(1, 1, 1, 0.7), 1.5)
			draw_line(Vector2(r + 1.0, -5.0), Vector2(r + 5.0, -2.0), Color(1, 1, 1, 0.7), 1.5)

		if status_manager.has_boredom():
			draw_circle(Vector2.ZERO, r + 5.0, Color(0.55, 0.58, 0.62, 0.30))

		match def.shape:
			"circle":
				draw_circle(Vector2.ZERO, r, _color)
			"rect":
				draw_rect(Rect2(-r, -r, r * 2.0, r * 2.0), _color)
			"triangle":
				var pts := PackedVector2Array([Vector2(0, -r), Vector2(r, r), Vector2(-r, r)])
				draw_colored_polygon(pts, _color)

		if status_manager.has_reframe():
			var seg: float = TAU / 8.0
			for i: int in range(4):
				var a: float = float(i) * seg * 2.0
				draw_arc(Vector2.ZERO, r + 4.0, a, a + seg, 6, Color(1, 1, 1, 0.85), 2.0)

	# Health bar — only shown when damaged.
	if current_health < max_health:
		var w: float = r * 2.0
		var y: float = -r - 6.0
		draw_rect(Rect2(-w / 2.0 - 1.0, y - 1.0, w + 2.0, 4.0), Color(0, 0, 0, 0.6))
		var ratio: float = clampf(float(current_health) / float(max_health), 0.0, 1.0)
		draw_rect(Rect2(-w / 2.0, y, w * ratio, 2.0), Color(0.2, 0.85, 0.33))
