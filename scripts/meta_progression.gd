extends Node
## AUTOLOAD: MetaProgression — persistent growth & save game manager across runs.
##
## Two things live here:
##   1. The Growth Tree — permanent, ranked upgrades bought with Insight.
##   2. Insight itself — the meta currency, earned from EVERY run including losses.
##      A lost run that pays nothing quietly teaches "failure was wasted time", which is
##      the opposite of what this game is about. Losing pays less, not zero.
##
## A Growth node's payload reaches the game by one of two routes: a `modifier` goes
## through ModifierManager like any drafted card, and a `perk_key` is read back through
## get_perk(). Adding a perk = a PERK_* constant here plus one read site.

# ---------------------------------------------------------------- perk vocabulary

## Extra card choices offered in every draft (on top of Data.DRAFT_OPTIONS_BASE).
const PERK_DRAFT_OPTIONS := &"draft_options"
## Rerolls available per draft.
const PERK_DRAFT_REROLLS := &"draft_rerolls"
## Flat max Focus added at level start.
const PERK_MAX_FOCUS := &"max_focus"
## Flat Dopamine added at level start.
const PERK_START_DOPAMINE := &"start_dopamine"
## Fraction shaved off every intervention cooldown. 0.15 = 15% faster.
const PERK_INTERVENTION_COOLDOWN := &"intervention_cooldown"
## Fraction added to Tolerance decay speed. 0.15 = decays 15% faster.
const PERK_TOLERANCE_DECAY := &"tolerance_decay"
## Fraction added to all Insight earned. 0.1 = +10%.
const PERK_INSIGHT_GAIN := &"insight_gain"
## Flat Attention Bandwidth added to the global build cap (GameState.BASE_BANDWIDTH).
const PERK_MAX_BANDWIDTH := &"max_bandwidth"

## Prefix for per-rarity draft odds perks: PERK_RARITY_ODDS + "diamond" bumps the
## Breakthrough weight in every draft roll. Built from the rarity id rather than
## enumerated, so a new rarity in Data.RARITIES is perk-able the day it is added.
const PERK_RARITY_ODDS := "rarity_odds_"

static func rarity_odds_perk(rarity: StringName) -> StringName:
	return StringName(PERK_RARITY_ODDS + String(rarity))

# ---------------------------------------------------------------- insight banking
#
# Insight is EARNED during the run (drops + wave income, see GameState) and spent there
# on draft cards. Whatever survives to the end is banked here. So this file no longer
# scores the run — it only settles it.

## One-time, the first time a level is beaten. Deliberately the only guaranteed lump
## sum: it is what stops the economy from becoming rich-get-richer. A player who had to
## spend every drop just to survive still walks away with tree progress, while a player
## who cruises and hoards cannot farm it twice.
const INSIGHT_FIRST_CLEAR := 50

var current_save: SaveGame

func _ready() -> void:
	current_save = SaveGame.load_save()
	apply_display_settings()

# ---------------------------------------------------------------- settings & hints

## Pushes persisted display preferences onto the window. Guarded for headless runs,
## where there is no window to set and DisplayServer calls would only log errors.
func apply_display_settings() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if current_save.fullscreen
		else DisplayServer.WINDOW_MODE_WINDOWED)

func set_fullscreen(on: bool) -> void:
	current_save.fullscreen = on
	apply_display_settings()
	current_save.write_savegame()

func is_hint_seen(hint_id: String) -> bool:
	return current_save.hints_seen.has(hint_id)

func mark_hint_seen(hint_id: String) -> void:
	if not current_save.hints_seen.has(hint_id):
		current_save.hints_seen.append(hint_id)
		current_save.write_savegame()

func reset_hints() -> void:
	current_save.hints_seen.clear()
	current_save.write_savegame()

func set_hints_enabled(on: bool) -> void:
	current_save.hints_enabled = on
	current_save.write_savegame()

## For settings that mutate current_save fields directly (volume, mute) and just need
## the write committed.
func save_settings() -> void:
	current_save.write_savegame()

# ---------------------------------------------------------------- growth tree

## Owned rank of a node, 0 when unowned.
func get_rank(growth_id: StringName) -> int:
	return int(current_save.growth_ranks.get(String(growth_id), 0))

func has_growth(growth_id: StringName) -> bool:
	return get_rank(growth_id) > 0

func is_maxed(growth_id: StringName) -> bool:
	var node: GrowthNodeData = Data.get_growth_node(growth_id)
	if node == null:
		return true
	return get_rank(growth_id) >= node.max_rank

## Every prerequisite node owned at rank 1+.
func requirements_met(growth_id: StringName) -> bool:
	var node: GrowthNodeData = Data.get_growth_node(growth_id)
	if node == null:
		return false
	for req: StringName in node.requires:
		if get_rank(req) < 1:
			return false
	return true

## Insight price of the next rank, or -1 if maxed / unknown.
func next_rank_cost(growth_id: StringName) -> int:
	var node: GrowthNodeData = Data.get_growth_node(growth_id)
	if node == null:
		return -1
	return node.cost_for_rank(get_rank(growth_id))

func can_unlock(growth_id: StringName) -> bool:
	if is_maxed(growth_id) or not requirements_met(growth_id):
		return false
	var price := next_rank_cost(growth_id)
	return price >= 0 and current_save.insight >= price

## Buys one rank. Returns false (and changes nothing) if it can't be afforded, is maxed,
## or has unmet prerequisites — the caller can react without pre-checking.
func unlock_rank(growth_id: StringName) -> bool:
	if not can_unlock(growth_id):
		return false
	var price := next_rank_cost(growth_id)
	current_save.insight -= price
	var key := String(growth_id)
	current_save.growth_ranks[key] = get_rank(growth_id) + 1
	if not current_save.unlocked_growth.has(key):
		current_save.unlocked_growth.append(key)
	current_save.write_savegame()
	return true

## Legacy signature kept so any older call site still compiles; `cost` is ignored
## because the price now comes from the node's own rank table.
func unlock_growth(growth_id: StringName, _cost: int = 0) -> bool:
	return unlock_rank(growth_id)

## Summed value of one perk across every owned node, scaled by rank.
func get_perk(perk_key: StringName) -> float:
	var total := 0.0
	for node: GrowthNodeData in Data.get_all_growth_nodes():
		if node.perk_key != perk_key:
			continue
		total += node.perk_value * float(get_rank(node.id))
	return total

# ---------------------------------------------------------------- applying growth

## Injects every owned node's stat modifier into ModifierManager, once per rank.
## Rank scaling needs no special maths: get_modified_stat() sums percentages and then
## multiplies once, so three copies of a +8% card read as +24%, not +26%.
func apply_growth_modifiers() -> void:
	for node: GrowthNodeData in Data.get_all_growth_nodes():
		if node.modifier == null:
			continue
		var rank := get_rank(node.id)
		for i in range(rank):
			ModifierManager.add_card(node.modifier)

## Applies level-start perks to a LevelData. game.gd hands in its own duplicate of the
## level, so this mutates a throwaway copy — never the shared resource in Data.
func apply_level_perks(level: LevelData) -> void:
	level.focus += int(get_perk(PERK_MAX_FOCUS))
	level.start_dopamine += int(get_perk(PERK_START_DOPAMINE))

# ---------------------------------------------------------------- run rewards

## Settles a finished run: banks the Insight the player collected and did NOT spend on
## cards, plus the first-clear bonus. Called for wins AND losses — a lost run keeps
## everything it carried, so hoarding is never punished by dying, only by the drops the
## player didn't live long enough to collect. That asymmetry is what makes "spend now or
## save for the tree" a real decision instead of a trap.
##
## Returns {"total": int, "spent": int, "lines": [{"label", "amount"}]} so the end
## screens can render the settlement without duplicating any of it.
func bank_run(level_id: String, victory: bool, carried: int, spent: int) -> Dictionary:
	var lines: Array = []
	var subtotal := 0

	if carried > 0:
		lines.append({"label": "Insight carried out of the run", "amount": carried})
		subtotal += carried

	if victory and not current_save.cleared_levels.has(level_id):
		current_save.cleared_levels.append(level_id)
		lines.append({"label": "First clear bonus", "amount": INSIGHT_FIRST_CLEAR})
		subtotal += INSIGHT_FIRST_CLEAR

	# Reflection pays out on what you take home, not on what you spent — it is the node
	# about reviewing the run, so it rewards ending it with something in hand.
	var bonus_ratio := get_perk(PERK_INSIGHT_GAIN)
	if bonus_ratio > 0.0 and subtotal > 0:
		var bonus := int(round(subtotal * bonus_ratio))
		if bonus > 0:
			lines.append({"label": "Reflection (+%d%%)" % int(round(bonus_ratio * 100.0)),
				"amount": bonus})
			subtotal += bonus

	current_save.insight += subtotal
	current_save.lifetime_insight += subtotal
	current_save.write_savegame()
	return {"total": subtotal, "spent": spent, "lines": lines}

# ---------------------------------------------------------------- map segments
#
# P8 (docs/refactor/PATHFINDING.MD). A map segment is a piece of BOARD a level grows by
# once the player has earned it — see scripts/resources/map_segment_data.gd and
# scripts/map_composer.gd. The unlock lives here, beside the other things that outlive a
# single run, because that is the decision the queue records for it: the map growing is
# persistent progress, NOT a level-completion record (which would tie the board to which
# level you last beat) and NOT a Growth Tree node (which would put board geometry behind
# an Insight price).

## True if `condition` — a MapSegmentData.unlock_condition, not a segment id — is
## satisfied. An EMPTY condition is always satisfied: a segment with no condition is
## simply an unconditional part of the map, which is what makes "no condition" the safe
## authoring default rather than a permanently dark wing.
func is_segment_unlocked(condition: StringName) -> bool:
	if condition == &"":
		return true
	return current_save.unlocked_segments.has(String(condition))

## Grants `condition` permanently and writes the save. Returns false (and writes nothing)
## if it was empty or already granted, so a caller can react without pre-checking — the
## same shape unlock_rank() above uses.
func unlock_segment(condition: StringName) -> bool:
	if condition == &"" or current_save.unlocked_segments.has(String(condition)):
		return false
	current_save.unlocked_segments.append(String(condition))
	current_save.write_savegame()
	return true

# ---------------------------------------------------------------- level completion

func complete_level(level_id: String, stars_earned: int, next_level_id: String = "") -> void:
	current_save.total_clarity_stars += stars_earned
	var prev_best: int = current_save.level_stars.get(level_id, 0)
	if stars_earned > prev_best:
		current_save.level_stars[level_id] = stars_earned
	if next_level_id != "" and not current_save.unlocked_levels.has(next_level_id):
		current_save.unlocked_levels.append(next_level_id)
	current_save.write_savegame()
