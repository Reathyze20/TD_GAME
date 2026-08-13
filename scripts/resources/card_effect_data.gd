class_name CardEffectData extends Resource
## One stat modifier inside a CardData's `effects` array. A card can carry several,
## even opposing, effects — that's what makes two-sided cards possible.

@export var stat_type: String = "willpower"    ## Matches a ModifierManager.STAT_* constant.
@export var target: String = "ALL"             ## A HabitData id, or "ALL".
@export var value: float = 0.0
@export var is_percentage: bool = true         ## true = multiplier, false = flat.
