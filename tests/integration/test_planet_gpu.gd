extends GutTest
## Epsilon III's picture, read back from the GPU (M6-T11, AC7): the limb is round (the shader finds the true sphere, not the
## coarse mesh's facets), the terminator is hard with the night side near black and no relief lit past it, the warm haze
## shows on the lit limb and not on the night one, and the maps' seams leave no line.
## Needs the real renderer: headless runs mark these pending. Run with a window:
## `.tools/godot/godot --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_planet_gpu.gd -gexit`

const PLANET: StringName = &"epsilon_iii"

var world: WorldFrame
var camera: Camera3D
var layer: ScaledSpace
var system: StarSystem
var _clock_backup: float


func before_each() -> void:
	_clock_backup = SimClock.now()
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
	camera.near = 0.05
	camera.far = 50000.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.add_child(camera)
	camera.current = true
	layer = ScaledSpace.new()
	layer.epoch_offset_s = 0.0
	add_child_autofree(layer)
	system = StarSystem.load_system(&"local")
	assert_true(world.anchor_on_rail(system, &"babylon5"))


func after_each() -> void:
	SimClock.reset(_clock_backup)


func _gpu() -> bool:
	if RenderingServer.get_rendering_device() == null:
		pending("needs the real renderer (no RenderingDevice headless)")
		return false
	return true


# The station `share` of its orbit on, the camera aimed `turn_deg` from the planet's centre toward the sun's side, the sun's
# side up on the screen (or `up`, when given). Returns the picture.
func _view(share: float, fov: float, turn_deg: float = 0.0, up: Vector3 = Vector3.ZERO) -> Image:
	SimClock.reset(system.period_s(&"babylon5") * share)
	camera.fov = fov
	layer.refresh(camera)
	var down: Vector3 = layer.placement_of(PLANET).direction
	var sunward: Vector3 = layer.sun_direction() - down * layer.sun_direction().dot(down)
	sunward = sunward.normalized() if sunward.length() > 1.0e-3 else Vector3.UP
	var turn: float = deg_to_rad(turn_deg)
	var look: Vector3 = down * cos(turn) + sunward * sin(turn)
	if up == Vector3.ZERO:
		# Away from the planet's centre across the picture: the sun's side up.
		up = sunward if absf(turn_deg) < 1.0 else (-down - look * look.dot(-down)).normalized()
	camera.global_basis = Basis.looking_at(look, up)
	return await _picture()


func _picture() -> Image:
	for i: int in 3:
		await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _luma(image: Image, x: int, y: int) -> float:
	var c: Color = image.get_pixel(x, y)
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func test_the_limb_is_round_not_faceted() -> void:
	if not _gpu():
		return
	# A 2 degree view of the lit limb from the station: the mesh's 64 facets would bend the edge by about 4 px here.
	# The surface's own edge: the haze's glow outside it is test_the_warm_haze_is_on_the_lit_limb_only's.
	layer.refresh(camera)
	layer.shell_of(PLANET).visible = false
	var image: Image = await _view(1.0 / 3.0, 2.0, 10.01)
	var placed: ScaledPlacement = layer.placement_of(PLANET)
	var size: Vector2i = image.get_size()
	var pixel_rad: float = deg_to_rad(camera.fov) / size.y
	var angles := PackedFloat64Array()
	# The left half only: GUT's own panel covers the right of the window.
	for x: int in range(20, size.x / 2, 8):
		# The edge from the sky (top) down into the disc: where the brightness first passes half the ground's.
		var ground: float = _luma(image, x, size.y - 5)
		var previous: float = _luma(image, x, 0)
		for y: int in range(1, size.y - 5):
			var here: float = _luma(image, x, y)
			if here >= ground * 0.5 and previous < ground * 0.5:
				var edge: float = y - 1 + (ground * 0.5 - previous) / maxf(here - previous, 1.0e-6)
				angles.append(_ray(Vector2(x + 0.5, edge + 0.5), size).angle_to(placed.direction))
				break
			previous = here
	assert_gt(angles.size(), 60, "the limb crosses the picture")
	var low: float = angles[0]
	var high: float = angles[0]
	var mean: float = 0.0
	for a: float in angles:
		low = minf(low, a)
		high = maxf(high, a)
		mean += a / angles.size()
	# The ground's colour along the limb moves the half-brightness edge by about a pixel; the mesh's facets bend it by five.
	assert_lt((high - low) / pixel_rad, 2.0, "the limb is a true circle to within the ground's own variation")
	assert_almost_eq((mean - placed.angular_radius_rad) / pixel_rad, 0.0, 2.0, "at the planet's true angular size")


func test_the_terminator_is_hard_and_the_night_side_black() -> void:
	if not _gpu():
		return
	# A quarter of the station's orbit on, the sun is 90 degrees from the planet: half the disc lit, the terminator across
	# the middle of the picture with the sun's side up.
	var image: Image = await _view(0.25, 32.0)
	var size: Vector2i = image.get_size()
	var radius_px: float = tan(layer.placement_of(PLANET).angular_radius_rad) / tan(deg_to_rad(camera.fov) / 2.0) * size.y / 2.0
	var mid: int = size.y / 2
	var day: float = 0.0
	var night: float = 0.0
	var night_max: float = 0.0
	var samples: int = 0
	for x: int in range(size.x / 2 - 40, size.x / 2 + 40, 2):
		day += _luma(image, x, mid - int(radius_px * 0.5))
		for y: int in range(mid + int(radius_px * 0.08), mid + int(radius_px * 0.9), 3):
			night_max = maxf(night_max, _luma(image, x, y))
		night += _luma(image, x, mid + int(radius_px * 0.5))
		samples += 1
	day /= samples
	night /= samples
	assert_gt(day, 0.3, "the lit half is bright")
	assert_lt(night, 0.03, "the night half is near black")
	assert_lt(night_max, 0.06, "and no relief catches light past the terminator")
	# The day side shows the relief: the brightness varies across a lit band.
	var lit := PackedFloat64Array()
	for x: int in range(size.x / 2 - 60, size.x / 2 + 60):
		lit.append(_luma(image, x, mid - int(radius_px * 0.3)))
	assert_gt(_spread(lit), 0.02, "the lit ground is not flat")


func test_the_warm_haze_is_on_the_lit_limb_only() -> void:
	if not _gpu():
		return
	# A third of the orbit on, three quarters lit: the sun's limb at the top of the picture, the night limb at the bottom.
	var image: Image = await _view(1.0 / 3.0, 32.0)
	var size: Vector2i = image.get_size()
	var radius_px: float = tan(layer.placement_of(PLANET).angular_radius_rad) / tan(deg_to_rad(camera.fov) / 2.0) * size.y / 2.0
	var x: int = size.x / 2
	var top: int = size.y / 2 - int(ceil(radius_px)) - 2
	var bottom: int = size.y / 2 + int(ceil(radius_px)) + 2
	var glow: Color = image.get_pixel(x, top)
	assert_gt(glow.r, 0.03, "a glow just outside the lit limb")
	assert_gt(glow.r, glow.b * 1.5, "and it is warm")
	assert_lt(glow.r, 0.5, "and faint")
	var dark: Color = image.get_pixel(x, bottom)
	assert_lt(dark.r + dark.g + dark.b, 0.02, "no ring round the night limb")


func test_the_maps_seams_leave_no_line() -> void:
	if not _gpu():
		return
	# Half an orbit on, full phase from the station: longitude 180 (where the angle wraps) runs down the middle of the disc.
	# Half a turn of the planet (and of its sun) brings longitude 0 (where the map's u wraps) there instead. Close in, where
	# the map is magnified, a seam that fell to the smallest mip level would be a line of one flat colour.
	# Aimed dead at the centre, the meridian would fall between the GPU's 2x2 pixel blocks and hide such a line, so the
	# planet is turned a little over half a pixel more.
	for turn: float in [0.0003, PI + 0.0003]:
		await _view(0.5, 4.0, 0.0, Vector3.UP)
		layer.set_process(false)
		var sphere: MeshInstance3D = layer.sphere_of(PLANET)
		var surface: ShaderMaterial = sphere.material_override as ShaderMaterial
		sphere.global_basis = sphere.global_basis * Basis(Vector3.UP, turn)
		surface.set_shader_parameter(&"sun_body", Basis(Vector3.UP, -turn) * (surface.get_shader_parameter(&"sun_body") as Vector3))
		var image: Image = await _picture()
		layer.set_process(true)
		var size: Vector2i = image.get_size()
		var centre: int = size.x / 2
		var seam: float = 0.0
		var elsewhere: float = 0.0
		var rows: int = 0
		for y: int in range(size.y / 2 - 150, size.y / 2 + 150):
			var line: float = 0.0
			for x: int in range(centre - 2, centre + 3):
				line = maxf(line, _kink(image, x, y))
			seam += line
			var control: float = 0.0
			for x: int in range(centre - 40, centre - 35):
				control = maxf(control, _kink(image, x, y))
			elsewhere += control
			rows += 1
		assert_lt(seam / rows, elsewhere / rows * 1.5 + 0.003, "no line down the seam (turned %s)" % turn)


# The view ray through a point of the picture, world axes (the camera's field of view is vertical).
func _ray(pixel: Vector2, size: Vector2i) -> Vector3:
	var half: float = tan(deg_to_rad(camera.fov) / 2.0)
	var x: float = (pixel.x / size.x * 2.0 - 1.0) * half * float(size.x) / size.y
	var y: float = (1.0 - pixel.y / size.y * 2.0) * half
	return (camera.global_basis * Vector3(x, y, -1.0)).normalized()


# How far a pixel stands out from its left and right neighbours.
func _kink(image: Image, x: int, y: int) -> float:
	return absf(_luma(image, x, y) - 0.5 * (_luma(image, x - 1, y) + _luma(image, x + 1, y)))


func _spread(values: PackedFloat64Array) -> float:
	var mean: float = 0.0
	for v: float in values:
		mean += v / values.size()
	var variance: float = 0.0
	for v: float in values:
		variance += (v - mean) * (v - mean) / values.size()
	return sqrt(variance)
