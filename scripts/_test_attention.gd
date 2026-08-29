extends Node
## Harness for the attention-lesson systems: novelty (RPE), the wanting/liking split,
## the payout schedule, the Mirror event log and the ad overlay.
##
## Same shape as _test_phase7.gd. Everything here is a rule that is INVISIBLE ON SCREEN
## UNTIL IT IS WRONG, which is the only kind of thing worth a harness:
##
##  * a variable payout whose mean has quietly drifted off the flat schedule it replaced
##    would rebalance every level in the game and look like nothing
##  * novelty that ages the wrong habit still plays a sound, just the wrong one
##  * a receipt that pairs against the wrong row prints a confident, false number — and
##    the receipt's credibility is the entire product
##  * an ad whose button does not actually pay is just a gag, and the lesson dies

var completed := false
var fails := 0

func _ready() -> void:
	var wd := Timer.new()
	wd.wait_time = 60.0
	wd.one_shot = true
	add_child(wd)
	wd.timeout.connect(func():
		if not completed:
			print("FAILED: watchdog fired")
			get_tree().quit(1))
	wd.start()
	call_deferred("_run")

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  ok   %s %s" % [label, detail])
	else:
		fails += 1
		print("  FAIL %s %s" % [label, detail])

func _run() -> void:
	GameState.designer_mode = false
	GameState.reset_for_level(Data.get_level(0))

	_test_novelty()
	_test_payout_schedule()
	_test_wanting_liking()
	_test_mirror()
	_test_receipt()
	_test_ad_overlay()

	completed = true
	print("\n%s (%d failures)" % ["PASSED" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)

# ---------------------------------------------------------------- novelty

func _test_novelty() -> void:
	print("\n-- novelty (reward prediction error)")
	GameState.reset_for_level(Data.get_level(0))

	_check("unseen habit is maximally surprising",
		is_equal_approx(GameState.surprise_of(&"focus_timer"), 1.0))
	_check("no killer reads as surprising",
		is_equal_approx(GameState.surprise_of(&""), 1.0))

	for i in range(GameState.FAMILIARITY_FULL):
		GameState._age_familiarity(&"focus_timer")
	var worn: float = GameState.surprise_of(&"focus_timer")
	_check("a worn habit bottoms out at the floor",
		is_equal_approx(worn, GameState.SURPRISE_FLOOR), "= %.2f" % worn)

	# The whole reason familiarity is per-habit rather than global: building something
	# new has to feel alive again even while the veteran tower is silent. That contrast
	# IS the decision the level is asking the player to make.
	_check("a different habit is untouched",
		is_equal_approx(GameState.surprise_of(&"exercise"), 1.0))

	# Never decays inside a level. Habituation to a stimulus does not wear off while you
	# keep using it — which is precisely why people switch apps instead of waiting.
	for i in range(50):
		GameState._age_familiarity(&"focus_timer")
	_check("wear never recovers mid-level",
		is_equal_approx(GameState.surprise_of(&"focus_timer"), GameState.SURPRISE_FLOOR))

	GameState.reset_for_level(Data.get_level(0))
	_check("reset clears familiarity",
		is_equal_approx(GameState.surprise_of(&"focus_timer"), 1.0))

# ---------------------------------------------------------------- payout schedule

func _test_payout_schedule() -> void:
	print("\n-- payout schedule")
	GameState.reset_for_level(Data.get_level(0))

	GameState.variable_rewards = false
	GameState.steady_payout = false
	_check("flat schedule pays exactly base",
		is_equal_approx(GameState._payout_multiplier(), 1.0))

	# The experiment only means anything if the two schedules have the SAME expected
	# value. If the variable one quietly paid more, every finding about how it feels
	# would be confounded by it also being better.
	GameState.variable_rewards = true
	var total := 0.0
	var n := 40000
	for i in range(n):
		total += GameState._payout_multiplier()
	var mean: float = total / float(n)
	_check("variable schedule has the same expected value", absf(mean - 1.0) < 0.03,
		"mean = %.4f" % mean)

	GameState.steady_payout = true
	_check("Steady Payout is strictly better than the gamble",
		GameState._payout_multiplier() > 1.0 and is_equal_approx(
			GameState._payout_multiplier(), GameState.STEADY_MULT),
		"= %.2fx" % GameState.STEADY_MULT)
	GameState.steady_payout = false

# ---------------------------------------------------------------- wanting vs liking

func _test_wanting_liking() -> void:
	print("\n-- wanting vs liking")
	GameState.reset_for_level(Data.get_level(0))

	_check("craving starts empty", is_equal_approx(GameState.craving, 0.0))
	_check("satisfaction starts full", is_equal_approx(GameState.satisfaction, 100.0))

	var seen_craving := [0.0]
	var seen_sat := [0.0]
	GameState.craving_changed.connect(func(v): seen_craving[0] = v)
	GameState.satisfaction_changed.connect(func(v): seen_sat[0] = v)

	GameState.add_craving(30.0)
	GameState.add_satisfaction(-20.0)
	_check("both emit on change",
		is_equal_approx(seen_craving[0], 30.0) and is_equal_approx(seen_sat[0], 80.0))

	GameState.add_craving(500.0)
	GameState.add_satisfaction(-500.0)
	_check("both clamp to 0..100",
		is_equal_approx(GameState.craving, 100.0) and is_equal_approx(GameState.satisfaction, 0.0))

	# Clearing a wave is the ONLY thing that pays liking back and the only thing that
	# walks wanting down. Without that recovery the pair is a one-way descent, which is
	# a punishment bar rather than a rhythm the player can learn to ride.
	GameState._on_wave_completed(1)
	_check("a cleared wave moves both back",
		GameState.satisfaction > 0.0 and GameState.craving < 100.0,
		"sat %.0f, crav %.0f" % [GameState.satisfaction, GameState.craving])

# ---------------------------------------------------------------- mirror

func _test_mirror() -> void:
	print("\n-- mirror event log")
	Mirror.begin_level(1)
	_check("recording on a non-designer run", Mirror.is_recording())

	Mirror.mark(&"quick_hit", 12)
	Mirror.mark(&"quick_hit", 9)
	_check("counts events", Mirror.count(&"quick_hit") == 2)

	Mirror.mark(&"prep_span", 20.0)
	Mirror.mark(&"prep_span", 10.0)
	_check("averages payloads", is_equal_approx(Mirror.prep_seconds(), 15.0))

	# -1 not 0: "never happened" and "happened instantly" are opposite findings and the
	# receipt must never print them the same way.
	_check("a statistic that never happened reads -1",
		Mirror.mean(&"threat_reaction") < 0.0)

	Mirror.mark(&"cue_flash", false)
	Mirror.mark_click(&"cue")
	_check("a cue pull is timed", Mirror.count(&"cue_reaction") == 1)

	Mirror.mark(&"offer_later")
	Mirror.mark(&"offer_later")
	Mirror.mark(&"offer_now")
	_check("patience is the share that waited",
		absf(Mirror.patience() - (2.0 / 3.0)) < 0.001, "= %.2f" % Mirror.patience())

	var summary := Mirror.summarise()
	_check("summary carries the level id", int(summary.get("level", -1)) == 1)

	# Designer runs write nothing: cheat keys would make every number a lie, and a
	# receipt that can lie is worse than no receipt.
	GameState.designer_mode = true
	Mirror.begin_level(2)
	Mirror.mark(&"quick_hit", 1)
	_check("designer runs record nothing",
		not Mirror.is_recording() and Mirror.count(&"quick_hit") == 0)
	GameState.designer_mode = false

# ---------------------------------------------------------------- receipt

func _test_receipt() -> void:
	print("\n-- receipt")
	Mirror.history.clear()

	Mirror.begin_level(1)
	Mirror.mark(&"prep_span", 22.0)
	Mirror.mark(&"quick_hit", 5)
	Mirror.end_level()
	_check("level 1 is stored for pairing", Mirror.history.has("1"))

	# The baseline is the EARLIEST level on record, not the literal id 1. The isometric
	# branch numbers its slice 99 and has no playable level 1 at all, so a hardcoded "1"
	# meant the receipt silently showed nothing there forever.
	Mirror.history.clear()
	Mirror.begin_level(99)
	Mirror.mark(&"prep_span", 30.0)
	Mirror.end_level()
	Mirror.begin_level(99)
	var iso_base := Mirror.baseline_row(99)
	_check("no baseline when the only record IS this level", iso_base.is_empty())

	Mirror.history.clear()
	Mirror.begin_level(7)
	Mirror.mark(&"prep_span", 18.0)
	Mirror.end_level()
	Mirror.begin_level(3)
	Mirror.mark(&"prep_span", 9.0)
	Mirror.end_level()
	Mirror.begin_level(99)
	var base := Mirror.baseline_row(99)
	_check("baseline is the LOWEST recorded level id, not the first written",
		int(base.get("level", -1)) == 3, "level %d" % int(base.get("level", -1)))
	# Something has to have HAPPENED this level for a row to exist — rows are ranked by
	# how far the number moved and zero-drift rows are dropped on purpose, so an empty
	# current level correctly produces nothing.
	Mirror.mark(&"prep_span", 2.0)
	_check("a level with no id-1 record still pairs",
		not Receipt._rows(Mirror.summarise(), base).is_empty())

	# The real campaign shape, with the ids the game actually ships: 98 then 99. This is
	# the entire reason level 98 exists — with one playable level, baseline_row() has
	# nothing to return and Receipt._rows() is empty forever, so the paired numbers that
	# the whole screen is built on could never appear in normal play.
	Mirror.history.clear()
	Mirror.begin_level(98)
	Mirror.mark(&"prep_span", 26.0)
	Mirror.end_level()
	Mirror.begin_level(99)
	Mirror.mark(&"prep_span", 5.0)
	var iso_base2 := Mirror.baseline_row(99)
	_check("iso campaign has a baseline at last", int(iso_base2.get("level", -1)) == 98,
		"level %d" % int(iso_base2.get("level", -1)))
	var iso_rows: Array = Receipt._rows(Mirror.summarise(), iso_base2)
	_check("iso campaign finally pairs rows", not iso_rows.is_empty(),
		"%d rows" % iso_rows.size())

	print("
-- cue conditioning: recovery does not un-learn it")
	GameState.forget_conditioning()
	for i in range(6):
		GameState.condition_cue(true)
	var learned: float = GameState.conditioning
	_check("honest pairings build the association", learned > 0.9, "%.2f" % learned)

	# Rule 2. The player drains Tolerance, the colour comes back, they are visibly
	# "better" — and the flash pulls exactly as hard. If this ever fails, the game is
	# quietly teaching that recovery erases the association, which is the opposite of
	# what the insight card claims.
	GameState.set_tolerance(90.0)
	GameState.set_tolerance(0.0)
	_check("Tolerance does not touch conditioning",
		is_equal_approx(GameState.conditioning, learned), "%.2f" % GameState.conditioning)

	# Rule 1. Finishing a level does not un-learn it either — this is the only run state
	# that deliberately survives reset_for_level().
	GameState.reset_for_level(Data.get_level(0))
	_check("a new level does not reset conditioning",
		is_equal_approx(GameState.conditioning, learned), "%.2f" % GameState.conditioning)

	# Rule 3a. Extinction is the SLOW direction. Symmetric numbers would teach that
	# unlearning is as easy as learning.
	var before_one_empty: float = GameState.conditioning
	GameState.condition_cue(false)
	var drop: float = before_one_empty - GameState.conditioning
	_check("one empty cue costs less than one honest one",
		drop < GameState.CUE_ACQUIRE, "%.3f < %.3f" % [drop, GameState.CUE_ACQUIRE])

	# Plne vyhasnuti proti plnemu nauceni — ne jen pokles na prah. Prah je kratsi cesta
	# a merit ho by znamenalo tvrdit neco slabsiho, nez co ten design opravdu rika.
	GameState.forget_conditioning()
	var to_learn := 0
	while GameState.conditioning < 0.999 and to_learn < 200:
		GameState.condition_cue(true)
		to_learn += 1
	var to_forget := 0
	while GameState.conditioning > 0.001 and to_forget < 200:
		GameState.condition_cue(false)
		to_forget += 1
	_check("unlearning takes far longer than learning", to_forget >= to_learn * 2,
		"%d empty vs %d honest" % [to_forget, to_learn])

	# Zpatky na vyhasly stav pro test reinstatementu nize.
	GameState.forget_conditioning()
	for i in range(6):
		GameState.condition_cue(true)
	var empties := 0
	while GameState.conditioning > GameState.cue_peak * GameState.CUE_EXTINCT_AT and empties < 60:
		GameState.condition_cue(false)
		empties += 1

	# Rule 3b, the finding the whole block exists for: reinstatement is ONE step.
	var faded: float = GameState.conditioning
	var reinstated: bool = GameState.condition_cue(true)
	_check("a single real payout reports reinstatement", reinstated)
	_check("and it snaps back rather than creeping",
		GameState.conditioning > faded + GameState.CUE_ACQUIRE,
		"%.2f -> %.2f" % [faded, GameState.conditioning])
	_check("back to most of the old peak",
		is_equal_approx(GameState.conditioning,
			GameState.cue_peak * GameState.CUE_REINSTATE_SHARE),
		"%.2f of peak %.2f" % [GameState.conditioning, GameState.cue_peak])
	# Not a second time without fading again — otherwise every honest cue would read as
	# a relapse and the headline would cry wolf every level.
	_check("not reported again while still strong", not GameState.condition_cue(true))

	# The receipt has to be able to name it.
	Mirror.history.clear()
	Mirror.begin_level(98)
	Mirror.mark(&"cue_pull", 0.4)
	Mirror.end_level()
	Mirror.begin_level(99)
	Mirror.mark(&"cue_pull", 0.9)
	Mirror.mark(&"cue_reinstated", 0.9)
	var cue_now := Mirror.summarise()
	_check("summary carries where the pull ENDED, not its average",
		is_equal_approx(float(cue_now.get("cue_pull", -1.0)), 0.9),
		str(cue_now.get("cue_pull", -1.0)))
	var cue_head: Dictionary = Receipt._headline(cue_now, Mirror.baseline_row(99))
	_check("headline names the reinstatement",
		String(cue_head.get("caption", "")).contains("brought it straight back"),
		String(cue_head.get("caption", "")))
	var cue_rows: Array = Receipt._rows(cue_now, Mirror.baseline_row(99))
	var has_pull := false
	for r: Dictionary in cue_rows:
		if String(r["label"]) == "What the flash means":
			has_pull = true
			_check("the pull row pairs both halves", String(r["first"]) == "40%"
				and String(r["now"]) == "90%", "%s -> %s" % [r["first"], r["now"]])
	_check("the pull row is on the receipt", has_pull)
	GameState.forget_conditioning()
	Mirror.history.clear()



	Mirror.history.clear()
	Mirror.begin_level(1)
	Mirror.mark(&"prep_span", 22.0)
	Mirror.mark(&"quick_hit", 5)
	Mirror.end_level()

	# Rule 2 is absolute: with nothing to pair against, the rows are not shown at all. A
	# column of unpaired numbers reads as a score, and a score is the one thing this
	# screen must never be.
	Mirror.begin_level(1)
	Mirror.mark(&"prep_span", 22.0)
	var rows_first: Array = Receipt._rows(Mirror.summarise(), Mirror.baseline_row(1))
	_check("no rows on the first level", rows_first.is_empty())

	Mirror.begin_level(2)
	Mirror.mark(&"prep_span", 3.0)
	Mirror.mark(&"quick_hit", 1)
	var now := Mirror.summarise()
	var rows: Array = Receipt._rows(now, Mirror.baseline_row(2))
	_check("later levels get paired rows", not rows.is_empty(), "%d rows" % rows.size())
	_check("never more than three rows", rows.size() <= 3)
	for r: Dictionary in rows:
		if not bool(r["has_pair"]):
			continue
		_check("row '%s' carries both halves" % r["label"],
			String(r["first"]) != "" and String(r["now"]) != "",
			"%s -> %s" % [r["first"], r["now"]])

	var built := Receipt.build(1000.0)
	_check("receipt builds a control", built != null and built is Control)
	if built != null:
		built.queue_free()
	Mirror.history.clear()
	Mirror.forget()

# ---------------------------------------------------------------- ads

func _test_ad_overlay() -> void:
	print("\n-- ad overlay")
	var ad: AdData = load("res://data/ads/free_dopamine.tres")
	_check("the offer ad loads", ad != null)
	if ad == null:
		return
	# The whole argument rests on this being real. A fake button makes it a gag, and a
	# gag proves nothing about knowing not being enough.
	_check("the offer actually pays", ad.payload_dopamine > 0)
	_check("the offer actually costs", ad.payload_tolerance > 0.0)

	GameState.reset_for_level(Data.get_level(0))
	var dop_before: int = GameState.dopamine
	var tol_before: float = GameState.tolerance

	var overlay := AdOverlay.create(ad)
	add_child(overlay)
	overlay._on_tapped()
	_check("tapping pays the player",
		GameState.dopamine == dop_before + ad.payload_dopamine,
		"+%d" % (GameState.dopamine - dop_before))
	_check("tapping charges Tolerance",
		GameState.tolerance > tol_before,
		"%.0f -> %.0f" % [tol_before, GameState.tolerance])
	_check("tapping raises Craving", GameState.craving > 0.0)

	# The first ad a player ever meets has to be free and after a level. An interstitial
	# that takes Focus before they know this game does jokes reads as hostility.
	var first: AdData = load("res://data/ads/dopamine_clicker.tres")
	_check("the introductory ad is between levels", first.between_levels)
	_check("the introductory ad takes nothing",
		first.payload_dopamine == 0 and first.payload_tolerance == 0.0)

	var honest: AdData = load("res://data/ads/go_outside.tres")
	_check("the honest ad is easy to close", honest.x_size_px >= 48 and honest.x_delay <= 0.1)
