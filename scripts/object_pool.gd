class_name ObjectPool
extends RefCounted
## A generic pool for reusing frequently instantiated objects (Projectiles, FX).

var _factory: Callable
var _pool: Array = []
var _active: int = 0
var _parent: Node
var _max_size: int

func _init(factory: Callable, initial_size: int, parent_node: Node, max_size: int = 1000) -> void:
	_factory = factory
	_parent = parent_node
	_max_size = max_size
	
	for i in range(initial_size):
		_pool.append(_create_item())

func _create_item() -> Variant:
	var item = _factory.call()
	if item is Node:
		_parent.add_child(item)
		if item.has_method("hide"):
			item.hide()
		item.set_process(false)
		item.set_physics_process(false)
		
		# If the item has a 'finished' or 'died' signal, we can auto-release it if desired,
		# but explicit release is usually safer to avoid double-frees.
	return item

## Gets an item from the pool. Creates a new one if the pool is empty and max_size is not reached.
func acquire() -> Variant:
	var item = null
	if not _pool.is_empty():
		item = _pool.pop_back()
	elif _active < _max_size:
		item = _create_item()
	else:
		push_warning("ObjectPool: Max size reached, cannot acquire more items.")
		return null
		
	_active += 1
	if item is Node:
		if item.has_method("show"):
			item.show()
		item.set_process(true)
		item.set_physics_process(true)
	return item

## Returns an item to the pool.
func release(item: Variant) -> void:
	if item == null:
		return
	if _pool.has(item):
		return
	if item is Node:
		if item.has_method("hide"):
			item.hide()
		item.set_process(false)
		item.set_physics_process(false)
		
		# Move it off-screen just in case it renders without visibility
		if "global_position" in item:
			item.global_position = Vector2(-9999, -9999)
			
	_pool.append(item)
	_active -= 1
