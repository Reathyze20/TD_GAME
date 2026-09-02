class_name SimRecorder
extends SimStrategy
## Wraps another SimStrategy and records a per-wave snapshot while it plays, without
## changing a single decision it makes (M1, docs/refactor -> PATHFINDING.MD).
##
## WHY A WRAPPER AND NOT A HOOK IN LevelSimulator: S2's determinism guarantee rests on
## the simulator driving the SAME functions the UI calls and on the strategy being the
## only source of decisions. Adding sampling INSIDE LevelSimulator would put measurement
## code on the determinism-critical path for every existing caller (_test_timecontrol
## proves 1x == 4x bit-identically through it). A wrapper is inert by construction: it
## forwards every hook verbatim and only reads state.
##
## The summary table alone could not answer M1's question. "died at wave 2 with 0 kills"
## does not say whether the run was lost because nothing could kill, because too much
## leaked at once, or because the money ran out -- those are three different repairs.
## The per-wave rows separate them.

## The strategy actually making the decisions. Every hook below forwards to it unchanged.
var inner: SimStrategy = null

## One entry per wave that was ENTERED, appended when the wave index moves and once more
## when the run ends. Keys: wave, kills, kills_delta, focus, focus_delta, dopamine,
## tolerance, frame.
var waves: Array[Dictionary] = []

var _last_wave := -1
var _last_kills := 0
var _last_focus := -1
var _frame := 0


func _init(wrapped: SimStrategy = null) -> void:
	inner = wrapped


func on_build_tick(sim: LevelSimulator) -> void:
	_sample(sim)
	if inner != null:
		inner.on_build_tick(sim)


func on_wave_tick(sim: LevelSimulator) -> void:
	_sample(sim)
	if inner != null:
		inner.on_wave_tick(sim)


func on_draft(sim: LevelSimulator, options: Array[CardData]) -> CardData:
	if inner != null:
		return inner.on_draft(sim, options)
	return null


## Closes the final wave's row. LevelSimulator stops ticking the strategy the moment
## game_over fires, so without this the wave the run actually DIED in -- the single most
## interesting row -- would never be written.
func finish(sim: LevelSimulator) -> void:
	_record(sim, true)


func _sample(sim: LevelSimulator) -> void:
	_frame += 1
	if sim.game == null or not is_instance_valid(sim.game):
		return
	if _last_focus < 0:
		_last_focus = GameState.focus
		_last_wave = sim.game.wave_index
		return
	if sim.game.wave_index != _last_wave:
		_record(sim, false)
		_last_wave = sim.game.wave_index


## Reads GameState only, never sim.game: finish() is called AFTER LevelSimulator.run()
## returns, and run() queue_free()s its Game on the way out. GameState is an autoload and
## still holds the run's final numbers at that point, so the last row -- the wave the run
## actually died in -- survives. Guarding on sim.game here would silently drop it.
func _record(_sim: LevelSimulator, final: bool) -> void:
	var kills: int = GameState.kills
	var focus: int = GameState.focus
	waves.append({
		"wave": _last_wave,
		"final": final,
		"kills": kills,
		"kills_delta": kills - _last_kills,
		"focus": focus,
		"focus_delta": focus - _last_focus,
		"dopamine": GameState.dopamine,
		"tolerance": GameState.tolerance,
		"frame": _frame,
	})
	_last_kills = kills
	_last_focus = focus
