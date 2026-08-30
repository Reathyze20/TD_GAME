shader_type canvas_item;
// P9 — brain fog CANDIDATE variant, screenshotted for the user to pick from.
//
// NOT the shipped look. shaders/brain_fog.gdshader is untouched and still drives the live
// game; this file only exists so scripts/_shot_p9_fog_variants.gd can swap it onto game.gd's
// existing _fog_rect for one frame, capture a PNG, and swap back. Nothing in game.gd loads
// this shader — see PROGRESS.md (P9) for why it stays a standalone comparison file instead of
// replacing the shipped one.
//
// SAME light_mask / dark math as the shipped shader, so the SHAPE of what is lit is pixel-
// identical across every screenshot and only the unlit TREATMENT changes. Instead of a flat
// fog_color, the unlit area shows a haze: the world already rendered behind this rect, grabbed
// via SCREEN_TEXTURE (the exact technique shaders/flatten.gdshader already uses for the
// Tolerance wash — same hint, same project, already proven to work on this renderer), then
// optionally box-blurred and/or desaturated, then tinted toward fog_color by `haze_mix`.
//
// WHY NOT a second full-scene SubViewport sharing World2D (the technique P9's own text names
// first). The light_mask viewport already IS "a second render composited via a texture" — kept
// small on purpose (240x135, additive light SHAPES only, no terrain/units/decor) because a
// full duplicate scene render at hundreds of Distraction nodes would double the frame's draw
// calls for what is, in the end, a screen-space colour filter. SCREEN_TEXTURE gets the same
// pixels from the render that is already happening, at the cost of one backbuffer copy — the
// cheaper equivalent the task text explicitly leaves open, and the one flatten.gdshader already
// banked on for a different mechanic on this same project.

uniform sampler2D light_mask : filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform vec4 fog_color : source_color = vec4(0.055, 0.025, 0.105, 1.0);
uniform float fog_alpha : hint_range(0.0, 1.0) = 0.88;
uniform float reveal : hint_range(0.0, 1.0) = 0.0;

// How much of the haze layer is the (optionally processed) world vs flat fog_color.
// 0.0 would be pixel-identical to the shipped shader; kept away from 0 and 1 so every demo
// screenshot still reads as "fog", not "clean window" or "unprocessed darkness".
uniform float haze_mix : hint_range(0.0, 1.0) = 0.45;
// Box-blur radius in pixels of THIS viewport's native resolution (480x270 logical). 0 skips
// the tap loop entirely, so the desaturate-only variant pays nothing extra for blur.
uniform float blur_px : hint_range(0.0, 12.0) = 0.0;
// 0 = full colour, 1 = fully drained to luminance. Same operation as flatten.gdshader's first
// step, reused rather than reinvented.
uniform float desaturate_amount : hint_range(0.0, 1.0) = 0.0;

vec3 sample_world(vec2 uv) {
	if (blur_px <= 0.001) {
		return texture(screen_tex, uv).rgb;
	}
	// canvas_item fragment shaders in this Godot build do not expose SCREEN_PIXEL_SIZE
	// (confirmed by running it: "Unknown identifier"), so the texel size is derived from
	// the screen texture's own size instead — works at whatever resolution it is sampled at.
	vec2 texel = (1.0 / vec2(textureSize(screen_tex, 0))) * blur_px;
	vec3 sum = vec3(0.0);
	// 9-tap 3x3 box blur. A side-by-side comparison pass run four times by a screenshot
	// harness, not a per-frame shipped effect, so a separable two-pass gaussian (which would
	// need its own intermediate render target) was not worth building for this.
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			sum += texture(screen_tex, uv + texel * vec2(float(x), float(y))).rgb;
		}
	}
	return sum / 9.0;
}

void fragment() {
	float lit = texture(light_mask, SCREEN_UV).r;
	lit = clamp(lit + reveal, 0.0, 1.0);
	// Identical curve to shaders/brain_fog.gdshader — same lit/dark boundary, every time.
	float dark = 1.0 - smoothstep(0.10, 0.72, lit);

	vec3 world = sample_world(SCREEN_UV);
	float lum = dot(world, vec3(0.2126, 0.7152, 0.0722));
	world = mix(world, vec3(lum), desaturate_amount);

	vec3 haze = mix(fog_color.rgb, world, haze_mix);
	COLOR = vec4(haze, fog_alpha * dark);
}
