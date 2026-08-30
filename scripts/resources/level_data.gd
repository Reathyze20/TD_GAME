class_name LevelData extends Resource
## One playable level: field layout + the horde curve that generates its waves.

@export_category("Identity")
## Campaign order AND the key the end screens use — keep it unique across data/levels/.
## Data sorts levels by this at startup, so id decides where the level appears.
@export var id: int = 1
## Shown in the level-select menu and on the end screens.
@export var display_name: String = "Level 1"

@export_category("Economy & Focus")
## Dopamine in the bank when the level opens — the entire first-build budget.
@export var start_dopamine: int = 260
## The level's health pool. Every escaped distraction burns some; at 0 the run is lost.
@export var focus: int = 30
## Enables the Quick Hit button and the Tolerance mechanic (level 2's lesson).
@export var quick_hit: bool = false
## Defeats pay a variable-ratio amount instead of a flat one. Expected value is
## IDENTICAL either way (GameState._payout_multiplier) — only the predictability
## changes, which is what makes the Steady Payout card an honest experiment rather
## than a trick question. Off on level 1: the first level runs no experiments.
@export var variable_rewards: bool = false
## Offer "take less now / more at the end of the wave" before each wave. The delayed
## option is always worth more, so every impatient pick is a measurement rather than a
## mistake the level punished.
@export var delay_offers: bool = false

@export_category("Attention lessons")
## The conditioned cue's phase in this level. It teaches by being CONSISTENT first and
## empty afterwards, which cannot be done retroactively — level 1 must already be
## training it or there is nothing to hollow out later.
##   0 OFF · 1 TRAINING (always precedes a real reward) · 2 EMPTY (fires, pays nothing)
@export_range(0, 2) var cue_phase: int = 0
## Waves announced as a bonus that then pay nothing. Negative prediction error, the one
## thing that drops the picture BELOW its own baseline. One per campaign, two at most —
## a third reads as a bug rather than as a feeling.
@export var bait_waves: Array[int] = []
## The fast. Quick Hit is unavailable, Tolerance drains far faster than usual, and the
## juice comes back gradually across the level instead of being there from wave one.
## Deliberately the least fun stretch in the campaign for its first two thirds; the
## payoff is that the first clean kill after the drought lands on a starved player.
@export var fasting: bool = false
## The finale. The level is won by holding for HANDS_OFF_SECONDS without input rather
## than by clearing the field — the boss lane never empties. Watching your own systems
## hold is both the most relaxing thing a tower defense can produce and the thesis of
## the game, which is why it is the ending.
@export var hands_off_finale: bool = false
## SPIKE (see game.gd "sinking walls"). Above a Tolerance threshold the buildable block
## furthest from the core stops being a wall: the maze frays, distractions path through
## it, and a habit standing on it can be interrupted. Drops back under the threshold and
## the wall returns. Off everywhere until the spike is judged.
@export var sinking_walls: bool = false
## Reveals the second line inside the Tolerance bar (UIMeter.split_value): wanting and
## liking, which have been two numbers all along. Held back until the player has a few
## levels of watching one bar, because the reveal IS that it was always two.
## The consecutive-clean-wave bonus. Real money, and meant to feel good — see the
## streak block in game_state.gd for why it is not a trap. Introduced on the first
## level and left on afterwards: a retention mechanic that appears and vanishes is not
## the thing being demonstrated.
## Presentation and gating switches that used to be a hardcoded `if level.id == 99` in
## game.gd. They are per-level DESIGN decisions, so they belong in the level — the magic
## number silently gave the isometric slice a different game from every other map, and
## the second iso level did not get the exemption because nobody remembered it existed.
##
## Defaults preserve the original top-down behaviour; the iso levels turn all three off.
@export var fog: bool = true
@export var shadows: bool = true
@export var routine_gates: bool = true

@export var streak: bool = false

@export var split_meter: bool = false
## Parody interstitials, in the order they appear. See scripts/resources/ad_data.gd.
@export var ads: Array[AdData] = []

@export_category("Field layout")
## The Focus core's cell — what every distraction walks toward. Drag the green sprite
## in MapEditor rather than typing coordinates here.
@export var objective: Vector2i = Vector2i.ZERO
@export var spawn_zones: Array[Rect2i] = []       ## [x, y, width, height] cell rects.
## Optional, ADDITIVE per-point spawn locations (docs/refactor/PATHFINDING.MD P6). Empty
## (every level today — nothing authors this yet) means Game._random_spawn_cell() keeps
## drawing from spawn_zones exactly as before. Non-empty means it draws ONLY from the
## points here that are active for the wave being built (SpawnPointData.active_from_wave)
## — spawn_zones is then unused for that level, not a merged second source. See
## Game._active_spawn_point_cells() for the exact filter.
@export var spawn_points: Array[SpawnPointData] = []
## Gameplay truth: these cells block movement AND are the only buildable spots.
@export var high_ground: Array[Vector2i] = []

@export_category("Composition")
## The level this one is built ON TOP OF — "Level N+1 = LevelData N + segment, ODKAZEM,
## NE KOPIÍ" (docs/refactor/PATHFINDING.MD P0/P8). Non-null means this level's own
## geometry arrays are a DELTA: at load, MapComposer.compose() walks `base` to the root
## and unions every link's geometry into one flat board. Editing the base map therefore
## fixes every level standing on it at once, and no cell layout is ever stored twice.
##
## Null (every level today) means "I am a whole map on my own" and composition is a pure
## deep copy — bit-identical to what game.gd did before P8 existed.
##
## Must not be cyclic. MapComposer refuses to walk a cycle rather than hanging, but a
## cycle is an authoring bug with no sane composition, so it is an error, not a mode.
@export var base: LevelData = null

## Non-null means THIS LevelData is a SEGMENT: its own geometry only joins the composed
## board when the header's `unlock_condition` is satisfied (see MapSegmentData), and it
## lands shifted by the header's `anchor_offset`. Null means this link's geometry is
## unconditional — the spine of the map, always present.
##
## The pairing is this way round (level owns header, not header owns level) so that a
## segment is painted in scenes/MapEditor.tscn exactly like any other board; see
## MapSegmentData's own header for why that mattered enough to decide the direction.
@export var segment: MapSegmentData = null

@export_category("Terrain art")
## Which tile sits on which cell: Vector2i cell -> Vector3i(source_id, atlas_x, atlas_y),
## against res://data/terrain/high_ground_tileset.tres.
##
## Deliberately SEPARATE from `high_ground` rather than merged into it. Gameplay must not
## depend on whether art has been authored yet: an empty dictionary simply means "no tiles
## painted", and the game falls back to drawing its vector walls. That keeps every level
## playable while the tile art is still being made, and keeps a missing texture from ever
## becoming a pathfinding bug.
@export var terrain_tiles: Dictionary = {}

## Ručně vybraná dlaždice podlahy: Vector2i(buňka) -> "ground/ground_03" (cesta bez
## přípony, relativně k assets/terrain/iso/).
##
## ČISTĚ VZHLED. Kudy se dá projít a kde se dá stavět určuje dál `high_ground` a
## `path_cells` — tahle mapa jen přebíjí, KTERÁ textura se na buňku vykreslí. Kdyby
## určovala i hru, namalovaná zeď by nebyla zeď a nepřátelé by jí prošli; ta vazba mezi
## daty a artem je jediný důvod, proč funguje pathfinding a stavební místa.
##
## Prázdné = všechno se odvodí jako dosud (masky pruhu, varianty ze seedu).
@export var tile_overrides: Dictionary = {}

## Hand-placed scenery: [{"id": "mug", "pos": Vector2(x, y), "flip": bool}, ...] in field
## pixels. Purely decorative — nothing here affects pathing, building or targeting.
##
## Empty means "nobody has dressed this level yet", and DecorLayer falls back to its
## seeded scatter. Same reasoning as terrain_tiles: art being unfinished must never make a
## level unplayable, and a level someone HAS dressed must never be re-scattered on top.
@export var decor: Array[Dictionary] = []

## Hand-painted lanes. Two jobs at once:
##
##  * They get their own floor texture, so the route the designer intends is VISIBLE.
##  * A* charges `path_off_lane_cost` for every step off them, so distractions genuinely
##    prefer them.
##
## Deliberately a preference, not a wall. Blocking everything off-lane would turn the
## open maze into a fixed corridor and break the design pillar in docs/core/00_overview.md
## ("open maze pathfinding … enemies route around fixed high ground"), and any lane the
## player walls off would make the level unsolvable. Weighting steers without lying: the
## horde takes the lane when it can and spills around when it cannot.
@export var path_cells: Array[Vector2i] = []

## How much dearer an off-lane step is. 1.0 = lanes are purely cosmetic; 4.0 keeps the
## horde on the lane unless the detour is over four times longer.
@export_range(1.0, 12.0, 0.5) var path_off_lane_cost: float = 4.0

## Routes that open partway through the level. See scripts/resources/trod_data.gd for
## why these are a preference rather than a terrain change, and for the convergence rule
## that separates "react" from "your work was wasted".
##
## Empty means a static map, which is the old behaviour and stays valid — not every
## level should move under the player, or the one that does stops being an event.
@export var trods: Array[TrodData] = []

@export_category("Horde curve")
## Total number of waves. The last one is the finale — the boss (if set) spawns there.
@export var wave_count: int = 12
## The horde recipe: one entry per distraction type, each saying when it appears and how
## fast its numbers grow. Data.build_waves() expands this into the actual waves.
@export var wave_curve: Array[WaveCurveEntryData] = []

@export_category("Wave modifiers")
## Wave numbers (1-based) where defeats pay NO Dopamine — the "no cash" pressure wave.
## Survival income (early-call bonus, saved Dopamine, Quick Hit at its Tolerance price)
## carries those waves instead. Flagged in the next-wave preview so it never ambushes.
@export var lean_waves: Array[int] = []

@export_category("Card drafts")
## A draft fires after every Nth wave is cleared, PLUS always right before the final
## wave — that last one is the level's hardest and the pre-boss draft is the whole
## point of the mechanic, so it is guaranteed rather than left to the interval landing
## on it. A 12-wave level at interval 3 drafts after waves 3, 6, 9 and 11.
## Set to 0 to keep only the guaranteed pre-final draft.
@export var draft_interval: int = 3

@export_category("Boss")
@export var boss: DistractionData = null   ## Optional. Spawned once, partway into the final wave.

## Populated at runtime by Data.build_waves() — not exported/hand-authored.
var waves: Array[WaveData] = []

## Ids of the MapSegmentData headers whose geometry is actually part of THIS composed
## board. Populated at runtime by MapComposer.compose() — not exported/hand-authored,
## same contract as `waves` above.
##
## This is what gives SpawnPointData.requires_segment its meaning (P8): a spawn point
## naming a segment is eligible only while that segment is in here. Empty — which is
## every level that was never composed, i.e. every level on disk today — means any
## non-empty requires_segment reads as "never active", exactly the behaviour P6 shipped
## and P7 built on.
var active_segments: Array[StringName] = []
