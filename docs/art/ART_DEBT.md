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
rules: this touches visual judgment) — no other status is in use yet, but a future entry
could carry `fixed, pending removal` while the fix and this file's cleanup are still two
separate commits.

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
