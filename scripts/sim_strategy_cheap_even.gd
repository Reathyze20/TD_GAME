class_name SimStrategyCheapEven
extends SimStrategy
## Builds the cheapest attack habit (focus_timer, 30 Dopamine — the lowest build_cost
## among Data.HABIT_ORDER's non-support, non-blocker types) at every currently
## buildable cell it can afford, then advances the wave. The "stavet levne veze
## rovnomerne" baseline S3 (docs/refactor/SYSTEMS.MD) asks for.
##
## Deliberately simple, not an attempt at optimal play: never builds an Anchor, so it
## never extends the Routine itself — it is bounded by whatever cells the level's own
## Anchors/core light up on their own. Never aims (leaves every tower at its default
## facing/width) and never presses Quick Hit, so the only variable against the passive
## baseline is "cheap, unaimed towers at every open spot," not a mix of decisions.

const CHEAP_TYPE := &"focus_timer"

func on_build_tick(sim: LevelSimulator) -> void:
	var cost: int = Data.get_habit(CHEAP_TYPE).build_cost
	for cell in sim.buildable_cells():
		if GameState.dopamine < cost:
			break
		sim.build(cell, CHEAP_TYPE)
	sim.start_wave()
