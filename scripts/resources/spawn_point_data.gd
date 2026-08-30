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
## Which way the P7 telegraph (docs/refactor/PATHFINDING.MD P7) points its warning arrow
## before this spawn activates — one of "N"/"NE"/"E"/"SE"/"S"/"SW"/"W"/"NW", read by
## Game._telegraph_direction_angle(). Purely cosmetic decoration on the marker: an empty
## or unrecognized value just omits the arrow and draws the pulsing position ring alone
## (no real level populates this yet — P6's own header: "nothing authors this yet"), so
## an author who never sets it loses nothing but the arrow. What the marker's POSITION
## promises (Game._draw_spawn_telegraph(), drawn at `cell`) is never optional — that half
## is the "telegraf musí být pravdivý" hard rule and does not depend on this field at all.
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
## Seconds of SIM-TICK time (Game._sim_tick(), never real/Engine.time_scale-scaled time —
## see docs/refactor/PATHFINDING.MD's Q1 entry for why that split matters) this point is
## shown telegraphed-but-silent after ITS OWN wave begins (active_from_wave == the current
## wave) before it starts producing distractions. Only gates that ONE activation wave: on
## every later wave the point is simply active from the start, no re-telegraphing — see
## Game._active_spawn_point_cells()'s own comment. A point already active from wave 1
## (active_from_wave == 0, the default — "already active on wave 1" per that field's own
## comment above) is never gated by this at all: there is no activation MOMENT for it to
## warn about, it was always going to be there.
@export var telegraph_lead_time: float = 5.0
