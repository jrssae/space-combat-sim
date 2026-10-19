extends GutTest
## WorldFrame against the real physics server (Jolt): rebasing must not change any velocity, any relative
## position or any universe position (architecture §14.1, AC9).

const SPEED_MPS: float = 30.0
const ONE_AU_M: float = 1.5e11
const TOL_M: float = 1e-3

var world: WorldFrame


func before_each() -> void:
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)


## A frictionless, gravity-free sphere: the same Newtonian body settings the ship uses (architecture §5.4).
func _make_body() -> RigidBody3D:
	var body := RigidBody3D.new()
	body.gravity_scale = 0.0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.angular_damp = 0.0
	body.can_sleep = false
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	body.add_child(shape)
	return body


func _vec_tol() -> Vector3:
	return Vector3(TOL_M, TOL_M, TOL_M)


func test_rebase_keeps_velocity_relative_and_universe_positions() -> void:
	var body: RigidBody3D = _make_body()
	var marker := Node3D.new()
	world.spawn(body, UniversePos.new(100.0, 0.0, -50.0))
	world.spawn(marker, UniversePos.new(-200.0, 30.0, 10.0))
	body.linear_velocity = Vector3(SPEED_MPS, 0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var offset := Vector3(5000.0, 0.0, 0.0)
	var rel_before: Vector3 = body.global_position - marker.global_position
	var body_u_before: UniversePos = world.to_universe(body.global_position)
	var marker_u_before: UniversePos = world.to_universe(marker.global_position)
	var velocity_before: Vector3 = body.linear_velocity
	assert_almost_eq(velocity_before, Vector3(SPEED_MPS, 0.0, 0.0), _vec_tol(), "body is moving before the rebase")
	var frames_before: int = Engine.get_physics_frames()

	world.rebase(offset)

	# Immediately: everything shifted by -offset locally, nothing changed in universe terms.
	assert_almost_eq(body.global_position - marker.global_position, rel_before, _vec_tol(), "relative position")
	assert_almost_eq(world.to_universe(body.global_position).x, body_u_before.x, TOL_M, "body universe x")
	assert_almost_eq(world.to_universe(marker.global_position).x, marker_u_before.x, TOL_M, "marker universe x")
	assert_almost_eq(world.origin.x, offset.x, TOL_M, "origin advanced by the offset")
	assert_almost_eq(marker.global_position.x, -200.0 - offset.x, TOL_M, "marker moved by -offset")

	await get_tree().physics_frame
	await get_tree().physics_frame

	var steps: int = Engine.get_physics_frames() - frames_before
	var travelled: Vector3 = velocity_before * float(steps) / float(Engine.physics_ticks_per_second)
	assert_eq(steps, 2, "two physics frames passed")
	assert_almost_eq(body.linear_velocity, velocity_before, _vec_tol(), "velocity unchanged by rebase")
	assert_almost_eq(body.global_position - marker.global_position, rel_before + travelled, _vec_tol(),
			"relative position after two ticks")
	var body_u_after: UniversePos = world.to_universe(body.global_position)
	assert_almost_eq(body_u_after.x, body_u_before.x + travelled.x, TOL_M, "body universe x after two ticks")
	assert_almost_eq(body_u_after.y, body_u_before.y, TOL_M, "body universe y")
	assert_almost_eq(body_u_after.z, body_u_before.z, TOL_M, "body universe z")
	var marker_u_after: UniversePos = world.to_universe(marker.global_position)
	assert_almost_eq(marker_u_after.x, marker_u_before.x, TOL_M, "marker universe x after two ticks")
	assert_almost_eq(marker_u_after.y, marker_u_before.y, TOL_M, "marker universe y")
	assert_almost_eq(marker_u_after.z, marker_u_before.z, TOL_M, "marker universe z")


func test_rebase_at_one_au_keeps_universe_positions() -> void:
	world.origin = UniversePos.new(ONE_AU_M, -ONE_AU_M, 0.5 * ONE_AU_M)
	var body: RigidBody3D = _make_body()
	var start: UniversePos = world.origin.plus_local(Vector3(3000.0, -400.0, 250.0))
	world.spawn(body, start)
	body.linear_velocity = Vector3(0.0, 0.0, -SPEED_MPS)
	await get_tree().physics_frame
	var u_before: UniversePos = world.to_universe(body.global_position)
	var frames_before: int = Engine.get_physics_frames()

	world.rebase(Vector3(3000.0, -400.0, 250.0))
	assert_almost_eq(world.to_universe(body.global_position).distance_to(u_before), 0.0, TOL_M, "no jump")
	assert_almost_eq(body.global_position, world.universe_to_local(u_before), _vec_tol(), "local position follows")
	assert_lt(body.global_position.length(), 1.0, "body is at the new local origin")

	await get_tree().physics_frame
	await get_tree().physics_frame
	var steps: int = Engine.get_physics_frames() - frames_before
	var expected: UniversePos = u_before.plus_local(
			Vector3(0.0, 0.0, -SPEED_MPS) * float(steps) / float(Engine.physics_ticks_per_second))
	assert_almost_eq(world.to_universe(body.global_position).distance_to(expected), 0.0, TOL_M, "on trajectory")
	assert_almost_eq(body.linear_velocity, Vector3(0.0, 0.0, -SPEED_MPS), _vec_tol())


func test_rebase_emits_signal_and_accumulates_origin() -> void:
	watch_signals(world)
	world.rebase(Vector3(5000.0, 0.0, 0.0))
	world.rebase(Vector3(0.0, -250.0, 1000.0))
	assert_signal_emit_count(world, "rebased", 2)
	assert_signal_emitted_with_parameters(world, "rebased", [Vector3(5000.0, 0.0, 0.0)], 0)
	assert_signal_emitted_with_parameters(world, "rebased", [Vector3(0.0, -250.0, 1000.0)], 1)
	assert_eq(world.origin.x, 5000.0)
	assert_eq(world.origin.y, -250.0)
	assert_eq(world.origin.z, 1000.0)


func test_rebase_resets_physics_interpolation() -> void:
	# With project physics interpolation on, an unreset node would be drawn sliding across the whole offset.
	assert_true(ProjectSettings.get_setting("physics/common/physics_interpolation"), "interpolation is on")
	var marker := Node3D.new()
	world.spawn(marker, UniversePos.new(10.0, 0.0, 0.0))
	await get_tree().physics_frame
	await get_tree().process_frame
	world.rebase(Vector3(5000.0, 0.0, 0.0))
	await get_tree().process_frame
	var drawn: Vector3 = marker.get_global_transform_interpolated().origin
	assert_almost_eq(drawn, marker.global_position, _vec_tol(), "drawn where it is, not interpolated from 5 km away")


func test_spawn_places_node_and_registers_it() -> void:
	world.origin = UniversePos.new(ONE_AU_M, 0.0, 0.0)
	var node := Node3D.new()
	var basis: Basis = Basis(Vector3.UP, deg_to_rad(90.0))
	world.spawn(node, world.origin.plus_local(Vector3(12.5, -3.0, 4.0)), basis)
	assert_eq(node.get_parent(), world)
	assert_true(node.is_in_group(WorldFrame.SHIFTABLE_GROUP))
	assert_almost_eq(node.global_position, Vector3(12.5, -3.0, 4.0), _vec_tol())
	assert_almost_eq(node.global_transform.basis.x, basis.x, Vector3(1e-5, 1e-5, 1e-5), "orientation applied")
	assert_almost_eq(world.to_universe(node.global_position).x, ONE_AU_M + 12.5, TOL_M)


func test_universe_to_local_and_back_at_one_au() -> void:
	world.origin = UniversePos.new(ONE_AU_M, -ONE_AU_M, 0.5 * ONE_AU_M)
	var local := Vector3(1234.567, -89.01, 4.5)
	var u: UniversePos = world.to_universe(local)
	assert_almost_eq(world.universe_to_local(u), local, _vec_tol())
	var far := UniversePos.new(ONE_AU_M + 700.0, -ONE_AU_M, 0.5 * ONE_AU_M - 20.0)
	assert_almost_eq(world.universe_to_local(far), Vector3(700.0, 0.0, -20.0), _vec_tol())


func test_rebase_ignores_shiftable_nodes_outside_this_world() -> void:
	var stray := Node3D.new()
	stray.add_to_group(WorldFrame.SHIFTABLE_GROUP)
	add_child_autofree(stray)
	stray.global_position = Vector3(1.0, 2.0, 3.0)
	world.rebase(Vector3(5000.0, 0.0, 0.0))
	assert_eq(stray.global_position, Vector3(1.0, 2.0, 3.0))


func test_environment_accel_is_zero_in_m1() -> void:
	assert_eq(world.environment_accel(Vector3(123.0, -4.0, 9000.0)), Vector3.ZERO)


func test_frame_velocity_starts_at_zero() -> void:
	assert_eq(world.origin_velocity.size(), 3)
	for i: int in 3:
		assert_eq(world.origin_velocity[i], 0.0)
	assert_eq(world.origin.system_id, &"local")


func test_auto_rebase_is_off_by_default() -> void:
	assert_eq(world.auto_rebase_distance_m, 0.0)
	var focus := Node3D.new()
	world.spawn(focus, UniversePos.new(1e6, 0.0, 0.0))
	world.focus = focus
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_almost_eq(focus.global_position.x, 1e6, TOL_M, "nothing moved")
	assert_eq(world.origin.x, 0.0)


func test_auto_rebase_recentres_focus_when_enabled() -> void:
	world.auto_rebase_distance_m = 5000.0
	var focus := Node3D.new()
	world.spawn(focus, UniversePos.new(4000.0, 0.0, 0.0))
	world.focus = focus
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_almost_eq(focus.global_position.x, 4000.0, TOL_M, "inside the threshold: untouched")
	focus.global_position = Vector3(6000.0, 0.0, 0.0)
	# physics_frame fires before the nodes' _physics_process of that tick, so wait for one full tick.
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_almost_eq(focus.global_position.length(), 0.0, TOL_M, "focus re-centred")
	assert_almost_eq(world.origin.x, 6000.0, TOL_M)
	assert_almost_eq(world.to_universe(focus.global_position).x, 6000.0, TOL_M, "universe position preserved")
