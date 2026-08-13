class_name InterventionData extends Resource
## One active player ability. `type` picks which fields matter: "damage_aoe" reads the
## damage fields, "freeze_aoe" reads freeze_duration, "summon_allies" reads the ally_*
## fields (the same shape Barracks/Accountability uses, so Ally.setup() can take either).

@export_category("Identity")
@export var id: StringName = &"screen_break"
@export var name: String = "Screen Break"     ## Field name matches existing call sites (idef.name).
@export var short: String = "Break"
@export_multiline var description: String = "Conscious pause."

@export_category("Stats")
@export var type: String = "damage_aoe"      ## "damage_aoe" | "freeze_aoe" | "summon_allies"
@export var cooldown: float = 18.0
@export var radius: float = 180.0

@export_category("Type-specific: damage_aoe")
@export var willpower_damage: int = 0
@export var awareness_damage: int = 0

@export_category("Type-specific: freeze_aoe")
@export var freeze_duration: float = 0.0

@export_category("Type-specific: summon_allies")
@export var ally_count: int = 0
@export var ally_health: int = 0
@export var ally_damage: int = 0
@export var ally_attack_cooldown: float = 0.0
@export var ally_lifetime: float = 0.0
@export var guard_radius: float = 0.0

@export_category("Visuals")
@export var color: String = "ff5566"
