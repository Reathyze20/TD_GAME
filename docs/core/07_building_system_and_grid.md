# 07 — Building System & High-Ground Grid

Habits are built exclusively on **high ground** — the fixed terrain tiles that also block
distraction movement and form the maze (`04`). A high-ground cell is either **empty** (buildable)
or **occupied** (one habit). Building, upgrading, and selling habits all spend or refund
**Dopamine** and route through `SignalBus` / `GameState` (`03`).

> Theme reminder (see `00_overview.md`): "towers" are **habits**, "gold" is **Dopamine**,
> "build spots" are **high-ground cells**, and the maze terrain embodies **structure & boundaries**.
> There are no "Archers" or "Cannons" — the habit roster is in `05`.

## 1. Display, Viewport & Scale Strategy

To support the arcade-style tactical gameplay feel, the project enforces a strict high-density macro battlefield scale.

### Viewport Configuration
- **Target Resolution**: `1920x1080` (1080p widescreen canvas).
- **Project Settings** (`project.godot`):
  - `display/window/size/viewport_width = 1920`
  - `display/window/size/viewport_height = 1080`
  - `stretch/mode = "canvas_items"`
  - `stretch/aspect = "keep"`

### Proportional Grid Density
- **High Tile Density**: Map grids should support approx. **30–40 tiles** across the horizontal width so towers and enemies do not feel oversized.
- **Scale Ratio**: Tower footprints and high-ground cells must be sized proportionally (e.g., `48x48px` or `64x64px`).
- **Tactical Spacing**: Enemies and roads (`Path2D`) must match this high-density scale to create a large-scale battle feeling with long, curving routes. This ensures ample tactical distance for the 125° directional cone targeting system (`05`).

---

## 2. High ground = build spot = maze wall

Every level in `data.gd` defines a `high_ground` array of `[col, row]` cells. These cells are:

- **Solid in `AStarGrid2D`** — distractions pathfind *around* them (`04`).
- **The only tiles where habits can be placed** — one habit per cell.
- **Visually raised** — drawn with a 3D-ish bevel in `game.gd._draw()`.

Because the maze is *terrain* (not player-placed), routes never need recomputing when a habit is
built or sold. The maze is fixed; the player decides *which* high-ground cell to fill and *which*
habit to place there.

## 3. Build interaction (prototype model)

The prototype uses a **select-then-click** flow, ensuring all coordinate math and hover indicators account for the `1920x1080` grid:

1. Player clicks a habit button in the bottom `BuildBar` (e.g. "Focus 30", "Calm 45", "Move 70").
2. `GameState.select_tower(key)` stores the selection; the HUD highlights the active button.
3. As the mouse moves, `game.gd._update_hover()` tracks the hovered cell and `_draw()` renders:
   - A **green frame** if the cell is valid (is high ground, is empty, player can afford it).
   - A **red frame** if invalid or unaffordable.
   - The habit's **range circle** around the hovered cell.
4. Left-click on a valid cell → `_build_on(cell)`:
   - Deducts Dopamine via `GameState.spend_dopamine(cost)`.
   - Instantiates a `Tower` node, calls `tower.setup(game, key, col, row)`.
   - Marks the cell in `tower_cells` so it cannot be double-built.

> ⚠️ **Mouse-filter bug (already fixed, keep it fixed):** the centered `_message_label`
> defaulted to `mouse_filter = STOP` and silently ate clicks over central high-ground cells.
> **All display labels must use `MOUSE_FILTER_IGNORE`** — see `09`.

## 4. Target node structure (when we add art)

When placeholder shapes graduate to sprites, each high-ground build spot and habit follows Y-sort
rules (`01`). Origin at the base; habit is a child of the build-spot container.

```text
BuildSpot (Area2D) [y_sort_enabled = true]
├── EmptyVisuals (Node2D) [y_sort_enabled = true]
│   └── Sprite2D (e.g. dirt patch / stone circle)   # bottom aligned to (0,0)
├── CollisionShape2D                                  # clickable area (input_event)
└── HabitContainer (Node2D) [y_sort_enabled = true]   # where Habit.tscn is instanced
```

Build spots live inside `EntityLayer/Habits` (`01`) so they integrate into the global Y-sort.

## 5. Target build-spot script (`BuildSpot.gd`)

Handles the state of one high-ground cell and bridges player clicks to the economy.

```gdscript
class_name BuildSpot extends Area2D

enum SpotState { EMPTY, BUILT }

@export var habit_scene: PackedScene         # base Habit.tscn to instantiate

var current_state: SpotState = SpotState.EMPTY
var current_habit: Habit = null

@onready var empty_visuals: Node2D = $EmptyVisuals
@onready var habit_container: Node2D = $HabitContainer

func _ready() -> void:
    input_event.connect(_on_input_event)

func _on_input_event(_vp: Node, event: InputEvent, _idx: int) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if get_viewport().gui_is_dragging() or get_viewport().gui_get_focus_owner() != null:
            return
        _handle_click()

func _handle_click() -> void:
    # Tell the UI system that a build spot was clicked.
    SignalBus.build_requested.emit(self)

# ---- Building & upgrading ----

func build_habit(habit_data: HabitData) -> void:
    if current_state != SpotState.EMPTY:
        return
    current_habit = habit_scene.instantiate() as Habit
    habit_container.add_child(current_habit)
    current_habit.global_position = global_position
    current_habit.setup(habit_data)

    empty_visuals.hide()
    current_state = SpotState.BUILT

    SignalBus.habit_built.emit(current_habit, habit_data.build_cost)

func upgrade_habit(new_data: HabitData) -> void:
    if current_state != SpotState.BUILT or not is_instance_valid(current_habit):
        return
    current_habit.queue_free()

    current_habit = habit_scene.instantiate() as Habit
    habit_container.add_child(current_habit)
    current_habit.global_position = global_position
    current_habit.setup(new_data)

    SignalBus.habit_upgraded.emit(current_habit, new_data, new_data.build_cost)

func sell_habit() -> void:
    if current_state != SpotState.BUILT or not is_instance_valid(current_habit):
        return
    var refund := int(current_habit.data.build_cost * 0.5)   # 50% dopamine refund
    current_habit.queue_free()
    current_habit = null

    empty_visuals.show()
    current_state = SpotState.EMPTY

    SignalBus.habit_sold.emit(self, refund)
```

## 6. Build menu controller (target)

Because multiple build spots exist, the contextual UI shouldn't be baked into each spot. A
singular `BuildMenuController` lives in the HUD layer (`09`). It listens for
`SignalBus.build_requested` and spawns a radial menu over the clicked spot.

**Flow:**

1. Player clicks a high-ground cell.
2. `BuildSpot` emits `build_requested(self)`.
3. `BuildMenuController` reads `spot.current_state`:
   - **EMPTY:** shows available base habits (Focus Timer, Mindfulness, Exercise, …).
   - **BUILT:** reads `spot.current_habit.data.upgrades` → shows next-tier options + a "Sell"
     button.
4. Each option cross-references `GameState.can_afford(cost)`. Unaffordable options are greyed out.

```gdscript
class_name BuildMenuController extends Control

@export var radial_menu_scene: PackedScene
var active_menu: Node = null
var selected_spot: BuildSpot = null

func _ready() -> void:
    SignalBus.build_requested.connect(_on_spot_clicked)
    SignalBus.build_canceled.connect(_close_menu)

func _on_spot_clicked(spot: BuildSpot) -> void:
    _close_menu()
    selected_spot = spot

    active_menu = radial_menu_scene.instantiate()
    add_child(active_menu)

    var screen_pos := spot.get_global_transform_with_canvas().origin
    active_menu.global_position = screen_pos

    if spot.current_state == BuildSpot.SpotState.EMPTY:
        active_menu.setup_build_options(self)
    else:
        active_menu.setup_upgrade_options(self, spot.current_habit)

func attempt_purchase(habit_data: HabitData) -> void:
    if GameState.can_afford(habit_data.build_cost):
        if selected_spot.current_state == BuildSpot.SpotState.EMPTY:
            selected_spot.build_habit(habit_data)
        else:
            selected_spot.upgrade_habit(habit_data)
        _close_menu()

func _close_menu() -> void:
    if is_instance_valid(active_menu):
        active_menu.queue_free()
    active_menu = null
    selected_spot = null
```

## 7. Required `SignalBus` additions

These signals (already listed in `03`) support the building flow:

```gdscript
# In SignalBus.gd:
signal build_requested(spot: Node2D)          # a high-ground spot was clicked
signal build_canceled()
signal habit_built(habit: Node2D, cost: int)
signal habit_upgraded(habit: Node2D, new_tier: HabitData, cost: int)
signal habit_sold(habit: Node2D, refund: int)
```

## Intersection with the prototype

**More of this doc is already built than the sections above admit — including upgrade/sell, which
was long assumed to be target-only work.** `scripts/build_spot.gd` (`class_name BuildSpot`) is real
and is created for every `high_ground` cell in `game.gd._build_field()`
(`build_spots[cell] = bs`). It genuinely handles build **and** upgrade **and** sell:

- **`BuildSpot` is a plain logic `Node`, not an `Area2D`.** It has no collision shape and doesn't
  detect its own clicks — unlike §5's target design. Click routing still lives entirely in
  `game.gd`: `_unhandled_input()` + `_update_hover()` track `_hover_cell` from raw mouse position
  (`world_to_cell()`), and clicking calls straight into `build_spots[cell]`'s methods. So `BuildSpot`
  is real, but as a state/logic object the `Game` node drives — not a scene-tree click target.
- **Real method signatures differ from §5's target.** `build_habit(type_key: String, facing_angle,
  arc_angle) -> Habit` (not a `HabitData` resource — `Data.HABIT_TYPES` dict key + the two SWHAOP
  aim values from build time), `upgrade_habit(new_type_key: String) -> Habit`, and
  `sell_habit() -> int` **returns the Dopamine refund directly** rather than emitting a
  `habit_sold` signal for something else to read.
- **Upgrade/sell/re-aim is a real UI**, just a code-built linear panel (`game.gd._open_panel()`),
  not §6's radial menu: clicking a built cell with nothing selected opens a `PanelContainer` with
  stat readout, an "↑ Upgrade" button per `HabitData.upgrades` entry, a "Sell +N ⬡" button, and —
  not covered by this doc at all — a **"Re-Aim Cone"** button that re-enters the SWHAOP aiming mode
  from `05` so a placed habit's facing/width can be redone later.
- **No `SignalBus` signals fire for any of this.** `build_requested` / `habit_built` /
  `habit_upgraded` / `habit_sold` (§7) are declared but never emitted anywhere in the codebase —
  `game.gd` calls `BuildSpot` methods and `GameState.spend_dopamine()` / `add_dopamine()` directly.
  The real change signal is `GameState.selected_habit_changed(type_key)` — **not**
  `selected_tower_changed` as an earlier draft of this section claimed.
- **Habits are parented to the Y-sort container** (`BuildSpot.build_habit()` calls
  `game.entities.add_child(h)`), rather than directly to `game` or a `HabitContainer`.
- **Hover preview already works** — green/red frame + range circle, redrawn each frame via
  `_hover_cell` in `_draw()`.

**Migration path:** the remaining gap is narrower than it looks — give `BuildSpot` a visual scene
(`Area2D` root + `HabitContainer`, per §4–§5) so it can Y-sort and optionally detect its own clicks,
and swap the linear panel for a radial menu if that's still wanted. Upgrade/sell/re-aim and the
core `BuildSpot` state machine do **not** need to be built — they're already shipped.

## Implementation checklist

- [ ] Create `BuildSpot.tscn` using an `Area2D` root, `y_sort_enabled = true` on root + `HabitContainer`.
- [ ] `BuildSpot.gd` uses `input_event` for mouse clicks, emits `build_requested(self)` on `SignalBus`.
- [ ] Habits are instanced into `HabitContainer` to preserve Y-sort; `EmptyVisuals` hidden when built.
- [ ] `habit_built`, `habit_upgraded`, `habit_sold` signals emit correct Dopamine costs/refunds
      so `GameState` (`03`) can deduct or add Dopamine.
- [ ] `BuildMenuController` maps the 2D world position of the build spot to screen coordinates
      via `get_global_transform_with_canvas().origin` for the contextual radial menu.
- [ ] Field clicks ignored while a menu/UI owns the pointer
      (`get_viewport().gui_get_hovered_control()` / `gui_is_dragging()` — see `09`).