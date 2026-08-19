class_name Habit
extends BaseHabit
# A placed healthy habit defending attention.
#
# It does NOT pick targets. A habit is a suppression emitter: it converts a fixed budget
# of energy per second into shots fired blind into its own sector, and the only thing the
# player controls is the geometry — where the wedge points and how wide it opens. Narrow
# it down a corridor and the shots run its whole length, hard and piercing; open it across
# the mouth of one and they become a wall that touches everything and stops none of it.
# ArcProfile owns every number that trade moves. AoE habits pulse their cone on the same
# rules instead of spawning projectiles. Support habits (Anchor line) never fire at all.
#
# What this replaced, and why it is worth not going back to: the habit used to lock the
# nearest distraction in its cone, slew the barrel at 8 rad/s and fire only once aligned.
# That made the cone a passive filter — the player aimed a region and the tower did the
# aiming that mattered — and it made the angle a range stat rather than a decision.

var cooldown := 0.0
var _pulse_progress := 0.0
var _recoil: float = 0.0
var _barrel_side: int = 0
var _muzzle_flash_alpha: float = 0.0

# Pomodoro work cycle (focus_timer line only — see its Data entry). Only habits with a
# work_duration participate; everything else fires uninterrupted as before.
var work_left: float = 0.0
var break_left: float = 0.0
var burned_out: bool = false   # true when the current break was forced, not chosen

## Disruptor ping (Group Chat): the habit is "looking at its phone" — no targeting,
## no firing until this runs out. Independent of the Pomodoro break by design: a
## disrupted habit can still be SENT on a break, and the timers don't feed each other.
var disrupted_left: float = 0.0

func disrupt(duration: float) -> void:
	disrupted_left = maxf(disrupted_left, duration)
	queue_redraw()

# Directional cone state
var facing_angle: float = 0.0     # center of cone in radians
var arc_angle: float = 60.0       # cone width in degrees (ArcProfile.ARC_MIN .. ARC_MAX)
var _aim: float = 0.0             # current live barrel orientation in radians

## Everything the cone width decides — damage, pierce, rate, hitbox, impulse, lane count.
## Recomputed on every set_arc_angle() and never per shot; see ArcProfile.
var _profile := ArcProfile.new()

## Which firing lane the next shot uses, and where the barrel is being dragged. The barrel
## chases the last shot rather than leading it, so a wide fan visibly rakes across its
## wedge while a narrow one barely twitches — the sprite reports the spread for free.
var _shot_index: int = 0
var _spray_angle: float = 0.0

## Per-habit RNG for the sub-lane jitter. Global randf() would leave two towers of the
## same type firing in lockstep whenever their cooldowns happened to align.
var _rng := RandomNumberGenerator.new()

# Base stats (immutable after setup)
var base_willpower_damage: int
var base_awareness_damage: int
var base_attack_range: float
var base_fire_cooldown: float

# Live stats (recalculated by ModifierManager)
var current_willpower_damage: int
var current_awareness_damage: int
var current_attack_range: float
var current_fire_cooldown: float

func _setup_specific(initial_facing: float, initial_arc: float) -> void:
	facing_angle = initial_facing
	_spray_angle = initial_facing
	_rng.randomize()
	# def.arc_angle always exists (every habit's data defines it), so the old
	# def.get("arc_angle", initial_arc) always resolved to def.arc_angle in practice —
	# the initial_arc param was already dead here before this refactor; preserved as-is.
	set_arc_angle(initial_arc)
	_aim = facing_angle
	work_left = def.work_duration
	# Head art must load HERE, not in _ready(): build_habit() add_child()s first and
	# calls setup() after, so at _ready() time type_key is still empty.
	_load_head_art()
	# Same trap as above: skip the shared disc for heads that sculpt their own plinth
	# (see HabitData.has_own_pedestal) — a monument head centers past the small shared
	# disc and pokes it out through its own middle instead of sitting on top of it.
	if not def.has_own_pedestal and FileAccess.file_exists("res://assets/towers/tower_base.png"):
		_base_tex = load("res://assets/towers/tower_base.png")

	base_willpower_damage = def.willpower_damage
	base_awareness_damage = def.awareness_damage
	base_attack_range = def.range
	base_fire_cooldown = def.fire_cooldown

	ModifierManager.modifiers_updated.connect(_recalculate_stats)
	_recalculate_stats()
	queue_redraw()

# ---------------------------------------------------------------- the cone as a dial
#
# Setting the width is the whole tactical decision, so it is also the only place the
# derived combat numbers are computed. Anything that moves `arc_angle` has to come
# through here — the profile and the angle can then never disagree.

func set_arc_angle(deg: float) -> void:
	arc_angle = clampf(deg, ArcProfile.ARC_MIN, ArcProfile.ARC_MAX)
	if def != null:
		_profile.recompute(def, arc_angle)

## Read-only view of the derived stats, for the HUD and for tests. Handing out the live
## object rather than copying it is safe because nothing outside set_arc_angle() writes
## to it, and a per-frame copy for a panel readout would be silly.
func arc_profile() -> ArcProfile:
	return _profile

## Seconds between shots at the current width — fire_cooldown shaped by the angle.
func shot_interval() -> float:
	return _profile.shot_interval(current_fire_cooldown)

## Whether anything is standing in the wedge right now. NOT used to decide whether to
## fire (the habit fires regardless — that is the point) — only to decide whether the
## Pomodoro is spending its work interval. A Focus Timer that burned out on schedule
## whether or not there was anything to focus ON would be a timer, not a habit.
func has_enemy_in_cone() -> bool:
	if game == null:
		return false
	for d in game.get_live_distractions():
		if is_instance_valid(d) and not d.dead and is_point_in_cone(d.global_position):
			return true
	return false

## has_enemy_in_cone() costs a cone test (with a wall raycast) per live distraction, and
## the work interval it feeds is measured in SECONDS — polling it every frame would spend
## per-frame money on a per-second question. Sampled instead, and the result held between
## samples; the interval drains by full delta either way, so the only thing at stake is
## how fast the meter notices a change, not how fast it drains.
const WORK_POLL_INTERVAL := 0.15
var _work_poll_t := 0.0
var _work_poll_result := false

func _enemy_in_cone_sampled(delta: float) -> bool:
	_work_poll_t -= delta
	if _work_poll_t <= 0.0:
		_work_poll_t = WORK_POLL_INTERVAL
		_work_poll_result = has_enemy_in_cone()
	return _work_poll_result

func has_work_cycle() -> bool:
	return def.has_work_cycle

func is_resting() -> bool:
	return break_left > 0.0

## Player-triggered rest. Cheap precisely because it was chosen: the same habit run dry
## costs break_long instead. Deliberate rest beats being forced to stop.
func take_break(forced: bool = false) -> void:
	if not has_work_cycle() or is_resting():
		return
	start_break(def.break_long if forced else def.break_short, forced)

func start_break(duration: float, forced: bool) -> void:
	break_left = duration
	burned_out = forced
	queue_redraw()

## Vector math filtering for directional cone sector.
func is_point_in_cone(target_pos: Vector2) -> bool:
	var dist := global_position.distance_to(target_pos)
	if dist > current_attack_range:
		return false
	if dist < 1.0:
		return true
	var facing_dir := Vector2.RIGHT.rotated(facing_angle)
	var target_dir := (target_pos - global_position).normalized()
	var angle_diff := absf(facing_dir.angle_to(target_dir))
	if angle_diff > deg_to_rad(arc_angle / 2.0):
		return false
	# The Brain Fog shades the cone the same way walls do: a body standing in the dark is
	# simply not in it. Suppression has no target selection to filter, so "can't hit what
	# you can't see" lives here (AoE pulses + the Pomodoro work check) and in the
	# projectile's hit loop — the two places a hit is actually decided.
	if game != null and not game.is_pos_visible(target_pos):
		return false
	# Walls shade the cone: anything behind high ground is simply not in it. Flyers over
	# a wall are shaded too — the wedge preview draws the same cast, and a preview that
	# never lies beats a special case the player cannot see.
	return game == null or game.has_line_of_sight(global_position, target_pos)

func _recalculate_stats() -> void:
	current_willpower_damage = int(ModifierManager.get_modified_stat(
		float(base_willpower_damage), ModifierManager.STAT_WILLPOWER, type_key))
	current_awareness_damage = int(ModifierManager.get_modified_stat(
		float(base_awareness_damage), ModifierManager.STAT_AWARENESS, type_key))
	current_attack_range = ModifierManager.get_modified_stat(
		base_attack_range, ModifierManager.STAT_RANGE, type_key)
	# Floor exists only to stop a division-by-zero-fast weapon; it must never bind on
	# authored data. It used to be 0.08, which silently clamped focus_timer_2's declared
	# 0.06 — a quarter of the Deep Focus upgrade's headline benefit — and made every
	# further cooldown card on that line a no-op.
	current_fire_cooldown = maxf(0.02, ModifierManager.get_modified_stat(
		base_fire_cooldown, ModifierManager.STAT_FIRE_COOLDOWN, type_key))
	queue_redraw()

## Idle barrel behaviour for every state that stops the habit firing — rest, a lost
## Routine, a disruptor ping. It drifts back to the cone's centre and stays there, so a
## stopped habit reads as stopped rather than merely quiet.
func _settle_barrel(delta: float) -> void:
	_spray_angle = facing_angle
	_aim = lerp_angle(_aim, facing_angle, 5.0 * delta)

func _process(delta: float) -> void:
	# Support habits (Anchor line) never target or fire — just the head animation and
	# the out-of-routine warning need to keep ticking.
	if def.is_support():
		if not _head_frames.is_empty():
			_anim_t += delta
			queue_redraw()
		elif not in_routine:
			queue_redraw()
		return

	var wave_active: bool = (game != null and game.started and not game.between_waves)

	# Rest runs on WAVE time, and it runs BEFORE the routine gate. Both halves used to
	# be wrong in opposite directions: breaks drained on wall-clock, so resting during
	# the untimed build phase was free (a rest that costs nothing teaches nothing) —
	# and the routine gate returned before this block, so a habit that fell out of
	# Routine mid-break froze there until the level ended.
	if has_work_cycle() and break_left > 0.0:
		if wave_active:
			break_left -= delta
			if break_left <= 0.0:
				break_left = 0.0
				burned_out = false
				work_left = def.work_duration
		_settle_barrel(delta)
		queue_redraw()
		return

	if not in_routine:
		_settle_barrel(delta)
		queue_redraw()
		return

	# Pinged by a disruptor — idle until the distraction passes. Wave time, like rest.
	if disrupted_left > 0.0:
		if wave_active:
			disrupted_left = maxf(0.0, disrupted_left - delta)
		_settle_barrel(delta)
		queue_redraw()
		return

	# Past every idle early-return, so rest/no-routine/disruption freeze the head sprite.
	if not _head_frames.is_empty():
		if def.charge_telegraph:
			_advance_charge_anim()
		else:
			_anim_t += delta
		queue_redraw()

	if _recoil > 0.001 or _muzzle_flash_alpha > 0.001:
		_recoil = lerpf(_recoil, 0.0, 16.0 * delta)
		_muzzle_flash_alpha = lerpf(_muzzle_flash_alpha, 0.0, 24.0 * delta)
		queue_redraw()

	# ------------------------------------------------------------ suppression stream
	#
	# There is no target and no alignment gate. The habit converts its energy budget into
	# shots aimed into the SECTOR, so the shots are already in the air when a distraction
	# walks into it — which is the entire reason the player is being asked to read the
	# corridor geometry instead of clicking on enemies.
	#
	# The one thing it will not do is fire at an empty board. Between spawns there is
	# nothing to suppress, and a screenful of bullets travelling at nobody costs pool
	# slots and per-frame collision passes while telling the player something false about
	# what the tower is doing. A board where everything alive is hidden in the Brain Fog
	# counts as empty for the same reason — you cannot suppress what you cannot see.
	var board_live: bool = wave_active and game.has_visible_distraction()

	# The Pomodoro spends its interval on WORK, not on ammunition: the trigger is that
	# something is in the wedge to be held off, not that the barrel happens to be moving.
	# Firing into an empty sector is free — it is warming up, not working.
	if has_work_cycle() and board_live and _enemy_in_cone_sampled(delta):
		work_left -= delta
		if work_left <= 0.0:
			work_left = 0.0
			start_break(def.break_long, true)
			queue_redraw()
			return

	cooldown -= delta
	if cooldown <= 0.0 and board_live:
		_fire()
		cooldown = shot_interval()

	# The barrel CHASES the last shot instead of leading it, so the sprite reports the
	# spread for free: a 120° fan visibly rakes across its wedge, a 15° beam barely
	# twitches. Faster than the old 8 rad/s slew because at ten shots a second a slow
	# barrel would just average out to the cone centre and read as static.
	_aim = lerp_angle(_aim, _spray_angle, 14.0 * delta)

	queue_redraw()

## One shot — or one pulse, for the AoE half of the roster. Split out of _process()
## because it is the point where the cone width stops being a preview and becomes damage,
## and because a test wants to call it without arranging a live wave first.
func _fire() -> void:
	_recoil = 1.0   # decays in _process; drawn as barrel push-back

	# Smooth soft muzzle flash fade
	_muzzle_flash_alpha = 1.0
	var tw_f := create_tween()
	tw_f.tween_property(self, "_muzzle_flash_alpha", 0.0, 0.14) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	if def.aoe:
		# A pulse has no lane to fire down: the cone IS the shot. The width still pays
		# for itself on the same curve — a narrowed pulse hits fewer bodies for more each.
		_spray_angle = facing_angle
		for d in _aoe_targets():
			apply_pulse_to(d)
		_pulse()
		return

	_barrel_side = 1 - _barrel_side
	var shot_angle: float = _profile.lane_angle(_shot_index, facing_angle, arc_angle, _rng)
	_shot_index += 1
	_spray_angle = shot_angle

	var dir := Vector2.RIGHT.rotated(shot_angle)
	var perp := dir.orthogonal()
	var side_offset := -5.0 if _barrel_side == 0 else 5.0
	var spawn_pos := global_position + (perp * side_offset) + (dir * 22.0)

	# A directional habit may carry a DoT too. Boredom used to be reachable only from the
	# AoE branch, which quietly forced every DoT habit to be a cone pulse — see
	# Projectile.boredom.
	game.spawn_directional_projectile(spawn_pos, shot_angle, current_attack_range,
		_profile.scale_damage(current_willpower_damage),
		_profile.scale_damage(current_awareness_damage),
		Color(def.projectile_color), self,
		def.boredom, def.boredom_duration, def.projectile_spin,
		_profile.pierce, _profile.hit_padding,
		_profile.knockback, _profile.stagger_factor)

## Everything one AoE pulse does to one distraction. Public and split out of _process()
## because the ORDER here is the whole design and it is invisible from the outside — a
## test can call this directly instead of trying to catch a live tower mid-shot.
##
## The order, and why:
##  1. Reframe strips resistance FIRST, so this pulse's own damage already gets the
##     opening it just made — that is what makes Mindfulness a set-up for itself.
##  2. Damage.
##  3. Slow, then Stun. apply_slow is strongest-wins and a freeze (0.0) beats anything,
##     so stunning after a partial slow costs nothing, while the reverse would let the
##     weaker slow be the one the player sees on a habit carrying both.
##  4. Dispel — clears Rush, leaves Overdrive (a latched phase change).
##  5. Vulnerability LAST, after the damage, so the pulse cannot amplify itself. This
##     debuff buys damage for the rest of the board; Reframe sits before the damage
##     precisely because it is meant to pay the caster too. The two read alike and do
##     opposite things, which is exactly why they are ordered on purpose.
func apply_pulse_to(d: Distraction) -> void:
	if def.reframe > 0:
		d.apply_reframe(def.reframe, def.reframe_duration)
	d.take_damage(_profile.scale_damage(current_willpower_damage),
		_profile.scale_damage(current_awareness_damage), self)
	# The physical response, on the same terms the projectile half gets it: a narrowed
	# pulse shoves outward from the tower, a widened one micro-staggers everything it
	# washes over. Applied before the authored slow so a real Calm still wins the compare.
	if _profile.knockback > 0.0:
		d.apply_knockback((d.global_position - global_position).normalized(),
			_profile.knockback)
	if _profile.stagger_factor < 1.0:
		d.apply_slow(_profile.stagger_factor, ArcProfile.STAGGER_TIME)
	if def.slow > 0.0:
		d.apply_slow(def.slow, def.slow_duration)
	if def.stun_duration > 0.0:
		d.apply_stun(def.stun_duration)
	if def.dispel_haste:
		d.dispel_haste()
	if def.vulnerable_mult > 1.0:
		d.apply_vulnerable(def.vulnerable_mult, def.vulnerable_duration)
	if def.boredom > 0.0:
		# `self` as source: each Real Hobby stacks its own dps, but one habit's
		# overlapping pulses don't stack with themselves.
		d.apply_boredom(def.boredom, def.boredom_duration, self)

# An AoE pulse used to damage EVERY body in the cone with no cap, no falloff and no
# per-pulse budget, so its damage scaled linearly with how many enemies happened to be
# standing there — Mindfulness+ into a 20-strong clump out-damaged every single-target
# habit in the game by an order of magnitude, for less money. Capping it makes the two
# archetypes distinct rather than one dominating: cone habits are AREA, bounded;
# projectile habits are LINE, bounded (see ArcProfile.MAX_PIERCE).
#
# Nearest-first, because a pulse that spends its budget on the back of the queue while
# the front walks past would read as broken.
#
# The cap is no longer a constant: it is the AoE mirror of pierce, and it moves with the
# cone width on the same curve (ArcProfile.aoe_targets). Narrow a Mindfulness down and it
# stops being area denial — it becomes a single-target armour shredder hitting for more.
# Same energy, different shape, which is the rule the whole roster now shares.

func _aoe_targets() -> Array:
	var cap: int = _profile.aoe_targets
	var in_cone: Array = []
	for d in game.get_live_distractions():
		if is_instance_valid(d) and not d.dead and is_point_in_cone(d.global_position):
			in_cone.append(d)
	if in_cone.size() <= cap:
		return in_cone
	var origin: Vector2 = global_position
	in_cone.sort_custom(func(a, b):
		return origin.distance_squared_to(a.global_position) \
			< origin.distance_squared_to(b.global_position))
	return in_cone.slice(0, cap)

func _pulse() -> void:
	var tw := create_tween()
	tw.tween_method(_set_pulse, 0.0, 1.0, 0.45)

func _set_pulse(v: float) -> void:
	_pulse_progress = v
	queue_redraw()

## The AoE activation as a WAVE travelling through the cone — flashing the whole wedge
## area read as a glitch, not an effect ("rozpětí problikává"). Two chunky arcs (front +
## fainter trailer) expand from the tower to its range and fade out; blocks behind a wall
## are skipped via the same cast that gates targeting, so the wave visibly breaks on
## terrain exactly where the damage does.
func _draw_pulse_wave() -> void:
	var wave_r: float = current_attack_range * _pulse_progress
	if wave_r < 3.0:
		return
	var wave_a: float = (1.0 - _pulse_progress) * 0.9
	var half: float = deg_to_rad(arc_angle / 2.0)
	for pass_i in range(2):
		var r := wave_r - 9.0 * float(pass_i)
		if r <= 3.0:
			continue
		var col := Color(_color.r, _color.g, _color.b, wave_a * (1.0 if pass_i == 0 else 0.4))
		var n := maxi(int(2.0 * half * r / 5.0), 8)
		var s := 3.0
		var last := Vector2.INF
		for i in range(n + 1):
			var a := facing_angle - half + 2.0 * half * float(i) / float(n)
			var dirv := Vector2.RIGHT.rotated(a)
			if game != null and game.cast_to_wall(global_position, dirv, r + 6.0) < r:
				continue
			var p := (dirv * r / s).floor() * s
			if p == last:
				continue
			last = p
			draw_rect(Rect2(p, Vector2(s, s)), col)

var _base_tex: Texture2D
var _head_tex: Texture2D
var _head_frames: Array[Texture2D] = []

## Head art lives in assets/towers/ as head_<type_key>.png plus optional animation
## frames head_<type_key>_frame_1.png, _2, ... A tier-2 habit with no art of its own
## falls back to the tier-1 files (mindfulness_2 -> mindfulness), so upgrades inherit
## the look until they earn a dedicated sprite.
##
## The animation clock (_anim_t) only advances while the habit actually works, so a
## break, a lost Routine or a disruptor ping literally STOP the hourglass — state you
## can read from the sprite alone.
const HEAD_FPS := 8.0
var _anim_t := 0.0

## Which way each type's art points; the draw rotation closes the gap to _aim. PixelLab
## generated the focus_timer_2 barrel at 45 degrees no matter how the prompt fought it,
## and compensating here is free — the head is GPU-rotated every frame anyway, while
## re-rotating the PNG offline chews the pixels.
const ART_FACING := {"focus_timer_2": PI * 0.75, "exercise": 0.0, "exercise_2": 0.0}

func _head_art_key() -> String:
	if FileAccess.file_exists("res://assets/towers/head_%s.png" % type_key) \
			or FileAccess.file_exists("res://assets/towers/head_%s_frame_1.png" % type_key):
		return type_key
	# Fall back to the tier-1 root of the upgrade line. This used to be
	# `trim_suffix("_2")`, which only worked while every line had exactly one upgrade
	# named <root>_2 — a BRANCHING line (zen_pulsar -> _2a / _2b) trimmed to nothing and
	# the upgraded habit silently lost its sprite. Data.habit_family() walks the actual
	# `upgrades` edges, so it handles any depth and any branch shape.
	return String(Data.habit_family(type_key))

## Pins the head animation to the reload instead of letting it free-run, so a telegraphed
## habit's sprite reads as its countdown: first frame the instant it fires, last frame when
## it is ready again. Both sides get to plan around the beat — which is the whole point of
## a habit that hits hard on a long timer instead of chipping continuously.
##
## `cooldown` goes NEGATIVE while a charged habit waits for something to walk into its
## cone (it is only reset on an actual shot), so progress is clamped: past 1.0 the sprite
## holds the fully-charged frame rather than wrapping back to the discharge.
func _advance_charge_anim() -> void:
	var full: float = maxf(0.001, current_fire_cooldown)
	var progress: float = clampf(1.0 - cooldown / full, 0.0, 1.0)
	var last: int = _head_frames.size() - 1
	var idx: int = clampi(int(progress * float(_head_frames.size())), 0, last)
	_anim_t = float(idx) / HEAD_FPS

## Which animation frame the head clock currently lands on.
func _frame_index() -> int:
	return int(_anim_t * HEAD_FPS) % _head_frames.size()

## Current frame when animated, the static sprite otherwise, null when no art exists.
func _current_head_tex() -> Texture2D:
	if not _head_frames.is_empty():
		return _head_frames[_frame_index()]
	return _head_tex

func _ready() -> void:
	# Tower sprites are pixel art now; anything but whole-multiple nearest scaling mushes.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# The shared pedestal is loaded in _setup_specific(), not here: it now depends on
	# def.has_own_pedestal, and def is still null at _ready() time (see the comment on
	# _load_head_art() below for why — same trap, same fix).

func _load_head_art() -> void:
	_head_tex = null
	_head_frames.clear()
	var key := _head_art_key()
	var static_path := "res://assets/towers/head_%s.png" % key
	if FileAccess.file_exists(static_path):
		_head_tex = load(static_path)
	for i in range(1, 33):
		var p := "res://assets/towers/head_%s_frame_%d.png" % [key, i]
		if not FileAccess.file_exists(p):
			break
		_head_frames.append(load(p))
	if _head_tex == null and not _head_frames.is_empty():
		_head_tex = _head_frames[0]

## One art pixel draws as the same screen block as everything else on the map, so head art
## can be authored at whatever size the design needs and the pixel density never changes
## between a tower and the distraction walking past it.
##
## This replaced a fit-to-cell `floor(tile / width)`, which capped useful head art at 24px:
## 32px art landed on floor(48/32) = 1, i.e. the head would SHRINK and draw one art pixel
## per screen pixel. Fixing that with a hardcoded 2.0 traded one mismatch for a quieter
## one — the ground was already at 3.0. Data.pixel_scale() is the single source now.

func _draw_head_sprite(tex: Texture2D, tint: Color, rot: float = 0.0, offset: Vector2 = Vector2.ZERO) -> void:
	var size := Vector2(tex.get_size()) * Data.pixel_scale()
	var transformed := rot != 0.0 or offset != Vector2.ZERO
	if transformed:
		draw_set_transform(offset, rot, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-size / 2.0, size), false, tint)
	if transformed:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw() -> void:
	var tile: int = Data.GRID.tile
	var base_r: float = tile * 0.42
	var resting: bool = is_resting()
	var main_col: Color = _color.darkened(0.45) if resting else _color

	# Support habits get their own look — an Anchor drawn as a turret with barrels
	# promises damage it will never deal. A pylon with a diamond marker reads as
	# infrastructure, and its range ring is the Routine radius it actually projects.
	if def.is_support():
		var support_head := _current_head_tex()
		if _base_tex != null and support_head != null:
			var sb_size := Vector2(_base_tex.get_size()) * Data.pixel_scale()
			draw_texture_rect(_base_tex, Rect2(-sb_size / 2.0, sb_size), false,
				Color(1, 1, 1, 0.5) if resting else Color.WHITE)
			_draw_head_sprite(support_head, Color.WHITE if in_routine else Color(0.6, 0.6, 0.6, 0.8))
		else:
			_draw_oct_base(base_r, Color("161a26"))
			draw_circle(Vector2.ZERO, base_r * 0.55, Color("1b2030"))
			PixelDraw.arc(self, Vector2.ZERO, base_r * 0.55, main_col, 1.0, 1.2)
			var dr := base_r * 0.3
			var diamond := PackedVector2Array([
				Vector2(0, -dr), Vector2(dr, 0), Vector2(0, dr), Vector2(-dr, 0)])
			draw_colored_polygon(diamond, main_col)
		if show_range_indicator:
			draw_circle(Vector2.ZERO, def.range, Color(main_col.r, main_col.g, main_col.b, 0.08))
			PixelDraw.arc(self, Vector2.ZERO, def.range, Color(main_col.r, main_col.g, main_col.b, 0.7), 1.0, 2.5)
		if not in_routine:
			var flash_a := (sin(Time.get_ticks_msec() * 0.008) * 0.35) + 0.65
			draw_string(ThemeDB.fallback_font, Vector2(-34, -base_r - 14), "⚠ NO ROUTINE",
				HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(1.0, 0.8, 0.2, flash_a))
		return

	# 0. PEDESTAL CONTACT SHADOW (Anchors tower firmly to ground)
	draw_set_transform(Vector2(0.0, base_r * 0.45), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, base_r * 1.15, Color(0.01, 0.01, 0.04, 0.15))
	draw_circle(Vector2.ZERO, base_r * 0.85, Color(0.01, 0.01, 0.04, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 1. FIXED PEDESTAL BASE (PNG Sprite or Vector Fallback)
	if _base_tex != null:
		var b_size := Vector2(_base_tex.get_size()) * Data.pixel_scale()
		draw_texture_rect(_base_tex, Rect2(-b_size / 2.0, b_size), false, Color(1, 1, 1, 0.5) if resting else Color.WHITE)
	else:
		_draw_oct_base(base_r, Color("161a26"))
		draw_arc(Vector2.ZERO, base_r - 3.0, 0.0, TAU, 24, Color("3b4561"), 2.5)

	# 2. ROTATING TURRET TOP (PNG Sprite or Vector Fallback)
	var dir := Vector2.RIGHT.rotated(_aim)
	var perp := dir.orthogonal()
	var recoil_offset := -_recoil * 6.0
	var head_tex := _current_head_tex()

	if head_tex != null and not def.aoe and def.head_aims:
		var head_tint := Color(0.6, 0.6, 0.6, 0.6) if resting else Color.WHITE
		var art_facing: float = ART_FACING.get(_head_art_key(), -PI / 2.0)
		_draw_head_sprite(head_tex, head_tint, _aim - art_facing, dir * recoil_offset)
	elif head_tex != null and (def.aoe or not def.head_aims):
		# Heads that do not aim: AoE pulses (the sprite's own animation carries the life)
		# and directional habits whose art would read wrong spinning — the Tome fires its
		# pages along _aim while the book itself stays open and still.
		_draw_head_sprite(head_tex, Color(0.6, 0.6, 0.6, 0.6) if resting else Color.WHITE)
	elif def.aoe: # Mindfulness / Meditation Crystal Orb (vector fallback)
		var crystal_r := base_r * 0.6
		draw_circle(Vector2.ZERO, crystal_r + 3.0, Color(main_col.r, main_col.g, main_col.b, 0.25))
		draw_circle(Vector2.ZERO, crystal_r, Color("1b2030"))
		draw_circle(Vector2.ZERO, crystal_r * 0.7, main_col)
		draw_circle(Vector2.ZERO, crystal_r * 0.35, Color.WHITE)
		PixelDraw.arc(self, Vector2.ZERO, crystal_r + 4.0, Color(1, 1, 1, 0.5), 1.0, 1.5)
	else: # Standard Heavy Dual-Barrel Turret (Vector Fallback)
		var b_len: float = (tile * 0.68) + recoil_offset
		var offset_p := perp * 6.5
		draw_line(-offset_p, -offset_p + dir * b_len, Color("141722"), 8.0)
		draw_line(offset_p, offset_p + dir * b_len, Color("141722"), 8.0)
		draw_line(-offset_p, -offset_p + dir * b_len, Color("293145"), 5.0)
		draw_line(offset_p, offset_p + dir * b_len, Color("293145"), 5.0)
		draw_line(-offset_p, -offset_p + dir * b_len, main_col, 2.5)
		draw_line(offset_p, offset_p + dir * b_len, main_col, 2.5)
		draw_circle(-offset_p + dir * b_len, 2.0, Color.WHITE)
		draw_circle(offset_p + dir * b_len, 2.0, Color.WHITE)
		draw_circle(Vector2.ZERO, base_r * 0.58, Color("151924"))
		draw_circle(Vector2.ZERO, base_r * 0.44, main_col)
		draw_circle(Vector2.ZERO, base_r * 0.22, Color.WHITE)

	# 3. MUZZLE FLASH EFFECT (At active barrel tip)
	if _muzzle_flash_alpha > 0.01 and not def.aoe:
		var side_offset := -6.0 if _barrel_side == 0 else 6.0
		var flash_tip := (dir * (tile * 0.65)) + (perp * side_offset)
		# Muzzle flash as collapsing raster blocks — matches ImpactFX's centre flash.
		var mf_units := 3.0 if _muzzle_flash_alpha > 0.66 else (2.0 if _muzzle_flash_alpha > 0.33 else 1.0)
		var mf_s := 3.0 * mf_units
		draw_rect(Rect2(flash_tip - Vector2(mf_s, mf_s) * 0.5, Vector2(mf_s, mf_s)), Color(1, 1, 1, _muzzle_flash_alpha))
		draw_rect(Rect2(flash_tip - Vector2(mf_s, mf_s) * 0.85, Vector2(mf_s, mf_s) * 1.7),
			Color(_color.r, _color.g, _color.b, _muzzle_flash_alpha * 0.45))

	# 3. WORK-INTERVAL BAR (Pomodoro ammo / rest meter — drawn BELOW pedestal)
	if has_work_cycle():
		var w: float = tile * 0.76
		var y: float = base_r + 7.0
		draw_rect(Rect2(-w / 2.0 - 1.0, y - 1.0, w + 2.0, 6.0), Color(0, 0, 0, 0.75))
		if resting:
			var total: float = def.break_long if burned_out else def.break_short
			var done: float = clampf(1.0 - break_left / maxf(total, 0.001), 0.0, 1.0)
			draw_rect(Rect2(-w / 2.0, y, w * done, 4.0),
				Color("ff4455") if burned_out else Color("2bd6c0"))
		else:
			var left: float = clampf(work_left / maxf(float(def.work_duration), 0.001), 0.0, 1.0)
			draw_rect(Rect2(-w / 2.0, y, w * left, 4.0),
				Color("ffd479") if left < 0.3 else Color("35ff8d"))

	# 4. PULSE VISUAL (AoE activation): expanding wave, not a full-area flash
	if _pulse_progress > 0.0 and _pulse_progress < 1.0:
		_draw_pulse_wave()

	# 5. RANGE INDICATOR OVERLAY (When selected or aiming)
	if show_range_indicator:
		_draw_wedge(current_attack_range, facing_angle, arc_angle, Color(0.35, 1.0, 0.55, 0.18), Color(0.35, 1.0, 0.55, 0.8))

	# 6. OUT-OF-ROUTINE WARNING — this habit has nothing in the player's day holding it
	# up, so it has stalled. Build an Anchor near it, or place habits closer to Focus.
	if not in_routine:
		var font = ThemeDB.fallback_font
		var flash_a := (sin(Time.get_ticks_msec() * 0.008) * 0.35) + 0.65
		draw_string(font, Vector2(-34, -base_r - 14), "⚠ NO ROUTINE", HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(1.0, 0.8, 0.2, flash_a))

	# 7. DISRUPTED — a Group Chat pinged this habit; it is looking at its phone.
	elif disrupted_left > 0.0:
		var flash_d := (sin(Time.get_ticks_msec() * 0.012) * 0.35) + 0.65
		draw_string(ThemeDB.fallback_font, Vector2(-38, -base_r - 14), "⚡ DISTRACTED",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(1.0, 0.55, 0.3, flash_d))

func _draw_oct_base(r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(8):
		var a = float(i) * TAU / 8.0 + (TAU / 16.0)
		pts.append(Vector2.RIGHT.rotated(a) * r)
	draw_colored_polygon(pts, color)
	pts.append(pts[0])
	draw_polyline(pts, Color(color.r * 1.5, color.g * 1.5, color.b * 1.5, 0.5), 1.5)

func _draw_wedge(radius: float, center_angle: float, fov_degrees: float, fill_color: Color, line_color: Color = Color.TRANSPARENT) -> void:
	var half_fov: float = deg_to_rad(fov_degrees / 2.0)
	var start_angle: float = center_angle - half_fov
	var end_angle: float = center_angle + half_fov
	# Enough rays that the outline blocks stay contiguous along the far edge.
	var num_segments: int = clampi(int((end_angle - start_angle) * radius / 6.0), 24, 160)

	# Every ray is clamped at the first wall — game.cast_to_wall, the same cast that
	# kills projectiles and filters targets — so the drawn wedge IS the covered area,
	# wall shadows included, and the preview cannot promise a shot the tower cannot take.
	var pts := PackedVector2Array([Vector2.ZERO])
	for i: int in range(num_segments + 1):
		var t: float = float(i) / float(num_segments)
		var a: float = lerpf(start_angle, end_angle, t)
		var dirv := Vector2.RIGHT.rotated(a)
		var r := radius
		if game != null:
			r = game.cast_to_wall(global_position, dirv, radius)
		pts.append(dirv * r)

	draw_colored_polygon(pts, fill_color)

	# Outline in raster blocks tracing the clamped boundary — where a wall cuts the
	# wedge, the blocks jump inward with it. The smooth polyline was the big screaming
	# circle whenever a tower was selected.
	if line_color.a > 0.0:
		var s := 3.0
		var last := Vector2.INF
		for i in range(1, pts.size()):
			var p := (pts[i] / s).floor() * s
			if p == last:
				continue
			last = p
			draw_rect(Rect2(p, Vector2(s, s)), line_color)
		if fov_degrees < 359.0:
			PixelDraw.line(self, Vector2.ZERO, pts[1], line_color, 1.0, 2.5)
			PixelDraw.line(self, Vector2.ZERO, pts[pts.size() - 1], line_color, 1.0, 2.5)
