extends SceneTree
## Scales a hand-authored 64x64 pixel-art atlas up to the 192x192 the TileSet expects.
##
## Run:  godot --headless --path <proj> --script res://tools/scale_pixel_atlas.gd
##       godot ... --script res://tools/scale_pixel_atlas.gd -- walls_4_panely_16.png
##
## THE WORKFLOW THIS CLOSES
## Pixel art is authored at 16x16 per tile (a 4x4 atlas = 64x64) because that is a size
## you can actually draw by hand, and because 48 / 3 = 16 exactly. Open the source in
## Aseprite, repaint, save, run this. Nothing else needs touching — the TileSet references
## the output png by path.
##
## Scaling MUST be nearest-neighbour. Any smoothing turns pixel art into mush, which is
## also why the project's canvas texture filter has to be Nearest (see docs/ART_PROMPTS.md).

const SRC_DIR := "res://assets/src/pixel"
const DEFAULT_SRC := "walls_1_obvod_16.png"
const OUT := "res://assets/terrain/high_ground_atlas.png"
const TARGET := 192          ## 4 tiles x Data.GRID.tile

## The authored size is read from the file rather than fixed, so 16 (x3), 24 (x2) and
## 48 (x1) all work without editing this script — the choice is an art decision and
## should not need a code change.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var name: String = args[0] if args.size() > 0 else DEFAULT_SRC
	var path := "%s/%s" % [SRC_DIR, name]

	var img := Image.new()
	if img.load(path) != OK:
		push_error("Nelze nacist %s" % path)
		quit(1)
		return

	var w := img.get_width()
	if w != img.get_height():
		push_error("Zdroj musi byt ctvercovy, je %dx%d." % [w, img.get_height()])
		quit(1)
		return
	if w % 4 != 0 or TARGET % w != 0:
		push_error("Zdroj %dx%d nejde zvetsit celociselne na %d. Pouzitelne: 48, 64, 96, 192 "
			% [w, w, TARGET] + "(tedy dlazdice 12, 16, 24 nebo 48 px).")
		quit(1)
		return

	var scale := TARGET / w
	if scale > 1:
		img.resize(TARGET, TARGET, Image.INTERPOLATE_NEAREST)
	if img.save_png(OUT) != OK:
		push_error("Zapis %s selhal" % OUT)
		quit(1)
		return

	print("%s (dlazdice %dpx) -> %s  %dx%d, zvetseno %dx nearest"
		% [name, w / 4, OUT, TARGET, TARGET, scale])
	quit(0)
