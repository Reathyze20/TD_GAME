class_name AdData extends Resource
## One parody interstitial.
##
## The joke is load-bearing, not decoration. Every other lesson in this game can be
## answered with "yes, I know how that works" — and knowing is exactly what does not
## help. An ad the player is actively laughing at, sees straight through, and taps
## anyway is the only proof that lands, because they produce it themselves.
##
## So the offer has to be REAL: `payload_dopamine` is genuinely paid and
## `payload_tolerance` genuinely charged. A fake button would make it a gag.
##
## Everything here is data. The overlay scene (scripts/ad_overlay.gd) is written once
## and every new joke is one more .tres in data/ads/ — same shape as cards and
## distractions.

@export_category("Copy")
@export var id: StringName = &""
@export var headline: String = ""
@export var subline: String = ""
## Fake store rating, e.g. "4.9 ★ (2,300,411)". Empty hides the row.
@export var stars: String = ""
@export var cta_text: String = "TAP HERE"
## Small print under the CTA. Used by the last ad in the campaign to drop the act.
@export var footnote: String = ""

@export_category("Look")
## Deliberately OFF the project's style bible: garish gradients, emoji, fat sans. The
## clash is half the joke, and it means these assets never have to pass the art bar.
@export var color_a: Color = Color("ff2e63")
@export var color_b: Color = Color("2e2eff")
@export var text_color: Color = Color.WHITE
## Big dumb emoji shown where a screenshot would be.
@export var emoji: String = "💎"

@export_category("The fake hand")
## Viewport-relative waypoints (0..1) the incompetent cursor tweens through. Real ad
## hands are the only animated thing in a real ad, and they always pick wrong — which
## is why they work. Empty = no hand.
@export var hand_path: Array[Vector2] = []
## Seconds per leg of the path.
@export var hand_leg_time: float = 0.7

@export_category("The X")
## 6 is the troll. 48 is honest. Every troll needs a punchline within three seconds of
## itself or it stops being a joke and is just bad UI.
@export_range(6, 64) var x_size_px: int = 32
## Seconds before the X appears at all.
@export var x_delay: float = 1.0
## The X moves once when first approached. ONCE — repeating it is cruelty, not comedy.
@export var x_dodges: bool = false
## Counts "5 … 4 … 3 … 3 … 3 …" and then closes on its own anyway. The lie costs the
## player nothing; noticing it is the entire payload.
@export var countdown_lies: bool = false

@export_category("The offer")
## Actually paid out when the CTA is tapped.
@export var payload_dopamine: int = 0
## Actually charged when the CTA is tapped.
@export var payload_tolerance: float = 0.0
## Craving added on tap — an ad that worked is a cue that worked.
@export var payload_craving: float = 12.0
## The warm troll: the CTA starts an honest countdown of this many seconds and then
## PAYS. The game catches the player and settles up anyway. That register is what keeps
## the whole campaign readable as "on your side" rather than as a lecture with jokes —
## nobody is ever punished for getting caught, they are only ever shown the receipt.
@export var reward_countdown: float = 0.0

@export_category("Placement")
## Show it on the post-level screen instead of mid-wave. The first ad a player ever
## sees MUST be this, and must cost nothing: an interstitial that takes Focus before
## the player knows the game does jokes reads as hostility, and they never come back.
@export var between_levels: bool = false
## Wave number (1-based) to interrupt. Ignored when `between_levels` is true.
@export var wave: int = 0
