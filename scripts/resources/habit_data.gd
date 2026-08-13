class_name HabitData extends Resource
## Combat profile, upgrade path, and (optional, type-specific) mechanics for one habit
## (tower) type. Optional fields default to "off" (0 / false / empty) and are only read
## by the code paths that need them — see the "Type-specific" categories below.

@export_category("Identity")
@export var id: StringName = &"focus_timer"
@export var name: String = "Focus Timer"      ## Field name matches existing call sites (def.name).
@export var short: String = "Focus"
@export_multiline var description: String = "Rapid-fire Willpower."

@export_category("Construction")
@export var build_cost: int = 30
@export var upgrades: Array[StringName] = []       ## Next-tier HabitData ids.

@export_category("Combat")
@export var range: float = 360.0                   ## Attack reach — or Routine radius for support habits.
@export var arc_angle: float = 60.0                ## Initial cone width; re-aimable in play.
@export var willpower_damage: int = 3
@export var awareness_damage: int = 0
@export var fire_cooldown: float = 0.10
@export var aoe: bool = false                      ## false = directional shot, true = cone pulse.

## Derived, not authored: a habit with no damage, no AoE pulse and no allies is pure
## infrastructure (the Anchor line). Support habits skip aiming on build, never
## target or fire, and draw as a pylon whose range ring is their Routine radius.
func is_support() -> bool:
	return not is_blocker and not aoe and willpower_damage <= 0 and awareness_damage <= 0

@export_category("Type-specific: status effects (AoE habits only)")
@export var slow: float = 0.0
@export var slow_duration: float = 0.0
@export var reframe: int = 0
@export var reframe_duration: float = 0.0
@export var boredom: float = 0.0
@export var boredom_duration: float = 0.0

@export_category("Type-specific: work/rest cycle (Focus Timer only)")
@export var has_work_cycle: bool = false
@export var work_duration: float = 0.0
@export var break_short: float = 0.0               ## Player-chosen rest.
@export var break_long: float = 0.0                ## Forced burnout rest.

@export_category("Type-specific: barracks (Accountability only)")
@export var is_blocker: bool = false
@export var ally_count: int = 0
@export var ally_health: int = 0
@export var ally_damage: int = 0
@export var ally_attack_cooldown: float = 0.0
@export var ally_spawn_cooldown: float = 0.0
@export var guard_radius: float = 0.0

@export_category("Visuals")
@export var color: String = "4aa3ff"
@export var projectile_color: String = "9bd0ff"
