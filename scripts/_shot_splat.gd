extends Node2D
## Ctyri faze splatu vedle sebe na cistem pozadi terasy.
##
## Izolovane schvalne: na herni desce se poloha ImpactFX ve viewportu neda spolehlive
## dopocitat (canvas transform lze), takze se splat soudil na obrazku, kde nebyl. Tady
## je poloha znama, protoze si ji urcim sam.
##
## POZOR NA ROZLISENI: projekt renderuje v 1920x1080 a `canvas_items` to na mensi okno
## ZMENSI. Souradnice uzlu jsou pak v jinem meritku nez pixely snimku (pri okne 900x300
## vyjde snimek 533x300, tedy meritko 0,278) a vyrez podle pozice uzlu mine. Proto se
## tenhle harness pousti v ZAKLADNIM rozliseni, kde je meritko 1.
##
##   godot --path <proj> --main-scene res://scenes/_shot_splat.tscn --resolution 1920x1080
const BG := Color8(184, 165, 135)      # vrch terasy, docs/art/iso_bible.md
var _done := false

func _draw() -> void:
	draw_rect(Rect2(-2000, -2000, 6000, 6000), BG)

func _ready() -> void:
	var fxs: Array = []
	for i in range(4):
		var fx := ImpactFX.new()
		fx.position = Vector2(240 + i * 420, 500)
		add_child(fx)
		fxs.append(fx)
	# Faze se NASTAVUJI, nespoleha se na cas. Prvni pokus je stridal po nekolika
	# snimcich a vsechny vysly v prvni desetine zivota, kdy je splat jeste bod.
	# Strom se zastavi (tween se tim zastavi taky), pak se _progress prepise rucne.
	var stages := [0.10, 0.25, 0.45, 0.70]
	for i in range(4):
		fxs[i].play(Color8(189, 53, 50), 1.0, Vector2(1.0, 0.5), true)
		fxs[i]._progress = stages[i]
		fxs[i].queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for i in range(4):
		print("faze %d: progress %.2f" % [i, fxs[i]._progress])
	get_viewport().get_texture().get_image().save_png("res://build/_splat_stages.png")
	print("SHOT build/_splat_stages.png")
	_done = true
	get_tree().quit(0)
