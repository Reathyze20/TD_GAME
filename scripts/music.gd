extends Node
## AUTOLOAD: Music — three looping layers whose volume rides GameState.satisfaction.
##
## ONE SYSTEM, ONE SENSE (docs/design/dopamine_mechanics.md §3). Satisfaction owns the
## music and nothing else touches it, the same way Tolerance owns colour, novelty owns
## the kill sound and Burnout owns the camera. Five systems, five channels, and the
## player learns the language in two levels without being taught it.
##
## Satisfaction is LIKING, not wanting — Berridge's other half. It is the one meter that
## starts full and can only be spent. A level cleared with every Focus intact and
## Satisfaction at 12% ends in near-silence, and that silence is the thesis: you won,
## and it did not feel like anything. No card can say that as well as an empty room can.
##
## Synthesised at startup like the rest of the soundscape (scripts/sfx.gd) — no audio
## files, so swapping in real music later means loading a stream into _layers instead of
## calling _render().

## VYPNUTO 21. 8. 2026 na zadost uzivatele ("odeber tu hudbu, to je naprd").
##
## Vypnuto, NE smazano. Ta hudba neni ozdoba: je to jeden z peti smyslovych kanalu podle
## docs/design/dopamine_mechanics.md §3 -- Satisfaction (liking) nema jiny hlas nez ji, a
## level dohrany s plnym Focusem a Satisfaction na 12 % ma koncit v tichu, ktere je celou
## tezi hry. Smazat autoload by tu tezi umlcelo natrvalo kvuli tomu, ze SYNTEZA zni
## spatne -- coz je vada provedeni, ne navrhu.
##
## Zpatky se to zapne prepnutim na true. Az bude realna hudba, nacte se stream do
## _layers misto volani _render() (viz komentar nize) a tenhle prepinac zmizi.
const ENABLED := false

const SAMPLE_RATE := 22050
const LOOP_SECONDS := 8.0

## satisfaction 0..100 mapped onto each layer's audible window. Staggered so the layers
## drop out one at a time instead of the whole mix fading together — a thinning
## arrangement reads as "something is missing", a fade just reads as a volume slider.
const _LAYERS := [
	# name        in    full   db
	["drone",     0.0,  25.0, -20.0],   # never fully leaves; the room is still there
	["pad",      30.0,  65.0, -17.0],
	["shimmer",  60.0,  95.0, -22.0],
]

var _players: Dictionary = {}     # name -> AudioStreamPlayer
var _duck_left := 0.0
var _enabled := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not ENABLED:
		# Sbernice se zalozi i tak, aby posuvnik v nastaveni nespadl na chybejici bus.
		_ensure_bus()
		set_process(false)
		return
	_ensure_bus()
	_build()
	# MetaProgression loads before this autoload, so saved preferences are ready here.
	set_volume_linear(MetaProgression.current_save.music_volume)
	set_muted(MetaProgression.current_save.music_muted)

func _ensure_bus() -> void:
	if AudioServer.get_bus_index(&"Music") == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, &"Master")

## Same shape as the Sfx autoload's volume API so the settings screen can drive both
## the same way: preview_* while a slider is dragged, set_* to commit and persist.
func set_volume_linear(v: float) -> void:
	preview_volume_linear(v)
	MetaProgression.current_save.music_volume = clampf(v, 0.0, 1.0)
	MetaProgression.save_settings()

func preview_volume_linear(v: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Music"),
		linear_to_db(maxf(clampf(v, 0.0, 1.0), 0.0001)))

func get_volume_linear() -> float:
	return MetaProgression.current_save.music_volume

func set_muted(m: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Music"), m)
	MetaProgression.current_save.music_muted = m

# ---------------------------------------------------------------- control

## Silence for `seconds`, then return. The one place the mix is allowed to drop BELOW
## its own baseline: a bonus wave that was announced and then paid nothing. Negative
## prediction error is not the absence of a reward, it is a dip under resting state, and
## three seconds of no room tone is the only honest way to render that.
func duck(seconds: float) -> void:
	_duck_left = maxf(_duck_left, seconds)

func stop() -> void:
	_enabled = false
	for p in _players.values():
		p.stop()

func start() -> void:
	_enabled = true
	for p in _players.values():
		if not p.playing:
			p.play()

func _process(delta: float) -> void:
	if not _enabled:
		return
	if _duck_left > 0.0:
		_duck_left -= delta / maxf(Engine.time_scale, 0.0001)

	var s: float = GameState.satisfaction
	for spec in _LAYERS:
		var p: AudioStreamPlayer = _players[spec[0]]
		var target_lin: float = 0.0
		if _duck_left <= 0.0:
			target_lin = clampf(inverse_lerp(float(spec[1]), float(spec[2]), s), 0.0, 1.0)
		var target_db: float = float(spec[3]) + linear_to_db(maxf(target_lin, 0.0001))
		# Lerped rather than snapped: satisfaction moves in per-wave steps and a stepped
		# mix would click. Slow enough that the player notices the room changing without
		# being able to point at the moment it did.
		p.volume_db = lerpf(p.volume_db, target_db, clampf(delta * 1.2, 0.0, 1.0))

# ---------------------------------------------------------------- synthesis

func _build() -> void:
	# A minor: root A2, fifth E3, and a high shimmer on A5/C6/E6. Chosen because it sits
	# under the SFX set (which lives from 660 Hz up) without masking any of it.
	_add("drone", func(t: float) -> float:
		return 0.30 * sin(TAU * 110.0 * t) \
			+ 0.16 * sin(TAU * 164.81 * t) \
			+ 0.07 * sin(TAU * 55.0 * t) \
			* (0.85 + 0.15 * sin(TAU * 0.12 * t)))

	_add("pad", func(t: float) -> float:
		# Two detuned saws an octave up, breathing on a slow LFO.
		var breathe: float = 0.55 + 0.45 * sin(TAU * 0.09 * t)
		return breathe * (0.13 * _saw(220.0 * t) + 0.11 * _saw(220.6 * t)
			+ 0.08 * _saw(329.63 * t)))

	_add("shimmer", func(t: float) -> float:
		# A slow four-note figure. int() on the loop length keeps it phase-aligned so the
		# loop point is inaudible.
		var step: int = int(t * 2.0) % 4
		var note: float = [880.0, 1046.5, 1318.5, 1046.5][step]
		var pluck: float = exp(-fmod(t * 2.0, 1.0) * 3.5)
		return 0.10 * pluck * (sin(TAU * note * t) + 0.4 * sin(TAU * note * 2.0 * t)))

func _add(layer_name: String, gen: Callable) -> void:
	var n: int = int(LOOP_SECONDS * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in range(n):
		var t: float = float(i) / SAMPLE_RATE
		# Crossfade the last 0.15 s into the first so the seam does not click. The
		# generators are all periodic in LOOP_SECONDS, but floating point is not.
		var v: float = float(gen.call(t))
		var tail: float = LOOP_SECONDS - t
		if tail < 0.15:
			var k: float = tail / 0.15
			v = v * k + float(gen.call(LOOP_SECONDS - t)) * (1.0 - k)
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	wav.data = bytes

	var p := AudioStreamPlayer.new()
	p.bus = &"Music"
	p.stream = wav
	p.volume_db = -60.0
	add_child(p)
	p.play()
	_players[layer_name] = p

func _saw(x: float) -> float:
	return 2.0 * (x - floor(x)) - 1.0
