class_name Receipt extends RefCounted
## The post-level mirror: what the player did, in their own numbers, with no comment.
##
## Four rules, and they are all about credibility rather than layout:
##
##  1. THREE NUMBERS. Everything else folds away. Ten statistics is a dashboard and
##     nobody reads a dashboard about themselves.
##  2. EVERY NUMBER IS A PAIR. "Prep phase: 3s" says nothing. "22s → 3s" is the whole
##     finding. The player is their own control group, which is the only comparison this
##     game is willing to make — a leaderboard would be the exact mechanic it is warning
##     about.
##  3. NEVER DURING PLAY. This screen only ever appears after the wave is over. A popup
##     mid-level is nagging; the same sentence afterwards is a mirror.
##  4. NO VERDICT. No "should", no "too many", no grade, no encouragement. The game
##     never tells the player they have a problem — it shows behaviour and lets them do
##     their own arithmetic. The moment it diagnoses, defences go up and learning stops.
##
## Laid out to be screenshot-able on purpose: legible small, no branding across half the
## frame, sharpest line at the top. What spreads is somebody's own self-knowledge, which
## is the only marketing this game can run without becoming a hypocrite.

## Returns null when there is nothing honest to show yet (designer run, or a first level
## with no prior row to pair against). A receipt with one unpaired number on it is worse
## than no receipt.
static func build(width: float = 1000.0) -> Control:
	var now: Dictionary = Mirror.summarise()
	var first: Dictionary = Mirror.baseline_row(int(now.get("level", -1)))
	var rows := _rows(now, first)
	var headline := _headline(now, first)
	if rows.is_empty() and headline.is_empty():
		return null

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)

	box.add_child(UI.label("DURING THIS LEVEL", UI.FS_MICRO, UI.TEXT_FAINT))

	# The sharpest finding, large and alone. One number the player cannot look past.
	if not headline.is_empty():
		var hl := UI.panel(UI.TOLERANCE, 1)
		box.add_child(hl)
		var hb := VBoxContainer.new()
		hb.add_theme_constant_override("separation", 2)
		hl.add_child(hb)
		hb.add_child(UI.label(headline["value"], UI.FS_TITLE, UI.TOLERANCE))
		hb.add_child(UI.wrapped(headline["caption"], width - 40, UI.FS_BODY, UI.TEXT_DIM))

	for r: Dictionary in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		box.add_child(line)
		var caption := UI.label(r["label"], UI.FS_BODY, UI.TEXT_DIM)
		caption.custom_minimum_size = Vector2(width * 0.45, 0)
		line.add_child(caption)
		if r["has_pair"]:
			line.add_child(UI.label(r["first"], UI.FS_BODY, UI.TEXT_FAINT))
			line.add_child(UI.label("→", UI.FS_BODY, UI.TEXT_FAINT))
		line.add_child(UI.label(r["now"], UI.FS_HEAD, UI.TEXT))

	box.add_child(UI.spacer(Vector2(0, 4)))
	# The promise, and the last lesson. It is only worth printing because it is true:
	# Mirror writes to user://mirror.json and nothing sends it anywhere.
	box.add_child(UI.label(
		"None of this left your computer. Guess how often that was true today.",
		UI.FS_MICRO, UI.TEXT_FAINT))
	return box

# ---------------------------------------------------------------- content

## The one line worth putting in 40pt, chosen by what actually happened rather than by a
## fixed priority — a level where the player ignored every ad should not lead with ads.
static func _headline(now: Dictionary, first: Dictionary) -> Dictionary:
	var cue_t: float = float(now.get("cue_reaction_time", -1.0))
	var threat_t: float = float(now.get("threat_reaction_time", -1.0))
	if cue_t >= 0.0 and threat_t >= 0.0 and cue_t < threat_t:
		return {
			"value": "%.1fs  vs  %.1fs" % [cue_t, threat_t],
			"caption": "Time to react to the cue, and to a real threat.",
		}

	var tapped: int = int(now.get("ads_tapped", 0))
	if tapped > 0:
		return {
			"value": "%d" % tapped,
			"caption": "Times you took the ad's offer. You knew exactly what it was.",
		}

	# Effort discounting, and it leads because it is the only number here the player will
	# not believe until they see it. They watched themselves trade damage for fewer
	# clicks, on purpose, with the numbers visible the whole time. Only shown when they
	# actually gave something up — a player who never tuned the wheel surrendered 0%, and
	# printing that as a finding would be inventing one.
	var surrendered: float = float(now.get("aim_surrendered", -1.0))
	if surrendered > 1.02:
		return {
			"value": "%d%%" % int(round((surrendered - 1.0) * 100.0)),
			"caption": "Extra damage your own aiming was worth. You handed it back when it got tedious.",
		}

	# Ranked above everything below because it is the only line on the screen about
	# RECOVERY, and recovery is the part people get wrong about themselves. Stated as
	# what happened, with no advice attached — rule 4 is doing the heavy lifting here.
	var again: int = int(now.get("cue_reinstatements", 0))
	if again > 0:
		return {
			"value": "%d" % again,
			"caption": "Times the signal had gone quiet, and one real payout brought it straight back.",
		}

	# The cleanest arithmetic on the whole screen, which is why it outranks everything
	# below it: fleeting distractions do exactly 0 Focus damage, so the shots spent on
	# them bought nothing and the game does not have to claim that — it just prints both
	# numbers. Rule 4 holds: no verdict, no "should".
	var bait: int = int(now.get("bait_kills", 0))
	if bait > 0:
		return {
			"value": "%d" % bait,
			"caption": "Limited-time offers you shot down. All of them were leaving on their own.",
		}

	var stolen: int = int(now.get("autoplay_thefts", 0))
	if stolen > 0:
		return {
			"value": "%d" % stolen,
			"caption": "Times the next wave started without being asked.",
		}

	# Only a streak long enough to have started FEELING like something owned. Below
	# four the loss frame has not formed yet and printing it would be inventing a
	# feeling the player did not have.
	var lost: float = float(now.get("streak_lost", -1.0))
	if lost >= 4.0:
		return {
			"value": "%d" % int(lost),
			"caption": "Waves in a row you had going when it broke. What you lost was a bonus you had not been paid yet.",
		}

	var flashes: int = int(now.get("cue_flashes", 0))
	var reacts: int = int(now.get("cue_reactions", 0))
	if flashes >= 4 and reacts > 0:
		return {
			"value": "%d of %d" % [reacts, flashes],
			"caption": "Times the signal pulled you. Most of them meant nothing.",
		}

	var qh: int = int(now.get("quick_hits", 0))
	if qh > 0:
		return {"value": "%d" % qh, "caption": "Quick Hits."}

	var speed_now: float = float(now.get("speed_fraction", 0.0))
	var speed_first: float = float(first.get("speed_fraction", 0.0))
	if speed_now > 0.35 and speed_now > speed_first + 0.2:
		return {
			"value": "%d%%" % int(round(speed_now * 100.0)),
			"caption": "Of this level played at speed. Nothing got harder.",
		}
	return {}

static func _rows(now: Dictionary, first: Dictionary) -> Array:
	# Rule 2 is absolute: with no earlier level on record there is nothing to pair
	# against, so the rows are simply not shown. A column of unpaired numbers reads as a
	# score, and a score is the one thing this screen must never be.
	#
	# `first` is already Mirror.baseline_row(current level) — the earliest level actually
	# played, not the literal id 1 (see that function for why the difference matters).
	var has_first: bool = not first.is_empty()
	if not has_first:
		return []
	var out: Array = []

	_maybe(out, has_first, "Quick Hits", now, first, "quick_hits",
		func(v): return "%d" % int(v))
	_maybe(out, has_first, "Time in the build phase", now, first, "prep_seconds",
		func(v): return "%.0fs" % float(v))
	_maybe(out, has_first, "Time at speed", now, first, "speed_fraction",
		func(v): return "%d%%" % int(round(float(v) * 100.0)))
	_maybe(out, has_first, "Limited-time offers shot", now, first, "bait_kills",
		func(v): return "%d" % int(v))

	# Sits next to the behaviour rows on purpose. The player reads "time in the build
	# phase: 22s → 3s" and then "what the flash means: 40% → 90%" in the same column,
	# and nothing has to draw the line between them.
	_maybe(out, has_first, "Longest run without a leak", now, first, "streak_best",
		func(v): return "%d" % int(v))

	_maybe(out, has_first, "Waves that aimed themselves", now, first, "auto_aim_waves",
		func(v): return "%d" % int(v))

	_maybe(out, has_first, "What the flash means", now, first, "cue_pull",
		func(v): return "%d%%" % int(round(float(v) * 100.0)))

	# Only shown once there is a curve to show. A single patience reading is noise; the
	# finding is that the curve steepens.
	if float(now.get("patience", -1.0)) >= 0.0:
		_maybe(out, has_first and float(first.get("patience", -1.0)) >= 0.0,
			"Waited for the larger payout", now, first, "patience",
			func(v): return "%d%%" % int(round(float(v) * 100.0)))

	# Ranked by how much the number actually MOVED, then cut to three. A row that reads
	# "0% → 0%" is dead weight: it costs a line, says nothing, and dilutes the two rows
	# that do say something. The receipt's job is to be pointed, not complete — the full
	# log is still in Mirror for anyone who wants it.
	out.sort_custom(func(a, b): return float(a["drift"]) > float(b["drift"]))
	while not out.is_empty() and float(out[-1]["drift"]) <= 0.0:
		out.pop_back()
	return out.slice(0, 3)

static func _maybe(out: Array, has_first: bool, label: String, now: Dictionary,
		first: Dictionary, key: String, fmt: Callable) -> void:
	if not now.has(key):
		return
	var v = now[key]
	if v == null or float(v) < 0.0:
		return
	var was: float = float(first.get(key, 0.0))
	# Relative drift, so a fraction (0.12 → 0.78) and a duration (22s → 3s) can be ranked
	# against each other at all. Guarded against a zero baseline, which would otherwise
	# make every first-time statistic infinitely interesting.
	var drift: float = absf(float(v) - was) / maxf(absf(was), 1.0)
	out.append({
		"label": label,
		"now": String(fmt.call(v)),
		"first": String(fmt.call(was)) if has_first else "",
		"has_pair": has_first and first.has(key),
		"drift": drift,
	})
