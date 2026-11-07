extends GutTest
## The explosion level of detail's maths (M4-T23, architecture §17.14): the full effect near, a reduced one between, a point
## flash far, the distances set by the blast's size; a far flash keeps a 1 px floor and its delivered light falls with the
## inverse square of distance below it, at 1 080 and at 2 160 lines; a capital's flash reads much farther than a fighter's.

const FOV_DEG: float = 70.0
const FIGHTER_KG: float = 2.0e4
const CARRIER_KG: float = 8.0e7


func _energy(mass_kg: float) -> float:
	return mass_kg * DestructionDirector.BLAST_J_PER_KG


func test_the_level_is_full_near_reduced_between_and_far_beyond_set_by_the_blast_size() -> void:
	var r: float = 6.0
	assert_eq(ExplosionLod.level(r, 100.0), ExplosionLod.Level.FULL)
	assert_eq(ExplosionLod.level(r, r * ExplosionLod.FULL_RADII * 1.5), ExplosionLod.Level.REDUCED)
	assert_eq(ExplosionLod.level(r, r * ExplosionLod.REDUCED_RADII * 1.5), ExplosionLod.Level.FAR)
	var big: float = 600.0
	assert_eq(ExplosionLod.level(big, r * ExplosionLod.REDUCED_RADII * 1.5), ExplosionLod.Level.FULL, "a capital's is full farther out")


func test_a_far_flash_keeps_a_one_pixel_floor_and_its_delivered_light_falls_by_the_inverse_square() -> void:
	var e: float = _energy(FIGHTER_KG)
	for lines: float in [1080.0, 2160.0]:
		var floor_m: float = ExplosionLod.floor_distance_m(e, lines, FOV_DEG)
		var at_floor: Vector2 = ExplosionLod.on_screen(e, floor_m, lines, FOV_DEG)
		assert_almost_eq(at_floor.x, 1.0, 1e-3, "%d lines: one pixel at the floor distance" % lines)
		assert_almost_eq(at_floor.y, ExplosionLod.peak(e), 1e-3, "at full brightness there")
		for d: float in [2.0 * floor_m, 4.0 * floor_m, 10.0 * floor_m]:
			var s: Vector2 = ExplosionLod.on_screen(e, d, lines, FOV_DEG)
			assert_eq(s.x, 1.0, "%d lines, %.0f m: never under a pixel" % [lines, d])
			var delivered: float = s.y * s.x * s.x
			var expected: float = ExplosionLod.peak(e) * pow(floor_m / d, 2.0)
			assert_almost_eq(delivered / expected, 1.0, 1e-3, "%d lines, %.0f m: the delivered light falls by the inverse square" % [lines, d])
		var near: Vector2 = ExplosionLod.on_screen(e, floor_m * 0.5, lines, FOV_DEG)
		assert_almost_eq(near.x, 2.0, 1e-3, "nearer than the floor it is its real size")
	assert_almost_eq(ExplosionLod.floor_distance_m(e, 2160.0, FOV_DEG) / ExplosionLod.floor_distance_m(e, 1080.0, FOV_DEG), 2.0, 1e-3,
			"at twice the lines the floor sits twice as far")


func test_a_capitals_flash_reads_much_farther_than_a_fighters() -> void:
	var fighter: float = ExplosionLod.visible_to_m(_energy(FIGHTER_KG), 1080.0, FOV_DEG)
	var carrier: float = ExplosionLod.visible_to_m(_energy(CARRIER_KG), 1080.0, FOV_DEG)
	gut.p("a flash reads to %.1f km (fighter) and %.0f km (carrier) at 1 080 lines" % [fighter / 1000.0, carrier / 1000.0])
	assert_between(fighter, 3000.0, 30000.0, "a fighter's death reads across a few km")
	assert_gt(carrier, 10.0 * fighter, "a capital's across tens of km")
	assert_gt(ExplosionLod.flash_radius_m(_energy(CARRIER_KG)), ExplosionLod.flash_radius_m(_energy(FIGHTER_KG)))
	assert_gt(ExplosionLod.flash_s(_energy(CARRIER_KG)), ExplosionLod.flash_s(_energy(FIGHTER_KG)), "and lasts longer")


func test_the_flash_rises_fast_and_fades_to_nothing_over_its_life() -> void:
	var e: float = _energy(FIGHTER_KG)
	var life: float = ExplosionLod.flash_s(e)
	assert_eq(ExplosionLod.envelope(0.0, life), 0.0)
	assert_almost_eq(ExplosionLod.envelope(ExplosionLod.RISE_S, life), 1.0, 1e-4)
	assert_lt(ExplosionLod.envelope(life * 0.5, life), 1.0)
	assert_eq(ExplosionLod.envelope(life, life), 0.0)
