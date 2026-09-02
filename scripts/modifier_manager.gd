extends Node
## AUTOLOAD: ModifierManager — tracks drafted cards and recalculates habit stats.
## Reset at the start of each level; cards do NOT carry across levels (meta-progression is Phase 5).

# Stat type string constants — match the "stat_type" key inside a card's `effects`.
const STAT_WILLPOWER          := "willpower"
const STAT_AWARENESS          := "awareness"
const STAT_RANGE              := "range"
const STAT_FIRE_COOLDOWN      := "fire_cooldown"     # lower = faster; cards use negative values
const STAT_DISTRACTION_SPEED  := "distraction_speed" # lower = slower; cards use negative values
const STAT_DISTRACTION_HEALTH := "distraction_health" # lower = frailer; cards use negative values
const STAT_DOPAMINE_BONUS     := "dopamine_bonus"    # flat bonus per distraction defeated
## How far the board can be SEEN, as a multiplier on every sight radius (P11). Cards use
## percentages. Distinct from STAT_RANGE on purpose: range is how far a habit can shoot,
## this is how far anything can be seen at all — and since a habit refuses a target it
## cannot see (tower.gd is_point_in_cone), shrinking this one shrinks effective range too,
## while widening range alone buys nothing in the dark.
const STAT_SIGHT_RADIUS       := "sight_radius"

var active_cards: Array[CardData] = []

## Ids of cards the player drafted THIS level. Growth Tree modifiers are added through
## the same add_card() pipeline but deliberately do not register here — a permanent
## upgrade must never remove its themed twin from the draft pool.
var drafted_ids: Array[StringName] = []

signal modifiers_updated

func add_card(card: CardData) -> void:
	active_cards.append(card)
	modifiers_updated.emit()

## add_card() plus bookkeeping that keeps a card from being offered twice in one level.
func add_drafted_card(card: CardData) -> void:
	if not drafted_ids.has(card.id):
		drafted_ids.append(card.id)
	add_card(card)

func has_drafted(card_id: StringName) -> bool:
	return drafted_ids.has(card_id)

func reset() -> void:
	drafted_ids.clear()
	if active_cards.is_empty():
		return
	active_cards.clear()
	modifiers_updated.emit()

## Returns the final stat value after applying all matching active modifiers.
##
## base_stat    — the unmodified value (e.g. def.willpower_damage)
## stat_type    — one of the STAT_* constants above
## habit_type   — the HABIT_TYPES key of the calling habit, or "" for non-habit contexts
##                (cards with target "ALL" always apply)
## A card may carry several effects, and they need not pull the same way — two-sided
## cards deliberately mix a benefit with a cost, so this sums across every effect of
## every active card rather than one effect per card.
func get_modified_stat(base_stat: float, stat_type: String, habit_type: String = "") -> float:
	var flat := 0.0
	var multi := 1.0
	for card in active_cards:
		for effect: CardEffectData in card.effects:
			if effect.stat_type != stat_type:
				continue
			var target: String = effect.target
			# Family match, not exact: a card targeting "focus_timer" must survive the
			# upgrade to "focus_timer_2" — the node is swapped on upgrade and an exact
			# type_key match silently deleted every drafted card the moment you upgraded.
			if target != "ALL" and (habit_type == ""
					or Data.habit_family(target) != Data.habit_family(habit_type)):
				continue
			if effect.is_percentage:
				multi += effect.value
			else:
				flat += effect.value
	return (base_stat + flat) * multi
