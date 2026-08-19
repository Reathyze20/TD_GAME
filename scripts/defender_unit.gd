class_name DefenderUnit
extends Node2D
# One melee defender on the field. Two employers, one body:
#
#  * The Nutrition Guild (Barracks) fields three of these from its slot recipe —
#    shaped by a DefenderData resource (setup_from_data), permanent, respawned by the
#    guild when they fall.
#  * Interventions and card bursts summon them raw (setup_raw) — explicit stats, no
#    resource, usually with a lifetime. This path is the old Ally class verbatim; the
#    class replaced Ally rather than living beside it, because two melee-blocking
#    implementations WILL drift apart on the rules that matter (leash, prune, counters).
#
# State machine (the RESPAWNING state from the design lives in the guild's slot, not
# here — a dead unit is a freed node; something has to outlive it to count the 4s):
#
#   MOVE_TO_RALLY -> IDLE -> ENGAGE -> ATTACK -> (death) ... barracks slot timer
#         ^            |________^  |______^
#         |_______________________________|   leash pull / target death
#
# Blocking is WEIGHTED: this unit can pin `block_capacity` points of enemy at once, a
# distraction costs `def.block_weight` (1 light, 2-3 heavy). A target too heavy for the
# unit's remaining capacity is fought ON THE MOVE — attacked but not halted — which is
# what separates the tank (stops things) from the striker (hurts things).

enum State { MOVE_TO_RALLY, IDLE, ENGAGE, ATTACK }

signal died(unit: DefenderUnit)

var game
var state: State = State.MOVE_TO_RALLY
var slot_index: int = 0          # formation slot within the owning guild

# Identity — null on raw summons; every type-specific ability checks the field, not this.
var data: DefenderData = null
var type_key: StringName = &""

var max_health: int
var current_health: int
var attack_damage: int
var attack_cooldown: float
var move_speed: float = 90.0
var chase_speed: float = 200.0
var damage_reduction: int = 0
var block_capacity: int = 1
var heal_amount: int = 0
var heal_interval: float = 1.0
var heal_radius: float = 0.0
var burn_dps: float = 0.0
var burn_duration: float = 0.0
var ward_slow_factor: float = 1.0
var ward_duration: float = 0.0
var ward_interval: float = 0.5
var ward_radius: float = 0.0

var rally_point: Vector2
var formation_offset := Vector2.ZERO
var guard_radius: float = 240.0   # leash, measured from rally_point — never from self

# Temporary summons (Call a Friend, card bursts) expire on their own; 0.0 = permanent.
var lifetime: float = 0.0
var _life_left: float = 0.0

## The one target this unit is actively swinging at.
var engaged_target: Distraction = null
## Everything this unit is PINNING (add_blocker'd) — engaged_target included when it
## was light enough to pin. Each entry paid its block_weight out of block_capacity.
var _pinned: Array = []
var attack_timer: float = 0.0
var _heal_timer: float = 0.0

var _color := Color("2bd6c0")
var _facing_left := false
var _hurt_flash: float = 0.0

# ---------------------------------------------------------------- setup

## Guild path: everything from the DefenderData, tier-scaled by the guild's own def.
func setup_from_data(_game, _data: DefenderData, _rally: Vector2, _offset: Vector2,
		_guard_radius: float, hp_mult: float = 1.0, dmg_mult: float = 1.0) -> void:
	game = _game
	data = _data
	type_key = _data.id
	max_health = maxi(1, roundi(_data.max_health * hp_mult))
	current_health = max_health
	attack_damage = maxi(1, roundi(_data.damage * dmg_mult))
	attack_cooldown = _data.attack_cooldown
	move_speed = _data.move_speed
	chase_speed = _data.chase_speed
	damage_reduction = _data.damage_reduction
	block_capacity = _data.block_capacity
	heal_amount = _data.heal_amount
	heal_interval = _data.heal_interval
	heal_radius = _data.heal_radius
	burn_dps = _data.burn_dps
	burn_duration = _data.burn_duration
	ward_slow_factor = _data.ward_slow_factor
	ward_duration = _data.ward_duration
	ward_interval = _data.ward_interval
	ward_radius = _data.ward_radius
	rally_point = _rally
	formation_offset = _offset
	guard_radius = _guard_radius
	_color = Color(_data.color)
	_load_frames()
	queue_redraw()

## Summon path — the old Ally.setup signature, kept verbatim so the intervention and
## card-burst call sites read the same as before the rename. Capacity 1, no abilities.
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
	state = State.IDLE
	queue_redraw()

# ---------------------------------------------------------------- state machine

func _process(delta: float) -> void:
	# A dying body only plays its death frames out; every live behaviour is already off.
	if _dying:
		_anim_t += delta
		queue_redraw()
		if _anim_t * _FPS >= float(_frames.get("death", []).size()):
			queue_free()
		return

	if lifetime > 0.0:
		_life_left -= delta
		if _life_left <= 0.0:
			_die()
			return

	if _hurt_flash > 0.0:
		_hurt_flash = maxf(0.0, _hurt_flash - 4.0 * delta)
	if _heal_pulse > 0.0:
		_heal_pulse = maxf(0.0, _heal_pulse - 1.6 * delta)
	if _ward_pulse > 0.0:
		_ward_pulse = maxf(0.0, _ward_pulse - 1.2 * delta)
	_attack_anim_t += delta
	_hurt_anim_t += delta

	_tick_heal_aura(delta)
	_tick_ward(delta)
	_prune_pins()

	var before: Vector2 = global_position
	match state:
		State.MOVE_TO_RALLY:
			var slot := _formation_pos()
			if global_position.distance_to(slot) <= 2.0:
				state = State.IDLE
			else:
				global_position = global_position.move_toward(slot, move_speed * delta)
		State.IDLE:
			var t := _find_target()
			if t != null:
				engaged_target = t
				state = State.ENGAGE
			elif global_position.distance_to(_formation_pos()) > 2.0:
				state = State.MOVE_TO_RALLY
		State.ENGAGE:
			if not _target_still_valid():
				_release_target()
			elif global_position.distance_to(engaged_target.global_position) <= _reach(engaged_target):
				_execute_clash(engaged_target)
			else:
				global_position = global_position.move_toward(
					engaged_target.global_position, chase_speed * delta)
		State.ATTACK:
			_process_melee(delta)

	# Heading from actual movement — the walk set picks its direction from it, and it
	# deliberately keeps the LAST heading when standing still, so a unit that stops
	# does not snap back to facing south.
	var moved := global_position - before
	if moved.length_squared() > 0.01:
		_heading = moved
		_facing_left = moved.x < -absf(moved.y) * 0.5

	_anim_t += delta
	queue_redraw()

func _formation_pos() -> Vector2:
	return rally_point + formation_offset

## Melee reach scales with the body it is hitting, so a wide doomscroll is struck at its
## edge rather than its centre — the old fixed 6px read as standing inside the sprite.
func _reach(d: Distraction) -> float:
	return d.def.radius + 12.0

## Leash rule, and the reason it measures from the RALLY, never from the unit: chaining
## "near me" checks would let a defender creep across the map one target at a time,
## abandoning the chokepoint its guild was built to hold.
func _in_guard_zone(d: Distraction) -> bool:
	return rally_point.distance_to(d.global_position) <= guard_radius

func _target_still_valid() -> bool:
	return is_instance_valid(engaged_target) and not engaged_target.dead \
		and _in_guard_zone(engaged_target)

## Nearest live ground enemy inside the leash zone. Already-blocked targets count too —
## several defenders may pile on — but a FREE unit prefers unpinned enemies, so three
## guild units don't all dogpile the first walker while its friends stroll past.
func _find_target() -> Distraction:
	if game == null:
		return null
	var best: Distraction = null
	var best_score := INF
	for d in game.get_live_distractions():
		if not is_instance_valid(d) or d.dead or d.is_flying or not _in_guard_zone(d):
			continue
		var score := global_position.distance_squared_to(d.global_position)
		if d.is_blocked:
			score *= 4.0   # someone already holds it; only take it if nothing else is near
		if score < best_score:
			best_score = score
			best = d
	return best

## Contact. Pin the target if the unit still has the capacity for its weight; a target
## too heavy to pin is fought unpinned — ATTACK state follows it while it walks.
## Owns the whole state transition (target included), so a caller — or a test — can
## hand it a fresh target directly instead of having to mirror ENGAGE's bookkeeping.
func _execute_clash(target: Distraction) -> void:
	engaged_target = target
	var weight: int = target.def.block_weight
	if _pinned_weight() + weight <= block_capacity and not _pinned.has(target):
		target.add_blocker(self)
		_pinned.append(target)
		# The clash knockback sells the stop — safe to tween the position directly now
		# that is_blocked has halted its cell-path movement.
		var dir := (target.global_position - global_position).normalized()
		var orig := target.position
		var tw := target.create_tween()
		tw.tween_property(target, "position", orig + dir * 6.0, 0.1) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(target, "position", orig, 0.08)
	state = State.ATTACK
	attack_timer = 0.0
	_attack_anim_t = 999.0

func _pinned_weight() -> int:
	var w := 0
	for d in _pinned:
		if is_instance_valid(d) and not d.dead:
			w += d.def.block_weight
	return w

## Drops dead/leashed-out entries from the pin list. Runs every frame — a stale pin is
## the bug the old Ally guarded against with _exit_tree alone, and a WEIGHTED pin that
## leaks also silently eats capacity the unit thinks it has spent.
func _prune_pins() -> void:
	for i in range(_pinned.size() - 1, -1, -1):
		var d = _pinned[i]
		if not is_instance_valid(d) or d.dead or not _in_guard_zone(d):
			if is_instance_valid(d):
				d.remove_blocker(self)
			_pinned.remove_at(i)

func _process_melee(delta: float) -> void:
	if not _target_still_valid():
		_release_target()
		return
	# An unpinned fight is a moving fight: keep pace with the target or the swing never
	# lands again after its first step. Pinned targets stand still by definition.
	if not _pinned.has(engaged_target):
		var gap := global_position.distance_to(engaged_target.global_position)
		if gap > _reach(engaged_target):
			global_position = global_position.move_toward(
				engaged_target.global_position, chase_speed * delta)
	_facing_left = engaged_target.global_position.x < global_position.x

	attack_timer -= delta
	if attack_timer > 0.0:
		return
	attack_timer = attack_cooldown
	_attack_anim_t = 0.0

	engaged_target.take_damage(attack_damage, 0)
	if burn_dps > 0.0 and is_instance_valid(engaged_target) and not engaged_target.dead:
		# The game's one DoT channel (per-source stacking, resist-bypassing). Each
		# berserker stacks its own searing; one berserker's flurry only refreshes itself.
		engaged_target.apply_boredom(burn_dps, burn_duration, self)

	# Counters come from EVERYTHING held, not just the one being struck — three pinned
	# monsters all maul the wall holding them. This is what damage_reduction is for, and
	# what stops a max-capacity tank from being a strictly free triple pin.
	var counter := 0
	if is_instance_valid(engaged_target) and not engaged_target.dead \
			and not _pinned.has(engaged_target):
		counter += engaged_target.def.melee_damage
	for d in _pinned:
		if is_instance_valid(d) and not d.dead:
			counter += d.def.melee_damage
	if counter > 0:
		take_damage(counter)

func _release_target() -> void:
	engaged_target = null
	# Anything still pinned keeps the unit in the fight; otherwise walk home.
	for d in _pinned:
		if is_instance_valid(d) and not d.dead:
			engaged_target = d
			state = State.ATTACK
			return
	state = State.MOVE_TO_RALLY

## Every removal path releases the melee hold here — death, lifetime expiry, or the
## guild being sold/upgraded mid-fight (queue_free without _die). A freed blocker must
## never leave a distraction pinned forever.
func _exit_tree() -> void:
	for d in _pinned:
		if is_instance_valid(d):
			d.remove_blocker(self)
	_pinned.clear()

# ---------------------------------------------------------------- aura / damage

func _tick_heal_aura(delta: float) -> void:
	if heal_amount <= 0:
		return
	_heal_timer -= delta
	if _heal_timer > 0.0:
		return
	_heal_timer = heal_interval
	var healed := false
	for u in get_tree().get_nodes_in_group("defenders"):
		if u == self or not is_instance_valid(u) or u._dying:
			continue   # a corpse playing its death frames is not a patient
		if global_position.distance_to(u.global_position) > heal_radius:
			continue
		if u.current_health < u.max_health:
			u.current_health = mini(u.max_health, u.current_health + heal_amount)
			u.queue_redraw()
			healed = true
	if healed:
		_heal_pulse = 1.0

func _enter_tree() -> void:
	add_to_group("defenders")

## The Garlic Mage's reek: a periodic soft slow on every distraction in radius. Strongest
## wins in StatusManager, so this floors the crowd's speed without ever beating a real
## Calm habit — and it deliberately ticks whether or not the mage is fighting, because
## the smell does not care who the mage is currently bonking.
func _tick_ward(delta: float) -> void:
	if ward_slow_factor >= 1.0 or ward_radius <= 0.0 or game == null:
		return
	_ward_timer -= delta
	if _ward_timer > 0.0:
		return
	_ward_timer = ward_interval
	var touched := false
	for d in game.get_live_distractions():
		if is_instance_valid(d) and not d.dead \
				and global_position.distance_to(d.global_position) <= ward_radius:
			d.apply_slow(ward_slow_factor, ward_duration)
			touched = true
	if touched:
		_ward_pulse = 1.0

## Counter-damage in. The tank's identity is one number: reduction comes off every
## separate counter-hit (floor 1), so it compounds exactly where the tank stands in
## front of several attackers at once.
func take_damage(amount: int) -> void:
	if _dying:
		return
	var dealt := maxi(1, amount - damage_reduction) if amount > 0 else 0
	current_health -= dealt
	_hurt_flash = 1.0
	if _frames.has("hurt"):
		_hurt_anim_t = 0.0   # brief recoil pose over whatever else is playing
	queue_redraw()
	if current_health <= 0:
		_die()

func _die() -> void:
	# The melee hold is released NOW, not at queue_free — a corpse playing its death
	# frames must not keep a distraction pinned for the length of the animation.
	for d in _pinned:
		if is_instance_valid(d):
			d.remove_blocker(self)
	_pinned.clear()
	engaged_target = null
	# The slot clock starts immediately either way; the body lingering through its death
	# frames is presentation, and the guild does not wait for presentation.
	died.emit(self)
	if _frames.has("death"):
		_dying = true
		_anim_t = 0.0
		queue_redraw()
		return
	# No death art: burst from the shared FX pool instead.
	if game != null and "impact_fx_pool" in game:
		var fx = game.impact_fx_pool.acquire()
		if fx != null:
			fx.global_position = global_position
			fx.play(_color, 1.4)
	queue_free()

# ---------------------------------------------------------------- art

## PNG frame sets, assets/defenders/<type_key>_<set>_frame_N.png — same file-name
## convention as distractions (32px art drawn ×2). Directional walk mirrors the
## distraction convention: south/north/east on disk, west = east flipped at draw time.
## attack/hurt ship east-facing and flip toward the target; idle and death face south.
const _ANIM_SETS := ["idle", "walk_south", "walk_north", "walk_east",
	"attack", "hurt", "death"]
const _FPS := 10.0
var _frames := {}          # set name -> Array[Texture2D]
var _anim_t := 0.0
var _attack_anim_t := 999.0   # runs 0 -> attack set length once per swing
var _hurt_anim_t := 999.0     # runs 0 -> hurt set length once per hit taken
var _heal_pulse := 0.0
var _ward_pulse := 0.0
var _ward_timer := 0.0
var _heading := Vector2.DOWN
var _dying := false

## Frame-set cache shared by every unit, keyed per type — the same disk-once pattern as
## DistractionAnimator. Three guilds' worth of respawning broccoli must not re-read
## seven PNG sets per death.
static var _set_cache: Dictionary = {}

func _load_frames() -> void:
	_frames.clear()
	if type_key == &"":
		return
	if _set_cache.has(type_key):
		_frames = _set_cache[type_key]
		return
	for set_name in _ANIM_SETS:
		var arr: Array[Texture2D] = []
		for i in range(1, 17):
			var p := "res://assets/defenders/%s_%s_frame_%d.png" % [type_key, set_name, i]
			if ResourceLoader.exists(p):
				arr.append(load(p))
			elif FileAccess.file_exists(p):
				var img := Image.new()
				if img.load(p) == OK:
					arr.append(ImageTexture.create_from_image(img))
				else:
					break
			else:
				break
		if not arr.is_empty():
			_frames[set_name] = arr
	_set_cache[type_key] = _frames

## Which walk set the current heading picks, mirroring Distraction.note_heading's
## dominant-axis snap (and its reason: axis-aligned movement plus a slight formation
## tilt must not flicker between two sets mid-corridor).
func _walk_set() -> Array:
	var flip := false
	var name: String
	if absf(_heading.x) > absf(_heading.y):
		name = "walk_east"
		flip = _heading.x < 0.0
	else:
		name = "walk_south" if _heading.y > 0.0 else "walk_north"
	if not _frames.has(name):
		name = "walk_south" if _frames.has("walk_south") else "idle"
		flip = false
	return [name, flip]

## Current frame plus whether to mirror it horizontally.
func _current_frame() -> Array:
	if _frames.is_empty():
		return [null, false]
	if _dying and _frames.has("death"):
		var dth: Array = _frames["death"]
		return [dth[mini(int(_anim_t * _FPS), dth.size() - 1)], false]
	# Priority: the hit just taken > the swing in progress > locomotion. Hurt and attack
	# play ONCE per trigger (clocks reset by take_damage / the swing) — a looping death
	# or a looping flinch reads as a glitch.
	if _frames.has("hurt") and _hurt_anim_t * _FPS < _frames["hurt"].size():
		var hrt: Array = _frames["hurt"]
		return [hrt[mini(int(_hurt_anim_t * _FPS), hrt.size() - 1)], _facing_left]
	if _frames.has("attack") and _attack_anim_t * _FPS < _frames["attack"].size():
		var atk: Array = _frames["attack"]
		return [atk[mini(int(_attack_anim_t * _FPS), atk.size() - 1)], _facing_left]
	var moving: bool = state == State.MOVE_TO_RALLY \
		or (state == State.ENGAGE and engaged_target != null)
	if moving:
		var pick := _walk_set()
		if _frames.has(pick[0]):
			var wlk: Array = _frames[pick[0]]
			return [wlk[int(_anim_t * _FPS) % wlk.size()], pick[1]]
	var idle_name: String = "idle" if _frames.has("idle") else _frames.keys()[0]
	var arr: Array = _frames[idle_name]
	return [arr[int(_anim_t * _FPS) % arr.size()], false]

func _draw() -> void:
	var pick := _current_frame()
	var tex: Texture2D = pick[0]
	if tex != null:
		# Contact shadow first, so the unit is anchored to the floor like the creatures
		# are — a fading one under a dying body, mirroring the distraction animator.
		var fade := 1.0
		if _dying and _frames.has("death"):
			fade = 1.0 - clampf(_anim_t * _FPS / float(_frames["death"].size()), 0.0, 1.0)
		var bob: float = 1.0 - absf(sin(_anim_t * 6.0)) * 0.10
		draw_set_transform(Vector2(0.0, 12.0), 0.0, Vector2(bob, 0.42 * bob))
		draw_circle(Vector2.ZERO, 15.0, Color(0.01, 0.01, 0.04, 0.12 * fade))
		draw_circle(Vector2.ZERO, 11.0, Color(0.01, 0.01, 0.04, 0.28 * fade))
		draw_circle(Vector2.ZERO, 6.5, Color(0.01, 0.01, 0.04, 0.45 * fade))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		# Same raster as the creature it blocks — and as the ground both stand on.
		# Was a hardcoded 2.0 while the terrain drew at 3.0; see Data.pixel_scale().
		var size := Vector2(tex.get_size()) * Data.pixel_scale()
		var flip := -1.0 if pick[1] else 1.0
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(flip, 1.0))
		var tint := Color.WHITE
		if _hurt_flash > 0.0 and not _dying:
			tint = Color(1.0 + _hurt_flash, 1.0 + _hurt_flash, 1.0 + _hurt_flash)
		draw_texture_rect(tex, Rect2(-size / 2.0, size), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if _dying:
			return   # no bars, rings or auras over a corpse
	else:
		_draw_vector_body()

	# Pungent ward pulse — pale ring drifting out, distinct from the monk's green.
	if ward_slow_factor < 1.0 and _ward_pulse > 0.0:
		var wr := ward_radius * (1.0 - _ward_pulse * 0.3)
		PixelDraw.arc(self, Vector2.ZERO, wr, Color(0.92, 0.9, 0.8, 0.28 * _ward_pulse), 1.0, 2.0)

	# Heal aura pulse — a ring that breathes out once per successful tick, so the monk
	# reads as doing something even before its neighbours' bars visibly move.
	if heal_amount > 0 and _heal_pulse > 0.0:
		var r := heal_radius * (1.0 - _heal_pulse * 0.35)
		PixelDraw.arc(self, Vector2.ZERO, r, Color(0.6, 1.0, 0.6, 0.35 * _heal_pulse), 1.0, 2.0)

	if lifetime > 0.0:
		var left: float = clampf(_life_left / lifetime, 0.0, 1.0)
		draw_arc(Vector2.ZERO, 14.0, -PI / 2.0, -PI / 2.0 + TAU * left, 24,
			Color(1.0, 0.82, 0.4, 0.9), 2.0)

	if current_health < max_health:
		var w := 22.0
		var y := -20.0
		draw_rect(Rect2(-w / 2.0 - 1.0, y - 1.0, w + 2.0, 4.0), Color(0, 0, 0, 0.6))
		var ratio: float = clampf(float(current_health) / float(max_health), 0.0, 1.0)
		draw_rect(Rect2(-w / 2.0, y, w * ratio, 2.0), _color)

## No art on disk yet: a readable placeholder in the unit's own colour, with a role
## glyph — shield arc (tank), cross (support), blade tick (striker) — so the three
## slots are tellable apart before a single sprite exists.
func _draw_vector_body() -> void:
	var r := 10.0
	var body := _color if _hurt_flash <= 0.0 else _color.lightened(_hurt_flash * 0.8)
	draw_circle(Vector2.ZERO, r, body)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 16, Color(1, 1, 1, 0.4), 2.0)
	if data == null:
		# Raw summons keep the old Ally cross — support/aid iconography.
		draw_line(Vector2(-4, 0), Vector2(4, 0), Color.WHITE, 2.0)
		draw_line(Vector2(0, -4), Vector2(0, 4), Color.WHITE, 2.0)
	elif block_capacity >= 3:
		draw_arc(Vector2.ZERO, r - 3.0, PI * 0.15, PI * 0.85, 10, Color.WHITE, 2.5)
	elif heal_amount > 0:
		draw_line(Vector2(-4, 0), Vector2(4, 0), Color.WHITE, 2.0)
		draw_line(Vector2(0, -4), Vector2(0, 4), Color.WHITE, 2.0)
	elif ward_slow_factor < 1.0:
		draw_circle(Vector2(3, -5), 2.5, Color.WHITE)   # staff orb — the warden's mark
		draw_line(Vector2(3, -3), Vector2(3, 5), Color.WHITE, 2.0)
	else:
		draw_line(Vector2(-3, 3), Vector2(4, -4), Color.WHITE, 2.0)
		draw_line(Vector2(1, -4), Vector2(4, -4), Color.WHITE, 2.0)
