shader_type canvas_item;
// Tolerance's visual verb: FLATTEN.
//
// Replaces a flat grey ColorRect, which was the wrong instrument for two measured
// reasons (build/flat3, 2026-08-20):
//
//   * mixing toward opaque grey RAISES average brightness on a dark scene — the picture
//     got lighter as Tolerance rose, which reads as haze, not as numbness.
//   * it collided with Brain Fog, which is also a full-screen dimmer one layer below.
//
// The first attempt at a fix drove the scene's Light2D energy instead ("the lights go
// out and the depth goes with them"). Measured: turning EVERY light off moved contrast
// by 3.1% and brightness by 2.0%. The lights are additive glow on top of art that is
// already fully lit (see the block comment above SHADOW_LIGHT_ENERGY in game.gd), so
// there is no darkness for them to lift out of and nothing to take away. That idea needs
// a CanvasModulate base darkness first — a real rendering decision, not a bolt-on.
//
// So: do it in screen space, but with the RIGHT operation. Not "add grey" — drain the
// colour and collapse the range, so everything converges on the same value. That is the
// actual phenomenology being modelled: anhedonia is not reported as "faded", it is
// reported as "everything looked the same, nothing stood out".
//
// It also stays distinct from Brain Fog by construction. Fog DARKENS and OCCLUDES (takes
// information away). This keeps every pixel exactly where it is and only removes the
// differences between them (takes depth away). Two different verbs, one screen.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;

// 0 = the scene as authored. 1 = fully drained and collapsed.
uniform float flatten : hint_range(0.0, 1.0) = 0.0;
// Momentary drop BELOW the resting picture. The one thing allowed to go under baseline:
// a bonus wave that was announced and paid nothing (negative prediction error).
uniform float dim : hint_range(0.0, 1.0) = 0.0;

// How far the range collapses at flatten = 1. Not 1.0: a completely uniform screen is
// unplayable, and the lesson is "nothing stands out", not "you cannot see".
const float MAX_COLLAPSE = 0.62;
// How much saturation is left at flatten = 1.
const float MIN_SATURATION = 0.12;

// The scene's own mid-tone, measured off the iso field (mean luminance ~0.12, see
// _shot_flat's printout). Collapsing toward the actual mid keeps the picture from
// drifting brighter or darker as it flattens — only the SPREAD changes.
const float MID = 0.13;

void fragment() {
	vec3 base = texture(screen_tex, SCREEN_UV).rgb;

	// 1. Drain the colour toward its own luminance.
	float lum = dot(base, vec3(0.2126, 0.7152, 0.0722));
	vec3 drained = mix(base, vec3(lum), flatten * (1.0 - MIN_SATURATION));

	// 2. Collapse the range toward the mid-tone, so lit and unlit surfaces stop
	//    separating. This is the half that removes depth: a wall and the floor beside it
	//    converge until the shape reads as one mass.
	vec3 collapsed = vec3(MID) + (drained - vec3(MID)) * (1.0 - MAX_COLLAPSE * flatten);

	COLOR = vec4(collapsed * (1.0 - dim), 1.0);
}
