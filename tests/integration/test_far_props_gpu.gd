extends GutTest
## Far props' pictures, read back from the GPU (M6-T15, D70, AC9): the near and shrunk gate and station draw the same pixels
## either side of the pull distance; the mesh covers the area its silhouette table says; the dot carries the mesh's light
## (the sum of its pixels) at the hand-off within a factor of two, from the sun's side and from the side away from it, and draws
## exactly its shader's law.
## Needs the real renderer: headless runs mark these pending. Run with a window:
## `.tools/godot/godot --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_far_props_gpu.gd -gexit`

const FOV_DEG: float = 50.0
## Linear light under which a pixel counts as sky.
const SKY: float = 0.0015
const BEARING: Vector3 = Vector3(-0.35, 0.25, -1.0)

var world: WorldFrame
var camera: Camera3D
var key: DirectionalLight3D
# The pictures are taken in a viewport of their own, sharing the scene's world: the test runner draws its panel over the window.
var view: SubViewport
# Half the side of the square read round the picture's centre, pixels: set by `_picture` from the prop's size on screen.
var _crop_px: float = 4096.0


func before_each() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.1  # the game's ambient_level
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR  # so the read-back pixels add up as light
	var sky := WorldEnvironment.new()
	sky.environment = environment
	add_child_autofree(sky)
	var rig := LightRig.new()
	key = DirectionalLight3D.new()
	key.name = "KeyStar"
	key.light_energy = 1.5
	key.light_color = Color(1.0, 0.94, 0.84)
	rig.add_child(key)
	add_child_autofree(rig)
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	view = SubViewport.new()
	view.size = Vector2i(1200, 675)
	view.world_3d = get_viewport().find_world_3d()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.use_hdr_2d = true  # linear floats to add up
	add_child_autofree(view)
	camera = Camera3D.new()
	camera.fov = FOV_DEG
	camera.near = 0.05
	camera.far = 50000.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.add_child(camera)
	camera.current = true


func _gpu() -> bool:
	if RenderingServer.get_rendering_device() == null:
		pending("needs the real renderer (no RenderingDevice headless)")
		return false
	return true


func _gate() -> Jumpgate:
	var gate: Jumpgate = Jumpgate.create("JUMPGATE")
	world.add_child(gate)
	gate.far_prop.set_process(false)
	return gate


# The sun shines along -`toward_sun` (prop frame) onto the prop.
func _sun_from(prop: Node3D, toward_sun: Vector3) -> void:
	key.global_transform = Transform3D(SpaceEnvironment.key_basis((prop.global_basis * toward_sun).normalized()), Vector3.ZERO)


# The camera `distance_m` from the prop's centre along `bearing` (prop frame), nudged sideways by `jitter_m`, looking at the
# centre; the far prop placed for it at the cross-fade `fade` (or by the distance when below 0), then the picture.
func _picture(far: FarProp, prop: Node3D, distance_m: float, fade: float, bearing: Vector3 = BEARING,
		jitter_m: Vector3 = Vector3.ZERO) -> Image:
	var centre: Vector3 = prop.global_transform * far.math.centre
	var eye: Vector3 = centre + prop.global_basis * bearing.normalized() * distance_m + jitter_m
	camera.global_transform = Transform3D(Basis.looking_at(centre - eye, Vector3.UP), eye)
	camera.reset_physics_interpolation()
	prop.reset_physics_interpolation()
	await get_tree().physics_frame  # the drawn poses settle on the new view
	far.held_fade = fade
	far.update(camera, 1.0)
	_crop_px = far.math.bounding_px(distance_m, FarProp.k_of(camera)) * 1.3 + 12.0
	for i: int in 3:
		await RenderingServer.frame_post_draw
	return view.get_texture().get_image()


# The light in the picture: every pixel's linear value summed (the viewport keeps linear floats), and how many are not sky.
func _measure(image: Image) -> Vector2:
	# Only round the prop, which the camera centres: the rest is sky, and reading it is slow.
	var half: int = mini(int(_crop_px), maxi(image.get_width(), image.get_height()))
	var centre := Vector2i(image.get_width() / 2, image.get_height() / 2)
	var box := Rect2i(centre - Vector2i(half, half), Vector2i(2 * half, 2 * half)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	image = image.get_region(box)
	image.convert(Image.FORMAT_RGBF)
	var values: PackedFloat32Array = image.get_data().to_float32_array()
	var flux: float = 0.0
	var covered: int = 0
	for i: int in range(0, values.size(), 3):
		var v: float = (values[i] + values[i + 1] + values[i + 2]) / 3.0
		if v > 0.0:
			flux += v
			covered += 1 if v > SKY else 0
	return Vector2(flux, covered)


func test_near_and_shrunk_draw_the_same_picture_either_side_of_the_pull() -> void:
	if not _gpu():
		return
	camera.fov = 4.0  # a long lens: hundreds of pixels to compare
	for which: int in 2:
		var prop: Node3D = _gate() if which == 0 else _station()
		var far: FarProp = FarProp.of(prop)
		_sun_from(prop, Vector3(-0.6, 0.5, -0.6))
		var pull: float = far.math.pull_m(camera.far)
		var inside: Vector2 = _measure(await _picture(far, prop, pull * 0.9999, 0.0))
		assert_eq(far.path(), &"near")
		var outside: Vector2 = _measure(await _picture(far, prop, pull * 1.0001, 0.0))
		assert_eq(far.path(), &"shrunk")
		assert_gt(inside.y, 200.0, "%s fills part of the picture" % far.display_name)
		assert_almost_eq(outside.y / inside.y, 1.0, 0.02, "%s: the same pixels covered (%d against %d)" % [far.display_name,
				outside.y, inside.y])
		assert_almost_eq(outside.x / inside.x, 1.0, 0.02, "%s: the same light" % far.display_name)
		prop.free()


func _station() -> StationStandin:
	var station := StationStandin.new()
	assert_true(station.build(), "the station's asset is built")
	FarPropHost.dress_station(station)
	world.add_child(station)
	FarProp.of(station).set_process(false)
	return station


func test_the_mesh_covers_what_its_silhouette_table_says() -> void:
	if not _gpu():
		return
	var gate: Jumpgate = _gate()
	var far: FarProp = gate.far_prop
	gate.activation_glows.hide()  # the lamps' glows spread past the outline; the table is the mesh's
	_sun_from(gate, Vector3(-0.6, 0.5, -0.6))
	# About 60 px of bounding radius through a long lens: big enough to count, far enough to be all but orthographic.
	camera.fov = 4.0
	var k: float = FarProp.k_of(camera)
	var d: float = far.math.radius_m * k / 60.0
	for bearing: Vector3 in [BEARING, Vector3(1.0, 0.2, 0.1), Vector3(0.1, 0.15, -1.0), Vector3(0.0, 1.0, 0.3)]:
		var seen: Vector2 = _measure(await _picture(far, gate, d, 0.0, bearing))
		var model: float = FarPropMath.mesh_cover_px2(far.math.area_toward(bearing), d, k)
		assert_almost_eq(seen.y / model, 1.0, 0.35, "from %s: %d pixels against the table's %.0f" % [bearing, seen.y, model])
		# The dot at the same size carries its paint over the same area (its shader's law).
		var dot: Vector2 = _measure(await _picture(far, gate, d, 1.0, bearing))
		var paint: Color = far.dot_paint()
		var expected: float = (paint.r + paint.g + paint.b) / 3.0 * model
		gut.p("from %s: mesh %d px flux %.3f, dot flux %.3f against %.3f (paint %s)" % [bearing, seen.y, seen.x, dot.x, expected, paint])
		assert_almost_eq(dot.x / expected, 1.0, 0.02, "the dot's light is its paint over the table's area")


func test_the_dot_carries_the_meshs_light_at_the_hand_off() -> void:
	if not _gpu():
		return
	var gate: Jumpgate = _gate()
	var far: FarProp = gate.far_prop
	var k: float = FarProp.k_of(camera)
	var d: float = far.math.dot_distance_m(k)
	# The sun behind the eye's shoulder, then off to the side; each the mean over a few sub-pixel shifts of the view.
	for toward_sun: Vector3 in [BEARING + Vector3(0.3, 0.3, 0.0), Vector3(1.0, 0.4, 0.4)]:
		_sun_from(gate, toward_sun)
		var mesh_flux: float = 0.0
		var dot_flux: float = 0.0
		for j: int in 4:
			var jitter := Vector3(cos(j * 1.1), sin(j * 1.7), 0.0) * d / k * 0.5  # half a pixel
			mesh_flux += _measure(await _picture(far, gate, d, 0.0, BEARING, jitter)).x
			dot_flux += _measure(await _picture(far, gate, d, 1.0, BEARING, jitter)).x
		gut.p("sun toward %s: mesh %.4f dot %.4f ratio %.3f paint %s radius %.1f m k %.1f d %.0f" % [toward_sun, mesh_flux, dot_flux,
				dot_flux / mesh_flux, far.dot_paint(), float(far.dot.material_override.get_shader_parameter(&"radius_m")), k, d])
		assert_gt(mesh_flux, 0.0, "the mesh shows at the hand-off")
		# A truss hull's light depends on the view more than one law can follow (its sheen, its lamps, which rails hit pixels):
		# within a factor of two, which the 0.35 s cross-fade turns into a gentle change.
		assert_between(dot_flux / mesh_flux, 0.5, 2.0, "the dot about as bright as the mesh it replaces (sun toward %s)" % toward_sun)
