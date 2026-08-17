shader_type canvas_item;
// Brain Fog — the purple-black darkness over everything the player's Routine does not
// light. Drawn as one full-screen rect (game.gd:_build_fog_layer); the holes come from
// `light_mask`, a SubViewport in which every light source paints an additive radial
// gradient (LightMaskCanvas). No Light2D anywhere: at up to hundreds of sources
// (projectiles glow too) per-pixel canvas lights would be the expensive way to say
// "1 minus a texture".
//
// The mask viewport is screen-aligned (lights are drawn at global coordinates, scaled
// 0.5 into a half-res target), so SCREEN_UV samples it directly — screen shake moves
// the world and the light sources by the same offset and the holes stay glued on.
//
// That alignment hangs on three project-level assumptions this shader cannot check:
// stretch aspect "keep" (pinned in project.godot — "expand" would desync mask from
// world on non-16:9 windows), NO Camera2D anywhere, and the game scene living in the
// ROOT viewport. Introduce any of those and this lookup must move off SCREEN_UV
// (pass the canvas transform as a uniform instead).

uniform sampler2D light_mask : filter_linear;
uniform vec4 fog_color : source_color = vec4(0.055, 0.025, 0.105, 1.0);
uniform float fog_alpha : hint_range(0.0, 1.0) = 0.88;
// Moment of Clarity: eased toward 1.0 while the reveal runs, and the whole field lights.
uniform float reveal : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float lit = texture(light_mask, SCREEN_UV).r;
	lit = clamp(lit + reveal, 0.0, 1.0);
	// Clear core, dim penumbra band, full fog. The gameplay circle (Game._lit_cells) is
	// slightly MORE generous than the visually clear area, so a tower never shoots
	// something the player cannot at least glimpse in the penumbra.
	float dark = 1.0 - smoothstep(0.10, 0.72, lit);
	COLOR = vec4(fog_color.rgb, fog_alpha * dark);
}
