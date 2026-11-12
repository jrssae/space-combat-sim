extends GutTest
## The star's picture, read back from the GPU (M6-T12, AC7): the disc is as wide on screen as its angular size says, and the
## lens flare is there in the open and gone when the planet's shadow covers the disc.
## Needs the real renderer: headless runs mark these pending. Run with a window:
## `.tools/godot/godot --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_sun_gpu.gd -gexit`

const ENV_SCENE: String = "res://src/environment/space_environment.tscn"
const FOV_DEG: float = 60.0
const STAR: StringName = &"epsilon"

var world: WorldFrame
var camera: Camera3D
var env: SpaceEnvironment
var _clock_backup: float


func before_each() -> void:
	_clock_backup = SimClock.now()
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
	env = (load(ENV_SCENE) as PackedScene).instantiate() as SpaceEnvironment
	add_child_autofree(env)
	env.scaled_space.epoch_offset_s = 0.0
	assert_true(world.anchor_on_rail(StarSystem.load_system(&"local"), &"babylon5"))


func after_each() -> void:
	SimClock.reset(_clock_backup)


func _gpu() -> bool:
	if RenderingServer.get_rendering_device() == null:
		pending("needs the real renderer (no RenderingDevice headless)")
		return false
	return true


# Turns the camera to the star and returns the picture after the layer, the light and the flare have followed.
func _look_at_sun(time_s: float) -> Image:
	SimClock.reset(time_s)
	env.scaled_space.refresh(camera)
	camera.global_basis = Basis.looking_at(env.scaled_space.sun_direction(), Vector3.UP)
	for i: int in 6:
		await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func test_the_disc_is_as_wide_as_its_angular_size() -> void:
	if not _gpu():
		return
	Settings.set_value(&"lens_flare", false)
	# A third of the orbit on: the star is in the open, 120 degrees from the planet.
	SimClock.reset(23_300.0)
	env.scaled_space.refresh(camera)
	var material: ShaderMaterial = env.scaled_space.sphere_of(STAR).material_override as ShaderMaterial
	material.set_shader_parameter(&"corona_strength", 0.0)
	var image: Image = await _look_at_sun(23_300.0)
	var placed: ScaledPlacement = env.scaled_space.placement_of(STAR)
	var expected_px: float = tan(placed.angular_radius_rad) / tan(deg_to_rad(FOV_DEG) / 2.0) * image.get_height()
	var tall: int = 0
	for y: int in image.get_height():
		var pixel: Color = image.get_pixel(image.get_width() / 2, y)
		tall += 1 if pixel.r + pixel.g + pixel.b > 1.2 else 0
	assert_almost_eq(float(tall), expected_px, 3.0, "the disc's height in pixels")
	Settings.set_value(&"lens_flare", true)


func test_the_corona_reaches_beyond_the_disc_and_the_disc_has_the_stars_colour() -> void:
	if not _gpu():
		return
	Settings.set_value(&"lens_flare", false)
	var image: Image = await _look_at_sun(23_300.0)
	var half: int = image.get_height() / 2
	var placed: ScaledPlacement = env.scaled_space.placement_of(STAR)
	var disc_px: float = tan(placed.angular_radius_rad) / tan(deg_to_rad(FOV_DEG) / 2.0) * image.get_height()
	var beside: Color = image.get_pixel(image.get_width() / 2, half - int(disc_px * 3.0))
	assert_gt(beside.r + beside.g + beside.b, 0.03, "the corona glows three radii out")
	var near_limb: Color = image.get_pixel(image.get_width() / 2, half - int(disc_px * 0.9))
	assert_gt(near_limb.r, near_limb.b + 0.05, "an orange-white star: red above blue")
	Settings.set_value(&"lens_flare", true)


func test_the_flare_shows_in_the_open_and_is_gone_in_the_shadow() -> void:
	if not _gpu():
		return
	Settings.set_value(&"lens_flare", true)
	var open: Image = await _look_at_sun(23_300.0)
	var row: int = open.get_height() / 2
	var x: int = open.get_width() / 2 - 250
	var open_streak: Color = open.get_pixel(x, row)
	assert_eq(env.post_effects.flare_strength(), 1.0)
	assert_gt(open_streak.r + open_streak.g + open_streak.b, 0.05, "the glare's streak crosses the picture beside the star")
	# Station directly behind the planet from the star: the shadow's middle.
	var dark: Image = await _look_at_sun(0.0)
	assert_eq(env.post_effects.flare_strength(), 0.0)
	var dark_streak: Color = dark.get_pixel(x, row)
	assert_lt(dark_streak.r + dark_streak.g + dark_streak.b, 0.03, "no flare in the planet's shadow")
