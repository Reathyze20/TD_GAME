# 00 — Project Overview (read this first)

This document defines **what** we are building and **why**. Every other doc in `docs/core/`
(rendering, data resources, enemy/tower systems, building & grid, etc.) describes **how** — and
must stay in service of the theme and pillars below. Before designing or implementing any enemy,
tower, wave, effect, map, or piece of text, internalize this.

## North star

A small, polished, **snappy tower-defense game in Godot 4.7 (GDScript)** — in the spirit of
*Sir We Have an Orc Problem*, with **maze paths** — that **teaches players how their attention
gets hijacked**: the neuroscience of dopamine, the attention economy, and "digital obesity"
(overconsumption of cheap digital stimulation). It teaches **through fun, well-designed levels,
not lectures.**

## Design pillars (the idea)

1. **Fun first, lesson second.** If a level isn't fun, the lesson doesn't land. Nail a clean,
   satisfying TD loop, then let the theme ride on top of it.
2. **Teach through MECHANICS, not text.** The systems themselves embody the concepts. Text is a
   garnish, not the meal.
3. **Two teaching channels:** (a) the mechanics, and (b) short "insight" cards between levels,
   each tied to what the player just experienced.
4. **Non-preachy, evidence-based, concise.** No moralizing. 1–2 sentences per idea. All
   player-facing text is in **English**.

## Theme mapping

Map every generic TD object to the theme. **Do not** use orcs/trolls/goblins or generic
"archer/cannon" towers — use the themed set in the next section.

| Generic TD           | This game |
|----------------------|-----------|
| Castle / base life   | **Focus Meter** — the player's attention; drains when distractions get through |
| Enemies              | **Digital distractions** marching toward your focus |
| Towers               | **Healthy habits** that defend attention |
| Gold / currency      | **Dopamine** — earned by defeating distractions |
| Walls / maze terrain | **Structure & boundaries** — the fixed "high ground" you build habits on |

## Vocabulary (shared across all docs)

Every other doc uses these terms. **Two layers, and the split is deliberate** (`Data.TERM` is the
single source of truth for the player-facing layer):

- **The NOUNS carry the theme** and are player-facing: Habit, Distraction, Dopamine, Focus,
  Insight, Tolerance, Quick Hit, Routine, Anchor. A player picks these up from context in one level.
- **The MECHANICS use the words every tower-defense player already knows** in all player-facing
  text (cards, panels, tooltips): *damage, mind damage, armor, slow, damage over time*. The bespoke
  names below survive as **internal/code names only** (`willpower_damage`, `apply_reframe`, …) —
  showing them to the player cost a translation step on every card, mid-fight, and paid nothing
  back.

| Concept | Code name (internal) | Player sees (`Data.TERM`) | Generic TD equivalent |
|---|---|---|---|
| Currency | Dopamine | **Dopamine** | gold |
| Base health | Focus | **Focus** | lives / base_health |
| Overuse penalty (0–100) | Tolerance | **Tolerance** | — (our mechanic) |
| Instant-currency button | Quick Hit | **Quick Hit** | — (our mechanic) |
| Enemy | Distraction | **Distraction** | enemy / orc |
| Tower | Habit | **Habit** | tower |
| Blocker unit | Ally (from *Accountability*) | **Ally** | barracks soldier |
| Buildable + blocking terrain | High ground | (terrain, unnamed) | build spot / wall |
| Direct damage | Willpower damage | **damage** | physical |
| Mindful damage | Awareness damage | **mind damage** | magic |
| Flat resist vs Willpower | Compulsion | **armor** | armor |
| Resist vs Awareness | Rationalization | (folded into **armor** on cards) | magic resistance |
| Slow | Calm | **slow** | slow |
| Damage-over-time | Boredom | **damage over time** | poison / burn |
| Strip resistances | Reframe | **−armor** | armor shred |

## Canonical content (keep ids/names consistent)

**Enemies (distractions):**
- `notification` — fast, weak, swarms (the ping that yanks your attention)
- `autoplay` — medium, spawns in bursts (the "next episode" auto-roll)
- `doomscroll` — slow, tanky, high value (the endless feed)
- `phantom_buzz` — **flying**; ignores the maze and Allies entirely, flies straight at Focus (the
  urge that comes from inside, not through the device). Level 2 only. See `04`.
- Room to add: `clickbait`, `streak`, boss `the_algorithm` / `infinite_feed`

**Towers (healthy habits):**
- `focus_timer` (Pomodoro) — cheap, reliable single-target
- `mindfulness` (breathing) — AoE + slow + **Reframe**; sets up every other habit
- `exercise` (movement) — big hits, slow cadence
- `real_hobby` — long range, light damage, applies **Boredom** (DOT that ignores both resistances)
- `accountability` — barracks; trains Allies that block distractions (`06`)
- Room to add: `sleep` (slow aura)

**Currency:** Dopamine. **Base life:** Focus.

## Signature educational mechanics (these ARE the lesson — implement them faithfully)

1. **Dopamine as currency.** You earn dopamine by defeating distractions and spend it to build
   habits — mirroring how the brain's reward signal is *earned and spent*.
2. **Tolerance + "Quick Hit."** An optional button grants instant dopamine but raises a
   **Tolerance** meter; higher tolerance = smaller future rewards (downregulation). Lesson:
   *cheap, instant dopamine is borrowed — you pay it back with tolerance.* Introduced on level 2.
3. **Burnout.** Every distraction that reaches the core raises a **Burnout** meter by
   `3 × focus_damage`, so the size of the leak is what counts, not the count. Past 50 the
   picture trembles; past 75 habits start losing ticks to *procrastination* (they get the
   disruptor's `disrupt()` treatment, named on-screen so it isn't mistaken for an enemy
   ping). It decays slowly during play. Lesson: *attention debt compounds — being
   overwhelmed is what makes you worse at not being overwhelmed.*
   Deliberately a **second meter** rather than more Tolerance: Tolerance is the price of
   *taking* rewards, Burnout the price of *letting things through*, and one number could
   not teach either.
4. **Maze of habits.** Enemies pathfind around **fixed high ground**, and that high ground is the
   **only** place towers can be built. Structure and boundaries are what let habits actually
   defend your attention.
5. **Insight cards between levels.** After each level, one short card ties a real concept
   (variable-ratio reinforcement, the attention economy, digital "obesity"/tolerance) to what the
   player just did.

## Constraints

- Engine: **Godot 4.7, GDScript**, data-driven (Resource/`.tres` — e.g. `EnemyData`, `TowerData`,
  `WaveData`; see `02_data_driven_resources.md`).
- When defining any enemy/tower/wave/effect Resource, give it a themed `id`, `display_name`, and a
  one-line `description` that reinforces the concept above.
- Scope: a small, winnable, easily-tuned prototype — start with 2 levels.
- All player-facing text in **English**, short and concrete.

**Rule of thumb:** if a feature doesn't make the game more *fun* **or** teach one of these ideas
more clearly, cut it.

## Document map

The docs below describe the **target ("complex") architecture**. Each one ends with an
**"Intersection with the prototype"** note that maps it to what already exists in `scripts/`
(`game.gd`, `enemy.gd`, `tower.gd`, `data.gd`, `game_state.gd`) and flags MVP vs. target.

**Read the "Pilot status" column before the topic column.** The doc numbering (01–13) implies a
build order, but the real, code-verified status doesn't follow it. Every gameplay system in the set
is now built; the only outstanding row is `01` (2.5D rendering), which is deliberately deferred —
flat `_draw()` shapes are the pilot's art style, and `01` is what the remaining unchecked boxes in
`06` and `12` are waiting on:

| Doc | Topic | Themed highlights | Pilot status |
|---|---|---|---|
| `01_rendering_and_depth` | 2.5D Y-sort, Z-index layers | distraction/habit sprites, shadows, feet-at-origin | **Partly done** — `Entities` Y-sort container, explicit CanvasLayer order, 2D MSAA, glitch shader and Dopamine particles all landed. Sprites, shadows and `TileMapLayer` still wait on actual art; see its Intersection section |
| `02_data_driven_resources` | `.tres` data containers | `DistractionData`, `HabitData`, Willpower/Awareness | **Done**, as `const` dicts in `data.gd`, not `.tres` |
| `03_global_state_and_signals` | `SignalBus` + `GameState` | Dopamine, Focus, Tolerance, Quick Hit | **Done** via `GameState`; `SignalBus` is now fully active and routing events (e.g. wave completion, game over). |
| `04_enemy_system_and_pathfinding` | distractions + **maze A\*** | `AStarGrid2D`, spawn zones, swarm scatter | **Done** for the pilot; `StatusManager` and `is_blocked` logic are now fully implemented and active. |
| `05_tower_system_and_targeting` | habits, targeting, projectiles | Willpower vs Awareness, Calm/Interrupt/Reframe | **Done** — `BaseHabit`/`Habit`/`Barracks` hierarchy and `AttackComponent` are fully implemented, tracking the target architecture exactly. |
| `06_barracks_and_soldier_mechanics` | **Accountability → Allies** | blocking distractions in the maze | **Done** — `Barracks` properly inherits `BaseHabit` and manages ally spawning, tracking the architecture. |
| `07_building_system_and_grid` | high-ground build spots | build/upgrade/sell, preview highlight | **Done**, including upgrade/sell/re-aim — more complete than this doc used to claim |
| `08_wave_manager` | waves, Quick Hit, insight cards | spawn batches from zones, tolerance windows | **Done**; shipped insight cards teach different topics than this doc's examples |
| `09_hud_and_ui` | reactive HUD, pause, menus | Dopamine/Focus/Tolerance readouts | **Done**, code-built (no `.tscn`) |
| `10_modifier_and_card_system` | roguelike card drafting | themed buff cards, `ModifierManager`, habit stat recalc | **Done** — fires once per level before the final wave (previously unreachable; see its Intersection section) |
| `11_meta_progression_and_save` | **Growth Tree** + save | Clarity Stars, permanent upgrades, `SaveGame` resource | **Done** — save file genuinely persists across runs |
| `12_player_abilities` | active **interventions** | Screen Break, Deep Breath, Call a Friend | **Done** — all three work; Call a Friend summons temporary `06` Allies |
| `13_hud_and_ui` | extended UI (draft, abilities, tree) | DraftScreen, intervention buttons, Growth Tree UI | **Mostly done** — buttons, draft screen, and Growth Tree screen all work |
| `14_brain_fog_and_bandwidth` | **Brain Fog** + build capacity | darkness = unexamined day, light = Routine, Attention Bandwidth cap, Moment of Clarity | **Done** — fog shader + lit-cell rule, Routine build gate, Bandwidth economy, 5th intervention; balance sweep pending |
| `15_cast_shadows` | Real `Light2D` + `LightOccluder2D`, separate from Brain Fog | a lamp's glow stopping at a wall — core/Anchors/built habits only, reusing `14`'s radii | **First pass, OFF by default** — `Game.shadow_enabled`; measured cost ≈0.45ms isolated, noise-level under a full horde; not yet reviewed for the shipped look |

> **The one hard reconciliation:** the raw drafts assumed a **fixed `Path2D` curve**. We do
> **open maze pathfinding with `AStarGrid2D`** instead (enemies route around fixed high ground).
> Docs 04, 06, and 08 are written for the maze model; ignore any leftover "curve" phrasing.
