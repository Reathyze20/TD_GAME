class_name WaveCurveEntryData extends Resource
## One row of a level's horde growth curve. Data.build_waves() expands this into real
## per-wave SpawnBatchData: for wave N >= from, count = round(base + growth * (N - from)).

## Which distraction this row spawns. Required — a row without one is a bake blocker.
@export var distraction: DistractionData
## First wave (1-indexed) this type appears in.
@export var from_wave: int = 1
## How many spawn on the wave this row first appears.
@export var base_count: int = 10
## How many MORE spawn with every wave after from_wave (fractions round per wave).
@export var growth_per_wave: float = 2.0
## Seconds between individual spawns in the batch — smaller = denser clump.
@export var spacing: float = 0.2
