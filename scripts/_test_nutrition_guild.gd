extends Node
## Harness for the Nutrition Guild rework: the three-slot recipe, respawn-as-current-
## slot-type, weighted blocking, the leash, the heal aura and the searing DoT.
##
## Same shape as _test_zen_pulsar.gd — instantiate the real Game, pin Focus so a leak
## cannot trip _game_over(), then drive the systems imperatively.
##
## Every check is a rule invisible in a playtest: a slot swap that executes the live
## veteran instead of waiting, a pin that leaks capacity, a berserker that quietly
## body-blocks the boss it was never meant to stop, an aura that heals its own caster
## into a second tank. The numbers are the design, so the numbers get a test.

var completed := false
var fails := 0

func _ready() -> void:
	var wd := Timer.new()
	wd.wait_time = 90.0
	wd.one_shot = true
	add_child(wd)
	wd.timeout.connect(func():
		if not completed:
			print("FAILED: watchdog fired")
			get_tree().quit(1))
	wd.start()
	call_deferred("_run")

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok   %s %s" % [label, detail])
	else:
		fails += 1
		print("  FAIL %s %s" % [label, detail])

func _run() -> void:
	_test_data()

	var game: Game = load("res://scenes/Game.tscn").instantiate()
	add_child(game)
	# Milestone isolation: this harness predates the Brain Fog and the Routine build
	# gate and exercises OTHER systems — both new gates are switched off wholesale.
	# Their own coverage lives in _test_fog_bandwidth.gd.
	game.fog_enabled = false
	game.routine_gates_enabled = false
	await get_tree().process_frame
	GameState.max_focus = 999999
	GameState.focus = 999999
	GameState.dopamine = 999999
	game.started = true
	game.between_waves = false

	var guild := _build_guild(game)
	if guild == null:
		_check("a guild could be built", false)
		return _finish()

	await _test_recipe_and_respawn(game, guild)
	await _test_weighted_blocking(game, guild)
	await _test_leash(game, guild)
	await _test_heal_aura(game, guild)
	await _test_burn(game, guild)
	await _test_ward(game, guild)
	_test_summons_still_work(game)

	_finish()

func _finish() -> void:
	completed = true
	print("")
	if fails == 0:
		print("ALL PASS")
		get_tree().quit(0)
	else:
		print("%d FAILED" % fails)
		get_tree().quit(1)

# ---------------------------------------------------------------- data wiring

func _test_data() -> void:
	print("=== the roster loads and the three roles actually differ")
	var b := Data.get_defender(&"broccoli_knight")
	var a := Data.get_defender(&"avocado_monk")
	var c := Data.get_defender(&"chilli_berserker")
	_check("all three defenders load", b != null and a != null and c != null)
	if b == null or a == null or c == null:
		return
	_check("tank pins the most, striker the least",
		b.block_capacity > a.block_capacity and a.block_capacity > c.block_capacity,
		"(%d/%d/%d)" % [b.block_capacity, a.block_capacity, c.block_capacity])
	_check("tank is the only one that soaks", b.damage_reduction > 0
		and a.damage_reduction == 0 and c.damage_reduction == 0)
	_check("monk is the only healer", a.heal_amount > 0
		and b.heal_amount == 0 and c.heal_amount == 0)
	_check("berserker is the only burner", c.burn_dps > 0.0
		and b.burn_dps == 0.0 and a.burn_dps == 0.0)
	_check("berserker swings fastest for the least",
		c.attack_cooldown < a.attack_cooldown and c.max_health < a.max_health)
	var heavy := Data.get_distraction(&"doomscroll")
	_check("a heavy costs more capacity than a light", heavy != null
		and heavy.block_weight > 1 and Data.get_distraction(&"notification").block_weight == 1)
	_check("the boss outweighs even one tank slot short",
		Data.get_distraction(&"social_media_binge").block_weight == b.block_capacity)

func _build_guild(game: Game) -> Barracks:
	for cell in game.build_spots:
		var bs: BuildSpot = game.build_spots[cell]
		if bs.state == BuildSpot.State.EMPTY:
			return bs.build_habit("accountability") as Barracks
	return null

# ---------------------------------------------------------------- slots / respawn

func _test_recipe_and_respawn(game: Game, guild: Barracks) -> void:
	print("=== the recipe: a slot change waits for the death it re-provisions")
	_check("guild fields the default recipe at once", guild.owned_allies.size() == 3,
		"(%d live)" % guild.owned_allies.size())
	_check("one of each by default",
		guild.slots[0] == &"broccoli_knight" and guild.slots[1] == &"avocado_monk"
			and guild.slots[2] == &"chilli_berserker")

	var veteran = guild._slot_units[0]
	guild.cycle_slot(0)   # broccoli -> avocado
	_check("cycling the slot does NOT touch the live unit",
		is_instance_valid(veteran) and veteran.type_key == &"broccoli_knight")
	_check("but the panel knows a swap is pending", guild.slot_pending_change(0))

	veteran.take_damage(999999)
	await get_tree().process_frame
	_check("death starts the slot clock", guild._slot_timers[0] > 0.0,
		"(%.1fs)" % guild._slot_timers[0])
	for i in range(45):
		guild._process(0.1)
	await get_tree().process_frame
	var replacement = guild._slot_units[0]
	_check("the replacement is the NEW type", replacement != null
		and is_instance_valid(replacement) and replacement.type_key == &"avocado_monk")
	guild.cycle_slot(0)
	guild.cycle_slot(0)
	guild.cycle_slot(0)   # avocado -> chilli -> garlic -> broccoli: the full four-type wrap
	_check("cycle wraps the whole roster (garlic included)",
		guild.slots[0] == &"broccoli_knight", "(%s)" % guild.slots[0])

# ---------------------------------------------------------------- blocking maths

func _spawn_at(game: Game, key: StringName, pos: Vector2) -> Distraction:
	var d := game.spawn_distraction(key, game.world_to_cell(pos))
	d.position = pos
	return d

func _test_weighted_blocking(game: Game, guild: Barracks) -> void:
	print("=== weight: the tank stops what the striker can only chase")
	# A quiet corner far from the guild's own units so they don't join in.
	var corner: Vector2 = game.cell_center(game.objective_cell) + Vector2(-60, -60)

	var tank := DefenderUnit.new()
	tank.setup_from_data(game, Data.get_defender(&"broccoli_knight"),
		corner, Vector2.ZERO, 240.0)
	game.entities.add_child(tank)
	tank.global_position = corner

	var lights: Array = []
	for i in range(3):
		lights.append(_spawn_at(game, &"notification", corner + Vector2(20 + i * 8, 0)))
	for i in range(3):
		var l = lights[i]
		tank._execute_clash(l)
	_check("capacity 3 pins three lights",
		lights.all(func(l): return l.is_blocked), "(weight %d/3)" % tank._pinned_weight())

	var heavy := _spawn_at(game, &"doomscroll", corner + Vector2(0, 30))
	tank._execute_clash(heavy)
	_check("a full tank cannot ALSO pin the heavy", not heavy.is_blocked,
		"(weight %d, needs +%d)" % [tank._pinned_weight(), heavy.def.block_weight])

	var chilli := DefenderUnit.new()
	chilli.setup_from_data(game, Data.get_defender(&"chilli_berserker"),
		corner, Vector2.ZERO, 240.0)
	game.entities.add_child(chilli)
	chilli.global_position = heavy.global_position + Vector2(10, 0)
	chilli._execute_clash(heavy)
	_check("the striker cannot pin the heavy either", not heavy.is_blocked)
	_check("but it fights it anyway", chilli.state == DefenderUnit.State.ATTACK
		and chilli.engaged_target == heavy)

	# Free the pins, then check a lone tank CAN pin the heavy — capacity was the issue.
	for l in lights:
		l.take_direct_damage(999999)
	await get_tree().process_frame
	tank._prune_pins()
	tank._execute_clash(heavy)
	_check("an empty tank pins the heavy fine", heavy.is_blocked,
		"(weight %d/%d)" % [tank._pinned_weight(), tank.block_capacity])

	heavy.take_direct_damage(999999)
	tank.queue_free()
	chilli.queue_free()
	await get_tree().process_frame

func _test_leash(game: Game, guild: Barracks) -> void:
	print("=== the leash measures from the rally, and it lets go")
	var corner: Vector2 = game.cell_center(game.objective_cell) + Vector2(80, -60)
	var unit := DefenderUnit.new()
	unit.setup_from_data(game, Data.get_defender(&"chilli_berserker"),
		corner, Vector2.ZERO, 100.0)   # tight leash for the test
	game.entities.add_child(unit)
	unit.global_position = corner
	unit.state = DefenderUnit.State.IDLE

	var prey := _spawn_at(game, &"notification", corner + Vector2(60, 0))
	unit._process(0.016)
	_check("it takes a target inside the zone", unit.engaged_target == prey)

	prey.position = corner + Vector2(300, 0)   # towed out past the 100px leash
	unit._process(0.016)
	_check("target out of zone is dropped, unit heads home",
		unit.engaged_target == null and unit.state == DefenderUnit.State.MOVE_TO_RALLY)

	prey.take_direct_damage(999999)
	unit.queue_free()
	await get_tree().process_frame

# ---------------------------------------------------------------- abilities

func _test_heal_aura(game: Game, guild: Barracks) -> void:
	print("=== the monk mends everyone but itself")
	var corner: Vector2 = game.cell_center(game.objective_cell) + Vector2(-80, 60)
	var monk := DefenderUnit.new()
	monk.setup_from_data(game, Data.get_defender(&"avocado_monk"), corner, Vector2.ZERO, 240.0)
	game.entities.add_child(monk)
	monk.global_position = corner
	var buddy := DefenderUnit.new()
	buddy.setup_from_data(game, Data.get_defender(&"broccoli_knight"),
		corner, Vector2(20, 0), 240.0)
	game.entities.add_child(buddy)
	buddy.global_position = corner + Vector2(20, 0)

	monk.current_health = 10
	buddy.current_health = 10
	var monk_hp: int = monk.current_health
	var buddy_hp: int = buddy.current_health
	monk._heal_timer = 0.0
	monk._tick_heal_aura(0.016)
	_check("the neighbour is healed", buddy.current_health > buddy_hp,
		"(+%d)" % (buddy.current_health - buddy_hp))
	_check("the monk itself is not", monk.current_health == monk_hp)

	var far := DefenderUnit.new()
	far.setup_from_data(game, Data.get_defender(&"broccoli_knight"),
		corner + Vector2(300, 0), Vector2.ZERO, 240.0)
	game.entities.add_child(far)
	far.global_position = corner + Vector2(300, 0)
	far.current_health = 10
	monk._heal_timer = 0.0
	monk._tick_heal_aura(0.016)
	_check("out of radius means out of the aura", far.current_health == 10)

	monk.queue_free()
	buddy.queue_free()
	far.queue_free()
	await get_tree().process_frame

func _test_burn(game: Game, guild: Barracks) -> void:
	print("=== the berserker's hits keep searing after they land")
	var corner: Vector2 = game.cell_center(game.objective_cell) + Vector2(120, 60)
	var chilli := DefenderUnit.new()
	chilli.setup_from_data(game, Data.get_defender(&"chilli_berserker"),
		corner, Vector2.ZERO, 240.0)
	game.entities.add_child(chilli)
	chilli.global_position = corner

	var victim := _spawn_at(game, &"doomscroll", corner + Vector2(10, 0))
	victim.current_health = 99999
	chilli.engaged_target = victim
	chilli.state = DefenderUnit.State.ATTACK
	chilli.attack_timer = 0.0
	chilli._process_melee(0.016)
	_check("the DoT landed with the hit", victim.status_manager.has_boredom(),
		"(%.1f/s)" % victim.status_manager.boredom_dps)
	var hp: int = victim.current_health
	victim.status_manager.tick(1.05)
	_check("and it burns on its own clock", victim.current_health < hp,
		"(-%d)" % (hp - victim.current_health))

	victim.take_direct_damage(999999)
	chilli.queue_free()
	await get_tree().process_frame

func _test_ward(game: Game, guild: Barracks) -> void:
	print("=== the garlic ward slows the reek's whole radius, softly")
	var corner: Vector2 = game.cell_center(game.objective_cell) + Vector2(-140, -20)
	var mage := DefenderUnit.new()
	mage.setup_from_data(game, Data.get_defender(&"garlic_mage"), corner, Vector2.ZERO, 240.0)
	game.entities.add_child(mage)
	mage.global_position = corner

	var near := _spawn_at(game, &"notification", corner + Vector2(40, 0))
	var far := _spawn_at(game, &"notification", corner + Vector2(400, 0))
	mage._ward_timer = 0.0
	mage._tick_ward(0.016)
	_check("inside the reek: slowed", near.status_manager.has_slow(),
		"(x%.2f)" % near.status_manager.slow_factor)
	_check("outside it: untouched", not far.status_manager.has_slow())
	# Strongest-wins guarantee: a real Calm must shrug the ward off, not be diluted.
	near.apply_slow(0.5, 1.0)
	mage._ward_timer = 0.0
	mage._tick_ward(0.016)
	_check("a real Calm overrides the ward", is_equal_approx(near.status_manager.slow_factor, 0.5),
		"(x%.2f)" % near.status_manager.slow_factor)

	near.take_direct_damage(999999)
	far.take_direct_damage(999999)
	mage.queue_free()
	await get_tree().process_frame

## The raw-summon path (Call a Friend, card bursts) rode on the old Ally.setup — the
## rename must not have cost interventions their soldiers.
func _test_summons_still_work(game: Game) -> void:
	print("=== raw summons survived the Ally -> DefenderUnit rename")
	var u := DefenderUnit.new()
	game.entities.add_child(u)
	u.setup(game, game.cell_center(game.objective_cell), 30, 5, 0.6, 240.0, 8.0)
	_check("raw setup yields a live temporary", is_instance_valid(u)
		and u.max_health == 30 and u.lifetime == 8.0 and u.block_capacity == 1)
	u.queue_free()
