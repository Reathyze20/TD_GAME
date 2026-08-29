class_name SimStrategy
extends RefCounted
## Decision policy for LevelSimulator (S2, docs/refactor/SYSTEMS.MD). Ticked once per
## simulated frame with the current phase, mirroring what a real player could decide
## each frame — override the hooks a concrete strategy needs; the rest default to
## doing nothing. Must not introduce its own unseeded randomness, or two runs of the
## same LevelSimulator seed would stop being bit-identical.

## Called every frame while the level is in its build phase (LevelSimulator.is_build_phase()
## is true). Call sim.build()/sim.aim()/sim.quick_hit() any number of times, and
## sim.start_wave() whenever ready to move on — nothing advances to combat until that
## call happens, exactly like a real player never being forced off the build screen.
func on_build_tick(_sim: LevelSimulator) -> void:
	pass

## Called every frame while a wave is in progress.
func on_wave_tick(_sim: LevelSimulator) -> void:
	pass

## Called once per frame a draft is pending, until it is resolved. `options` is the
## hand currently on offer (may be empty). Return the chosen CardData, or null to skip.
func on_draft(_sim: LevelSimulator, _options: Array[CardData]) -> CardData:
	return null
