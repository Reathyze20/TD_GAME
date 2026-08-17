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
## "damage_aoe" | "freeze_aoe" | "summon_allies" | "freeze_field" | "reveal_field"
## "freeze_field" and "reveal_field" ignore `radius` and take the whole field; neither
## is targeted.
@export var type: String = "damage_aoe"
@export var cooldown: float = 18.0
@export var radius: float = 180.0
## Rush charged per cast, on top of the cooldown. Defaults to 0 so the three original
## interventions — which author almost nothing and inherit the rest of this file — stay
## free; only an ability that opts in costs anything.
@export var rush_cost: int = 0
## Run-Insight charged per cast, same double-gate contract as rush_cost (checked at arm
## AND at cast, refused cast leaves the cooldown untouched). A separate field rather
## than a generic cost type because the two currencies teach different lessons — Rush is
## a receipt for risk, Insight is understanding spent for immediate advantage.
@export var insight_cost: int = 0

@export_category("Type-specific: damage_aoe")
@export var willpower_damage: int = 0
@export var awareness_damage: int = 0

@export_category("Type-specific: freeze_aoe")
@export var freeze_duration: float = 0.0

@export_category("Type-specific: reveal_field")
## Seconds the Brain Fog lifts off the whole field (Game.fog_reveal_left).
@export var reveal_duration: float = 0.0

@export_category("Type-specific: summon_allies")
@export var ally_count: int = 0
@export var ally_health: int = 0
@export var ally_damage: int = 0
@export var ally_attack_cooldown: float = 0.0
@export var ally_lifetime: float = 0.0
@export var guard_radius: float = 0.0

@export_category("Visuals")
@export var color: String = "ff5566"
