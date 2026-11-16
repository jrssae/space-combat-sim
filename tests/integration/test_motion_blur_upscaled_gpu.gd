extends GutTest
## M7-T46: the motion blur under FSR 2.2, read back from the GPU. Under FSR 2.2 Godot writes motion vectors only for what moved
## and marks everything still (-1, -1) for the upscaler to work out from depth; the blur took that mark for a real vector and
## smeared every still hull across the screen ("FSR2 is showing very very blurry results"). A still box must stay sharp, and with
## the camera sliding past it the box must blur as it does without FSR 2.2.
## Needs the real renderer: headless runs have no RenderingDevice and mark these pending. Run with a window:
## `.tools/godot/godot --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_motion_blur_upscaled_gpu.gd -gexit`

## A pixel this bright (0 to 1, the brightest channel) is part of the box or its smear; black space reads 0.
const LIT: float = 0.06
## How far the camera slides each frame, metres, with the box 30 m ahead (about 1.7 % of the window's width).
const SLIDE_M: float = 0.8

var blur: MotionBlurEffect
var camera: Camera3D
var box: MeshInstance3D
var _backup: Dictionary = {}


func before_each() -> void:
	var root: Window = get_tree().root
	_backup = {"mode": root.scaling_3d_mode, "scale": root.scaling_3d_scale, "aa": AntiAliasingMode.read(root)}
	blur = MotionBlurEffect.new()
	blur.strength = 1.0
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	var world := WorldEnvironment.new()
	world.environment = environment
	var compositor := Compositor.new()
	compositor.compositor_effects = [blur]
	world.compositor = compositor
	add_child_autofree(world)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.far = 50000.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # moved per frame here, not per tick
	add_child_autofree(camera)
	camera.current = true
	box = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(4, 4, 4)
	box.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material_override = material
	box.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	box.position = Vector3(-9, 0, -30)  # the left of the window: GUT's panel covers its right
	add_child_autofree(box)
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


static func _lit(image: Image, at: Vector2i) -> float:
	var c: Color = image.get_pixelv(at)
	return maxf(c.r, maxf(c.g, c.b))


# The box's front face on screen, in window pixels.
func _box_rect() -> Rect2:
	var near: float = box.position.z + 2.0
	var top_left: Vector2 = camera.unproject_position(Vector3(box.position.x - 2.0, box.position.y + 2.0, near))
	var bottom_right: Vector2 = camera.unproject_position(Vector3(box.position.x + 2.0, box.position.y - 2.0, near))
	return Rect2(top_left, bottom_right - top_left)


# How bright the box is just inside each edge (from 3 to 18 px in), found along its middle row and column from `centre`: the blur
# drags the black around the box over its rim, so a smeared edge reads dark. Keys left, right, top, bottom.
static func _rims(image: Image, centre: Vector2i) -> Dictionary:
	var out: Dictionary = {}
	var bounds := Rect2i(Vector2i.ZERO, image.get_size())
	for side: Array in [["left", Vector2i(-1, 0)], ["right", Vector2i(1, 0)], ["top", Vector2i(0, -1)], ["bottom", Vector2i(0, 1)]]:
		var step: Vector2i = side[1]
		var edge: Vector2i = centre
		while bounds.has_point(edge + step) and _lit(image, edge + step) > LIT:
			edge += step
		var sum: float = 0.0
		for d: int in range(3, 19):
			sum += _lit(image, edge - step * d)
		out[side[0]] = sum / 16.0
	return out


# Slides the camera sideways past the box for a few frames and returns the box's rims (`_rims`) in the last frame.
func _slide_rims(mode: Viewport.Scaling3DMode, scale: float) -> Dictionary:
	_upscale(mode, scale)
	camera.position = Vector3.ZERO
	await _settle(20)
	for f: int in 8:
		camera.position.x += SLIDE_M
		await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	return _rims(image, Vector2i(_box_rect().get_center().round()))


func test_under_fsr2_the_blur_leaves_a_still_box_sharp() -> void:
	if not _gpu():
		return
	_upscale(Viewport.SCALING_3D_MODE_FSR2, 0.5)
	await _settle(30)
	var image: Image = get_viewport().get_texture().get_image()
	var centre := Vector2i(_box_rect().get_center().round())
	assert_gt(_lit(image, centre), 0.9, "the box is drawn where it is")
	# The mark taken for a vector smeared every still pixel diagonally by up to 6 % of the picture's height.
	var rims: Dictionary = _rims(image, centre)
	for side: String in rims:
		assert_gt(rims[side], 0.9, "the still box's %s rim is not smeared (%.3f bright)" % [side, rims[side]])


func test_under_fsr2_a_still_box_blurs_with_the_camera_as_it_does_without() -> void:
	if not _gpu():
		return
	var native: Dictionary = await _slide_rims(Viewport.SCALING_3D_MODE_BILINEAR, 1.0)
	var fsr2: Dictionary = await _slide_rims(Viewport.SCALING_3D_MODE_FSR2, 0.5)
	assert_lt(minf(native["left"], native["right"]), 0.98, "without FSR 2.2 the slide blurs the box's sides (%s)" % native)
	for side: String in native:
		assert_almost_eq(fsr2[side], native[side], 0.06, "under FSR 2.2 the %s rim blurs as without (%.3f against %.3f)" % [
				side, fsr2[side], native[side]])
