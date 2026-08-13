class_name StatusManager
extends Node
## Reusable status-effect component. Manages Calm (slow), Reframe (resistance strip),
## and Boredom (damage over time) for the parent entity.
##
## Rule for Calm and Reframe: **strongest wins, duration is never truncated.**
## "Strongest" is inverted for Calm (lower factor = stronger), normal for Reframe.
##
## Boredom is the exception: it stacks PER SOURCE. Each distinct applier (each Real
## Hobby on the field) contributes its own dps and they sum — otherwise building a
## second Real Hobby added zero damage, and Boredom is the only damage that bypasses
## the boss's Denial Shield, so that silent cap decided boss fights. Within one
## source the old rule still holds (strongest wins, duration never truncated), which
## is what stops a single habit's overlapping pulses from stacking with themselves.
##
## Created as a child node by the entity's setup(). The entity calls tick(delta) at
## the very top of its _process(), before any early returns (blocked, unrouted, etc.),
## so statuses always count down even while the entity is held in place.

# --- Calm (Slow) ----------------------------------------------------------------
## 1.0 = unslowed, 0.0 = full Interrupt (frozen). Applied by habits with a slow value.
var slow_factor := 1.0
var _slow_left := 0.0

# --- Reframe (resistance strip) -------------------------------------------------
## Strips this many points of both Compulsion AND Rationalization while active.
## Naming the hook loosens its grip — Mindfulness opens the target for heavy hitters.
var reframe_amount := 0
var _reframe_left := 0.0

# --- Boredom (damage over time) --------------------------------------------------
## Novelty draining away. Bypasses both Compulsion and Rationalization: you cannot
## rationalise your way out of something simply being boring — the reliable answer
## to heavily-resistant types.
## `boredom_dps` is the SUMMED dps across all live sources — kept as a plain readable
## var because the draw code and older harnesses read it directly.
var boredom_dps := 0.0
## source instance id (0 = anonymous) -> {dps, left, accum}. Each source carries its
## OWN fractional accumulator so its damage can be credited back to it.
var _boredom_sources: Dictionary = {}

## Emitted per whole point of Boredom damage, PER SOURCE — `source` is the habit that
## applied the dot (null for anonymous/freed sources), so panel kill/damage counters
## can credit the right tower. The parent entity connects this to take_direct_damage().
signal boredom_damage(amount: int, source: Object)

## Emitted when reframe_amount changes (applied or expired) — lets the parent
## queue_redraw() for the cracked-ring visual tell without polling.
signal reframe_changed(amount: int)

# ---------------------------------------------------------------- public API

## Advance all status timers by delta. Call this at the very top of the parent's
## _process(), BEFORE any early returns (blocked, unrouted, dead-check, etc.).
func tick(delta: float) -> void:
	_tick_slow(delta)
	_tick_reframe(delta)
	_tick_boredom(delta)

## Strongest Calm wins: a weaker pulse cannot dilute or cut short a stronger one
## (lower factor = stronger). Re-applying the same or stronger slow refreshes its timer.
func apply_slow(factor: float, duration: float) -> void:
	if _slow_left <= 0.0 or factor <= slow_factor:
		slow_factor = factor
		_slow_left = maxf(_slow_left, duration)

## Strongest Reframe wins. One rule governs all three statuses: strongest wins, and
## duration is never truncated.
func apply_reframe(amount: int, duration: float) -> void:
	if amount <= 0:
		return
	if amount >= reframe_amount:
		reframe_amount = amount
		_reframe_left = maxf(_reframe_left, duration)
		reframe_changed.emit(reframe_amount)

## Boredom stacks per source: pass the applying habit as `source` so each distinct
## tower adds its own dps. A null source shares one anonymous slot (legacy callers,
## interventions) with the old strongest-wins semantics inside that slot.
func apply_boredom(dps: float, duration: float, source: Object = null) -> void:
	if dps <= 0.0:
		return
	var key: int = source.get_instance_id() if source != null else 0
	if _boredom_sources.has(key):
		var entry: Dictionary = _boredom_sources[key]
		if dps >= entry.dps:
			entry.dps = dps
			entry.left = maxf(entry.left, duration)
	else:
		_boredom_sources[key] = {"dps": dps, "left": duration, "accum": 0.0}
	_sum_boredom()

## Whether a slow effect is currently active.
func has_slow() -> bool:
	return slow_factor < 1.0

## Whether a reframe effect is currently active.
func has_reframe() -> bool:
	return reframe_amount > 0

## Whether a boredom effect is currently active.
func has_boredom() -> bool:
	return boredom_dps > 0.0

## Clears all active effects immediately.
func reset() -> void:
	slow_factor = 1.0
	_slow_left = 0.0
	reframe_amount = 0
	_reframe_left = 0.0
	boredom_dps = 0.0
	_boredom_sources.clear()

# ---------------------------------------------------------------- internals

func _tick_slow(delta: float) -> void:
	if _slow_left > 0.0:
		_slow_left -= delta
		if _slow_left <= 0.0:
			slow_factor = 1.0

func _tick_reframe(delta: float) -> void:
	if _reframe_left > 0.0:
		_reframe_left -= delta
		if _reframe_left <= 0.0:
			reframe_amount = 0
			reframe_changed.emit(reframe_amount)

func _tick_boredom(delta: float) -> void:
	if _boredom_sources.is_empty():
		return
	var expired := false
	for key: int in _boredom_sources.keys():
		var entry: Dictionary = _boredom_sources[key]
		entry.accum += entry.dps * delta
		entry.left -= delta
		var whole: int = int(entry.accum)
		if whole > 0:
			entry.accum -= float(whole)
			var src: Object = instance_from_id(key) if key != 0 else null
			boredom_damage.emit(whole, src)
			if not _boredom_sources.has(key):
				return   # the emit killed the entity and something reset() this manager
		if entry.left <= 0.0:
			_boredom_sources.erase(key)
			expired = true
	if expired:
		_sum_boredom()

func _sum_boredom() -> void:
	var total := 0.0
	for entry: Dictionary in _boredom_sources.values():
		total += float(entry.dps)
	boredom_dps = total
