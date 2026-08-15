@tool
extends EditorPlugin
## Mounts the TD Designer dock and the split-view preview pane.
##
## Panel je „samsfacee" split: připnutý k pravému okraji 2D canvas editoru
## (add_control_to_container), uvnitř SubViewport se StylizedRenderer a Camera2D,
## která KOPÍRUJE levý pohled — kam se posuneš a přiblížíš vlevo, to vidíš vpravo
## vykreslené herní grafikou. Překresluje se na signál canvas_changed z MapEditoru.
##
## Panel nikdy nepřebírá vstup do plátna — sedí VEDLE něj. Vlastní razítkovací nástroj
## s pěti režimy a přebíráním kliků tu byl a je smazaný záměrně: maluje se vestavěným
## editorem dlaždic. Tenhle plugin jen ZOBRAZUJE.

const RENDERER_SCRIPT := "res://tools/stylized_renderer.gd"

## Šířky panelu; Půlka je výchozí — dost na čtení mapy, dost místa na malování.
const W_HALF := 760.0
const W_NARROW := 420.0

var _dock: Control = null
var _pane: Control = null
var _viewport: SubViewport = null
var _camera: Camera2D = null
var _renderer: StylizedMapRenderer = null
var _collapse_btn: Button = null
var _bound: MapEditor = null

func _enter_tree() -> void:
	_dock = preload("res://addons/td_level_designer/dock.gd").new()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)
	_build_pane()
	scene_changed.connect(_on_scene_changed)
	set_process(true)

func _exit_tree() -> void:
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	_bind(null)
	remove_control_from_docks(_dock)
	_dock.queue_free()
	_dock = null
	if _pane != null:
		remove_control_from_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_SIDE_RIGHT, _pane)
		_pane.queue_free()
		_pane = null

func _on_scene_changed(root: Node) -> void:
	if _dock != null:
		_dock.bind_scene(root)
	_bind(_find_editor(root))

func _find_editor(node: Node) -> MapEditor:
	if node == null:
		return null
	if node is MapEditor:
		return node
	for child in node.get_children():
		var found := _find_editor(child)
		if found != null:
			return found
	return null

# ---------------------------------------------------------------- pane

func _build_pane() -> void:
	_pane = VBoxContainer.new()
	_pane.name = "TDNahled"
	_pane.custom_minimum_size.x = W_HALF

	var bar := HBoxContainer.new()
	_pane.add_child(bar)
	var title := Label.new()
	title.text = "Náhled hry"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)
	var half := Button.new()
	half.text = "Půlka"
	half.tooltip_text = "Přepnout šířku panelu"
	half.pressed.connect(func():
		_pane.custom_minimum_size.x = W_NARROW \
			if _pane.custom_minimum_size.x == W_HALF else W_HALF)
	bar.add_child(half)
	_collapse_btn = Button.new()
	_collapse_btn.text = "Sbalit"
	_collapse_btn.toggle_mode = true
	_collapse_btn.tooltip_text = "Schovat náhled (zůstane jen lišta)"
	bar.add_child(_collapse_btn)
	var redraw := Button.new()
	redraw.text = "⟳"
	redraw.tooltip_text = "Překreslit a znovu načíst grafiku (po tiles.py / výměně PNG)"
	redraw.pressed.connect(func():
		if _renderer != null:
			_renderer.drop_art_cache()
		_rebuild())
	bar.add_child(redraw)

	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Náhled je jen obraz — ať nikdy nesebere focus ani kolečko myši.
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pane.add_child(holder)
	_collapse_btn.toggled.connect(func(on: bool):
		holder.visible = not on
		_pane.custom_minimum_size.x = 130.0 if on else W_HALF)

	_viewport = SubViewport.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(_viewport)

	# Tmavé plátno kolem mapy, ať konec hřiště nevypadá jako díra v okně.
	var bg := ColorRect.new()
	bg.color = Color("161320")
	bg.size = Vector2(8000, 8000)
	bg.position = Vector2(-4000, -4000)
	_viewport.add_child(bg)

	_renderer = (load(RENDERER_SCRIPT) as GDScript).new() as StylizedMapRenderer
	_viewport.add_child(_renderer)

	# Bez make_current(): panel v tuhle chvíli ještě není ve stromu (přidává se až
	# řádek níž) a jediná povolená Camera2D se po vstupu do stromu zapne sama.
	_camera = Camera2D.new()
	_viewport.add_child(_camera)

	add_control_to_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_SIDE_RIGHT, _pane)

func _bind(ed: MapEditor) -> void:
	if _bound == ed:
		return
	if _bound != null and is_instance_valid(_bound) \
			and _bound.canvas_changed.is_connected(_rebuild):
		_bound.canvas_changed.disconnect(_rebuild)
	_bound = ed
	if _pane != null:
		_pane.visible = ed != null
	if ed != null:
		ed.canvas_changed.connect(_rebuild)
		if _renderer != null:
			_renderer.drop_art_cache()
		_rebuild()

func _rebuild() -> void:
	if _renderer != null and _bound != null and is_instance_valid(_bound):
		_renderer.rebuild(_bound)

## Kamera náhledu kopíruje levý 2D pohled — to je celé kouzlo split-view: obě půlky
## ukazují TENTÝŽ výřez světa, jen jinou grafikou. Levný per-frame poll; signál na
## posun editoru neexistuje.
func _process(_delta: float) -> void:
	if _bound == null or not is_instance_valid(_bound) \
			or _pane == null or not _pane.visible or _camera == null:
		return
	if not _bound.is_inside_tree():
		return
	var vp := _bound.get_viewport()
	if vp == null:
		return
	var xf: Transform2D = vp.global_canvas_transform
	var s: float = xf.get_scale().x
	if s <= 0.0001:
		return
	var view_size: Vector2 = vp.get_visible_rect().size
	_camera.position = xf.affine_inverse() * (view_size / 2.0)
	_camera.zoom = Vector2(s, s)
