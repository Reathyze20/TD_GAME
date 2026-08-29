extends Node
## S4 (docs/refactor/SYSTEMS.MD): renders the same shipped distraction sprite
## (clickbait, a real PixelLab asset from the junk-food family, not a placeholder)
## three times side by side through shaders/palette_swap.gdshader — the master
## palette unchanged, and two alternative palettes (+120 deg and +240 deg hue,
## computed from the master's own colours, docs/art/palette_48.hex) — and saves the
## comparison as one PNG. NOT --headless: needs a real viewport texture, same as
## every other _shot_*.gd in this repo.
##
##   godot --path <proj> --main-scene res://scenes/_shot_palette_swap.tscn

const SPRITE_PATH := "res://assets/distractions/clickbait_frame_1.png"

# Same hue-rotated variants as the shader's own embedded MASTER_PALETTE, computed
# once from docs/art/palette_48.hex (pure math, not PixelLab) — see PROGRESS.md's S4
# entry for how.
const VARIANT_B := [
	Vector3(0.0039, 0.0039, 0.0000), Vector3(0.1725, 0.0000, 0.0000),
	Vector3(0.0196, 0.0118, 0.0549), Vector3(0.1922, 0.0275, 0.0824),
	Vector3(0.1373, 0.2039, 0.0745), Vector3(0.1098, 0.0745, 0.1647),
	Vector3(0.2784, 0.0863, 0.1451), Vector3(0.1765, 0.1412, 0.2471),
	Vector3(0.1725, 0.4431, 0.1098), Vector3(0.5059, 0.2980, 0.1490),
	Vector3(0.1882, 0.3451, 0.2627), Vector3(0.3412, 0.4784, 0.1176),
	Vector3(0.1725, 0.5333, 0.1333), Vector3(0.2039, 0.2275, 0.3529),
	Vector3(0.4392, 0.3216, 0.3412), Vector3(0.4275, 0.0392, 0.4000),
	Vector3(0.7216, 0.4667, 0.2549), Vector3(0.1647, 0.5804, 0.3412),
	Vector3(0.2000, 0.6902, 0.2275), Vector3(0.3255, 0.7804, 0.0510),
	Vector3(0.2588, 0.3490, 0.4863), Vector3(0.5176, 0.4706, 0.4824),
	Vector3(0.5373, 0.0745, 0.5569), Vector3(0.9059, 0.6000, 0.3294),
	Vector3(0.0667, 0.9569, 0.0784), Vector3(0.8275, 0.1490, 0.5569),
	Vector3(0.2039, 0.7216, 0.4667), Vector3(0.6039, 0.5569, 0.5765),
	Vector3(0.6078, 0.0784, 0.6824), Vector3(0.9922, 0.7176, 0.4588),
	Vector3(0.2078, 0.8235, 0.5529), Vector3(0.4667, 0.7137, 0.6039),
	Vector3(0.2706, 0.6118, 0.6745), Vector3(0.5451, 0.8706, 0.5412),
	Vector3(0.6588, 0.0863, 0.7529), Vector3(0.2157, 0.9137, 0.6588),
	Vector3(0.5529, 0.8078, 0.7059), Vector3(0.6980, 0.7647, 0.7098),
	Vector3(0.8000, 0.3529, 0.8078), Vector3(0.3137, 0.9529, 0.7373),
	Vector3(0.4000, 0.8549, 0.8078), Vector3(0.2235, 0.4902, 0.9373),
	Vector3(0.8706, 0.4667, 0.8941), Vector3(0.7373, 0.8784, 0.8078),
	Vector3(0.7922, 0.0745, 0.9686), Vector3(0.1020, 0.9843, 0.8627),
	Vector3(0.6353, 0.9882, 0.8980), Vector3(0.9373, 0.7608, 0.9686),
]
const VARIANT_C := [
	Vector3(0.0000, 0.0039, 0.0039), Vector3(0.0000, 0.1725, 0.0000),
	Vector3(0.0549, 0.0196, 0.0118), Vector3(0.0824, 0.1922, 0.0275),
	Vector3(0.0745, 0.1373, 0.2039), Vector3(0.1647, 0.1098, 0.0745),
	Vector3(0.1451, 0.2784, 0.0863), Vector3(0.2471, 0.1765, 0.1412),
	Vector3(0.1098, 0.1725, 0.4431), Vector3(0.1490, 0.5059, 0.2980),
	Vector3(0.2627, 0.1882, 0.3451), Vector3(0.1176, 0.3412, 0.4784),
	Vector3(0.1333, 0.1725, 0.5333), Vector3(0.3529, 0.2039, 0.2275),
	Vector3(0.3412, 0.4392, 0.3216), Vector3(0.4000, 0.4275, 0.0392),
	Vector3(0.2549, 0.7216, 0.4667), Vector3(0.3412, 0.1647, 0.5804),
	Vector3(0.2275, 0.2000, 0.6902), Vector3(0.0510, 0.3255, 0.7804),
	Vector3(0.4863, 0.2588, 0.3490), Vector3(0.4824, 0.5176, 0.4706),
	Vector3(0.5569, 0.5373, 0.0745), Vector3(0.3294, 0.9059, 0.6000),
	Vector3(0.0784, 0.0667, 0.9569), Vector3(0.5569, 0.8275, 0.1490),
	Vector3(0.4667, 0.2039, 0.7216), Vector3(0.5765, 0.6039, 0.5569),
	Vector3(0.6824, 0.6078, 0.0784), Vector3(0.4588, 0.9922, 0.7176),
	Vector3(0.5529, 0.2078, 0.8235), Vector3(0.6039, 0.4667, 0.7137),
	Vector3(0.6745, 0.2706, 0.6118), Vector3(0.5412, 0.5451, 0.8706),
	Vector3(0.7529, 0.6588, 0.0863), Vector3(0.6588, 0.2157, 0.9137),
	Vector3(0.7059, 0.5529, 0.8078), Vector3(0.7098, 0.6980, 0.7647),
	Vector3(0.8078, 0.8000, 0.3529), Vector3(0.7373, 0.3137, 0.9529),
	Vector3(0.8078, 0.4000, 0.8549), Vector3(0.9373, 0.2235, 0.4902),
	Vector3(0.8941, 0.8706, 0.4667), Vector3(0.8078, 0.7373, 0.8784),
	Vector3(0.9686, 0.7922, 0.0745), Vector3(0.8627, 0.1020, 0.9843),
	Vector3(0.8980, 0.6353, 0.9882), Vector3(0.9686, 0.9373, 0.7608),
]

func _make_sprite(tex: Texture2D, target_palette: Array, pos_x: float) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.position = Vector2(pos_x, 100)
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not target_palette.is_empty():
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/palette_swap.gdshader")
		mat.set_shader_parameter("target_palette", PackedVector3Array(target_palette))
		spr.material = mat
	add_child(spr)
	return spr

func _save(img: Image, path: String) -> void:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	if img.save_png(path) != OK:
		printerr("_shot_palette_swap: save failed: ", path)
		return
	print("_shot_palette_swap: %s  %dx%d" % [path, img.get_width(), img.get_height()])

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	get_viewport().transparent_bg = false
	RenderingServer.set_default_clear_color(Color(0.1, 0.1, 0.12))

	var tex: Texture2D = load(SPRITE_PATH)
	if tex == null:
		printerr("_shot_palette_swap: could not load ", SPRITE_PATH)
		get_tree().quit(1)
		return

	# Variant A: master palette unchanged (the shader's identity case — remapping
	# every index onto itself, read from the same hex file the shader's own
	# MASTER_PALETTE constant was generated from). Variant B/C: hue-rotated
	# alternative sets.
	var f := FileAccess.open("res://docs/art/palette_48.hex", FileAccess.READ)
	var master_colors: Array = []
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.length() == 6:
			var r := ("0x" + line.substr(0, 2)).hex_to_int() / 255.0
			var g := ("0x" + line.substr(2, 2)).hex_to_int() / 255.0
			var b := ("0x" + line.substr(4, 2)).hex_to_int() / 255.0
			master_colors.append(Vector3(r, g, b))
	f.close()

	_make_sprite(tex, master_colors, 20)
	_make_sprite(tex, VARIANT_B, 20 + tex.get_width() + 20)
	_make_sprite(tex, VARIANT_C, 20 + (tex.get_width() + 20) * 2)

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	_save(img, "build/palette_swap_variants.png")
	get_tree().quit(0)
