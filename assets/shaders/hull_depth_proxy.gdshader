// Hull depth proxy (architecture §7.2): an opaque black copy of a splat body's fallback mesh that exists only to
// write depth. Gaussian splats write no depth, so without it transparent effects (thruster plumes, muzzle flash,
// projectiles, beacons) behind the hull would draw on top of it. The vertices are pulled inward along their normals,
// so the proxy sits just inside the splat surface: it occludes what is behind the hull but never covers the splats,
// which are centred on the true surface and therefore always nearer than the proxy.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

// How far inside the surface the proxy sits, m (model space; the hulls are unscaled).
uniform float inset_m : hint_range(0.0, 0.5, 0.001) = 0.04;

void vertex() {
	VERTEX -= NORMAL * inset_m;
}

void fragment() {
	ALBEDO = vec3(0.0);
}
