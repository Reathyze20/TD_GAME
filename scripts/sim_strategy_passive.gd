class_name SimStrategyPassive
extends SimStrategy
## Builds nothing, never presses Quick Hit, always skips the draft — advances the
## wave the instant the build phase begins. The "do nothing" baseline S3
## (docs/refactor/SYSTEMS.MD) asks for, and a useful determinism check on its own:
## with zero decisions to make, any non-determinism in the surrounding simulation
## (spawn timing, enemy AI, status effects) still has to reproduce bit-identically.

func on_build_tick(sim: LevelSimulator) -> void:
	sim.start_wave()
