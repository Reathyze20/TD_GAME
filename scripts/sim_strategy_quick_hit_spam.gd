class_name SimStrategyQuickHitSpam
extends SimStrategy
## Presses Quick Hit every single tick, build phase and wave alike, builds nothing,
## always skips the draft, and advances the wave the instant the build phase begins.
## The "spam Quick Hit" baseline S3 (docs/refactor/SYSTEMS.MD) asks for.
##
## Game.do_quick_hit() is fully self-guarded (a real cooldown, level-data
## availability, game_ended) — calling it every tick is exactly as safe as a player
## mashing the button, and only actually pays out on the ticks the cooldown allows.

func on_build_tick(sim: LevelSimulator) -> void:
	sim.quick_hit()
	sim.start_wave()

func on_wave_tick(sim: LevelSimulator) -> void:
	sim.quick_hit()
