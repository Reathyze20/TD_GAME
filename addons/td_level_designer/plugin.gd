@tool
extends EditorPlugin
## Mounts the TD Level Designer dock. All level logic lives in tools/map_editor.gd —
## this file only hosts the dock and feeds it scene-change events, so the buttons and
## metrics stay visible no matter which node is selected.

var _dock: Control = null

func _enter_tree() -> void:
	_dock = preload("res://addons/td_level_designer/dock.gd").new()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)
	scene_changed.connect(_on_scene_changed)

func _exit_tree() -> void:
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	remove_control_from_docks(_dock)
	_dock.queue_free()
	_dock = null

func _on_scene_changed(root: Node) -> void:
	if _dock != null:
		_dock.bind_scene(root)
