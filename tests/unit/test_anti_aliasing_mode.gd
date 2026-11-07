extends GutTest
## M4-T38: each anti-aliasing mode sets the viewport's three switches, and only TAA asks for motion vectors.


func test_the_modes_are_the_six_the_task_lists() -> void:
	assert_eq(AntiAliasingMode.MODES, [&"off", &"fxaa", &"smaa", &"msaa_2x", &"msaa_4x", &"taa"])


func test_the_setting_offers_exactly_the_modes() -> void:
	var schema := SettingsSchema.new()
	assert_true(schema.has_key(&"anti_aliasing"))
	assert_eq(schema.get_choices(&"anti_aliasing"), AntiAliasingMode.MODES)
	assert_true(AntiAliasingMode.MODES.has(schema.get_default(&"anti_aliasing")))


func test_each_mode_maps_to_one_switch() -> void:
	var expected: Dictionary = {
		&"off": [Viewport.MSAA_DISABLED, Viewport.SCREEN_SPACE_AA_DISABLED, false],
		&"fxaa": [Viewport.MSAA_DISABLED, Viewport.SCREEN_SPACE_AA_FXAA, false],
		&"smaa": [Viewport.MSAA_DISABLED, Viewport.SCREEN_SPACE_AA_SMAA, false],
		&"msaa_2x": [Viewport.MSAA_2X, Viewport.SCREEN_SPACE_AA_DISABLED, false],
		&"msaa_4x": [Viewport.MSAA_4X, Viewport.SCREEN_SPACE_AA_DISABLED, false],
		&"taa": [Viewport.MSAA_DISABLED, Viewport.SCREEN_SPACE_AA_DISABLED, true],
	}
	for mode: StringName in expected:
		var want: Array = expected[mode]
		assert_eq(AntiAliasingMode.msaa(mode), want[0], "%s msaa" % mode)
		assert_eq(AntiAliasingMode.screen_space(mode), want[1], "%s screen space" % mode)
		assert_eq(AntiAliasingMode.taa(mode), want[2], "%s taa" % mode)


func test_only_taa_wants_motion_vectors() -> void:
	for mode: StringName in AntiAliasingMode.MODES:
		assert_eq(AntiAliasingMode.wants_motion_vectors(mode), mode == &"taa", String(mode))


func test_apply_then_read_gives_the_mode_back() -> void:
	var viewport := SubViewport.new()
	add_child_autofree(viewport)
	for mode: StringName in AntiAliasingMode.MODES:
		AntiAliasingMode.apply(viewport, mode)
		assert_eq(AntiAliasingMode.read(viewport), mode)
	viewport.msaa_3d = Viewport.MSAA_8X
	assert_eq(AntiAliasingMode.read(viewport), &"custom", "a mix no mode makes reads as custom")


func test_an_unknown_mode_applies_as_off() -> void:
	var viewport := SubViewport.new()
	add_child_autofree(viewport)
	AntiAliasingMode.apply(viewport, &"taa")
	AntiAliasingMode.apply(viewport, &"nonsense")
	assert_eq(AntiAliasingMode.read(viewport), &"off")
