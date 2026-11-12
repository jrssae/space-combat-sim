extends GutTest
## The star's look on the scaled-space layer, pure (M6-T12, AC7): its colours from the data's temperature, the flare's strength
## in an eclipse, the disc and corona law the shader repeats.

const EPSILON_K: float = 5084.0


func test_the_disc_takes_its_colour_from_the_star_data() -> void:
	var disc: Color = SunLook.disc_colour(StarCatalog.temperature_k(&"local"))
	assert_eq(StarCatalog.temperature_k(&"local"), EPSILON_K)
	assert_eq(disc, StarColor.linear_from_kelvin(EPSILON_K))
	assert_gt(disc.r, disc.g, "a K2V star is orange-white: red leads")
	assert_gt(disc.g, disc.b)
	assert_lt(disc.b, 0.7, "and not white")


func test_a_hotter_star_is_bluer() -> void:
	assert_gt(SunLook.disc_colour(9000.0).b, SunLook.disc_colour(EPSILON_K).b)


func test_the_corona_is_warmer_than_the_disc() -> void:
	var disc: Color = SunLook.disc_colour(EPSILON_K)
	var corona: Color = SunLook.corona_colour(EPSILON_K)
	assert_lt(corona.b / corona.r, disc.b / disc.r)


func test_the_flare_is_full_in_the_open_and_gone_in_an_eclipse() -> void:
	assert_eq(SunLook.flare_factor(1.0), 1.0)
	assert_eq(SunLook.flare_factor(0.0), 0.0)
	assert_eq(SunLook.flare_factor(0.01), 0.0, "a sliver of disc is no flare")


func test_the_flare_fades_smoothly_as_the_planet_covers_the_disc() -> void:
	var last: float = 0.0
	for part: float in [0.1, 0.3, 0.5, 0.7, 0.9, 1.0]:
		var now: float = SunLook.flare_factor(part)
		assert_gt(now, last, "stronger as more of the disc shows (%s)" % part)
		last = now
	assert_eq(SunLook.flare_factor(2.0), 1.0, "clamped")
	assert_eq(SunLook.flare_factor(-1.0), 0.0, "clamped")


func test_the_disc_is_darker_at_its_limb_and_the_corona_falls_off() -> void:
	assert_eq(SunLook.profile(0.0), 1.0)
	assert_almost_eq(SunLook.profile(0.9999), 1.0 - SunLook.LIMB_DARKENING, 0.02)
	assert_gt(SunLook.profile(0.5), SunLook.profile(0.95))
	assert_lt(SunLook.profile(1.5), SunLook.profile(1.0001), "the corona starts below the rim and falls")
	assert_gt(SunLook.profile(2.0), SunLook.profile(4.0))
	assert_eq(SunLook.profile(SunLook.GLOW_SCALE), 0.0, "and is gone inside the glow sphere")


func test_the_uniforms_carry_the_whole_look() -> void:
	var uniforms: Dictionary = SunLook.uniforms(EPSILON_K)
	for key: StringName in [&"colour", &"corona_colour", &"glow_scale", &"disc_brightness", &"corona_strength", &"limb_darkening"]:
		assert_true(uniforms.has(key), String(key))
	assert_eq(uniforms[&"glow_scale"], SunLook.GLOW_SCALE)
