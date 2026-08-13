class_name CardData extends Resource
## A roguelike draft card. `tolerance_cost` > 0 marks a two-sided card: it raises
## GameState's Tolerance floor the moment it's picked, in addition to whatever its
## `effects` do.
##
## A card is offered by a two-stage roll (see Game._show_draft_screen): first a rarity
## is drawn from the level's odds curve, then one card is drawn from that rarity's pool.
## So a card's chance of appearing is set by its `rarity` band, not by the size of the
## whole pool — adding ten new commons never dilutes the legendaries.

@export_category("Identity")
@export var id: StringName = &"card_base"
@export var title: String = "Unknown Buff"
@export_multiline var description: String = "Modifies a stat."
## Optional override. Left empty the card inherits its rarity's colour, which is what
## keeps the draft readable — colour should mean rarity, not decoration.
@export var color: String = ""

@export_category("Draft")
## A key of Data.RARITIES. Unknown values fall back to the lowest band.
@export var rarity: StringName = &"common"
## Relative odds against other cards of the SAME rarity. 1.0 is normal; 0.5 shows up
## half as often, 2.0 twice. Lets a band hold both staples and spice.
@export var weight: float = 1.0
## Earliest draft (1-based) this card may appear in. Use it to hold back cards that
## only make sense once the player has habits on the field.
@export var min_draft: int = 1
## Insight cost. -1 means "use my rarity's price" (the normal case); set a value to
## override a single card without inventing a rarity band for it.
@export var price_override: int = -1

@export_category("Effect")
@export var effects: Array[CardEffectData] = []
@export var tolerance_cost: float = 0.0
## Optional one-shot payload fired on pick (Diamond cards). Null for plain stat cards.
@export var burst: CardBurstData = null
