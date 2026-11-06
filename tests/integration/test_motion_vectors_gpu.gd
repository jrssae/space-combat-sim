extends GutTest
## M4-T38: the motion vectors TAA (and T40's FSR 2.2) reproject with, read back from the GPU by `VelocityProbeEffect`.
## A moving point writes the vector its movement implies; under TAA the sky carries the camera's turn (Godot leaves it at
## zero); a bolt new to its draw slot never writes a vector from another bolt or from the world origin (NaN at the camera).
## Needs the real renderer: headless runs have no RenderingDevice and mark these pending. Run with a window:
## `.tools/godot/godot --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_motion_vectors_gpu.gd -gexit`

const TOLERANCE_PX: float = 0.35

var probe: VelocityProbeEffect
var sky: SkyVelocityEffect
var camera: Camera3D
var ghost: Camera3D
var _aa_backup: StringName


func before_each() -> void:
	_aa_backup = AntiAliasingMode.read(get_viewport())
	probe = VelocityProbeEffect.new()
	sky = SkyVelocityEffect.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	var world := WorldEnvironment.new()
	world.environment = environment
	var compositor := Compositor.new()
	compositor.compositor_effects = [sky, probe]
	world.compositor = compositor
	add_child_autofree(world)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.far = 50000.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child_autofree(camera)
	camera.current = true
	# Holds the camera's previous pose, to project where things were last frame.
	ghost = Camera3D.new()
	ghost.fov = 75.0
	ghost.far = 50000.0
	add_child_autofree(ghost)


func after_each() -> void:
	AntiAliasingMode.apply(get_viewport(), _aa_backup)


func _gpu() -> bool:
	if RenderingServer.get_rendering_device() == null:
		pending("needs the real renderer (no RenderingDevice headless)")
		return false
	return true


func _size() -> Vector2:
	return Vector2(probe.buffer_size()) if probe.buffer_size() != Vector2i.ZERO else get_viewport().get_visible_rect().size


# Draws one frame with the probe reading `points` (viewport pixels) and returns what it read, in pixels.
func _frame(points: PackedVector2Array) -> Array[Vector2]:
	probe.set_points(points)
	await RenderingServer.frame_post_draw
	var scale: Vector2 = Vector2(probe.buffer_size()) / get_viewport().get_visible_rect().size
	var out: Array[Vector2] = []
	for s: Vector4 in probe.samples():
		out.append(Vector2(s.x, s.y) * Vector2(probe.buffer_size()))
	assert_eq(scale, Vector2.ONE, "the 3D renders at the window's size here")
	return out


func _settle(frames: int) -> void:
	for i: int in frames:
		await RenderingServer.frame_post_draw


func test_a_moving_point_writes_the_vector_its_movement_implies() -> void:
	if not _gpu():
		return
	AntiAliasingMode.apply(get_viewport(), &"taa")
	sky.enabled = true
	var point := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.4
	mesh.height = 0.8
	point.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	point.material_override = material
	point.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # moved per frame here, not per tick
	add_child_autofree(point)
	point.position = Vector3(-4, 1, -30)
	await _settle(4)
	var step := Vector3(0.35, -0.12, 0.0)
	for f: int in 6:
		var before: Vector2 = camera.unproject_position(point.position)
		point.position += step
		var now: Vector2 = camera.unproject_position(point.position)
		var read: Array[Vector2] = await _frame(PackedVector2Array([now]))
		var expected: Vector2 = before - now  # where it was minus where it is (Godot's convention)
		assert_lt(read[0].distance_to(expected), TOLERANCE_PX, "frame %d: read %s, moved %s" % [f, read[0], expected])


# A canary pinned to Godot 4.7.2: if an upgrade starts writing the sky's motion, this fails and the sky pass may go.
func test_without_the_sky_pass_godot_leaves_the_sky_at_zero() -> void:
	if not _gpu():
		return
	AntiAliasingMode.apply(get_viewport(), &"taa")
	sky.enabled = false
	await _settle(3)
	camera.rotate_y(0.01)
	await _settle(1)
	camera.rotate_y(0.01)
	var read: Array[Vector2] = await _frame(PackedVector2Array([Vector2(100, 100)]))
	assert_eq(read[0], Vector2.ZERO, "why the sky pass exists")


func test_under_taa_the_sky_carries_the_cameras_turn() -> void:
	if not _gpu():
		return
	AntiAliasingMode.apply(get_viewport(), &"taa")
	sky.enabled = true
	await _settle(3)
	var size: Vector2 = get_viewport().get_visible_rect().size
	var points := PackedVector2Array([Vector2(40, 40), size * 0.5, size - Vector2(60, 30), Vector2(size.x * 0.8, size.y * 0.2)])
	for f: int in 5:
		ghost.global_transform = camera.global_transform
		camera.rotate_y(0.012)
		camera.rotate_object_local(Vector3.RIGHT, -0.005)
		var read: Array[Vector2] = await _frame(points)
		for i: int in points.size():
			var direction: Vector3 = camera.project_ray_normal(points[i])
			var before: Vector2 = ghost.unproject_position(camera.global_position + direction * 1.0e5)
			var expected: Vector2 = before - points[i]
			assert_lt(read[i].distance_to(expected), TOLERANCE_PX,
					"frame %d point %s: read %s, turn %s" % [f, points[i], read[i], expected])


func test_a_static_camera_gives_the_sky_no_jitter() -> void:
	if not _gpu():
		return
	AntiAliasingMode.apply(get_viewport(), &"taa")
	sky.enabled = true
	await _settle(4)
	for f: int in 4:
		var read: Array[Vector2] = await _frame(PackedVector2Array([Vector2(50, 60), Vector2(300, 200)]))
		for v: Vector2 in read:
			assert_lt(v.length(), 0.01, "TAA's jitter is not motion")


func test_a_bolt_new_to_its_slot_writes_no_vector_from_elsewhere() -> void:
	if not _gpu():
		return
	AntiAliasingMode.apply(get_viewport(), &"taa")
	sky.enabled = true
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.6, 0.6, 2.0)
	multimesh.mesh = mesh
	multimesh.instance_count = 2
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.custom_aabb = AABB(Vector3.ONE * -1.0e4, Vector3.ONE * 2.0e4)
	instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child_autofree(instance)
	var quarantine := BoltSlotQuarantine.new(Vector3(0, 0, -1))
	var basis := Basis.looking_at(Vector3.RIGHT)  # flies along +X, its -Z
	var step := 0.4
	var empty := PackedFloat32Array()
	empty.resize(24)
	RenderingServer.multimesh_set_buffer(multimesh.get_rid(), quarantine.filter(0, empty))
	await _settle(3)
	# Slot 0 holds bolt A for three frames; then A is freed and B, elsewhere, takes the slot between two frames.
	for f: int in 8:
		var origin := Vector3(-3.0 + step * f, 0.0, -25.0) if f < 3 else Vector3(-8.0 + step * f, -2.0, -25.0)
		var buffer := empty.duplicate()
		var rows: Array[Vector3] = [Vector3(basis.x.x, basis.y.x, basis.z.x), Vector3(basis.x.y, basis.y.y, basis.z.y),
				Vector3(basis.x.z, basis.y.z, basis.z.z)]
		for r: int in 3:
			buffer[r * 4] = rows[r].x
			buffer[r * 4 + 1] = rows[r].y
			buffer[r * 4 + 2] = rows[r].z
		buffer[3] = origin.x
		buffer[7] = origin.y
		buffer[11] = origin.z
		RenderingServer.multimesh_set_buffer(multimesh.get_rid(), quarantine.filter(0, buffer))
		var before: Vector2 = camera.unproject_position(origin - Vector3(step, 0, 0))
		var now: Vector2 = camera.unproject_position(origin)
		var read: Array[Vector2] = await _frame(PackedVector2Array([now, now + Vector2(6, 0), now - Vector2(6, 0)]))
		for v: Vector2 in read:
			assert_false(is_nan(v.x) or is_nan(v.y), "frame %d: no NaN" % f)
			# A collapsed frame draws nothing (the sky's zero); a drawn one moves by at most its step plus half its length.
			assert_lt(v.length(), (before - now).length() * 4.0 + 1.0, "frame %d: %s is not a jump from elsewhere" % [f, v])
