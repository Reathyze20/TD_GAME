class_name RunLog extends RefCounted
## Per-wave telemetry for a single run, appended to user://runlog.csv.
##
## This exists because every balance question about this game has so far been answered
## with arithmetic instead of evidence — "level 1 is probably too easy", "wave 15 is
## probably a wall". One playthrough with this attached turns those into a curve you can
## read: where Focus actually starts dropping, what the player actually built, how long
## each wave actually took, and whether the frame rate held.
##
## Appends rather than truncates, and stamps every row with a run id, so successive
## playtests accumulate into one comparable dataset.

const PATH := "user://runlog.csv"

const COLUMNS: PackedStringArray = [
	"run_id", "level", "wave", "wave_seconds", "avg_frame_ms",
	"focus", "max_focus", "focus_lost_total",
	"dopamine", "run_insight", "insight_spent", "kills_total",
	"tolerance", "tolerance_floor",
	"towers_total", "anchors", "towers_in_routine", "towers_by_type",
	"cards_taken", "outcome",
]

var _run_id: String = ""
var _level_id: String = ""
var _run_start_ms: int = 0
var _wave_start_ms: int = 0
var _frame_accum := 0.0
var _frame_count := 0
var _open := false

func begin(level_id: String) -> void:
	_run_id = "%d" % Time.get_unix_time_from_system()
	_level_id = level_id
	_run_start_ms = Time.get_ticks_msec()
	_wave_start_ms = _run_start_ms
	_frame_accum = 0.0
	_frame_count = 0
	_open = true
	_ensure_header()

## Called every frame by Game._process so the row can report the frame cost the player
## actually experienced during that wave — the one number a headless test cannot produce.
func tick(delta: float) -> void:
	if not _open:
		return
	_frame_accum += delta
	_frame_count += 1

func _ensure_header() -> void:
	if FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("RunLog: cannot open %s (%s)" % [PATH, FileAccess.get_open_error()])
		return
	f.store_line(",".join(COLUMNS))
	f.close()

## One row. `outcome` is "" mid-run, or "victory"/"defeat" on the closing row.
func write_wave(wave: int, fields: Dictionary, outcome: String = "") -> void:
	if not _open:
		return
	var now := Time.get_ticks_msec()
	var wave_seconds := float(now - _wave_start_ms) / 1000.0
	var avg_frame_ms := (_frame_accum / float(maxi(1, _frame_count))) * 1000.0

	var row: Array[String] = [
		_run_id, _level_id, str(wave),
		"%.1f" % wave_seconds, "%.2f" % avg_frame_ms,
		str(fields.get("focus", 0)), str(fields.get("max_focus", 0)),
		str(fields.get("focus_lost_total", 0)),
		str(fields.get("dopamine", 0)), str(fields.get("run_insight", 0)),
		str(fields.get("insight_spent", 0)), str(fields.get("kills_total", 0)),
		"%.0f" % float(fields.get("tolerance", 0.0)),
		"%.0f" % float(fields.get("tolerance_floor", 0.0)),
		str(fields.get("towers_total", 0)), str(fields.get("anchors", 0)),
		str(fields.get("towers_in_routine", 0)),
		_csv_escape(String(fields.get("towers_by_type", ""))),
		_csv_escape(String(fields.get("cards_taken", ""))),
		outcome,
	]

	var f := FileAccess.open(PATH, FileAccess.READ_WRITE)
	if f == null:
		push_warning("RunLog: cannot append to %s" % PATH)
		return
	f.seek_end()
	f.store_line(",".join(row))
	f.close()

	# Reset the per-wave accumulators only after a successful write.
	_wave_start_ms = now
	_frame_accum = 0.0
	_frame_count = 0

func end() -> void:
	_open = false

## Quotes any field containing a comma or quote — "towers_by_type" is a semicolon-joined
## list and "cards_taken" is free text, so both can otherwise break column alignment.
static func _csv_escape(s: String) -> String:
	if s.contains(",") or s.contains("\"") or s.contains("\n"):
		return "\"%s\"" % s.replace("\"", "\"\"")
	return s
