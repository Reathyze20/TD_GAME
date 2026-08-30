class_name MapSegmentData extends Resource
## One optional chunk of board that a level grows by once the player has unlocked it
## (docs/refactor/PATHFINDING.MD P8, "MapSegmentData a skládání levelů").
##
## THIS RESOURCE CARRIES NO GEOMETRY, ON PURPOSE. It is a HEADER attached to a
## `LevelData` (see `LevelData.segment`): that level's own `high_ground`/`path_cells`/
## `decor`/... ARE the segment's geometry, and the four fields below only say who the
## segment is, where its geometry lands, what unlocks it, and which spawn points come
## with it. The rule the queue settled in P0 and repeated here is "odkazem, ne kopií" —
## level N+1 REFERENCES level N through `LevelData.base` rather than copying its cells,
## so editing the base map fixes every level built on it at once and no cell layout ever
## exists twice.
##
## Why the reference points that way round (LevelData -> MapSegmentData, not the
## reverse): a segment has to be AUTHORABLE, and the only sanctioned way to author board
## geometry in this project is scenes/MapEditor.tscn baking a LevelData (CLAUDE.md,
## "Levely se autorují v scenes/MapEditor.tscn a bakují"). Making the segment's geometry
## a LevelData means a segment is painted with the tools that already exist, and this
## header is the one small extra resource an author attaches to it. A geometry field
## here would have needed a second, parallel level editor.
##
## See scripts/map_composer.gd for the composition itself, including exactly which
## LevelData fields compose and which the played level always wins on.

## Stable name of this segment. Two jobs, both of them lookups rather than display:
##   * `SpawnPointData.requires_segment` names it, so a spawn point can be authored on
##     the BASE map yet stay dark until the segment that justifies it is in play.
##   * Composition order is canonicalised by this id (see MapComposer), which is what
##     makes the composed board depend on WHICH segments are live and never on the order
##     they happened to be applied in.
## Unique across the segments reachable from one level, or the later of two identical
## ids silently wins every collision.
@export var id: StringName

## Where this segment's geometry lands on the composed board, in CELLS. Every cell the
## segment's own LevelData authors (high_ground, path_cells, terrain tiles, trod cells,
## spawn points, and `adds_spawns` below) is shifted by this before it joins the board,
## so the segment can be painted around its own origin and placed afterwards.
##
## Decor is shifted too, by `anchor_offset * Data.GRID.tile`, because decor positions are
## field PIXELS rather than cells (see LevelData.decor).
##
## HARD LIMIT: the offset geometry must still land inside the visible board. A segment
## that would push content off screen is REFUSED at composition time (MapComposer drops
## it and push_error()s) rather than silently forcing the camera to scroll — a scrolling
## map breaks the concentration this whole game is built on (Doucet, Defender's Quest).
@export var anchor_offset: Vector2i

## Persistent flag in MetaProgression that has to be set for this segment to be part of
## the board — `MetaProgression.is_segment_unlocked()` is the single reader.
##
## Deliberately NOT a level-completion record and NOT a Growth Tree node (decided
## 2026-08-30): the map growing is meta progress that survives a lost run, so it lives in
## SaveGame.unlocked_segments beside the other things that outlive a run, not in
## `cleared_levels` (which is per level and would make the board depend on which level
## you happen to have beaten) and not in `growth_ranks` (which is bought with Insight and
## would put board geometry on the shop shelf).
##
## Empty means "no condition" — the segment is simply always part of the board. Several
## segments MAY share one condition; that is how one unlock opens a whole wing.
@export var unlock_condition: StringName

## Spawn points this segment brings with it, in the segment's OWN cell space (they are
## shifted by `anchor_offset` like every other cell it owns).
##
## This is the place to author a segment's spawns. The segment's LevelData may also carry
## its own `spawn_points` and those are honoured as well, but a point authored HERE reads
## as "belongs to the segment" at a glance, and it lets a segment's geometry LevelData
## stay a pure board.
##
## Set `requires_segment` on them to this segment's `id` if you also want them dark on
## any board where the segment is not live — composition already leaves them out in that
## case, so it is belt-and-braces rather than required.
@export var adds_spawns: Array[SpawnPointData] = []
