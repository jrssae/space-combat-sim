// The station's hull (M7-T24, D72): each tier's atlas (paint, drawn seams, windows, about a metre a texel or finer near) and, laid
// over it in the piece's own space, two detail tiles: the fine Earth Alliance mosaic (16 m) and the panel tile (128 m), so the hull
// reads sharp from a few metres and is never one plain tone from a kilometre. Each tile cell takes one of four variants and one of
// eight orientations from a hash of the cell, so no repeat shows; every variant's border is a seam, so neighbours always meet on one.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D emissive_map : source_color, hint_default_black, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float emission_energy = 1.0;
// `settings.hull_sheen`: a clear coat over the paint (MeshAssets sets both).
uniform float sheen = 0.0;
uniform float sheen_roughness = 0.35;

// The tiles: colour (red the albedo factor, green the roughness shift about 0.5, blue the cavity) and normal (RG), 2 x 2 variants.
uniform sampler2D fine_colour_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fine_normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D panel_colour_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D panel_normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float fine_tile_m = 16.0;
uniform float panel_tile_m = 128.0;
uniform float fine_tone = 1.0;
uniform float fine_relief = 1.0;
uniform float fine_rough = 0.15;
uniform float panel_tone = 1.0;
uniform float panel_relief = 1.0;
uniform float panel_rough = 0.12;
uniform float triplanar_sharpness = 4.0;

// The station's floodlights (M7-T18): lit pools on the hull from fixed fixtures, in this piece's space, so they take no light slot
// and still show on the night side. Each section's own list (StationLights): the fixture and its throw, the beam's direction and
// the cone's outer cosine, the colour times its energy and the cone's inner cosine.
const int MAX_FLOODS = 64;
uniform int flood_count = 0;
uniform vec4 flood_pos[MAX_FLOODS];
uniform vec4 flood_dir[MAX_FLOODS];
uniform vec4 flood_col[MAX_FLOODS];

// Where this mesh's origin lies in its piece (a section's origin), so the tiles run on unbroken across the section joints.
instance uniform vec3 piece_offset = vec3(0.0);

varying vec3 v_pos;
varying vec3 v_nrm;

void vertex() {
	v_pos = VERTEX + piece_offset;
	v_nrm = NORMAL;
}

uint cell_hash(ivec2 c, uint salt) {
	uint h = uint(c.x) * 0x8DA6B343u ^ uint(c.y) * 0xD8163841u ^ salt * 0xCB1AB31Fu;
	h ^= h >> 13u;
	h *= 0x5BD1E995u;
	h ^= h >> 15u;
	return h;
}

// One tile looked up for one projection. `c` the point in the projection's plane (m), `dx`, `dy` its change across a pixel (taken
// outside any branch), so the mipmap level is the same either side of a cell's edge. Returns the colour sample; `slope` is the
// normal's tilt along the plane's two axes.
vec3 tile_sample(sampler2D colour_map, sampler2D normal_map_, vec2 c, vec2 dx, vec2 dy, float tile_m, uint salt, out vec2 slope) {
	vec2 q = c / tile_m;
	vec2 cell = floor(q);
	vec2 t = q - cell;
	uint h = cell_hash(ivec2(cell), salt);
	// The orientation's linear part: mirror u, swap the axes, mirror v (the eight symmetries of a square).
	mat2 m = mat2(vec2(1.0, 0.0), vec2(0.0, 1.0));
	if ((h & 1u) != 0u) { t.x = 1.0 - t.x; m[0] = -m[0]; }
	if ((h & 2u) != 0u) { t = t.yx; m = mat2(vec2(m[0].y, m[0].x), vec2(m[1].y, m[1].x)); }
	if ((h & 4u) != 0u) { t.y = 1.0 - t.y; m = mat2(vec2(m[0].x, -m[0].y), vec2(m[1].x, -m[1].y)); }
	uint variant = (h >> 3u) & 3u;
	vec2 uv = (t + vec2(float(variant & 1u), float(variant >> 1u))) * 0.5;
	vec2 gx = m * (dx / tile_m) * 0.5;
	vec2 gy = m * (dy / tile_m) * 0.5;
	vec3 colour = textureGrad(colour_map, uv, gx, gy).rgb;
	vec2 n = textureGrad(normal_map_, uv, gx, gy).rg * 2.0 - 1.0;
	// The map's +Y points up the image, against the tile's v; back through the orientation into the plane's axes.
	slope = transpose(m) * vec2(n.x, -n.y);
	return colour;
}

// Both scales of detail, triplanar in the piece's space: the colour mix and the normal's tilt in the piece's space.
vec3 detail(sampler2D colour_map, sampler2D normal_map_, float tile_m, uint salt, vec3 p, vec3 dpx, vec3 dpy, vec3 w,
		out vec3 tilt) {
	vec2 sx, sy, sz;
	vec3 cx = tile_sample(colour_map, normal_map_, p.zy, dpx.zy, dpy.zy, tile_m, salt, sx);
	vec3 cy = tile_sample(colour_map, normal_map_, p.xz, dpx.xz, dpy.xz, tile_m, salt + 1u, sy);
	vec3 cz = tile_sample(colour_map, normal_map_, p.xy, dpx.xy, dpy.xy, tile_m, salt + 2u, sz);
	tilt = w.x * vec3(0.0, sx.y, sx.x) + w.y * vec3(sy.x, 0.0, sy.y) + w.z * vec3(sz.x, sz.y, 0.0);
	return cx * w.x + cy * w.y + cz * w.z;
}

// The tiles laid flat in one facet's plane (a slanted facet of a Cobra arm): its axes the station's axis projected into the facet and
// the facet's cross direction, so the plating is not sheared across two projections.
vec3 planar_detail(sampler2D colour_map, sampler2D normal_map_, float tile_m, uint salt, vec3 p, vec3 dpx, vec3 dpy, vec3 n,
		out vec3 tilt) {
	vec3 u = vec3(0.0, 0.0, 1.0) - n * n.z;
	u = length(u) > 1e-3 ? normalize(u) : vec3(1.0, 0.0, 0.0);
	vec3 v = cross(n, u);
	vec2 slope;
	vec3 colour = tile_sample(colour_map, normal_map_, vec2(dot(p, u), dot(p, v)), vec2(dot(dpx, u), dot(dpx, v)),
			vec2(dot(dpy, u), dot(dpy, v)), tile_m, salt + 7u, slope);
	tilt = slope.x * u + slope.y * v;
	return colour;
}

void fragment() {
	vec3 p = v_pos;
	vec3 dpx = dFdx(p);
	vec3 dpy = dFdy(p);
	vec3 w = pow(abs(normalize(v_nrm)), vec3(triplanar_sharpness));
	w /= max(w.x + w.y + w.z, 1e-5);
	vec3 orm = texture(orm_map, UV).rgb;
	// The bake marks the texels to lay flat in their facet in the occlusion channel, which the station's hull does not use.
	vec3 face = normalize(cross(dpx, dpy));
	face = dot(face, v_nrm) < 0.0 ? -face : face;
	float flat_facet = 1.0 - step(0.5, orm.r);
	vec3 fine_tilt, panel_tilt, fine_tilt_f, panel_tilt_f;
	vec3 fine = detail(fine_colour_map, fine_normal_map, fine_tile_m, 17u, p, dpx, dpy, w, fine_tilt);
	vec3 panel = detail(panel_colour_map, panel_normal_map, panel_tile_m, 53u, p, dpx, dpy, w, panel_tilt);
	vec3 fine_f = planar_detail(fine_colour_map, fine_normal_map, fine_tile_m, 17u, p, dpx, dpy, face, fine_tilt_f);
	vec3 panel_f = planar_detail(panel_colour_map, panel_normal_map, panel_tile_m, 53u, p, dpx, dpy, face, panel_tilt_f);
	fine = mix(fine, fine_f, flat_facet);
	panel = mix(panel, panel_f, flat_facet);
	fine_tilt = mix(fine_tilt, fine_tilt_f, flat_facet);
	panel_tilt = mix(panel_tilt, panel_tilt_f, flat_facet);

	vec3 base = texture(albedo_map, UV).rgb;
	ALBEDO = base * mix(1.0, fine.r, fine_tone) * mix(1.0, panel.r, panel_tone);
	AO = mix(1.0, fine.b, fine_tone);
	float rough = orm.g + (fine.g - 0.5) * 2.0 * fine_rough + (panel.g - 0.5) * 2.0 * panel_rough;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = orm.b;

	// The atlas's normal as Godot applies a normal map, then the tiles' tilt from the piece's space into the view's.
	vec2 nm = texture(normal_map, UV).rg * 2.0 - 1.0;
	vec3 n = normalize(TANGENT * nm.x + BINORMAL * nm.y + NORMAL * sqrt(max(0.0, 1.0 - dot(nm, nm))));
	vec3 tilt = fine_tilt * fine_relief + panel_tilt * panel_relief;
	vec3 tilt_view = mat3(VIEW_MATRIX) * (MODEL_NORMAL_MATRIX * tilt);
	NORMAL = normalize(n + tilt_view - n * dot(tilt_view, n));

	// The clear coat on the paint only, as worn as the paint (as the ships' livery has it, M7-T17).
	// The coat follows the atlas's paint only (M7-T24: the tiles' roughness broke the sun's glint up into grain).
	float on_paint = (1.0 - smoothstep(0.62, 0.78, orm.b)) * clamp((0.85 - orm.g) / 0.35, 0.0, 1.0);
	CLEARCOAT = sheen * on_paint;
	CLEARCOAT_ROUGHNESS = clamp(sheen_roughness + (orm.g - 0.5), 0.1, 1.0);
	EMISSION = texture(emissive_map, UV).rgb * emission_energy;
	if (flood_count > 0) {
		// A flood lights the paint as a lamp would: its cone with a soft edge, even over most of its throw, the surface turned to it.
		vec3 np = normalize(v_nrm + tilt * 0.5);
		vec3 flood = vec3(0.0);
		for (int i = 0; i < flood_count; i++) {
			vec3 to_light = flood_pos[i].xyz - p;
			float d = length(to_light);
			if (d >= flood_pos[i].w) {
				continue;
			}
			vec3 l = to_light / max(d, 1e-3);
			float cone = smoothstep(flood_dir[i].w, flood_col[i].w, dot(-l, flood_dir[i].xyz));
			float r2 = d / flood_pos[i].w;
			r2 *= r2;
			float fall = 1.0 - r2 * r2;
			flood += flood_col[i].rgb * cone * fall * fall * max(dot(np, l), 0.0);
		}
		EMISSION += ALBEDO * flood;
	}
}
