class_name SimStrategyCounterPick
extends SimStrategy
## Builds the most expensive attack habit it can afford at every buildable spot and aims
## each one back down the lane the distractions come from. The "plays reasonably" baseline
## (M1, PATHFINDING.MD) — added because the four strategies that existed could not tell
## two very different findings apart.
##
## WHY THIS EXISTS. S3's three baselines and Q2's fourth all share two blind spots that are
## deliberate in each of them individually and fatal in aggregate: every one of them builds
## `focus_timer` or nothing, and not one of them ever aims. Measured in docs/BALANCE.md §3,
## `focus_timer` does 3 Willpower against `doomscroll`'s 4 Compulsion, i.e. it lands on
## take_damage()'s floor of 1 and needs 40 shots (4.0 s of unbroken fire) per kill, while
## `exercise` — whose own description says "Built for tanky distractions like Doomscroll" —
## needs 2 shots. A sweep in which every strategy loses therefore does NOT establish that a
## level is unwinnable; it is equally consistent with "no baseline ever builds the counter."
## Those two readings call for opposite repairs, so the diagnosis needs a strategy that
## makes the obvious plays before anyone edits balance numbers.
##
## Not an attempt at optimal play either, and it must not become one: it makes exactly the
## two decisions a first-time player makes without being taught (buy the better tower when
## the money is there, point it at where the enemies come from) so that the gap between it
## and `cheap_even` measures those two decisions and nothing else.

## Most expensive first. The order is the whole strategy: take the best affordable thing.
## Support/blocker types are left out on purpose — an Anchor extends the Routine rather
## than killing anything, and mixing that in would blur what this baseline measures.
const PREFERENCE: Array[StringName] = [&"exercise", &"mindfulness", &"focus_timer"]

var _aimed: Dictionary = {}   # BaseHabit instance id -> true, so each is aimed once


func on_build_tick(sim: LevelSimulator) -> void:
	for cell in sim.buildable_cells():
		var pick := _affordable_pick()
		if pick == &"":
			break
		var habit := sim.build(cell, String(pick))
		if habit != null and is_instance_valid(habit):
			_aim_down_the_lane(sim, habit)
	sim.start_wave()


func _affordable_pick() -> StringName:
	for id in PREFERENCE:
		var def: HabitData = Data.get_habit(id)
		if def != null and GameState.dopamine >= def.build_cost \
				and GameState.can_reserve_bandwidth(def.bandwidth_cost):
			return id
	return &""


## Points the habit at the centre of the level's first spawn zone, keeping its own default
## cone width. Facing is the only variable changed: arc width feeds ArcProfile's damage
## shaping, so widening it would silently trade damage for coverage and stop this from
## being a clean two-decision comparison against `cheap_even`.
##
## Default facing is 0 rad — due EAST — while every level in the project spawns on the WEST
## edge and walks toward a core on the east side. An unaimed habit therefore spends the
## approach with its cone pointed away from the horde and only engages what has already
## passed it, which is most of the difference this baseline is here to measure.
func _aim_down_the_lane(sim: LevelSimulator, habit: BaseHabit) -> void:
	var key := habit.get_instance_id()
	if _aimed.has(key):
		return
	_aimed[key] = true
	var level: LevelData = sim.game.level
	if level == null or level.spawn_zones.is_empty():
		return
	var z: Rect2i = level.spawn_zones[0]
	var mid := Vector2i(z.position.x + z.size.x / 2, z.position.y + z.size.y / 2)
	var target: Vector2 = Data.cell_center(mid)
	var facing_deg: float = rad_to_deg((target - habit.position).angle())
	sim.aim(habit as Habit, facing_deg, habit.def.arc_angle)
