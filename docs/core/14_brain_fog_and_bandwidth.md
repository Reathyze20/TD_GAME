# 14 — Brain Fog & Attention Bandwidth

> Theme reminder (see `00_overview`): the player defends **attention**. Darkness on this
> map is not weather — it is *brain fog*, the unexamined part of your own day. Light is
> not a torch — it is your **Routine**, and it reaches exactly as far as the structures
> you have actually built. The same nouns the game already speaks: Focus, Routine,
> Anchor, Insight.

## The two mechanics, and why they are one system

**Brain Fog** covers the whole field in purple-black darkness. The Focus core lights a
circle around itself; every established Anchor lights its own circle; working habits and
defenders carry small lamps. Everything else is dark, and *what stands in the dark
cannot be seen — or hit*.

**Attention Bandwidth** is the global build capacity: every standing habit occupies part
of it (`HabitData.bandwidth_cost`) and a build that would overflow the cap is refused
outright, exactly like an unaffordable one.

They are one system because **the light IS the Routine**. The core's light radius is
`CORE_ROUTINE_RADIUS` (330), an Anchor's is `ANCHOR_ROUTINE_RADIUS` (260) — the same
constants the Routine chain has always used. So the three rules the player learns read
as one picture:

1. **You can only build in the light** (the Routine build gate).
2. **You can only fight what the light touches** (the fog visibility rule).
3. **You can only hold so much at once** (the Bandwidth cap).

A habit that falls out of Routine *goes dark in both senses*: it stops firing (as
before) and its lamp goes out, so the darkness closes over it on screen at the moment it
stalls. "Zhasnou" is literal.

### The teaching frame — and one deliberate refusal

Bandwidth is a **capacity of commitments, not a fuel tank**. The HUD deliberately shows
`held / cap` and the number never moves on its own — it changes only when the player
takes on a habit or lets one go. This game explicitly refuses the ego-depletion model
(willpower as a resource that drains; see the HUD comment in `game.gd:_build_hud`), and
a leaking attention meter would have taught exactly that. "You cannot hold twelve new
practices at once" is the defensible, evidence-aligned version — cognitive *bandwidth*
in the Mullainathan & Shafir sense, which is also why the stat is named Bandwidth and
not another overload of Focus or Attention.

## Rules reference (as shipped)

### Brain Fog
- **Visual**: one full-screen rect (`Z_FOG = 60`, canvas 0 — the glitch shader still
  distorts it) with `shaders/brain_fog.gdshader`; holes come from a half-res SubViewport
  light mask into which `LightMaskCanvas` draws every light as an additive radial sprite.
  **No `Light2D` anywhere** — projectiles glow too, and 500 canvas lights on the Mobile
  renderer is the expensive way to say "1 minus a texture".
- **Gameplay**: `Game._lit_cells` is rebuilt every frame from the *sight* sources — core,
  established Anchors, working habits (`TOWER_LIGHT_RADIUS = 150`), defenders (90).
  Projectile light is shine, not eyes: a stream fired into the dark must not scout it.
- **`Game.is_pos_visible(pos)`** is the one O(1) predicate, honoured at the three places
  a hit is actually decided (suppression has no target selection to filter):
  - `Habit.is_point_in_cone()` — AoE pulses and the Pomodoro work check;
  - `Projectile._process()` hit loop — a shot passes **through** a fogged body (fog is
    absence of sight, not a wall; only walls stop shots);
  - `board_live` via `Game.has_visible_distraction()` — a board where everything alive
    is hidden counts as empty, and towers hold fire.
- The wedge preview stays geometric (walls clamp it, fog does not) — fog moves with the
  fight, and a preview flickering with every defender step would read as a glitch.
- Enemies **never** emit light. They are the dark arriving.

### Attention Bandwidth
- `GameState.BASE_BANDWIDTH = 120`, raised permanently by the Growth Tree node **Room to
  Grow** (`data/growth/room_to_grow.tres`, +25/rank, 2 ranks, Awareness branch).
- Reserve on build, **delta** on upgrade (the old tier's hold transfers), release **in
  full** on sell and on an aiming-cancel rollback — it mirrors *reserve*, not *spend*,
  which is why selling returns 100% of Bandwidth but only 50% of Dopamine.
- Both build costs are gates that abort before anything is created (Bandwidth checked
  first, Dopamine spent second, Bandwidth reserved last — a refusal on either leaves
  both untouched).
- Costs as shipped: Anchor 3 · Focus Timer/Mindfulness 8 · Exercise/Real Hobby/Zen
  Pulsar 10 · Guild 12 · tier 2 = +4. First-pass numbers, expect a balance sweep.

### Routine build gate
- `Game._can_build()` now also requires the cell inside `_routine_sources` (cached each
  frame by `_update_routine_reach`). `_build_on` calls it, so preview tint and the
  actual gate can never disagree. The old freedom ("place, extend the Routine, move
  on") is gone on purpose: it put the Anchor lesson *after* the money was spent.
- The Nutrition Guild now honours `in_routine`: out of Routine the kiosk dims, flashes
  `⚠ NO ROUTINE`, and **fallen slots do not respawn** until the connection returns.
  Live defenders keep fighting — they are out of the pantry and on their own legs — so
  the cost of a cut-off guild is that its line, once broken, stays broken.

### Moment of Clarity (new intervention)
- `data/interventions/moment_of_clarity.tres`: `type = "reveal_field"`, 6 run-Insight,
  40s cooldown, lifts the fog everywhere for 6s (hotkey **T**). The reveal timer runs on
  *wave* time, so a between-waves cast holds until the fight starts.
- `InterventionData.insight_cost` is a general field with the same double-gate contract
  as `rush_cost`. Taxonomy note for `12`: this bends "Insight = permanence" into
  "understanding spent for advantage now" — same trade as draft cards, made sharper.

## Intersection with the prototype

Shipped 2026-08-16, all headless harnesses green (`_test_fog_bandwidth.gd` is the
dedicated coverage; the eight older harnesses run with `game.fog_enabled = false` and
`game.routine_gates_enabled = false`, because they test other systems).

Supersedes, in part: `05`'s "fires continuously with nothing in the cone" (still true in
the lit field; a fully fogged board now holds fire), `07`'s "high ground is the only
build rule", and the doc-map row for `12` (five interventions now). `EDITOR_GUIDE.md`'s
metric "spots in core Routine 12–20" is now load-bearing for the *opening* of every
level: the first towers can only stand in the core's light.

## Implementation checklist
- [x] Fog shader + light-mask SubViewport, screen-aligned, shake-safe
- [x] Lit-cell grid + `is_pos_visible` at all three combat sites
- [x] Routine build gate shared by preview and build
- [x] Bandwidth reserve/delta/release across build, upgrade, sell, aiming-cancel
- [x] Guild respawn stall out of Routine
- [x] Moment of Clarity + `insight_cost` plumbing + hotkey T
- [x] Room to Grow growth node (+25/rank)
- [x] HUD chip (held/cap, hot when nearly full), build-bar affordability + tooltips
- [ ] Balance sweep: bandwidth costs vs. real builds on levels 1–2
- [ ] Fog-aware level design: dead-end branches, props in the dark (`level-design`)
- [ ] Sound: a hush when the fog closes over a stalled habit?
- [ ] `11`/`12` doc reconciliation (Clarity Stars → Insight; five interventions)

## Tunables (one place each)
`game.gd`: `FOG` block — `TOWER_LIGHT_RADIUS`, `DEFENDER_LIGHT_RADIUS`,
`PROJECTILE_LIGHT_RADIUS`, light falloff (`LightMaskCanvas.light_tex`, flat to 62%).
`shaders/brain_fog.gdshader`: `fog_color`, `fog_alpha` (0.88), clear/penumbra band
(`smoothstep(0.10, 0.72, lit)`). `GameState.BASE_BANDWIDTH`; per-habit costs in
`data/habits/*.tres`.
