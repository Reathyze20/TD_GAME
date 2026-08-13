class_name CardBurstData extends Resource
## A one-shot effect fired the moment a card is drafted, as opposed to the continuous
## stat modifiers in CardData.effects. Diamond cards are built from these.
##
## Same discriminated-union shape as InterventionData: `type` decides which fields
## below matter, and everything else stays at its default. Adding a new burst means
## adding a type string here plus one match arm in Game._execute_burst() — no new
## resource type, no change to ModifierManager (which only understands stats).

@export var type: String = "grant_dopamine"
## "grant_dopamine"  — dopamine
## "restore_focus"   — focus_amount / focus_percent
## "clear_tolerance" — wipes Tolerance and its floor
## "summon_allies"   — ally_* fields, spawned around the Focus core
## "damage_field"    — willpower_damage / awareness_damage to every live distraction
## "freeze_field"    — freeze_duration on every live distraction

@export_category("Type-specific: grant_dopamine")
@export var dopamine: int = 0

@export_category("Type-specific: restore_focus")
@export var focus_amount: int = 0
## Fraction of max Focus, added on top of focus_amount. 0.4 = +40% of the level's cap.
@export var focus_percent: float = 0.0

@export_category("Type-specific: summon_allies")
@export var ally_count: int = 0
@export var ally_health: int = 0
@export var ally_damage: int = 0
@export var ally_attack_cooldown: float = 1.0
@export var guard_radius: float = 240.0
## 0.0 means permanent — the difference between a Diamond card and Call a Friend (12).
@export var ally_lifetime: float = 0.0
## Ring radius the summoned Allies are placed on, around the Focus core.
@export var spawn_radius: float = 160.0

@export_category("Type-specific: damage_field / freeze_field")
@export var willpower_damage: int = 0
@export var awareness_damage: int = 0
@export var freeze_duration: float = 0.0
