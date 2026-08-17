class_name ArcProfile
extends RefCounted
## Everything the cone angle decides, in one place.
##
## The rule the whole habit roster now runs on: a habit generates a FIXED amount of
## energy per second. The cone angle (α) does not change how much — it changes how that
## energy is SHAPED in space. Narrow concentrates it into a line that punches through a
## queue; wide smears it into a wall that touches everything and stops none of it.
##
## Every derived value below is a ratio against the habit's OWN authored `arc_angle`,
## which is therefore its home setting: at α == α_default every multiplier is 1.0 and the
## tower behaves exactly as its .tres file says. That is what lets one curve serve a heavy
## cannon, a machine gun and a DoT sprayer without a per-habit special case — they differ
## only in where their home sits and in the base constants they bring to it.
##
## Recomputed only when the player changes the cone (Habit.set_arc_angle), never per shot:
## a tower firing ten times a second would otherwise allocate ten of these every second.

# ---------------------------------------------------------------- the tunable curve

## Player-settable range. Narrower than 15° stops reading as a cone at all (and the
## wedge preview degenerates into a line); wider than 120° starts wrapping around the
## tower's own footprint, where "which way does this thing face" stops being a decision.
const ARC_MIN := 15.0
const ARC_MAX := 120.0

## Damage exponent. Deliberately sub-linear: halving the cone must NOT double the damage,
## or narrow would simply be the correct answer everywhere and the dial would be fake.
const DMG_EXP := 0.7

## Rate exponent — "constant, or rising slightly with the angle". A wide fan fires a
## little faster so the wall of shots stays a wall instead of thinning into gaps the
## enemies walk through. Small on purpose; this is garnish, not the main trade.
const RATE_EXP := 0.25

## Hitbox exponent. Wide shots are fatter, which is what stops a spread fan from slipping
## between two enemies it visually covered. It is also the compensation for losing pierce.
const HIT_EXP := 0.5

## Ratio clamps, and the reason they exist: α_default is authored per habit and ranges
## 45°..120° across the roster, so an UNCLAMPED ratio would reach 8.0 on the widest habit
## and turn its narrow setting into a railgun with eight-body pierce, while the narrowest
## habit could never reach past 3.0 in the same direction. Clamping the ratio (rather than
## the angle) is what makes one curve behave the same way on every habit.
const RATIO_MIN := 0.4
const RATIO_MAX := 3.0

## Hit window at the home angle — this was Projectile.HIT_PADDING, now a starting point.
const BASE_HIT_PADDING := 16.0

## Line, bounded — the same principle the old fixed MAX_PIERCE carried. A narrow shot
## earns more of it; it never earns unlimited.
const MAX_PIERCE := 8

## Area, bounded — the AoE mirror of MAX_PIERCE, scaled by how wide the pulse is.
const AOE_BASE_TARGETS := 6
const AOE_MAX_TARGETS := 12

## Knockback pixels per hit per point of ratio above 1.0, times the habit's `impulse`.
## Only a cone NARROWER than home pushes: concentrated fire has somewhere to put the
## momentum. What stops this from pinning an enemy forever is the per-enemy budget in
## Distraction.apply_knockback(), not this number.
const KNOCKBACK_PX := 5.0

## Stagger, the wide-cone mirror: a shallow, short slow that a wall of shots keeps
## refreshing. Never deep enough to compete with a real Calm — apply_slow is
## strongest-wins, so a Mindfulness 0.5 simply ignores this.
const STAGGER_DEPTH := 0.12
const STAGGER_FLOOR := 0.75
const STAGGER_TIME := 0.25

## How many degrees of cone one firing lane covers. The fan is fired lane by lane rather
## than at a uniformly random angle inside the wedge, because random alone clumps — you
## get visible holes in the wall and three shots stacked on one line.
const LANE_DEG := 7.5
## Stride between consecutive lanes. Coprime with most lane counts, so the fan fills in
## a scattered order instead of sweeping left-to-right like a windscreen wiper.
const LANE_STRIDE := 3
## Fraction of a lane a shot may wander, so the fan reads as spray rather than a grid.
const LANE_JITTER := 0.45

# ---------------------------------------------------------------- computed per angle

## α_default / α. Above 1.0 = narrower than home (concentrated), below = wider (spread).
var ratio := 1.0
## α / α_default — the exact reciprocal of `ratio`, clamped alongside it so the two can
## never disagree about how far from home the cone is.
var spread := 1.0

var damage_mult := 1.0        ## multiplies the habit's live willpower/awareness damage
var rate_mult := 1.0          ## divides fire_cooldown — shots per second
var pierce := 1               ## bodies one shot passes through before it dies
var hit_padding := BASE_HIT_PADDING
var aoe_targets := AOE_BASE_TARGETS
var knockback := 0.0          ## px pushed back per hit; 0 = off
var stagger_factor := 1.0     ## move-speed multiplier applied on hit; 1.0 = off
var lanes := 1                ## firing lanes the cone is divided into

## Fills this profile in for one habit at one cone width. `def` may be any HabitData —
## a barracks (arc 0) or an Anchor (arc 360) never fires, but both can still reach here
## through a shared code path, so the home angle is clamped before it divides anything.
func recompute(def: HabitData, arc: float) -> void:
	var home: float = clampf(def.arc_angle, ARC_MIN, ARC_MAX)
	var live: float = clampf(arc, ARC_MIN, ARC_MAX)

	ratio = clampf(home / live, RATIO_MIN, RATIO_MAX)
	spread = 1.0 / ratio

	damage_mult = pow(ratio, DMG_EXP)
	rate_mult = pow(spread, RATE_EXP)
	pierce = clampi(roundi(float(def.base_pierce) * ratio), 1, MAX_PIERCE)
	hit_padding = BASE_HIT_PADDING * pow(spread, HIT_EXP)
	aoe_targets = clampi(roundi(float(AOE_BASE_TARGETS) * spread), 1, AOE_MAX_TARGETS)

	# The two halves of the physical response. They are mutually exclusive by
	# construction: a cone is either narrower than home or wider, never both, and at
	# home exactly it is neither — the tower is doing what its data says and nothing else.
	knockback = maxf(0.0, KNOCKBACK_PX * (ratio - 1.0) * def.impulse)
	stagger_factor = 1.0
	if spread > 1.0 and def.impulse > 0.0:
		stagger_factor = maxf(STAGGER_FLOOR,
			1.0 - STAGGER_DEPTH * (spread - 1.0) * def.impulse)

	lanes = maxi(1, roundi(live / LANE_DEG))

## Seconds between shots for a habit whose modifier-adjusted cooldown is `cooldown`.
func shot_interval(cooldown: float) -> float:
	return maxf(0.02, cooldown / rate_mult)

## `base` scaled by the angle, floored at 1 so a narrow-to-wide sweep can weaken a
## damage channel but never silently switch it off. A channel authored at 0 (Mindfulness
## deals no Willpower at all) stays 0 — off is off.
func scale_damage(base: int) -> int:
	if base <= 0:
		return 0
	return maxi(1, roundi(float(base) * damage_mult))

## Angle of the `i`-th shot inside the cone, in radians, given the cone's centre and
## width. `rng` supplies the sub-lane jitter; pass a habit's own RandomNumberGenerator so
## two towers side by side don't fire in lockstep.
func lane_angle(index: int, facing: float, arc: float, rng: RandomNumberGenerator) -> float:
	if lanes <= 1:
		return facing
	var lane: int = posmod(index * LANE_STRIDE, lanes)
	# Lane centres, so the outermost shots sit half a lane inside the wedge edge rather
	# than exactly on it — a shot on the boundary reads as leaking out of the preview.
	var t: float = (float(lane) + 0.5) / float(lanes) - 0.5
	t += rng.randf_range(-LANE_JITTER, LANE_JITTER) / float(lanes)
	return facing + deg_to_rad(arc) * t
