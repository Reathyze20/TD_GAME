class_name SpawnPointData extends Resource
## One named spawn location a level's horde can enter the board from (docs/refactor/
## PATHFINDING.MD P6, "SpawnPointData a více aktivních spawnů").
##
## Additive to LevelData.spawn_zones, never a replacement: a level whose spawn_points is
## empty (every level today — nothing authors this yet, and this project's own CLAUDE.md
## forbids hand-editing an existing level's .tres) keeps picking spawn cells uniformly
## from spawn_zones exactly as before. A level that DOES populate spawn_points switches
## Game._random_spawn_cell() over to drawing only from the points active for the wave
## being built — see Game._active_spawn_point_cells().
##
## The flow field (P1, scripts/flow_field.gd) needs NO change to support more spawn
## points: it is already "every source cell -> one shared target field" (built once from
## the objective), so adding spawn locations only changes which cells get READ off the
## SAME field, never how the field itself is built. Reachability for one spawn point is
## exactly FlowField.has_cell(spawn.cell) — the identical check AntiBlockValidator (P2)
## already applies to spawn_zones-derived cells; see that module's header for why
## `active_spawns` there is deliberately a plain Array of cells rather than something
## read from LevelData directly — P6 (this class) is the filtering step P2 was written
## expecting.

## The cell distractions enter the board on — same grid space as LevelData.high_ground
## and LevelData.objective.
@export var cell: Vector2i
## Which way the P7 telegraph (docs/refactor/PATHFINDING.MD P7, not yet built) points its
## warning arrow before this spawn activates. Carried here but UNUSED until P7 lands —
## this class only carries the data shape, P7 owns the visual.
@export var direction_id: StringName          # pro telegraf
## Wave number (1-based — matches LevelData.lean_waves/bait_waves' own convention, and
## the wave number _start_wave() already passes around as `wave_index + 1`) this point
## first becomes eligible for spawn selection. 0 (the default) means "already active on
## wave 1", since no real wave is numbered below 1.
@export var active_from_wave: int = 0
## Names a MapSegmentData (P8, docs/refactor/PATHFINDING.MD, not yet built) this point
## belongs to. Carried here but UNUSED until P8 lands segment composition and unlocking —
## in the meantime Game._active_spawn_point_cells() treats ANY non-empty value as "never
## available", since nothing exists yet that could ever unlock a segment. Empty (the
## default) means "always part of the base map", i.e. gated on active_from_wave alone.
@export var requires_segment: StringName = &""
## Seconds the P7 telegraph (not yet built) shows its warning before this point starts
## producing distractions. Carried here but UNUSED until P7 lands.
@export var telegraph_lead_time: float = 5.0
