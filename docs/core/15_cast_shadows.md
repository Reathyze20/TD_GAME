# 15 — Cast Shadows (Light2D)

> **Dodatek 21. 8. 2026 — iso deska má vlastní, JINÝ stín.** Světlo, které dělá Rogue
> Tower, není Light2D: jsou to **vržené stíny na plochou zem**. Ploché plochy čtou jako
> těleso proto, že vrhají stín, ne proto, že mají texturu. Proto přibyl
> `Game.TerraceShadow` — statický kontaktní stín terasy v iso prostoru, který s tímhle
> dokumentem nesdílí ani řádek kódu.
>
> `WallShadow` popsaná níž je psaná pro **čtvercovou** mřížku (slučuje vodorovné běhy,
> kreslí `draw_rect`), takže na kosočtvercové desce by kreslila obdélníky napříč mřížkou.
> `TerraceShadow` je táž myšlenka přeložená do iso: místo obdélníku kosočtverec, místo
> „jižní hrany" posun o buňku ve směru `TERRACE_SHADOW_DIR`.
>
> **Směr stínu a stínovaná stěna terasy si musí odpovídat.** Bible má světlo zleva (levý
> bok 70 %, pravý 45 %), takže stín padá na +x. Když se jedno otočí, musí se otočit obojí.
>
> **A jedna věc, kvůli které to teprve teď dává smysl:** playtest 18. 8. zamítl Light2D
> verzi mimo jiné proto, že „textury čtou jako rozbité". Terén od 21. 8. žádnou texturu
> nemá (`docs/art/iso_bible.md` kap. 2b), takže ten konkrétní důvod zanikl. Jestli by
> Light2D verze na ploché desce obstála, **není změřeno** — `shadow_enabled` je na iso
> levelech pořád `false` a tenhle dodatek to nemění.
>
> Síla a délka: `TERRACE_SHADOW_STEPS` (dnes `[0.55, 0.26]`, tedy dvě buňky).


> Theme reminder (see `00_overview`): Brain Fog (`14`) is the macro question — *what can
> you see at all*. This doc is the micro one — *given that you can see it, how does the
> light actually fall across the room*. Same world, two different jobs, two different
> systems on purpose (see below).

## Why this is NOT the same system as Brain Fog

`14` wrote down a deliberate, load-bearing decision: **no `Light2D` anywhere**, because
Brain Fog counts every light source — including up to ~500 live projectiles, which glow
cosmetically — and a real `Light2D` per source would mean up to 500 shadow-casting canvas
lights on the **Mobile** renderer (`project.godot`: `renderer/rendering_method="mobile"`,
the shipped/target renderer, not a hypothetical one). That decision still stands and this
feature does not reopen it: Brain Fog still has no `Light2D`, still works exactly as `14`
describes, and still pays for hundreds of lights the same cheap way — one SubViewport
mask, `1 - texture`.

What changed is that a *different, much smaller* question showed up: does the maze ever
look like it has real depth, with a lamp's glow actually stopping at a wall? Fog cannot
answer that — it is a flat "hole punched in the dark," not a directional light. The two
systems solve different problems and are built, toggled, and measured independently.

## Playtest round 2 (2026-08-18): what the first pass got wrong, and what was actually true

The first pass (below) shipped `shadow_enabled` OFF, verified only by an isolated demo
scene (`_shot_shadows.gd`'s own build) and a geometric correctness test — not by looking
at it inside a real, ongoing game. A live playtest with `shadow_enabled` flipped on found
it "hrozný" (terrible): map textures read as "rozbité" (broken), and the shadows "didn't
make much sense." **The individual habit lamp (`TOWER_LAMP_RADIUS`) was explicitly called
out as working and to be kept as-is.** Two hypotheses were raised for the two complaints —
both investigated on the actual occluder/render geometry, not the screenshot alone, per
this project's own measurement discipline. One was confirmed and fixed outright; the
other pointed at the wrong mechanism but led to a real fix anyway.

**Hypothesis: core/Anchor read as a floodlight, not a lamp — CONFIRMED AND FIXED.**
`_shadow_light_tex()`'s one shared curve (flat to 55% of radius, dark by 88%) was being
reused at the core's and an Anchor's much bigger gameplay radius (330 / 260 px vs the
habit lamp's 56). A flat zone that is a fixed FRACTION of radius does not stay lamp-sized
as radius grows: 55% of 330 is 182px of uniform full brightness — nearly the whole visible
circle — followed by a near-instant cliff in the last 12%. That is a dome, not a falloff,
and matches "a big diagonal hard edge across the screen" exactly. Fix: `SHADOW_CURVE_TIGHT`
(0.55, 0.88) stays the habit lamp's curve, untouched, because playtest explicitly said it
already works. A new `SHADOW_CURVE_WIDE` (0.17, 0.90) is used for the core and Anchors
only — a flat core sized to a roughly CONSTANT ~45–56px regardless of which of the two big
sources is lighting, with most of the remaining radius spent on a real gradual taper.
Gameplay radius/position are unchanged — only the visual falloff shape is now source-size-
aware. See "The light texture" below for the code.

**Hypothesis: occluder row-merge seams cause the "broken texture" banding — INVESTIGATED,
NOT THE CAUSE, but led to a real fix anyway.** The reasoning was sound in theory (separate
`LightOccluder2D` polygons that only touch, rather than being one shape, are a known
shadow-rendering seam risk) and the visual symptom matched (regular horizontal bands on a
tall wall, measured as three ~1px bright spikes at exact 16px/row intervals against a real
6-row wall on level 1, both numerically and in a zoomed screenshot). The row-only occluder
merge documented below was upgraded to a full 2D rectangle merge (`_build_shadow_occluders`
now merges a strip DOWN into the strip below it whenever their x-span matches exactly, so
a whole rectangular wall mass becomes one occluder — level 1 dropped from 48 occluders to
**8**) — a genuine improvement (fewer draw calls, more correct "one shape per wall mass"
geometry, and it measurably helped frame time; see Measured). **But re-measuring the exact
same wall after the merge landed showed the identical spike pattern, unchanged to four
decimal places.** Further isolation (re-testing with `shadow_enabled` fully OFF and no
light at all) showed the SAME spikes at the SAME magnitude — proving the artifact predates
this feature entirely and has nothing to do with `Light2D`, occluders, or the toggle.
`WallShadow`'s own per-cell south-shadow/side-AO strips were the next suspect (same
"many separate same-colour rects that only touch" shape, same 16px period) and were also
merged into runs (`WallShadow._draw()`, below) — a correct, worthwhile fix on its own
merits, but re-measuring afterward again showed the identical spikes, unchanged. Decor was
checked directly (`game.decor_layer._items`) and ruled out (zero props near the tested
cell). Terrain corner-tile variant boundaries were checked by coordinate and land at the
wrong rows to explain it. **Conclusion, stated honestly rather than papered over: this
specific banding is a real, small, pre-existing rendering artifact somewhere in the
base wall/floor render (not caused or fixed by anything in this feature, confirmed
present with the whole cast-shadow system off), most likely tied to how the corner-terrain
tileset or its neighbouring layers render at certain wall edges — narrowed but not fully
isolated in the time available.** Scanning many other wall columns across the map (see
Measured) found the same low-grade pattern recurring at a handful of other wall edges,
always at a similarly small magnitude (roughly +0.03–0.05 absolute brightness, on an
already-dark base) — never at the scale of the floodlight problem, and not something a
casual glance would catch even now (finding it took 3× zoomed screenshots and per-pixel
sampling). It reads as a separate, minor, pre-existing terrain-rendering follow-up item,
not a blocker for this feature — flagged below rather than left silently unmentioned.

## What casts light

Deliberately the **exact same set** that already feeds `Game._lit_cells` through
`_building_sight_lights()` (`14`): the Focus core, every established Anchor, and any
other built habit (Guild included) currently `in_routine`. Same positions, same radii —
`CORE_ROUTINE_RADIUS` (330), `ANCHOR_ROUTINE_RADIUS` (260), `TOWER_LAMP_RADIUS` (56, the
habit's own small tile-lamp, renamed from `TOWER_LIGHT_RADIUS` while adjacent code
changed — see the block comment above `has_visible_distraction` in `game.gd`) — reused,
not reinvented, so "what casts a shadow" and "what lights the fog" can never quietly
disagree.

Explicitly **not** lights, and not planned to become lights:

- **Projectiles.** `14`'s reasoning applies doubly hard once shadows are involved — a
  shadow-casting light recomputes its shadow map every frame, so 500 of them is a
  different order of cost than 500 additive sprites, not just "the expensive way to say
  1 minus a texture."
- **Distractions/defenders.** Enemies never emit light in `14` either ("they are the dark
  arriving"); defenders keep their fog lamp but do not get a physical one here.
- **Small decor**, for this first pass — `decor_layer.gd` props stay unlit-as-source and
  non-occluding.
- **A habit's WEDGE reach-light** — the extra light `14` gives a working habit down its
  firing lane, past the flat `TOWER_LAMP_RADIUS` circle. Shaping a `Light2D` texture into
  a rotated wedge that stays in sync with the arc dial is real extra work for an
  atmospheric first pass; every built habit still gets the flat circular lamp. Backlog
  item if the circle reads as too small once seen in motion.

Count is bounded by `GameState.BASE_BANDWIDTH` (120), not by wave/enemy count — there is
one `Light2D` per **built structure**, and the cheapest structure (an Anchor) costs 3
Bandwidth, so the hard ceiling is ~40 and a realistic mixed build lands around 15–20 (see
Measured, below).

## What casts shadows

`LightOccluder2D` geometry built once per level load, straight from `level.high_ground`
(`Game._build_shadow_occluders()`) — the same solid-cell dictionary `WallFace`/
`WallShadow` already read for their own cosmetic passes, reusing the codebase's
established "code draws wall geometry from the solid dict" pattern rather than
hand-authoring occluders.

One real difference from `WallFace`/`WallShadow`: those two only care about a wall mass's
**south-facing rim**, because that is the only side a top-down camera ever renders. A
light can sit on any side of a wall, so occlusion needs the wall's full footprint — every
`high_ground` cell contributes, not only ones with open floor to their south.

Two merges on top of "one occluder per solid cell": cells are run-length merged along
each row into horizontal strips, and a strip is merged DOWN into the strip below it
whenever the two share the exact same span — so a whole rectangular wall mass becomes
ONE occluder regardless of how many rows tall it is (level 1: **8 occluders**, down from
48 with row-only merging, down from thousands of fine `16px` cells). The row-only version
shipped first and was upgraded after the 2026-08-18 playtest round (see above) — not
because it turned out to be the cause of the banding that prompted the investigation
(it wasn't), but because "many separate polygons that only touch" is a real
shadow-rendering seam risk in general, and the full merge is strictly better geometry for
the same reason WallShadow's per-cell strips were also merged. Genuinely irregular wall
shapes (a row whose width doesn't match the row above it) still end as separate
occluders — a real limitation, not a bug — but this game's walls are built from uniform
`Data.BUILD_BLOCK` unions, so most wall masses merge into a single rectangle in practice.

Decorations and entities never occlude — only static `high_ground` geometry does, built
once and never touched again. A tower does not cast a shadow onto its neighbour.

## The light texture, and why its curve is not copied from Brain Fog

`Game._shadow_light_tex(flat_frac, dark_frac)` bakes a 128×128 radial gradient (same
resolution as `LightMaskCanvas.light_tex()`, a size already validated in this project for
this exact purpose) with its own channel convention, because it feeds a different
consumer:

- `LightMaskCanvas` bakes brightness into RGB and pins alpha to 1, because a **custom
  shader** reads its `.r` channel straight off a `SubViewport`.
- A real `PointLight2D` texture instead follows Godot's own convention — a white cookie
  shaped by **alpha** — so this writes the same value into every channel and lets
  whichever one the engine samples carry the falloff.

Both curves are **tighter** than the fog mask's (flat to 62%, soft out to 100%): this
texture renders straight into the visible scene at `TEXTURE_FILTER_NEAREST`, not sampled
by a shader, so a long soft tail would be exactly the "blurry glow that sticks out against
flat pixel art" the render-fx brief rules out.

Since the 2026-08-18 playtest round (see above), `flat_frac`/`dark_frac` are **not one
shared constant** — cached per distinct pair, since only two are ever requested:

- `SHADOW_CURVE_TIGHT := (0.55, 0.88)` — the habit lamp's curve, **unchanged from the
  first pass on purpose**: playtest explicitly said this one already works. Flat to 55%
  of the light's own radius (≈31px at `TOWER_LAMP_RADIUS`), fully dark by 88%.
- `SHADOW_CURVE_WIDE := (0.17, 0.90)` — the core's and every Anchor's curve. Flat only to
  17% of radius (≈45px at an Anchor's 260, ≈56px at the core's 330 — both close to the
  habit lamp's own ~31px rather than 5× it), with the remaining ~73% of the radius spent
  on an actual gradual taper instead of a near-instant cliff.

`_make_shadow_light(radius, curve := SHADOW_CURVE_TIGHT)` picks the curve by caller;
`_build_shadow_light_layer()` passes `SHADOW_CURVE_WIDE` for the core, and
`_sync_shadow_lights()` picks per-spot based on `h.type_key == ANCHOR_HABIT`, re-checked
every sync (not cached at creation) so an upgrade that changes what a spot holds can never
leave a stale curve/texture behind. `shadow_filter` is `SHADOW_FILTER_NONE` (hard-edged)
for both curves, same "no soft blur" reasoning.

`SHADOW_LIGHT_ENERGY` is `0.3`, tuned down from an initial `0.45` after a real,
measured problem: the lamp's flat core has *no* falloff at all inside 55% of its radius,
so two overlapping flat cores (an Anchor built near the core is the common case) add
their full energy with zero softening. At `0.45`, two-plus sources overlapping near a
start-of-game cluster clipped to pure white — a flare, not a reading lamp. At `0.3`, a
2-source overlap lands at 0.6 (comfortably under 1.0) and a rare 3-source overlap at 0.9
(close but not clipping in the common case). Tuned by screenshot + pixel sampling, not by
eye alone — see Verification below.

## Interaction with Brain Fog, checked

`Light2D`'s default blend mode is `ADD`, and nothing in this project uses
`CanvasModulate`, so the base art already renders at full authored brightness with **zero
lights present** — adding a `Light2D` does not darken anything, it only adds a warm pool
of brightness within its texture's radius, cut off wherever an occluder sits between it
and the pixel being drawn. That reads as "the lamp's glow stops at the wall" without
touching the always-fully-visible base art or duplicating what Brain Fog's darkness does.

One real conflict had to be closed by hand: Brain Fog's full-screen rect (`Z_FOG = 60`,
`_fog_rect`) is a plain `ColorRect` with a custom shader and no `render_mode unshaded` —
by default it would still receive the engine's built-in light response, since it shares
the world's default canvas layer (0) with every new `Light2D`. Without a fix, any light
whose range reached the rect would tint its RGB, visible as a faint warm ring right at
the edge of the lit penumbra. Fix: `_fog_rect.light_mask = 0` (`game.gd`, inside
`_build_fog_layer`), which matches no light's default `range_item_cull_mask` (1), so the
rect always renders exactly what its own shader computes, regardless of how many
`Light2D`s exist. Everything else in the world (floor, walls, decor, entities) keeps the
default mask and is lit normally — only the fog overlay itself opts out.

Z-order needs no other change: `Light2D`/`LightOccluder2D` are not drawn shapes with a
`z_index` slot of their own (their `range_z_min/max` — default `-1024..1024` — decides
which *other* items they light, not where they sit in a paint order), so the shadow
system's glow renders as part of the normal world pass, strictly **under** `Z_FOG`. In a
cell Brain Fog calls lit, the fog rect is transparent there and the glow/shadow shows
through; in a cell it calls dark, the rect covers it at up to 0.88 alpha and the new
system is invisible underneath — which is the right behaviour, since the new system's
light radii are the same radii that make the fog call a cell lit in the first place.

## Verification

**A whole-screenshot before/after diff was tried first and rejected as evidence.**
`_shot_shadows.gd` (see below) captures the same build with `shadow_enabled` false, then
true; a raw pixel diff of the two zoomed crops found ~27% of pixels changed, which is
real but not proof of *shadows specifically* — the two captures are ~20 frames apart in
wall-clock time, and this project already has several time-driven animations (dashed
Routine tethers, habit idle motion) that differ between any two moments regardless of
the toggle. A diff alone cannot separate "the light changed this" from "time passed."

**The confound-free check** is `scripts/_test_shadow_occlusion.gd`
(`scenes/_test_shadow_occlusion.tscn`, run via `--main-scene`, needs the real renderer).
It samples two points at the **same radius** from the core's lamp — one
`Game.has_line_of_sight()` (the exact raycast combat already trusts, walking the same
`high_ground` dictionary the occluders are built from) calls blocked by a wall, one it
calls clear — and compares what EACH point GAINS from toggling `shadow_enabled`, not
their absolute brightness in one frame. An earlier version of this test compared the two
points' absolute brightness within a single ON frame ("same radius, same frame, so the
wall is the only difference") — sound-looking, but it silently assumed the floor/wall art
under both points started equally bright, which real level geometry does not guarantee:
a blocked point that happened to sit on a brighter wall-face highlight measured 0.2471
with the light fully OFF, comfortably beating a clear point's 0.1085 WITH the light on —
a false fail with nothing to do with occlusion. The delta each point gains from the
toggle isolates the light's own contribution from whatever the art underneath already
looked like. Result (level 1, both points ~167px from the core):

| | shadow OFF | shadow ON | delta |
|---|--:|--:|--:|
| blocked point (behind a wall) | 0.2471 | 0.2471 | **+0.0000** |
| clear point (same radius, no wall) | 0.1007 | 0.1085 | **+0.0078** |

The clear point gained real brightness from the light; the blocked point gained exactly
none — the wall is doing its job. `ALL PASS`.

**Visual spot-check**: `scripts/_shot_shadows.gd` builds one Anchor, four habits, and one
Guild, then saves wide (`*_wide.png`) and zoomed (`*_zoom.png`, ×2 nearest-upscaled)
screenshots with shadows off and on. Kept as a permanent tool (same pattern as
`_shot_fog.gd`) for the next time this needs a human look, not just a pixel sample.

Two API facts worth recording because they cost real debugging time before being
confirmed against the actual Godot 4.7.1 build (`ClassDB.can_instantiate`, not memory):
`Light2D` itself is **abstract** — the concrete node is `PointLight2D` — and the captured
viewport image was `1895×1066`, not the project's logical `1920×1080`
(`window/stretch/mode="canvas_items"` scales the logical canvas to whatever the actual
window turned out to be in this environment). Any tool that samples a screenshot by
world coordinate has to scale by `image_size / Vector2(1920, 1080)` first, or a sample
meant to land just past a 16px wall can land ~26px away — enough to invalidate the
sample. `_test_shadow_occlusion.gd`'s `_sample()` does this; a first version of it did
not, and reported confusing near-zero deltas that had nothing to do with shadows.

## Measured (2026-08-18, RTX 4070 Super, Mobile renderer, level 1, vsync off, `max_fps=0`)

Methodology per `project-mereni-vykonu`: wall-clock around `process_frame`
(`Performance.TIME_PROCESS` is a smoothed, stale value — confirmed stale again in this
session's raw harness output, where it visibly lags a state change by a full measurement
window; wall-clock is the number trusted below). `scripts/_perf_shadows.gd`
(`scenes/_perf_shadows.tscn`) builds bandwidth up toward the 120 cap with a realistic mix
(Anchors to extend Routine reach + attack habits + one Guild), then spawns a horde on the
scale of the earlier zero-tower baseline (~270–300 concurrent `Distraction`s at 60fps,
`reference-godot-binary` memory). Two methodology fixes this harness needed, kept in its
own header comment: (1) a warm-up pass before any timed row, because the first-ever
`shadow_enabled = true` compiles the shadow-map pipeline variant and that one-time stall
would otherwise land inside whichever row happened to go first; (2) the horde is
re-spawned fresh (same seed) before **every** timed row, because towers in this harness
fight for real and a shrinking population made a first pass look like shadows were
*speeding the game up* between sequential rows — an artifact of fewer live enemies, not
of the toggle.

| Scenario | shadow OFF | shadow ON | delta |
|---|--:|--:|--:|
| Empty field | 3.28–3.35 ms (~298–305 fps) | 3.38–3.42 ms (~292–296 fps) | +0.06–0.1 ms |
| 18 built structures (8 Anchor + 10 mixed, 118/120 bandwidth), no horde | 5.65–5.74 ms (~174–177 fps) | 5.82–6.18 ms (~162–172 fps) | +0.17–0.46 ms |
| Same 18 structures + 280 distractions (main scenario) | 37.4–37.8 ms (~26.5–26.7 fps) | 37.9–39.5 ms (~25.3–26.4 fps) | +0.3–1.8 ms |
| Same load, fog OFF, shadow ON (isolates shadow from fog cost) | — | 36.0–37.3 ms (~26.8–27.8 fps) | — |

Measured across three full runs spanning both the row-only occluder merge (48 occluders)
and the full rectangle merge (8 occluders); the "towers only" row visibly tightened after
the rectangle merge (was +0.44–0.46ms consistently, now as low as +0.17ms) — fewer, larger
occluders is a real, measurable win on top of being more correct geometry, not just
cheaper on paper.

Reading it: the system's real, isolated cost at a realistic full build (18 shadow-casting
lights + 8 occluders) is under half a millisecond — the cleanest number, since nothing
else is competing for frame time. At the *combined* worst case (same build plus a
280-strong horde), that cost is dwarfed by the horde's own combat simulation — 18
actively-firing habits doing per-frame cone/target tests against 280 enemies, projectiles,
hit resolution, impact FX — which dominates the frame by one to two orders of magnitude.
**The ~26fps figure in that row is not a shadow-system regression**: it reproduces
near-identically with shadows fully off, and is a pre-existing property of this project's
combat simulation at this enemy density, out of scope for this feature and unchanged by
it either way.

## Toggle

`Game.shadow_enabled` (default **`false`** — this is a first, unreviewed visual pass, not
yet the shipped look). Mirrors `fog_enabled`'s shape exactly: safe to set before or after
the scene enters the tree, idempotent, and actually stops paying the per-frame sync cost
when off rather than merely hiding the result — flipping it back on starts
`_sync_shadow_lights()` from an empty dictionary instead of diffing a stale one.

## Implementation checklist
- [x] `Light2D` (`PointLight2D`) sources for core/Anchors/built habits, reusing `14`'s
      positions and radii
- [x] `LightOccluder2D` geometry from `level.high_ground`, fully rectangle-merged
- [x] Own falloff texture, `TEXTURE_FILTER_NEAREST`, hard shadow edges — no soft glow
- [x] Source-size-aware falloff curve (`SHADOW_CURVE_TIGHT` for habits,
      `SHADOW_CURVE_WIDE` for the core/Anchors) — the round-2 playtest fix
- [x] `shadow_enabled` toggle, OFF by default, same shape as `fog_enabled`
- [x] Verified non-interference with Brain Fog (`_fog_rect.light_mask = 0`, Z-order)
- [x] Confound-free correctness test (`_test_shadow_occlusion.gd`), delta-based
- [x] Visual spot-check tool (`_shot_shadows.gd`)
- [x] Performance measured at realistic full load (`_perf_shadows.gd`)
- [x] Playtest round 2: floodlight/spotlight complaint fixed and re-verified
- [ ] The small, pre-existing, ~16px-periodic wall/floor banding found while
      investigating round 2 — confirmed unrelated to this feature (present with
      `shadow_enabled` off, unchanged by the occluder and WallShadow merges), not fully
      root-caused. Separate follow-up, likely terrain/corner-tile rendering, not render-fx
      scope for this doc.
- [ ] Wedge-shaped reach light for working habits (matching `14`'s wedge), if the flat
      lamp reads as too small once seen in motion
- [ ] A human look at fresh `_shot_shadows.gd` output (post round-2 fixes) before deciding
      this ships default-on

## Tunables (one place each)
`game.gd`: `SHADOW_LIGHT_COLOR`, `SHADOW_LIGHT_ENERGY` (0.3), the two falloff curves
(`SHADOW_CURVE_TIGHT`, `SHADOW_CURVE_WIDE` — do not merge these back into one shared
constant, that regression is exactly what round 2 fixed), `shadow_filter`
(`SHADOW_FILTER_NONE`). Light radii are NOT tunable here on purpose — they read from
`14`'s own constants (`CORE_ROUTINE_RADIUS`, `ANCHOR_ROUTINE_RADIUS`,
`TOWER_LAMP_RADIUS`) so the two systems cannot drift apart.
