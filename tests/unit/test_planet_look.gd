extends GutTest
## A planet's look on the scaled-space layer (M6-T11): its maps and tints read from the manifest, its maps turned to the
## ephemeris's axes (kernel z north is the game's y up), the sun in the planet's own frame, and a coarse mesh that still
## encloses the true sphere the shaders draw.

const RADIUS_M: float = 4.78e6
const INFO: Dictionary = {"kind": &"planet", "radius_m": RADIUS_M, "atmosphere_top_m": 1.0e5}
const MANIFEST: String = """{"asset_id": "test_world", "planet": {"radius_m": 4780000.0, "projection": "equirectangular",
	"maps": {"albedo": {"file": "a.png"}, "height": {"file": "h.png"}, "normal": {"file": "n.png"},
		"clouds": {"file": "c.png", "tint_srgb": [240, 226, 206]}},
	"atmosphere": {"limb_srgb": [236, 150, 84], "ocean": false}}}"""


func _look(text: String = MANIFEST, info: Dictionary = INFO) -> PlanetLook:
	return PlanetLook.from_json_text(text, "res://assets/generated/test_world", info)


func test_a_manifest_gives_the_maps_and_tints() -> void:
	var look: PlanetLook = _look()
	assert_true(look.valid, look.error)
	assert_eq(look.albedo_path, "res://assets/generated/test_world/a.png")
	assert_eq(look.normal_path, "res://assets/generated/test_world/n.png")
	assert_eq(look.wisp_path, "res://assets/generated/test_world/c.png")
	assert_eq(look.haze_srgb, Color8(236, 150, 84), "the faint warm limb's tint")
	assert_eq(look.wisp_srgb, Color8(240, 226, 206))
	assert_eq(look.radius_m, RADIUS_M, "the star system's radius")


func test_the_air_comes_from_the_star_systems_data() -> void:
	var look: PlanetLook = _look()
	assert_almost_eq(look.shell_radius(), 1.0 + 1.0e5 / RADIUS_M, 1.0e-9, "the shell's top, 100 km up")
	assert_almost_eq(look.scale_height(), 1.0e5 / RADIUS_M / 5.0, 1.0e-9, "five scale heights below the top")
	var uniforms: Dictionary = look.haze_uniforms()
	assert_almost_eq(float(uniforms[&"mesh_inflate"]), PlanetLook.mesh_inflate() * look.shell_radius(), 1.0e-9)
	assert_eq(uniforms[&"haze_tint"], look.haze_srgb)
	var airless: PlanetLook = _look(MANIFEST, {"radius_m": RADIUS_M})
	assert_eq(airless.atmosphere_top_m, 0.0, "no atmosphere_top_m: no air")


func test_a_bad_manifest_says_why() -> void:
	assert_string_contains(_look("not json").error, "JSON")
	assert_string_contains(_look("{\"asset_id\": \"x\"}").error, "no planet maps")
	assert_string_contains(_look(MANIFEST.replace("\"normal\": {\"file\": \"n.png\"},", "")).error, "no normal map")
	assert_string_contains(_look(MANIFEST.replace("equirectangular", "cube")).error, "equirectangular")
	assert_string_contains(_look(MANIFEST, {"radius_m": 0.0}).error, "radius")
	assert_false(_look("not json").valid)


func test_a_body_without_built_maps_is_not_fatal() -> void:
	var look: PlanetLook = PlanetLook.load_body(&"no_such_world", INFO)
	assert_false(look.valid)
	assert_string_contains(look.error, "gen_assets")


func test_the_maps_north_is_the_ephemeris_north() -> void:
	var axes: Basis = PlanetLook.orientation()
	assert_almost_eq(axes.y, Vector3.UP, Vector3.ONE * 1.0e-6, "the north pole: kernel z, the game's y")
	assert_almost_eq(axes.z, Vector3.RIGHT, Vector3.ONE * 1.0e-6, "u = 0 faces the kernel's +x, the game's +X")
	assert_almost_eq(axes.x, Vector3.FORWARD, Vector3.ONE * 1.0e-6, "east faces the kernel's +y, the game's -Z")
	assert_almost_eq(axes.determinant(), 1.0, 1.0e-6, "a rotation: the maps are not mirrored")
	assert_eq(PlanetLook.to_game(Vector3(1.0, 2.0, 3.0)), Vector3(1.0, 3.0, -2.0), "as ScaledPlacement.to_game")
	# East is the way a planet spinning about kernel z (counter-clockwise from the north) carries its ground.
	assert_almost_eq(PlanetLook.to_game(Vector3(0.0, 0.0, 1.0).cross(Vector3(1.0, 0.0, 0.0))), axes.x, Vector3.ONE * 1.0e-6)


func test_a_tilted_pole_is_followed() -> void:
	var tilt: float = deg_to_rad(23.0)
	var pole_kernel := Vector3(0.0, -sin(tilt), cos(tilt))
	var axes: Basis = PlanetLook.orientation(pole_kernel)
	assert_almost_eq(axes.y, PlanetLook.to_game(pole_kernel), Vector3.ONE * 1.0e-6)
	assert_almost_eq(axes.y.angle_to(Vector3.UP), tilt, 1.0e-6)
	assert_almost_eq(axes.z.dot(axes.y), 0.0, 1.0e-6, "the meridian kept square to the pole")
	assert_almost_eq(axes.determinant(), 1.0, 1.0e-6)


func test_the_sun_in_the_planets_frame() -> void:
	var axes: Basis = PlanetLook.orientation()
	var noon_on_the_meridian: Vector3 = PlanetLook.sun_in_body(Vector3.RIGHT, axes)
	assert_almost_eq(noon_on_the_meridian, Vector3.BACK, Vector3.ONE * 1.0e-6, "the planet's +Z: u = 0")
	assert_almost_eq(PlanetLook.longitude_latitude(noon_on_the_meridian), Vector2.ZERO, Vector2.ONE * 1.0e-6)
	var east: Vector2 = PlanetLook.longitude_latitude(PlanetLook.sun_in_body(Vector3.FORWARD, axes))
	assert_almost_eq(east, Vector2(PI / 2.0, 0.0), Vector2.ONE * 1.0e-6, "the sun over 90 degrees east")
	var pole: Vector2 = PlanetLook.longitude_latitude(PlanetLook.sun_in_body(Vector3.UP, axes))
	assert_almost_eq(pole.y, PI / 2.0, 1.0e-6, "the sun over the north pole")
	# Scaled axes (the stand-in's transform) give the same unit direction.
	assert_almost_eq(PlanetLook.sun_in_body(Vector3.RIGHT, axes * Basis.from_scale(Vector3.ONE * 3476.0)), Vector3.BACK,
			Vector3.ONE * 1.0e-6)


func test_longitude_and_latitude_match_the_maps_layout() -> void:
	# The generator's layout: u = 0 at +Z growing toward +X, v = 0 at +Y.
	for u: float in [0.0, 0.125, 0.25, 0.6, 0.9]:
		for v: float in [0.1, 0.5, 0.8]:
			var lon: float = u * TAU
			var lat: float = (0.5 - v) * PI
			var d := Vector3(sin(lon) * cos(lat), sin(lat), cos(lon) * cos(lat))
			var back: Vector2 = PlanetLook.longitude_latitude(d)
			assert_almost_eq(fposmod(back.x, TAU), fposmod(lon, TAU), 1.0e-5, "longitude at u %s" % u)
			assert_almost_eq(back.y, lat, 1.0e-5, "latitude at v %s" % v)


func test_the_coarse_mesh_encloses_the_true_sphere() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = PlanetLook.SEGMENTS
	mesh.rings = PlanetLook.RINGS
	var arrays: Array = mesh.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var inflate: float = PlanetLook.mesh_inflate()
	var nearest: float = INF
	for i: int in range(0, indices.size(), 3):
		var a: Vector3 = vertices[indices[i]] * inflate
		var b: Vector3 = vertices[indices[i + 1]] * inflate
		var c: Vector3 = vertices[indices[i + 2]] * inflate
		var normal: Vector3 = (b - a).cross(c - a)
		if normal.length() < 1.0e-9:
			continue  # a pole's collapsed triangle
		nearest = minf(nearest, absf(normal.normalized().dot(a)))
	assert_gte(nearest, 1.0, "every face's plane is outside the sphere the shader draws")
	assert_lt(inflate, 1.005, "and the cover is snug: few wasted pixels")


func test_epsilon_iiis_built_maps_load() -> void:
	var system: StarSystem = StarSystem.load_system(&"local")
	var look: PlanetLook = PlanetLook.load_body(&"epsilon_iii", system.info(&"epsilon_iii"))
	assert_true(look.valid, look.error)
	assert_true(ResourceLoader.exists(look.albedo_path), "the albedo map is imported")
	assert_eq(look.haze_srgb, Color8(236, 150, 84))
	assert_almost_eq(look.shell_radius(), 1.0 + 1.0e5 / RADIUS_M, 1.0e-9)
