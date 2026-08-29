class_name SpawnBatchData extends Resource
## One group within a generated wave: N of one distraction type, spaced `spacing`
## seconds apart. This is the runtime OUTPUT of Data.build_waves(), not hand-authored.

@export var distraction: DistractionData
@export var count: int = 0
@export var spacing: float = 0.2
## Copied from the authoring WaveCurveEntryData row — see its SpawnShape doc comment.
@export var shape: WaveCurveEntryData.SpawnShape = WaveCurveEntryData.SpawnShape.STREAM
