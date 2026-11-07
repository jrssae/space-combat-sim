extends GutTest
## The explosion level of detail's maths (M4-T23, fix round 1, architecture §17.14): the level follows the fireball's size in
## pixels on the current picture (the full effect while its radius is `FULL_PX` or more, the reduced one down to `REDUCED_PX`,
## then the far flash), so the switch moves with the resolution; the flash takes over at the fireball's size and brightness, so
## its delivered light at the switch is what the reduced effect showed (no pop, no gap), then shrinks to its 1 px floor and falls
## with the inverse square until it drops under the visibility bar. Checked for a fighter, a destroyer and a carrier at 1 080 and
## 2 160 lines.

const FOV_DEG: float = 70.0
## A raider's bounding radius (17 by 7.2 m), about.
const FIGHTER_R: float = 9.3


func _classes() -> Dictionary:
	return {"fighter": FIGHTER_R, "destroyer": CapitalStandin.hull_radius(&"destroyer"), "carrier": CapitalStandin.hull_radius(&"carrier")}


func test_the_level_follows_the_fireballs_size_in_pixels() -> void:
	for lines: float in [1080.0, 2160.0]:
		for r: float in _classes().values():
			var full_m: float = ExplosionLod.switch_distance_m(r, lines, FOV_DEG, ExplosionLod.FULL_PX)
			var far_m: float = ExplosionLod.switch_distance_m(r, lines, FOV_DEG, ExplosionLod.REDUCED_PX)
			assert_almost_eq(ExplosionLod.fireball_px(r, full_m, lines, FOV_DEG), ExplosionLod.FULL_PX, 1e-3)
			assert_eq(ExplosionLod.level(r, full_m * 0.99, lines, FOV_DEG), ExplosionLod.Level.FULL)
			assert_eq(ExplosionLod.level(r, full_m * 1.01, lines, FOV_DEG), ExplosionLod.Level.REDUCED)
			assert_eq(ExplosionLod.level(r, far_m * 0.99, lines, FOV_DEG), ExplosionLod.Level.REDUCED)
			assert_eq(ExplosionLod.level(r, far_m * 1.01, lines, FOV_DEG), ExplosionLod.Level.FAR)


func test_the_switch_moves_with_the_resolution() -> void:
	for r: float in _classes().values():
		assert_almost_eq(ExplosionLod.switch_distance_m(r, 2160.0, FOV_DEG, ExplosionLod.REDUCED_PX)
				/ ExplosionLod.switch_distance_m(r, 1080.0, FOV_DEG, ExplosionLod.REDUCED_PX), 2.0, 1e-4, "twice the lines, twice as far")


func test_the_flash_is_visible_at_the_switch_and_takes_over_the_reduced_effects_light() -> void:
	var classes: Dictionary = _classes()
	for lines: float in [1080.0, 2160.0]:
		for cls: String in classes:
			var r: float = classes[cls]
			var switch_m: float = ExplosionLod.switch_distance_m(r, lines, FOV_DEG, ExplosionLod.REDUCED_PX)
			var at_switch: Vector2 = ExplosionLod.on_screen(r, switch_m, lines, FOV_DEG)
			assert_almost_eq(at_switch.x, ExplosionLod.REDUCED_PX, 1e-3, "%s, %d lines: the flash as big as the fireball it replaces" % [cls, lines])
			var delivered: float = at_switch.y * at_switch.x * at_switch.x
			assert_almost_eq(delivered, ExplosionLod.PEAK * ExplosionLod.REDUCED_PX * ExplosionLod.REDUCED_PX, 1e-3,
					"%s, %d lines: the same light as the reduced effect at its end" % [cls, lines])
			assert_gt(delivered, ExplosionLod.VISIBLE_DELIVERED, "%s, %d lines: visible at the switch" % [cls, lines])
			assert_gte(ExplosionLod.visible_to_m(r, lines, FOV_DEG), 2.0 * switch_m, "%s, %d lines: and well beyond it" % [cls, lines])


func test_below_its_floor_the_flash_keeps_a_pixel_and_its_light_falls_by_the_inverse_square() -> void:
	for lines: float in [1080.0, 2160.0]:
		var floor_m: float = ExplosionLod.floor_distance_m(FIGHTER_R, lines, FOV_DEG)
		assert_almost_eq(ExplosionLod.on_screen(FIGHTER_R, floor_m, lines, FOV_DEG).x, 1.0, 1e-3)
		for d: float in [2.0 * floor_m, 4.0 * floor_m]:
			var s: Vector2 = ExplosionLod.on_screen(FIGHTER_R, d, lines, FOV_DEG)
			assert_eq(s.x, 1.0, "never under a pixel")
			assert_almost_eq(s.y * s.x * s.x / (ExplosionLod.PEAK * pow(floor_m / d, 2.0)), 1.0, 1e-3, "the inverse square")


func test_a_fighters_death_reads_across_a_few_km_and_a_capitals_across_tens() -> void:
	var classes: Dictionary = _classes()
	for lines: float in [1080.0, 2160.0]:
		var reach: Dictionary = {}
		for cls: String in classes:
			reach[cls] = ExplosionLod.visible_to_m(classes[cls], lines, FOV_DEG)
			gut.p("%d lines, %s (R %.0f m): full to %.1f km, reduced to %.1f km, the flash reads to %.1f km" % [lines, cls, classes[cls],
					ExplosionLod.switch_distance_m(classes[cls], lines, FOV_DEG, ExplosionLod.FULL_PX) / 1000.0,
					ExplosionLod.switch_distance_m(classes[cls], lines, FOV_DEG, ExplosionLod.REDUCED_PX) / 1000.0, reach[cls] / 1000.0])
		assert_between(float(reach["fighter"]), 3000.0, 60000.0, "%d lines: a fighter's across a few km" % lines)
		assert_gt(float(reach["destroyer"]), 10.0 * float(reach["fighter"]), "a capital's much farther")
		assert_gt(float(reach["carrier"]), float(reach["destroyer"]))
		assert_gt(float(reach["destroyer"]), 30000.0, "%d lines: a capital's across tens of km" % lines)


func test_the_flash_rises_fast_lasts_longer_for_a_bigger_blast_and_fades_to_nothing() -> void:
	var e: float = 2.0e9
	var life: float = ExplosionLod.flash_s(e)
	assert_eq(ExplosionLod.envelope(0.0, life), 0.0)
	assert_almost_eq(ExplosionLod.envelope(ExplosionLod.RISE_S, life), 1.0, 1e-4)
	assert_eq(ExplosionLod.envelope(life, life), 0.0)
	assert_gt(ExplosionLod.flash_s(8.0e12), life)
