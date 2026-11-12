extends GutTest
## The scaled-space layer in a World (M6-T10, D68, AC7): the star and Epsilon III drawn at their true direction and angular
## size from the station's rail, from a low orbit, from anywhere in the local space and after a rebase; the key star turned to
## the true sun and dimmed in the planet's shadow. The layer's logic needs no GPU; its picture is `test_scaled_space_gpu.gd`.

const ENV_SCENE: String = "res://src/environment/space_environment.tscn"
const PLANET: StringName = &"epsilon_iii"
const STAR: StringName = &"epsilon"
const PLANET_RADIUS_M: float = 4.78e6
const STATION_ORBIT_M: float = 2.75e7
const PLANET_GM: float = 1.68e14

var world: WorldFrame
var camera: Camera3D
var env: SpaceEnvironment
var layer: ScaledSpace
var system: StarSystem
var _clock_backup: float


func before_each() -> void:
	_clock_backup = SimClock.now()
	SimClock.reset(0.0)
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	camera = Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.add_to_group(WorldFrame.SHIFTABLE_GROUP)
	world.add_child(camera)
	camera.current = true
	env = (load(ENV_SCENE) as PackedScene).instantiate() as SpaceEnvironment
	add_child_autofree(env)
	layer = env.scaled_space
	layer.epoch_offset_s = 0.0
	system = StarSystem.load_system(&"local")
	assert_true(system.is_valid(), "the shipped system loads: %s" % [system.errors])


func after_each() -> void:
	SimClock.reset(_clock_backup)


func _on_the_rail() -> void:
	assert_true(world.anchor_on_rail(system, &"babylon5"))
	layer.refresh(camera)


# The angle the drawn stand-in covers from the camera, degrees.
func _drawn_size_deg(id: StringName) -> float:
	var sphere: MeshInstance3D = layer.sphere_of(id)
	var radius: float = sphere.global_transform.basis.x.length()
	return rad_to_deg(2.0 * asin(radius / sphere.global_position.distance_to(camera.global_position)))


func _drawn_direction(id: StringName) -> Vector3:
	return (layer.sphere_of(id).global_position - camera.global_position).normalized()


func test_from_the_station_the_planet_is_20_degrees_across() -> void:
	_on_the_rail()
	assert_eq(layer.drawn_count(), 2, "the star and the planet")
	var planet: ScaledPlacement = layer.placement_of(PLANET)
	assert_almost_eq(planet.angular_size_deg(), 20.02, 0.02, "2 asin(4 780 / 27 500)")
	assert_almost_eq(planet.distance_m, STATION_ORBIT_M, 1.0, "the rail's radius")
	# At the data's epoch 0 the station is out along the kernel's +x, so the planet is toward the game's -X.
	assert_almost_eq(planet.direction, Vector3.LEFT, Vector3.ONE * 1.0e-4)
	assert_almost_eq(_drawn_size_deg(PLANET), 20.02, 0.02, "the stand-in covers the same angle")
	assert_almost_eq(_drawn_direction(PLANET).angle_to(planet.direction), 0.0, 1.0e-4, "in the same direction")
	assert_true(layer.sphere_of(PLANET).visible)
	assert_almost_eq(layer.placement_of(STAR).angular_size_deg(), 0.652, 0.002, "the star from 0.6 AU")
	# The star's sphere also holds its corona: SunLook.GLOW_SCALE times the disc.
	assert_almost_eq(_drawn_size_deg(STAR), 0.652 * SunLook.GLOW_SCALE, 0.05)
	assert_almost_eq(layer.placement_of(STAR).angular_size_deg(), 0.652, 0.002, "the disc itself is its true size")
	assert_gt(planet.depth, layer.placement_of(STAR).depth, "the planet is drawn over the star")


func test_the_stand_ins_stay_inside_the_cameras_far_plane() -> void:
	_on_the_rail()
	for id: StringName in [PLANET, STAR]:
		var sphere: MeshInstance3D = layer.sphere_of(id)
		var reach: float = sphere.global_position.distance_to(camera.global_position) + sphere.global_transform.basis.x.length()
		assert_lt(reach, 50000.0, "%s is never culled by the far plane" % id)


func test_the_planet_moves_round_the_sky_with_the_station_orbit() -> void:
	_on_the_rail()
	SimClock.reset(system.period_s(&"babylon5") / 4.0)
	layer.refresh(camera)
	var planet: ScaledPlacement = layer.placement_of(PLANET)
	# A quarter orbit on, the station is along the kernel's +y, the game's -Z: the planet is toward +Z.
	assert_almost_eq(planet.direction, Vector3.BACK, Vector3.ONE * 1.0e-4)
	assert_almost_eq(planet.angular_size_deg(), 20.02, 0.02, "a circular orbit keeps its size")


func test_anywhere_in_the_local_space_and_after_a_rebase() -> void:
	_on_the_rail()
	# 3 000 km toward the planet and 4 000 km to the side: far outside float32's fine range, exact in the frame's 64 bits.
	world.rebase(Vector3(-3.0e6, 0.0, 4.0e6))
	camera.global_position = Vector3(120.0, -40.0, 15.0)
	layer.refresh(camera)
	var to_planet := Vector3(-STATION_ORBIT_M + 3.0e6 - 120.0, 40.0, -4.0e6 - 15.0)
	var before: ScaledPlacement = layer.placement_of(PLANET)
	assert_almost_eq(before.distance_m, 24_824_506.0, 100.0, "the true distance from the new place")
	assert_almost_eq(before.direction.angle_to(to_planet.normalized()), 0.0, 1.0e-5)
	assert_almost_eq(before.angular_size_deg(), rad_to_deg(2.0 * asin(PLANET_RADIUS_M / to_planet.length())), 0.001)
	var drawn_before: Vector3 = layer.sphere_of(PLANET).global_position - camera.global_position
	# The rebase moves the origin under the camera; the camera's universe place is the same.
	world.rebase(Vector3(4000.0, 250.0, -1500.0))
	assert_almost_eq(camera.global_position, Vector3(-3880.0, -290.0, 1515.0), Vector3.ONE * 0.01, "the camera was shifted")
	layer.refresh(camera)
	var after: ScaledPlacement = layer.placement_of(PLANET)
	assert_almost_eq(after.direction.angle_to(before.direction), 0.0, 1.0e-6, "the same direction after the rebase")
	assert_almost_eq(after.angular_radius_rad, before.angular_radius_rad, 1.0e-9, "the same size")
	assert_almost_eq(after.distance_m, before.distance_m, 0.01, "the same distance")
	var drawn_after: Vector3 = layer.sphere_of(PLANET).global_position - camera.global_position
	assert_almost_eq(drawn_after, drawn_before, Vector3.ONE * 0.05, "drawn at the same place from the camera")
	assert_almost_eq(_drawn_size_deg(PLANET), after.angular_size_deg(), 0.001)


func test_from_a_low_orbit_the_planet_fills_the_view_below() -> void:
	var radius: float = PLANET_RADIUS_M + 4.0e5
	var state := PackedFloat64Array([radius, 0.0, 0.0, 0.0, 0.0, -sqrt(PLANET_GM / radius)])
	assert_true(world.anchor_in_orbit(system, PLANET, state))
	layer.refresh(camera)
	var planet: ScaledPlacement = layer.placement_of(PLANET)
	assert_almost_eq(planet.distance_m, radius, 1.0, "400 km up")
	assert_almost_eq(planet.angular_size_deg(), rad_to_deg(2.0 * asin(PLANET_RADIUS_M / radius)), 0.001, "about 135 degrees")
	assert_almost_eq(planet.direction, Vector3.LEFT, Vector3.ONE * 1.0e-5, "straight down, toward the centre")
	assert_almost_eq(_drawn_size_deg(PLANET), planet.angular_size_deg(), 0.001)
	assert_almost_eq(layer.sphere_of(PLANET).global_position.distance_to(camera.global_position), radius / ScaledPlacement.SCALE,
			0.01, "close in, the stand-in is at 1:1000")
	assert_almost_eq(layer.placement_of(STAR).angular_size_deg(), 0.652, 0.002, "the star is as far as ever")
	# A metre of camera height shows in the distance: the planet is placed against the anchor, not through the barycentre.
	camera.global_position = Vector3(1.0, 0.0, 0.0)
	layer.refresh(camera)
	assert_almost_eq(layer.placement_of(PLANET).distance_m - planet.distance_m, 1.0, 1.0e-3)


func test_with_no_star_system_nothing_is_drawn() -> void:
	layer.refresh(camera)
	assert_eq(layer.drawn_count(), 0)
	assert_false(layer.has_sun())
	assert_eq(layer.key_light(), 1.0)
	_on_the_rail()
	assert_eq(layer.drawn_count(), 2)
	world.clear_anchor()
	layer.refresh(camera)
	assert_eq(layer.drawn_count(), 0, "and nothing once the World lets go of its system")
	assert_false(layer.sphere_of(PLANET).visible)
	layer.refresh(null)
	assert_eq(layer.drawn_count(), 0, "no camera, no layer")


func test_the_key_star_shines_from_the_true_sun() -> void:
	var authored: Basis = env.key_star.global_basis
	env.follow_sun()
	assert_eq(env.key_star.global_basis, authored, "with no star system the light stays as the scene made it")
	layer.epoch_offset_s = system.period_s(&"babylon5") / 3.0
	_on_the_rail()
	env.follow_sun()
	assert_true(layer.has_sun())
	assert_almost_eq(layer.sun_direction().angle_to(layer.placement_of(STAR).direction), 0.0, 1.0e-6)
	assert_almost_eq(env.key_star.global_basis.z.angle_to(layer.sun_direction()), 0.0, 1.0e-4, "the light's +Z points at the star")
	assert_almost_eq(layer.sun_direction().angle_to(layer.placement_of(PLANET).direction), deg_to_rad(120.0), 0.01,
			"a third of an orbit on, the planet is 120 degrees from the sun")
	assert_eq(layer.key_light(), 1.0, "in full sunlight")
	assert_almost_eq(env.key_star.light_energy, 1.5, 1.0e-5)
	# The lens flare reads the same light.
	assert_eq(env.post_effects.sun, env.key_star)


func test_the_planets_shadow_puts_the_key_light_out() -> void:
	# At the data's epoch 0 the station is straight behind the planet from the star.
	_on_the_rail()
	env.follow_sun()
	assert_almost_eq(layer.sun_direction().angle_to(layer.placement_of(PLANET).direction), 0.0, 1.0e-3, "the star is behind the planet")
	assert_eq(layer.key_light(), 0.0, "the middle of the shadow")
	assert_eq(env.key_star.light_energy, 0.0)
	# About 10 degrees of the orbit on, the star's disc comes out from behind the limb.
	var period: float = system.period_s(&"babylon5")
	var last: float = 0.0
	for step: int in 9:
		SimClock.reset(period * (9.5 + 0.125 * step) / 360.0)
		layer.refresh(camera)
		assert_gte(layer.key_light(), last, "the light only grows on the way out (%d)" % step)
		last = layer.key_light()
	assert_eq(last, 1.0, "out of the shadow")
	env.follow_sun()
	assert_almost_eq(env.key_star.light_energy, 1.5, 1.0e-5)


func test_a_look_sheet_can_hold_the_key_star() -> void:
	_on_the_rail()
	env.follow_sun()
	assert_eq(env.key_star.light_energy, 0.0, "in the shadow")
	env.hold_key_star(true)
	assert_almost_eq(env.key_star.light_energy, 1.5, 1.0e-5, "a sheet lights its subject fully")
	var held := Basis.looking_at(Vector3(0.3, -0.5, 0.2).normalized(), Vector3.UP)
	env.key_star.global_basis = held
	env.follow_sun()
	assert_almost_eq(env.key_star.global_basis.z, held.z, Vector3.ONE * 1.0e-5, "the sun leaves the light alone while it is held")
	env.hold_key_star(false)
	env.follow_sun()
	assert_almost_eq(env.key_star.global_basis.z.angle_to(layer.sun_direction()), 0.0, 1.0e-4, "and takes it back")
	assert_eq(env.key_star.light_energy, 0.0)


func test_the_key_basis_points_its_z_at_the_star() -> void:
	for to_sun: Vector3 in [Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3(0.2, 0.9, -0.3).normalized(), Vector3.BACK]:
		var basis: Basis = SpaceEnvironment.key_basis(to_sun)
		assert_almost_eq(basis.z, to_sun, Vector3.ONE * 1.0e-5, "toward %s" % to_sun)
		assert_almost_eq(basis.determinant(), 1.0, 1.0e-5, "a rotation")


func test_the_scaled_command_and_provider() -> void:
	_on_the_rail()
	assert_eq(DebugConsole.registry.read("scaled.bodies")["value"], 2)
	assert_eq(DebugConsole.registry.read("scaled.key_light")["value"], 0.0)
	assert_true(String(DebugConsole.registry.read("scaled.layout")["value"]).contains("epsilon_iii 20.020 deg"))
	var result: ConsoleResult = DebugConsole.registry.execute("scaled epoch 6.5")[0]
	assert_true(result.ok, result.error)
	assert_almost_eq(layer.epoch_offset_s, 23400.0, 1.0e-6)
	assert_eq(layer.key_light(), 1.0, "6.5 hours on, the station is in sunlight")
	assert_true(DebugConsole.registry.execute("scaled hide")[0].ok)
	assert_eq(DebugConsole.registry.read("scaled.bodies")["value"], 0)
	assert_false(layer.sphere_of(PLANET).is_visible_in_tree())
	assert_true(DebugConsole.registry.execute("scaled show")[0].ok)
	assert_eq(DebugConsole.registry.read("scaled.bodies")["value"], 2)
	assert_false(DebugConsole.registry.execute("scaled epoch")[0].ok, "epoch needs its hours")
	assert_true(DebugConsole.registry.execute("scaled")[0].ok, "alone, it reports")


func test_epsilon_iii_is_drawn_with_its_maps_and_its_haze() -> void:
	layer.epoch_offset_s = system.period_s(&"babylon5") / 3.0
	_on_the_rail()
	assert_eq(layer.mapped_bodies(), PackedStringArray(["epsilon_iii"]), "the planet has built maps (M6-T11)")
	var sphere: MeshInstance3D = layer.sphere_of(PLANET)
	var surface: ShaderMaterial = sphere.material_override as ShaderMaterial
	assert_eq(surface.shader.resource_path, ScaledSpace.PLANET_SHADER_PATH)
	for map: StringName in [&"albedo_map", &"normal_map", &"wisp_map"]:
		assert_not_null(surface.get_shader_parameter(map), "%s is set" % map)
	# The maps' north is the ephemeris's: the stand-in's y axis is the game's up, its size still the planet's angle.
	assert_almost_eq(sphere.global_basis.y.normalized(), Vector3.UP, Vector3.ONE * 1.0e-6)
	assert_almost_eq(sphere.global_basis.z.normalized(), Vector3.RIGHT, Vector3.ONE * 1.0e-6, "u = 0 toward the kernel's +x")
	assert_almost_eq(_drawn_size_deg(PLANET), 20.02, 0.02)
	# The haze shell rides on the planet, a hair nearer in the layer's depth (its shader adds the hair).
	var shell: MeshInstance3D = layer.shell_of(PLANET)
	assert_eq(shell.get_parent(), sphere)
	var haze: ShaderMaterial = shell.material_override as ShaderMaterial
	assert_eq(haze.shader.resource_path, ScaledSpace.ATMOSPHERE_SHADER_PATH)
	assert_eq(haze.get_shader_parameter(&"layer_depth"), surface.get_shader_parameter(&"layer_depth"))
	assert_almost_eq(float(haze.get_shader_parameter(&"shell_radius")), 1.0 + 1.0e5 / PLANET_RADIUS_M, 1.0e-6,
			"the atmosphere's top from the star system's data")
	assert_eq(haze.get_shader_parameter(&"haze_tint"), Color8(236, 150, 84), "the manifest's warm limb")


func test_the_planet_is_lit_from_where_it_sees_the_star() -> void:
	layer.epoch_offset_s = system.period_s(&"babylon5") / 3.0
	_on_the_rail()
	var surface: ShaderMaterial = layer.sphere_of(PLANET).material_override as ShaderMaterial
	var sun_body: Vector3 = surface.get_shader_parameter(&"sun_body")
	var star_from_planet: PackedFloat64Array = ScaledPlacement.to_game(system.relative_state(STAR, PLANET, layer.epoch_offset_s))
	var expected: Vector3 = PlanetLook.sun_in_body(Vector3(star_from_planet[0], star_from_planet[1], star_from_planet[2]),
			PlanetLook.orientation())
	assert_almost_eq(sun_body, expected, Vector3.ONE * 1.0e-5, "the sun in the planet's own frame")
	assert_almost_eq((layer.shell_of(PLANET).material_override as ShaderMaterial).get_shader_parameter(&"sun_body"), sun_body,
			Vector3.ONE * 1.0e-6, "the haze is lit from the same sun")
	# The star sits in the planet's equator plane (no tilt), so the sun is overhead somewhere on the equator.
	assert_almost_eq(PlanetLook.longitude_latitude(sun_body).y, 0.0, 1.0e-4)
	# The sun about 120 degrees from the planet seen from the station is about 60 degrees from the station seen from the
	# planet (the star's parallax is a few hundredths of a degree): three quarters of the disc lit.
	var at_station: float = rad_to_deg(layer.sun_direction().angle_to(layer.placement_of(PLANET).direction))
	assert_almost_eq(rad_to_deg(acos(sun_body.dot(PlanetLook.sun_in_body(-layer.placement_of(PLANET).direction,
			PlanetLook.orientation())))), 180.0 - at_station, 0.05)


func test_the_maps_are_mipmapped() -> void:
	_on_the_rail()
	var surface: ShaderMaterial = layer.sphere_of(PLANET).material_override as ShaderMaterial
	for map: StringName in [&"albedo_map", &"normal_map", &"wisp_map"]:
		var texture: Texture2D = surface.get_shader_parameter(map)
		assert_true(texture.get_image().has_mipmaps(), "%s has its mip levels, so the far planet does not shimmer" % map)


func test_the_star_is_drawn_with_the_star_look_in_its_data_colour() -> void:
	_on_the_rail()
	var material: ShaderMaterial = layer.sphere_of(STAR).material_override as ShaderMaterial
	assert_eq(material.shader.resource_path, ScaledSpace.STAR_SHADER_PATH)
	var expected: Color = SunLook.disc_colour(StarCatalog.temperature_k(&"local")).linear_to_srgb()
	assert_eq(material.get_shader_parameter(&"colour"), expected)
	assert_eq(material.get_shader_parameter(&"glow_scale"), SunLook.GLOW_SCALE)
	assert_eq(env.key_star.light_color, expected, "the key light is the star's colour")


func test_the_flare_fades_with_the_eclipse_and_the_limb() -> void:
	layer.epoch_offset_s = system.period_s(&"babylon5") / 3.0
	_on_the_rail()
	env.follow_sun()
	assert_eq(env.post_effects.flare_strength(), 1.0, "full in the open")
	layer.epoch_offset_s = 0.0
	layer.refresh(camera)
	env.follow_sun()
	assert_eq(env.post_effects.flare_strength(), 0.0, "gone in the middle of the shadow")
	var period: float = system.period_s(&"babylon5")
	var last: float = 0.0
	for step: int in 9:
		SimClock.reset(period * (9.5 + 0.125 * step) / 360.0)
		layer.refresh(camera)
		env.follow_sun()
		assert_gte(env.post_effects.flare_strength(), last, "the flare only grows as the disc comes out (%d)" % step)
		last = env.post_effects.flare_strength()
	assert_eq(last, 1.0)
	var flare: LensFlareEffect = env.post_effects.flare_effect()
	if flare != null:
		assert_gt(flare.sun_color.r, 0.0, "back at full strength")


func test_a_held_key_light_leaves_the_flare_whole() -> void:
	_on_the_rail()
	env.follow_sun()
	assert_eq(env.post_effects.flare_strength(), 0.0)
	env.hold_key_star(true)
	env.follow_sun()
	assert_eq(env.post_effects.flare_strength(), 1.0)
