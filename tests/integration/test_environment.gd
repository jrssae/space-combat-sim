extends GutTest
## SpaceEnvironment against the real scene, headless (architecture §3, §7.2, §17.19). There is no GPU here, so these tests cover
## wiring and values, not pixels. What the sky and the compositor look like is (H).
##
## `StarField` draws the stars as points and the nebula is a panorama on the environment's sky (M4-T30c).

const SCENE_PATH: String = "res://src/environment/space_environment.tscn"
const ENVIRONMENT_DEFAULT_PATH: String = "res://assets/environment/environment_default.tres"
const MANIFEST_PATH: String = "res://assets/generated/sky_default/manifest.json"
const STARS_PATH: String = "res://assets/generated/sky_default/sky_default_stars.f32"
const PANORAMA_PATH: String = "res://assets/generated/sky_default/sky_default_panorama.png"
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh, then scripts/run_tests.sh (it imports first)"

var env: SpaceEnvironment
var camera: Camera3D


func before_each() -> void:
	camera = Camera3D.new()
	add_child_autofree(camera)
	camera.current = true
	env = _instantiate()
	add_child_autofree(env)


func _instantiate() -> SpaceEnvironment:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	assert_not_null(packed, "scene loads")
	return packed.instantiate() as SpaceEnvironment


## The real manifest, parsed independently of SkyManifest so a parser bug cannot hide in both.
func _read_manifest() -> Dictionary:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


## One frame has run its `_process` once the second `process_frame` has fired (the signal fires before the nodes').
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _exec(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _collect(node: Node, out: Array) -> Array:
	out.append(node)
	for child: Node in node.get_children():
		_collect(child, out)
	return out


# --- structure ---------------------------------------------------------------------------------------------------


func test_scene_instantiates_with_every_part() -> void:
	assert_not_null(env, "root script is SpaceEnvironment")
	assert_true(env.world_environment is WorldEnvironment)
	assert_true(env.key_star is DirectionalLight3D)
	assert_true(env.star_field is StarField)
	assert_true(env.sky_follower is SkyFollower)
	assert_eq(env.sky_follower.sky, env.star_field, "the follower is wired to StarField (node_paths in the .tscn)")
	assert_true(env.star_field.top_level, "the sky ignores its parent's transform")
	assert_null(env.get_parent() as WorldFrame, "the environment is not under World: it is camera-relative")


# --- the star field ----------------------------------------------------------------------------------------------


func test_the_field_has_one_instance_per_star_in_the_file() -> void:
	var manifest: Dictionary = _read_manifest()
	assert_true(manifest.has("star_field"), "manifest has star_field (%s)" % GEN_ASSETS_HINT)
	if not manifest.has("star_field"):
		return
	var count: int = int(manifest["counts"]["stars"])
	assert_eq(env.star_field.star_count(), count)
	assert_eq(env.star_field.multimesh.instance_count, count)
	assert_eq(env.star_field.multimesh.visible_instance_count, -1, "every star drawn")
	# The records, read here without StarField's parser: direction, colour, brightness.
	var floats: PackedFloat32Array = FileAccess.get_file_as_bytes(STARS_PATH).to_float32_array()
	assert_eq(floats.size(), count * 7)
	for i: int in [0, 1, count / 2, count - 1]:
		var direction := Vector3(floats[i * 7], floats[i * 7 + 1], floats[i * 7 + 2])
		assert_almost_eq(direction.length(), 1.0, 1e-4, "star %d has a unit direction" % i)
		assert_almost_eq(env.star_field.direction_of(i), direction, Vector3.ONE * 1e-4, "star %d points where the file says" % i)
		var light: Color = env.star_field.light_of(i)
		assert_almost_eq(light.r, floats[i * 7 + 3] * floats[i * 7 + 6], 1e-3, "star %d: colour times brightness" % i)
		assert_almost_eq(light.b, floats[i * 7 + 5] * floats[i * 7 + 6], 1e-3)


func test_the_field_is_one_draw_of_unshaded_additive_points() -> void:
	var field: StarField = env.star_field
	assert_not_null(field.multimesh)
	assert_eq(field.multimesh.transform_format, MultiMesh.TRANSFORM_3D)
	assert_true(field.multimesh.use_custom_data, "each star's light is its custom data")
	assert_true(field.multimesh.mesh is QuadMesh)
	var material: ShaderMaterial = field.material_override as ShaderMaterial
	assert_not_null(material)
	assert_eq(material.shader.resource_path, StarField.SHADER_PATH)
	assert_eq(field.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_eq(field.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_OFF)
	var manifest: Dictionary = _read_manifest()
	if manifest.has("star_field"):
		assert_almost_eq(float(material.get_shader_parameter(&"radius_rad")), float(manifest["star_field"]["radius_mrad"]) * 0.001, 1e-9)
		assert_almost_eq(float(material.get_shader_parameter(&"min_radius_px")), float(manifest["star_field"]["floor_px"]), 1e-6)


func test_the_nebula_dims_the_stars_behind_it() -> void:
	# Q42: the star points sample the panorama's alpha (the gas's opacity) in each star's direction.
	var material: ShaderMaterial = env.star_field.material_override as ShaderMaterial
	if not env.has_panorama():
		assert_false(bool(material.get_shader_parameter(&"nebula_occludes")), "no panorama, nothing to dim the stars")
		return
	assert_eq(material.get_shader_parameter(&"nebula"), (env.world_environment.environment.sky.sky_material as PanoramaSkyMaterial).panorama)
	assert_true(bool(material.get_shader_parameter(&"nebula_occludes")))
	env.show_sky_part(&"nebula", false)
	assert_false(bool(material.get_shader_parameter(&"nebula_occludes")), "a hidden nebula hides no stars")
	env.show_sky_part(&"nebula", true)
	assert_true(bool(material.get_shader_parameter(&"nebula_occludes")))


func test_the_field_loads_without_the_generated_asset() -> void:
	var field := StarField.new()
	add_child_autofree(field)
	assert_false(field.load_file("res://assets/generated/sky_default/no_such_stars.f32", 100, 0.5, 1.0))
	assert_eq(field.star_count(), 0)
	assert_push_warning("no_such_stars.f32")


func test_a_short_star_file_is_refused() -> void:
	var path: String = "user://test_star_field_short.f32"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(PackedFloat32Array([0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 2.0]).to_byte_array())
	file.close()
	var field := StarField.new()
	add_child_autofree(field)
	assert_false(field.load_file(path, 2, 0.5, 1.0), "the file holds one record, the manifest says two")
	assert_eq(field.star_count(), 0)
	assert_push_warning("records")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- environment resource ----------------------------------------------------------------------------------------


func test_the_environment_shows_the_nebula_panorama_and_keeps_its_look() -> void:
	var e: Environment = env.world_environment.environment
	assert_not_null(e)
	assert_eq(e.resource_path, ENVIRONMENT_DEFAULT_PATH, "one environment from here on")
	assert_eq(e.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR)
	# Since M4-T30a the ambient is `settings.ambient_level` of white, applied at ready (the resource's own dim grey is overwritten).
	assert_eq(e.ambient_light_color, Color.WHITE)
	assert_almost_eq(e.ambient_light_energy, float(Settings.get_value(&"ambient_level")), 0.0001)
	assert_eq(e.reflected_light_source, Environment.REFLECTION_SOURCE_DISABLED, "hulls keep the look they had on the black sky")
	assert_eq(e.tonemap_mode, Environment.TONE_MAPPER_FILMIC)
	assert_true(e.glow_enabled)
	assert_almost_eq(e.glow_intensity, 0.4, 0.0001)
	assert_almost_eq(e.glow_hdr_threshold, 1.0, 0.0001)
	assert_false(e.fog_enabled)
	assert_false(e.ssao_enabled)
	assert_false(e.ssr_enabled)
	if not ResourceLoader.exists(PANORAMA_PATH):
		pending("sky_default_panorama.png not generated (%s)" % GEN_ASSETS_HINT)
		return
	assert_eq(e.background_mode, Environment.BG_SKY)
	assert_not_null(e.sky)
	assert_true(e.sky.sky_material is PanoramaSkyMaterial)
	var panorama: Texture2D = (e.sky.sky_material as PanoramaSkyMaterial).panorama
	assert_not_null(panorama)
	assert_eq(panorama.resource_path, PANORAMA_PATH)
	assert_eq(panorama.get_width(), 4096)
	assert_eq(panorama.get_height(), 2048)
	assert_true(env.has_panorama())


func test_the_environment_loads_with_no_generated_sky() -> void:
	var bare: SpaceEnvironment = _instantiate()
	bare.sky_dir = "res://assets/generated/no_such_sky"
	add_child_autofree(bare)
	assert_eq(bare.star_field.star_count(), 0, "no stars")
	assert_false(bare.has_panorama())
	var e: Environment = bare.world_environment.environment
	assert_eq(e.background_mode, Environment.BG_COLOR, "a black sky instead")
	assert_eq(e.background_color, Color.BLACK)
	assert_push_warning("gen_assets.sh")
	assert_false(bool((bare.star_field.material_override as ShaderMaterial).get_shader_parameter(&"nebula_occludes")))
	var result: ConsoleResult = _exec("sky nebula on")
	assert_true(result.ok)
	assert_string_contains("\n".join(result.lines), "missing", "the command says there is no nebula to show")
	var state: String = "\n".join(_exec("state sky").lines)
	assert_string_contains(state, "nebula_shown = false")
	# The shared resource is the real environment's too: give it its panorama back.
	env._load_sky()


# --- the compositor -----------------------------------------------------------------------------------------------


func test_compositor_holds_the_sky_vectors_the_blur_then_the_flare() -> void:
	var compositor: Compositor = env.world_environment.compositor
	assert_not_null(compositor)
	assert_eq(compositor.compositor_effects.size(), 3, "sky motion vectors (M4-T38), motion blur, lens flare (M3-T25)")
	assert_true(compositor.compositor_effects[0] is SkyVelocityEffect, "the sky's vectors are written before TAA reads them")
	assert_true(compositor.compositor_effects[1] is MotionBlurEffect, "the blur smears stars and hulls together")
	assert_true(compositor.compositor_effects[2] is LensFlareEffect, "the flare goes on last, so it is never smeared")


# --- key light ---------------------------------------------------------------------------------------------------


func test_key_star_is_a_warm_light_from_front_left_above() -> void:
	var light: DirectionalLight3D = env.key_star
	assert_almost_eq(light.light_energy, 1.5, 0.0001)
	assert_gt(light.light_color.r, light.light_color.b + 0.05, "warm: more red than blue")
	assert_true(light.visible)
	# A directional light shines along its local -Z, so +Z points at the light. The ship faces -Z, its left is -X.
	var to_light: Vector3 = light.global_transform.basis.z.normalized()
	assert_lt(to_light.z, -0.3, "from the front (-Z)")
	assert_lt(to_light.x, -0.2, "from the left (-X)")
	assert_gt(to_light.y, 0.3, "from above (+Y)")


# --- sky follower ------------------------------------------------------------------------------------------------


func test_follower_runs_late_in_both_loops() -> void:
	assert_gt(env.sky_follower.process_priority, 0, "after the camera rig's _process")
	assert_gt(env.sky_follower.process_physics_priority, 0, "after a rebase made in the physics tick")
	assert_true(env.sky_follower.is_processing())
	assert_true(env.sky_follower.is_physics_processing())


func test_the_field_sits_on_the_camera() -> void:
	for camera_position: Vector3 in [Vector3.ZERO, Vector3(1000.0, -250.0, 4000.0), Vector3(-18000.0, 9000.0, -500.0)]:
		camera.global_position = camera_position
		await _settle()
		assert_almost_eq(env.star_field.global_position, camera_position, Vector3.ONE * 0.01, "camera at %s" % camera_position)


func test_physics_tick_alone_repositions_the_sky() -> void:
	camera.global_position = Vector3(5000.0, 0.0, -7000.0)
	# No process frame in between: this is the path a teleport or rebase made in a physics tick relies on.
	env.sky_follower._physics_process(1.0 / 60.0)
	assert_almost_eq(env.star_field.global_position, camera.global_position, Vector3.ONE * 0.01)


func test_process_alone_repositions_the_sky() -> void:
	camera.global_position = Vector3(-300.0, 40.0, 25.0)
	env.sky_follower._process(0.016)
	assert_almost_eq(env.star_field.global_position, camera.global_position, Vector3.ONE * 0.01)


func test_a_large_jump_is_followed_at_once() -> void:
	# What a World rebase does to the camera: a sudden shift of kilometres.
	camera.global_position = Vector3(100.0, 0.0, 0.0)
	await _settle()
	camera.global_position -= Vector3(15000.0, 0.0, 0.0)
	env.sky_follower._physics_process(1.0 / 60.0)
	assert_almost_eq(env.star_field.global_position, Vector3(-14900.0, 0.0, 0.0), Vector3.ONE * 0.01)


func test_sky_ignores_camera_rotation() -> void:
	await _settle()
	var basis_before: Basis = env.star_field.global_transform.basis
	camera.global_position = Vector3(10.0, 20.0, 30.0)
	camera.rotate_y(deg_to_rad(90.0))
	camera.rotate_object_local(Vector3.RIGHT, deg_to_rad(35.0))
	await _settle()
	assert_true(env.star_field.global_transform.basis.is_equal_approx(basis_before), "the sky is fixed in the world; the camera turns inside it")


func test_without_a_camera_the_sky_stays_put() -> void:
	camera.global_position = Vector3(10.0, 0.0, 0.0)
	await _settle()
	var placed: Vector3 = env.star_field.global_position
	camera.clear_current()
	assert_null(get_viewport().get_camera_3d(), "no current camera")
	camera.global_position = Vector3(99.0, 0.0, 0.0)
	assert_false(env.sky_follower.follow())
	await _settle()
	assert_eq(env.star_field.global_position, placed)


# --- the sky console ---------------------------------------------------------------------------------


func test_the_sky_parts_can_be_hidden_and_shown() -> void:
	env.show_sky_part(&"stars", false)
	assert_false(env.star_field.visible)
	env.show_sky_part(&"stars", true)
	assert_true(env.star_field.visible)
	if not env.has_panorama():
		return
	env.show_sky_part(&"nebula", false)
	assert_eq(env.world_environment.environment.background_mode, Environment.BG_COLOR)
	env.show_sky_part(&"nebula", true)
	assert_eq(env.world_environment.environment.background_mode, Environment.BG_SKY)


func test_the_sky_command_and_provider() -> void:
	assert_true(_exec("sky stars off").ok)
	assert_false(env.star_field.visible)
	assert_true(_exec("sky stars on").ok)
	assert_true(env.star_field.visible)
	assert_true(_exec("sky stars").ok, "no state toggles")
	assert_false(env.star_field.visible)
	env.show_sky_part(&"stars", true)
	assert_false(_exec("sky clouds on").ok)
	var result: ConsoleResult = _exec("state sky")
	assert_true(result.ok)
	var text: String = "\n".join(result.lines)
	assert_string_contains(text, "stars = %d" % env.star_field.star_count())
	assert_string_contains(text, "panorama")
