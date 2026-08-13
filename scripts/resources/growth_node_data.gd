class_name GrowthNodeData extends Resource
## One permanent Growth Tree upgrade, bought with Insight and kept across runs.
##
## A node carries two independent payloads and may use either, both, or neither:
##
##   `modifier` — a CardData injected into ModifierManager, exactly like a drafted card
##                (see 10/11). Applied ONCE PER RANK, which is why rank scaling needs no
##                maths of its own: get_modified_stat() sums percentages before it
##                multiplies, so holding rank 3 of a +8% node reads as +24%.
##   `perk_key` — a named non-stat effect (extra draft options, better Diamond odds,
##                cheaper interventions...). ModifierManager only speaks in habit stats,
##                so anything outside that vocabulary goes here instead of being forced
##                into a fake stat. Read it back with MetaProgression.get_perk().
##
## Adding a node = drop a .tres into res://data/growth/. Data groups and orders the tree
## by `branch` + `tier`, so there is no list to keep in sync.

@export_category("Identity")
@export var id: StringName = &"deep_sleep"
@export var name: String = "Deep Sleep"       ## Field name matches existing call sites (nd.name).
@export_multiline var description: String = "Rest sharpens resolve."

@export_category("Tree placement")
## A key of Data.GROWTH_BRANCHES. Unknown branches are still shown, under their own id.
@export var branch: StringName = &"discipline"
## Row within the branch. Also the display order — lower tiers sit nearer the trunk.
@export var tier: int = 0
## Node ids that must be owned at rank 1 or higher before this one can be bought.
@export var requires: Array[StringName] = []

@export_category("Cost & ranks")
## How many times this node can be bought. Rank 1 is the first purchase.
@export var max_rank: int = 1
## Insight cost per rank. If shorter than max_rank the last entry repeats, so a flat
## cost is just [40] and an escalating one is [40, 70, 120].
@export var costs: Array[int] = [40]
## Legacy single-cost field, kept so pre-Insight .tres files still load. Used only when
## `costs` is empty.
@export var cost: int = 0

@export_category("Payload — stat modifier")
@export var modifier: CardData = null

@export_category("Payload — named perk")
## A MetaProgression.PERK_* constant, or "" for none.
@export var perk_key: StringName = &""
## Added once per owned rank.
@export var perk_value: float = 0.0

## Insight price of the next rank up from `current_rank`. -1 when maxed.
func cost_for_rank(current_rank: int) -> int:
	if current_rank >= max_rank:
		return -1
	if costs.is_empty():
		return cost
	return costs[mini(current_rank, costs.size() - 1)]
