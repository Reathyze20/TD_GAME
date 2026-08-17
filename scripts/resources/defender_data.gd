class_name DefenderData extends Resource
## One Nutrition Guild defender type (Broccoli Knight / Avocado Monk / Chilli Berserker).
## The guild's three slots each hold one of these ids; the unit itself is always the same
## DefenderUnit scene-less node, shaped entirely by this resource — the same pattern as
## HabitData/DistractionData, and for the same reason: a roster grows by adding a .tres,
## not a subclass.

@export_category("Identity")
@export var id: StringName = &"broccoli_knight"
@export var display_name: String = "Broccoli Knight"
## One word the slot button leads with — the player reads the ROLE first, the vegetable
## second ("Tank — Broccoli Knight"). Roles are what the recipe is built from.
@export var role: String = "Tank"
@export_multiline var description: String = "Holds the line."

@export_category("Combat")
@export var max_health: int = 60
@export var damage: int = 6
@export var attack_cooldown: float = 0.7
## Flat damage soaked off every melee counter-hit (floor 1 still lands). The Broccoli
## Knight's whole identity: same counter-punches, smaller bites.
@export var damage_reduction: int = 0

@export_category("Blocking")
## Total block weight this unit can pin at once. A distraction costs its own
## `block_weight` (1 light, heavier for tanks/bosses) — so 3 here means "three lights or
## one weight-3 boss". A unit whose REMAINING capacity is under a target's weight still
## fights it, it just cannot stop it walking — the striker harasses, the tank stops.
@export var block_capacity: int = 1

@export_category("Movement")
@export var move_speed: float = 90.0      ## walk to the rally formation — no hurry
## Closing speed on a target. Must beat the fastest ground distraction (notification,
## 140 px/s) or the chase never resolves — see the old Ally CHASE_SPEED note.
@export var chase_speed: float = 200.0

@export_category("Type-specific: regeneration aura (Avocado Monk)")
## Heals every OTHER defender inside `heal_radius` by `heal_amount` each `heal_interval`
## seconds. Deliberately not itself: a support that self-sustains becomes the tank, and
## the guild's three roles collapse into one best pick. 0 amount = no aura.
@export var heal_amount: int = 0
@export var heal_interval: float = 1.0
@export var heal_radius: float = 0.0

@export_category("Type-specific: burning strikes (Chilli Berserker)")
## Damage-over-time left on everything this unit hits — routed through the game's one
## DoT channel (Boredom), so it bypasses both resistances and stacks per-source like
## every other DoT in the game. Thematically it burns; mechanically the pipes are shared.
@export var burn_dps: float = 0.0
@export var burn_duration: float = 0.0

@export_category("Type-specific: pungent ward (Garlic Mage)")
## Every `ward_interval` seconds, every distraction within `ward_radius` is slowed to
## `ward_slow_factor` for `ward_duration`. Routed through apply_slow, where strongest
## wins — so the ward is a floor under the fight, never a competitor to a real Calm
## habit (a Mindfulness 0.5 simply overrides this 0.8). 1.0 factor = no ward.
@export var ward_slow_factor: float = 1.0
@export var ward_duration: float = 0.0
@export var ward_interval: float = 0.5
@export var ward_radius: float = 0.0

@export_category("Visuals")
@export var color: String = "7cffb2"     ## fallback body + health bar tint, no leading '#'
