extends SceneTree
## Generates a minimal `_test_*.tscn` wrapper (a bare Node with the harness script
## attached) via PackedScene.pack() + ResourceSaver.save(), per CLAUDE.md's "Scény"
## rule: new scenes are made programmatically, never hand-typed.
##
## Usage: godot --headless --script tools/make_test_scene.gd -- <node_name> <script_res_path> <out_tscn_path>
## Example: godot --headless --script tools/make_test_scene.gd -- \
##   TestEconomyCharacterization res://scripts/_test_economy_characterization.gd \
##   res://scenes/_test_economy_characterization.tscn

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		push_error("usage: make_test_scene.gd <node_name> <script_res_path> <out_tscn_path>")
		quit(1)
		return

	var node_name: String = args[0]
	var script_path: String = args[1]
	var out_path: String = args[2]

	var script := load(script_path)
	if script == null:
		push_error("could not load script: %s" % script_path)
		quit(1)
		return

	var root := Node.new()
	root.name = node_name
	root.set_script(script)

	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		push_error("pack() failed: %s" % pack_err)
		quit(1)
		return

	var save_err := ResourceSaver.save(packed, out_path)
	if save_err != OK:
		push_error("save() failed: %s" % save_err)
		quit(1)
		return

	print("wrote %s" % out_path)
	quit(0)
