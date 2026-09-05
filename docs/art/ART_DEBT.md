# Art debt ledger

Living log of shipped-art-vs-data color mismatches: cases where a creature/tower's
`.tres` `color` field and/or its STYLE_BIBLE.md §8 description say one color, but the
PNG actually installed in `assets/` reads as a different one. Each entry exists because
someone (or `tools/check_art_colors.py`) noticed the drift and it isn't fixed yet —
this file is the visible record, not a place to quietly explain drift away.

**Mechanism:** `tools/check_art_colors.py` (wired into `verify.sh`) parses this file's
`## <id>` headings and `**Affected ids:**` lines as its allowlist. A mismatch whose id
is logged here prints as `KNOWN` and does not fail the build; an *undocumented* new
mismatch prints `FAIL` and turns `verify.sh` red until it's either fixed or logged here.
Add an entry the same way you'd add a `KNOWN_BROKEN_TESTS` line — before or as part of
whatever change surfaces it, never to sweep something under the rug.

**Status values:** `waiting on style anchor resolution` (root-caused, no fix without an
art decision from the user — not actionable by an agent per CLAUDE.md's "Autonomní běh"
rules: this touches visual judgment); `legacy — superseded by směr A` (the asset or the
decision behind it is abandoned, the files stay on disk, and the replacement is gated
behind STYLE_BIBLE.md §12f) — a future entry could also carry `fixed, pending removal`
while the fix and this file's cleanup are still two separate commits.

**Two kinds of entry live here, and the difference matters to the parser.** The original
kind is a per-entity colour mismatch whose heading IS an entity id (`## doomscroll`) —
`check_art_colors.py` reads those headings as its allowlist, so adding one really does
stop that id from failing the build. The second kind, added 2026-09-02, records an
abandoned *direction* rather than one entity's colour; those headings are deliberately
**not** entity ids (`## legacy-figural-direction`), so they document the decision without
silently widening the colour allowlist. Keep that split: never name a direction-level
entry after a real id unless you actually intend to stop gating that id.

---

# Legacy directions (not colour mismatches)

Added 2026-09-02 when the user chose **směr A — abstract organic phenomena**
(`STYLE_BIBLE.md` §12). Everything in this part of the file is abandoned work kept on
disk on purpose. **Nothing here is to be deleted** — unpicked candidates are cheaper in
the repo than regenerated ones (CLAUDE.md), and the measurements taken from them are
still the evidence behind §12's thresholds.

## legacy-figural-direction

- **Type:** direction (style anchor + defender family)
- **Gated ids:** none — this entry adds nothing to the colour allowlist, by design.
  The field is deliberately NOT spelled `Affected ids`, because `check_art_colors.py`
  splits that line on whitespace and would swallow this sentence into its allowlist.
- **Files (KEEP, do not delete):** `assets/raw/broccoli_knight/` (incl. the selected
  `cand_03.png`), `data/defenders/broccoli_knight.tres`, `avocado_monk.tres`,
  `chilli_berserker.tres`, `garlic_mage.tres`, `tools/anchor_flat_candidates.py`,
  `tools/anchor_simplify_candidates.py`
- **What was abandoned:** the figural style as the project's visual language, and with it
  the Broccoli Knight style anchor `fa8294b1-…` — a detailed, armoured, limbed 64px
  character that was the single anchor for defenders, distractions and the boss
  (`STYLE_BIBLE.md` §6).
- **Why:** směr A makes distractions *phenomena, not creatures* — amorphous, faceless,
  limbless. A figural anchor is the wrong reference for that by construction, not merely
  too detailed. The horde argument is the load-bearing one: hundreds of units on a
  480×270 board need silhouette and colour to do the work, and faces smear into noise at
  that density.
- **Not yet done, and deliberately so:** the anchor row in `STYLE_BIBLE.md` §6
  `gen:anchors` is still marked valid. Flipping it to `plati_pro = nic` without a
  replacement id breaks `tools/gen_art_prompts.py` (a form referencing a missing family
  is a hard exit) and `scripts/_test_art_prompts.gd` (which asserts both "every character
  prompt carries its family's anchor" and "no retired anchor appears anywhere in the
  plan") at the same time. The retirement lands with the approved master — §12c and §12f.
- **Undecided, needs the user:** what the four Nutrition Guild defenders become. Směr A
  drops the figural style they are built from, but the brief only ordered a master
  distraction and a master habit, so their replacement direction was never stated. Their
  limb exception is therefore still live in §7b's literal prompt block.
- **Status:** legacy — superseded by směr A

## legacy-anchor-flat-probe

- **Type:** probe (abandoned experiment)
- **Gated ids:** none
- **Files (KEEP):** `assets/raw/anchor_flat/cand_00.png`–`cand_07.png`,
  `tools/anchor_flat_candidates.py`, `scripts/_shot_anchor_flat.gd`,
  `.dev/screenshots/anchor_flat_candidates.png`
- **What it was:** 20 generations spent 2026-08-30 asking whether a *flatter* Broccoli
  Knight could become the new anchor (`STYLE_BIBLE.md` §6a). Ran without
  `style_character_id` on purpose.
- **Why abandoned:** the question it asked no longer exists. Směr A retires the knight
  itself, so "flatter knight or not" has nothing to decide. Closed as `UZAVŘENO`, not
  answered.
- **What survives and is still worth reading:** its actual finding — with the anchor
  removed, the candidates lost *colour and theme*, not just detail density (no green, no
  vegetable motif, eight generic human figures). That is a live constraint on how the
  směr A master gets generated: dropping the anchor drops more than fidelity.
- **Status:** legacy — superseded by směr A

## legacy-anchor-simplify-probe

- **Type:** probe (abandoned experiment)
- **Gated ids:** none
- **Files (KEEP):** `assets/raw/anchor_simplify/cand_00.png`–`cand_07.png`,
  `tools/anchor_simplify_candidates.py`,
  `.dev/screenshots/anchor_simplify_candidates.png`
- **What it was:** the second probe, run 2026-09-02 (`STYLE_BIBLE.md` §6b) — keep the
  dithering and shading, cut the number of silhouette-breaking elements down to three
  strong shapes. `get_balance` read 4820 before and after, unexplained, logged as
  measured rather than assumed.
- **Why abandoned:** same day it ran, superseded by the směr A decision for the same
  reason as the flat probe — it was tuning a creature that is now leaving.
- **What survives:** the mechanism it exposed. `gen_art_prompts.py` appends §7 and §7b
  verbatim to every prompt, so a form that argues with them ships a self-contradictory
  order ("riveted armour" + "no mechanical parts"). §7b now carries an explicit list of
  the contradictions směr A opened, because of this probe.
- **Status:** legacy — superseded by směr A

## legacy-color-role-swap

- **Type:** direction (roster-wide colour assignment)
- **Gated ids:** none — the per-entity colour gate keeps working normally on all of them
- **Files:** every `data/habits/*.tres` and `data/distractions/*.tres` `color` field,
  plus the fifteen habit and thirteen distraction `form` rows in `STYLE_BIBLE.md` §8
- **What changed:** směr A **swapped which family owns which half of the palette**.
  Until 2026-09-01 habits held the warm half (amber, gold, orange, teal) and distractions
  the cold, poisonous half (magenta, violet, acid green, icy azure). From §12 it is the
  other way round: distractions are warm, saturated, "dopamine" bait; habits are cool,
  quiet and controlled. The reasoning is in `STYLE_BIBLE.md` §2, point 0 — a lure that
  looks repellent is the wrong drawing for a game about why people get pulled in.
- **What is now stale because of it:** the `color` field of every habit and distraction
  `.tres`, and §8's form descriptions, which still name the old side's hues and still
  describe habits as organic "glial cells" rather than geometry.
- **Why it is not fixed in the same commit:** phase 1 (the rest of the roster) is gated
  behind the user approving the two masters (§12f). Rewriting thirty colour fields and
  thirty form descriptions *before* the master exists would be authoring the roster from
  a desk against art nobody has seen yet — exactly what §12f orders not to do.
- **Effect on the colour checker today: none.** `check_art_colors.py` compares shipped
  PNG hue against the `.tres` colour and against §8's colour words. Neither of those two
  inputs was touched by the směr A commit, so the tool's verdict is unchanged
  (measured before and after: `PASSED — 0 FAIL, 8 KNOWN`).
- **Status:** legacy — superseded by směr A

## legacy-distraction-sprite-size

- **Type:** measurement drift (bible vs disk)
- **Gated ids:** none
- **Files:** `assets/distractions/*_frame_1.png`, `STYLE_BIBLE.md` §5 `gen:sizes`
- **What was measured 2026-09-02:** shipped distraction sprites are **48×48** on disk and
  `social_media_binge` is **96×96**. `STYLE_BIBLE.md` §5 declares `distraction`
  `art_px = 32` (ordered at 64, halved exactly once) and `distraction_boss` 64. Neither
  number matches what is installed.
- **Hypothesis:** junk-food-era art that predates the current size table, same provenance
  class as the `doomscroll`/`group_chat` colour entries above — not a consequence of
  směr A, only surfaced by measuring for it.
- **Why it matters to směr A:** §5b parks the 64→32 downsample question for horde
  distractions until "a simpler anchor exists". Směr A is that anchor, so the question
  reopens on the master — and it must be answered against a real measurement, not
  against a table that currently disagrees with the disk by 16 px.
- **Status:** legacy — superseded by směr A

## legacy-habit-head-overflows-build-block

- **Type:** measurement (art size vs board geometry)
- **Gated ids:** none — this entry adds nothing to the colour allowlist, by design.
  Deliberately not spelled `Affected ids`, for the same reason as
  `legacy-figural-direction` above: `check_art_colors.py` would swallow the list.
- **Files:** `assets/towers/head_*.png`
- **What was measured 2026-09-05:** the build block is **48 px** — derived, not copied:
  `Data.GRID.tile` (16) × `Data.BUILD_BLOCK` (3) in `scripts/data.gd`. Heads draw at their
  raw PNG size, because `Data.pixel_scale()` returns `ISO_PIXEL_SCALE` = 1.0, so one art
  pixel is one world pixel and nothing else scales them
  (`tower.gd:_draw_head_sprite`, `size = tex.get_size() * Data.pixel_scale()`).
  Alfa-bbox (alpha > 8) of every PNG referenced from `data/habits/*.tres`:

  | typ | ink | vůči 48px bloku |
  |---|---|---|
  | `real_hobby`, `real_hobby_2` | 56 na výšku | **+8** (3,50 dlaždice) |
  | `exercise`, `exercise_2` | 53 na výšku | +5 (3,31) |
  | `anchor` | 53 × 31 | +5 na výšku, na šířku se vejde |
  | `focus_timer`, `focus_timer_2` | 53 na **šířku** (V/Z), 51 (SV/SZ), 48–50 na výšku | +5 na šířku |
  | `focus_pillar` | 51 na výšku | +3 |
  | `zen_pulsar`, `_2a`, `_2b` | 50 na výšku | +2 |
  | `mindfulness`, `mindfulness_2` | 37 × 42 | vejde se |
  | `accountability`, `accountability_2` | 46 × 44 | vejde se |
  | sdílený `tower_base.png` | 33 × 33 | vejde se |

  Potvrzeno druhou, nezávislou metodou: frame diff živé desky (level 98, `focus_timer`)
  naměřil ink 53,0 px na šířku — na pixel stejně jako alfa-bbox ze souboru.
  `focus_timer` je jediný typ s kompletní osmisměrnou sadou, takže je i jediný, u kterého
  přesah **probliká** — na východ/západ vyjede o 5 px, na sever ne.
- **Why it is not being fixed in code:** rozhodl uživatel 5. 9. 2026 — nepřidávat scale
  cap na art, který se stejně zahodí. Věže se přegenerují do směru A jako geometrické
  habity dimenzované rovnou pro 48px blok. Sražení výšky u figurky s nohama vyrobí jen
  rozmáčknutou figurku — stejný závěr jako `BLOCKED.md`, záznam „Věže vypadají obrovské
  a izometricky". Per-typ konstanta pro měřítko hlavy dnes neexistuje a založit ji by
  znamenalo vyrobit něco, co se s novým artem musí zase mazat.
  (`Data.UNIT_ART_SCALE` = 0.4 se hlav věží netýká — platí jen pro pohyblivé jednotky.)
- **Not this entry:** svislé „vznášení" věže nad podložkou **nebyl** přesah artu, ale
  kotva — `_draw_head_sprite` kotvil spodek obsahu na `position`, tedy na STŘED bloku
  místo na jeho spodní hranu, takže hlava trčela 1,56 dlaždice nad podložku a její
  spodní půlka zůstala prázdná. Opraveno 5. 9. 2026 v `BaseHabit.art_origin()`; ink se
  přitom nezměnil ani o pixel (53,0 × 67,8 px před i po), což je důkaz, že to nebylo
  měřítko. Boční přesah výše tím dotčený není a trvá.
- **What clears this entry:** schválení masterů směru A a jejich instalace do
  `assets/towers/`. Pak přeměř stejným bboxem; když se všech 15 typů vejde do 48 px,
  smaž tuhle sekci.
- **Status:** legacy — superseded by směr A

---

# Colour mismatches (per-entity, allowlisted by `check_art_colors.py`)

---

## doomscroll

- **Type:** distraction
- **Affected ids:** doomscroll
- **Files:** `data/distractions/doomscroll.tres`, `scripts/components/distraction_animator.gd`,
  `assets/distractions/doomscroll_frame_1..8.png`, `_north_frame_1..8.png`,
  `_east_frame_1..8.png`, `_death_frame_1..11.png`
- **Declared color (.tres):** `#33cc77` (green, hue ~147°)
- **Bible color:** green — `STYLE_BIBLE.md:496`, "a long green ciliated ribbon that
  flows head first, segmented, with no visible end to it"
- **Shipped PNG dominant color:** amber/brown, hue ~44°, gap ~103° vs `.tres`. Sampled
  swatches: `#e9a837`, `#d28d35`, `#743f23`, `#9b5222`. No green pixels of consequence
  (a small, consistent ~9% pixel cluster at `#91fc0a`-ish green exists across every
  frame — plausibly an eye or bioluminescent fleck — but it does not read as the body).
- **Hypothesis:** `distraction_animator.gd:618-621` — art on disk always wins over the
  procedural `_draw_doomscroll()` fallback, which is dead code once PNG frames exist.
  `doomscroll.tres:17`'s `color` field only drives the glow halo
  (`_draw_type_glow`/`_draw_body_glow`), never the body pixels, so the mismatch is
  silent — nothing re-derives one from the other. Likely origin: leftover art from the
  abandoned junk-food-themed distraction direction (CLAUDE.md documents this
  abandonment, 17.8.2026), never regenerated after the pivot to the current "creature"
  direction.
- **Status:** waiting on style anchor resolution

## group_chat

- **Type:** distraction
- **Affected ids:** group_chat
- **Files:** `data/distractions/group_chat.tres`,
  `assets/distractions/group_chat_frame_1..8.png`, `_north_frame_1..8.png`,
  `_east_frame_1..8.png`, `_death_frame_1..11.png`
- **Declared color (.tres):** `#42c86a` (green, hue ~138°)
- **Bible color:** green — `STYLE_BIBLE.md:497`, "a knot of six small green spores
  sharing one membrane, all of them mouths, none of them a head"
- **Shipped PNG dominant color:** orange/brown, hue ~51°, gap ~87° vs `.tres`. Visually
  confirmed (`assets/distractions/group_chat_frame_1.png`): the body reads clearly
  orange/brown; green appears only as a small trim/membrane detail, not the creature's
  overall read.
- **Hypothesis:** same shape as `doomscroll` — `group_chat` is also in the `clickbait`
  family (`STYLE_BIBLE.md:497`'s `base` column) and its shipped body sits in the same
  amber/brown palette region as the doomscroll leftovers, consistent with junk-food-era
  art bleeding into the creature roster at the same point in time. **Note for
  `tools/check_art_colors.py` readers:** this entry's gap (~87°) sits under the
  checker's own 100° `HUE_GAP_THRESHOLD`, so the automated tool would not have
  flagged it on its own — it was found by the manual visual audit that produced this
  ledger (task instruction: "assume doomscroll won't be the only one"), not by the
  script. Logged here anyway so the visible-debt record is complete; the checker will
  print this id as `ok` (no mismatch measured) rather than `KNOWN`, which is expected
  and not a sign the entry is stale.
- **Status:** waiting on style anchor resolution

## focus_timer

- **Type:** habit
- **Affected ids:** focus_timer, focus_timer_2
- **Files:** `data/habits/focus_timer.tres`, `data/habits/focus_timer_2.tres`,
  `assets/towers/head_focus_timer.png` (+ 8-directional `head_focus_timer_<dir>.png`,
  used only by `focus_timer` — `focus_timer_2` falls back to the same static head via
  `tower.gd`'s `_head_art_key()` root-of-upgrade-line rule)
- **Declared color (.tres):** `focus_timer.tres` has no `color` line at all, so it
  falls back to `HabitData`'s script default `#4aa3ff` (blue, hue ~210°);
  `focus_timer_2.tres:21` explicitly sets `#1166ee` (blue, hue ~217°)
- **Bible color:** amber — `STYLE_BIBLE.md:502`, "...a single warm amber node,
  working in bursts"
- **Shipped PNG dominant color:** red, hue ~12°. Gap vs `.tres` blue: ~161°
  (`focus_timer`) / ~155° (`focus_timer_2`). Gap vs bible amber: ~28° (closer —
  red-orange and amber are adjacent, this one is a milder drift than the others below).
  Visually, `head_focus_timer.png` is a tomato/Pomodoro-style character with a small
  green stem, sitting on a wooden crate — not a glial cell with an amber node.
- **Hypothesis:** the `color` field looks simply forgotten for the root habit (never
  set, so it silently carries the resource script's own default blue) and
  `focus_timer_2` copied that same blue rather than the tomato-red the shipped art
  actually uses. Separately, and outside this audit's color-only scope: the shipped
  "tomato" character (a Pomodoro Technique pun) doesn't match
  `STYLE_BIBLE.md:502`'s "glial cell body" form description at all, which suggests the
  bible's form entry for `focus_timer` may itself be stale relative to what got
  installed — flagged for awareness, not something this color checker can resolve.
- **Status:** waiting on style anchor resolution

## zen_pulsar

- **Type:** habit
- **Affected ids:** zen_pulsar, zen_pulsar_2a, zen_pulsar_2b
- **Files:** `data/habits/zen_pulsar.tres`, `data/habits/zen_pulsar_2a.tres`,
  `data/habits/zen_pulsar_2b.tres`, `assets/towers/head_zen_pulsar.png`
- **Declared color (.tres):** `#5fe4f6` (cyan, hue ~187°) on all three
- **Bible color:** cyan — `STYLE_BIBLE.md:506`, "a spherical glial bulb held inside
  one standing cyan ring, still until it releases"
- **Shipped PNG dominant color:** brown/tan, hue ~20°, gap ~168°. Visually,
  `head_zen_pulsar.png` is a mortar-and-pestle in maroon/brown clay on a woven base —
  no cyan anywhere.
- **Hypothesis:** `PROGRESS.md` (commit `0465a23`) documents that the previous
  8-frame `head_zen_pulsar_frame_1..8.png` animated set was removed and replaced with
  today's single-frame `head_zen_pulsar.png` as part of an unrelated test-fixture
  cleanup. The replacement art (mortar-and-pestle) reads as a different concept
  entirely and never carried forward the "cyan ring" accent that both the `.tres`
  `color` and the bible still describe.
- **Status:** waiting on style anchor resolution

## anchor

- **Type:** habit
- **Affected ids:** anchor
- **Files:** `data/habits/anchor.tres`, `assets/towers/head_anchor.png`
- **Declared color (.tres):** `#33e6f2` (cyan, hue ~184°) — both `color` and
  `projectile_color`
- **Bible color:** cyan — `STYLE_BIBLE.md:508`, "a squat glial body rooted into the
  tissue by thick processes, one cyan crystal node, it holds and does not fire"
- **Shipped PNG dominant color:** the measured circular-mean hue is ~27° (orange), but
  that number is a blend of two separate swatches rather than one true dominant tone —
  the most prominent bright/saturated pixels split between salmon-pink (~h1°) and gold
  (~h49°). By eye `head_anchor.png` reads as a purple/maroon oil-lamp-like object with
  a pale gold trim. Either way, gap vs `.tres` is large (~157° against the ~27° mean,
  and no closer against either individual swatch) — no cyan present at any prominence.
- **Hypothesis:** unlike `zen_pulsar`, no direct provenance note was found for this
  swap. The shipped art reads as an unrelated object (a lamp) rather than
  `STYLE_BIBLE.md:508`'s "glial body...cyan crystal node" — same class of drift as
  `focus_timer`'s tomato and `focus_pillar`'s hourglass below (see those entries):
  a hand-installed or reused piece of art that was never checked back against the
  `.tres` color or bible description it's supposed to satisfy.
- **Status:** waiting on style anchor resolution

## focus_pillar

- **Type:** habit
- **Affected ids:** focus_pillar
- **Files:** `data/habits/focus_pillar.tres`, `assets/towers/head_focus_pillar.png`
- **Declared color (.tres):** `#5fe4f6` (cyan, hue ~187°) — copied verbatim from
  `zen_pulsar.tres`, per this file's own header comment (see hypothesis)
- **Bible color:** cyan — `STYLE_BIBLE.md:509`, "a fluted round glial column with a
  single cyan crystal at its crown, quiet and upright"
- **Shipped PNG dominant color:** brown/tan, hue ~23°, gap ~164°. Visually,
  `head_focus_pillar.png` is an hourglass in brown/tan wood tones with cream sand —
  no cyan.
- **Hypothesis:** `data/habits/focus_pillar.tres:5-11` documents in its own header
  comment that its combat stats — and, by inheritance since nothing else was
  authored, its color fields — were "borrowed 1:1 from `zen_pulsar`...NOT a balanced
  design decision," installed only to give the approved 64×64 "Focus Pillar" landmark
  art (`assets/src/pixel/towers/tower_01_FOCUS_final.png`) something buildable to live
  on. This habit is explicitly, self-documented as an unfinished placeholder; the
  color mismatch is a symptom of that placeholder status, not a fresh regression —
  it will most naturally resolve together with `focus_pillar`'s own design pass
  rather than in isolation.
- **Status:** waiting on style anchor resolution
