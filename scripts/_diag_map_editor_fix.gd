extends Node
## Jednorázová diagnostika: ověří, že scenes/MapEditor.tscn po opravě
## dangling ext_resource (level_iso_1.tres smazané v T6) nahrává čistě
## a target_level ukazuje na existující level. Smaž po použití.

func _ready() -> void:
	var packed: PackedScene = load("res://scenes/MapEditor.tscn")
	if packed == null:
		print("FAIL: PackedScene.load() vratilo null")
		get_tree().quit(1)
		return
	var inst: Node = packed.instantiate()
	if inst == null:
		print("FAIL: instantiate() vratilo null")
		get_tree().quit(1)
		return
	var tl = inst.get("target_level")
	if tl == null:
		print("FAIL: target_level je null")
		get_tree().quit(1)
		return
	print("OK: target_level = %s" % tl.resource_path)
	inst.queue_free()
	get_tree().quit(0)
