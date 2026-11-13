// A planet's thin haze on the scaled-space layer (M6-T11, D68): a shell drawn just over the surface, adding light where the
// view passes through sunlit air. Seen face on the air is a thin column and adds almost nothing; along the limb the view
// grazes it for a long way, so the lit edge gets a faint warm rim and a thin glow just outside the disc. Air over the night
// side stays dark, so there is no ring round the night limb (the show still, docs/design-references.md "Epsilon III").
// The depth is T10's `layer_depth`, a hair in front of the surface it covers, so the near world still draws over both.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_front, shadows_disabled, fog_disabled, ambient_light_disabled;

uniform float layer_depth = 5.0e-9;
// The mesh's vertices are pushed out by this, so its faces enclose the shell (PlanetLook.haze_uniforms).
uniform float mesh_inflate = 1.02;
// The atmosphere's top and its scale height, in planet radii.
uniform float shell_radius = 1.02;
uniform float scale_height = 0.004;
// Unit vector toward the star in the planet's own frame.
uniform vec3 sun_body = vec3(0.0, 1.0, 0.0);
uniform vec3 haze_tint : source_color = vec3(0.92, 0.59, 0.33);
// How much light one scale height of air straight up gives back, against a lit surface's 1. The limb sees about 40 times
// that column, so this sets how strong the rim is: a look choice (H).
uniform float haze_strength = 0.012;
// Over which band of the sun's height the air is lit: the day side and a little past the terminator.
uniform vec2 lit_band = vec2(-0.15, 0.35);

const int STEPS = 16;

varying vec3 model_position;
varying vec3 model_eye;

void vertex() {
	VERTEX *= mesh_inflate;
	model_position = VERTEX;
	model_eye = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	// The nearer side of the slab, so the shell is drawn over its own planet's surface.
	POSITION = vec4(clip.xy, layer_depth * 1.0001 * clip.w, clip.w);
}

void fragment() {
	vec3 ray = normalize(model_position - model_eye);
	float along = dot(model_eye, ray);
	vec3 closest = model_eye - ray * along;
	float closest2 = dot(closest, closest);
	float top2 = shell_radius * shell_radius;
	if (closest2 >= top2) {
		discard;
	}
	// The stretch of the ray inside the air, measured from its closest approach: in from the top (or from the eye, when
	// the eye is in the air), out at the top or down at the ground.
	float half_top = sqrt(top2 - closest2);
	float start = max(-half_top, along);
	float stop = closest2 < 1.0 ? -sqrt(1.0 - closest2) : half_top;
	float span = stop - start;
	if (span <= 0.0) {
		discard;
	}
	float stride = span / float(STEPS);
	float column = 0.0;
	for (int i = 0; i < STEPS; i++) {
		vec3 p = closest + ray * (start + (float(i) + 0.5) * stride);
		float r = length(p);
		float air = exp(-(r - 1.0) / scale_height);
		column += air * smoothstep(lit_band.x, lit_band.y, dot(p, sun_body) / r);
	}
	// In scale heights of air: a column straight up from the ground counts 1.
	column *= stride / scale_height;
	ALBEDO = haze_tint * (1.0 - exp(-haze_strength * column));
}
