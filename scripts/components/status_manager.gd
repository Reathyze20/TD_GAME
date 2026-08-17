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

## Set by a distraction that has earned a permanent exemption from Calm — the Energy
## Drink's Overdrive. A FULL freeze (factor 0.0) still lands: "ignores slows" and "cannot
## be stopped" are different promises, and the second one would make Airplane Mode read
## as broken against the one enemy the player most wants to stop.
var slow_immune := false

# --- Rush (haste) ----------------------------------------------------------------
## 1.0 = normal pace, >1.0 = sped up. The mirror image of Calm, and it multiplies with
## it rather than cancelling it: a distraction can be both wired and half-interrupted,
## and the player should see the slow still doing its job.
##
## Applied by an energiser distraction's pulse (see DistractionData.haste_interval), so
## unlike every other status here the source is an ENEMY buffing its own side.
var haste_factor := 1.0
var _haste_left := 0.0

## A permanent, timer-less speed multiplier — a phase change the creature does not come
## back from (Overdrive). Kept separate from `haste_factor` on purpose: that one is
## strongest-wins and expires, so an Overdrive routed through apply_haste() would SWALLOW
## the Energy Drink's own 1.35 aura instead of compounding with it, then wear off.
var extra_factor := 1.0

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
	_tick_haste(delta)
	_tick_vulnerable(delta)
	_tick_reframe(delta)
	_tick_boredom(delta)

## Strongest Calm wins: a weaker pulse cannot dilute or cut short a stronger one
## (lower factor = stronger). Re-applying the same or stronger slow refreshes its timer.
func apply_slow(factor: float, duration: float) -> void:
	if slow_immune and factor > 0.0:
		return
	if _slow_left <= 0.0 or factor <= slow_factor:
		slow_factor = factor
		_slow_left = maxf(_slow_left, duration)

## Drops any Calm currently on the target. Separate from apply_slow(1.0, 0.0) because
## that one is a no-op by the strongest-wins rule — a weaker value can never dilute a
## running slow, which is exactly the behaviour this needs to bypass.
func clear_slow() -> void:
	slow_factor = 1.0
	_slow_left = 0.0

## Strongest Rush wins (higher factor = stronger), duration never truncated — the same
## rule as Calm, with the comparison flipped. Two energisers overlapping therefore do
## not stack into a runaway sprint; the stronger one simply governs.
func apply_haste(factor: float, duration: float) -> void:
	if factor <= 1.0 or duration <= 0.0:
		return
	if _haste_left <= 0.0 or factor >= haste_factor:
		haste_factor = factor
		_haste_left = maxf(_haste_left, duration)

## Drops any Rush currently on the target — the Zen Pulsar's momentum reset. Separate
## from apply_haste(1.0, 0.0) for the same reason clear_slow() is separate from
## apply_slow(): strongest-wins means a weak value can never dilute a running one.
##
## Deliberately leaves `extra_factor` alone. That is Overdrive, a latched phase change
## the design says a creature "does not come back from" — dispelling it would let one
## habit undo a wounded Energy Drink's whole second act. The stun still lands on it
## regardless, because a full freeze pierces slow_immune.
func clear_haste() -> void:
	haste_factor = 1.0
	_haste_left = 0.0

# --- Vulnerable (damage amplification) -------------------------------------------
## Multiplies incoming habit damage while active — the Resonance Wave's debuff. 1.0 = off.
## Read by Distraction._shape_damage(), so it amplifies what habits do and deliberately
## not what Boredom does: Boredom already bypasses both resistance channels, and stacking
## an amplifier on top of the one damage type nothing mitigates compounds too hard.
var vulnerable_mult := 1.0
var _vulnerable_left := 0.0

## Strongest Vulnerable wins (higher multiplier = stronger), duration never truncated —
## the same rule as Calm, Rush and Reframe.
func apply_vulnerable(mult: float, duration: float) -> void:
	if mult <= 1.0 or duration <= 0.0:
		return
	if _vulnerable_left <= 0.0 or mult >= vulnerable_mult:
		vulnerable_mult = mult
		_vulnerable_left = maxf(_vulnerable_left, duration)

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

## The single multiplier the parent applies to its movement each frame. Calm and Rush
## multiply rather than override, so a slowed-and-hurried distraction lands between the
## two instead of one status silently winning — and a Calm pulse keeps visibly paying
## off even while an energiser is shouting at the same crowd.
func move_scale() -> float:
	return slow_factor * haste_factor * extra_factor

## Whether a slow effect is currently active.
func has_slow() -> bool:
	return slow_factor < 1.0

## Whether a rush effect is currently active.
func has_haste() -> bool:
	return haste_factor > 1.0

## Whether a vulnerability effect is currently active.
func has_vulnerable() -> bool:
	return vulnerable_mult > 1.0

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
	slow_immune = false
	haste_factor = 1.0
	_haste_left = 0.0
	extra_factor = 1.0
	vulnerable_mult = 1.0
	_vulnerable_left = 0.0
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

func _tick_haste(delta: float) -> void:
	if _haste_left > 0.0:
		_haste_left -= delta
		if _haste_left <= 0.0:
			haste_factor = 1.0

func _tick_vulnerable(delta: float) -> void:
	if _vulnerable_left > 0.0:
		_vulnerable_left -= delta
		if _vulnerable_left <= 0.0:
			vulnerable_mult = 1.0

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
