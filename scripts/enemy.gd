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
## Left of its own accord (a fleeting distraction's timer ran out). Deliberately NOT
## `defeated` — nothing was beaten, nobody is paid, and no kill is recorded. The game
## only needs it to drop the body from its live list so the wave can end.
signal expired(distraction: Distraction)

var def: DistractionData
var type_key: String

var max_health: int
var current_health: int
var current_speed: float
var current_compulsion: int
var current_rationalization: int
var is_flying: bool

var dead := false

## Habit id that landed the killing blow, or &"" for a leak / direct kill with no
## source. Read by GameState._on_distraction_defeated to age the novelty of THAT habit:
## the twentieth kill by the same tower is the one that stops surprising you.
var killer_key: StringName = &""

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

# Energiser (support archetype, def.haste_interval > 0): periodically washes a wave of
# speed over every distraction in radius, itself included. See _tick_haste().
var _haste_timer := 0.0
var _wave_time := -1.0        # >= 0 while a wave is expanding; drives the ring in _draw()

# Fleeting (FOMO, def.lifetime_seconds > 0): counts down in WAVE time only, so a
# limited-time offer cannot quietly expire while the player is thinking in the build
# phase. Its whole claim is that the clock is running; the clock has to be the same one
# the threat runs on or the mechanic is a lie in the player's favour.
var _life_left := -1.0

# Splitter (Just One More, def.split_count > 0): how deep in the chain this body is.
# Set by Game.spawn_distraction BEFORE setup() so the health scaling can read it.
# Generation 0 is the one the wave actually spawned.
var generation := 0

# Autoplay (def.autoplay_seconds > 0): wave-time countdown to stealing the build phase.
# Latches once armed — killing it afterwards does not give the prep phase back, the same
# way closing the tab after the next episode started does not give you the evening back.
var _autoplay_left := -1.0
var _autoplay_fired := false

# Comparison (def.adapts_to_player): which channel this body hardened against, or &"" if
# the board was still empty when it arrived. Drives the resistance tell in _draw().
var adapted_channel: StringName = &""

func setup(_game, _type_key: String) -> void:
	game = _game
	type_key = _type_key
	def = Data.get_distraction(type_key)
	# Cards can make the feed sturdier (the cost half of a two-sided card) or frailer.
	max_health = maxi(1, int(round(ModifierManager.get_modified_stat(
		float(def.max_health), ModifierManager.STAT_DISTRACTION_HEALTH))))
	# Splitter children are frailer the deeper they sit in the chain. The tail of a
	# "just one more" spawn has to be trivial to clear: the archetype's cost is the TIME
	# it eats, never difficulty, and a hard tail would turn a lesson about attrition into
	# an ordinary hard wave.
	if generation > 0 and def.split_scale > 0.0:
		max_health = maxi(1, int(round(float(max_health) * pow(def.split_scale, generation))))
	current_health = max_health
	# Apply any active distraction-speed modifiers (cards drafted earlier this level).
	current_speed = ModifierManager.get_modified_stat(def.speed, ModifierManager.STAT_DISTRACTION_SPEED)
	current_compulsion = def.compulsion
	current_rationalization = def.rationalization
	is_flying = def.is_flying
	_disrupt_timer = def.disrupt_interval
	# Staggered start, unlike the disruptor's fixed one: a wave that spawns with the
	# batch would have every energiser in it pulsing on the same frame, which reads as
	# one big scripted event instead of several creatures each doing their own thing.
	_haste_timer = def.haste_interval * randf_range(0.4, 1.0)
	_color = Color(def.color)
	var s: float = Data.GRID.tile * 0.16
	_scatter = Vector2(randf_range(-s, s), randf_range(-s, s))
	_life_left = def.lifetime_seconds if def.lifetime_seconds > 0.0 else -1.0
	_autoplay_left = def.autoplay_seconds if def.autoplay_seconds > 0.0 else -1.0
	# Visual shrink only — the hit radius stays def.radius. A split child that LOOKS
	# smaller than it is, is slightly easier to hit than it appears; the reverse would be
	# a body that eats shots it visibly dodged, and forgiving beats punishing when the
	# archetype is already about volume.
	if generation > 0 and def.split_scale > 0.0:
		scale = Vector2.ONE * maxf(0.45, pow(def.split_scale, generation))

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

	# After the def values are seeded above — this ADDS to them rather than replacing.
	if def.adapts_to_player:
		_adapt_to_player()

	add_to_group("distractions")
	queue_redraw()

func set_cell_path(p: Array) -> void:
	cell_path = p
	path_index = 1 if p.size() > 1 else 0

func add_blocker(ally: DefenderUnit) -> void:
	if not blockers.has(ally):
		blockers.append(ally)
	is_blocked = true

func remove_blocker(ally: DefenderUnit) -> void:
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
		if _awaiting_death_anim:
			_process_death_animation()
		return
	# Statuses tick before every early return below — a blocked or unrouted distraction
	# must still shed its Calm and Reframe on schedule, and still take Boredom damage.
	status_manager.tick(delta)
	if dead:
		return  # Boredom can finish it off mid-tick
	# Knockback budget refills on the same clock as everything else, and deliberately
	# before the blocked/no-path early returns: a distraction held by Allies is still
	# shedding the shove it took, so releasing it doesn't hand the tower a free stunlock.
	if _knock_left < KNOCK_BUDGET:
		_knock_left = minf(KNOCK_BUDGET, _knock_left + KNOCK_REGEN * delta)
	# The disruptor ticks BEFORE the blocked early-return on purpose: a pinned phone
	# still buzzes. Wave-time gated like every combat effect.
	if def.disrupt_interval > 0.0 and game != null and game.started and not game.between_waves:
		_tick_disrupt(delta)
	# Same gating, same reason: a blocked energiser still pushes the ones behind it.
	if def.haste_interval > 0.0 and game != null and game.started and not game.between_waves:
		_tick_haste(delta)
	# Both deadline archetypes run on WAVE time, matching the two ticks above: a
	# countdown that kept running through the build phase would either expire a
	# limited-time offer the player never got to answer, or steal a prep phase that had
	# already started.
	if _life_left > 0.0 and game != null and game.started and not game.between_waves:
		_life_left -= delta
		queue_redraw()          # the ring is the whole tell; it must move every frame
		if _life_left <= 0.0:
			_expire()
			return
	if _autoplay_left > 0.0 and game != null and game.started and not game.between_waves:
		_autoplay_left -= delta
		queue_redraw()
		if _autoplay_left <= 0.0:
			_arm_autoplay()
	if _wave_time >= 0.0:
		_wave_time += delta
		if _wave_time > WAVE_FX_TIME:
			_wave_time = -1.0
		queue_redraw()
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
	var step: float = current_speed * status_manager.move_scale() * delta
	if dist <= step:
		position = target
		path_index += 1
	else:
		position += to / dist * step
		note_heading(to / dist)
	queue_redraw()

## Which way this distraction is travelling, as one of four compass directions. The
## animator picks its walk cycle from it — without this every creature moonwalked east
## while playing its south-facing animation.
##
## Snapped to the dominant axis rather than kept as a raw vector: AStar runs with
## DIAGONAL_MODE_NEVER, so real movement is axis-aligned and only `_scatter` (the small
## per-enemy offset that stops a column overlapping into one blob) tilts it slightly.
## Snapping ignores that tilt; a raw angle would flicker between two sets mid-corridor.
enum Facing { SOUTH, NORTH, EAST, WEST }
var facing: Facing = Facing.SOUTH

func note_heading(dir: Vector2) -> void:
	# In 2:1 isometric diamond projection, grid cardinal axes land on screen diagonals:
	# Grid +X (1, 0) -> screen (+32, +16) (Facing.EAST)
	# Grid -X (-1, 0) -> screen (-32, -16) (Facing.WEST)
	# Grid +Y (0, 1) -> screen (-32, +16) (Facing.SOUTH)
	# Grid -Y (0, -1) -> screen (+32, -16) (Facing.NORTH)
	var axes := GridProjection.screen_dir_to_grid_axes(dir)
	var u := axes.x
	var v := axes.y
	if absf(u) > absf(v):
		facing = Facing.EAST if u > 0.0 else Facing.WEST
	else:
		facing = Facing.SOUTH if v > 0.0 else Facing.NORTH

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
	take_direct_damage(_shape_damage(wp + aw, source), source)

## Scales an incoming hit by WHAT FIRED IT, after the flat resistances and before the
## health is touched. Lives here rather than in projectile.gd because this is the one
## funnel every direct hit already passes through, and projectile.gd's pooled setup would
## have to reset any new field on every shot or leak it into the next one.
##
## Reads the habit's DATA cooldown, not its live one: a fire-rate card must not be able to
## push a habit across the "chip damage" line and quietly halve its own upgrade.
func _shape_damage(amount: int, source: Object) -> int:
	if amount <= 0 or not (source is Habit) or not is_instance_valid(source):
		return amount
	var mult := 1.0
	if source.def.aoe:
		mult = def.aoe_damage_mult
	elif def.fast_shot_threshold > 0.0 and source.def.fire_cooldown <= def.fast_shot_threshold:
		mult = def.fast_shot_damage_mult
	# Vulnerability multiplies on top of the archetype shaping rather than replacing it:
	# the Resonance Wave is supposed to make a target softer to whatever the player already
	# built, not to flatten that habit's own strength or weakness against it.
	mult *= status_manager.vulnerable_mult
	if is_equal_approx(mult, 1.0):
		return amount
	# Floored at 1 like every other mitigation: no armour in this game makes a hit free.
	return maxi(1, int(round(float(amount) * mult)))

## Health loss that skips both mitigation channels entirely — Boredom's damage, and the
## single place death is resolved. Attribution happens here so every damage path (direct
## hits, AoE pulses, dots) credits through one gate: applied damage is clamped to health
## actually lost, and the killing blow also counts a kill.
func take_direct_damage(amount: int, source: Object = null) -> void:
	if dead or amount <= 0:
		return
	var applied: int = mini(amount, maxi(0, current_health))
	current_health -= amount
	_check_overdrive()
	if source is BaseHabit and is_instance_valid(source):
		source.record_damage(applied)
		if current_health <= 0:
			source.record_kill()
			# Who landed the killing blow, for the novelty tax (GameState.surprise_of).
			# Recorded here rather than passed through distraction_defeated because the
			# bus signal is consumed by five listeners that have no use for it, and a
			# wider signature would have to be threaded through every test harness.
			killer_key = source.def.id
	if animator != null:
		animator.trigger_hit_flash()
	queue_redraw()
	if current_health <= 0:
		_die()

## Overdrive: the wounded phase. Latched, not polled — checked once per damage event
## (health changes nowhere else) and never re-evaluated, so healing or a rounding wobble
## cannot switch it back off. A creature does not calm down again after this.
##
## The speed goes through StatusManager.extra_factor rather than apply_haste() or
## current_speed: haste is strongest-wins and would SWALLOW this creature's own 1.35 aura
## instead of compounding with it, and current_speed is invisible to move_scale().
var _overdrive := false

func _check_overdrive() -> void:
	if _overdrive or def.overdrive_hp_pct <= 0.0 or max_health <= 0:
		return
	if float(current_health) / float(max_health) > def.overdrive_hp_pct:
		return
	_overdrive = true
	status_manager.extra_factor *= def.overdrive_speed_mult
	if def.overdrive_slow_immune:
		status_manager.slow_immune = true
		# Shed the Calm it is standing in. Without this the creature keeps the slow it
		# was carrying when it crossed the threshold, and "ignores slows" reads as a lie
		# for as long as that pulse lasts.
		status_manager.clear_slow()
	if game != null:
		game.add_shake(4.0)
	queue_redraw()

func is_overdriven() -> bool:
	return _overdrive

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

## How long the expanding wave ring is drawn for. Purely cosmetic: the speed is granted
## the instant the wave fires, so the ring is a readout of what already happened rather
## than a travelling hitbox. A ring that had to reach you first would make the buff feel
## dodgeable when it isn't.
const WAVE_FX_TIME := 0.45

## The energiser's whole job: every def.haste_interval seconds, wash def.haste_factor
## speed over every living distraction within def.haste_radius, itself included.
##
## Deliberately NOT limited to one target the way the disruptor is — an energy drink
## that hurried a single neighbour would be invisible in a crowd. Hitting the whole
## group is what makes the emitter worth shooting first, and the ring in _draw() is
## how the player finds out which one to shoot.
func _tick_haste(delta: float) -> void:
	_haste_timer -= delta
	if _haste_timer > 0.0:
		return
	_haste_timer = def.haste_interval
	_wave_time = 0.0
	var r_sq: float = def.haste_radius * def.haste_radius
	for d in get_tree().get_nodes_in_group("distractions"):
		if not is_instance_valid(d) or d.dead or d.status_manager == null:
			continue
		if global_position.distance_squared_to(d.global_position) > r_sq:
			continue
		d.status_manager.apply_haste(def.haste_factor, def.haste_duration)
		d.queue_redraw()
	queue_redraw()

## Flyers ignore the maze completely — no cell path, straight line to the Focus core.
## That *is* the point: an urge from inside doesn't route around your structure, and no
## barricade or Ally stands between it and your attention.
func _fly(delta: float) -> void:
	var target: Vector2 = game.objective_pos + _scatter
	var to: Vector2 = target - position
	var dist: float = to.length()
	var step: float = current_speed * status_manager.move_scale() * delta
	if dist <= step:
		_reach_core()
		return
	position += to / dist * step
	note_heading(to / dist)
	queue_redraw()

## Boredom damage callback — StatusManager emits this per source, so the habit that
## applied the dot gets panel credit. Routes through take_direct_damage() so the
## mid-tick kill check is preserved. The source may have been sold/freed since it
## applied the dot; the BaseHabit check plus take_direct_damage's own
## is_instance_valid guard cover that.
## The dot multiplier is applied HERE and not in take_direct_damage(), which is also the
## boss's shield bypass and the F4 clear-the-field path — scaling it there would quietly
## reshape both.
func _on_boredom_damage(amount: int, source: Object) -> void:
	var dealt: int = amount
	if not is_equal_approx(def.dot_damage_mult, 1.0):
		dealt = maxi(1, int(round(float(amount) * def.dot_damage_mult)))
	take_direct_damage(dealt, source if source is BaseHabit else null)

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

## Freezes the distraction outright for `duration`. Routed through apply_slow(0.0, ...)
## because a factor of 0.0 already means "stopped" to move_scale() AND is the one value
## apply_slow lets through slow_immune — so a stun needs no parallel timer, just a name
## the call sites can read.
func apply_stun(duration: float) -> void:
	if duration <= 0.0:
		return
	status_manager.apply_slow(0.0, duration)
	queue_redraw()

## Wipes the Rush aura (not Overdrive). See StatusManager.clear_haste().
func dispel_haste() -> void:
	status_manager.clear_haste()
	queue_redraw()

## Marks the distraction to take amplified habit damage for `duration`.
func apply_vulnerable(mult: float, duration: float) -> void:
	status_manager.apply_vulnerable(mult, duration)
	queue_redraw()

# --- Knockback -----------------------------------------------------------------------
#
# The narrow-cone half of the impulse rule (ArcProfile): concentrated fire pushes bodies
# back down the corridor they came from. Two things keep it from becoming a stunlock, and
# both matter more than the push itself:
#
#  * A BUDGET. A machine gun landing ten hits a second would otherwise out-push any
#    walking speed in the game and pin its target on the spot forever — a hard crowd
#    control the player bought by accident. The budget refills over time, so a burst of
#    fire shoves hard and then stops mattering until the target has walked some of it off.
#  * A WALL CHECK. Movement here is a walk toward the next cell centre, not a physics
#    body, so nothing else would stop a push from parking a distraction inside high
#    ground — where it is unreachable, unkillable and visibly wrong.
#
# Deliberately NOT resisted by anything: `slow_immune` (Overdrive) says "ignores slows",
# and being shoved is not a slow. A tower narrowed to a beam is supposed to be the answer
# to the thing that cannot be slowed.

const KNOCK_BUDGET := 26.0     ## px of push available at once
const KNOCK_REGEN := 34.0      ## px/s the budget refills

var _knock_left: float = KNOCK_BUDGET

## Shoves this distraction `px` pixels along `dir`, spending from its budget. `dir` is
## the shot's flight direction (or, for a pulse, outward from the tower) — already
## normalized by the caller.
func apply_knockback(dir: Vector2, px: float) -> void:
	if dead or px <= 0.0 or _knock_left <= 0.0:
		return
	var amount: float = minf(px, _knock_left)
	_knock_left -= amount
	var target: Vector2 = position + dir * amount
	# Flyers are over the terrain, so nothing down there can catch them. Everything else
	# has to land somewhere it could have walked to.
	# `position`, not `global_position`: world_to_cell and cell_center are both pure grid
	# math in the Game node's own space, which is the space this node walks its path in.
	if not is_flying and game != null:
		if game.high_ground.has(game.world_to_cell(target)):
			return
	position = target

func effective_compulsion() -> int:
	return maxi(0, current_compulsion - status_manager.reframe_amount)

func effective_rationalization() -> int:
	return maxi(0, current_rationalization - status_manager.reframe_amount)

## Comparison archetype: harden against whatever the player leaned on.
##
## Only ONE channel is ever resisted, and that is the whole design. Resisting both would
## be a flat difficulty bump that says nothing; resisting the dominant one says "the
## thing you did most is the thing that stopped working", and leaves the answer visible
## on the player's own board.
##
## Silent when the board is empty (wave 1, or a maze of pure blockers): there is nothing
## to have learned yet, and inventing a resistance would make the archetype arbitrary.
func _adapt_to_player() -> void:
	if game == null or not game.has_method("player_damage_profile"):
		return
	var profile: Dictionary = game.player_damage_profile()
	var wp: int = int(profile.get("willpower", 0))
	var aw: int = int(profile.get("awareness", 0))
	if wp <= 0 and aw <= 0:
		return
	# Scaled off the single best habit, not the board total, so adding towers never makes
	# this one harder. Otherwise the archetype would punish building, which is the one
	# thing a tower defence must never do.
	var bite: int = maxi(1, int(round(float(profile.get("top_damage", 0)) * def.adapt_ratio)))
	if wp >= aw:
		current_compulsion += bite
		adapted_channel = &"willpower"
	else:
		current_rationalization += bite
		adapted_channel = &"awareness"
	Mirror.mark(&"adapted", adapted_channel)

## Fleeting archetype: the offer closes. No damage, no reward, no kill — the point is
## that this was ALWAYS what ignoring it would cost. Recorded so the receipt can pair
## "offers you shot" against "damage they would have done", which is 0.
func _expire() -> void:
	if dead:
		return
	dead = true
	Mirror.mark(&"bait_expired", type_key)
	expired.emit(self)
	queue_free()

## Autoplay archetype: the deadline passed and the next wave is now on a clock. Latched,
## so killing it after this changes nothing. Handing it to the game rather than acting
## here keeps every wave-flow decision in one place.
func _arm_autoplay() -> void:
	if _autoplay_fired:
		return
	_autoplay_fired = true
	_autoplay_left = -1.0
	Mirror.mark(&"autoplay_armed", type_key)
	if game != null and game.has_method("arm_autoplay"):
		game.arm_autoplay(def.autoplay_grace)

## Splitter archetype: leave smaller copies behind. Called from _die() AFTER the defeat
## signals, so the parent is already off the live list and the wave-progress check sees
## the children as the reason the wave has not ended — rather than briefly seeing an
## empty field and declaring the wave clear.
func _split() -> void:
	if def.split_count <= 0 or generation >= def.split_generations:
		return
	if game == null or not game.has_method("spawn_split"):
		return
	for i: int in range(def.split_count):
		game.spawn_split(self, i)

func _die() -> void:
	if dead:
		return
	dead = true
	# Signals fire IMMEDIATELY, before any death animation. Reward, kill count, combo and
	# the game's live-enemy list must not wait on presentation — a wave whose last kill
	# animates for half a second would otherwise take half a second too long to end, and
	# the corpse would still count as "on field".
	defeated.emit(self)
	SignalBus.distraction_defeated.emit(self, def.dopamine_reward)
	_split()

	# With death art, the node lingers just long enough to play it out. It is already
	# `dead`, so nothing targets it, it deals no damage and it does not move.
	if animator != null and animator.has_death_animation():
		animator.play_death()
		_awaiting_death_anim = true
		set_process(true)
		return
	queue_free()

## Set while the corpse plays its death frames; see _process's early-out below.
var _awaiting_death_anim := false

func _process_death_animation() -> void:
	if animator == null or animator.is_death_finished():
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

	# Deadline tells. Both archetypes are only fair if the clock is VISIBLE — a
	# limited-time offer the player cannot see expiring teaches nothing, and an autoplay
	# that steals the build phase without warning is a punishment rather than a threat.
	# Drawn as a depleting ground arc (PixelDraw.arc is already 2:1, so it reads as a
	# ring on the floor in isometry rather than a flat circle pasted over the body).
	if _life_left > 0.0 and def.lifetime_seconds > 0.0:
		var left: float = clampf(_life_left / def.lifetime_seconds, 0.0, 1.0)
		PixelDraw.arc(self, Vector2(0.0, r * 0.35), r * 1.7,
			Color(1.0, 0.78, 0.25, 0.75), 1.0, 2.0, -PI * 0.5, -PI * 0.5 + TAU * left)
	# Comparison tell: a closed ring in the colour of the channel it learned. Solid
	# rather than depleting, because unlike the two below it this is not a countdown —
	# it is a fact about this body that was already true when it arrived.
	if adapted_channel != &"":
		var chan_col := Color(0.45, 0.72, 1.0, 0.7) if adapted_channel == &"willpower" 			else Color(1.0, 0.85, 0.35, 0.7)
		PixelDraw.arc(self, Vector2(0.0, r * 0.35), r * 1.5, chan_col, 1.0, 2.4)
	if _autoplay_left > 0.0 and def.autoplay_seconds > 0.0:
		var run: float = clampf(_autoplay_left / def.autoplay_seconds, 0.0, 1.0)
		# Reddens as it charges: this one is counting UP to something bad, unlike the
		# offer above, which is counting down to nothing.
		PixelDraw.arc(self, Vector2(0.0, r * 0.35), r * 1.7,
			Color(1.0, 0.35 + run * 0.4, 0.3, 0.8), 1.0, 2.0,
			-PI * 0.5, -PI * 0.5 + TAU * (1.0 - run))

	# Disruptor tells, drawn regardless of which body renderer is active: a radius ring
	# that brightens as the ping charges, and the ping line itself when it fires. The
	# player must be able to SEE why their tower just stopped.
	if def.disrupt_interval > 0.0:
		var charge: float = 1.0 - clampf(_disrupt_timer / def.disrupt_interval, 0.0, 1.0)
		if charge > 0.6:
			PixelDraw.arc(self, Vector2.ZERO, def.disrupt_radius,
				Color(0.26, 0.78, 0.42, (charge - 0.6) * 0.6), 1.0, 2.5)
		if _ping_flash > 0.0:
			var a: float = _ping_flash / 0.35
			PixelDraw.line(self, Vector2.ZERO, to_local(_ping_target), Color(0.4, 1.0, 0.55, a * 0.9), 1.0, 2.0)
			draw_circle(to_local(_ping_target), 8.0 * a, Color(0.4, 1.0, 0.55, a * 0.5))

	# Energiser tells, drawn on the enemy layer for the same reason as the disruptor's:
	# a buff nobody can see reads as "the game sped up on its own". The ring expands to
	# the real haste_radius, so the player can measure who is inside it.
	if def.haste_interval > 0.0:
		if _wave_time >= 0.0:
			var t: float = clampf(_wave_time / WAVE_FX_TIME, 0.0, 1.0)
			var col := Color(_color.r, _color.g, _color.b, (1.0 - t) * 0.75)
			PixelDraw.arc(self, Vector2.ZERO, def.haste_radius * t, col, 1.0, 3.0)
			PixelDraw.arc(self, Vector2.ZERO, def.haste_radius * t * 0.62,
				Color(col.r, col.g, col.b, col.a * 0.5), 1.0, 2.0)
		else:
			# Between waves: a faint charge ring so the emitter is identifiable at rest.
			var charge: float = 1.0 - clampf(_haste_timer / maxf(def.haste_interval, 0.001), 0.0, 1.0)
			if charge > 0.55:
				PixelDraw.arc(self, Vector2.ZERO, def.haste_radius,
					Color(_color.r, _color.g, _color.b, (charge - 0.55) * 0.5), 1.0, 2.0)

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
