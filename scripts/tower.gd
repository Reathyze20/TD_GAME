class_name Habit
extends BaseHabit
# A placed healthy habit defending attention.
# Targeting: locks onto the nearest live distraction inside its aim cone, slews the
# barrel toward it (8 rad/s) and fires directional projectiles along the barrel (_aim)
# once it is within AIM_TOLERANCE_DEG. AoE habits pulse the whole cone instead.
# Support habits (Anchor line — no damage, no AoE) never target or fire at all.

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
var arc_angle: float = 60.0       # cone width in degrees (10° .. 125°)
var _aim: float = 0.0             # current live barrel orientation in radians

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
	# def.arc_angle always exists (every habit's data defines it), so the old
	# def.get("arc_angle", initial_arc) always resolved to def.arc_angle in practice —
	# the initial_arc param was already dead here before this refactor; preserved as-is.
	set_arc_angle(initial_arc)
	_aim = facing_angle
	work_left = def.work_duration
	# Head art must load HERE, not in _ready(): build_habit() add_child()s first and
	# calls setup() after, so at _ready() time type_key is still empty.
	_load_head_art()

	base_willpower_damage = def.willpower_damage
	base_awareness_damage = def.awareness_damage
	base_attack_range = def.range
	base_fire_cooldown = def.fire_cooldown

	ModifierManager.modifiers_updated.connect(_recalculate_stats)
	_recalculate_stats()
	queue_redraw()

## How far off the barrel may be and still fire (degrees). See the gate in _process().
const AIM_TOLERANCE_DEG := 12.0

# ---------------------------------------------------------------- targeting modes
#
# The standard TD set. NEAREST is the default and re-picks every frame (the original
# feel). The other modes HOLD their locked target while it stays alive and in-cone:
# re-picking each frame thrashes the 8 rad/s barrel slew against the aim-tolerance
# gate — STRONGEST/WEAKEST would ping-pong between equal-health targets on every hit
# and the tower would never fire.

enum TargetMode { NEAREST, FIRST, STRONGEST, WEAKEST }
const TARGET_MODE_NAMES := {
	TargetMode.NEAREST: "Nearest", TargetMode.FIRST: "First",
	TargetMode.STRONGEST: "Strongest", TargetMode.WEAKEST: "Weakest",
}

## Copied to the replacement node by BuildSpot.upgrade_habit(), like the combat record.
var target_mode: TargetMode = TargetMode.NEAREST
var _locked_target: Distraction = null

func cycle_target_mode() -> void:
	target_mode = ((int(target_mode) + 1) % TargetMode.size()) as TargetMode
	_locked_target = null

func target_mode_name() -> String:
	return TARGET_MODE_NAMES[target_mode]

func _pick_target() -> Distraction:
	if target_mode != TargetMode.NEAREST:
		if is_instance_valid(_locked_target) and not _locked_target.dead \
				and is_point_in_cone(_locked_target.global_position):
			return _locked_target
		_locked_target = null
	var best: Distraction = null
	var best_score := INF
	for d in game.get_live_distractions():
		if not is_instance_valid(d) or d.dead or not is_point_in_cone(d.global_position):
			continue
		var score: float
		match target_mode:
			TargetMode.FIRST:
				# Furthest along its route = least remaining path. Flyers have no
				# route; distance to the core is the same "closest to hurting you".
				score = d.distance_to_core() if d.is_flying \
					else float(d.cell_path.size() - d.path_index) * float(Data.GRID.tile)
			TargetMode.STRONGEST:
				score = -float(d.current_health)
			TargetMode.WEAKEST:
				score = float(d.current_health)
			_:
				score = global_position.distance_squared_to(d.global_position)
		if score < best_score:
			best_score = score
			best = d
	if target_mode != TargetMode.NEAREST:
		_locked_target = best
	return best

func set_arc_angle(deg: float) -> void:
	arc_angle = clampf(deg, 10.0, 125.0)

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
		_aim = lerp_angle(_aim, facing_angle, 5.0 * delta)
		queue_redraw()
		return

	if not in_routine:
		_aim = lerp_angle(_aim, facing_angle, 5.0 * delta)
		queue_redraw()
		return

	# Pinged by a disruptor — idle until the distraction passes. Wave time, like rest.
	if disrupted_left > 0.0:
		if wave_active:
			disrupted_left = maxf(0.0, disrupted_left - delta)
		_aim = lerp_angle(_aim, facing_angle, 5.0 * delta)
		queue_redraw()
		return

	# Past every idle early-return, so rest/no-routine/disruption freeze the head sprite.
	if not _head_frames.is_empty():
		_anim_t += delta
		queue_redraw()

	if _recoil > 0.001 or _muzzle_flash_alpha > 0.001:
		_recoil = lerpf(_recoil, 0.0, 16.0 * delta)
		_muzzle_flash_alpha = lerpf(_muzzle_flash_alpha, 0.0, 24.0 * delta)
		queue_redraw()

	var target_enemy: Distraction = _pick_target() if wave_active else null

	# Spend work/ammo duration ONLY when actively targeting/firing at an enemy!
	if has_work_cycle() and wave_active and target_enemy != null:
		work_left -= delta
		if work_left <= 0.0:
			work_left = 0.0
			start_break(def.break_long, true)
			queue_redraw()
			return

	# The barrel slews toward the target rather than snapping, and firing used to be gated
	# on the cooldown alone — so every time the nearest-target pick flipped (constantly, in
	# a swarm) the habit dumped its next few shots into empty space. Now a shot also has to
	# wait for the barrel to actually point at something.
	var aim_error := TAU
	if target_enemy != null:
		var target_angle = (target_enemy.global_position - global_position).angle()
		_aim = lerp_angle(_aim, target_angle, 8.0 * delta)
		aim_error = absf(angle_difference(_aim, target_angle))
	else:
		_aim = lerp_angle(_aim, facing_angle, 5.0 * delta)

	cooldown -= delta
	if cooldown <= 0.0:
		# AoE resolves inside the cone and doesn't care where the barrel points; only the
		# projectile line does. Tolerant on purpose — with a wider hit window and pierce, a
		# slightly-off shot still connects, and a gate this could never satisfy would be
		# worse than the wasted shots it replaces.
		var aimed: bool = def.aoe or aim_error <= deg_to_rad(AIM_TOLERANCE_DEG)
		if wave_active and target_enemy != null and aimed:
			_barrel_side = 1 - _barrel_side
			_recoil = 1.0   # decays in the block above; drawn as barrel push-back

			# Smooth Soft Muzzle Flash Fade
			_muzzle_flash_alpha = 1.0
			var tw_f := create_tween()
			tw_f.tween_property(self, "_muzzle_flash_alpha", 0.0, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

			if def.aoe:
				for d in _aoe_targets():
					# Reframe first, so this pulse's own damage already benefits
					# from the opening it just made.
					if def.reframe > 0:
						d.apply_reframe(def.reframe, def.reframe_duration)
					d.take_damage(current_willpower_damage, current_awareness_damage, self)
					if def.slow > 0.0:
						d.apply_slow(def.slow, def.slow_duration)
					if def.boredom > 0.0:
						# `self` as source: each Real Hobby stacks its own dps, but one
						# habit's overlapping pulses don't stack with themselves.
						d.apply_boredom(def.boredom, def.boredom_duration, self)
				_pulse()
			else:
				# Continuous firing along _aim barrel orientation alternating left/right!
				var dir := Vector2.RIGHT.rotated(_aim)
				var perp := dir.orthogonal()
				var side_offset := -5.0 if _barrel_side == 0 else 5.0
				var spawn_pos := global_position + (perp * side_offset) + (dir * 22.0)
				game.spawn_directional_projectile(spawn_pos, _aim, current_attack_range,
					current_willpower_damage, current_awareness_damage,
					Color(def.projectile_color), self)
			cooldown = current_fire_cooldown

	queue_redraw()

# An AoE pulse used to damage EVERY body in the cone with no cap, no falloff and no
# per-pulse budget, so its damage scaled linearly with how many enemies happened to be
# standing there — Mindfulness+ into a 20-strong clump out-damaged every single-target
# habit in the game by an order of magnitude, for less money. Capping it makes the two
# archetypes distinct rather than one dominating: cone habits are AREA, bounded;
# projectile habits are LINE, bounded (see Projectile.MAX_PIERCE).
#
# Nearest-first, because a pulse that spends its budget on the back of the queue while
# the front walks past would read as broken.
const AOE_MAX_TARGETS := 6

func _aoe_targets() -> Array:
	var in_cone: Array = []
	for d in game.get_live_distractions():
		if is_instance_valid(d) and not d.dead and is_point_in_cone(d.global_position):
			in_cone.append(d)
	if in_cone.size() <= AOE_MAX_TARGETS:
		return in_cone
	var origin: Vector2 = global_position
	in_cone.sort_custom(func(a, b):
		return origin.distance_squared_to(a.global_position) \
			< origin.distance_squared_to(b.global_position))
	return in_cone.slice(0, AOE_MAX_TARGETS)

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
	return type_key.trim_suffix("_2")

## Current frame when animated, the static sprite otherwise, null when no art exists.
func _current_head_tex() -> Texture2D:
	if not _head_frames.is_empty():
		return _head_frames[int(_anim_t * HEAD_FPS) % _head_frames.size()]
	return _head_tex

func _ready() -> void:
	# Tower sprites are pixel art now; anything but whole-multiple nearest scaling mushes.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if FileAccess.file_exists("res://assets/towers/tower_base.png"):
		_base_tex = load("res://assets/towers/tower_base.png")

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

## Draws `tex` centred at native size x whole zoom (16px art x3 on a 48px cell).
func _draw_head_sprite(tex: Texture2D, tint: Color, rot: float = 0.0, offset: Vector2 = Vector2.ZERO) -> void:
	var zoom := maxf(1.0, floorf(float(Data.GRID.tile) / tex.get_width()))
	var size := Vector2(tex.get_size()) * zoom
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
			var sb_zoom := maxf(1.0, floorf(float(tile) / _base_tex.get_width()))
			var sb_size := Vector2(_base_tex.get_size()) * sb_zoom
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

	# 1. FIXED PEDESTAL BASE (PNG Sprite or Vector Fallback)
	if _base_tex != null:
		# Native size x whole zoom (48px art x1, 16px art x3). The old tile * 1.15 rect
		# stretched the texture fractionally, which blurs pixel art even under NEAREST.
		var b_zoom := maxf(1.0, floorf(float(tile) / _base_tex.get_width()))
		var b_size := Vector2(_base_tex.get_size()) * b_zoom
		draw_texture_rect(_base_tex, Rect2(-b_size / 2.0, b_size), false, Color(1, 1, 1, 0.5) if resting else Color.WHITE)
	else:
		_draw_oct_base(base_r, Color("161a26"))
		draw_arc(Vector2.ZERO, base_r - 3.0, 0.0, TAU, 24, Color("3b4561"), 2.5)

	# 2. ROTATING TURRET TOP (PNG Sprite or Vector Fallback)
	var dir := Vector2.RIGHT.rotated(_aim)
	var perp := dir.orthogonal()
	var recoil_offset := -_recoil * 6.0
	var head_tex := _current_head_tex()

	if head_tex != null and not def.aoe:
		var head_tint := Color(0.6, 0.6, 0.6, 0.6) if resting else Color.WHITE
		var art_facing: float = ART_FACING.get(_head_art_key(), -PI / 2.0)
		_draw_head_sprite(head_tex, head_tint, _aim - art_facing, dir * recoil_offset)
	elif def.aoe and head_tex != null:
		# AoE heads do not aim — the sprite sits still and its animation carries the life.
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
