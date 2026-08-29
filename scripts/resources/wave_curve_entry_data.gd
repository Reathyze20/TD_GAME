class_name WaveCurveEntryData extends Resource
## One row of a level's horde growth curve. Data.build_waves() expands this into real
## per-wave SpawnBatchData: for wave N >= from, count = round(base + growth * (N - from)).

## STREAM (default): evenly spaced, `spacing` seconds apart — current/original
## behavior, unchanged. CLUSTER: spawns in tight groups with a longer pause between
## groups — see game.gd's WAVE_CLUSTER_* constants for the exact grouping/gap math.
## BURST: nearly all at once, `spacing` is ignored in favor of a fixed small stagger
## (game.gd's WAVE_BURST_STAGGER) just enough to avoid spawning everything on the
## exact same frame. Existing content is unaffected: every pre-S7 row defaults to
## STREAM, which computes spawn times identically to before this field existed.
enum SpawnShape { STREAM, CLUSTER, BURST }

## Which distraction this row spawns. Required — a row without one is a bake blocker.
@export var distraction: DistractionData
## First wave (1-indexed) this type appears in.
@export var from_wave: int = 1
## How many spawn on the wave this row first appears.
@export var base_count: int = 10
## How many MORE spawn with every wave after from_wave (fractions round per wave).
@export var growth_per_wave: float = 2.0
## Seconds between individual spawns in the batch — smaller = denser clump. Ignored
## by BURST; used as the base gap unit by CLUSTER (see SpawnShape above).
@export var spacing: float = 0.2
## Temporal pacing of this batch's spawns within the wave — see SpawnShape above.
@export var shape: SpawnShape = SpawnShape.STREAM
