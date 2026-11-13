extends GutTest
## The jumpgate and the station's stand-in drawn far out (M6-T15, D70, AC9), in the tree: the look shrinks toward the eye past
## the far plane's reach and covers the same angle, then cross-fades into a far dot with M4's hysteresis; the collision and the
## marker never move; the station's drum keeps turning inside its look; the console reads it all.

const FOV_DEG: float = 75.0
const FRAME_S: float = 1.0 / 60.0

var world: WorldFrame
var camera: Camera3D
var _window_backup: Vector2i


func before_each() -> void:
	# Headless the window is 64 px tall; the hand-offs are by pixels, so give it a 1080-line picture.
	_window_backup = get_tree().root.size
	get_tree().root.size = Vector2i(1920, 1080)
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	camera = Camera3D.new()
	camera.fov = FOV_DEG
	camera.near = 0.05
	camera.far = 50000.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.add_child(camera)
	camera.current = true


func after_each() -> void:
	get_tree().root.size = _window_backup


func _gate(at: Vector3 = Vector3(1000.0, -500.0, 2000.0)) -> Jumpgate:
	var gate: Jumpgate = Jumpgate.create("JUMPGATE")
	gate.position = at
	world.add_child(gate)
	gate.far_prop.set_process(false)  # the tests step it
	return gate


# Puts the camera `distance_m` from the prop's centre along `bearing` (prop frame), looking at it, and steps the far prop.
func _view(far: FarProp, prop: Node3D, distance_m: float, bearing: Vector3 = Vector3(-0.35, 0.25, -1.0), frames: int = 1) -> void:
	var centre: Vector3 = prop.global_transform * far.math.centre
	var eye: Vector3 = centre + prop.global_basis * bearing.normalized() * distance_m
	camera.global_transform = Transform3D(Basis.looking_at(centre - eye, Vector3.UP), eye)
	for i: int in frames:
		far.update(camera, FRAME_S)


# Half the angle the look's bounding sphere covers from the camera, rad.
func _drawn_angle(far: FarProp) -> float:
	var scale: float = far.look.global_basis.get_scale().x
	var drawn_centre: Vector3 = far.look.global_transform * far.math.centre
	return asin(minf(far.math.radius_m * scale / camera.global_position.distance_to(drawn_centre), 1.0))


func test_the_gate_carries_a_far_prop_round_its_visuals() -> void:
	var gate: Jumpgate = _gate()
	var far: FarProp = gate.far_prop
	assert_not_null(far, "the built gate has its far section")
	assert_eq(far.range_m, Jumpgate.BROADCAST_RANGE_M)
	assert_eq(gate.body.get_parent(), far.look, "the body is under the look")
	assert_eq(gate.vortex.get_parent(), far.look, "and the vortex")
	assert_eq(gate.activation_glows.get_parent(), far.look, "and the lamps")
	assert_eq(gate.collision_body.get_parent(), gate, "the collision is not: it never moves")
	assert_eq(gate.targetable.get_parent(), gate, "nor the marker")
	assert_gt(far.albedo.r, 0.0, "a mean albedo from the manifest")


func test_near_the_gate_is_drawn_where_it_is() -> void:
	var gate: Jumpgate = _gate()
	var far: FarProp = gate.far_prop
	for d: float in [100.0, 3000.0, 30000.0, far.math.pull_m(camera.far) - 1.0]:
		_view(far, gate, d)
		assert_eq(far.path(), &"near", "at %.0f m" % d)
		assert_eq(far.look.transform, Transform3D.IDENTITY, "the look at rest at %.0f m" % d)
		assert_false(far.dot.visible)
		assert_true(gate.body.visible)


func test_past_the_far_plane_the_gate_is_shrunk_to_the_same_angle() -> void:
	var gate: Jumpgate = _gate()
	var far: FarProp = gate.far_prop
	var collision_before: Transform3D = gate.collision_body.global_transform
	var marker_before: Vector3 = gate.targetable.global_position
	var pull: float = far.math.pull_m(camera.far)
	for d: float in [pull + 1.0, 60000.0, 150000.0, 200000.0]:
		_view(far, gate, d)
		assert_eq(far.path(), &"shrunk", "at %.0f m" % d)
		assert_almost_eq(far.shrink, pull / d, 1e-6)
		assert_almost_eq(_drawn_angle(far), asin(far.math.radius_m / d), 1e-6, "the same angle at %.0f m" % d)
		var true_dir: Vector3 = (gate.global_transform * far.math.centre - camera.global_position).normalized()
		var drawn_dir: Vector3 = (far.look.global_transform * far.math.centre - camera.global_position).normalized()
		assert_almost_eq(drawn_dir.dot(true_dir), 1.0, 1e-6, "in the same direction")
		var drawn_far_side: float = camera.global_position.distance_to(far.look.global_transform * far.math.centre) + \
				far.math.radius_m * far.shrink
		assert_lt(drawn_far_side, camera.far, "inside the far plane")
		assert_eq(gate.body.lod_bias, FarPropMath.FAR_LOD_BIAS, "the shrunk mesh keeps its rails")
	assert_eq(gate.collision_body.global_transform, collision_before, "the collision did not move")
	assert_eq(gate.targetable.global_position, marker_before, "nor the marker")
	_view(far, gate, 1000.0)
	assert_eq(far.look.transform, Transform3D.IDENTITY, "back near, back at rest")
	assert_eq(gate.body.lod_bias, 1.0, "and the importer's levels as usual")


func test_the_dot_cross_fades_in_past_its_distance_and_out_a_tenth_inside() -> void:
	var gate: Jumpgate = _gate()
	var far: FarProp = gate.far_prop
	_view(far, gate, 1000.0)
	var out_at: float = far.math.dot_distance_m(far.k_px_per_rad)
	_view(far, gate, out_at * 0.99)
	assert_false(far.wants_dot, "a mesh just inside")
	_view(far, gate, out_at * 1.01)
	assert_true(far.wants_dot, "a dot just past")
	assert_eq(far.path(), &"fading")
	assert_true(far.dot.visible and gate.body.visible, "both drawn while they cross-fade")
	assert_almost_eq(gate.body.transparency, far.fade, 1e-6, "the mesh fades as the dot comes in")
	var cover_mid: float = far.cover_px2()
	_view(far, gate, out_at * 1.01, Vector3(-0.35, 0.25, -1.0), 30)
	assert_eq(far.path(), &"dot")
	assert_false(gate.body.visible, "the mesh is hidden once the dot alone draws it")
	assert_false(gate.activation_glows.visible, "and the lamps")
	assert_almost_eq(far.cover_px2(), cover_mid, cover_mid * 1e-5, "the same area covered all through the fade")
	var expected_r: float = FarPropMath.dot_radius_m(far.math.area_toward(far.to_eye_local)) * far.shrink
	assert_almost_eq(float(far.dot.material_override.get_shader_parameter(&"radius_m")), expected_r, 1e-3)
	var dot_dist: float = camera.global_position.distance_to(far.dot.global_position)
	assert_almost_eq(dot_dist, far.distance_m * far.shrink, 1.0, "the dot is shrunk toward the eye with the look")
	_view(far, gate, out_at * 0.95, Vector3(-0.35, 0.25, -1.0), 30)
	assert_eq(far.path(), &"dot", "still a dot 5 % inside")
	_view(far, gate, out_at * 0.89, Vector3(-0.35, 0.25, -1.0), 30)
	assert_eq(far.path(), &"shrunk", "the mesh again past a tenth inside")
	assert_true(gate.body.visible)
	assert_eq(gate.body.transparency, 0.0)
	assert_false(far.dot.visible)


func test_an_open_vortex_stays_drawn_when_the_gate_is_a_dot() -> void:
	var gate: Jumpgate = _gate()
	var far: FarProp = gate.far_prop
	_view(far, gate, Jumpgate.BROADCAST_RANGE_M, Vector3(-0.35, 0.25, -1.0), 30)
	assert_eq(far.path(), &"dot", "a dot at its 1 000 km range")
	assert_true(gate.vortex.visible, "the vortex node is left as it is")
	assert_eq(gate.vortex.get_parent(), far.look, "and shrunk with the look")


func test_the_dots_light_follows_the_sun_as_the_mesh_does() -> void:
	var rig := LightRig.new()
	var key := DirectionalLight3D.new()
	key.name = "KeyStar"
	key.light_energy = 1.5
	rig.add_child(key)
	add_child_autofree(rig)
	var gate: Jumpgate = _gate()
	var far: FarProp = gate.far_prop
	var b: Vector3 = Vector3(-0.35, 0.25, -1.0).normalized()
	var side: Vector3 = b.cross(Vector3.UP).normalized()
	var paints: Array[float] = []
	for phase_deg: float in [0.0, 110.0, 175.0]:
		key.global_transform = Transform3D(SpaceEnvironment.key_basis(gate.global_basis * b.rotated(side, deg_to_rad(phase_deg))),
				Vector3.ZERO)
		_view(far, gate, Jumpgate.BROADCAST_RANGE_M, b, 30)
		paints.append(far.dot_paint().r)
	assert_lt(paints[1], paints[0], "dimmer with the sun round to its side")
	assert_gt(paints[2], paints[0], "seen against the sun its rims glint, as the mesh's sheen does")
	key.light_energy = 0.0
	_view(far, gate, Jumpgate.BROADCAST_RANGE_M, b, 2)
	assert_almost_eq(far.dot_paint().r, far.albedo.r * FarProp.GLOW_SHARE, 1e-5,
			"in the planet's shadow (no ambient here): its own glow only")


func test_the_station_shrinks_both_pieces_and_its_drum_keeps_turning() -> void:
	var station := StationStandin.new()
	if not station.build():
		fail_test("the babylon5_station asset is not generated")
		station.free()
		return
	var far: FarProp = FarPropHost.dress_station(station)
	assert_not_null(far)
	world.add_child(station)
	far.set_process(false)
	assert_eq(station.frame_piece.get_parent(), far.look)
	assert_eq(station.drum_pivot.get_parent(), far.look)
	assert_eq(far.range_m, FarPropHost.STATION_RANGE_M)
	_view(far, station, 500000.0, Vector3(1.0, 0.4, 0.3))
	assert_eq(far.path(), &"shrunk", "an 8 km station is still a mesh at 500 km")
	assert_almost_eq(_drawn_angle(far), asin(far.math.radius_m / 500000.0), 1e-6)
	var turned: Basis = station.drum_pivot.basis
	await wait_process_frames(3)
	assert_ne(station.drum_pivot.basis, turned, "the drum turns inside the shrunk look")
	_view(far, station, FarPropHost.STATION_RANGE_M * 1.5, Vector3(1.0, 0.4, 0.3), 30)
	assert_eq(far.path(), &"dot", "a dot beyond its range")


func test_the_console_lists_the_far_props() -> void:
	var gate: Jumpgate = _gate()
	var host := FarPropHost.new()
	add_child_autofree(host)
	_view(gate.far_prop, gate, 100000.0)
	assert_eq(host.prop_count(), 1)
	assert_eq(DebugConsole.registry.read("far.props")["value"], 1)
	assert_true(String(DebugConsole.registry.read("far.layout")["value"]).contains("JUMPGATE shrunk at 100.0 km"))
	var result: ConsoleResult = DebugConsole.registry.execute("far")[0]
	assert_true(result.ok, "alone, it reports")
	assert_false(DebugConsole.registry.execute("far view gate")[0].ok, "a view needs its distance")
