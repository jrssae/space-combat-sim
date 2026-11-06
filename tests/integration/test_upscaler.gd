extends GutTest
## M4-T40: the upscaler settings set the root viewport's 3D scaling live and survive a restart; the HUD stays at the window's
## size; FSR 2.2 holds the anti-aliasing mode off (its own temporal anti-aliasing) and turns on the motion vectors, and the mode
## comes back when FSR 2.2 goes. Headless there is no RenderingDevice, so this checks the switches; the picture is
## `test_upscaling_gpu`'s.

const SCENE_PATH: String = "res://src/environment/space_environment.tscn"
const SettingsScript := preload("res://src/autoload/settings.gd")
const CONFIG_PATH := "user://test_upscaler.cfg"
const KEYS: Array[StringName] = [&"upscaler", &"upscale_preset", &"upscale_custom_scale", &"fsr_sharpness", &"anti_aliasing"]

var env: SpaceEnvironment
var upscaler: Upscaler
var _backup: Dictionary = {}
var _viewport_backup: Dictionary = {}


func before_each() -> void:
	for key: StringName in KEYS:
		_backup[key] = Settings.get_value(key)
	var root: Window = get_tree().root
	_viewport_backup = {"mode": root.scaling_3d_mode, "scale": root.scaling_3d_scale, "sharpness": root.fsr_sharpness,
			"aa": AntiAliasingMode.read(root), "size": root.size}
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.current = true
	env = (load(SCENE_PATH) as PackedScene).instantiate() as SpaceEnvironment
	add_child_autofree(env)
	upscaler = env.upscaler


func after_each() -> void:
	for key: StringName in KEYS:
		Settings.set_value(key, _backup[key])
	var root: Window = get_tree().root
	root.size = _viewport_backup["size"]
	root.scaling_3d_mode = _viewport_backup["mode"]
	root.scaling_3d_scale = _viewport_backup["scale"]
	root.fsr_sharpness = _viewport_backup["sharpness"]
	AntiAliasingMode.apply(root, _viewport_backup["aa"])
	BoltMesh.set_motion_vectors(false)
	if FileAccess.file_exists(CONFIG_PATH):
		DirAccess.remove_absolute(CONFIG_PATH)


func test_the_scene_has_the_node_after_the_anti_aliasing() -> void:
	assert_not_null(upscaler)
	assert_same(upscaler.anti_aliasing, env.anti_aliasing)
	assert_gt(upscaler.get_index(), env.anti_aliasing.get_index(), "set up after the mode it may hold")


func test_the_settings_apply_live_to_the_root_viewport() -> void:
	var root: Window = get_tree().root
	Settings.set_value(&"upscale_preset", &"balanced")
	for name: StringName in [&"bilinear", &"fsr1", &"fsr2"]:
		assert_eq(Settings.set_value(&"upscaler", name), OK)
		assert_eq(root.scaling_3d_mode, Upscaling.mode(name), String(name))
		assert_almost_eq(root.scaling_3d_scale, 1.0 / 1.7, 1e-6, String(name))
	Settings.set_value(&"upscale_preset", &"ultra_performance")
	assert_almost_eq(root.scaling_3d_scale, 1.0 / 3.0, 1e-6)
	Settings.set_value(&"upscale_preset", &"custom")
	Settings.set_value(&"upscale_custom_scale", 0.8)
	assert_almost_eq(root.scaling_3d_scale, 0.8, 1e-6)
	Settings.set_value(&"fsr_sharpness", 1.25)
	assert_eq(root.fsr_sharpness, 1.25)
	Settings.set_value(&"upscaler", &"native")
	assert_eq(root.scaling_3d_scale, 1.0, "native renders the 3D at the window's size")
	assert_eq(root.scaling_3d_mode, Viewport.SCALING_3D_MODE_BILINEAR)


func test_auto_follows_the_window() -> void:
	var root: Window = get_tree().root
	Settings.set_value(&"upscaler", &"auto")
	Settings.set_value(&"upscale_preset", &"auto")
	root.size = Vector2i(3840, 2160)
	await get_tree().process_frame
	assert_eq(root.scaling_3d_mode, Viewport.SCALING_3D_MODE_FSR2, "a 4K window gets FSR 2.2")
	assert_almost_eq(root.scaling_3d_scale, 1.0 / 1.5, 1e-6, "at Quality")
	root.size = Vector2i(1920, 1080)
	await get_tree().process_frame
	assert_eq(root.scaling_3d_scale, 1.0, "a 1 080 window renders native")
	assert_eq(root.scaling_3d_mode, Viewport.SCALING_3D_MODE_BILINEAR)


func test_the_settings_survive_a_restart() -> void:
	var first: Node = SettingsScript.new()
	first.config_path = CONFIG_PATH
	first.joy_mappings_path = "user://test_no_such_gamecontrollerdb.txt"
	add_child_autofree(first)
	assert_eq(first.set_value(&"upscaler", &"fsr1"), OK)
	assert_eq(first.set_value(&"upscale_preset", &"custom"), OK)
	assert_eq(first.set_value(&"upscale_custom_scale", 0.6), OK)
	assert_eq(first.set_value(&"fsr_sharpness", 0.9), OK)
	assert_eq(first.save(), OK)
	var fresh: Node = SettingsScript.new()
	fresh.config_path = CONFIG_PATH
	fresh.joy_mappings_path = "user://test_no_such_gamecontrollerdb.txt"
	add_child_autofree(fresh)
	assert_eq(fresh.get_value(&"upscaler"), &"fsr1")
	assert_eq(fresh.get_value(&"upscale_preset"), &"custom")
	assert_almost_eq(float(fresh.get_value(&"upscale_custom_scale")), 0.6, 1e-6)
	assert_almost_eq(float(fresh.get_value(&"fsr_sharpness")), 0.9, 1e-6)
	for key: StringName in [&"upscaler", &"upscale_preset", &"upscale_custom_scale", &"fsr_sharpness"]:
		Settings.set_value(key, fresh.get_value(key))
	var root: Window = get_tree().root
	assert_eq(root.scaling_3d_mode, Viewport.SCALING_3D_MODE_FSR)
	assert_almost_eq(root.scaling_3d_scale, 0.6, 1e-6)


func test_the_hud_stays_at_the_windows_size() -> void:
	var layer := CanvasLayer.new()
	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(panel)
	add_child_autofree(layer)
	await get_tree().process_frame
	var root: Window = get_tree().root
	var window_rect: Rect2 = root.get_visible_rect()
	var size: Vector2 = panel.size
	var transform: Transform2D = root.canvas_transform
	Settings.set_value(&"upscaler", &"fsr2")
	Settings.set_value(&"upscale_preset", &"ultra_performance")
	await get_tree().process_frame
	assert_almost_eq(root.scaling_3d_scale, 1.0 / 3.0, 1e-6)
	assert_eq(root.get_visible_rect(), window_rect, "the 2D canvas keeps the window's size")
	assert_eq(panel.size, size, "the HUD does not shrink with the 3D")
	assert_eq(panel.size, window_rect.size)
	assert_eq(root.canvas_transform, transform, "nor is it scaled")
	assert_eq(root.content_scale_mode, Window.CONTENT_SCALE_MODE_DISABLED, "no stretch: 2D draws at the window's pixels")


func test_fsr2_holds_the_anti_aliasing_mode_and_gives_it_back() -> void:
	var root: Window = get_tree().root
	Settings.set_value(&"upscaler", &"native")
	Settings.set_value(&"anti_aliasing", &"taa")
	assert_true(root.use_taa)
	Settings.set_value(&"upscaler", &"fsr2")
	Settings.set_value(&"upscale_preset", &"quality")
	assert_false(root.use_taa, "FSR 2.2 does its own temporal anti-aliasing")
	assert_eq(AntiAliasingMode.read(root), AntiAliasingMode.OFF, "no other mode stacks on it")
	assert_eq(Settings.get_value(&"anti_aliasing"), &"taa", "the setting is kept")
	assert_true(env.anti_aliasing.held(), "and shown as held")
	assert_true(env.anti_aliasing.sky_effect().enabled, "FSR 2.2 reprojects: the sky's vectors stay on")
	assert_true(BoltMesh.motion_vectors(), "and the bolts carry theirs")
	Settings.set_value(&"upscaler", &"fsr1")
	assert_true(root.use_taa, "TAA comes back when FSR 2.2 goes")
	assert_false(env.anti_aliasing.held())
	Settings.set_value(&"anti_aliasing", &"smaa")
	Settings.set_value(&"upscaler", &"fsr2")
	assert_eq(root.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED, "SMAA is held too")
	assert_true(env.anti_aliasing.sky_effect().enabled, "motion vectors under FSR 2.2 whatever the mode")
	Settings.set_value(&"upscaler", &"bilinear")
	assert_eq(AntiAliasingMode.read(root), AntiAliasingMode.SMAA, "and SMAA comes back")
	assert_false(env.anti_aliasing.sky_effect().enabled, "SMAA needs no vectors")
	assert_false(BoltMesh.motion_vectors())


func test_a_mode_changed_under_fsr2_waits_for_it_to_go() -> void:
	var root: Window = get_tree().root
	Settings.set_value(&"upscaler", &"fsr2")
	Settings.set_value(&"anti_aliasing", &"msaa_4x")
	assert_eq(root.msaa_3d, Viewport.MSAA_DISABLED, "held while FSR 2.2 is on")
	Settings.set_value(&"upscaler", &"native")
	assert_eq(root.msaa_3d, Viewport.MSAA_4X)


func test_the_console_shows_the_hold() -> void:
	Settings.set_value(&"anti_aliasing", &"taa")
	assert_true(_run("upscale fsr2 quality").ok)
	var aa: ConsoleResult = _run("aa")
	assert_string_contains("\n".join(aa.lines), "taa")
	assert_string_contains("\n".join(aa.lines), "FSR 2.2")
	var state: String = "\n".join(_run("state aa").lines)
	assert_string_contains(state, "held = true")
	assert_string_contains(state, "viewport = off")


func test_the_console_command_and_provider() -> void:
	var result: ConsoleResult = _run("upscale fsr1 performance")
	assert_true(result.ok, result.error)
	assert_eq(Settings.get_value(&"upscaler"), &"fsr1")
	assert_eq(Settings.get_value(&"upscale_preset"), &"performance")
	assert_eq(get_tree().root.scaling_3d_scale, 0.5)
	result = _run("upscale fsr2 0.75")
	assert_true(result.ok, result.error)
	assert_eq(Settings.get_value(&"upscale_preset"), &"custom", "a number is a custom scale")
	assert_almost_eq(float(Settings.get_value(&"upscale_custom_scale")), 0.75, 1e-6)
	var text: String = "\n".join(_run("state upscale").lines)
	assert_string_contains(text, "upscaler = fsr2")
	assert_string_contains(text, "applied = fsr2")
	assert_string_contains(text, "scale = 0.75")
	assert_string_contains(text, "internal_lines")
	result = _run("upscale dlss")
	assert_false(result.ok, "an unknown upscaler")
	result = _run("upscale bilinear nonsense")
	assert_false(result.ok, "an unknown preset")
	assert_eq(Settings.get_value(&"upscaler"), &"fsr2", "a bad line changes nothing")
	result = _run("upscale")
	assert_true(result.ok, result.error)
	assert_string_contains("\n".join(result.lines), "fsr2")


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]
