class_name InsightCardData extends Resource
## The educational card shown between levels, tying a real concept to what the
## player just experienced.

@export var level_id: int = 1
@export var title: String = ""
@export var concept: String = ""
@export_multiline var description: String = ""
@export_multiline var takeaway: String = ""
@export var color: String = "4aa3ff"
