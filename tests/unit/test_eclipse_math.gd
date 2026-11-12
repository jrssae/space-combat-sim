extends GutTest
## How much of the star's disc a planet leaves showing (M6-T10, AC7): the factor on the key light.

const PLANET_RADIUS_M: float = 4.78e6
const STAR_RADIUS_M: float = 5.11e8
const STAR_DISTANCE_M: float = 8.976e10


func _at(x: float, y: float, z: float) -> PackedFloat64Array:
	return PackedFloat64Array([x, y, z])


# The lit part seen from a point 27 500 km from the planet's centre, `angle_deg` round from the line behind the planet.
func _lit_at(angle_deg: float) -> float:
	var angle: float = deg_to_rad(angle_deg)
	var camera: PackedFloat64Array = _at(2.75e7 * cos(angle), 2.75e7 * sin(angle), 0.0)
	var to_planet: PackedFloat64Array = _at(-camera[0], -camera[1], 0.0)
	var to_sun: PackedFloat64Array = _at(-STAR_DISTANCE_M - camera[0], -camera[1], 0.0)
	return EclipseMath.lit_fraction(to_sun, STAR_RADIUS_M, to_planet, PLANET_RADIUS_M)


func test_behind_the_planet_the_key_light_is_out() -> void:
	assert_eq(_lit_at(0.0), 0.0, "the station at epoch 0: the middle of the shadow")
	assert_eq(_lit_at(9.0), 0.0, "still in the umbra")


func test_beside_and_in_front_of_the_planet_the_light_is_whole() -> void:
	assert_eq(_lit_at(11.0), 1.0, "past the planet's edge")
	assert_eq(_lit_at(90.0), 1.0)
	assert_eq(_lit_at(180.0), 1.0, "the planet behind the camera")


func test_the_edge_of_the_shadow_fades() -> void:
	# The planet's limb crosses the star's 0.65 degree disc between about 9.67 and 10.33 degrees.
	var last: float = 0.0
	for step: int in 41:
		var lit: float = _lit_at(9.6 + 0.02 * step)
		assert_gte(lit, last, "never darker further out (%s)" % step)
		last = lit
	assert_eq(last, 1.0, "whole at the end")
	assert_almost_eq(_lit_at(rad_to_deg(asin(PLANET_RADIUS_M / 2.75e7))), 0.5, 0.02, "half the disc when the limb crosses its centre")


func test_a_body_behind_the_star_hides_nothing() -> void:
	var lit: float = EclipseMath.lit_fraction(_at(1.0e10, 0.0, 0.0), STAR_RADIUS_M, _at(2.0e10, 0.0, 0.0), PLANET_RADIUS_M)
	assert_eq(lit, 1.0)


func test_a_small_body_in_front_takes_its_share() -> void:
	# A disc half the star's angular radius, centred on it, hides a quarter.
	var lit: float = EclipseMath.lit_fraction(_at(1.0e10, 0.0, 0.0), 1.0e8, _at(1.0e9, 0.0, 0.0), 5.0e6)
	assert_almost_eq(lit, 0.75, 1.0e-3)


func test_degenerate_inputs_leave_the_light_on() -> void:
	assert_eq(EclipseMath.lit_fraction(_at(0.0, 0.0, 0.0), STAR_RADIUS_M, _at(1.0, 0.0, 0.0), 1.0), 1.0, "no star distance")
	assert_eq(EclipseMath.lit_fraction(PackedFloat64Array(), STAR_RADIUS_M, _at(1.0, 0.0, 0.0), 1.0), 1.0, "no star")
