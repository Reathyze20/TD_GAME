extends Node
# Autoload "GameState": runtime state shared across scenes + change signals so
# the HUD can stay decoupled from gameplay. Reset at the start of each level.

signal dopamine_changed(value: int)
signal focus_changed(value: int, max_value: int)
signal wave_changed(value: int, max_value: int)
signal tolerance_changed(value: int)
signal burnout_changed(value: float)
signal selected_habit_changed(type_key)
signal kills_changed(value: int)
signal run_insight_changed(value: int)
signal rush_changed(value: int)
## A defeat dropped Insight. Carries the position so the popup can appear on the corpse;
## the amount travels with it because the drop size is a rule, not a constant.
signal insight_dropped(at_position: Vector2, amount: int)
signal bandwidth_changed(used: int, max_value: int)
## How much Dopamine one defeat actually paid out, after tolerance scaling and card
## bonuses. Presentation-only: the floating "+N" popup needs the number, but the
## position comes from the defeated distraction itself, so game.gd buffers the two
## independently and flushes them together — neither handler depends on the other's
## ordering.
signal defeat_reward_granted(amount: int)
## Wanting and liking, emitted separately because they are separately true. See the
## `craving` / `satisfaction` docs below.
## The streak and the multiplier it is currently worth, together — the HUD needs both
## and computing the second from the first at the call site would let them drift.
signal streak_changed(value: int, multiplier: float)
signal craving_changed(value: float)
signal satisfaction_changed(value: float)

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
## Accumulated strain from leaks, 0-100. The second half of the "you are losing" story and
## deliberately NOT folded into Tolerance: Tolerance is the price of TAKING rewards
## (downregulation), Burnout is the price of LETTING THINGS THROUGH. They rise from
## different mistakes, so one number could not teach either.
##
## It reads back into the field rather than just into the scoreboard — above the strain
## threshold the screen shakes, above the failure threshold habits start dropping ticks
## (game.gd:_update_burnout). Leaks therefore compound, which is exactly how attention
## debt behaves: the tireder you are, the more gets through.
var burnout := 0.0
var selected_habit = null  # String key or null
var quick_hit_enabled := false
var kills := 0

# ---------------------------------------------------------------- wanting vs liking
#
# Berridge's split, made mechanical. Dopamine drives WANTING; liking is a different
# system, and in a downregulated brain the two come apart — you can want something
# badly that gives you nothing. One meter could not show that, because the whole
# finding IS the gap between two lines.
#
# Craving is deliberately USEFUL (game.gd turns it into fire rate). It has to be: a
# stat that only ever punished would be a morality bar, and the player would route
# around it instead of feeling the trade. The trap is that it works.

## Wanting, 0-100. Rises from cheap sources (Quick Hit, ads, frantic clicking), decays
## during clean play. Drives urgency: faster habits, louder UI, unbearable downtime.
var craving := 0.0
## Liking, 0-100, starts full. Falls when reward is taken cheaply or leaks through,
## recovers from waves cleared on their own merits. Drives the music: a level won at
## low Satisfaction ends in near-silence, which is the whole thesis in one sensation.
var satisfaction := 100.0

const CRAVING_DECAY_PER_WAVE := 8.0
const SATISFACTION_PER_CLEAN_WAVE := 6.0
const SATISFACTION_PER_QUICK_HIT := -9.0
const SATISFACTION_PER_LEAK := -4.0

# ---------------------------------------------------------------- novelty (RPE)
#
# Reward prediction error, the half of dopamine a Tolerance meter cannot express.
# Schultz: a fully predicted reward produces NO response; novelty restores it. So the
# juice of a defeat is not just "how downregulated am I" but "did I see this coming".
#
# Familiarity is counted per killing habit. That is what turns the science into a
# DECISION: upgrading the tower that already works is strategically correct and
# progressively duller, while building a new one feels alive and is weaker. The pull
# toward the new button, against your own interest, is the lesson — and no card has to
# say it out loud.

## habit id -> how many defeats it has been credited with this level.
var _familiarity: Dictionary = {}
## Kills by one habit before its surprise bottoms out.
const FAMILIARITY_FULL := 18.0
## Floor on surprise, so a veteran tower still reads as a kill rather than as silence.
const SURPRISE_FLOOR := 0.25

## How surprising one more defeat by `key` would be, 1.0 (never seen) → SURPRISE_FLOOR.
func surprise_of(key: StringName) -> float:
	if key == &"":
		return 1.0
	var seen: float = float(_familiarity.get(key, 0))
	return lerpf(1.0, SURPRISE_FLOOR, clampf(seen / FAMILIARITY_FULL, 0.0, 1.0))

## Novelty ages only for the habit that actually fired. Deliberately never decays
## within a level: habituation to a specific stimulus does not wear off while you keep
## using it, which is exactly why people switch apps rather than wait.
func _age_familiarity(key: StringName) -> void:
	if key == &"":
		return
	_familiarity[key] = int(_familiarity.get(key, 0)) + 1

func add_craving(amount: float) -> void:
	set_craving(craving + amount)

func set_craving(value: float) -> void:
	craving = clampf(value, 0.0, 100.0)
	craving_changed.emit(craving)

func add_satisfaction(amount: float) -> void:
	set_satisfaction(satisfaction + amount)

func set_satisfaction(value: float) -> void:
	satisfaction = clampf(value, 0.0, 100.0)
	satisfaction_changed.emit(satisfaction)
	streak_changed.emit(streak, streak_mult())

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

# ---------------------------------------------------------------- Attention Bandwidth
#
# The global build capacity: every standing habit OCCUPIES part of it, and a build that
# would overflow it is refused the same way an unaffordable one is. "Bandwidth" is the
# attention-science term (cognitive bandwidth — Mullainathan & Shafir), not a sci-fi
# power grid; it lives beside the Routine field, which decides WHERE you can build,
# while Bandwidth decides HOW MUCH you can hold at once.
#
# Deliberately NOT a draining tank. The HUD comment at game.gd:_build_hud explains why
# this game refuses the ego-depletion model (willpower as fuel that runs out); this
# number never moves on its own — it counts commitments currently held, and it only
# changes when the player takes one on or lets one go. That is the defensible version
# of a capacity: you cannot hold twelve new practices at once, but attention does not
# leak out of you while you stand still.

const BASE_BANDWIDTH := 120

var bandwidth_max := BASE_BANDWIDTH
var bandwidth_used := 0

func bandwidth_free() -> int:
	return bandwidth_max - bandwidth_used

func can_reserve_bandwidth(amount: int) -> bool:
	return amount <= bandwidth_free()

## Same gate-not-reaction contract as spend_dopamine: returns false and changes nothing
## when the capacity isn't there, so _build_on can refuse before anything is created.
func reserve_bandwidth(amount: int) -> bool:
	if amount > bandwidth_free():
		return false
	bandwidth_used += amount
	bandwidth_changed.emit(bandwidth_used, bandwidth_max)
	return true

func release_bandwidth(amount: int) -> void:
	if amount == 0:
		return
	bandwidth_used = maxi(0, bandwidth_used - amount)
	bandwidth_changed.emit(bandwidth_used, bandwidth_max)

# ---------------------------------------------------------------- Rush economy
#
# The third currency, and the only one you cannot farm safely. Dopamine pays for
# structure (habits), Insight for permanence (cards and the tree), Rush for the panic
# button — and it is earned exclusively by letting a distraction get close enough that
# killing it was nearly a mistake.
#
# That is the lesson in one number: the tools you reach for when you are already
# overwhelmed are paid for by having been overwhelmed. It cannot be banked between
# levels and it cannot be bought.

## How close to the core a defeat has to land to pay. Roughly three cells — inside the
## ring where a leak was one bad second away, and well outside the "cleared it at the
## spawn" band that the rest of the economy already rewards.
const RUSH_CLOSE_RADIUS := 160.0
const RUSH_PER_CLOSE_KILL := 1

var rush := 0

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
	burnout = 0.0
	selected_habit = null
	quick_hit_enabled = level.quick_hit
	variable_rewards = level.variable_rewards
	kills = 0
	lean_wave_active = false
	craving = 0.0
	satisfaction = 100.0
	streak_enabled = level.streak
	streak = 0
	_leaked_this_wave = false
	# `conditioning` is deliberately ABSENT from this function. See the cue-conditioning
	# block below: a level boundary does not un-learn an association, and resetting it
	# here would quietly delete the one thing the two-level cue arc exists to show.
	_familiarity.clear()
	steady_payout = false
	run_insight = 0
	rush = 0
	# Growth Tree ranks raise the cap permanently (+25/rank). Read here rather than via
	# apply_level_perks(level) because bandwidth is not a LevelData field — the cap is a
	# property of the player's head, not of the map.
	bandwidth_max = BASE_BANDWIDTH + int(MetaProgression.get_perk(MetaProgression.PERK_MAX_BANDWIDTH))
	bandwidth_used = 0
	bandwidth_changed.emit(bandwidth_used, bandwidth_max)
	run_insight_changed.emit(run_insight)
	rush_changed.emit(rush)
	dopamine_changed.emit(dopamine)
	focus_changed.emit(focus, max_focus)
	wave_changed.emit(wave, max_wave)
	tolerance_changed.emit(int(tolerance))
	burnout_changed.emit(burnout)
	selected_habit_changed.emit(selected_habit)
	kills_changed.emit(kills)
	craving_changed.emit(craving)
	satisfaction_changed.emit(satisfaction)

# ---------------------------------------------------------------- the streak
#
# Consecutive waves cleared without a single leak, and the only mechanic in the game
# that the player will recognise from their own phone inside two seconds.
#
# The bonus is REAL and it is meant to feel good. This is not a trap and there is no
# right answer being withheld — a streak genuinely pays, and building carefully to keep
# one is genuinely correct play. If it were secretly bad the lesson would be "the game
# lied to me", which teaches nothing about anything outside the game.
#
# What it does is change the FRAME. Past two or three waves the player is no longer
# earning a bonus, they are protecting one, and a loss looms roughly twice as large as
# the equivalent gain (Kahneman & Tversky, 1979). Two things follow, and both are the
# point:
#
#   * it makes people play SAFE — overbuild, stop experimenting, take the boring line
#   * it makes people play ONE MORE WAVE
#
# Neither is a penalty the game applies. Both are things the player does to themselves
# for a number, with the number visible the whole time.
#
# BREAKS ON THE LEAK, not at the end of the wave. The instant a distraction touches the
# core the counter drops to zero, because the loss has to be a MOMENT — a streak that
# quietly failed to increment during the between-wave summary is bookkeeping, and
# bookkeeping does not sting.
#
# Nothing about the next wave is harder after a break. What was lost is a bonus that had
# not been paid yet. That gap is what the receipt prints.

## Per-wave increment, and the ceiling it stops at. Capped because an uncapped streak
## would eventually pay for careless play by itself, and because the loss-frame is fully
## established by wave four — everything above that is just a bigger number to lose.
const STREAK_STEP := 0.15
const STREAK_MAX_MULT := 1.6

var streak_enabled := false
var streak := 0
var _leaked_this_wave := false

func streak_mult() -> float:
	if not streak_enabled or streak < 1:
		return 1.0
	return minf(STREAK_MAX_MULT, 1.0 + STREAK_STEP * float(streak))

## Called by game.gd when a wave finishes. A wave that leaked has already broken the
## streak at the moment it happened, so this only ever has to handle the clean case.
func note_wave_cleared() -> void:
	if not streak_enabled or _leaked_this_wave:
		return
	streak += 1
	Mirror.mark(&"streak", streak)
	streak_changed.emit(streak, streak_mult())

func begin_wave_streak_window() -> void:
	_leaked_this_wave = false

# ---------------------------------------------------------------- cue conditioning
#
# How much the blue flash has come to MEAN. Everything about this block is designed
# around one finding, and it is the hardest thing the game has to say:
#
#   **Recovery does not erase the association.**
#
# Cue-induced reinstatement (Shaham et al., 2003, and the human cue-reactivity work
# behind it): after a conditioned response has been extinguished, a single re-pairing
# restores it almost to its old strength — far faster than it took to build. It is why
# relapse is not evidence of weak character, and it is why "I quit for a month, I can
# handle one" is the most expensive sentence in the whole subject.
#
# Three rules make that literal here, and each one is a deliberate refusal:
#
#  1. NOT reset in reset_for_level(). Finishing a level does not un-learn it. This is
#     the only piece of run state that survives the boundary on purpose.
#  2. NOT touched by Tolerance. The player can drain Tolerance to zero, watch the
#     colour come back, and be entirely, visibly "better" — and the flash still pulls
#     exactly as hard. That gap is the lesson, and the receipt prints both numbers
#     side by side without commenting on it.
#  3. Extinction is SLOW and reinstatement is FAST. Empty cues wear the association
#     down a little at a time; one real payout snaps it back to REINSTATE_SHARE of its
#     old peak in a single step. Symmetric numbers here would teach the opposite of
#     what is true.
#
# Deliberately has NO mechanical effect on combat. Its teeth are that the player looks,
# and looking costs them the wave they were watching. Mirror counts that.

## Acquisition per real pairing. ~6 honest cues to full, which is one clean level.
const CUE_ACQUIRE := 0.18
## Extinction per empty cue. A third of acquisition: unlearning is the slow direction.
const CUE_EXTINGUISH := 0.06
## How much of the old peak one real pairing restores after extinction has set in.
const CUE_REINSTATE_SHARE := 0.9
## Below this share of peak the association counts as extinguished — and therefore as
## something that can be REINSTATED rather than merely topped up.
const CUE_EXTINCT_AT := 0.6

var conditioning := 0.0
var cue_peak := 0.0
var _cue_extinct := false

## Returns true when this pairing was a reinstatement rather than ordinary acquisition —
## the caller uses it to mark the log and to let the receipt name the moment.
func condition_cue(real: bool) -> bool:
	if not real:
		conditioning = maxf(0.0, conditioning - CUE_EXTINGUISH)
		if cue_peak > 0.0 and conditioning < cue_peak * CUE_EXTINCT_AT:
			_cue_extinct = true
		return false
	var reinstated: bool = _cue_extinct and cue_peak * CUE_REINSTATE_SHARE > conditioning
	if reinstated:
		conditioning = cue_peak * CUE_REINSTATE_SHARE
	else:
		conditioning = minf(1.0, conditioning + CUE_ACQUIRE)
	cue_peak = maxf(cue_peak, conditioning)
	_cue_extinct = false
	return reinstated

## Only for tests and a genuinely fresh profile. Nothing in normal play calls this —
## if it did, the mechanic above would be a lie.
func forget_conditioning() -> void:
	conditioning = 0.0
	cue_peak = 0.0
	_cue_extinct = false

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

## Burnout has no floor and no permanent component — unlike Tolerance it is a state you
## can actually recover from, just not quickly (game.gd decays it during wave time). A
## meter that only went up would turn one bad wave into an unwinnable level.
func set_burnout(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 100.0)
	if is_equal_approx(clamped, burnout):
		return
	burnout = clamped
	burnout_changed.emit(burnout)

func add_burnout(amount: float) -> void:
	set_burnout(burnout + amount)

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

func add_rush(amount: int) -> void:
	if amount == 0:
		return
	rush = maxi(0, rush + amount)
	rush_changed.emit(rush)

## Same gate-not-reaction contract as spend_insight: returns false and changes nothing
## when it cannot be afforded, so a cast can be refused before it burns its cooldown.
func spend_rush(amount: int) -> bool:
	if amount > rush:
		return false
	rush -= amount
	rush_changed.emit(rush)
	return true

func can_afford_rush(amount: int) -> bool:
	return rush >= amount

# ---------------------------------------------------------------- bus reactions

## True while a "lean wave" runs: defeats pay NO Dopamine — the feed that gives nothing
## back. Set/cleared by game.gd from LevelData.lean_waves. Insight drops still roll:
## the learning still pays even when the feed doesn't.
var lean_wave_active := false

## Rush is paid ABOVE the lean-wave short-circuit, alongside Insight and unlike Dopamine:
## a lean wave withholds the feed's reward, but the risk the player took was real either
## way, and this currency is a receipt for risk rather than a payout for a kill.
##
## Distance comes from the distraction itself (Distraction.distance_to_core) because
## GameState holds no reference to the field and would otherwise have to re-derive the
## core's position from level data.
func _roll_rush(d: Node2D) -> void:
	if not is_instance_valid(d) or not d.has_method("distance_to_core"):
		return
	if d.distance_to_core() <= RUSH_CLOSE_RADIUS:
		add_rush(RUSH_PER_CLOSE_KILL)

# ---------------------------------------------------------------- payout schedule
#
# Variable-ratio reinforcement, with the expected value held EXACTLY equal to the flat
# schedule it replaces. That equality is not a nicety, it is the experiment: the level's
# income is unchanged, only its predictability is, so any difference in how the player
# feels about it comes from the schedule alone.
#
# Most defeats pay BASE_TIER of the old amount; JACKPOT_CHANCE of them pay JACKPOT_MULT.
# BASE_TIER is derived rather than typed so the mean stays 1.0 if the other two are
# retuned.
#
# The Steady Payout card then offers a flat schedule that is STRICTLY BETTER (+20%) and
# perfectly predictable. Turning it down is the finding; taking it and missing the
# randomness is the same finding from the other side.

## Set to false on level 1 — the first level is a clean tower defense with no experiment
## running on the player. Enabled per level via LevelData.variable_rewards.
var variable_rewards := false
## Set by the Steady Payout card. Flat, predictable, and worth more than the gamble.
var steady_payout := false

const JACKPOT_CHANCE := 0.15
const JACKPOT_MULT := 3.0
const STEADY_MULT := 1.2

func _payout_multiplier() -> float:
	if steady_payout:
		return STEADY_MULT
	if not variable_rewards:
		return 1.0
	if randf() < JACKPOT_CHANCE:
		return JACKPOT_MULT
	# Whatever is left over once the jackpots are paid for, so the mean is exactly 1.0.
	return (1.0 - JACKPOT_CHANCE * JACKPOT_MULT) / (1.0 - JACKPOT_CHANCE)

## Downregulation made mechanical: the higher your Tolerance, the less every defeat
## pays. Card/Growth `dopamine_bonus` is applied on top, and the total is floored at 1 —
## without that floor a negative bonus would drain Dopamine on a kill and print "+-1".
func _on_distraction_defeated(d: Node2D, base_reward: int) -> void:
	_roll_rush(d)
	if lean_wave_active:
		add_kill()
		defeat_reward_granted.emit(0)
		if randf() < INSIGHT_DROP_CHANCE:
			add_run_insight(INSIGHT_DROP_AMOUNT)
			if is_instance_valid(d):
				insight_dropped.emit(d.global_position, INSIGHT_DROP_AMOUNT)
		return
	var ratio: float = tolerance / 100.0
	var reward: int = maxi(1, int(round(base_reward * (1.0 - 0.6 * ratio)
		* _payout_multiplier() * streak_mult())))
	var bonus: int = int(ModifierManager.get_modified_stat(0.0, ModifierManager.STAT_DOPAMINE_BONUS))
	reward = maxi(1, reward + bonus)
	add_dopamine(reward)
	add_kill()
	defeat_reward_granted.emit(reward)

	# Novelty ages here, AFTER game.gd has already read surprise_of() for the kill sound.
	# The ordering is guaranteed by Distraction._die(), which emits its own `defeated`
	# signal (presentation) before the bus signal (economy) — so presentation always sees
	# the un-aged value, which is the honest one: how surprising was THIS kill, not the
	# next one.
	if is_instance_valid(d) and "killer_key" in d:
		_age_familiarity(d.killer_key)

	# The Insight drop. Rolled per defeat and independent of the Dopamine reward: one is
	# the fast currency that gets spent immediately, the other the slow one that
	# accumulates into something permanent. That contrast IS the lesson.
	if randf() < INSIGHT_DROP_CHANCE:
		add_run_insight(INSIGHT_DROP_AMOUNT)
		if is_instance_valid(d):
			insight_dropped.emit(d.global_position, INSIGHT_DROP_AMOUNT)

func _on_wave_completed(_wave_number: int) -> void:
	add_run_insight(INSIGHT_PER_WAVE_CLEARED)
	# A wave held on its own merits is the only thing that pays Satisfaction, and the
	# only thing that walks Craving back down. Both directions matter: without the
	# recovery this is a one-way descent, and a one-way descent is a punishment bar
	# rather than a rhythm the player can learn to ride.
	add_satisfaction(SATISFACTION_PER_CLEAN_WAVE)
	add_craving(-CRAVING_DECAY_PER_WAVE)

## Scaled by focus_damage rather than flat per leak, so the meter agrees with the rest of
## the game about what a bad leak is: a Notification getting through (1) barely registers,
## the boss (15) is most of the way to the failure threshold on its own.
const BURNOUT_PER_FOCUS := 3.0

func _on_distraction_escaped(focus_damage: int) -> void:
	# Before anything else: the break has to land on the same frame as the breach, not
	# after the Focus arithmetic and definitely not at the end of the wave.
	if streak_enabled and streak > 0:
		Mirror.mark(&"streak_broken", streak)
		streak = 0
		streak_changed.emit(0, 1.0)
	_leaked_this_wave = true
	lose_focus(focus_damage)
	add_burnout(BURNOUT_PER_FOCUS * float(focus_damage))
	add_satisfaction(SATISFACTION_PER_LEAK * float(focus_damage))
	Mirror.mark(&"leak", focus_damage)
	if focus <= 0:
		SignalBus.game_over.emit(false)

func select_habit(type_key) -> void:
	selected_habit = type_key
	selected_habit_changed.emit(selected_habit)
