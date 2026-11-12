extends GutTest
## The scaled-space layer's picture, read back from the GPU (M6-T10, D68, AC7): the planet's disc is as wide on screen as its
## angular size says, the near world draws over it out to the far plane, and it hides the sky behind it.
## Needs the real renderer: headless runs mark these pending. Run with a window:
## `.tools/godot/godot --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_scaled_space_gpu.gd -gexit`

const FOV_DEG: float = 60.0
const PLANET: StringName = &"epsilon_iii"
const MARKER := Color(0.0, 1.0, 0.0)

var world: WorldFrame
var camera: Camera3D
var layer: ScaledSpace
var _clock_backup: float


func before_each() -> void:
	_clock_backup = SimClock.now()
	# A third of the station's orbit on: the planet is 120 degrees from the sun, three quarters of its disc lit.
	SimClock.reset(23_300.0)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	var sky := WorldEnvironment.new()
	sky.environment = environment
	add_child_autofree(sky)
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
	layer = ScaledSpace.new()
	layer.epoch_offset_s = 0.0
	add_child_autofree(layer)
	assert_true(world.anchor_on_rail(StarSystem.load_system(&"local"), &"babylon5"))


func after_each() -> void:
	SimClock.reset(_clock_backup)


func _gpu() -> bool:
	if RenderingServer.get_rendering_device() == null:
		pending("needs the real renderer (no RenderingDevice headless)")
		return false
	return true


# Turns the camera to the planet's centre and returns the picture after the layer has drawn.
func _look_at_planet() -> Image:
	layer.refresh(camera)
	camera.global_basis = Basis.looking_at(layer.placement_of(PLANET).direction, Vector3.UP)
	return await _picture()


func _picture() -> Image:
	for i: int in 3:
		await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


# A flat green square `size` across, `distance` in front of the camera, unlit: the near world's marker.
func _marker(distance: float, size: float) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = MARKER
	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	mesh.material_override = material
	world.add_child(mesh)
	mesh.global_transform = Transform3D(camera.global_basis, camera.global_position - camera.global_basis.z * distance)
	return mesh


func _lit(pixel: Color) -> bool:
	return pixel.r + pixel.g + pixel.b > 0.02


func test_the_planets_disc_is_as_wide_as_its_angular_size() -> void:
	if not _gpu():
		return
	var image: Image = await _look_at_planet()
	var size: Vector2i = image.get_size()
	var placed: ScaledPlacement = layer.placement_of(PLANET)
	# A sphere on the view's axis draws as a circle of tan(angular radius) over tan(half the field of view).
	var expected_px: float = tan(placed.angular_radius_rad) / tan(deg_to_rad(FOV_DEG) / 2.0) * size.y
	var tall: int = 0
	for y: int in size.y:
		tall += 1 if _lit(image.get_pixel(size.x / 2, y)) else 0
	assert_almost_eq(float(tall), expected_px, 3.0, "the disc's height in pixels (the lit side reaches both poles)")
	assert_true(_lit(image.get_pixel(size.x / 2, size.y / 2)), "the planet is at the centre of the picture")
	assert_false(_lit(image.get_pixel(size.x / 2, 2)), "and the sky above it is dark")


func test_the_near_world_draws_over_the_planet_out_to_the_far_plane() -> void:
	if not _gpu():
		return
	await _look_at_planet()
	for distance: float in [10.0, 5000.0, 30000.0, 49000.0]:
		var marker: MeshInstance3D = _marker(distance, distance * 0.05)
		var image: Image = await _picture()
		var centre: Color = image.get_pixel(image.get_width() / 2, image.get_height() / 2)
		assert_gt(centre.g, 0.9, "a thing %s m away is in front of the planet" % distance)
		assert_lt(centre.r, 0.1, "and nothing of the planet shows through it at %s m" % distance)
		marker.queue_free()


func test_the_planet_hides_the_star_behind_it() -> void:
	if not _gpu():
		return
	# At the data's epoch 0 the star is straight behind the planet: its bright disc must not show through.
	SimClock.reset(0.0)
	var image: Image = await _look_at_planet()
	var centre: Color = image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	assert_lt(centre.r, 0.2, "the night side, not the star's disc")
	assert_eq(layer.key_light(), 0.0)
	# With the planet's stand-in gone the star is there (the layer would show it again on its next frame).
	layer.set_process(false)
	layer.sphere_of(PLANET).visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	image = get_viewport().get_texture().get_image()
	centre = image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	assert_gt(centre.r, 0.8, "the star's disc at the centre")
