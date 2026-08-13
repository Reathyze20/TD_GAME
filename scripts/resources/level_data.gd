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

@export_category("Field layout")
## The Focus core's cell — what every distraction walks toward. Drag the green sprite
## in MapEditor rather than typing coordinates here.
@export var objective: Vector2i = Vector2i.ZERO
@export var spawn_zones: Array[Rect2i] = []       ## [x, y, width, height] cell rects.
## Gameplay truth: these cells block movement AND are the only buildable spots.
@export var high_ground: Array[Vector2i] = []

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
