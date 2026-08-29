class_name TrodData extends Resource
## A route that opens partway through a level — the map's own move against the player.
##
## Named for the folklore term the lanes already use (see docs/design/fae_theme.md §5):
## a trod is a road the Fae walk, and real trods SHIFT. Mechanically this is the game's
## thesis made playable: attention hijacking is never solved once, it comes back through
## a different channel. A static maze cannot teach that — you solve it and it is over.
##
## PURELY A PREFERENCE, exactly like `LevelData.path_cells`. Opening a trod does not
## move a single wall: it makes ground the horde could always cross into ground the
## horde WANTS to cross, by dropping `path_off_lane_cost` on those cells. That matters
## for two reasons:
##
##  * Nothing the player built can be invalidated by terrain appearing or vanishing
##    under it. The maze still works; the traffic moved.
##  * A trod can never make a level unsolvable, because it removes no route.
##
## Terrain that genuinely changes shape at runtime is a different mechanic and already
## exists — see the sinking-walls spike in game.gd.

## Wave number (1-based) at the start of which this opens. The wave BEFORE it is the
## telegraph: the cells are drawn faint so the player can see it coming and still not
## have enough time to be comfortable. Set to 1 and it is just an ordinary lane.
@export var open_at_wave: int = 3

## The cells to add to the lane network. Paint them in MapEditor exactly like any other
## lane — they are the same kind of data.
##
## DESIGN RULE, learned the hard way in every maze TD that shipped this: a new trod must
## CONVERGE with the existing one, not replace it. If it runs from the spawn to the core
## without ever touching the old route, the player's whole level of work is worth
## nothing and the level reads as a cheat. Sharing the final approach keeps every tower
## near the core paying off, so the player REPOSITIONS instead of starting over.
@export var cells: Array[Vector2i] = []

## Shown when it opens. Keep it in the world's voice — this is the moment the level
## tells the player it is not finished with them.
@export var announce: String = "A new trod has opened"
