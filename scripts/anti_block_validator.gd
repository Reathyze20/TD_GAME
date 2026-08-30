class_name AntiBlockValidator
extends RefCounted
## A wall must never cut off an active spawn from the objective (docs/refactor/
## PATHFINDING.MD P2). Answers exactly one question — "if this cell became a wall,
## would some active spawn lose its route to the objective?" — and nothing else: no
## opinion on whether a cell is otherwise buildable, no mutation of anything.
##
## Reuses FlowField (P1) rather than inventing a second reachability algorithm: build
## the field from the objective with the candidate cell added to `blocked`, then check
## that every active spawn is still in it. That is a FULL field rebuild, not the
## "union-find nebo lokální re-BFS" P2's own text offers as the two expected
## approaches — a third, simpler option, chosen because it already meets the task's
## own budget by a wide margin (see `_test_antiblock.gd`'s bench section: ~0.6ms on
## the actual 30x14 shipped grid, against a 1ms budget) without either union-find's
## bookkeeping (which does not support cheaply UNDOING a wall, and this game does
## allow un-building) or a hand-rolled local BFS's correctness risk (a local check has
## to reason conservatively about the region it did NOT visit, which is exactly the
## kind of subtle-off-by-one surface a full rebuild has none of). If a future, much
## larger map (P8 segments) ever makes this measurably slow, that is the moment to
## revisit — not a guess made now against a board that does not exist yet.
##
## `active_spawns` is a plain Array of cells, not read from LevelData directly:
## nothing today gates a spawn as active or inactive (P6, "SpawnPointData a více
## spawnů", introduces `active_from_wave`) — this module stays ignorant of waves
## entirely, and P6's own filtering decides what counts as "active" before calling in.

## True if placing a wall at `candidate` would strand at least one cell in
## `active_spawns` — i.e. the placement is ILLEGAL. `blocked` is read, never mutated;
## the trial dictionary is a copy.
static func would_block(cols: int, rows: int, objective: Vector2i, blocked: Dictionary,
		candidate: Vector2i, active_spawns: Array) -> bool:
	if blocked.has(candidate):
		return false  # Already a wall — "placing" it again changes nothing.
	var trial: Dictionary = blocked.duplicate()
	trial[candidate] = true
	var field := FlowField.build(cols, rows, objective, trial)
	for spawn: Vector2i in active_spawns:
		if not field.has_cell(spawn):
			return true
	return false

## The same question phrased the other way round, for call sites that read more
## naturally as "is this placement OK to commit".
static func is_legal(cols: int, rows: int, objective: Vector2i, blocked: Dictionary,
		candidate: Vector2i, active_spawns: Array) -> bool:
	return not would_block(cols, rows, objective, blocked, candidate, active_spawns)
