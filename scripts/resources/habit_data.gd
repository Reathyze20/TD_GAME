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

## Attention Bandwidth this habit OCCUPIES while it stands. Reserved on build, the
## delta charged on upgrade, released in full on sell. Unlike Dopamine it is never
## consumed — it counts commitments currently held, so the number on the HUD can only
## move when the player builds or lets go of something. See GameState's bandwidth block
## for why that distinction is load-bearing.
@export var bandwidth_cost: int = 10

@export_category("Combat")
@export var range: float = 360.0                   ## Attack reach — or Routine radius for support habits.
@export var arc_angle: float = 60.0                ## Initial cone width; re-aimable in play.
@export var willpower_damage: int = 3
@export var awareness_damage: int = 0
@export var fire_cooldown: float = 0.10
@export var aoe: bool = false                      ## false = directional shot, true = cone pulse.

## Bodies one shot passes through at this habit's HOME cone angle (`arc_angle`). Narrowing
## the cone multiplies it, widening divides it down to 1 — see ArcProfile. This is the
## per-weapon character knob: a heavy cannon is authored with more base pierce than a
## sprayer, so "narrow it into a corridor" pays off differently on each.
@export var base_pierce: int = 2

## How hard this weapon shoves. Scales BOTH halves of the physical response — knockback
## when the cone is narrower than home, stagger when it is wider. 0.0 turns the whole
## thing off for weapons with no business pushing anything (a beam of attention does not
## have momentum); 2.0 is a habit whose identity is the impact.
@export var impulse: float = 1.0

## Whether the head SPRITE rotates to follow the barrel. Shots always fly along `_aim`
## either way — this is purely how the tower reads.
##
## A turret should swing to face its target; a book should not. The Tome is drawn in
## isometric 3/4, and GPU-rotating that through 360° spins it like a plate instead of
## aiming it. Pages flying out of a book that stays open is the readable version of the
## same act. AoE heads already never rotate, so this only concerns directional habits.
@export var head_aims: bool = true

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

## Hard stun: freeze the target outright for this long. A SEPARATE field from `slow`
## rather than "slow = 0.0", because every optional field here reads 0.0 as OFF — a full
## freeze and an absent effect would be the same authored value and the pulse could never
## tell them apart. Pierces slow_immune (Overdrive), by StatusManager's own rule that
## "ignores slows" and "cannot be stopped" are different promises.
@export var stun_duration: float = 0.0

## Wipe the target's Rush on hit — the Zen Pulsar's momentum reset. An energised
## distraction loses the aura outright and has to wait for the next enemy pulse to get it
## back. Leaves Overdrive alone; see StatusManager.clear_haste().
@export var dispel_haste: bool = false

## Vulnerability: the target takes this much more habit damage for `vulnerable_duration`.
## 1.0 = off. Applied AFTER the pulse's own damage in the AoE loop, so the habit that
## opens the target does not also cash in on it — this buys damage for everyone ELSE.
@export var vulnerable_mult: float = 1.0
@export var vulnerable_duration: float = 0.0

## Drive the head animation off the reload instead of wall time, so the sprite IS the
## countdown: frame 1 on the shot, last frame as it comes off cooldown. Only worth it on
## slow, telegraphed habits — a fast one would just strobe.
@export var charge_telegraph: bool = false

@export_category("Type-specific: work/rest cycle (Focus Timer only)")
@export var has_work_cycle: bool = false
@export var work_duration: float = 0.0
@export var break_short: float = 0.0               ## Player-chosen rest.
@export var break_long: float = 0.0                ## Forced burnout rest.

@export_category("Type-specific: barracks (Nutrition Guild only)")
@export var is_blocker: bool = false
## Seconds a fallen slot waits before its defender walks out again. Unit STATS live on
## DefenderData (data/defenders/) — the guild only owns the recipe, the respawn clock,
## and the tier scaling below. The old per-tower ally_health/damage fields died with
## the single generic Ally; a tier upgrade now scales the whole roster instead.
@export var ally_spawn_cooldown: float = 4.0
@export var guard_radius: float = 240.0            ## Leash radius, measured from the rally point.
@export var defender_hp_mult: float = 1.0          ## Tier scaling on every defender's max HP.
@export var defender_damage_mult: float = 1.0      ## Tier scaling on every defender's damage.

@export_category("Visuals")
@export var color: String = "4aa3ff"
@export var projectile_color: String = "9bd0ff"

## Radians/sec the shot tumbles. 0 = the default energy bolt. Nonzero draws it as a flat
## sheet turning end over end — Deep Reading fires torn pages, not plasma.
@export var projectile_spin: float = 0.0
