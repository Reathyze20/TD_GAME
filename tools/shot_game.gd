extends SceneTree
## Vyfotí rozehranou hru do PNG, aby se rastr dal zkontrolovat okem, ne odhadem.
##
## Spuštění (NE --headless, kreslení potřebuje skutečný renderer):
##   godot --path <proj> --script res://tools/shot_game.gd -- --out build/shot.png --frames 90
##
## PROČ VLASTNÍ SKRIPT A NE PROSTĚ SPUSTIT HRU
## Kontrola rastru je otázka „sedí velikost pixelu terénu, příšer a věží?" a ta se
## zodpoví z jednoho snímku. Spustit hru a fotit ručně znamená pokaždé jiný okamžik,
## takže dva snímky před a po změně nejdou položit vedle sebe.
##
## Čeká se na SNÍMKY, ne na čas: terén se staví v _build_field() během prvního
## _process, dekor a stíny o snímek později. Pevná pauza by podle zatížení stroje
## někdy vyfotila prázdné pole.

func _initialize() -> void:
	var out := "build/shot.png"
	var frames := 90
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
		elif args[i] == "--frames" and i + 1 < args.size():
			frames = int(args[i + 1])
	_run(out, frames)


func _run(out: String, frames: int) -> void:
	var scene: PackedScene = load("res://scenes/Game.tscn")
	if scene == null:
		printerr("shot_game: res://scenes/Game.tscn se nenačetla")
		quit(1)
		return
	var node := scene.instantiate()
	root.add_child(node)

	# Brain Fog schvalne VYPINAME. Kontrolujeme rastr a kresbu, a tma je herni
	# mechanika, ne chyba — pod ni nejde poznat, jestli teren sedi na bunku.
	# Game.fog_enabled ma setter, ktery navic zastavi celou maskovaci rouru, takze
	# se za neco, co stejne nechceme videt, ani neplati.
	if "fog_enabled" in node:
		node.fog_enabled = false

	# Ručně otáčíme smyčkou, takže _process a _draw proběhnou stejně jako ve hře.
	for i in range(frames):
		await process_frame

	var img := root.get_texture().get_image()
	var dir := out.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := img.save_png(out)
	if err != OK:
		printerr("shot_game: uložení selhalo, kód %d" % err)
		quit(1)
		return
	print("shot_game: %s  %dx%d po %d snímcích" % [out, img.get_width(), img.get_height(), frames])
	quit(0)
