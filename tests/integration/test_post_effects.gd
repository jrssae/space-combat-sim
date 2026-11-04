extends GutTest
## AC34: the lens flare and the motion blur toggle live from settings and the console, the flare follows the key star, and a
## rebase blanks the blur. Headless there is no RenderingDevice, so the effects do no work and pixels are (H); this checks
## the wiring, the values the effects are given and that nothing errors.

const SCENE_PATH: String = "res://src/environment/space_environment.tscn"

var env: SpaceEnvironment
var camera: Camera3D
var post: PostEffects
var _backup: Dictionary = {}


func before_each() -> void:
	for key: StringName in [&"lens_flare", &"motion_blur", &"motion_blur_strength"]:
		_backup[key] = Settings.get_value(key)
	camera = Camera3D.new()
	add_child_autofree(camera)
	camera.current = true
	env = (load(SCENE_PATH) as PackedScene).instantiate() as SpaceEnvironment
	add_child_autofree(env)
	post = env.post_effects


func after_each() -> void:
	for key: StringName in _backup:
		Settings.set_value(key, _backup[key])


func _frame() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


# --- the effects and their order ---------------------------------------------------------------------------------


func test_the_post_node_finds_both_effects() -> void:
	assert_not_null(post, "the scene has PostEffects")
	assert_not_null(post.flare_effect(), "the add-on's LensFlareEffect")
	assert_not_null(post.blur_effect(), "our MotionBlurEffect")


func test_both_run_after_the_transparent_pass() -> void:
	# Hulls, glass, plumes and the star points are all drawn by then, so the blur smears them together and the flare goes on top.
	assert_true(post.blur_effect().effect_callback_type >= CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT)
	assert_true(post.flare_effect().effect_callback_type >= CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT)


func test_the_flare_is_the_vendored_effect_through_our_thin_subclass() -> void:
	var effect: LensFlareEffect = post.flare_effect()
	assert_true(effect is SceneLensFlareEffect)
	var base_path: String = (effect.get_script() as Script).get_base_script().resource_path
	assert_eq(base_path, "res://addons/lens_effects/lens_flare_compositor_effect.gd", "the add-on's class, as vendored")


# --- settings, live -----------------------------------------------------------------------------------------------


func test_defaults_flare_on_blur_off() -> void:
	assert_true(bool(Settings.get_value(&"lens_flare")))
	assert_false(bool(Settings.get_value(&"motion_blur")))
	assert_almost_eq(float(Settings.get_value(&"motion_blur_strength")), 0.5, 0.0001)
	post.apply_settings()
	assert_true(post.flare_effect().enabled)
	assert_false(post.blur_effect().enabled, "an off blur asks the renderer for no motion vectors")


func test_settings_switch_the_effects_live() -> void:
	Settings.set_value(&"lens_flare", false)
	assert_false(post.flare_effect().enabled)
	Settings.set_value(&"lens_flare", true)
	assert_true(post.flare_effect().enabled)
	Settings.set_value(&"motion_blur", true)
	assert_true(post.blur_effect().enabled)
	Settings.set_value(&"motion_blur", false)
	assert_false(post.blur_effect().enabled)


func test_the_blur_strength_setting_reaches_the_effect() -> void:
	Settings.set_value(&"motion_blur", true)
	Settings.set_value(&"motion_blur_strength", 0.8)
	await _frame()
	assert_almost_eq(post.blur_effect().strength, 0.8, 0.0001)


func test_an_off_blur_is_given_zero_strength() -> void:
	Settings.set_value(&"motion_blur", false)
	await _frame()
	assert_eq(post.blur_effect().strength, 0.0)


func test_strength_is_a_unit_range_setting() -> void:
	var entry: Dictionary = SettingsSchema.ENTRIES[&"motion_blur_strength"]
	assert_eq(entry["min"], 0.0)
	assert_eq(entry["max"], 1.0)


# --- console ------------------------------------------------------------------------------------------------------


func test_console_commands_toggle_the_effects() -> void:
	var result: ConsoleResult = DebugConsole.registry.execute_tokens(PackedStringArray(["flare", "off"]))
	assert_true(result.ok, "flare off")
	assert_false(post.flare_effect().enabled)
	result = DebugConsole.registry.execute_tokens(PackedStringArray(["blur", "on"]))
	assert_true(result.ok, "blur on")
	assert_true(post.blur_effect().enabled)
	result = DebugConsole.registry.execute_tokens(PackedStringArray(["blur"]))
	assert_true(result.ok, "blur toggles")
	assert_false(post.blur_effect().enabled)


func test_set_settings_path_works_from_the_console() -> void:
	var result: ConsoleResult = DebugConsole.registry.write("settings.motion_blur", true)
	assert_true(result.ok)
	assert_true(post.blur_effect().enabled)


func test_the_post_provider_answers_state() -> void:
	assert_true(DebugConsole.registry.has_provider(&"post"))
	var lines: String = "\n".join(DebugConsole.registry.describe_provider(&"post"))
	for key: String in ["flare", "blur", "sun_uv"]:
		assert_string_contains(lines, key)


# --- the star ------------------------------------------------------------------------------------------------------


func test_the_flare_is_told_where_the_star_is() -> void:
	# The key star shines along its -Z, so the star lies along its +Z. Point the camera at it.
	var to_sun: Vector3 = env.key_star.global_basis.z
	camera.global_transform = Transform3D(Basis.looking_at(to_sun), Vector3.ZERO)
	await _frame()
	assert_almost_eq(post.flare_effect().sun_position.x, 0.5, 0.01)
	assert_almost_eq(post.flare_effect().sun_position.y, 0.5, 0.01)
	assert_almost_eq(post.flare_effect().sun_dir_sign, 1.0, 0.001)


func test_looking_away_from_the_star_flips_the_facing_sign() -> void:
	var to_sun: Vector3 = env.key_star.global_basis.z
	camera.global_transform = Transform3D(Basis.looking_at(-to_sun), Vector3.ZERO)
	await _frame()
	assert_almost_eq(post.flare_effect().sun_dir_sign, -1.0, 0.001)


func test_the_flare_does_not_chase_the_star_while_off() -> void:
	Settings.set_value(&"lens_flare", false)
	var before: Vector2 = post.flare_effect().sun_position
	camera.global_transform = Transform3D(Basis.looking_at(env.key_star.global_basis.z), Vector3.ZERO)
	await _frame()
	assert_eq(post.flare_effect().sun_position, before)


# --- rebase ---------------------------------------------------------------------------------------------------------


func test_a_rebase_blanks_the_blur_then_it_returns() -> void:
	var world := WorldFrame.new()
	add_child_autofree(world)
	post.watch_world(world)
	Settings.set_value(&"motion_blur", true)
	Settings.set_value(&"motion_blur_strength", 0.6)
	await _frame()
	assert_almost_eq(post.blur_effect().strength, 0.6, 0.0001, "blurring")
	world.rebase(Vector3(5000.0, 0.0, 0.0))
	assert_eq(post.blur_gate().skipping(), MotionBlurGate.SKIP_FRAMES_AFTER_REBASE)
	await get_tree().process_frame
	assert_eq(post.blur_effect().strength, 0.0, "the rebase frame is not smeared")
	for i: int in MotionBlurGate.SKIP_FRAMES_AFTER_REBASE + 1:
		await get_tree().process_frame
	assert_almost_eq(post.blur_effect().strength, 0.6, 0.0001, "and the blur is back")


func test_watching_a_second_world_stops_listening_to_the_first() -> void:
	var first := WorldFrame.new()
	var second := WorldFrame.new()
	add_child_autofree(first)
	add_child_autofree(second)
	post.watch_world(first)
	post.watch_world(second)
	first.rebase(Vector3(1.0, 0.0, 0.0))
	assert_eq(post.blur_gate().skipping(), 0)
	second.rebase(Vector3(1.0, 0.0, 0.0))
	assert_gt(post.blur_gate().skipping(), 0)


func test_the_flare_and_the_key_star_show_the_systems_star() -> void:
	var star: Color = StarColor.linear_from_kelvin(5084.0)
	var flare: Color = env.post_effects.flare_effect().sun_color
	assert_almost_eq(flare.g / flare.r, star.g, 1e-3, "the flare has the star's colour")
	assert_almost_eq(flare.b / flare.r, star.b, 1e-3)
	var light: Color = env.key_star.light_color.srgb_to_linear()
	assert_almost_eq(light.g / light.r, star.g, 1e-3, "and so does its light")
	assert_almost_eq(light.b / light.r, star.b, 1e-3)


func test_another_system_changes_both() -> void:
	env.set_star(3000.0)
	var red: Color = StarColor.linear_from_kelvin(3000.0)
	var flare: Color = env.post_effects.flare_effect().sun_color
	assert_almost_eq(flare.g / flare.r, red.g, 1e-3)
	assert_almost_eq(env.key_star.light_color.srgb_to_linear().b, red.b, 1e-3)
	env.set_star(5084.0)


func test_the_shader_patches_still_apply_to_the_vendored_shader() -> void:
	var path: String = "res://addons/lens_effects/lens_flares.glsl"
	var original: String = FileAccess.get_file_as_string(path)
	for old: String in SceneLensFlareEffect.SHADER_PATCHES:
		assert_string_contains(original, old, "still in the add-on")
	var patched: String = SceneLensFlareEffect.patched_source(path)
	assert_false(patched.contains("lensflare.r -= yellow"), "the ghosts are no longer pushed toward blue")
	assert_string_contains(patched, "vec3 always_on_flare = vec3(0.0);", "no veil over the picture")
	assert_false(patched.contains("col *= godrays"), "no shafts of light in empty space")
	assert_string_contains(patched, "for (int i = 0; i < 0; i++) {", "and no depth reads marching them")


func test_the_star_field_leaves_the_flare_open_on_the_sky_and_a_hull_still_hides_it() -> void:
	# M4-T30c: the flare reads the star's pixel as open sky where the depth is still the clear value; the star points write no
	# depth, so the sky stays open through them, while a hull writes its depth and still closes it. The stars are drawn after
	# the opaque pass and depth-tested, so the same hull hides them.
	var material: ShaderMaterial = env.star_field.material_override as ShaderMaterial
	assert_not_null(material)
	var code: String = material.shader.code
	assert_string_contains(code, "depth_draw_never", "no depth from the stars: the sky stays open for the flare")
	assert_false(code.contains("depth_test_disabled"), "depth-tested: a hull hides a star")
	assert_string_contains(code, "blend_add", "drawn in the transparent pass, after the hulls' depth")
	var lens_shader: String = FileAccess.get_file_as_string("res://addons/lens_effects/lens_flares.glsl")
	assert_string_contains(lens_shader, "get_raw_depth(ivec2(sun_position)) <= 0.0", "the flare's open-sky rule is the clear depth")

