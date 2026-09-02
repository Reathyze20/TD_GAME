extends Node
## Ověřuje SAMOTNÝ mechanismus y-sortu, který defender_unit.gd, enemy.gd (Distraction)
## i boss.gd sdílejí přes Game.entities (y_sort_enabled = true, scripts/game.gd:277) —
## grep přes celý scripts/ potvrdil, že ŽÁDNÝ z těch tří souborů nenastavuje z_index
## (jen game.gd samo a horde_renderer.gd, oba mimo tenhle mechanismus), takže výsledek
## kreslení mezi defenderem/distrakcí/bossem záleží čistě na tomhle jednom mechanismu.
##
## Test je MĚŘENÝ (čte konkrétní pixel po vykreslení), ne odhad z screenshotu: dva
## neprůhledné čtverce, různá Y, stejný X, uvnitř y_sort_enabled rodiče — a pak se
## čte barva na jejich průniku, aby šlo tvrdit "kreslí se v tomhle pořadí", ne jen
## "vypadá to tak".
##
## Jednorázový diagnostický harness pro P-render-anchor (anchoring/shadow úkol),
## NE trvalá _test_* fixture podle docs/REFACTOR_PLAN.md vzoru — smazat i s .tscn
## a .gd.uid po použití.
##
## Spuštění (NE --headless, kreslení potřebuje skutečný renderer):
##   godot --path <proj> --main-scene res://scenes/_diag_ysort_check.tscn

const RES := 64

class Sq:
	extends Node2D
	var col: Color
	var half: float

	func _draw() -> void:
		draw_rect(Rect2(-half, -half, half * 2.0, half * 2.0), col, true)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(RES, RES)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	add_child(vp)

	var parent := Node2D.new()
	parent.y_sort_enabled = true
	vp.add_child(parent)

	# A (červený) má MENŠÍ Y (výš na obrazovce) -> y-sort ho má kreslit VZADU.
	var a := Sq.new()
	a.col = Color(1, 0, 0, 1)
	a.half = 20.0
	a.position = Vector2(RES * 0.5, RES * 0.5 - 8.0)
	parent.add_child(a)

	# B (modrý) má VĚTŠÍ Y (níž) -> y-sort ho má kreslit PŘED A, tedy navrchu na
	# jejich průniku. Přidán DO STROMU JAKO PRVNÍ POTOMEK by dokazoval jen strom-
	# pořadí; přidán DRUHÝ ukazuje, že by bez y-sortu kreslil navrchu i tak — proto
	# je druhý test níž (pořadí ve stromu obrácené) skutečným důkazem, že o pořadí
	# rozhoduje Y, ne pozice ve stromu.
	var b := Sq.new()
	b.col = Color(0, 0, 1, 1)
	b.half = 20.0
	b.position = Vector2(RES * 0.5, RES * 0.5 + 8.0)
	parent.add_child(b)

	for _f in range(4):
		await get_tree().process_frame

	var img := vp.get_texture().get_image()
	var mid := img.get_pixel(RES / 2, RES / 2)
	var pass1 := mid.is_equal_approx(Color(0, 0, 1, 1))
	print("_diag_ysort_check: test 1 (B přidán DRUHÝ do stromu) pixel = %s -> %s" %
		[mid, "PASS" if pass1 else "FAIL"])

	# Test 2: stejné pozice, ale A a B se ve stromu PROHODÍ (A přidán druhý). Pokud by
	# výsledek závisel na pořadí přidání do stromu místo na Y, test 2 by teď dopadl
	# opačně než test 1 — a nedopadl.
	a.queue_free()
	b.queue_free()
	await get_tree().process_frame
	var b2 := Sq.new()
	b2.col = Color(0, 0, 1, 1)
	b2.half = 20.0
	b2.position = Vector2(RES * 0.5, RES * 0.5 + 8.0)
	parent.add_child(b2)
	var a2 := Sq.new()
	a2.col = Color(1, 0, 0, 1)
	a2.half = 20.0
	a2.position = Vector2(RES * 0.5, RES * 0.5 - 8.0)
	parent.add_child(a2)   # A teď PŘIDÁN DRUHÝ, ale pořád menší Y

	for _f in range(4):
		await get_tree().process_frame

	var img2 := vp.get_texture().get_image()
	var mid2 := img2.get_pixel(RES / 2, RES / 2)
	var pass2 := mid2.is_equal_approx(Color(0, 0, 1, 1))
	print("_diag_ysort_check: test 2 (A přidán DRUHÝ do stromu) pixel = %s -> %s" %
		[mid2, "PASS" if pass2 else "FAIL"])

	var ok := pass1 and pass2
	print("_diag_ysort_check: %s — y-sort řadí podle Y pozice, ne podle pořadí přidání do stromu" %
		("CELKOVĚ PASS" if ok else "CELKOVĚ FAIL"))
	get_tree().quit(0 if ok else 1)
