extends GutTest
## M4-T40: what the upscalers do to the picture, read back from the GPU. Under FSR 2.2 a moving point writes its motion at the
## internal resolution and leaves no trail beyond it; the sky carries the camera's turn there too; a one-pixel HUD line stays
## one window pixel wide with the 3D at a third. Reuses T38's probe scene (`test_motion_vectors_gpu`).
## Needs the real renderer: headless runs have no RenderingDevice and mark these pending. Run with a window:
## `.tools/godot/godot --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_upscaling_gpu.gd -gexit`

const TOLERANCE_PX: float = 0.35
## A pixel this bright (0 to 1, the brightest channel) is part of the point or its trail; black space reads 0.
const LIT: float = 0.06

var probe: VelocityProbeEffect
var sky: SkyVelocityEffect
var camera: Camera3D
var ghost: Camera3D
var _backup: Dictionary = {}


func before_each() -> void:
	var root: Window = get_tree().root
	_backup = {"mode": root.scaling_3d_mode, "scale": root.scaling_3d_scale, "aa": AntiAliasingMode.read(root)}
	probe = VelocityProbeEffect.new()
	sky = SkyVelocityEffect.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
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
	ghost = Camera3D.new()
	ghost.fov = 75.0
	ghost.far = 50000.0
	add_child_autofree(ghost)
	AntiAliasingMode.apply(root, AntiAliasingMode.OFF)


func after_each() -> void:
	var root: Window = get_tree().root
	root.scaling_3d_mode = _backup["mode"]
	root.scaling_3d_scale = _backup["scale"]
	AntiAliasingMode.apply(root, _backup["aa"])


func _gpu() -> bool:
	if RenderingServer.get_rendering_device() == null:
		pending("needs the real renderer (no RenderingDevice headless)")
		return false
	return true


func _upscale(mode: Viewport.Scaling3DMode, scale: float) -> void:
	var root: Window = get_tree().root
	root.scaling_3d_mode = mode
	root.scaling_3d_scale = scale


func _settle(frames: int) -> void:
	for i: int in frames:
		await RenderingServer.frame_post_draw


func _point(radius: float) -> MeshInstance3D:
	var point := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	point.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	point.material_override = material
	point.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # moved per frame here, not per tick
	add_child_autofree(point)
	return point


static func _lit(image: Image, at: Vector2i) -> float:
	var c: Color = image.get_pixelv(at)
	return maxf(c.r, maxf(c.g, c.b))


func test_under_fsr2_a_moving_point_writes_its_motion_at_the_internal_size() -> void:
	if not _gpu():
		return
	_upscale(Viewport.SCALING_3D_MODE_FSR2, 0.5)
	sky.enabled = true
	var point: MeshInstance3D = _point(0.4)
	point.position = Vector3(-4, 1, -30)
	await _settle(6)
	var window: Vector2 = get_viewport().get_visible_rect().size
	var step := Vector3(0.35, -0.12, 0.0)
	for f: int in 6:
		var before: Vector2 = camera.unproject_position(point.position)
		point.position += step
		var now: Vector2 = camera.unproject_position(point.position)
		var internal: Vector2 = Vector2(probe.buffer_size()) if probe.buffer_size() != Vector2i.ZERO else window * 0.5
		probe.set_points(PackedVector2Array([now * internal / window]))
		await RenderingServer.frame_post_draw
		var size := Vector2(probe.buffer_size())
		assert_almost_eq(size.y, roundf(window.y * 0.5), 1.0, "the 3D renders at half the lines")
		var s: Vector4 = probe.samples()[0]
		var read := Vector2(s.x, s.y) * size
		var expected: Vector2 = (before - now) * size / window
		assert_lt(read.distance_to(expected), TOLERANCE_PX, "frame %d: read %s, moved %s (internal px)" % [f, read, expected])


func test_under_fsr2_the_sky_carries_the_cameras_turn() -> void:
	if not _gpu():
		return
	_upscale(Viewport.SCALING_3D_MODE_FSR2, 1.0 / 1.5)
	sky.enabled = true
	await _settle(4)
	var window: Vector2 = get_viewport().get_visible_rect().size
	var points := PackedVector2Array([Vector2(40, 40), window * 0.5, window - Vector2(60, 30)])
	for f: int in 4:
		ghost.global_transform = camera.global_transform
		camera.rotate_y(0.012)
		var internal: Vector2 = Vector2(probe.buffer_size()) if probe.buffer_size() != Vector2i.ZERO else window / 1.5
		var scaled := PackedVector2Array()
		for p: Vector2 in points:
			scaled.append(p * internal / window)
		probe.set_points(scaled)
		await RenderingServer.frame_post_draw
		var size := Vector2(probe.buffer_size())
		var read: Array[Vector4] = probe.samples()
		for i: int in points.size():
			var direction: Vector3 = camera.project_ray_normal(points[i])
			var before: Vector2 = ghost.unproject_position(camera.global_position + direction * 1.0e5)
			var expected: Vector2 = (before - points[i]) * size / window
			var got := Vector2(read[i].x, read[i].y) * size
			# The probe reads the nearest internal pixel, up to half a pixel off the window point it stands for.
			assert_lt(got.distance_to(expected), TOLERANCE_PX + 0.1, "frame %d point %s: read %s, turn %s" % [f, points[i], got, expected])


# The point flies across black space; once it has passed, the pixels it crossed must be black again, except within its own
# size and one frame's motion behind it.
func test_fsr2_leaves_no_trail_behind_a_moving_point() -> void:
	if not _gpu():
		return
	_upscale(Viewport.SCALING_3D_MODE_FSR2, 0.5)
	sky.enabled = true
	var point: MeshInstance3D = _point(0.3)
	point.position = Vector3(-6, 0, -30)
	await _settle(8)
	var step := Vector3(0.25, 0.0, 0.0)
	for f: int in 30:
		point.position += step
		await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var window := Vector2(image.get_size())
	assert_eq(Vector2i(window), Vector2i(get_viewport().get_visible_rect().size), "the picture is at the window's size")
	var center: Vector2 = camera.unproject_position(point.position)
	var radius_px: float = camera.unproject_position(point.position + Vector3(0.3, 0, 0)).x - center.x
	var motion_px: float = camera.unproject_position(point.position).x - camera.unproject_position(point.position - step).x
	assert_gt(_lit(image, Vector2i(center)), 0.5, "the point is drawn where it is")
	var y: int = roundi(center.y)
	var trail_start: int = floori(center.x - radius_px - motion_px - 2.0)
	var start: int = roundi(camera.unproject_position(Vector3(-6, 0, -30)).x)
	var worst: float = 0.0
	var worst_x: int = -1
	for x: int in range(maxi(start, 0), trail_start):
		for dy: int in [-1, 0, 1]:
			var lit: float = _lit(image, Vector2i(x, y + dy))
			if lit > worst:
				worst = lit
				worst_x = x
	assert_lt(worst, LIT, "the path behind is black (brightest %.3f at x %d, the point at %.0f, radius %.1f px, step %.1f px)" %
			[worst, worst_x, center.x, radius_px, motion_px])


func test_a_one_pixel_hud_line_stays_one_window_pixel_wide() -> void:
	if not _gpu():
		return
	_upscale(Viewport.SCALING_3D_MODE_FSR2, 1.0 / 3.0)
	var layer := CanvasLayer.new()
	var line := ColorRect.new()
	line.color = Color.WHITE
	line.position = Vector2(101, 50)
	line.size = Vector2(1, 200)
	layer.add_child(line)
	add_child_autofree(layer)
	await _settle(4)
	var image: Image = get_viewport().get_texture().get_image()
	assert_eq(image.get_size(), Vector2i(get_viewport().get_visible_rect().size), "2D is drawn at the window's size")
	for y: int in [60, 150, 240]:
		assert_gt(_lit(image, Vector2i(101, y)), 0.95, "the line itself, row %d" % y)
		assert_lt(_lit(image, Vector2i(100, y)), LIT, "nothing left of it, row %d" % y)
		assert_lt(_lit(image, Vector2i(102, y)), LIT, "nothing right of it, row %d" % y)
