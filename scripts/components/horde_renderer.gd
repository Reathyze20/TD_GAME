class_name HordeRenderer
extends Node2D
## P5 (docs/refactor/PATHFINDING.MD): batches the steady-state "just walking" body of
## the distraction horde into three MultiMeshInstance2D draw calls instead of one
## Node2D + _draw() per creature. Owned by Game (one instance per level, built once
## alongside `entities` — see game.gd's _build_horde_renderer()), rebuilt every frame
## from Game._process() with the current live distraction list.
##
## Every currently-shipped distraction's base body is already sprite art, not the
## hand-coded procedural _draw_* functions in distraction_animator.gd — see this
## task's PROGRESS.md entry for how that was confirmed against docs/ROSTER.md and
## assets/distractions/. Those procedural functions stay alive as the fallback for any
## type that ships with none; that fallback is NOT touched by this class and keeps
## rendering exactly as before, one node at a time.
##
## What's batched here: the walking sprite body, its type-glow ground ring and its
## contact shadow — the three things distraction_animator.gd used to draw
## UNCONDITIONALLY for every live, healthy, unblocked distraction every single frame,
## which is what actually dominated a large horde's frame time (see PROGRESS.md's
## bench numbers). What's excluded from the batch, and stays on the individual
## Distraction/DistractionAnimator node exactly as before — see
## DistractionAnimator.is_batch_eligible():
##   - dying bodies (death-frame animation) — a handful at once, never the majority
##   - a distraction currently blocked by an Ally (plays its attack loop instead)
##   - any type with no frame art at all (the seven hand-drawn procedural fallbacks)
##   - status aura overlays (Boredom halo, Slow ring, Rush/Overdrive chevrons, Reframe
##     ring) — only drawn for whichever slice of the population currently carries that
##     status, which even a rough wave is normally a small fraction of N
## Hit-flash is the one exception that DOES stay batched: MultiMesh's native
## per-instance colour IS a hit-flash tint, so it costs nothing extra to keep.
##
## SIMPLIFICATIONS versus the exact per-node draw, both cosmetic and documented rather
## than silently dropped:
##   - The contact shadow's subtle time-based "bob" squash (distraction_animator.gd's
##     _draw_contact_shadow) is not reproduced — every batched shadow is a static soft
##     ellipse. The bob was a few percent of scale on a low-alpha ground blob; invisible
##     at horde scale, not worth a per-instance animated transform for.
##   - Glow and shadow are pre-baked single soft radial-gradient textures (see
##     _radial_image() below) standing in for the original's 3-4 stacked hard-edged
##     rings. Close in overall density and footprint, not pixel-identical.
##
## Y-SORT COMPROMISE (see docs/core/01_rendering_and_depth.md and this task's
## PROGRESS.md entry): a single CanvasItem can only occupy one place in the draw
## order. The old per-node renderer let each distraction's OWN y sort it against every
## habit individually, so a tall habit head poking into the lane above it could
## correctly hide (or be hidden by) a walking body crossing there. A batched
## MultiMeshInstance2D cannot do that — every instance in one draw call shares the
## node's own z position, full stop; there is no per-instance sort key to give it.
## Chosen compromise: the batched BODY layer draws at a fixed z tier, above every
## z=0 "main entity" (habits, allies, any individually-drawn distraction) and below
## projectiles/world UI — i.e. distractions always read on top of habits. This is a
## real, deliberate loss of per-instance sort accuracy, traded for horde readability:
## the player has to be able to see what is bearing down on their maze, and hiding an
## oncoming body behind a tower's sprite is a worse failure than the reverse (and is
## the more common convention in horde/TD games generally). GLOW and SHADOW are
## demoted further still, to their own fixed tier below every unit entirely — which
## actually brings them a step CLOSER to docs/core/01's own stated ideal ("Shadows...
## No [y-sort]") than the old per-node renderer was: that drew glow/shadow inside the
## same y-sorted node as the body, so they sorted WITH it before this change.

const Z_GLOW := -8   ## below every unit, matches docs/core/01's "shadows are z-only, never y-sorted"
const Z_SHADOW := -6 ## same tier, drawn after glow so it sits on top of it (matches old stacking order)

## ------------------------------------------------------------ contact-shadow tuning
## Same intent as DistractionAnimator's and DefenderUnit's per-instance shadow exports
## (scripts/components/distraction_animator.gd, scripts/defender_unit.gd), but exported
## on the RENDERER instead: this class draws the whole batched horde through one shared
## MultiMesh, so there is no per-creature node to hang a per-instance export on — see
## this file's own header on why the batch trades per-instance control for draw-call
## count. One HordeRenderer exists per Game (see header), so these two knobs still
## reach every batched shadow; they just move together instead of independently.
## Deliberately NOT exporting a shadow colour here: unlike the two per-node scripts
## above, the shadow's pixels are a single soft-falloff texture baked ONCE and shared
## by every HordeRenderer that will ever exist (the static _shadow_tex below, same
## pattern as game.gd's dopamine-burst dot — see _ensure_shadow_texture()'s own
## comment). Recolouring it would mean generating a per-instance texture instead of
## reusing that shared bake, which is real added complexity this diagnostic task's
## scope does not need — the per-node scripts above already cover "can a shadow's
## colour be tuned at all" for the (non-batched) cases that matter here.
@export var shadow_radius_scale: float = 1.0
@export var shadow_alpha_scale: float = 1.0

var _body_mmi: MultiMeshInstance2D
var _glow_mmi: MultiMeshInstance2D
var _shadow_mmi: MultiMeshInstance2D

var _body_mm: MultiMesh
var _glow_mm: MultiMesh
var _shadow_mm: MultiMesh

var _capacity := 0

static var _glow_tex: ImageTexture = null
static var _shadow_tex: ImageTexture = null

func _ready() -> void:
	z_index = 0 ## the "main entities" tier — see this file's Y-sort header

	_body_mm = MultiMesh.new()
	_body_mm.transform_format = MultiMesh.TRANSFORM_2D
	_body_mm.use_colors = true
	_body_mm.use_custom_data = true
	_body_mm.mesh = _build_body_mesh()
	_body_mmi = MultiMeshInstance2D.new()
	_body_mmi.name = "HordeBody"
	_body_mmi.multimesh = _body_mm
	_body_mmi.texture = HordeAtlas.texture()
	_body_mmi.material = _build_atlas_material()
	_body_mmi.z_index = 0
	# Sprite frames are pixel art (same reasoning as DistractionAnimator._ready()).
	_body_mmi.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_body_mmi)

	_glow_mm = _new_ground_multimesh()
	_glow_mmi = _new_ground_mmi("HordeGlow", _glow_mm, _ensure_glow_texture(), Z_GLOW)

	_shadow_mm = _new_ground_multimesh()
	_shadow_mmi = _new_ground_mmi("HordeShadow", _shadow_mm, _ensure_shadow_texture(), Z_SHADOW)

	_grow(64)

func _new_ground_multimesh() -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = false
	mm.mesh = _build_ground_mesh()
	return mm

func _new_ground_mmi(node_name: String, mm: MultiMesh, tex: Texture2D, z: int) -> MultiMeshInstance2D:
	var mmi := MultiMeshInstance2D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.texture = tex
	mmi.z_index = z
	add_child(mmi)
	return mmi

## Bottom-center pivot quad: local x in [-0.5, 0.5], y in [-1, 0]. Matches
## DistractionAnimator._draw_texture_centred()'s Rect2(Vector2(-size.x*0.5, -size.y)
## + shift, size) — an instance transform scaled by (size.x, size.y) reproduces that
## rect exactly (see rebuild()'s transform math below).
func _build_body_mesh() -> ArrayMesh:
	return _build_quad(Vector2(-0.5, -1.0), Vector2(0.5, 0.0))

## Centered quad: local x/y in [-0.5, 0.5] — glow and shadow are ground blobs centred
## on the creature's feet, not bottom-anchored like the body.
func _build_ground_mesh() -> ArrayMesh:
	return _build_quad(Vector2(-0.5, -0.5), Vector2(0.5, 0.5))

func _build_quad(top_left: Vector2, bottom_right: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tl := Vector3(top_left.x, top_left.y, 0.0)
	var tr := Vector3(bottom_right.x, top_left.y, 0.0)
	var br := Vector3(bottom_right.x, bottom_right.y, 0.0)
	var bl := Vector3(top_left.x, bottom_right.y, 0.0)
	var verts := [tl, tr, br, bl]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uvs[i])
		st.add_vertex(verts[i])
	return st.commit()

func _build_atlas_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/horde_atlas.gdshader")
	return mat

## A soft radial falloff, generated once and cached in a static var — the same pattern
## game.gd's own dopamine-burst dot uses (docs/core/01_rendering_and_depth.md, "Glitch
## shader and Dopamine particles"): "an 8x8 soft dot is generated once in code and
## cached". `rgb` is baked into the texture so glow (white, tinted per-instance by
## def.color via MultiMesh colour) and shadow (fixed near-black, never tinted) can
## share this helper without the shadow picking up a colour tint it never had before.
static func _radial_image(size: int, rgb: Color) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var d: float = Vector2(x, y).distance_to(Vector2(c, c)) / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = a * a # softer falloff — reads closer to the old multi-ring stack than a linear one
			img.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, a))
	return img

static func _ensure_glow_texture() -> ImageTexture:
	if _glow_tex == null:
		_glow_tex = ImageTexture.create_from_image(_radial_image(32, Color.WHITE))
	return _glow_tex

static func _ensure_shadow_texture() -> ImageTexture:
	if _shadow_tex == null:
		_shadow_tex = ImageTexture.create_from_image(_radial_image(32, Color(0.01, 0.01, 0.04)))
	return _shadow_tex

## Grows every multimesh's instance_count to at least `min_capacity`, doubling rather
## than growing exactly to size so a horde that fluctuates near a boundary does not
## reallocate every frame. Never shrinks — visible_instance_count (set every
## rebuild()) is what actually controls how many render; a stale tail past it is never
## drawn regardless of what garbage transform sits there from a previous, larger frame.
func _grow(min_capacity: int) -> void:
	if min_capacity <= _capacity:
		return
	var new_cap: int = maxi(min_capacity, maxi(64, _capacity * 2))
	_body_mm.instance_count = new_cap
	_glow_mm.instance_count = new_cap
	_shadow_mm.instance_count = new_cap
	_capacity = new_cap

## Called once per Game frame (Game._process(), AFTER this frame's wave-spawn step so
## a distraction spawned this same frame is included immediately rather than popping
## in one frame late) with the current live distraction list. Writes every
## batch-eligible instance's transform/colour/atlas-uv into the three multimeshes and
## hides everything else via visible_instance_count.
func rebuild(distractions: Array) -> void:
	if distractions.is_empty():
		_body_mm.visible_instance_count = 0
		_glow_mm.visible_instance_count = 0
		_shadow_mm.visible_instance_count = 0
		return
	_grow(distractions.size())
	# Data.UNIT_ART_SCALE on top of pixel_scale(): this batch sizes sprites independently
	# of DistractionAnimator._sprite_size(), so it needs the same combined factor or a
	# batched (walking) body would visibly mismatch the size of a non-batched (dying/
	# blocked/fallback) one drawn through the per-node path. See Data.UNIT_ART_SCALE's
	# own header for the measured raw-pixel numbers behind it.
	var scale: float = Data.pixel_scale() * Data.UNIT_ART_SCALE
	var gy: float = 1.0 / maxf(GridProjection.GROUND_Y_SCALE, 0.001)
	var i := 0
	for d in distractions:
		if not is_instance_valid(d) or d.dead:
			continue
		var animator: DistractionAnimator = d.animator
		if animator == null:
			continue
		var fd: Dictionary = animator.batch_frame_data()
		if fd.is_empty():
			continue # not eligible this frame — DistractionAnimator's own _draw() handles it
		var frame_uv: Rect2 = HordeAtlas.uv(fd["base_id"], fd["variant"], fd["dir_suffix"], fd["frame_idx"])
		var px: Vector2 = HordeAtlas.px_size(fd["base_id"], fd["variant"], fd["dir_suffix"], fd["frame_idx"])
		if frame_uv.size == Vector2.ZERO or px == Vector2.ZERO:
			continue # atlas out of room (HordeAtlas._pack_one) — legacy path picks this one up

		# ---- body ----
		var size: Vector2 = px * scale
		var mirror: bool = fd["mirror"]
		var shift: Vector2 = Vector2(fd["offset"]) * scale
		# Mirroring reflects the WHOLE local frame about x=0 (see DistractionAnimator.
		# _draw_sprite_frames()'s draw_set_transform(..., Vector2(-1,1)) branch), which
		# also negates any authored x-shift — matched here so a mirrored west walk uses
		# the same per-frame AnimTuning offset the east art was authored with.
		var eff_shift_x: float = -shift.x if mirror else shift.x
		var origin: Vector2 = d.position + Vector2(eff_shift_x, shift.y)
		var sx: float = -size.x if mirror else size.x
		_body_mm.set_instance_transform_2d(i, Transform2D(Vector2(sx, 0.0), Vector2(0.0, size.y), origin))
		_body_mm.set_instance_color(i, animator.hit_flash_color())
		_body_mm.set_instance_custom_data(i,
			Color(frame_uv.position.x, frame_uv.position.y, frame_uv.size.x, frame_uv.size.y))

		# ---- glow ----
		var vr: float = animator.visual_radius()
		var glow_d: float = vr * 3.4
		_glow_mm.set_instance_transform_2d(i,
			Transform2D(Vector2(glow_d, 0.0), Vector2(0.0, glow_d * gy), d.position))
		var gcol: Color = Color(d.def.color) if d.def != null else Color.WHITE
		_glow_mm.set_instance_color(i, Color(gcol.r, gcol.g, gcol.b, 0.85))

		# ---- shadow ----
		var drop: float = vr * 1.45 if d.is_flying else 0.0
		var shadow_d: float = vr * 2.3 * shadow_radius_scale
		var salpha: float = (0.22 if d.is_flying else 0.42) * shadow_alpha_scale
		_shadow_mm.set_instance_transform_2d(i,
			Transform2D(Vector2(shadow_d, 0.0), Vector2(0.0, shadow_d * gy), d.position + Vector2(0.0, drop)))
		_shadow_mm.set_instance_color(i, Color(1.0, 1.0, 1.0, salpha))

		i += 1

	_body_mm.visible_instance_count = i
	_glow_mm.visible_instance_count = i
	_shadow_mm.visible_instance_count = i

## How many instances the last rebuild() actually put in the batch — test/debug
## introspection (scripts/_test_horde_renderer.gd), not read by any gameplay code.
func batch_count() -> int:
	return _body_mm.visible_instance_count
