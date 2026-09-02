# Steam capsule art — specification

**Q3 (`PATHFINDING.MD`). This is a brief to hand to a human artist, not a generation
prompt.** Nothing here was generated and nothing here should be: see §6.

Every dimension in §1 was read off Steamworks on **2026-09-02**, not from memory — the
first draft of this document had the header capsule at 460×215, which is the *old* size and
would have cost a commission. Steam changes these; re-check before ordering.

---

## 1. Every asset, exact size

### Store assets ([source](https://partner.steamgames.com/doc/store/assets/standard))

| Asset | Size | Where it shows |
|---|---|---|
| **Small capsule** | **462 × 174** | Search results, top sellers, new releases. Steam auto-derives **184 × 69** and **120 × 45** from it. |
| **Header capsule** | **920 × 430** | Top of the store page, "Recommended for you", browse views. |
| **Main capsule** | **1232 × 706** | Store front-page carousel. |
| **Vertical capsule** | **748 × 896** | Seasonal sales, sale pages. |
| Page background | 1438 × 810 | Optional; Steam derives one from the last screenshot if absent. |
| Bundle header | 707 × 232 | Only if we ever ship a bundle. |
| Screenshots | ≥ 1920 × 1080, 16:9 | **Minimum five.** These we produce in-engine, not commissioned. |

### Library assets ([source](https://partner.steamgames.com/doc/store/assets/libraryassets))

| Asset | Size | Format | Notes |
|---|---|---|---|
| **Library capsule** | **600 × 900** | PNG | Auto-derives 300 × 450. |
| **Library header** | **920 × 430** | PNG | Same size as the store header — but see §3, it is not necessarily the same picture. |
| **Library hero** | **3840 × 1240** | PNG | Auto-derives 1920 × 620. **Safe area 860 × 380** stays uncropped. **Steam forbids text in this image.** |
| **Library logo** | 1280 wide and/or 720 tall | **PNG, transparent** | Overlays the hero. Anchor is chosen from: left-bottom, centered top, centered middle, centered bottom. |

Library assets only become visible once the store page is published.

### Icons ([source](https://partner.steamgames.com/doc/store/assets/community))

| Asset | Size | Format |
|---|---|---|
| **App icon** | **184 × 184** | JPG |
| **Shortcut / client icon** | **256 × 256** or **512 × 512** | ICO or PNG (Steam converts PNG for us) |

---

## 2. Design from the smallest size up, not the largest

The **120 × 45** derivative is the one a browsing player actually sees first, and Steam
generates it by shrinking the 462 × 174 small capsule. At that size the game's whole board,
its palette and its lighting are gone. Roughly three things survive: **one silhouette, one
colour contrast, one word.**

So the order of work is:

1. Compose the **small capsule** first and judge it at **120 × 45**.
2. Only then scale the idea up. The larger capsules may add detail, but they must not
   introduce a *different* focal point — a player who clicks a thumbnail should land on a
   page that looks like the thumbnail grew, not like a different game.
3. The **vertical capsule (748 × 896)** is the one composition that cannot be a crop of the
   others: portrait, and used during sales where it sits next to hundreds of others.

**Concrete test to apply before delivery:** shrink each capsule to 120 × 45 and, separately,
view it in a grid of 20 unrelated Steam thumbnails. If it stops being findable, the
composition failed, whatever it looks like at full size.

---

## 3. What the picture has to say

Read `docs/core/00_overview.md` first — it is the ground truth for what this game is. The
one-line version for the artist:

> A tower-defense game about **attention being hijacked**. You defend a Focus core from
> Distractions — notifications, autoplay, doomscroll — by building Habits that shine a
> cone of light and only shoot what they can see. There is a button that hands you instant
> currency and permanently narrows your attention afterwards.

**The single idea the capsule must land: this is a game about your own attention, and it is
a real tower defense.** Two failure modes to avoid, both very easy to fall into:

- **Reads as a productivity app.** No checklists, no timers-as-UI, no clean corporate
  flat-design. It is a game.
- **Reads as a generic pixel TD.** Towers-and-creeps with no theme visible. If you could
  swap in orcs and nothing would change, the theme did not land. The overview is explicit:
  *do not* use orcs/trolls/goblins or generic "archer/cannon" towers.

**What may appear** (all of it exists in-game, so the capsule stays honest):

- The **Focus core** — the thing being defended. `UI.FOCUS` green (`7cffb2`).
- One or two **Habits** with their **cone of light**. The cone is the game's most
  recognisable shape and the mechanic that makes it different: a habit only shoots what it
  can see. This is the strongest single visual we own.
- **Distractions** streaming in — sharp, cold, toxic-coloured silhouettes. Per
  `docs/art/STYLE_BIBLE.md` §2a: habits are round and warm, distractions are sharp and
  coldly poisonous. **The silhouette carries the family, not the colour** — that rule is
  the project's, and the capsule must not break it.
- **Brain Fog** — the dark that the cone cuts into. The contrast between lit wedge and
  unlit board is the picture.
- Optionally the **Tolerance** meter's amber (`ff8a3d`) as the one warm intrusion, if a
  hint of the game's cost is wanted.

**What must NOT appear:**

- Text in the **library hero** (Steam rule).
- Any UI chrome copied from the game. Capsules are illustration, not screenshots.
- A human face or a brain diagram. Both are the obvious literal move for this subject and
  both read as stock.

---

## 4. Palette and style anchor

- **Palette:** `docs/art/palette_48.hex` — 48 colours, the master the whole project draws
  from. Hand it to the artist as a file. `palette_32.hex` exists and is measurably worse;
  do not offer it.
- **Key colours** from `scripts/ui.gd`, so the capsule agrees with the game's own screen:
  background `0a0c14`, Focus `7cffb2`, Dopamine `ffd479`, Tolerance `ff8a3d`,
  danger/distraction `ff6b6b`, accent `9bd0ff`.
- **Style reference:** the shipped art, not a mood board. `docs/art/STYLE_BIBLE.md` is the
  authority; `.dev/screenshots/p_hudrescale_gameplay.png` shows the real board at real
  scale.
- **Resolution discipline:** the game is pixel art authored at 1× on a 16 px grid and
  integer-scaled. A capsule does not have to be pixel art — at 1232 × 706 a pixel-art
  capsule would be enormous pixels — but it must look like the *same world*. If it is pixel
  art, author at a native size and integer-scale; never bilinear-scale pixel art up.

---

## 5. Deliverables checklist

| # | File | Size | Format |
|---|---|---|---|
| 1 | `capsule_small` | 462 × 174 | PNG |
| 2 | `capsule_header` | 920 × 430 | PNG |
| 3 | `capsule_main` | 1232 × 706 | PNG |
| 4 | `capsule_vertical` | 748 × 896 | PNG |
| 5 | `library_capsule` | 600 × 900 | PNG |
| 6 | `library_header` | 920 × 430 | PNG |
| 7 | `library_hero` | 3840 × 1240 | PNG, **no text**, safe area 860 × 380 |
| 8 | `library_logo` | 1280 w and/or 720 h | PNG, **transparent** |
| 9 | `app_icon` | 184 × 184 | JPG |
| 10 | `client_icon` | 512 × 512 | PNG |
| 11 | `page_background` | 1438 × 810 | PNG (optional) |

Plus, from the artist: **layered source files** (PSD/Krita/Aseprite) for every capsule. See
§6 for why that is not optional.

---

## 6. The "AI slop" problem, handled deliberately

Capsule art is the single most common target of AI-art accusations on Steam, and it is the
first thing a player sees. **Documented backlash exists even where the accusation turned out
to be false** — which means "we didn't use AI" is not a defence you can mount after the
fact, only one you can prepare for.

**Therefore:**

1. **Do not generate capsule art.** Not through PixelLab, not through anything else. This
   is the one asset class where the project's own generation pipeline is off-limits, and
   this document exists partly to say so in writing.
2. **Require layered sources and process shots.** Ask the artist for the working file and a
   few WIP captures. That is what answers an accusation in an hour instead of a week.
3. **Steam's own disclosure field.** The store submission asks whether AI was used in
   creating the game's content. Answer it honestly for the whole game, not just the
   capsule — the in-game sprites *were* generated through PixelLab, and being straight
   about that while the capsule is hand-made is a far better position than being caught
   splitting hairs.
4. **Consistency is the tell.** The most reliable giveaway is not brushwork, it is a
   capsule whose lighting, palette and shapes do not match the game's screenshots. Holding
   the capsule to `palette_48` and to the silhouette rule in §3 is both a quality measure
   and the cheapest possible defence.

---

## 7. What is deliberately not decided here

- **The logo/wordmark itself.** The library logo is a separate transparent PNG and a
  typographic problem, not an illustration one. It wants its own brief.
- **Which composition wins.** This document says what the picture must communicate and at
  what sizes it has to survive. Choosing between two good compositions is the user's call
  and needs to be made by looking, not by specification.
- **The final game title as it appears on the capsule.** It is player-facing copy; that is
  `insight-copy` territory, not this document's.
