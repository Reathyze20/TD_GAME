# 12 — Player Abilities (Active Interventions)

The player has **active abilities** — powerful, cooldown-gated interventions that represent
*conscious, deliberate actions* against the digital onslaught. Unlike habits (which fire
automatically), abilities require manual targeting and timing.

> Theme reminder (see `00_overview.md`): abilities are **interventions** — not generic "spells."
> Each one maps to a real-world deliberate action the player can take against digital overwhelm.
> "Enemies" are **distractions**, "towers" are **habits**, damage channels are **Willpower** and
> **Awareness**.

## 1. Ability roster (design)

| id | Ability | Type | Themed meaning |
|---|---|---|---|
| `screen_break` | Screen Break | `DAMAGE_AOE` | Step away from the screen — AoE Willpower burst |
| `call_a_friend` | Call a Friend | `SUMMON_ALLIES` | Summon temporary Allies (see `06`) at a location |
| `deep_breath` | Deep Breath | `FREEZE_AOE` | AoE **Interrupt** (freeze) — pause all distractions in radius |

## 2. Ability data (`InterventionData.gd`)

```gdscript
class_name InterventionData extends Resource

enum InterventionType { DAMAGE_AOE, SUMMON_ALLIES, FREEZE_AOE }

@export_category("Identity")
@export var id: StringName = &"screen_break"
@export var display_name: String = "Screen Break"
@export_multiline var description: String = "Step away. AoE Willpower burst."
@export var icon: Texture2D

@export_category("Stats")
@export var type: InterventionType
@export var cooldown: float = 30.0
@export var radius: float = 100.0
@export var willpower_damage: int = 50            # for DAMAGE_AOE
@export var awareness_damage: int = 0             # for DAMAGE_AOE
@export var freeze_duration: float = 3.0          # for FREEZE_AOE

@export_category("Visuals")
@export var visual_scene: PackedScene             # explosion / freeze ring / ally spawn FX
```

## 3. Ability state machine

Abilities use a simple three-state flow:

```
IDLE  ──▶  TARGETING  ──▶  CASTING  ──▶  COOLDOWN  ──▶  IDLE
            (LMB)           (execute)      (timer)
           ╰─ RMB cancel ─╯
```

- **Idle:** button is clickable (cooldown elapsed).
- **Targeting:** button clicked → game shows an AoE indicator following the mouse.
- **Casting:** left-click on the field → execute the ability, start cooldown.
- Right-click during targeting → cancel, return to Idle.

## 4. Intervention manager (`InterventionManager.gd`)

Handles cursor state and ability execution. Lives in the `Level` scene hierarchy.

```gdscript
class_name InterventionManager extends Node2D

@export var intervention_data: InterventionData
@export var aoe_indicator: Sprite2D              # visual circle showing radius

var current_cooldown: float = 0.0
var is_targeting: bool = false

signal cooldown_updated(time_left: float)

func _ready() -> void:
    aoe_indicator.hide()

func _process(delta: float) -> void:
    if current_cooldown > 0:
        current_cooldown -= delta
        cooldown_updated.emit(current_cooldown)

    if is_targeting:
        aoe_indicator.global_position = get_global_mouse_position()

func _input(event: InputEvent) -> void:
    if not is_targeting:
        return
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_LEFT:
            _cast(get_global_mouse_position())
        elif event.button_index == MOUSE_BUTTON_RIGHT:
            _cancel_targeting()

# ---- Public API ----

func start_targeting() -> void:
    if current_cooldown <= 0:
        is_targeting = true
        aoe_indicator.show()
        aoe_indicator.scale = Vector2.ONE * (intervention_data.radius /
            (aoe_indicator.texture.get_width() / 2.0))

# ---- Internal ----

func _cancel_targeting() -> void:
    is_targeting = false
    aoe_indicator.hide()

func _cast(target_pos: Vector2) -> void:
    _cancel_targeting()
    current_cooldown = intervention_data.cooldown

    # Spawn visual FX in ProjectileLayer (Z 5, see 01).
    if intervention_data.visual_scene:
        var fx := intervention_data.visual_scene.instantiate()
        get_tree().current_scene.get_node("ProjectileLayer").add_child(fx)
        fx.global_position = target_pos

    # Execute based on type.
    match intervention_data.type:
        InterventionData.InterventionType.DAMAGE_AOE:
            _deal_aoe_damage(target_pos)
        InterventionData.InterventionType.FREEZE_AOE:
            _freeze_aoe(target_pos)
        InterventionData.InterventionType.SUMMON_ALLIES:
            _summon_allies(target_pos)

func _deal_aoe_damage(pos: Vector2) -> void:
    for d in get_tree().get_nodes_in_group("distractions"):
        if is_instance_valid(d) and not d.is_dead:
            if d.global_position.distance_to(pos) <= intervention_data.radius:
                d.take_damage(intervention_data.willpower_damage,
                    intervention_data.awareness_damage)

func _freeze_aoe(pos: Vector2) -> void:
    for d in get_tree().get_nodes_in_group("distractions"):
        if is_instance_valid(d) and not d.is_dead:
            if d.global_position.distance_to(pos) <= intervention_data.radius:
                d.get_node("StatusManager").apply_interrupt(
                    intervention_data.freeze_duration)

func _summon_allies(pos: Vector2) -> void:
    # Temporary allies — see 06 for Ally logic.
    pass # implementation deferred to when Accountability/Allies are built
```

## 5. Thematic integration

Abilities reinforce the educational message:

- **Screen Break** — stepping away from the screen is the single most effective intervention.
  The AoE Willpower burst shows that *disengaging deals massive damage to distractions*.
- **Call a Friend** — social support physically blocks the feed (Allies, `06`).
- **Deep Breath** — mindful pause freezes everything, showing that *a deliberate pause halts
  the cycle*.

Ability tooltips should carry a one-liner: `"Step away. The feed can wait."`

## Intersection with the prototype

**Built and playable — this doc is stale, not the code.** All three §1 abilities are implemented
directly in `game.gd` (no separate `InterventionManager` node/class — it's ~130 lines
of functions + an `intervention_cooldowns: Dictionary` field on `Game` itself):

- `Data.INTERVENTIONS` has `screen_break` (18s cooldown, radius 180, **45 Willpower + 15
  Awareness** — genuinely both channels, per the checklist below), `deep_breath` (22s cooldown,
  radius 210, 3.5s freeze), and `call_a_friend` (30s cooldown, **2 Allies for 14s**), which landed
  once `06` (Accountability/Allies) was built and could supply the `Ally` class.
- **`call_a_friend` reuses `06`'s `Ally` verbatim**, passing its own dictionary as the stat block —
  `Ally.setup()` reads `ally_health` / `ally_damage` / `ally_attack_cooldown` / `ally_lifetime` off
  whatever def it is handed, so the barracks row and the intervention row are interchangeable. The
  only behavioural difference is `ally_lifetime > 0`, which makes the summon expire on its own
  (drawn as a draining gold ring). `type` is the string `"summon_allies"`, matching how the other
  two dispatch, and the Allies land in a ring of `radius` around the click.
- Data is a plain `Dictionary` per entry (matches `02`'s MVP shortcut), no `InterventionData`
  Resource or `InterventionType` enum — a string `"type"` field (`"damage_aoe"` / `"freeze_aoe"`)
  is switched on instead.
- **The state flow is simpler than §3**, with no separate targeting phase: `_select_intervention()`
  arms it (button highlights), and the **next left-click casts immediately** at the clicked point —
  there's no AoE-radius indicator that scales and follows the mouse before you commit. A falling
  "sky-strike" visual travels to the target over ~0.22s, then `_trigger_intervention_impact()` runs
  the real gameplay: iterates `game.distractions` within `radius`, calling `take_damage()` (damage
  type) or `apply_slow(0.0, freeze_duration)` (freeze type — reuses the existing slow system with
  factor `0.0` rather than a dedicated `is_stunned`/`StatusManager` flag).
- Cooldowns show as **live countdown text on the button itself** (`"Break (12.3s)"`, greyed out),
  not `13`'s `TextureProgressBar` radial sweep — same information, different presentation.
- VFX (`strike`/`wave` nodes) are plain children of `Game`, not a dedicated `ProjectileLayer` —
  consistent with the project having no Z-layer container nodes at all yet (`01`).
- `Distraction` **is** added to the `"distractions"` group (`enemy.gd::setup()`), but the
  intervention code doesn't actually use `get_tree().get_nodes_in_group(...)` — it iterates
  `game.distractions` directly. The group tag is there and correct, just not yet load-bearing here.

## Airplane Mode + the Rush currency (added 15. 8. 2026)

A fourth ability, `data/interventions/airplane_mode.tres`, hotkey **R**. It is the first one
that costs a resource rather than only time.

- **`type = "freeze_field"`** — a fourth arm in `_trigger_intervention_impact()`. It ignores
  `radius` entirely and freezes every live distraction on the board for `freeze_duration`
  (3.0s). Because it is not targeted, `_cast_intervention()` overwrites `target_pos` with
  `objective_pos` so the strike, the ring and the popup all land on the core, and the armed
  preview draws a frame around the whole field instead of a disc at the cursor — a disc
  would promise a placement decision the player does not get to make.
- **`rush_cost = 3`**, charged through `GameState.spend_rush()` as a **gate placed before the
  cooldown is committed**, so a refused cast leaves the ability ready. The same check also
  runs in `_select_intervention()`, which historically validated *nothing*: a hotkey could
  arm an ability that was on cooldown and then swallow the next left-click on the field.
- `InterventionData.rush_cost` defaults to **0**, because `screen_break.tres` and its
  siblings author almost nothing and inherit the rest of that file — a nonzero default would
  silently price all three.

**Rush** (`GameState.rush`) is the third currency, alongside Dopamine (structure) and Insight
(permanence). It is earned **only** by defeating a distraction within `RUSH_CLOSE_RADIUS`
(160px, roughly three cells) of the core — i.e. by nearly losing. It is paid above the
lean-wave short-circuit, like Insight and unlike Dopamine: a lean wave withholds the feed's
reward, but the risk the player took was real either way. It does not persist between levels.

> **"Freeze" means movement only.** `apply_slow(0.0, dur)` stops pathing and nothing else, so
> under Airplane Mode a Group Chat still disrupts habits, an Energy Drink still pulses its
> haste aura, and the boss still cycles its shield and spawns minions. This is stated in the
> ability's own description so it does not read as a bug.

## Implementation checklist

- [ ] `InterventionData.gd` as a Resource with `InterventionType` enum and themed fields — real data
      is untyped `Dictionary` literals in `Data.INTERVENTIONS` instead.
- [ ] `InterventionManager.gd` with `IDLE → TARGETING → CASTING → COOLDOWN` state flow — real flow
      is `IDLE → (armed) → CAST-on-click → COOLDOWN`, no separate aim-then-confirm targeting phase.
- [ ] AoE indicator scales to `intervention_data.radius` and follows the mouse during targeting —
      not implemented; casting is a blind click at the current mouse position.
- [ ] Right-click cancels targeting without casting.
- [x] `_deal_aoe_damage()` uses both Willpower and Awareness channels (not a generic "true damage") —
      `screen_break` deals 45 Willpower + 15 Awareness.
- [x] `_summon_allies()` implemented — spawns `06`'s `Ally` in a ring around the click, with an
      `ally_lifetime` so the summons expire instead of being permanent.
- [ ] VFX spawn into `ProjectileLayer` (Z 5) to stay above the field — no `ProjectileLayer` exists;
      VFX nodes are plain children of `Game`.
- [x] Distractions added to `"distractions"` group for fast iteration — done, though the current
      AoE code iterates `game.distractions` directly rather than the group.
