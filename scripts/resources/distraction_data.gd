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

@export_category("Type-specific: disruptor (support archetype)")
## A distraction that distracts your habits: every `disrupt_interval` seconds it pings
## the nearest working habit within `disrupt_radius`, stopping it for
## `disrupt_duration`. 0.0 interval = not a disruptor (default for everything).
@export var disrupt_interval: float = 0.0
@export var disrupt_duration: float = 0.0
@export var disrupt_radius: float = 0.0
