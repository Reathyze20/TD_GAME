extends Node
# Autoload "GameState": runtime state shared across scenes + change signals so
# the HUD can stay decoupled from gameplay. Reset at the start of each level.

signal dopamine_changed(value: int)
signal focus_changed(value: int, max_value: int)
signal wave_changed(value: int, max_value: int)
signal tolerance_changed(value: int)
signal selected_habit_changed(type_key)
signal kills_changed(value: int)
signal run_insight_changed(value: int)
## A defeat dropped Insight. Carries the position so the popup can appear on the corpse;
## the amount travels with it because the drop size is a rule, not a constant.
signal insight_dropped(at_position: Vector2, amount: int)
## How much Dopamine one defeat actually paid out, after tolerance scaling and card
## bonuses. Presentation-only: the floating "+N" popup needs the number, but the
## position comes from the defeated distraction itself, so game.gd buffers the two
## independently and flushes them together — neither handler depends on the other's
## ordering.
signal defeat_reward_granted(amount: int)

var current_level_index := 0

## True on runs launched from the map editor's Playtest button. Unlocks the F1–F4
## designer cheats in game.gd and disables telemetry, so runlog.csv only ever holds
## honest runs. Deliberately NOT cleared by reset_for_level — a designer restarting the
## same playtest stays in designer mode. The Menu clears it: that is the boundary where
## an editor playtest session ends and real runs begin.
var designer_mode := false

var dopamine := 0
var focus := 0
var max_focus := 0
var wave := 0
var max_wave := 0
var tolerance := 0.0
# Baseline Tolerance cannot decay below. Quick Hit spikes recover fully, but a
# two-sided card's tolerance_cost raises this floor for the rest of the level —
# downregulation as the real thing works: the baseline moves and stays moved.
var tolerance_floor := 0.0
var selected_habit = null  # String key or null
var quick_hit_enabled := false
var kills := 0

## Insight breakdown from the run that just ended, as returned by
## MetaProgression.bank_run(). Lives here rather than in game.gd because
## change_scene_to_file() frees the Game node before the end screen can read it.
## Deliberately NOT cleared by reset_for_level — the end screen runs after the level.
var last_run_insight: Dictionary = {}
## Run summary for the end screens: {stars, kills, waves_cleared, max_wave, focus,
## max_focus}. Written by game.gd right before the scene change, same lifecycle as
## last_run_insight — deliberately NOT cleared by reset_for_level.
var last_run_stats: Dictionary = {}

# ---------------------------------------------------------------- Insight economy
#
# Insight is earned DURING a run and spent two ways: on draft cards now, or banked into
# the Growth Tree after. That is the whole decision — a card bought is a permanent
# upgrade not bought — so it has to be a live, spendable number, not an end-of-run
# payout. Towers stay on Dopamine; the two currencies never overlap.

## Chance per defeat that a distraction drops Insight. Deliberately random rather than
## a flat per-kill trickle: variable-ratio reinforcement is one of the concepts this
## game teaches (see 00_overview), and the pull of "the next one might drop" is far
## better felt than described. ~910 kills clear level 1, so this pays about 45.
const INSIGHT_DROP_CHANCE := 0.05
const INSIGHT_DROP_AMOUNT := 1
## Guaranteed income per wave cleared. Without a floor the first draft (after ~103
## kills, so ~5 Insight expected) would be unaffordable and the mechanic would look
## broken exactly where the player first meets it.
const INSIGHT_PER_WAVE_CLEARED := 3

## Insight collected this run and not yet spent. Banked at the end, win or lose.
var run_insight := 0

func _ready() -> void:
	# GameState owns the economy and Focus rules, so it reacts to world events itself
	# rather than being driven imperatively by game.gd. Note this only covers events
	# that are already FACTS by the time they fire (something died, something got
	# through). Spending Dopamine to build stays imperative — that check has to be able
	# to abort the build, which a reaction cannot.
	SignalBus.distraction_defeated.connect(_on_distraction_defeated)
	SignalBus.distraction_escaped.connect(_on_distraction_escaped)
	SignalBus.wave_completed.connect(_on_wave_completed)

func reset_for_level(level: LevelData) -> void:
	dopamine = level.start_dopamine
	focus = level.focus
	max_focus = level.focus
	wave = 0
	max_wave = level.waves.size()
	tolerance = 0.0
	tolerance_floor = 0.0
	selected_habit = null
	quick_hit_enabled = level.quick_hit
	kills = 0
	lean_wave_active = false
	run_insight = 0
	run_insight_changed.emit(run_insight)
	dopamine_changed.emit(dopamine)
	focus_changed.emit(focus, max_focus)
	wave_changed.emit(wave, max_wave)
	tolerance_changed.emit(int(tolerance))
	selected_habit_changed.emit(selected_habit)
	kills_changed.emit(kills)

func can_afford(amount: int) -> bool:
	return dopamine >= amount

func add_dopamine(amount: int) -> void:
	dopamine += amount
	dopamine_changed.emit(dopamine)

func spend_dopamine(amount: int) -> bool:
	if dopamine < amount:
		return false
	dopamine -= amount
	dopamine_changed.emit(dopamine)
	return true

func lose_focus(amount: int) -> void:
	focus = max(0, focus - amount)
	focus_changed.emit(focus, max_focus)

## Heals Focus, capped at the level's maximum. Only a Breakthrough card does this today,
## which is the point: Focus is otherwise a one-way resource and getting some back has to
## feel like a genuine reprieve.
func restore_focus(amount: int) -> void:
	if amount <= 0:
		return
	focus = mini(max_focus, focus + amount)
	focus_changed.emit(focus, max_focus)

## Wipes Tolerance and the floor a two-sided card raised. Distinct from set_tolerance(0),
## which clamps back up to the floor and would therefore do nothing.
func clear_tolerance() -> void:
	tolerance_floor = 0.0
	set_tolerance(0.0)

func set_wave(value: int) -> void:
	wave = value
	wave_changed.emit(wave, max_wave)

func set_tolerance(value: float) -> void:
	tolerance = clampf(value, tolerance_floor, 100.0)
	tolerance_changed.emit(int(tolerance))

## Permanently raises the level's baseline Tolerance (a two-sided card's cost).
func raise_tolerance_floor(amount: float) -> void:
	tolerance_floor = clampf(tolerance_floor + amount, 0.0, 100.0)
	set_tolerance(maxf(tolerance, tolerance_floor))

func add_kill() -> void:
	kills += 1
	kills_changed.emit(kills)

func add_run_insight(amount: int) -> void:
	if amount == 0:
		return
	run_insight = maxi(0, run_insight + amount)
	run_insight_changed.emit(run_insight)

## Spends banked run Insight. Returns false and changes nothing if it can't be afforded,
## so the draft can gate a pick on the return value.
func spend_insight(amount: int) -> bool:
	if amount > run_insight:
		return false
	run_insight -= amount
	run_insight_changed.emit(run_insight)
	return true

func can_afford_insight(amount: int) -> bool:
	return run_insight >= amount

# ---------------------------------------------------------------- bus reactions

## True while a "lean wave" runs: defeats pay NO Dopamine — the feed that gives nothing
## back. Set/cleared by game.gd from LevelData.lean_waves. Insight drops still roll:
## the learning still pays even when the feed doesn't.
var lean_wave_active := false

## Downregulation made mechanical: the higher your Tolerance, the less every defeat
## pays. Card/Growth `dopamine_bonus` is applied on top, and the total is floored at 1 —
## without that floor a negative bonus would drain Dopamine on a kill and print "+-1".
func _on_distraction_defeated(d: Node2D, base_reward: int) -> void:
	if lean_wave_active:
		add_kill()
		defeat_reward_granted.emit(0)
		if randf() < INSIGHT_DROP_CHANCE:
			add_run_insight(INSIGHT_DROP_AMOUNT)
			if is_instance_valid(d):
				insight_dropped.emit(d.global_position, INSIGHT_DROP_AMOUNT)
		return
	var ratio: float = tolerance / 100.0
	var reward: int = maxi(1, int(round(base_reward * (1.0 - 0.6 * ratio))))
	var bonus: int = int(ModifierManager.get_modified_stat(0.0, ModifierManager.STAT_DOPAMINE_BONUS))
	reward = maxi(1, reward + bonus)
	add_dopamine(reward)
	add_kill()
	defeat_reward_granted.emit(reward)

	# The Insight drop. Rolled per defeat and independent of the Dopamine reward: one is
	# the fast currency that gets spent immediately, the other the slow one that
	# accumulates into something permanent. That contrast IS the lesson.
	if randf() < INSIGHT_DROP_CHANCE:
		add_run_insight(INSIGHT_DROP_AMOUNT)
		if is_instance_valid(d):
			insight_dropped.emit(d.global_position, INSIGHT_DROP_AMOUNT)

func _on_wave_completed(_wave_number: int) -> void:
	add_run_insight(INSIGHT_PER_WAVE_CLEARED)

func _on_distraction_escaped(focus_damage: int) -> void:
	lose_focus(focus_damage)
	if focus <= 0:
		SignalBus.game_over.emit(false)

func select_habit(type_key) -> void:
	selected_habit = type_key
	selected_habit_changed.emit(selected_habit)
