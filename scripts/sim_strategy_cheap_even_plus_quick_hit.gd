class_name SimStrategyCheapEvenPlusQuickHit
extends SimStrategy
## Builds like `SimStrategyCheapEven` AND presses Quick Hit on every tick from the very
## first frame. The baseline M4 (PATHFINDING.MD) needs to measure the game's signature
## lesson, which none of the existing five could reach.
##
## WHY THE EXISTING BASELINES CANNOT MEASURE IT. `SimStrategyQuickHitSpam` presses the
## button but never builds, so it loses for a reason that has nothing to do with Tolerance
## — it has no defense at all. `SimStrategyHabitsEmergencyQuickHit` builds, but only
## presses below 30% Focus, i.e. once the run is already lost. Neither describes the player
## the lesson is aimed at: the one who builds a real defense AND keeps reaching for the
## cheap button because it is free money right now.
##
## WHAT IT IS SUPPOSED TO SHOW. `00_overview.md`'s second signature mechanic is "cheap,
## instant dopamine is borrowed — you pay it back with tolerance", and the queue is
## explicit that the lesson only lands if the player regrets their OWN optimisation. That
## makes this strategy's comparison against plain `cheap_even` the measurement: same
## builds, same everything, one extra button. If spam ends AHEAD, the lesson has no teeth;
## if it ends behind having been ahead early, the lesson is in the data.
##
## The mechanism it is measuring is a ratchet, not the visible spike: each press adds
## QUICK_HIT_SPIKE (18) to Tolerance, which decays at 4/s and is therefore gone before the
## 6 s cooldown is up — but it also calls raise_tolerance_floor(QUICK_HIT_FLOOR_GAIN),
## +2 that NEVER decays. Tolerance then scales both sources down together
## (game_state.gd `_on_distraction_defeated`: reward × (1 − 0.6 × tolerance/100), and
## game.gd `quick_hit_payout()` uses the same curve), so the cost of pressing shows up in
## what the player's KILLS pay, not only in what the button pays.

const CHEAP_TYPE := &"focus_timer"


func on_build_tick(sim: LevelSimulator) -> void:
	sim.quick_hit()
	var cost: int = Data.get_habit(CHEAP_TYPE).build_cost
	for cell in sim.buildable_cells():
		if GameState.dopamine < cost:
			break
		sim.build(cell, String(CHEAP_TYPE))
	sim.start_wave()


func on_wave_tick(sim: LevelSimulator) -> void:
	sim.quick_hit()
