extends Node
## Odehraje iso kampaň od začátku, v NORMÁLNÍM režimu.
##
## Záměrně bez jediné cheat klávesy, a to je celý důvod, proč to není `_play_iso`:
## designer mód vypíná Mirror i RunLog (ptá se na `GameState.designer_mode`), takže
## v `_play_iso` účtenka **nikdy nemůže nic ukázat**. A účtenka je půlka téhle hry.
##
## Co se má stát, když to dohraješ:
##
##   level 98 "First Light"  — čistá TD, `cue_phase 1`: modrý záblesk veze VŽDYCKY
##                                 skutečnou odměnu, a tím si staví význam
##   → insight karta "The Cue"   — Schultz 1997, proč se dopamin stěhuje na předzvěst
##   → účtenka BEZ řádků         — není s čím párovat, a jedno číslo bez páru je skóre
##   level 99 "Iso Slice"        — `cue_phase 2`: stejný záblesk, teď většinou o ničem
##   → insight karta "Wanting Is Not Liking"
##   → účtenka S ŘÁDKY           — poprvé "předtím → teď"
##
## Ten druhý záblesk funguje jen proto, že první level byl poctivý. Přes jeden level se
## to zahrát nedá — kvůli tomu ta dvojka vznikla.
##
## Spuštění (NE --headless):
##   godot --path <proj> --main-scene res://scenes/_play_campaign.tscn

const START_LEVEL_ID := 98

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var found := false
	for i in range(Data.get_level_count()):
		if Data.get_level(i).id == START_LEVEL_ID:
			GameState.current_level_index = i
			found = true
			break
	if not found:
		push_error("_play_campaign: level id %d neexistuje" % START_LEVEL_ID)
		return

	# Explicitně, ne spoléháním na výchozí hodnotu: kdyby v procesu zůstal zapnutý
	# designer mód z jiného harnessu, tenhle běh by tiše nic nezaznamenal a účtenka by
	# vyšla prázdná bez jediné stopy proč.
	GameState.designer_mode = false

	add_child(load("res://scenes/Game.tscn").instantiate())
	await get_tree().process_frame

	print("""
=== ISO KAMPAN ===
  Zadne cheaty - jinak by ucetnka lhala.

  level 98  First Light   cista TD, cue_phase 1 (zablesk vzdy neco znamena)
  level 99  Iso Slice         cue_phase 2 + vsechny 4 archetypy distrakci

  Na co se divat:
   * FOMO (ruzova)      zmizi sama po 7 s a NEUBERE Focus. Strilis ji stejne?
   * Just One More      umira na 2 mensi kopie, 3 generace
   * Autoplay (oranz.)  prezije 18 s -> dalsi vlna se spusti sama za 5 s
   * Comparison (modra) ztvrdne proti kanalu, do ktereho jsi investoval nejvic
   * Tolerance nad 45  mireni ztezkne (krok kolecka 10 -> 4 stupne) a hra nabidne
                        klavesu A: navyky se miri samy, ale vzdas se sveho doladeni
   * modry zablesk      po case zesili a zvetsi se - to je ta asociace
   * po levelu          insight karta s citaci + ucetnka
""")
