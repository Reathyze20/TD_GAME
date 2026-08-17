@tool
extends EditorPlugin
## Mounts the Animation Lab dock.
##
## Deliberately thinner than td_level_designer's plugin: that one has to bind to the
## MapEditor node of the edited scene, so it polls and follows scene changes. This dock
## reads PNGs off disk and one resource, so it needs no scene at all and works with the
## project freshly opened and nothing loaded.
##
## Slot is RIGHT_BL so it sits under the level designer instead of fighting it for tabs.

var _dock: Control = null

func _enter_tree() -> void:
	_dock = preload("res://addons/td_anim_lab/dock.gd").new()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_BL, _dock)

func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
