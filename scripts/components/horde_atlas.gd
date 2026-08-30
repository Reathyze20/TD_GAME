class_name HordeAtlas
extends RefCounted
## P5 (docs/refactor/PATHFINDING.MD): one shared runtime texture atlas holding every
## walking-cycle sprite frame (south/north/east; west is east mirrored at draw time,
## the same convention DistractionAnimator already used for the per-node path) that
## HordeRenderer's batched body MultiMeshInstance2D needs. A MultiMeshInstance2D can
## only draw ONE texture per draw call, and different distraction types (and even one
## type's own facings) live in separate PNG files on disk — so this is what makes "one
## draw call for the whole horde" possible at all: every frame any live batched
## instance might need gets packed into one shared sheet, and the instance picks its
## own sub-rect at render time via MultiMesh custom_data (see shaders/horde_atlas.gdshader).
##
## Built LAZILY and INCREMENTALLY: a (type, variant) pair is packed the first time a
## batch-eligible instance of it is actually seen live (DistractionAnimator.
## is_batch_eligible() triggers ensure_packed()), so a level that only ever spawns
## three distraction types never pays to pack the other ten. Static/shared across
## every Game instance in this process — same pattern as DistractionAnimator's own
## _frame_cache and AnimTuning's cache: the art on disk does not change mid-run, so
## there is nothing to invalidate, and a second Game (next level, or a second harness
## in the same process) reuses whatever a previous one already packed.
##
## Only WALKING frames (south/north/east) go in here — death and attack frames never
## do, because a dying or Ally-blocked distraction is deliberately excluded from the
## batch entirely and stays on DistractionAnimator's own per-node draw (see
## is_batch_eligible()). That keeps this atlas an order of magnitude smaller than
## packing the whole roster's full animation set would be.

const ATLAS_W := 2048
const ATLAS_H := 2048
const PAD := 1 ## gutter between packed frames — avoids neighbour bleed if filtering is ever linear

## south/north/east cover every facing DistractionAnimator._facing_frames() ever
## resolves to (west reuses east, mirrored) — see that function's own comment.
const DIR_SUFFIXES: Array[String] = ["", "_north", "_east"]

static var _img: Image = null
static var _tex: ImageTexture = null
static var _cursor := Vector2i(PAD, PAD)
static var _row_h := 0
static var _known: Dictionary = {} ## "base|variant" -> true, once that pair is packed
## "base|variant|dir_suffix|frame_idx" -> Rect2 (uv, normalized 0..1)
static var _uv: Dictionary = {}
## same key -> Vector2 (source texture size in px — HordeRenderer scales by this,
## exactly like DistractionAnimator._sprite_size() scales by tex.get_width()/height())
static var _px_size: Dictionary = {}

static func _ensure_image() -> void:
	if _img == null:
		_img = Image.create(ATLAS_W, ATLAS_H, false, Image.FORMAT_RGBA8)
		_tex = ImageTexture.create_from_image(_img)

## The shared atlas texture — assign this to HordeRenderer's body MultiMeshInstance2D.
static func texture() -> ImageTexture:
	_ensure_image()
	return _tex

## True once base_id+variant_suffix's walk frames are packed and look-up-able.
static func has(base_id: String, variant_suffix: String) -> bool:
	return _known.has(base_id + "|" + variant_suffix)

## Packs south/north/east frames for one (type, variant) into the atlas if they are
## not there already. Reuses DistractionAnimator.load_frame_set() — the exact same
## static cache the per-node fallback path itself reads — so this can never disagree
## with what that path would have drawn for the same instance. Returns true if the
## pair is packed and ready to look up (whether just now or on a prior call), false if
## the type genuinely has no walking art (caller should keep that instance on the
## legacy per-node path) or the atlas ran out of room.
static func ensure_packed(base_id: String, variant_suffix: String) -> bool:
	var known_key := base_id + "|" + variant_suffix
	if _known.has(known_key):
		return true
	_ensure_image()
	var packed_any := false
	var overflowed := false
	for dir_suffix in DIR_SUFFIXES:
		var frames: Array[Texture2D] = DistractionAnimator.load_frame_set(base_id, variant_suffix, dir_suffix)
		for i in range(frames.size()):
			var tex := frames[i]
			var img: Image = tex.get_image() if tex != null else null
			if img == null:
				continue
			if img.get_format() != Image.FORMAT_RGBA8:
				img = img.duplicate()
				img.convert(Image.FORMAT_RGBA8)
			var key := base_id + "|" + variant_suffix + "|" + dir_suffix + "|" + str(i)
			if _pack_one(key, img):
				packed_any = true
			else:
				overflowed = true
	_known[known_key] = true
	if packed_any:
		_tex.set_image(_img)
	return packed_any and not overflowed

## Shelf-packs one frame into the atlas at the current cursor, wrapping to a new row
## when it does not fit. Returns false (and leaves the atlas untouched) if the atlas
## is entirely out of room — a real but very unlikely ceiling: ATLAS_W x ATLAS_H at
## typical distraction frame sizes (docs/ROSTER.md's whole roster, every facing, every
## variant) is comfortably below capacity; see this file's own header for why death/
## attack frames never even reach here to begin with.
static func _pack_one(key: String, img: Image) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	if _cursor.x + w + PAD > ATLAS_W:
		_cursor.x = PAD
		_cursor.y += _row_h + PAD
		_row_h = 0
	if _cursor.y + h + PAD > ATLAS_H:
		push_warning("HordeAtlas: out of space, '%s' dropped — grow ATLAS_W/ATLAS_H" % key)
		return false
	_img.blit_rect(img, Rect2i(Vector2i.ZERO, Vector2i(w, h)), _cursor)
	_uv[key] = Rect2(float(_cursor.x) / float(ATLAS_W), float(_cursor.y) / float(ATLAS_H),
		float(w) / float(ATLAS_W), float(h) / float(ATLAS_H))
	_px_size[key] = Vector2(w, h)
	_cursor.x += w + PAD
	_row_h = maxi(_row_h, h)
	return true

## Normalized UV rect for one packed frame, or an empty Rect2 (size ZERO) if it was
## never packed (caller must check — see HordeRenderer.rebuild()).
static func uv(base_id: String, variant_suffix: String, dir_suffix: String, frame_idx: int) -> Rect2:
	return _uv.get(base_id + "|" + variant_suffix + "|" + dir_suffix + "|" + str(frame_idx), Rect2())

## Source pixel size of one packed frame, or Vector2.ZERO if never packed.
static func px_size(base_id: String, variant_suffix: String, dir_suffix: String, frame_idx: int) -> Vector2:
	return _px_size.get(base_id + "|" + variant_suffix + "|" + dir_suffix + "|" + str(frame_idx), Vector2.ZERO)

## Test-only: drops every packed frame so a fixture can start from a clean atlas
## rather than inheriting state from whatever else ran earlier in the same process.
static func reset_for_tests() -> void:
	_img = null
	_tex = null
	_cursor = Vector2i(PAD, PAD)
	_row_h = 0
	_known.clear()
	_uv.clear()
	_px_size.clear()
