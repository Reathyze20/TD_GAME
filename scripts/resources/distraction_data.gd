class_name DistractionData extends Resource
## Stats + visual reference for one distraction (enemy) type.

@export_category("Identity")
@export var id: StringName = &"notification"
@export var display_name: String = "Notification"
@export_multiline var description: String = "The ping that yanks your attention."

@export_category("Stats")
@export var max_health: int = 5
@export var speed: float = 140.0
@export var is_flying: bool = false          ## Flyers ignore the maze and Allies entirely.

@export_category("Resistances")
@export var compulsion: int = 0              ## Flat reduction vs Willpower damage.
@export var rationalization: int = 0         ## Flat reduction vs Awareness damage.

@export_category("Economy & Threat")
@export var dopamine_reward: int = 1         ## Dopamine granted on defeat.
@export var focus_damage: int = 1            ## Focus lost if it reaches the core.
@export var melee_damage: int = 3            ## Counter-damage dealt to a blocking Ally.

## How much of a defender's block capacity pinning this creature costs. 1 = ordinary;
## heavies cost more, so a capacity-3 Broccoli Knight holds three lights OR one weight-3
## monster, while a capacity-1 Chilli Berserker cannot stop the heavy at all — it fights
## it on the move instead. Blocking maths only; nothing else reads this.
@export var block_weight: int = 1

@export_category("Visuals")
@export var color: String = "ff5566"         ## Hex color, no leading '#'.
@export var radius: float = 9.0
@export var shape: String = "circle"         ## "circle", "triangle", or "rect".

@export_category("Type-specific: boss (final-wave only)")
@export var is_boss: bool = false
@export var shield_interval: float = 0.0     ## Seconds of open damage before the shield goes up.
@export var shield_duration: float = 0.0     ## How long the shield stays up.
@export var minion_type: DistractionData = null
@export var minion_count: int = 0            ## Minions spawned per burst.
@export var minion_interval: float = 0.0     ## Seconds between minion bursts.

@export_category("Type-specific: damage shape (armour archetype)")
## The first PERCENTAGE mitigation in the game — everything else (compulsion,
## rationalization) is flat subtraction with a floor of 1. Percentages are used here on
## purpose: this archetype is not "hard to hurt", it is "hurt by the RIGHT tool", and a
## flat number cannot say that at both ends of the damage scale.
##
## A single-target habit whose fire_cooldown is at or under `fast_shot_threshold` counts
## as chip damage and is scaled by `fast_shot_damage_mult`; AoE habits are scaled by
## `aoe_damage_mult`; Boredom (the game's damage-over-time) by `dot_damage_mult`.
## 1.0 everywhere = no shaping, which is what every other distraction uses.
##
## Only habits are shaped. Interventions, card bursts and ally melee deliberately credit
## no source, so they land unshaped — a deliberate escape hatch, not an oversight.
@export var fast_shot_threshold: float = 0.0
@export var fast_shot_damage_mult: float = 1.0
@export var aoe_damage_mult: float = 1.0
@export var dot_damage_mult: float = 1.0

@export_category("Type-specific: overdrive (wounded-phase archetype)")
## A one-way phase change when the creature drops to `overdrive_hp_pct` of its health:
## it speeds up by `overdrive_speed_mult` and, with `overdrive_slow_immune`, stops caring
## about Calm. Hurting it is what arms it, so the lesson is about committing to a kill
## rather than chipping — half-damaging one of these makes the wave worse than not
## shooting it at all.
##
## A FULL freeze still lands on an immune target; see StatusManager.slow_immune.
## 0.0 pct = no overdrive phase (default for everything).
@export var overdrive_hp_pct: float = 0.0
@export var overdrive_speed_mult: float = 1.0
@export var overdrive_slow_immune: bool = false

@export_category("Type-specific: energiser (support archetype)")
## A distraction that distracts *for* the others: every `haste_interval` seconds it
## sends a wave out to `haste_radius` and every distraction it touches — itself
## included — moves at `haste_factor` speed for `haste_duration`.
##
## The counterpart to the disruptor: that one attacks your towers, this one buffs its
## own side, so the answer is to kill the emitter rather than to out-damage the wave.
## 0.0 interval = not an energiser (default for everything).
@export var haste_interval: float = 0.0
@export var haste_duration: float = 0.0
@export var haste_radius: float = 0.0
@export var haste_factor: float = 1.0        ## 1.35 = 35 % faster. <= 1.0 does nothing.

@export_category("Type-specific: disruptor (support archetype)")
## A distraction that distracts your habits: every `disrupt_interval` seconds it pings
## the nearest working habit within `disrupt_radius`, stopping it for
## `disrupt_duration`. 0.0 interval = not a disruptor (default for everything).
@export var disrupt_interval: float = 0.0
@export var disrupt_duration: float = 0.0
@export var disrupt_radius: float = 0.0

@export_category("Type-specific: fleeting (FOMO)")
## A limited-time offer, and the only distraction in the game that CANNOT hurt you.
## After `lifetime_seconds` of wave time it simply leaves — no Focus damage, no leak,
## nothing. Ignoring it is free; the game never says so.
##
## The lesson is the one every countdown timer in every shop is built on: urgency is not
## evidence of value. What it actually costs you is the cooldowns your habits burned
## shooting it while a real threat walked past, and the receipt is where that lands
## (Mirror counts `bait_kill`). So it must be genuinely tempting rather than a trap —
## give it a fat `dopamine_reward`. The payout is real. The value is zero. That gap IS
## the mechanic, and it is exactly the gap the attention economy runs on.
##
## 0.0 = permanent (default for everything).
@export var lifetime_seconds: float = 0.0

@export_category("Type-specific: splitter (Just One More)")
## Dies and leaves `split_count` smaller copies of itself, up to `split_generations`
## deep. Every copy looks like the last one.
##
## The arithmetic is deliberately reassuring and deliberately wrong: at count 2 and
## 3 generations one spawn is 15 bodies, and each individual kill feels like progress
## because it IS progress. "Just one more" is not a lie the game tells the player, it is
## a true statement about the next body and a false statement about the queue.
##
## Health scales by `split_scale` per generation, so the tail is trivial to clear —
## the cost is never difficulty, it is TIME, which is the thing the archetype is about.
## 0 count or 0 generations = does not split (default for everything).
@export var split_count: int = 0
@export var split_generations: int = 0
@export var split_scale: float = 0.66

@export_category("Type-specific: autoplay (deadline archetype)")
## Let it live `autoplay_seconds` of wave time and it takes your build phase: the next
## wave starts on a short forced countdown (`autoplay_grace`) instead of waiting for you.
##
## It steals the one part of a tower defence that is actually restful — the untimed
## think. That is precisely what an autoplay countdown does to the end of an episode,
## and the reason it exists is that the pause is where people leave.
##
## Killable, and the countdown is visible from the moment it arms, so it is a threat the
## player can answer rather than a punishment they discover. 0.0 = not an autoplay.
@export var autoplay_seconds: float = 0.0
@export var autoplay_grace: float = 4.0

@export_category("Type-specific: comparison (adaptive archetype)")
## Reads the habits the player actually built and hardens against whichever damage
## channel they leaned on, by `adapt_ratio` of the single best habit's output.
##
## The lesson is the recommender loop, not difficulty: the thing you engage with most is
## the thing that learns you fastest, and a monoculture is what makes that cheap. The
## counter is never more of your best tower — it is a SECOND channel, because the
## resistance only ever lands on one of the two.
##
## Deliberately reads the built board rather than a kill history, so the player can look
## at their own maze and predict what the next one will resist. An adaptation nobody can
## anticipate is just a random stat. false = does not adapt (default for everything).
@export var adapts_to_player: bool = false
@export var adapt_ratio: float = 0.5
