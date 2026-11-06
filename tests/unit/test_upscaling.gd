extends GutTest
## M4-T40: the upscalers and internal-resolution presets `Upscaling` offers, their exact scales, and what `auto` picks for a
## window. Pure: no viewport needed.


func test_the_upscalers_and_presets_are_the_ones_the_task_lists() -> void:
	assert_eq(Upscaling.UPSCALERS, [&"auto", &"native", &"bilinear", &"fsr1", &"fsr2"])
	assert_eq(Upscaling.PRESETS, [&"auto", &"native", &"quality", &"balanced", &"performance", &"ultra_performance", &"custom"])


func test_the_settings_offer_exactly_them() -> void:
	var schema := SettingsSchema.new()
	assert_eq(schema.get_choices(&"upscaler"), Upscaling.UPSCALERS)
	assert_eq(schema.get_choices(&"upscale_preset"), Upscaling.PRESETS)
	assert_true(Upscaling.UPSCALERS.has(schema.get_default(&"upscaler")))
	assert_true(Upscaling.PRESETS.has(schema.get_default(&"upscale_preset")))
	assert_true(schema.has_key(&"upscale_custom_scale"))
	assert_true(schema.has_key(&"fsr_sharpness"))
	assert_eq(schema.get_entry(&"fsr_sharpness")["min"], 0.0, "Godot's own scale: 0 is the sharpest")
	assert_eq(schema.get_entry(&"fsr_sharpness")["max"], 2.0)
	assert_eq(schema.get_entry(&"upscale_custom_scale")["min"], Upscaling.MIN_SCALE, "down to a third of the height")
	assert_eq(schema.get_entry(&"upscale_custom_scale")["max"], 1.0, "never above native")


# AMD's FSR 2 ratios: 1.5, 1.7, 2 and 3 times smaller per side, so a 2 160-line window renders 1 440, 1 080 and 720 lines.
func test_the_preset_scales_are_exact() -> void:
	assert_eq(Upscaling.preset_scale(&"native"), 1.0)
	assert_eq(Upscaling.preset_scale(&"quality"), 1.0 / 1.5)
	assert_eq(Upscaling.preset_scale(&"balanced"), 1.0 / 1.7)
	assert_eq(Upscaling.preset_scale(&"performance"), 0.5)
	assert_eq(Upscaling.preset_scale(&"ultra_performance"), 1.0 / 3.0)
	var listed: Dictionary = {&"native": 1.0, &"quality": 0.67, &"balanced": 0.59, &"performance": 0.5, &"ultra_performance": 0.33}
	for preset: StringName in listed:
		assert_eq(snappedf(Upscaling.preset_scale(preset), 0.01), listed[preset], "%s rounds to the listed scale" % preset)
	assert_eq(Upscaling.internal_lines(2160, Upscaling.preset_scale(&"quality")), 1440)
	assert_eq(Upscaling.internal_lines(2160, Upscaling.preset_scale(&"performance")), 1080)
	assert_eq(Upscaling.internal_lines(2160, Upscaling.preset_scale(&"ultra_performance")), 720)
	assert_eq(Upscaling.internal_lines(3456, Upscaling.preset_scale(&"quality")), 2304)


func test_a_custom_scale_is_used_as_given_and_clamped() -> void:
	assert_eq(Upscaling.preset_scale(&"custom", 0.8), 0.8)
	assert_eq(Upscaling.preset_scale(&"custom", 1.7), 1.0, "never above native: FSR is not a downsampler")
	assert_eq(Upscaling.preset_scale(&"custom", 0.1), Upscaling.MIN_SCALE, "never below a third of the height")
	assert_eq(Upscaling.MIN_SCALE, 0.33)


func test_each_upscaler_maps_to_its_godot_mode() -> void:
	assert_eq(Upscaling.mode(&"native"), Viewport.SCALING_3D_MODE_BILINEAR)
	assert_eq(Upscaling.mode(&"bilinear"), Viewport.SCALING_3D_MODE_BILINEAR)
	assert_eq(Upscaling.mode(&"fsr1"), Viewport.SCALING_3D_MODE_FSR)
	assert_eq(Upscaling.mode(&"fsr2"), Viewport.SCALING_3D_MODE_FSR2)


func test_only_fsr2_is_temporal() -> void:
	for upscaler: StringName in [&"native", &"bilinear", &"fsr1"]:
		assert_false(Upscaling.temporal(upscaler), String(upscaler))
	assert_true(Upscaling.temporal(&"fsr2"))


func test_auto_picks_fsr2_quality_for_a_4k_window_and_native_below() -> void:
	var big: Dictionary = Upscaling.plan(&"auto", &"auto", 0.75, 2160)
	assert_eq(big["upscaler"], &"fsr2")
	assert_eq(big["preset"], &"quality")
	assert_eq(big["scale"], 1.0 / 1.5)
	assert_eq(big["mode"], Viewport.SCALING_3D_MODE_FSR2)
	var six_k: Dictionary = Upscaling.plan(&"auto", &"auto", 0.75, 3456)
	assert_eq(six_k["upscaler"], &"fsr2")
	for lines: int in [1080, 1440, 1600]:
		var small: Dictionary = Upscaling.plan(&"auto", &"auto", 0.75, lines)
		assert_eq(small["upscaler"], &"native", "%d lines" % lines)
		assert_eq(small["scale"], 1.0, "%d lines" % lines)
		assert_eq(small["mode"], Viewport.SCALING_3D_MODE_BILINEAR)


func test_native_renders_at_the_windows_size_whatever_the_preset() -> void:
	var plan: Dictionary = Upscaling.plan(&"native", &"performance", 0.75, 2160)
	assert_eq(plan["scale"], 1.0)
	assert_eq(plan["upscaler"], &"native")


func test_an_explicit_upscaler_with_the_auto_preset_follows_the_window() -> void:
	assert_eq(Upscaling.plan(&"fsr1", &"auto", 0.75, 2160)["scale"], 1.0 / 1.5)
	assert_eq(Upscaling.plan(&"fsr1", &"auto", 0.75, 1080)["scale"], 1.0, "FSR 1.0 at a 1 080 window keeps native lines")
	assert_eq(Upscaling.plan(&"fsr2", &"auto", 0.75, 1080)["upscaler"], &"fsr2", "FSR 2.2 at 1.0 is its anti-aliasing alone")


func test_explicit_choices_are_kept() -> void:
	var plan: Dictionary = Upscaling.plan(&"bilinear", &"balanced", 0.75, 1080)
	assert_eq(plan["upscaler"], &"bilinear")
	assert_eq(plan["preset"], &"balanced")
	assert_eq(plan["scale"], 1.0 / 1.7)
	assert_eq(Upscaling.plan(&"fsr2", &"custom", 0.8, 2160)["scale"], 0.8)


func test_unknown_values_fall_back_to_native() -> void:
	var plan: Dictionary = Upscaling.plan(&"dlss", &"silly", 0.75, 2160)
	assert_eq(plan["upscaler"], &"native")
	assert_eq(plan["scale"], 1.0)
