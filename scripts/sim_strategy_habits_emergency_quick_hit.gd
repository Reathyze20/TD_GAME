class_name SimStrategyHabitsEmergencyQuickHit
extends SimStrategy
## Builds the same cheap, unaimed habits as SimStrategyCheapEven (see its header —
## cheapest attack habit at every buildable cell it can afford, never aims), and
## additionally presses Quick Hit — but ONLY while Focus is critically low, not on
## every tick like SimStrategyQuickHitSpam. The "habity + Quick Hit jen v nouzi"
## baseline Q2 (BLOCKED.md analysis) asks for, to compare against unconditional spam.
##
## "Emergency" is an analysis-harness judgment call, not a game balance number:
## Focus at or below EMERGENCY_FOCUS_RATIO of max_focus. Chosen as a plausible
## "about to lose, grab the safety net" read — not tuned against anything, and the
## one knob to move if a different threshold turns out to matter more.

const CHEAP_TYPE := &"focus_timer"
const EMERGENCY_FOCUS_RATIO := 0.3

func _in_emergency() -> bool:
	if GameState.max_focus <= 0:
		return false
	return float(GameState.focus) / float(GameState.max_focus) <= EMERGENCY_FOCUS_RATIO

func on_build_tick(sim: LevelSimulator) -> void:
	var cost: int = Data.get_habit(CHEAP_TYPE).build_cost
	for cell in sim.buildable_cells():
		if GameState.dopamine < cost:
			break
		sim.build(cell, CHEAP_TYPE)
	if _in_emergency():
		sim.quick_hit()
	sim.start_wave()

func on_wave_tick(sim: LevelSimulator) -> void:
	if _in_emergency():
		sim.quick_hit()
