class_name DistractionAnimator
extends Node2D

# Component attached to Distraction (enemy.gd).
# Renders crisp, multi-part procedural vector graphics directly in Godot 2D Canvas.
# Internal sub-elements move independently (swinging bell clapper, scrolling feed items,
# expanding vibration waves, dynamic buffering progress, glitching mosaic tiles, orbiting boss screens).

var enemy: Distraction
var _time: float = 0.0
var _hit_flash_timer: float = 0.0

# Pre-calculated colors for performance
const COLOR_NOTIF_BG := Color("ff3b30")
const COLOR_NOTIF_BELL := Color("ffffff")
const COLOR_NOTIF_CLAPPER := Color("ffcc00")

const COLOR_BUZZ_PHONE := Color("007aff")
const COLOR_BUZZ_CYAN := Color("64d2ff")

const COLOR_AP_RING := Color("ff9500")
const COLOR_AP_PLAY := Color("ffffff")

const COLOR_DS_FRAME := Color("34c759")
const COLOR_DS_BG := Color("1c1c1e")

const COLOR_ADULT_BASE := Color("ff2d55")
const COLOR_ADULT_HOT := Color("ff9500")

const COLOR_BOSS_CORE := Color("af52de")
const COLOR_BOSS_TENDRILL := Color("bf5af2")

## The set currently on screen; always one of the four facings below, so existing code
## that asks "does this enemy have sprite art?" keeps working unchanged.
var _frame_textures: Array[Texture2D] = []

var _frames_south: Array[Texture2D] = []
var _frames_north: Array[Texture2D] = []
var _frames_east: Array[Texture2D] = []
var _frames_west: Array[Texture2D] = []
var _frames_attack: Array[Texture2D] = []


## Fallback rate for hand-authored frames — used by every set the Animation Lab has not
## given a rate of its own. Independent of the procedural animations below, which are
## driven by _time directly.
const SPRITE_FPS := 12.0

## Per-set timing and frame alignment, authored in the Animation Lab dock.
##
## Loaded once per run and shared by every instance: it is two dictionaries and all
## creatures read the same ones. A missing file yields an empty resource, so the game
## behaves exactly as it did before tuning existed.
static var _tuning: AnimTuning = null

static func tuning() -> AnimTuning:
	if _tuning == null:
		if ResourceLoader.exists(AnimTuning.PATH):
			_tuning = load(AnimTuning.PATH) as AnimTuning
		if _tuning == null:
			_tuning = AnimTuning.new()
	return _tuning

## Drops the cached tuning so the next draw re-reads it from disk. The Animation Lab
## calls this after saving, so a running preview picks the change up.
static func drop_tuning_cache() -> void:
	_tuning = null

func _ready() -> void:
	set_process(true)
	# Sprite frames are pixel art. The project default filter is linear, which would smear
	# them, so this node opts out rather than forcing a project-wide setting on every
	# other canvas item.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func setup(parent_enemy: Distraction) -> void:
	enemy = parent_enemy
	_time = randf() * 10.0 # Randomize phase offset
	_load_frame_textures()
	queue_redraw()

## Cache shared by every instance: <id>|<variant> -> frames. Twenty Notifications in a
## wave used to hit the disk twenty times over; now the first one pays and the rest
## borrow. Keyed per variant because variants are separate frame sets.
static var _frame_cache: Dictionary = {}

## Art variants let one enemy type field several different-looking creatures, so a wave
## reads as a crowd rather than an army of clones.
##
## Files: `<id>_frame_N.png` is variant 0; `<id>_b_frame_N.png`, `<id>_c_...` are extras.
## Drop a set in and it joins the rotation — no code change, no registry to update.
const VARIANT_SUFFIXES := ["", "_b", "_c", "_d", "_e", "_f"]

func _load_frame_textures() -> void:
	_frame_textures.clear()
	if enemy == null or enemy.def == null:
		return

	var base_id := String(enemy.def.id)
	# Which variants exist is a property of the files, so it is discovered once and
	# cached; picking is per-instance.
	var available: Array = _frame_cache.get("avail|" + base_id, [])
	if available.is_empty():
		for suffix in VARIANT_SUFFIXES:
			if _variant_first_frame_exists(base_id, suffix):
				available.append(suffix)
		if available.is_empty():
			return
		_frame_cache["avail|" + base_id] = available

	var suffix: String = available[randi() % available.size()]
	_variant_suffix = suffix
	_load_death_frames(base_id, suffix)

	# Facing sets. The bare name is south (the direction every enemy shipped with), so
	# older art keeps working untouched; the others are optional additions.
	#
	# Spelled out rather than abbreviated: `_e` would be indistinguishable from the fifth
	# art variant, which is also `_e`.
	_frames_south = _load_set(base_id, suffix, "")
	_frames_north = _load_set(base_id, suffix, "_north")
	_frames_east = _load_set(base_id, suffix, "_east")
	# West is east mirrored at draw time unless real west art exists — a walk cycle seen
	# from the side is symmetric enough that generating it twice buys nothing.
	_frames_west = _load_set(base_id, suffix, "_west")
	# Optional melee set, played on loop while a defender holds this creature
	# (`<id>[_variant]_attack_frame_N.png`). Ships one enemy at a time like death art;
	# a type without it just keeps walking in place against the blocker, as before.
	_frames_attack = _load_set(base_id, suffix, "_attack")
	_frame_textures = _frames_south

func _load_set(base_id: String, suffix: String, dir_suffix: String) -> Array[Texture2D]:
	return load_frame_set(base_id, suffix, dir_suffix)

## Static half of the above — same cache, same path convention. Pulled out for P5
## (docs/refactor/PATHFINDING.MD): HordeAtlas needs to pack these exact textures into
## its runtime atlas for the batched MultiMesh render path, and calling into THIS
## loader (rather than re-deriving the file-path convention a second time) guarantees
## the atlas can never disagree with what the individual per-node fallback would draw —
## one cache, read by both.
static func load_frame_set(base_id: String, suffix: String, dir_suffix: String) -> Array[Texture2D]:
	var key := base_id + "|" + suffix + "|" + dir_suffix
	if _frame_cache.has(key):
		return _frame_cache[key]
	# Loads until a frame is missing rather than assuming four, so a distraction can ship
	# with as many frames as its animation needs.
	var frames: Array[Texture2D] = []
	for i in range(1, 33):
		var p := "res://assets/distractions/%s%s%s_frame_%d.png" % [base_id, suffix, dir_suffix, i]
		if ResourceLoader.exists(p):
			var tex := load(p)
			if tex is Texture2D:
				frames.append(tex)
		elif FileAccess.file_exists(p):
			var img := Image.new()
			if img.load(p) == OK:
				frames.append(ImageTexture.create_from_image(img))
		else:
			break
	_frame_cache[key] = frames
	return frames

func _variant_first_frame_exists(base_id: String, suffix: String) -> bool:
	var p := "res://assets/distractions/%s%s_frame_1.png" % [base_id, suffix]
	return ResourceLoader.exists(p) or FileAccess.file_exists(p)

## A pool of the distraction's own colour on the ground under it.
##
## Measured need, not decoration: the sprite family shares one muted palette, and at the
## 32-64px a distraction actually occupies, "grey-green creature holding a phone" and
## "grey-green creature with antennae" are the same handful of pixels. No amount of detail
## in the art fixes that — a 32px sprite cannot carry an identity from across the screen.
## Colour and size can. The glow puts def.color under every enemy, so type reads instantly
## and matches the wave-preview legend, which uses the same colour.
##
## Drawn first, so it sits beneath the body; it fades out with the death animation.
func _draw_type_glow(r: float, strength: float) -> void:
	if strength <= 0.01 or enemy.def == null:
		return
	var col := Color(enemy.def.color)
	# Squashed vertically in 2:1 ground projection anchored at feet
	var steps := 4
	for i in range(steps):
		var t := float(i) / float(steps)
		var rad := r * (1.75 - t * 0.95)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 1.0 / GridProjection.GROUND_Y_SCALE))
		draw_circle(Vector2.ZERO, rad, Color(col.r, col.g, col.b, 0.10 * strength))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## A tight dark ellipse where the creature meets the ground.
##
## This is what reconciles front-facing creatures with a top-down floor. The two views do
## clash on paper, but it is the standard convention for 2D games (Zelda, Stardew) and it
## reads fine — provided the character is anchored. Without a shadow the sprite floats and
## looks pasted on, which is exactly what "the style doesn't fit the map" turns out to be.
##
## Flyers get theirs pushed further down and softer, so the gap reads as altitude.
func _draw_contact_shadow(r: float, strength: float) -> void:
	if strength <= 0.01:
		return
	var drop: float = r * 1.45 if enemy.is_flying else 0.0
	var alpha: float = (0.22 if enemy.is_flying else 0.42) * strength
	# Dynamic bobbing: shadow gently tightens on upward steps for physical ground anchor (2:1 projection)
	var bob: float = 1.0 - absf(sin(_time * 6.0)) * (0.06 if enemy.is_flying else 0.12)
	draw_set_transform(Vector2(0.0, drop), 0.0, Vector2(bob, bob / GridProjection.GROUND_Y_SCALE))
	# 3-tier soft shadow (core, mid-body, soft rim)
	draw_circle(Vector2.ZERO, r * 1.15, Color(0.01, 0.01, 0.04, alpha * 0.25))
	draw_circle(Vector2.ZERO, r * 0.85, Color(0.01, 0.01, 0.04, alpha * 0.65))
	draw_circle(Vector2.ZERO, r * 0.50, Color(0.01, 0.01, 0.04, alpha * 0.95))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Draws the current frame centred on the enemy.
func _facing_frames() -> Array:
	match enemy.facing:
		Distraction.Facing.NORTH:
			if not _frames_north.is_empty():
				return [_frames_north, false, "_north"]
		Distraction.Facing.EAST:
			if not _frames_east.is_empty():
				return [_frames_east, false, "_east"]
		Distraction.Facing.WEST:
			if not _frames_west.is_empty():
				return [_frames_west, false, "_west"]
			if not _frames_east.is_empty():
				return [_frames_east, true, "_east"]
	return [_frames_south, false, ""]

## Filename stem of one sprite set — the same string _load_set builds its paths from, and
## therefore the key AnimTuning stores that set under.
func _set_key(dir_suffix: String) -> String:
	if enemy == null or enemy.def == null:
		return ""
	return String(enemy.def.id) + _variant_suffix + dir_suffix

## Frame/facing/mirror/offset selection, shared by the legacy per-node sprite draw
## below AND the batched MultiMesh path (P5, docs/refactor/PATHFINDING.MD) — ONE
## function, so the two can never disagree about which frame an artist's AnimTuning
## says should be showing right now. Empty Dictionary if there is nothing to draw
## (walk cycle but no facing has any frames at all — should not happen in practice,
## but _facing_frames() already has to handle the "no art" case for the caller).
func _select_frame() -> Dictionary:
	var pick := _facing_frames()
	if enemy.is_blocked and not _frames_attack.is_empty():
		pick = [_frames_attack, enemy.facing == Distraction.Facing.WEST, "_attack"]
	var frames: Array[Texture2D] = pick[0]
	if frames.is_empty():
		return {}
	var mirror: bool = pick[1]
	var dir_suffix: String = pick[2]
	var key := _set_key(dir_suffix)
	var slot: int = int(_time * tuning().fps_for(key, SPRITE_FPS))
	var idx: int = tuning().frame_at(key, frames.size(), slot, true)
	return {"tex": frames[idx], "mirror": mirror, "dir_suffix": dir_suffix, "idx": idx,
		"offset": tuning().offset_for(key, idx)}

func _draw_sprite_frames(r: float) -> void:
	var sel := _select_frame()
	if sel.is_empty():
		return
	var tex: Texture2D = sel["tex"]
	var mirror: bool = sel["mirror"]
	var off: Vector2i = sel["offset"]
	if mirror:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0, 1.0))
		_draw_texture_centred(tex, r, 1.0, off)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		_draw_texture_centred(tex, r, 1.0, off)

# ---------------------------------------------------------------- P5 batch support
# (docs/refactor/PATHFINDING.MD) — the surface HordeRenderer reads to draw this
# creature's walking body through the shared MultiMesh instead of this node's own
# _draw(). See horde_renderer.gd's own header for which instances qualify and why.

## True while this instance's BODY should be drawn by the batch instead of here.
## Also the trigger that packs this (type, variant)'s walk frames into HordeAtlas —
## called every frame from both this node's own _draw() (to decide whether to skip
## its heavy drawing) and from HordeRenderer.rebuild() (to decide whether to include
## this instance), so packing happens exactly once, on whichever runs first, and both
## call sites always agree.
func is_batch_eligible() -> bool:
	if enemy == null or enemy.def == null or enemy.dead or _dying or enemy.is_blocked:
		return false
	if _frame_textures.is_empty():
		return false  # no walking art at all — stays on the procedural fallback path
	return HordeAtlas.ensure_packed(String(enemy.def.id), _variant_suffix)

## Everything HordeRenderer needs to place one instance's body quad this frame, or an
## empty Dictionary if is_batch_eligible() is false (caller should leave this instance
## on the legacy per-node path for this frame).
func batch_frame_data() -> Dictionary:
	if not is_batch_eligible():
		return {}
	var sel := _select_frame()
	if sel.is_empty():
		return {}
	return {
		"base_id": String(enemy.def.id),
		"variant": _variant_suffix,
		"dir_suffix": sel["dir_suffix"],
		"frame_idx": sel["idx"],
		"mirror": sel["mirror"],
		"offset": sel["offset"],
	}

## The same overbright-white hit-flash tint _draw_texture_centred applies to the
## legacy path's draw_texture_rect() call — MultiMesh's native per-instance colour is
## exactly this, so a batched instance needs no separate hit-flash overlay at all.
func hit_flash_color() -> Color:
	if _hit_flash_timer <= 0.0:
		return Color.WHITE
	var flash_intensity: float = clampf(_hit_flash_timer / 0.15, 0.0, 1.0)
	return Color(1.0 + flash_intensity * 2.5, 1.0 + flash_intensity * 2.5,
		1.0 + flash_intensity * 2.5, 1.0)

## Public wrapper — HordeRenderer needs this to size the batched glow/shadow quads the
## same way the legacy per-node draw sizes its own.
func visual_radius() -> float:
	if enemy == null or enemy.def == null:
		return 0.0
	return _visual_radius(enemy.def.radius)

## Whether an overlay this node still owns (status auras, procedural fallback body,
## the attack loop, a death animation) needs a fresh _draw() this frame. A batched,
## idle, unstatused instance returns false — its body/glow/shadow are the horde
## batch's job now, and nothing else here is animating, so scheduling a redraw would
## just re-issue the same empty draw list every frame for nothing. This is the actual
## per-node cost P5 set out to remove: see this file's _process() and horde_renderer.gd.
func needs_own_redraw() -> bool:
	if _dying:
		return true
	if enemy == null or enemy.dead:
		return false
	if not is_batch_eligible():
		return true  # fallback body (procedural or attack loop) animates every frame
	var sm := enemy.status_manager
	if sm != null and (sm.has_boredom() or sm.has_slow() or sm.has_haste() \
			or sm.extra_factor > 1.0 or sm.has_reframe()):
		return true
	return false

func _draw_texture_centred(tex: Texture2D, r: float, glow: float = 1.0,
		off: Vector2i = Vector2i.ZERO) -> void:
	var size := _sprite_size(tex)
	if size == Vector2.ZERO:
		return
	var shift := Vector2(off) * (size.x / float(tex.get_width()))
	_draw_body_glow(tex, size, glow, shift)
	
	# Crisp overbright stencil hit flash
	var tint := Color.WHITE
	if _hit_flash_timer > 0.0:
		var flash_intensity: float = clampf(_hit_flash_timer / 0.15, 0.0, 1.0)
		tint = Color(1.0 + flash_intensity * 2.5, 1.0 + flash_intensity * 2.5, 1.0 + flash_intensity * 2.5, 1.0)
	
	draw_texture_rect(tex, Rect2(Vector2(-size.x * 0.5, -size.y) + shift, size), false, tint)

## On-screen size of one frame. NOT derived from radius, and no longer from anything local.
##
## radius is a gameplay number — projectile.gd hits against it — so it never had any
## business setting the art scale, and the old formula only pretended otherwise: with
## radii from 8 to 30 against 32px art it rounded to the floor for EVERY creature in the
## game, boss included. So the real behaviour was a flat x2 while the ground ran at x3,
## and the creatures were half a pixel finer than the world they walked on.
##
## The scale now comes from the map (Data.pixel_scale), which is the only thing entitled
## to decide it. Size differences stay authored into the art itself: regulars ship 32px
## art and draw at 96, the boss ships 64px and draws at 192 — four cells, as a boss should.
func _sprite_size(tex: Texture2D) -> Vector2:
	var src := Vector2(tex.get_width(), tex.get_height())
	if src.x <= 0.0:
		return Vector2.ZERO
	return src * Data.pixel_scale()

## Half of what the body actually covers on screen — as opposed to `radius`, which is the
## hitbox. Ground FX and status rings must wrap THIS: the art is now wider than the
## hitbox, and anything sized from `radius` alone ends up hidden behind the sprite —
## a shield ring the boss wears under its own fur announces nothing.
## For procedural bodies (no frames) the two are the same number.
func _visual_radius(r: float) -> float:
	var frames: Array[Texture2D] = _death_frames if _dying else _frame_textures
	if frames.is_empty():
		return r
	return _sprite_size(frames[0]).x * 0.5

## A halo of the creature's own colour behind its silhouette.
##
## The sprite family was drawn against the old pale map and is mostly olive, grey and
## brown; on the Deep Focus floor those bodies sit within a few values of the ground and
## a half-size creature all but disappears. The floor pool in _draw_type_glow marks where
## something is, but the body itself still needs to separate from the background — so the
## same frame is stamped a step larger in def.color behind it. Silhouette-shaped, not a
## circle, so it reads as the creature glowing rather than as a lamp under it.
func _draw_body_glow(tex: Texture2D, size: Vector2, strength: float,
		shift: Vector2 = Vector2.ZERO) -> void:
	if enemy.def == null or strength <= 0.01:
		return
	var col := Color(enemy.def.color)
	var step: float = maxf(2.0, size.x * 0.06)
	for ring in [2.0, 1.0]:
		var i: float = float(ring)
		var grown: Vector2 = size + Vector2.ONE * (step * i * 2.0)
		var a: float = (0.16 if is_equal_approx(i, 1.0) else 0.09) * strength
		draw_texture_rect(tex, Rect2(Vector2(-grown.x * 0.5, -grown.y) + shift + Vector2(0, step * i), grown), false,
			Color(col.r, col.g, col.b, a))

func trigger_hit_flash() -> void:
	_hit_flash_timer = 0.15

func _process(delta: float) -> void:
	if enemy == null:
		return

	# A dying enemy keeps ticking so its death frames can play; everything else about it
	# is already switched off by Distraction.dead.
	if _dying:
		_death_time += delta
		queue_redraw()
		if _death_time >= death_duration():
			_death_finished = true
		return

	if enemy.dead:
		return

	_time += delta

	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta

	# P5 (docs/refactor/PATHFINDING.MD): _time and the hit-flash countdown above always
	# advance — HordeRenderer's per-frame rebuild() reads both directly off this node
	# for a batched instance's frame pick and tint, with no need for _draw() to ever
	# run. Redraw is only scheduled when there is still something ONLY this node's own
	# _draw() can show: the procedural fallback body, the attack loop, or an active
	# status aura. See needs_own_redraw()'s own header for the reasoning.
	if needs_own_redraw():
		queue_redraw()

# ---------------------------------------------------------------- death animation
#
# Files: `<id>[_variant]_death_frame_N.png`. Optional — a type with no death art dies
# instantly the way it always did, so this can be filled in one enemy at a time.
# The variant suffix is inherited from the walk cycle, so a creature dies as the same
# creature it walked as.

const DEATH_FPS := 12.0

var _death_frames: Array[Texture2D] = []
var _variant_suffix := ""
var _dying := false
var _death_time := 0.0
var _death_finished := false

func has_death_animation() -> bool:
	return not _death_frames.is_empty()

## Reads the tuned rate, not the constant: Distraction._die() waits on this number before
## freeing the corpse, so a death slowed down in the Animation Lab would otherwise be cut
## off partway through.
## Counts held slots, not frames: a death whose last frame is held 4x has to keep the
## corpse alive for all four, or Distraction._die() frees it mid-collapse.
func death_duration() -> float:
	var key := _set_key("_death")
	return float(tuning().hold_total(key, _death_frames.size())) / tuning().fps_for(key, DEATH_FPS)

func is_death_finished() -> bool:
	return _death_finished

## Switches the body over to the death frames. Called by Distraction._die(), which then
## waits for is_death_finished() before freeing itself.
func play_death() -> void:
	if _dying:
		return
	_dying = true
	_death_time = 0.0
	_death_finished = _death_frames.is_empty()
	queue_redraw()

func _load_death_frames(base_id: String, suffix: String) -> void:
	_death_frames.clear()
	var key := "death|" + base_id + "|" + suffix
	if _frame_cache.has(key):
		_death_frames = _frame_cache[key]
		return
	var frames: Array[Texture2D] = []
	for i in range(1, 33):
		var p := "res://assets/distractions/%s%s_death_frame_%d.png" % [base_id, suffix, i]
		if ResourceLoader.exists(p):
			var tex := load(p)
			if tex is Texture2D:
				frames.append(tex)
		elif FileAccess.file_exists(p):
			var img := Image.new()
			if img.load(p) == OK:
				frames.append(ImageTexture.create_from_image(img))
		else:
			break
	_frame_cache[key] = frames
	_death_frames = frames

## Death frames play ONCE and hold on the last one — a looping death reads as a glitch.
func _draw_death_frames(r: float) -> void:
	var key := _set_key("_death")
	var slot: int = int(_death_time * tuning().fps_for(key, DEATH_FPS))
	var idx: int = tuning().frame_at(key, _death_frames.size(), slot, false)
	_draw_texture_centred(_death_frames[idx], r, 1.0, tuning().offset_for(key, idx))

func _draw() -> void:
	if enemy == null or enemy.def == null:
		return

	var r: float = enemy.def.radius
	# Ground FX and rings wrap the drawn body; r stays the gameplay number.
	var vr := _visual_radius(r)
	var is_moving := enemy.current_speed > 0 and not enemy.is_blocked

	# A dying body draws its death frames and nothing else — no status auras, no hit
	# flash. Those describe a live enemy's state and would keep pulsing over a corpse.
	if _dying:
		if not _death_frames.is_empty():
			var fade := 1.0 - clampf(_death_time / maxf(death_duration(), 0.001), 0.0, 1.0)
			_draw_type_glow(vr, fade)
			_draw_contact_shadow(vr, fade)
			_draw_death_frames(r)
		return

	# P5 (docs/refactor/PATHFINDING.MD): a batch-eligible instance's glow, shadow, hit
	# flash and body are drawn by HordeRenderer's shared MultiMeshInstance2D instead —
	# see is_batch_eligible()'s own header. Everything below this check (status auras,
	# the reframe ring further down) still belongs to THIS node either way: they only
	# apply to whichever slice of the population currently carries that status, so
	# skipping them here would cost nothing measurable and they are not what P5 set
	# out to batch.
	var batched := is_batch_eligible()
	if not batched:
		_draw_type_glow(vr, 1.0)
		_draw_contact_shadow(vr, 1.0)

		# Apply Hit Flash modulation tint
		if _hit_flash_timer > 0.0:
			draw_circle(Vector2.ZERO, vr + 4.0, Color(1, 1, 1, 0.8))

	# -------------------------------------------------- Status Aura Overlays
	# Boredom halo
	if enemy.status_manager != null and enemy.status_manager.has_boredom():
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 1.0 / GridProjection.GROUND_Y_SCALE))
		draw_circle(Vector2.ZERO, vr + 7.0, Color(0.55, 0.58, 0.62, 0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Slow / Calm ring
	if enemy.status_manager != null and enemy.status_manager.has_slow():
		PixelDraw.ellipse(self, Vector2.ZERO, vr + 6.0, (vr + 6.0) / GridProjection.GROUND_Y_SCALE, Color(0.3, 0.8, 1.0, 0.7), 1.0, 1.5)

	# Rush chevrons — a hurried distraction has to be legible in a crowd, and it is the
	# crowd that carries the tell: a solid ring like Calm's would just read as another
	# aura. Two arrowheads trailing the body point the way it is being pushed, so a
	# hasted pack visibly leans in one direction. Sits behind the sprite frames below.
	# Overdrive borrows the same chevrons but burns them red: it is the same statement
	# ("this one is moving faster than you think") and a second, unrelated symbol for it
	# would just cost the player another thing to learn.
	var overdriven: bool = enemy.status_manager != null and enemy.status_manager.extra_factor > 1.0
	if enemy.status_manager != null and (enemy.status_manager.has_haste() or overdriven):
		var back := Vector2(-1.0, 0.0)
		match enemy.facing:
			Distraction.Facing.WEST:
				back = Vector2(1.0, 0.0)
			Distraction.Facing.NORTH:
				back = Vector2(0.0, 1.0)
			Distraction.Facing.SOUTH:
				back = Vector2(0.0, -1.0)
		var side := Vector2(-back.y, back.x)
		var pulse: float = 0.55 + 0.45 * sin(_time * (26.0 if overdriven else 18.0))
		var tint := Color(1.0, 0.30, 0.24) if overdriven else Color(1.0, 0.86, 0.32)
		for i in range(2):
			var root: Vector2 = back * (vr * (0.85 + 0.42 * float(i)))
			var a: float = (0.85 - 0.3 * float(i)) * pulse
			var col := Color(tint.r, tint.g, tint.b, a)
			draw_line(root + side * vr * 0.42, root - back * vr * 0.34, col, 2.0)
			draw_line(root - side * vr * 0.42, root - back * vr * 0.34, col, 2.0)

	# -------------------------------------------------- Hand-authored sprite frames
	# Art on disk wins over the procedural body. The status auras above still draw, so a
	# sprited enemy keeps its Boredom halo and Slow ring; only the body is replaced. A
	# batched instance's body is the horde MultiMesh's job now (P5) — this node drew
	# only the overlays above (if any were active this frame) and stops here.
	if not _frame_textures.is_empty():
		if not batched:
			_draw_sprite_frames(r)
		return

	# -------------------------------------------------- Multi-Part Vector Animations
	match String(enemy.def.id):
		"notification":
			_draw_notification(r, is_moving)
		"phantom_buzz":
			_draw_phantom_buzz(r)
		"autoplay":
			_draw_autoplay(r, is_moving)
		"doomscroll":
			_draw_doomscroll(r, is_moving)
		"adult_content":
			_draw_adult_content(r)
		"social_media_binge":
			_draw_boss_social_media(r)
		"group_chat":
			_draw_group_chat(r, is_moving)
		_:
			_draw_generic_fallback(r, is_moving)

	# Reframe status broken ring
	if enemy.status_manager != null and enemy.status_manager.has_reframe():
		var seg: float = TAU / 8.0
		for i in range(4):
			var a: float = float(i) * seg * 2.0
			draw_arc(Vector2.ZERO, vr + 6.0, a, a + seg, 6, Color(1, 1, 1, 0.9), 2.0)

	# Denial Shield — the boss ignores every direct hit while this is up, so it has to
	# be unmissable ON the body, not only a text flash in the corner of the HUD.
	# Rotating segments over a soft ring read as an active barrier, not a decoration.
	if enemy is Boss and (enemy as Boss).is_shielded():
		var sr: float = vr + 12.0
		draw_arc(Vector2.ZERO, sr, 0, TAU, 40, Color(1.0, 0.83, 0.47, 0.30), 6.0)
		for i in range(6):
			var a: float = _time * 2.2 + float(i) * TAU / 6.0
			draw_arc(Vector2.ZERO, sr, a, a + 0.55, 8, Color("ffd479"), 3.0)
		draw_arc(Vector2.ZERO, sr + 5.0, 0, TAU, 40, Color(1.0, 0.83, 0.47, 0.45), 1.5)

# ==============================================================================
# 1. NOTIFICATION (Zvonící odznak + kmitající srdce/jazyk zvonku + posakující badge)
# ==============================================================================
func _draw_notification(r: float, is_moving: bool) -> void:
	var tilt := sin(_time * 14.0) * 0.2 if is_moving else sin(_time * 5.0) * 0.08

	# Ringing sound waves emitting outwards
	for i in range(2):
		var wave_t := fmod(_time * 3.0 + i * 0.5, 1.0)
		var wave_r := r + wave_t * 12.0
		var alpha := (1.0 - wave_t) * 0.6
		draw_arc(Vector2.ZERO, wave_r, -PI * 0.7, -PI * 0.3, 12, Color(1, 0.3, 0.3, alpha), 2.0)

	# Main Red Badge Disc
	draw_circle(Vector2.ZERO, r, COLOR_NOTIF_BG)
	draw_arc(Vector2.ZERO, r, 0, TAU, 24, Color.WHITE, 1.5)

	# Bell Outline Shape
	var bell_center := Vector2(0, 1.0)
	var pts := PackedVector2Array([
		bell_center + Vector2(0, -r * 0.55).rotated(tilt),
		bell_center + Vector2(r * 0.45, r * 0.2).rotated(tilt),
		bell_center + Vector2(-r * 0.45, r * 0.2).rotated(tilt)
	])
	draw_colored_polygon(pts, COLOR_NOTIF_BELL)

	# Independent Swinging Clapper
	var clapper_angle := sin(_time * 16.0) * 0.35
	var clapper_pos := bell_center + Vector2(sin(clapper_angle) * (r * 0.3), r * 0.28)
	draw_circle(clapper_pos, r * 0.16, COLOR_NOTIF_CLAPPER)

	# Bouncing "+1" / "!" Badge at Top-Right
	var badge_bounce := sin(_time * 8.0) * 2.5
	var badge_pos := Vector2(r * 0.55, -r * 0.55 + badge_bounce)
	draw_circle(badge_pos, r * 0.35, Color.WHITE)
	draw_circle(badge_pos, r * 0.28, COLOR_NOTIF_BG)
	# Exclamation mark
	draw_line(badge_pos + Vector2(0, -r * 0.12), badge_pos + Vector2(0, 0), Color.WHITE, 2.0)
	draw_circle(badge_pos + Vector2(0, r * 0.12), 1.2, Color.WHITE)

# ==============================================================================
# 2. PHANTOM BUZZ (Létající telefon + expanzivní vibrační vlny + živý osciloskop)
# ==============================================================================
func _draw_phantom_buzz(r: float) -> void:
	var hover_y := sin(_time * 5.0) * 5.0
	var jitter_x := randf_range(-1.2, 1.2)
	var phone_center := Vector2(jitter_x, hover_y)

	# 1. Dynamic Expanding Vibration Shockwaves (Left and Right)
	for i in range(3):
		var wave_t := fmod(_time * 2.5 + i * 0.33, 1.0)
		var wave_r := r + wave_t * 20.0
		var alpha := (1.0 - wave_t) * 0.75
		var wave_color := Color(0.39, 0.82, 1.0, alpha)
		draw_arc(phone_center, wave_r, PI * 0.65, PI * 1.35, 16, wave_color, 2.2)
		draw_arc(phone_center, wave_r, -PI * 0.35, PI * 0.35, 16, wave_color, 2.2)

	# 2. Ghost Trail Echo (2 trailing ghosts for smooth ghost effect)
	for t_idx in range(1, 3):
		var trail_offset := Vector2(-t_idx * 4.0, sin((_time - t_idx * 0.08) * 5.0) * 5.0)
		var trail_rect := Rect2(trail_offset - Vector2(r * 0.6, r * 0.9), Vector2(r * 1.2, r * 1.8))
		draw_rect(trail_rect, Color(0.0, 0.5, 1.0, 0.15 / float(t_idx)), true)
		draw_rect(trail_rect, Color(0.39, 0.82, 1.0, 0.3 / float(t_idx)), false, 1.0)

	# 3. Main Ghost Phone Body (Transparent Hologram Chassis)
	var phone_size := Vector2(r * 1.3, r * 1.9)
	var phone_rect := Rect2(phone_center - phone_size / 2.0, phone_size)
	# Translucent cyan fill
	draw_rect(phone_rect, Color(0.0, 0.45, 0.95, 0.55), true)
	# Glowing white & cyan border
	draw_rect(phone_rect, Color("64d2ff"), false, 2.0)
	draw_rect(phone_rect.grow(-1.5), Color.WHITE, false, 1.0)

	# 4. Glowing Expressive Ghost Eyes
	var eye_y := phone_center.y - r * 0.35
	var eye_pulse := 1.0 + sin(_time * 12.0) * 0.15
	var left_eye := Vector2(phone_center.x - r * 0.28, eye_y)
	var right_eye := Vector2(phone_center.x + r * 0.28, eye_y)
	draw_circle(left_eye, r * 0.18 * eye_pulse, Color.WHITE)
	draw_circle(left_eye, r * 0.12 * eye_pulse, Color("64d2ff"))
	draw_circle(right_eye, r * 0.18 * eye_pulse, Color.WHITE)
	draw_circle(right_eye, r * 0.12 * eye_pulse, Color("64d2ff"))

	# 5. Live Oscilloscope Signal Waveform Mouth / Screen
	var wave_y := phone_center.y + r * 0.3
	var points := PackedVector2Array()
	var width := r * 0.9
	var steps := 10
	for i in range(steps + 1):
		var px := phone_center.x - width / 2.0 + (width / float(steps)) * float(i)
		var py := wave_y + sin(float(i) * 0.9 + _time * 16.0) * (r * 0.2)
		points.append(Vector2(px, py))
	draw_polyline(points, COLOR_BUZZ_CYAN, 2.0)

# ==============================================================================
# 3. AUTOPLAY (Kruhový timer plnící se 0-360° + ozubený prstenec + rotující play)
# ==============================================================================
func _draw_autoplay(r: float, is_moving: bool) -> void:
	# Dark Disc Base
	draw_circle(Vector2.ZERO, r, Color(0.1, 0.1, 0.12))
	draw_circle(Vector2.ZERO, r, Color(1, 0.6, 0, 0.3))

	# Segmented Rotating Outer Gear Ring
	var gear_angle := -_time * 2.0
	var segs := 6
	for i in range(segs):
		var a := gear_angle + i * (TAU / segs)
		draw_arc(Vector2.ZERO, r * 0.95, a, a + 0.5, 6, COLOR_AP_RING, 3.0)

	# Continuous Dynamic Countdown Progress Fill Arc
	var fill_progress := fmod(_time * 1.5, TAU)
	draw_arc(Vector2.ZERO, r * 0.75, -PI * 0.5, -PI * 0.5 + fill_progress, 24, Color(1, 0.8, 0), 2.5)

	# Central Play Button Triangle (Pulsing forward)
	var pulse := 1.0 + sin(_time * 10.0) * 0.12
	var tri_size := r * 0.4 * pulse
	var pts := PackedVector2Array([
		Vector2(-tri_size * 0.5, -tri_size * 0.7),
		Vector2(tri_size * 0.8, 0),
		Vector2(-tri_size * 0.5, tri_size * 0.7)
	])
	draw_colored_polygon(pts, COLOR_AP_PLAY)

# ==============================================================================
# 4. DOOMSCROLL (Nekonečný feed příspěvků fyzicky rolovaný dolů po displeji)
# ==============================================================================
func _draw_doomscroll(r: float, is_moving: bool) -> void:
	# Walking Feet animation underneath
	if is_moving:
		var leg1_x := sin(_time * 12.0) * (r * 0.3)
		var leg2_x := -sin(_time * 12.0) * (r * 0.3)
		draw_line(Vector2(-r * 0.3, r * 0.9), Vector2(-r * 0.3 + leg1_x, r * 1.2), COLOR_DS_FRAME, 3.0)
		draw_line(Vector2(r * 0.3, r * 0.9), Vector2(r * 0.3 + leg2_x, r * 1.2), COLOR_DS_FRAME, 3.0)

	# Smartphone Frame
	var phone_rect := Rect2(-r * 0.7, -r * 1.0, r * 1.4, r * 2.0)
	draw_rect(phone_rect, COLOR_DS_FRAME, true)
	draw_rect(phone_rect, Color.WHITE, false, 2.0)

	# Screen Viewport
	var screen_rect := Rect2(-r * 0.55, -r * 0.85, r * 1.1, r * 1.7)
	draw_rect(screen_rect, COLOR_DS_BG, true)

	# Continuous Downward Rolling Post Cards (3 items cycling)
	var card_height := r * 0.45
	var scroll_speed := 35.0
	var total_height := r * 1.5

	for i in range(3):
		var base_y := -r * 0.7 + i * (card_height + 4.0)
		var cur_y := -r * 0.7 + fmod(base_y + _time * scroll_speed + r * 1.0, total_height) - r * 0.3
		var card_r := Rect2(-r * 0.45, cur_y, r * 0.9, card_height)

		# Clip check inside screen
		if card_r.position.y > -r * 0.85 and card_r.position.y + card_height < r * 0.85:
			draw_rect(card_r, Color(0.2, 0.2, 0.23), true)
			draw_rect(card_r, COLOR_DS_FRAME, false, 1.0)

			# Post details (Like heart icon + text lines)
			var heart_pos := card_r.position + Vector2(r * 0.15, r * 0.2)
			draw_circle(heart_pos, 2.5, Color("ff3b30"))
			draw_line(card_r.position + Vector2(r * 0.3, r * 0.15), card_r.position + Vector2(r * 0.75, r * 0.15), Color.WHITE, 1.5)
			draw_line(card_r.position + Vector2(r * 0.15, r * 0.32), card_r.position + Vector2(r * 0.6, r * 0.32), Color(0.6, 0.6, 0.6), 1.0)

	# Bottom Vortex Gradient Line
	draw_line(Vector2(-r * 0.55, r * 0.75), Vector2(r * 0.55, r * 0.75), Color("ff3b30"), 2.0)

# ==============================================================================
# 5. ADULT CONTENT (Dopaminová past – mozaikový glitch + zrychleně tepající jádro)
# ==============================================================================
func _draw_adult_content(r: float) -> void:
	# Outer Neon Hazard Frame
	draw_rect(Rect2(-r, -r, r * 2.0, r * 2.0), COLOR_ADULT_BASE, true)
	draw_rect(Rect2(-r, -r, r * 2.0, r * 2.0), Color.WHITE, false, 2.0)

	# Rapid Pulsing Flame/Heart Core
	var heart_pulse := 1.0 + sin(_time * 14.0) * 0.18
	draw_circle(Vector2.ZERO, r * 0.45 * heart_pulse, COLOR_ADULT_HOT)

	# Dynamic Glitching Mosaic Grid (4x4 tiles changing color & opacity)
	var grid_size := 4
	var tile_dim := (r * 1.8) / float(grid_size)
	var start_pos := Vector2(-r * 0.9, -r * 0.9)

	for row in range(grid_size):
		for col in range(grid_size):
			# Seeded pseudo-randomness based on time step
			var tile_seed := row * 7 + col * 13 + int(_time * 8.0)
			if tile_seed % 3 == 0:
				var t_pos := start_pos + Vector2(col * tile_dim, row * tile_dim)
				var alpha := 0.4 + (tile_seed % 5) * 0.12
				var c := COLOR_ADULT_BASE if tile_seed % 2 == 0 else COLOR_ADULT_HOT
				c.a = alpha
				draw_rect(Rect2(t_pos, Vector2(tile_dim - 1.0, tile_dim - 1.0)), c, true)

# ==============================================================================
# 6. SOCIAL MEDIA BINGE (Boss - Obíhající satelitní obrazovky + úponky)
# ==============================================================================
func _draw_boss_social_media(r: float) -> void:
	# Central Boss Disc
	var boss_pulse := 1.0 + sin(_time * 4.0) * 0.06
	draw_circle(Vector2.ZERO, r * 0.7 * boss_pulse, COLOR_BOSS_CORE)
	draw_circle(Vector2.ZERO, r * 0.7 * boss_pulse, Color.WHITE, false, 2.5)

	# Inner Spiral Line
	var spiral_pts := PackedVector2Array()
	for i in range(16):
		var a := float(i) * 0.4 + _time * 3.0
		var radius_step := (r * 0.55) * (float(i) / 16.0)
		spiral_pts.append(Vector2(cos(a), sin(a)) * radius_step)
	draw_polyline(spiral_pts, Color.WHITE, 1.5)

	# 4 Satellite Screens Orbiting the Core
	var screens := 4
	var orbit_radius := r * 1.25
	var speed := 1.4

	for i in range(screens):
		var angle := _time * speed + i * (TAU / float(screens))
		var screen_pos := Vector2(cos(angle), sin(angle)) * orbit_radius

		# Pulsing Zig-Zag Energy Tendrils to Center
		var mid_point := screen_pos * 0.5 + Vector2(randf_range(-2, 2), randf_range(-2, 2))
		draw_line(Vector2.ZERO, mid_point, COLOR_BOSS_TENDRILL, 2.5)
		draw_line(mid_point, screen_pos, Color.WHITE, 1.5)

		# Satellite Screen Body
		var s_size := Vector2(r * 0.5, r * 0.6)
		var s_rect := Rect2(screen_pos - s_size / 2.0, s_size)
		draw_rect(s_rect, Color(0.15, 0.15, 0.18), true)
		draw_rect(s_rect, COLOR_BOSS_TENDRILL, false, 1.5)

		# Icon on Screen
		match i:
			0: # Like Heart
				draw_circle(screen_pos, 3.0, Color("ff3b30"))
			1: # Retweet Arrow
				draw_line(screen_pos + Vector2(-3, 2), screen_pos + Vector2(0, -2), Color("30d158"), 1.5)
				draw_line(screen_pos + Vector2(0, -2), screen_pos + Vector2(3, 2), Color("30d158"), 1.5)
			2: # Chat Bubble
				draw_circle(screen_pos, 3.0, Color("64d2ff"))
			3: # Dopamine Star
				draw_circle(screen_pos, 2.5, Color("ffcc00"))

# ==============================================================================
# 7. GROUP CHAT (Disruptor — trs chatovacích bublin + tečky psaní + ping vlny)
# ==============================================================================
func _draw_group_chat(r: float, is_moving: bool) -> void:
	var bob := sin(_time * 9.0) * 1.5 if is_moving else 0.0
	var base := Color("42c86a")

	# Ringing ping waves, same language as the notification's bell arcs.
	for i in range(2):
		var wave_t := fmod(_time * 2.2 + i * 0.5, 1.0)
		var alpha := (1.0 - wave_t) * 0.5
		draw_arc(Vector2(0, bob), r + wave_t * 14.0, -PI * 0.8, -PI * 0.2, 12,
			Color(base.r, base.g, base.b, alpha), 2.0)

	# A cluster of three chat bubbles — the thread, not one message.
	var main_rect := Rect2(-r * 0.9, bob - r * 0.7, r * 1.5, r * 1.1)
	draw_rect(main_rect, base, true)
	draw_rect(main_rect, Color.WHITE, false, 1.5)
	var tail := PackedVector2Array([
		Vector2(-r * 0.5, bob + r * 0.4), Vector2(-r * 0.2, bob + r * 0.4),
		Vector2(-r * 0.55, bob + r * 0.85)])
	draw_colored_polygon(tail, base)
	var back_rect := Rect2(-r * 0.1, bob - r * 1.05, r * 1.1, r * 0.75)
	draw_rect(back_rect, base.darkened(0.35), true)
	draw_rect(back_rect, Color(1, 1, 1, 0.6), false, 1.0)

	# "Someone is typing…" dots, blinking in sequence — the hook that never resolves.
	for i in range(3):
		var phase := fmod(_time * 2.4 - float(i) * 0.25, 1.0)
		var da := 0.35 + 0.65 * clampf(sin(phase * TAU) * 0.5 + 0.5, 0.0, 1.0)
		draw_circle(Vector2(-r * 0.55 + float(i) * r * 0.4, bob - r * 0.15),
			r * 0.11, Color(1, 1, 1, da))

# ==============================================================================
# FALLBACK (Pro neurčené typy)
# ==============================================================================
func _draw_generic_fallback(r: float, is_moving: bool) -> void:
	var c := Color(enemy.def.color)
	var bob := sin(_time * 10.0) * 2.0 if is_moving else 0.0
	var center := Vector2(0, bob)
	match enemy.def.shape:
		"circle":
			draw_circle(center, r, c)
		"rect":
			draw_rect(Rect2(center - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), c)
		"triangle":
			var pts := PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, r), center + Vector2(-r, r)])
			draw_colored_polygon(pts, c)
