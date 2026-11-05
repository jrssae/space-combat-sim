extends GutTest
## M4-T38: `settings.anti_aliasing` sets the root viewport's anti-aliasing live, survives a restart, and under TAA turns on the
## sky's motion vectors and the bolts that write their own (opaque bolts, slots quarantined). Headless there is no
## RenderingDevice, so this checks the switches; the vectors themselves are `test_motion_vectors_gpu`'s.

const SCENE_PATH: String = "res://src/environment/space_environment.tscn"
const SettingsScript := preload("res://src/autoload/settings.gd")
const CONFIG_PATH := "user://test_anti_aliasing.cfg"

var env: SpaceEnvironment
var aa: AntiAliasing
var _backup: Variant
var _viewport_backup: StringName


func before_each() -> void:
	_backup = Settings.get_value(&"anti_aliasing")
	_viewport_backup = AntiAliasingMode.read(get_viewport())
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.current = true
	env = (load(SCENE_PATH) as PackedScene).instantiate() as SpaceEnvironment
	add_child_autofree(env)
	aa = env.anti_aliasing


func after_each() -> void:
	Settings.set_value(&"anti_aliasing", _backup)
	AntiAliasingMode.apply(get_viewport(), _viewport_backup)
	BoltMesh.set_motion_vectors(false)
	if FileAccess.file_exists(CONFIG_PATH):
		DirAccess.remove_absolute(CONFIG_PATH)


func test_the_scene_has_the_node_and_the_sky_effect_first() -> void:
	assert_not_null(aa)
	var effects: Array[CompositorEffect] = env.world_environment.compositor.compositor_effects
	assert_true(effects[0] is SkyVelocityEffect, "the sky's vectors are written before anything reads them")
	assert_eq(effects[0].effect_callback_type, CompositorEffect.EFFECT_CALLBACK_TYPE_POST_SKY)
	assert_same(aa.sky_effect(), effects[0])


func test_the_default_is_applied_at_start() -> void:
	assert_eq(AntiAliasingMode.read(get_viewport()), StringName(Settings.get_value(&"anti_aliasing")))


func test_each_mode_applies_live_to_the_viewport() -> void:
	for mode: StringName in AntiAliasingMode.MODES:
		assert_eq(Settings.set_value(&"anti_aliasing", mode), OK)
		assert_eq(AntiAliasingMode.read(get_viewport()), mode, String(mode))
		assert_eq(aa.sky_effect().enabled, mode == &"taa", "%s: the sky's vectors only under TAA" % mode)
		assert_eq(BoltMesh.motion_vectors(), mode == &"taa", "%s: opaque bolts only under TAA" % mode)


func test_bolt_materials_go_opaque_under_taa_and_come_back() -> void:
	var material := Projectile.DEFAULT_MATERIAL as BaseMaterial3D
	var transparency: int = material.transparency
	var blend: int = material.blend_mode
	Settings.set_value(&"anti_aliasing", &"taa")
	assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, "an opaque bolt writes its motion vector")
	Settings.set_value(&"anti_aliasing", &"smaa")
	assert_eq(material.transparency, transparency, "the approved additive look returns")
	assert_eq(material.blend_mode, blend)


func test_the_mode_survives_a_restart() -> void:
	var first: Node = SettingsScript.new()
	first.config_path = CONFIG_PATH
	first.joy_mappings_path = "user://test_no_such_gamecontrollerdb.txt"
	add_child_autofree(first)
	assert_eq(first.set_value(&"anti_aliasing", &"msaa_4x"), OK)
	assert_eq(first.save(), OK)
	var fresh: Node = SettingsScript.new()
	fresh.config_path = CONFIG_PATH
	fresh.joy_mappings_path = "user://test_no_such_gamecontrollerdb.txt"
	add_child_autofree(fresh)
	assert_eq(fresh.get_value(&"anti_aliasing"), &"msaa_4x")
	aa.apply_mode(StringName(fresh.get_value(&"anti_aliasing")))
	assert_eq(AntiAliasingMode.read(get_viewport()), &"msaa_4x")


func test_the_console_command_and_provider() -> void:
	var result: ConsoleResult = _run("aa taa")
	assert_true(result.ok, result.error)
	assert_eq(Settings.get_value(&"anti_aliasing"), &"taa")
	var text: String = "\n".join(_run("state aa").lines)
	assert_string_contains(text, "mode = taa")
	assert_string_contains(text, "sky_vectors = true")
	result = _run("aa nonsense")
	assert_false(result.ok)
	assert_eq(Settings.get_value(&"anti_aliasing"), &"taa", "a bad mode changes nothing")
	result = _run("aa")
	assert_true(result.ok, result.error)
	assert_string_contains("\n".join(result.lines), "taa")


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]
