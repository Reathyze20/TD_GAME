extends Node
## AUTOLOAD: SignalBus — global event routing. No logic, only typed signal definitions.
## Autoload order: SignalBus (index 0) BEFORE GameState (index 2), so GameState can
## connect to these in its own _ready().
##
## Division of labour with GameState's signals — they are NOT competing buses:
##   SignalBus.*        — "something happened in the world" (events, past tense)
##   GameState.*_changed — "this value is now X" (state readouts the HUD binds to)
## A dopamine reward therefore travels: distraction_defeated (bus, event) → GameState
## applies the economy rules → dopamine_changed (GameState, new value) → HUD.

# --- Game flow ---
signal level_started(level_id: int)
## Unified end-of-level event. victory=true routes to the stars/save/Education path,
## victory=false to the Game Over screen — the two are NOT symmetric, see game.gd.
signal game_over(victory: bool)

# --- Waves & spawns ---
signal wave_started(wave_number: int)
signal wave_completed(wave_number: int)
signal distraction_spawned(distraction: Node2D)
signal distraction_escaped(focus_damage: int)    ## reached the Focus core

# --- Combat & economy ---
## Carries the distraction's BASE reward; GameState applies tolerance scaling and
## modifier bonuses, since those are economy rules, not properties of the kill.
signal distraction_defeated(distraction: Node2D, dopamine_reward: int)

# --- Building (doc 07) ---
## Notification-only. Dopamine is spent/refunded imperatively at the call site, because
## affordability is a GATE that can abort the build — a listener reacting after the fact
## could not stop it. See REFACTOR_PLAN.md hazard 1.
signal build_requested(spot: Node2D)             ## entered aiming mode on a fresh build
signal build_canceled()                          ## aiming canceled, build rolled back
signal habit_built(habit: Node2D, cost: int)
signal habit_upgraded(habit: Node2D, cost: int)
signal habit_sold(spot: Node2D, refund: int)
