# Game Design — TD Project

> **Ground truth for AI tooling (MCP / codegen).** This is the single file to load before
> generating or judging any gameplay content — a new enemy, tower, wave, card, intervention,
> level, or piece of player-facing text. It is a condensed, current snapshot; the full
> reasoning lives in `docs/core/00_overview.md` (design pillars, deep dive) and
> `docs/design/dopamine_mechanics.md` (the psychology behind every meter). If this file and
> a deeper doc disagree, **prefer this file for facts about shipped scope**, but read the
> deeper doc before writing new mechanics — it explains *why*, and *why* is what keeps new
> content from drifting off-theme.

## What this is

A small, snappy **tower-defense game in Godot 4.7 (GDScript)** — in the spirit of *Sir We
Have an Orc Problem*, with **maze paths** — that teaches players how their attention gets
hijacked: the neuroscience of dopamine, the attention economy, and "digital obesity"
(overconsumption of cheap digital stimulation).

It teaches **through fun, well-designed levels, not lectures.** All player-facing text is in
**English**, short, concrete, and non-preachy. Target length: **5–8 levels, ~90 minutes.**

## Design pillars (non-negotiable)

1. **Fun first, lesson second.** If a level isn't fun, the lesson doesn't land.
2. **Teach through MECHANICS, not text.** The systems embody the concepts; text is garnish.
3. **Two teaching channels:** the mechanics themselves, and short "insight" cards between
   levels tied to what the player just experienced.
4. **Non-preachy, evidence-based, concise.** No moralizing, 1–2 sentences per idea.
5. **The game never diagnoses the player.** It shows behavior; the player draws the
   conclusion. Copy never says "should", "too much", or grades the player (see §Copy rules).
6. **No generic fantasy skins.** Do not use orcs/trolls/goblins or generic "archer/cannon"
   towers — every object must map onto the theme below.

## How you play (the loop)

- You defend the **Focus core**. When distractions reach it, Focus drops; at 0 Focus you
  lose the level.
- **Distractions** spawn from fixed spawn zones and pathfind (`AStarGrid2D`) toward the
  core, routing around **high ground** — the only place you can build.
- Between/during waves you spend **Dopamine** (earned by defeating distractions) to build
  **Habits** (towers) on high ground, forming a maze that shapes the enemy path.
- Build spots are **3×3 cell blocks**, keyed by the block's center cell
  (`Data.build_block()`); you don't build tower-by-tower on a fine grid, you build blocks.
- A level ends when its final wave (often a boss) is cleared. Losing all Focus ends the run.
- **Once per level**, before the final wave, a roguelike **card draft** offers a themed
  stat buff (`ModifierManager`).
- After each level, a short **Insight card** ties a real, citable concept (Schultz, Berridge,
  Volkow, Kahneman & Tversky, Salamone, Solomon & Corbit — always named, always checkable)
  to what the player just did. Never a moral, always a mechanic they just felt.
- Between runs, permanent upgrades are bought on the **Growth Tree** with **Insight**
  currency (meta-progression, persists via `SaveGame`).

## Theme mapping (canonical — do not deviate)

| Generic TD          | This game                                                                       |
|----------------------|---------------------------------------------------------------------------------|
| Castle / base life   | **Focus** — the player's attention; drains when distractions get through       |
| Enemies              | **Distractions** — digital noise marching toward Focus                         |
| Towers               | **Habits** — healthy routines that defend attention                            |
| Gold / currency      | **Dopamine** — earned by defeating distractions                                |
| Walls / maze         | **High ground** — the fixed structure you build habits on                      |
| Barracks / soldiers  | **Accountability** habit → trains **Allies** that block distractions           |

Two bespoke mechanics sit on top with no generic-TD equivalent: **Tolerance** (an overuse
penalty) and **Quick Hit** (an instant-currency button that raises it).

## Vocabulary — two layers (read before writing any card/tooltip text)

The split is deliberate. **Nouns carry the theme** and are what the player learns from
context in one level (Habit, Distraction, Dopamine, Focus, Insight, Tolerance, Quick Hit,
Routine, Anchor). **Mechanics use words every TD player already knows**, in all
player-facing text — cards, panels, tooltips, floating combat text:

| Concept | Internal/code name | Player sees (`Data.TERM`) | Generic TD equivalent |
|---|---|---|---|
| Currency | Dopamine | **Dopamine** | gold |
| Base health | Focus | **Focus** | lives / base_health |
| Overuse penalty | Tolerance | **Tolerance** | — (bespoke) |
| Instant-currency button | Quick Hit | **Quick Hit** | — (bespoke) |
| Enemy | Distraction | **Distraction** | enemy / orc |
| Tower | Habit | **Habit** | tower |
| Blocker unit | Ally | **Ally** | barracks soldier |
| Buildable + blocking terrain | High ground | (terrain, unnamed) | build spot / wall |
| Direct damage | Willpower damage | **damage** | physical |
| Mindful damage | Awareness damage | **mind damage** | magic |
| Flat resist vs Willpower | Compulsion | **armor** | armor |
| Resist vs Awareness | Rationalization | folded into **armor** on cards | magic resistance |
| Slow | Calm | **slow** | slow |
| Damage-over-time | Boredom | **damage over time** | poison / burn |
| Strip resistances | Reframe | **−armor** | armor shred |

Never show a code name (`willpower_damage`, `apply_reframe`, …) to the player — that
translation step costs nothing back mid-fight.

## Currencies & meters — what's live, what's aspirational

All of these are wired into `GameState` today (`scripts/game_state.gd`); "shipped" means
the core number and its trigger exist, not that it's fully balanced.

| Meter | What it is | Channel it owns (see §5) | Status |
|---|---|---|---|
| **Dopamine** | Currency, earned on kill, spent to build/upgrade | HUD number | Shipped |
| **Focus** | Base health | HUD number | Shipped |
| **Tolerance** (0–100) | Cost of *taking* cheap reward (Quick Hit); higher = smaller future rewards | color/saturation (desaturate + compress toward mid-tone via `shaders/flatten.gdshader`) | Shipped |
| **Burnout** | Cost of *letting things through* — every leak adds `3 × focus_damage`; past 50 the screen shakes, past 75 habits stall (`disrupt()`) | camera (shake/blur) | Shipped |
| **Attention Bandwidth** (cap `BASE_BANDWIDTH = 120`) | Global build capacity; every standing habit reserves `bandwidth_cost`; a build that would overflow it is refused like an unaffordable one | HUD chip (held/cap) | Shipped |
| **Insight** | Meta-currency, earned per level cleared, spent on the Growth Tree | between-run screen | Shipped |
| **Rush** | Built from close-range kills, spends on interventions | HUD number | Shipped |
| **Streak** | Waves in a row with zero leaks; `+0.15` payout mult/wave, cap `×1.60`, breaks to 0 on any leak | floating text at the core (no sound — sound belongs to Novelty) | Shipped |
| **Craving** (wanting) / **Satisfaction** (liking) | Berridge's wanting≠liking split: Craving rises from Quick Hit/near-miss and makes you mechanically stronger; Satisfaction falls with it. They can diverge — powerful and empty at once | Craving = UI pulse tempo; Satisfaction = music layers | Shipped |
| **Conditioning** (cue) | Pavlovian: a blue-flash cue that once predicted a reward keeps tugging at attention even after Tolerance is back to zero. Deliberately **not** reset per level | UI flash pull/duration | Shipped |
| **Familiarity / novelty tax** | Per-tower-type kill counter; reward juice scales with surprise, not just `1 - tolerance` | kill sound | Shipped |

**Brain Fog & Routine** (shipped 2026-08-16): the field is dark outside light cast by the
Focus core, established **Anchors**, and working habits/defenders. Three rules read as one
picture: *build only in the light, fight only what the light touches, hold only so much at
once (Bandwidth)*. A habit that falls out of Routine goes dark and stops firing at the same
moment. See `docs/core/14_brain_fog_and_bandwidth.md`.

**Living map — trods** (shipped 2026-08-21): a `TrodData` can cheapen an off-lane route to
1.0 at a specific wave, turning a detour into the preferred path mid-level — telegraphed one
wave ahead. It never removes a path (unsolvable levels can't happen) and the new route must
overlap the old one within tower range, or the player's earlier build was wasted for nothing.
See `docs/core/17_living_map.md`.

## Content roster

The authoritative, always-current list is **generated from `data/*.tres`** — run
`python tools/roster.py --md > docs/ROSTER.md` and read that file for exact numbers
(HP, speed, damage, cost, range, cooldown). Do not hand-maintain a duplicate list here — it
has gone stale three times before. Summary of what exists today:

- **Distractions (enemies):** `notification`, `autoplay`, `doomscroll`, `clickbait`,
  `group_chat`, `energy_drink`, `jackpot`, `adult_content`, `phantom_buzz` (flying, ignores
  the maze and Allies), and boss `social_media_binge`.
- **Habits (towers):** `focus_timer`→`focus_timer_2` (Pomodoro, cheap single-target),
  `mindfulness`→`mindfulness_2` (AoE + slow + Reframe), `exercise`→`exercise_2` (big hits,
  slow cadence), `real_hobby`→`real_hobby_2` (long range, Boredom DoT), `accountability`→
  `accountability_2` (barracks, trains Allies), `zen_pulsar`→`zen_pulsar_2a`/`2b` (AoE stun +
  dispel), `anchor` (extends Routine light), `focus_pillar` (landmark, iso).
- **Interventions (active abilities):** `airplane_mode` (freeze field), `call_a_friend`
  (summon temporary Allies), `deep_breath` (freeze AoE), `screen_break` (damage AoE),
  `moment_of_clarity` (lifts fog for 6s).
- **Distraction archetypes** (reusable behavior flags on `DistractionData`, not
  inheritance): `fleeting` (expires, does 0 Focus damage — its cost is your attention, not
  your base), `splitter` (dies into smaller copies), `autoplay` (steals the next prep phase
  if not killed in time), `adaptive` (copies your strongest habit's stats).

## Level structure & progression

- Levels are data-driven `LevelData` resources under `data/levels/`, authored **natively in
  the Godot editor** via `scenes/MapEditor.tscn` + the `td_level_designer` dock, then baked.
  See `docs/EDITOR_GUIDE.md`.
- Waves come from `WaveData`/`WaveCurveEntryData`, spawned from `spawn_zones` into the maze.
- `lean_waves` levels remove Quick Hit and let Tolerance decay — used for the deliberate
  "fasting level" arc (worst-feeling for ~2/3 of its length, recovers by design; see
  `docs/design/dopamine_mechanics.md` §5.8).
- The campaign finale is envisioned as an unkillable, endless lane ("The Feed") whose win
  condition is holding the line **hands-off for 30 seconds** — not a kill count. Confirm
  against `dopamine_mechanics.md` §5.10 before implementing; not yet fully shipped.

## Copy rules (apply to every card, tooltip, insight, and UI string)

| Never | Always |
|---|---|
| "You used Quick Hit too many times! Try using it less." | "Quick Hits used: 9. Average reward per hit: 3.2 (started at 15)." |
| "You should pay more attention." | "Fake notification: 0.3s. Real threat: 1.8s." |
| "Good job!" / "You failed" | (say nothing) |

- Never the word "should". Never "too much". Never a grade.
- Insight cards must cite real, checkable research — a name and a year, not vibes.
- No leaderboard, no ranking. One deliberate friction point: no "next level" auto-advance —
  the player returns to menu between sessions.
- All telemetry stays local, and the game says so explicitly where relevant.

## World / theme status — read before generating any new lore or names

- **Canon theme is the neuroscience/attention-economy framing** in the table above (Focus,
  Dopamine, Distraction, Habit) — this is what all shipped content uses.
- **`docs/design/fae_theme.md` ("Podměsíčí") is retired** (decided and shelved the same day
  it was adopted, 2026-08-21). Its folklore names (Wisp, Hob, the Trod-as-proper-noun, Glimmer,
  Hearth, etc.) are **historical record only — do not use them for new content.** The one
  surviving artifact is the `TrodData` class name (kept because it describes the mechanic
  fine on its own), whose *documentation* should still use the neuroscience framing.
- The isometric board's visual theme is **"Deep Focus: Cortex Terrace"** — a neuroanatomical
  metaphor (grey-matter tissue, dopamine pathway, myelin terrace, bioluminescent habit
  growths). This is a **visual/art** direction layered on the same canon theme above, not a
  competing world. Full detail in `docs/art_style.md` and `docs/art/iso_bible.md`.

## Current build status (this branch, `feat/iso-slice`)

- An **isometric vertical slice is now the live rendering/grid model** — `Data.cell_center()`
  / `world_to_cell()` compute a native 2:1 diamond projection unconditionally (no top-down
  branch left in the coordinate math).
- The original **top-down levels (`level_1`, `level_2`) are currently unplayable** — they
  hold ~8,000 hand-placed pixel coordinates tuned for the old square-grid formula, which no
  longer applies. They have not been converted; see `docs/core/16_isometric_slice.md`.
- Playable isometric content lives in `data/levels/level_iso.tres` /
  `level_iso_1.tres`, exercised via `scenes/_play_iso.tscn`, `_play_trod.tscn`,
  `_play_campaign.tscn`.
- Deliberately **out of scope for the slice** so far: barracks/defender formation polish,
  full intervention art, cards & draft UI in iso, bosses, cast shadows, a second iso level,
  and the level editor's live iso preview (it still computes its own step size and can
  silently disagree with the real game — verify visually, don't trust the editor preview).
- Range/radius semantics in isometric (`docs/core/16_isometric_slice.md` §9: should a 300px
  range be a screen circle or a ground-plane ellipse?) is an **open gameplay decision** —
  check current code before assuming either answer.

## Where to go deeper

- `docs/core/00_overview.md` — pillars, full vocabulary table, doc map with per-system
  "pilot status" (what's actually built vs. planned, system by system).
- `docs/design/dopamine_mechanics.md` — the psychology behind every meter above, in full,
  including mechanics not yet summarized here (novelty tax, negative RPE bonus wave,
  variable-ratio payout, effort discounting, ad parody design, telemetry).
- `docs/core/14_brain_fog_and_bandwidth.md`, `docs/core/17_living_map.md` — the two newest
  systems, in full.
- `docs/ROSTER.md` — generated, exact current numbers for every habit/distraction/intervention.
- `docs/core/16_isometric_slice.md` — the iso migration plan and what's known-stale.
