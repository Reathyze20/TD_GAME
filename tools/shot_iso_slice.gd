extends SceneTree

func _initialize() -> void:
	var out := "build/iso_slice.png"
	var frames := 30
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
		elif args[i] == "--frames" and i + 1 < args.size():
			frames = int(args[i + 1])
	_run(out, frames)

func _run(out: String, frames: int) -> void:
	var scene: PackedScene = load("res://scenes/test_slice.tscn")
	if scene == null:
		printerr("shot_iso_slice: scéna se nenačetla")
		quit(1)
		return
	var node := scene.instantiate()
	root.add_child(node)

	for i in range(frames):
		await process_frame

	var img := root.get_texture().get_image()
	var dir := out.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := img.save_png(out)
	if err != OK:
		printerr("shot_iso_slice: uložení selhalo, kód %d" % err)
		quit(1)
		return
	print("shot_iso_slice: %s %dx%d po %d snímcích" % [out, img.get_width(), img.get_height(), frames])
	quit(0)
