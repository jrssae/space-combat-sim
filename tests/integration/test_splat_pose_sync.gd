extends GutTest
## SplatPoseSync (architecture §7.2): the hull splats are drawn at the same physics-interpolated pose as the meshes
## and the chase camera, instead of the pose of the last physics tick that GDGS's Compute backend would read. Checked
## with plain nodes, then with a real ship flying in Jolt, compared at the end of every frame, as it would be drawn.

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const TOL: float = 1e-4

## Calls `callback` from its _process after every other node's (late priority): a look at the scene as it is drawn.
class FrameProbe:
	extends Node
	var callback: Callable = Callable()

	func _init() -> void:
		process_priority = 100000

	func _process(_delta: float) -> void:
		if callback.is_valid():
			callback.call()


var body: Node3D
var splats: Node3D
var sync: SplatPoseSync


func _make_rig(interpolated: bool) -> void:
	body = Node3D.new()
	body.name = "Body"
	if not interpolated:
		body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child_autofree(body)
	splats = Node3D.new()
	splats.name = "Splats"
	splats.transform = Transform3D(Basis(Vector3.BACK, PI), Vector3(0.0, 1.0, -2.0))  # like GDGS: a model correction
	body.add_child(splats)
	sync = SplatPoseSync.new()
	sync.name = "Sync"
	sync.splats = splats
	body.add_child(sync)


func _vec_tol(tol: float = TOL) -> Vector3:
	return Vector3(tol, tol, tol)


func test_the_splat_node_keeps_its_scene_pose_while_the_body_rests() -> void:
	_make_rig(false)
	var before: Transform3D = splats.transform
	sync.sync()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(splats.transform, before, "a resting body causes no rewrite, not even a rounding one")


func test_the_splat_node_follows_the_body_with_its_local_offset_intact() -> void:
	_make_rig(false)
	var local: Transform3D = splats.transform
	body.global_transform = Transform3D(Basis(Vector3(0.2, 1.0, 0.1).normalized(), 1.1), Vector3(300.0, -40.0, 12.0))
	sync.sync()
	var expected: Transform3D = body.global_transform * local
	assert_almost_eq(splats.global_position, expected.origin, _vec_tol())
	assert_almost_eq(splats.global_basis.x, expected.basis.x, _vec_tol())
	assert_almost_eq(splats.global_basis.y, expected.basis.y, _vec_tol())
	assert_almost_eq(splats.global_basis.z, expected.basis.z, _vec_tol())


func test_process_keeps_the_splat_node_on_the_body_every_frame() -> void:
	_make_rig(false)
	var local: Transform3D = splats.transform
	for i: int in 5:
		body.global_position = Vector3(10.0 * i, 0.0, -5.0 * i)
		await get_tree().process_frame
		await get_tree().process_frame
		assert_almost_eq(splats.global_position, (body.global_transform * local).origin, _vec_tol(), "frame %d" % i)


func test_the_splat_node_does_not_blend_an_already_interpolated_pose() -> void:
	_make_rig(true)
	assert_eq(splats.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_OFF, "the sync owns this node's pose")
	assert_eq(body.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_INHERIT, "the body is untouched")


func test_a_sync_without_a_splat_node_does_nothing_and_does_not_crash() -> void:
	var lone := Node3D.new()
	add_child_autofree(lone)
	var bare := SplatPoseSync.new()
	lone.add_child(bare)
	bare.sync()
	await get_tree().process_frame
	assert_false(bare.is_processing(), "switched itself off")


func test_the_hull_splats_are_drawn_at_the_interpolated_pose_of_a_flying_ship() -> void:
	var frame := WorldFrame.new()
	frame.name = "World"
	add_child_autofree(frame)
	var ship: Ship = Ship.create(load(SPEC_PATH) as ShipSpec, frame)
	frame.spawn(ship, frame.to_universe(Vector3.ZERO))
	var sync_node := ship.get_node(^"HullSplatSync") as SplatPoseSync
	assert_not_null(sync_node, "the ship scene has a HullSplatSync")
	assert_eq(sync_node.splats, ship.hull_splats, "driving the hull splats")
	assert_eq(ship.hull_splats.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_OFF)
	var correction: Transform3D = GaussianSplatNode.get_model_orientation_correction()
	ship.linear_velocity = -ship.global_basis.z * 150.0
	var cmd := FlightCommand.new()
	cmd.main_left = 1.0
	cmd.main_right = 0.6
	cmd.rot = Vector3(0.4, 0.3, 0.5)
	var state: Dictionary = {"frames": 0, "worst": 0.0, "differs_from_tick": 0}
	var check: Callable = func() -> void:
		var drawn: Transform3D = ship.hull_splats.global_transform
		var wanted: Transform3D = ship.get_global_transform_interpolated() * correction
		var error: float = maxf(drawn.origin.distance_to(wanted.origin), maxf((drawn.basis.x - wanted.basis.x).length(),
				maxf((drawn.basis.y - wanted.basis.y).length(), (drawn.basis.z - wanted.basis.z).length())))
		state["worst"] = maxf(float(state["worst"]), error)
		state["frames"] = int(state["frames"]) + 1
		if drawn.origin.distance_to((ship.global_transform * correction).origin) > 1e-3:
			state["differs_from_tick"] = int(state["differs_from_tick"]) + 1
	var probe := FrameProbe.new()
	probe.callback = check
	add_child_autofree(probe)
	for i: int in 90:
		ship.set_flight_command(cmd)
		await get_tree().process_frame
	probe.callback = Callable()
	assert_gt(int(state["frames"]), 30, "frames were checked")
	assert_lt(float(state["worst"]), TOL, "the splats are on the interpolated pose in every drawn frame")
	assert_gt(int(state["differs_from_tick"]), 0, "and that is not just the last physics tick's pose")
