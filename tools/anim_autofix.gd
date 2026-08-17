extends Node
## Davkove srovnani pohledu pres celou sadu prisery.
##
##   godot --headless --path <projekt> --main-scene res://tools/anim_autofix.tscn
##   godot ... --main-scene res://tools/anim_autofix.tscn -- --dry
##
## CO DELA A CO ZAMERNE NEDELA
##
## Dela jedinou vec: postavi kazdy pohled (north, east, attack, death) na stejnou linku,
## na jake stoji south. Kdyz prisera pri otoceni vyskoci nebo se propadne, je to vada bez
## debaty — nikdo nechtel, aby group_chat pri zataceni klesl o tri pixely.
##
## NEDELA "Srovnat nohy" ani "Srovnat střed", a to je rozhodnuti, ne nedodelek. Ty dve
## srovnavaji framy UVNITR cyklu, jenze pohyb uvnitr cyklu byva zamer:
##
##   - chuze ma houpat, jinak vypada, ze prisera klouze po lede
##   - smrt se MA hybat; clickbait_death kmita 7 px prave proto, ze se kací k zemi.
##     Davkove srovnat mu spodni hranu znamena to padnuti smazat.
##
## Rozlisit "houpe se zameme" od "generator to netrefil" je ukol pro oko, ne pro skript.
## Od toho je dock: linter to najde, panel to ukaze vedle sebe a ty rozhodnes jednim
## kliknutim. Tenhle nastroj bere jen to, kde zadne rozhodovani neni.
##
## Logika zarovnani se sem NEKOPIRUJE — instancuje se primo panel z addons/td_anim_lab a
## vola se jeho vlastni _align_views(). Dve kopie stejne matematiky by se rozesly.

const DOCK := "res://addons/td_anim_lab/dock.gd"

func _ready() -> void:
	var dry := "--dry" in OS.get_cmdline_user_args()

	var dock: Control = (load(DOCK) as GDScript).new()
	add_child(dock)

	var ids: Array = dock.get("_ids")
	if ids == null or ids.is_empty():
		print("Zadny art k srovnani.")
		get_tree().quit(1)
		return

	var touched := 0
	var moved_total := 0
	print("%-22s %s" % ["prisera", "posun pohledu proti south"])
	for id: String in ids:
		dock.call("_select_id", id)
		var stats: Dictionary = dock.get("_stats")
		if not stats.has(""):
			print("%-22s (nema south — preskoceno)" % id)
			continue
		var ref: int = int((stats[""] as Dictionary)["base_ref"])

		var parts: Array[String] = []
		for s in stats.keys():
			if s == "":
				continue
			var st: Dictionary = stats[s]
			if int(st["n"]) == 0:
				continue
			var d: int = ref - int(st["base_ref"])
			if d != 0:
				parts.append("%s %+d" % [String(s).trim_prefix("_"), -d])
		if parts.is_empty():
			continue

		dock.call("_align_views")
		touched += 1
		moved_total += parts.size()
		print("%-22s %s" % [id, ", ".join(parts)])

	if touched == 0:
		print("\nVsechny pohledy uz sedi, neni co menit.")
		get_tree().quit(0)
		return

	if dry:
		print("\n--dry: %d prisery, %d pohledu by se srovnalo. Nic se neulozilo."
			% [touched, moved_total])
		get_tree().quit(0)
		return

	var tuning: AnimTuning = dock.get("_tuning")
	var err := ResourceSaver.save(tuning, AnimTuning.PATH)
	if err != OK:
		print("\nUlozeni selhalo (chyba %d)" % err)
		get_tree().quit(1)
		return
	print("\nSrovnano %d pohledu u %d priser -> %s" % [moved_total, touched, AnimTuning.PATH])
	print("PNG se nezmenily; zpet to vrati smazani toho souboru.")
	get_tree().quit(0)
