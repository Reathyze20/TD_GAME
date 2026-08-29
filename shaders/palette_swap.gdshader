shader_type canvas_item;

// S4 (docs/refactor/SYSTEMS.MD): remaps the master 48-colour palette
// (docs/art/palette_48.hex) that every sprite in this project draws from onto an
// alternative 48-colour set, index for index. Since nothing in the art has its own
// palette (CLAUDE.md: "Vse z ni cerpa, nic nema vlastni paletu"), a pixel's RGB value
// already IS its palette index — no lookup texture needed. Matches by NEAREST
// distance rather than requiring an exact hit: a real shipped sprite
// (clickbait_frame_1.png, checked directly) carries a few /255 of drift per channel
// from PNG/import compression even though it was authored on-palette, so an exact-
// match version of this shader (tried first) silently left every pixel unchanged.
// Nearest-match always finds the closest of the 48 entries, which is what an
// on-palette sprite's every pixel is close to.
//
// Usable on any CanvasItem drawing on-palette pixels, whether that's a real Sprite2D
// or (as distractions do) manual draw_texture_rect() calls inside a custom _draw() —
// a CanvasItem's material shader applies uniformly to everything that node draws.

uniform vec3 target_palette[48];

const vec3 MASTER_PALETTE[48] = vec3[48](
	vec3(0.0039, 0.0000, 0.0039),
	vec3(0.0000, 0.0000, 0.1725),
	vec3(0.0118, 0.0549, 0.0196),
	vec3(0.0275, 0.0824, 0.1922),
	vec3(0.2039, 0.0745, 0.1373),
	vec3(0.0745, 0.1647, 0.1098),
	vec3(0.0863, 0.1451, 0.2784),
	vec3(0.1412, 0.2471, 0.1765),
	vec3(0.4431, 0.1098, 0.1725),
	vec3(0.2980, 0.1490, 0.5059),
	vec3(0.3451, 0.2627, 0.1882),
	vec3(0.4784, 0.1176, 0.3412),
	vec3(0.5333, 0.1333, 0.1725),
	vec3(0.2275, 0.3529, 0.2039),
	vec3(0.3216, 0.3412, 0.4392),
	vec3(0.0392, 0.4000, 0.4275),
	vec3(0.4667, 0.2549, 0.7216),
	vec3(0.5804, 0.3412, 0.1647),
	vec3(0.6902, 0.2275, 0.2000),
	vec3(0.7804, 0.0510, 0.3255),
	vec3(0.3490, 0.4863, 0.2588),
	vec3(0.4706, 0.4824, 0.5176),
	vec3(0.0745, 0.5569, 0.5373),
	vec3(0.6000, 0.3294, 0.9059),
	vec3(0.9569, 0.0784, 0.0667),
	vec3(0.1490, 0.5569, 0.8275),
	vec3(0.7216, 0.4667, 0.2039),
	vec3(0.5569, 0.5765, 0.6039),
	vec3(0.0784, 0.6824, 0.6078),
	vec3(0.7176, 0.4588, 0.9922),
	vec3(0.8235, 0.5529, 0.2078),
	vec3(0.7137, 0.6039, 0.4667),
	vec3(0.6118, 0.6745, 0.2706),
	vec3(0.8706, 0.5412, 0.5451),
	vec3(0.0863, 0.7529, 0.6588),
	vec3(0.9137, 0.6588, 0.2157),
	vec3(0.8078, 0.7059, 0.5529),
	vec3(0.7647, 0.7098, 0.6980),
	vec3(0.3529, 0.8078, 0.8000),
	vec3(0.9529, 0.7373, 0.3137),
	vec3(0.8549, 0.8078, 0.4000),
	vec3(0.4902, 0.9373, 0.2235),
	vec3(0.4667, 0.8941, 0.8706),
	vec3(0.8784, 0.8078, 0.7373),
	vec3(0.0745, 0.9686, 0.7922),
	vec3(0.9843, 0.8627, 0.1020),
	vec3(0.9882, 0.8980, 0.6353),
	vec3(0.7608, 0.9686, 0.9373)
);

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	int nearest = 0;
	float best_dist = distance(src.rgb, MASTER_PALETTE[0]);
	for (int i = 1; i < 48; i++) {
		float d = distance(src.rgb, MASTER_PALETTE[i]);
		if (d < best_dist) {
			best_dist = d;
			nearest = i;
		}
	}
	COLOR = vec4(target_palette[nearest], src.a);
}
