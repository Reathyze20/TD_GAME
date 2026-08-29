extends Node
## AUTOLOAD: Sfx — the game's entire soundscape, synthesized at startup.
##
## Eight informational cues, chosen because each marks a moment that previously had no
## feedback at all (or feedback the player can't see while looking elsewhere):
##   place · error · focus_lost · insight · wave_start · card · shield_up/down · click
##
## The Insight drop matters most: it is a variable-ratio reward schedule, and a
## variable-ratio schedule without a bright immediate cue is only half a hook — and
## that hook is the level-1 lesson this game teaches.
##
## No audio files: every cue is an AudioStreamWAV rendered from sine/square math in
## _ready(), mirroring how the rest of the project draws its art in code. Swapping in
## real sounds later = loading a file into _streams instead of calling _add().
##
## Bus wiring lives here (SignalBus events, GameState.insight_dropped); the few moments
## without a bus signal call Sfx.play() directly at the site (game.gd errors, card pick,
## boss shield lambda; ui.gd button factories for clicks).

const SAMPLE_RATE := 22050
const POOL_SIZE := 8

var _streams: Dictionary = {}      # StringName -> AudioStreamWAV
var _volume_db: Dictionary = {}    # StringName -> float
var _min_gap: Dictionary = {}      # StringName -> seconds between repeats (anti-spam)
var _last_ms: Dictionary = {}      # StringName -> last play time
var _players: Array[AudioStreamPlayer] = []

func _ready() -> void:
	# UI clicks and the pause toggle must stay audible while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus()
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = &"Sfx"
		add_child(p)
		_players.append(p)
	_build_streams()
	# MetaProgression loads before this autoload, so saved preferences are ready here.
	set_volume_linear(MetaProgression.current_save.sfx_volume)
	set_muted(MetaProgression.current_save.sfx_muted)

	SignalBus.habit_built.connect(func(_h, _c): play(&"place"))
	SignalBus.habit_upgraded.connect(func(_h, _c): play(&"place"))
	SignalBus.wave_started.connect(func(_n): play(&"wave_start"))
	SignalBus.distraction_escaped.connect(func(_dmg): play(&"focus_lost"))
	GameState.insight_dropped.connect(func(_pos, _amt): play(&"insight"))

# ---------------------------------------------------------------- volume & bus

## All cues route through a dedicated "Sfx" bus so one user-facing slider controls the
## whole mix while the per-cue _volume_db values keep their relative balance. Created in
## code rather than a bus layout file — the project has no other audio to lay out.
func _ensure_bus() -> void:
	if AudioServer.get_bus_index(&"Sfx") == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Sfx")
		AudioServer.set_bus_send(idx, &"Master")

## Master SFX volume, linear 0..1 (what the settings slider speaks). Persisted.
## The bus is resolved by NAME on every call — indices shift when buses are reordered.
func set_volume_linear(v: float) -> void:
	preview_volume_linear(v)
	MetaProgression.current_save.sfx_volume = clampf(v, 0.0, 1.0)
	MetaProgression.save_settings()

## Applies the volume to the bus WITHOUT writing the save — for live slider dragging,
## which would otherwise hit the disk on every tick. Commit with set_volume_linear().
func preview_volume_linear(v: float) -> void:
	v = clampf(v, 0.0, 1.0)
	# linear_to_db(0) is -inf, which serializes badly; floor the audible range instead.
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Sfx"),
		linear_to_db(maxf(v, 0.0001)))

func get_volume_linear() -> float:
	return MetaProgression.current_save.sfx_volume

func set_muted(m: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Sfx"), m)
	MetaProgression.current_save.sfx_muted = m
	MetaProgression.save_settings()

func is_muted() -> bool:
	return MetaProgression.current_save.sfx_muted

## Fire a cue by name. Unknown names are ignored (a missing sound must never break a
## gameplay path). Repeats inside the cue's min-gap are dropped — ten simultaneous
## leaks are one alarm, not a machine-gun.
func play(cue: StringName) -> void:
	if not _streams.has(cue):
		return
	var now: int = Time.get_ticks_msec()
	if now - int(_last_ms.get(cue, -99999)) < int(float(_min_gap.get(cue, 0.05)) * 1000.0):
		return
	_last_ms[cue] = now
	for p in _players:
		if not p.playing:
			p.stream = _streams[cue]
			p.volume_db = _volume_db.get(cue, -6.0)
			# A few cents of random detune keeps rapid repeats (builds, drops) organic.
			p.pitch_scale = randf_range(0.97, 1.03)
			p.play()
			return
	# Pool exhausted: steal the first player — newest information wins.
	_players[0].stream = _streams[cue]
	_players[0].volume_db = _volume_db.get(cue, -6.0)
	_players[0].play()

## The cue chime, scaled by how much the flash has come to mean (GameState.conditioning).
##
## Volume rather than pitch on purpose: pitch is the kill sound's channel (novelty) and
## sharing an output is what makes a game feel muddy. A well-conditioned cue is simply
## LOUDER — it takes up more of the room, which is exactly what it does in a head.
func play_cue(strength: float) -> void:
	var t: float = clampf(strength, 0.0, 1.0)
	play(&"cue")
	# play() already picked a player and started it; nudge the one that just began.
	for p in _players:
		if p.playing and p.stream == _streams.get(&"cue"):
			p.volume_db = float(_volume_db.get(&"cue", -6.0)) + lerpf(-7.0, 3.0, t)
			return

# ---------------------------------------------------------------- surprise-scaled defeat
#
# ONE SYSTEM, ONE SENSE. The kill sound belongs to NOVELTY and nothing else touches
# it; Tolerance owns colour and saturation, Burnout owns the camera. Sharing an output
# between two systems is what makes a game feel muddy — the player can tell something
# changed but never what caused it, and a lesson they cannot attribute is not a lesson.
#
# So this rides reward PREDICTION ERROR, not downregulation. Schultz: a fully predicted
# reward produces no dopamine response at all. The twentieth kill by the same habit is
# a dull thud not because the player has been abusing anything, but because their brain
# already knew it was coming. The first kill by a habit they just built is bright again,
# instantly, even at high Tolerance.
#
# That asymmetry is the whole design: building something NEW feels alive and is weaker,
# upgrading what already works is correct and progressively silent. The pull toward the
# new button — against the player's own interest, while they can see the numbers — is
# the lesson, and nothing has to say it out loud.
#
# Implementation: two pre-rendered cues (defeat_bright / defeat_dull) crossfaded by how
# worn the killing habit is, with pitch and volume scaled so it is continuous rather
# than a hard switch.

## Call this instead of play() for a kill. `surprise` is GameState.surprise_of(killer):
## 1.0 for a habit that has never scored, falling toward SURPRISE_FLOOR as it repeats.
func play_defeat(surprise: float) -> void:
	# 0.0 = never seen this before, 1.0 = completely worn out. Normalised against the
	# floor so a veteran habit lands at full dullness rather than three quarters of it.
	var t: float = clampf(inverse_lerp(1.0, GameState.SURPRISE_FLOOR,
		clampf(surprise, GameState.SURPRISE_FLOOR, 1.0)), 0.0, 1.0)

	# Below 0.4 worn: bright chime. Above 0.6: dull thud. Between: random mix.
	var cue: StringName
	if t < 0.4:
		cue = &"defeat_bright"
	elif t > 0.6:
		cue = &"defeat_dull"
	else:
		cue = &"defeat_bright" if randf() > (t - 0.4) / 0.2 else &"defeat_dull"

	if not _streams.has(cue):
		return
	var now: int = Time.get_ticks_msec()
	if now - int(_last_ms.get(cue, -99999)) < int(float(_min_gap.get(cue, 0.04)) * 1000.0):
		return
	_last_ms[cue] = now

	# Volume: base dB scaled down by juice loss. Pitch: slightly detuned + flattened.
	var db: float = _volume_db.get(cue, -6.0) + lerpf(0.0, -10.0, t)
	var pitch: float = randf_range(0.97, 1.03) * lerpf(1.0, 0.72, t)

	for p in _players:
		if not p.playing:
			p.stream = _streams[cue]
			p.volume_db = db
			p.pitch_scale = pitch
			p.play()
			return
	_players[0].stream = _streams[cue]
	_players[0].volume_db = db
	_players[0].pitch_scale = pitch
	_players[0].play()

## Returns the juice factor (1.0 = full satisfaction, ~0.15 = numb) for the given
## tolerance ratio. Other systems (particles, screenshake) use this to stay in sync
## with the sound degradation so the whole game feel dims together.
static func juice_factor(tolerance_ratio: float) -> float:
	return lerpf(1.0, 0.15, clampf(tolerance_ratio, 0.0, 1.0))

# ---------------------------------------------------------------- synthesis

func _build_streams() -> void:
	# place — a soft descending thump: something solid was set down.
	_add(&"place", 0.09, -8.0, 0.05,
		func(t: float) -> float: return 0.55 * _chirp(t, 260.0, 180.0, 0.09))

	# error — two low square blips with a gap: "no" said twice, unmistakably not a reward.
	_add(&"error", 0.16, -7.0, 0.10,
		func(t: float) -> float:
			if t >= 0.055 and t < 0.085:
				return 0.0
			return 0.30 * signf(sin(TAU * 145.0 * t)))

	# focus_lost — a falling two-octave cry, the loudest cue in the set. Losing Focus is
	# the one event the player must register even while staring at the other lane.
	_add(&"focus_lost", 0.28, -3.0, 0.25,
		func(t: float) -> float:
			return 0.50 * _chirp(t, 520.0, 170.0, 0.28) + 0.25 * _chirp(t, 260.0, 85.0, 0.28))

	# insight — a bright sparkle of stacked harmonics; the variable-ratio hook.
	_add(&"insight", 0.15, -6.0, 0.09,
		func(t: float) -> float:
			return 0.40 * sin(TAU * 1318.5 * t) + 0.28 * sin(TAU * 1760.0 * t) \
				+ 0.14 * sin(TAU * 2637.0 * t))

	# wave_start — a rising horn (sine + a little square for brass).
	_add(&"wave_start", 0.22, -6.0, 0.30,
		func(t: float) -> float:
			var s := _chirp(t, 220.0, 460.0, 0.22)
			return 0.38 * s + 0.16 * signf(s))

	# card — a two-note confirmation, low then high: a choice was locked in.
	_add(&"card", 0.17, -6.0, 0.15,
		func(t: float) -> float:
			return 0.45 * sin(TAU * (660.0 if t < 0.08 else 880.0) * t))

	# shield up/down — ring-modulated metal. Up sustains, down falls away.
	_add(&"shield_up", 0.18, -5.0, 0.20,
		func(t: float) -> float: return 0.50 * sin(TAU * 115.0 * t) * sin(TAU * 940.0 * t))
	_add(&"shield_down", 0.20, -5.0, 0.20,
		func(t: float) -> float:
			return 0.50 * sin(TAU * 115.0 * t) * _chirp(t, 700.0, 250.0, 0.20))

	# click — a tiny tick for every button; barely there, but the UI stops feeling numb.
	_add(&"click", 0.03, -14.0, 0.03,
		func(t: float) -> float: return 0.30 * sin(TAU * 1150.0 * t))

	# cue — the conditioned signal. Deliberately the most DISTINCTIVE two notes in the
	# set and never used for anything else, because the entire mechanic depends on the
	# player learning it without noticing they learned it (game.gd:_fire_cue).
	#
	# It precedes every real reward for the first two levels, then starts firing empty.
	# Pavlov, then Schultz: the dopamine response migrates backwards from the reward
	# onto whatever reliably predicts it, which is why an app icon works on you and the
	# content behind it does not have to.
	_add(&"cue", 0.13, -9.0, 0.12,
		func(t: float) -> float:
			var note := 1567.98 if t < 0.05 else 2093.0  # G6 → C7, a doorbell-bright pair
			return 0.30 * sin(TAU * note * t) + 0.10 * sin(TAU * note * 2.0 * t))

	# defeat_bright — a rising two-note chime with stacked harmonics: the satisfying
	# kill sound at clean (low-tolerance) play. Bright, clear, the kind of ding that
	# makes you want another. This is what downregulation takes away.
	_add(&"defeat_bright", 0.18, -7.0, 0.04,
		func(t: float) -> float:
			var note := 880.0 if t < 0.07 else 1174.7  # A5 → D6 (ascending = reward)
			return 0.35 * sin(TAU * note * t) \
				+ 0.20 * sin(TAU * note * 2.0 * t) \
				+ 0.10 * sin(TAU * note * 3.0 * t))

	# defeat_dull — a short, low, muffled thump: the same event heard through the fog
	# of high Tolerance. No harmonics, no sparkle — just a dead weight landing. The
	# player does not need to be told the game is less fun; they can hear it.
	_add(&"defeat_dull", 0.10, -10.0, 0.04,
		func(t: float) -> float:
			return 0.40 * _chirp(t, 180.0, 90.0, 0.10))

## Renders one cue: generator -> attack/release envelope -> 16-bit mono WAV.
func _add(cue: StringName, duration: float, db: float, min_gap: float,
		gen: Callable, attack: float = 0.004, release: float = 0.05) -> void:
	var n: int = int(duration * SAMPLE_RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in range(n):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = minf(1.0, t / attack) * clampf((duration - t) / release, 0.0, 1.0)
		var v: float = clampf(float(gen.call(t)) * env, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(v * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = bytes
	_streams[cue] = wav
	_volume_db[cue] = db
	_min_gap[cue] = min_gap

## Linear frequency sweep with correct phase (naive sin(TAU * f(t) * t) warbles).
func _chirp(t: float, f0: float, f1: float, dur: float) -> float:
	return sin(TAU * (f0 * t + 0.5 * (f1 - f0) / dur * t * t))
