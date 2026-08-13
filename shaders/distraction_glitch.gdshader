shader_type canvas_item;

// Full-screen distortion that stands in for a hijacked attention span. Driven from
// game.gd by two things: the player's Tolerance (a constant, creeping degradation) and a
// short spike whenever a distraction reaches the Focus core. At intensity 0 the ColorRect
// is hidden entirely, so nothing here runs during clean play.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// Horizontal band slip: a few bands at a time jump sideways, re-rolled several
	// times a second so the tear reads as unstable rather than as a static offset.
	float band = floor(uv.y * 26.0);
	float tick = floor(TIME * 9.0);
	float pick = rand(vec2(band * 1.7, tick * 0.31));
	float slip = (rand(vec2(band, tick)) - 0.5) * 0.055 * intensity;
	uv.x += slip * step(0.72, pick);

	// Chromatic split — the channels stop agreeing on where things are.
	float split = 0.0045 * intensity;
	vec4 col;
	col.r = texture(screen_tex, uv + vec2(split, 0.0)).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - vec2(split, 0.0)).b;
	col.a = 1.0;

	// Scanline dimming, and a slight desaturation as it climbs: the picture loses its
	// colour the same way a hijacked evening does.
	col.rgb *= 1.0 - 0.10 * intensity * step(0.5, fract(uv.y * 180.0));
	float grey = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	col.rgb = mix(col.rgb, vec3(grey), 0.22 * intensity);

	COLOR = col;
}
