@tool
class_name AnimTuning extends Resource
## Timing and per-frame alignment for the hand-authored distraction sprite sets.
##
## @tool is load-bearing, not decoration. The Animation Lab dock is an editor plugin, and
## the editor instantiates a non-tool script's resource as a PLACEHOLDER: the exported
## properties are there but every method call fails with "Attempt to call a method on a
## placeholder instance". The dock does nothing but call methods on this, so without the
## annotation the panel comes up empty and the console fills with errors.
##
## Why a separate resource and not fields on DistractionData: these numbers describe ART
## FILES, not the creature. The key is exactly the filename stem the animator builds its
## paths from — `energy_drink`, `energy_drink_east`, `energy_drink_death` — so a set keeps
## its tuning when the creature's stats change, a variant tunes independently of the
## creature it varies, and a set nobody has touched is simply absent from both
## dictionaries and falls back to the animator's defaults.
##
## Authored by the Animation Lab dock (addons/td_anim_lab), read by DistractionAnimator.
## Nothing else writes it.

const PATH := "res://data/anim_tuning.tres"

## Filename stem -> frames per second. Absent or <= 0 means "use the animator's default".
@export var fps: Dictionary = {}

## Filename stem -> Array[Vector2i], one entry per frame, in ART pixels.
##
## Art pixels, not screen pixels, on purpose: the animator multiplies by the integer
## sprite scale, so one step of nudge is one source pixel at every zoom and the art never
## lands on a half pixel. A set whose nudges are all zero is erased rather than stored, so
## the saved file only ever contains sets somebody actually tuned.
@export var offsets: Dictionary = {}


func fps_for(key: String, fallback: float) -> float:
	var v: float = float(fps.get(key, 0.0))
	return v if v > 0.0 else fallback


func offset_for(key: String, frame: int) -> Vector2i:
	var arr: Array = offsets.get(key, [])
	if frame < 0 or frame >= arr.size():
		return Vector2i.ZERO
	return arr[frame]


func offsets_for(key: String, frame_count: int) -> Array:
	var arr: Array = (offsets.get(key, []) as Array).duplicate()
	while arr.size() < frame_count:
		arr.append(Vector2i.ZERO)
	return arr


func set_fps(key: String, value: float, default_fps: float) -> void:
	if is_equal_approx(value, default_fps) or value <= 0.0:
		fps.erase(key)
	else:
		fps[key] = value


func set_offsets(key: String, arr: Array) -> void:
	for v in arr:
		if v != Vector2i.ZERO:
			offsets[key] = arr
			return
	offsets.erase(key)
