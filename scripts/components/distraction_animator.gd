class_name DistractionAnimator
extends Node2D

# Component attached to Distraction (enemy.gd).
# Renders crisp, multi-part procedural vector graphics directly in Godot 2D Canvas.
# Internal sub-elements move independently (swinging bell clapper, scrolling feed items,
# expanding vibration waves, dynamic buffering progress, glitching mosaic tiles, orbiting boss screens).

var enemy: Distraction
var _time: float = 0.0
var _hit_flash_timer: float = 0.0

# Pre-calculated colors for performance
const COLOR_NOTIF_BG := Color("ff3b30")
const COLOR_NOTIF_BELL := Color("ffffff")
const COLOR_NOTIF_CLAPPER := Color("ffcc00")

const COLOR_BUZZ_PHONE := Color("007aff")
const COLOR_BUZZ_CYAN := Color("64d2ff")

const COLOR_AP_RING := Color("ff9500")
const COLOR_AP_PLAY := Color("ffffff")

const COLOR_DS_FRAME := Color("34c759")
const COLOR_DS_BG := Color("1c1c1e")

const COLOR_ADULT_BASE := Color("ff2d55")
const COLOR_ADULT_HOT := Color("ff9500")

const COLOR_BOSS_CORE := Color("af52de")
const COLOR_BOSS_TENDRILL := Color("bf5af2")

var _frame_textures: Array[Texture2D] = []

func _ready() -> void:
	set_process(true)

func setup(parent_enemy: Distraction) -> void:
	enemy = parent_enemy
	_time = randf() * 10.0 # Randomize phase offset
	_load_frame_textures()
	queue_redraw()

func _load_frame_textures() -> void:
	_frame_textures.clear()
	if enemy == null or enemy.def == null:
		return
	
	var base_id := String(enemy.def.id)
	for i in range(1, 5):
		var p := "res://assets/distractions/%s_frame_%d.png" % [base_id, i]
		if ResourceLoader.exists(p):
			var tex = load(p)
			if tex is Texture2D:
				_frame_textures.append(tex)
		elif FileAccess.file_exists(p):
			var img := Image.new()
			if img.load(p) == OK:
				_frame_textures.append(ImageTexture.create_from_image(img))

func trigger_hit_flash() -> void:
	_hit_flash_timer = 0.15

func _process(delta: float) -> void:
	if enemy == null or enemy.dead:
		return

	_time += delta

	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta

	queue_redraw()

func _draw() -> void:
	if enemy == null or enemy.def == null:
		return

	var r: float = enemy.def.radius
	var is_moving := enemy.current_speed > 0 and not enemy.is_blocked

	# Apply Hit Flash modulation tint
	if _hit_flash_timer > 0.0:
		draw_circle(Vector2.ZERO, r + 4.0, Color(1, 1, 1, 0.8))

	# -------------------------------------------------- Status Aura Overlays
	# Boredom halo
	if enemy.status_manager != null and enemy.status_manager.has_boredom():
		draw_circle(Vector2.ZERO, r + 7.0, Color(0.55, 0.58, 0.62, 0.35))

	# Slow / Calm ring
	if enemy.status_manager != null and enemy.status_manager.has_slow():
		draw_arc(Vector2.ZERO, r + 4.0, 0, TAU, 24, Color(0.3, 0.8, 1.0, 0.7), 2.0)

	# -------------------------------------------------- Multi-Part Vector Animations
	match String(enemy.def.id):
		"notification":
			_draw_notification(r, is_moving)
		"phantom_buzz":
			_draw_phantom_buzz(r)
		"autoplay":
			_draw_autoplay(r, is_moving)
		"doomscroll":
			_draw_doomscroll(r, is_moving)
		"adult_content":
			_draw_adult_content(r)
		"social_media_binge":
			_draw_boss_social_media(r)
		"group_chat":
			_draw_group_chat(r, is_moving)
		_:
			_draw_generic_fallback(r, is_moving)

	# Reframe status broken ring
	if enemy.status_manager != null and enemy.status_manager.has_reframe():
		var seg: float = TAU / 8.0
		for i in range(4):
			var a: float = float(i) * seg * 2.0
			draw_arc(Vector2.ZERO, r + 6.0, a, a + seg, 6, Color(1, 1, 1, 0.9), 2.0)

	# Denial Shield — the boss ignores every direct hit while this is up, so it has to
	# be unmissable ON the body, not only a text flash in the corner of the HUD.
	# Rotating segments over a soft ring read as an active barrier, not a decoration.
	if enemy is Boss and (enemy as Boss).is_shielded():
		var sr: float = r + 12.0
		draw_arc(Vector2.ZERO, sr, 0, TAU, 40, Color(1.0, 0.83, 0.47, 0.30), 6.0)
		for i in range(6):
			var a: float = _time * 2.2 + float(i) * TAU / 6.0
			draw_arc(Vector2.ZERO, sr, a, a + 0.55, 8, Color("ffd479"), 3.0)
		draw_arc(Vector2.ZERO, sr + 5.0, 0, TAU, 40, Color(1.0, 0.83, 0.47, 0.45), 1.5)

# ==============================================================================
# 1. NOTIFICATION (Zvonící odznak + kmitající srdce/jazyk zvonku + posakující badge)
# ==============================================================================
func _draw_notification(r: float, is_moving: bool) -> void:
	var tilt := sin(_time * 14.0) * 0.2 if is_moving else sin(_time * 5.0) * 0.08

	# Ringing sound waves emitting outwards
	for i in range(2):
		var wave_t := fmod(_time * 3.0 + i * 0.5, 1.0)
		var wave_r := r + wave_t * 12.0
		var alpha := (1.0 - wave_t) * 0.6
		draw_arc(Vector2.ZERO, wave_r, -PI * 0.7, -PI * 0.3, 12, Color(1, 0.3, 0.3, alpha), 2.0)

	# Main Red Badge Disc
	draw_circle(Vector2.ZERO, r, COLOR_NOTIF_BG)
	draw_arc(Vector2.ZERO, r, 0, TAU, 24, Color.WHITE, 1.5)

	# Bell Outline Shape
	var bell_center := Vector2(0, 1.0)
	var pts := PackedVector2Array([
		bell_center + Vector2(0, -r * 0.55).rotated(tilt),
		bell_center + Vector2(r * 0.45, r * 0.2).rotated(tilt),
		bell_center + Vector2(-r * 0.45, r * 0.2).rotated(tilt)
	])
	draw_colored_polygon(pts, COLOR_NOTIF_BELL)

	# Independent Swinging Clapper
	var clapper_angle := sin(_time * 16.0) * 0.35
	var clapper_pos := bell_center + Vector2(sin(clapper_angle) * (r * 0.3), r * 0.28)
	draw_circle(clapper_pos, r * 0.16, COLOR_NOTIF_CLAPPER)

	# Bouncing "+1" / "!" Badge at Top-Right
	var badge_bounce := sin(_time * 8.0) * 2.5
	var badge_pos := Vector2(r * 0.55, -r * 0.55 + badge_bounce)
	draw_circle(badge_pos, r * 0.35, Color.WHITE)
	draw_circle(badge_pos, r * 0.28, COLOR_NOTIF_BG)
	# Exclamation mark
	draw_line(badge_pos + Vector2(0, -r * 0.12), badge_pos + Vector2(0, 0), Color.WHITE, 2.0)
	draw_circle(badge_pos + Vector2(0, r * 0.12), 1.2, Color.WHITE)

# ==============================================================================
# 2. PHANTOM BUZZ (Létající telefon + expanzivní vibrační vlny + živý osciloskop)
# ==============================================================================
func _draw_phantom_buzz(r: float) -> void:
	var hover_y := sin(_time * 5.0) * 5.0
	var jitter_x := randf_range(-1.2, 1.2)
	var phone_center := Vector2(jitter_x, hover_y)

	# 1. Dynamic Expanding Vibration Shockwaves (Left and Right)
	for i in range(3):
		var wave_t := fmod(_time * 2.5 + i * 0.33, 1.0)
		var wave_r := r + wave_t * 20.0
		var alpha := (1.0 - wave_t) * 0.75
		var wave_color := Color(0.39, 0.82, 1.0, alpha)
		draw_arc(phone_center, wave_r, PI * 0.65, PI * 1.35, 16, wave_color, 2.2)
		draw_arc(phone_center, wave_r, -PI * 0.35, PI * 0.35, 16, wave_color, 2.2)

	# 2. Ghost Trail Echo (2 trailing ghosts for smooth ghost effect)
	for t_idx in range(1, 3):
		var trail_offset := Vector2(-t_idx * 4.0, sin((_time - t_idx * 0.08) * 5.0) * 5.0)
		var trail_rect := Rect2(trail_offset - Vector2(r * 0.6, r * 0.9), Vector2(r * 1.2, r * 1.8))
		draw_rect(trail_rect, Color(0.0, 0.5, 1.0, 0.15 / float(t_idx)), true)
		draw_rect(trail_rect, Color(0.39, 0.82, 1.0, 0.3 / float(t_idx)), false, 1.0)

	# 3. Main Ghost Phone Body (Transparent Hologram Chassis)
	var phone_size := Vector2(r * 1.3, r * 1.9)
	var phone_rect := Rect2(phone_center - phone_size / 2.0, phone_size)
	# Translucent cyan fill
	draw_rect(phone_rect, Color(0.0, 0.45, 0.95, 0.55), true)
	# Glowing white & cyan border
	draw_rect(phone_rect, Color("64d2ff"), false, 2.0)
	draw_rect(phone_rect.grow(-1.5), Color.WHITE, false, 1.0)

	# 4. Glowing Expressive Ghost Eyes
	var eye_y := phone_center.y - r * 0.35
	var eye_pulse := 1.0 + sin(_time * 12.0) * 0.15
	var left_eye := Vector2(phone_center.x - r * 0.28, eye_y)
	var right_eye := Vector2(phone_center.x + r * 0.28, eye_y)
	draw_circle(left_eye, r * 0.18 * eye_pulse, Color.WHITE)
	draw_circle(left_eye, r * 0.12 * eye_pulse, Color("64d2ff"))
	draw_circle(right_eye, r * 0.18 * eye_pulse, Color.WHITE)
	draw_circle(right_eye, r * 0.12 * eye_pulse, Color("64d2ff"))

	# 5. Live Oscilloscope Signal Waveform Mouth / Screen
	var wave_y := phone_center.y + r * 0.3
	var points := PackedVector2Array()
	var width := r * 0.9
	var steps := 10
	for i in range(steps + 1):
		var px := phone_center.x - width / 2.0 + (width / float(steps)) * float(i)
		var py := wave_y + sin(float(i) * 0.9 + _time * 16.0) * (r * 0.2)
		points.append(Vector2(px, py))
	draw_polyline(points, COLOR_BUZZ_CYAN, 2.0)

# ==============================================================================
# 3. AUTOPLAY (Kruhový timer plnící se 0-360° + ozubený prstenec + rotující play)
# ==============================================================================
func _draw_autoplay(r: float, is_moving: bool) -> void:
	# Dark Disc Base
	draw_circle(Vector2.ZERO, r, Color(0.1, 0.1, 0.12))
	draw_circle(Vector2.ZERO, r, Color(1, 0.6, 0, 0.3))

	# Segmented Rotating Outer Gear Ring
	var gear_angle := -_time * 2.0
	var segs := 6
	for i in range(segs):
		var a := gear_angle + i * (TAU / segs)
		draw_arc(Vector2.ZERO, r * 0.95, a, a + 0.5, 6, COLOR_AP_RING, 3.0)

	# Continuous Dynamic Countdown Progress Fill Arc
	var fill_progress := fmod(_time * 1.5, TAU)
	draw_arc(Vector2.ZERO, r * 0.75, -PI * 0.5, -PI * 0.5 + fill_progress, 24, Color(1, 0.8, 0), 2.5)

	# Central Play Button Triangle (Pulsing forward)
	var pulse := 1.0 + sin(_time * 10.0) * 0.12
	var tri_size := r * 0.4 * pulse
	var pts := PackedVector2Array([
		Vector2(-tri_size * 0.5, -tri_size * 0.7),
		Vector2(tri_size * 0.8, 0),
		Vector2(-tri_size * 0.5, tri_size * 0.7)
	])
	draw_colored_polygon(pts, COLOR_AP_PLAY)

# ==============================================================================
# 4. DOOMSCROLL (Nekonečný feed příspěvků fyzicky rolovaný dolů po displeji)
# ==============================================================================
func _draw_doomscroll(r: float, is_moving: bool) -> void:
	# Walking Feet animation underneath
	if is_moving:
		var leg1_x := sin(_time * 12.0) * (r * 0.3)
		var leg2_x := -sin(_time * 12.0) * (r * 0.3)
		draw_line(Vector2(-r * 0.3, r * 0.9), Vector2(-r * 0.3 + leg1_x, r * 1.2), COLOR_DS_FRAME, 3.0)
		draw_line(Vector2(r * 0.3, r * 0.9), Vector2(r * 0.3 + leg2_x, r * 1.2), COLOR_DS_FRAME, 3.0)

	# Smartphone Frame
	var phone_rect := Rect2(-r * 0.7, -r * 1.0, r * 1.4, r * 2.0)
	draw_rect(phone_rect, COLOR_DS_FRAME, true)
	draw_rect(phone_rect, Color.WHITE, false, 2.0)

	# Screen Viewport
	var screen_rect := Rect2(-r * 0.55, -r * 0.85, r * 1.1, r * 1.7)
	draw_rect(screen_rect, COLOR_DS_BG, true)

	# Continuous Downward Rolling Post Cards (3 items cycling)
	var card_height := r * 0.45
	var scroll_speed := 35.0
	var total_height := r * 1.5

	for i in range(3):
		var base_y := -r * 0.7 + i * (card_height + 4.0)
		var cur_y := -r * 0.7 + fmod(base_y + _time * scroll_speed + r * 1.0, total_height) - r * 0.3
		var card_r := Rect2(-r * 0.45, cur_y, r * 0.9, card_height)

		# Clip check inside screen
		if card_r.position.y > -r * 0.85 and card_r.position.y + card_height < r * 0.85:
			draw_rect(card_r, Color(0.2, 0.2, 0.23), true)
			draw_rect(card_r, COLOR_DS_FRAME, false, 1.0)

			# Post details (Like heart icon + text lines)
			var heart_pos := card_r.position + Vector2(r * 0.15, r * 0.2)
			draw_circle(heart_pos, 2.5, Color("ff3b30"))
			draw_line(card_r.position + Vector2(r * 0.3, r * 0.15), card_r.position + Vector2(r * 0.75, r * 0.15), Color.WHITE, 1.5)
			draw_line(card_r.position + Vector2(r * 0.15, r * 0.32), card_r.position + Vector2(r * 0.6, r * 0.32), Color(0.6, 0.6, 0.6), 1.0)

	# Bottom Vortex Gradient Line
	draw_line(Vector2(-r * 0.55, r * 0.75), Vector2(r * 0.55, r * 0.75), Color("ff3b30"), 2.0)

# ==============================================================================
# 5. ADULT CONTENT (Dopaminová past – mozaikový glitch + zrychleně tepající jádro)
# ==============================================================================
func _draw_adult_content(r: float) -> void:
	# Outer Neon Hazard Frame
	draw_rect(Rect2(-r, -r, r * 2.0, r * 2.0), COLOR_ADULT_BASE, true)
	draw_rect(Rect2(-r, -r, r * 2.0, r * 2.0), Color.WHITE, false, 2.0)

	# Rapid Pulsing Flame/Heart Core
	var heart_pulse := 1.0 + sin(_time * 14.0) * 0.18
	draw_circle(Vector2.ZERO, r * 0.45 * heart_pulse, COLOR_ADULT_HOT)

	# Dynamic Glitching Mosaic Grid (4x4 tiles changing color & opacity)
	var grid_size := 4
	var tile_dim := (r * 1.8) / float(grid_size)
	var start_pos := Vector2(-r * 0.9, -r * 0.9)

	for row in range(grid_size):
		for col in range(grid_size):
			# Seeded pseudo-randomness based on time step
			var tile_seed := row * 7 + col * 13 + int(_time * 8.0)
			if tile_seed % 3 == 0:
				var t_pos := start_pos + Vector2(col * tile_dim, row * tile_dim)
				var alpha := 0.4 + (tile_seed % 5) * 0.12
				var c := COLOR_ADULT_BASE if tile_seed % 2 == 0 else COLOR_ADULT_HOT
				c.a = alpha
				draw_rect(Rect2(t_pos, Vector2(tile_dim - 1.0, tile_dim - 1.0)), c, true)

# ==============================================================================
# 6. SOCIAL MEDIA BINGE (Boss - Obíhající satelitní obrazovky + úponky)
# ==============================================================================
func _draw_boss_social_media(r: float) -> void:
	# Central Boss Disc
	var boss_pulse := 1.0 + sin(_time * 4.0) * 0.06
	draw_circle(Vector2.ZERO, r * 0.7 * boss_pulse, COLOR_BOSS_CORE)
	draw_circle(Vector2.ZERO, r * 0.7 * boss_pulse, Color.WHITE, false, 2.5)

	# Inner Spiral Line
	var spiral_pts := PackedVector2Array()
	for i in range(16):
		var a := float(i) * 0.4 + _time * 3.0
		var radius_step := (r * 0.55) * (float(i) / 16.0)
		spiral_pts.append(Vector2(cos(a), sin(a)) * radius_step)
	draw_polyline(spiral_pts, Color.WHITE, 1.5)

	# 4 Satellite Screens Orbiting the Core
	var screens := 4
	var orbit_radius := r * 1.25
	var speed := 1.4

	for i in range(screens):
		var angle := _time * speed + i * (TAU / float(screens))
		var screen_pos := Vector2(cos(angle), sin(angle)) * orbit_radius

		# Pulsing Zig-Zag Energy Tendrils to Center
		var mid_point := screen_pos * 0.5 + Vector2(randf_range(-2, 2), randf_range(-2, 2))
		draw_line(Vector2.ZERO, mid_point, COLOR_BOSS_TENDRILL, 2.5)
		draw_line(mid_point, screen_pos, Color.WHITE, 1.5)

		# Satellite Screen Body
		var s_size := Vector2(r * 0.5, r * 0.6)
		var s_rect := Rect2(screen_pos - s_size / 2.0, s_size)
		draw_rect(s_rect, Color(0.15, 0.15, 0.18), true)
		draw_rect(s_rect, COLOR_BOSS_TENDRILL, false, 1.5)

		# Icon on Screen
		match i:
			0: # Like Heart
				draw_circle(screen_pos, 3.0, Color("ff3b30"))
			1: # Retweet Arrow
				draw_line(screen_pos + Vector2(-3, 2), screen_pos + Vector2(0, -2), Color("30d158"), 1.5)
				draw_line(screen_pos + Vector2(0, -2), screen_pos + Vector2(3, 2), Color("30d158"), 1.5)
			2: # Chat Bubble
				draw_circle(screen_pos, 3.0, Color("64d2ff"))
			3: # Dopamine Star
				draw_circle(screen_pos, 2.5, Color("ffcc00"))

# ==============================================================================
# 7. GROUP CHAT (Disruptor — trs chatovacích bublin + tečky psaní + ping vlny)
# ==============================================================================
func _draw_group_chat(r: float, is_moving: bool) -> void:
	var bob := sin(_time * 9.0) * 1.5 if is_moving else 0.0
	var base := Color("42c86a")

	# Ringing ping waves, same language as the notification's bell arcs.
	for i in range(2):
		var wave_t := fmod(_time * 2.2 + i * 0.5, 1.0)
		var alpha := (1.0 - wave_t) * 0.5
		draw_arc(Vector2(0, bob), r + wave_t * 14.0, -PI * 0.8, -PI * 0.2, 12,
			Color(base.r, base.g, base.b, alpha), 2.0)

	# A cluster of three chat bubbles — the thread, not one message.
	var main_rect := Rect2(-r * 0.9, bob - r * 0.7, r * 1.5, r * 1.1)
	draw_rect(main_rect, base, true)
	draw_rect(main_rect, Color.WHITE, false, 1.5)
	var tail := PackedVector2Array([
		Vector2(-r * 0.5, bob + r * 0.4), Vector2(-r * 0.2, bob + r * 0.4),
		Vector2(-r * 0.55, bob + r * 0.85)])
	draw_colored_polygon(tail, base)
	var back_rect := Rect2(-r * 0.1, bob - r * 1.05, r * 1.1, r * 0.75)
	draw_rect(back_rect, base.darkened(0.35), true)
	draw_rect(back_rect, Color(1, 1, 1, 0.6), false, 1.0)

	# "Someone is typing…" dots, blinking in sequence — the hook that never resolves.
	for i in range(3):
		var phase := fmod(_time * 2.4 - float(i) * 0.25, 1.0)
		var da := 0.35 + 0.65 * clampf(sin(phase * TAU) * 0.5 + 0.5, 0.0, 1.0)
		draw_circle(Vector2(-r * 0.55 + float(i) * r * 0.4, bob - r * 0.15),
			r * 0.11, Color(1, 1, 1, da))

# ==============================================================================
# FALLBACK (Pro neurčené typy)
# ==============================================================================
func _draw_generic_fallback(r: float, is_moving: bool) -> void:
	var c := Color(enemy.def.color)
	var bob := sin(_time * 10.0) * 2.0 if is_moving else 0.0
	var center := Vector2(0, bob)
	match enemy.def.shape:
		"circle":
			draw_circle(center, r, c)
		"rect":
			draw_rect(Rect2(center - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), c)
		"triangle":
			var pts := PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, r), center + Vector2(-r, r)])
			draw_colored_polygon(pts, c)
