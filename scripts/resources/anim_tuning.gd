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

## Filename stem -> Array[int], how many base slots each frame is held. 1 = normal.
##
## This is the timing half of the animation, and it matters more than the frame count.
## A five-frame attack held 1-1-3-2-1 reads as wind-up, IMPACT, recovery; the same five
## frames held evenly read as a shrug. Shipped games get their weight from uneven holds,
## not from extra drawings — and every drawing this saves is one fewer frame for a
## generator to draw inconsistently.
##
## Whole multiples of the set's own rate, not milliseconds. Milliseconds would drift out
## of step with fps the moment somebody retuned the rate, and "hold this one three times
## as long" is the actual authoring thought. A set with nothing but 1s is erased rather
## than stored, so an untouched animation stays absent from the file and costs nothing.
@export var holds: Dictionary = {}


## How long frame `i` is held, in base slots. Never below 1: a zero-length frame would be
## skipped entirely and a negative one would corrupt the running total below it.
static func _hold_at(arr: Array, i: int) -> int:
	if i < 0 or i >= arr.size():
		return 1
	return maxi(1, int(arr[i]))


func holds_for(key: String, frame_count: int) -> Array:
	var arr: Array = holds.get(key, [])
	var out: Array = []
	for i in range(frame_count):
		out.append(_hold_at(arr, i))
	return out


## Total length of one cycle in base slots — the number the playback clock wraps around,
## and what death timing must wait for instead of the raw frame count.
func hold_total(key: String, frame_count: int) -> int:
	if frame_count <= 0:
		return 0
	var arr: Array = holds.get(key, [])
	var total := 0
	for i in range(frame_count):
		total += _hold_at(arr, i)
	return total


## Which frame is on screen at `slot` (elapsed time × fps, floored).
##
## The untuned case returns before touching the dictionary — every creature in the game
## goes through here every frame, and an animation nobody has tuned must cost exactly what
## the plain modulo cost before holds existed.
func frame_at(key: String, frame_count: int, slot: int, loop: bool) -> int:
	if frame_count <= 0:
		return 0
	var arr: Array = holds.get(key, [])
	if arr.is_empty():
		return posmod(slot, frame_count) if loop else clampi(slot, 0, frame_count - 1)
	var total := hold_total(key, frame_count)
	var s: int = posmod(slot, total) if loop else clampi(slot, 0, total - 1)
	var acc := 0
	for i in range(frame_count):
		acc += _hold_at(arr, i)
		if s < acc:
			return i
	return frame_count - 1


func set_holds(key: String, arr: Array) -> void:
	for v in arr:
		if int(v) != 1:
			holds[key] = arr
			return
	holds.erase(key)


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
