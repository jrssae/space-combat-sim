extends GutTest
## A ship's passage through a jump vortex's funnel (M6-T22), the pure rules: the funnel's shape as the shader draws it, the scale
## law (the ship keeps its share of the funnel's width and fits inside it, down to the black ring at the base; a capital shrinks
## more than a fighter), where an arriving ship starts and leaves, how long a passage takes, and the ring's flash.

const GATE := Vector2(1198.0, 753.9)  # the gate's mouth: half width, half height


func _gate() -> VortexFit:
	return VortexFit.new(GATE.y, 1200.0, 0.0, GATE.x)


func test_the_funnel_shape_is_the_shaders() -> void:
	assert_almost_eq(VortexTransit.depth_share_at(0.0), 1.0, 1e-5, "the axis is at the base")
	assert_almost_eq(VortexTransit.depth_share_at(1.0), 0.0, 1e-5, "the rim is at the mouth")
	for s: float in [0.05, 0.24, 0.4, 0.6, 0.8, 0.95]:
		assert_almost_eq(VortexTransit.radius_share_at(VortexTransit.depth_share_at(s)), s, 1e-4, "the inverse at %.2f" % s)
	assert_almost_eq(VortexTransit.depth_share_at(VortexTransit.RING_SHARE), 0.82, 0.01, "the ring sits 82 % of the way down")


func test_a_ship_is_whole_at_the_mouth_and_in_front_of_it() -> void:
	var fit: VortexFit = _gate()
	assert_eq(VortexTransit.scale_at(fit, 0.0, 12.0), 1.0)
	assert_eq(VortexTransit.scale_at(fit, -500.0, 12.0), 1.0)
	var point := VortexFit.for_ship(12.0)
	assert_eq(VortexTransit.scale_at(point, 0.0, 12.0), 1.0, "a point is sized for its ship")


func test_every_ship_shrinks_with_the_funnel_down_to_the_ring() -> void:
	var fit: VortexFit = _gate()
	var last: float = 1.0
	for i: int in range(1, 41):
		var depth: float = fit.depth_m * float(i) / 40.0
		var s: float = VortexTransit.scale_at(fit, depth, 12.0)
		assert_true(s <= last + 1e-6, "never grows going down (%.0f m)" % depth)
		last = s
	assert_almost_eq(VortexTransit.ring_scale(fit, 12.0), VortexTransit.RING_SHARE, 1e-4,
			"a fighter at the gate keeps its share of the width: the ring's share of the mouth")
	var point := VortexFit.for_ship(12.0)
	assert_almost_eq(VortexTransit.ring_scale(point, 12.0), VortexTransit.RING_SHARE, 1e-4, "the same at its own point")


func test_a_capital_shrinks_more_and_fits_inside_the_ring() -> void:
	var fit: VortexFit = _gate()
	var capital_r: float = 700.0
	var at_ring: float = VortexTransit.ring_scale(fit, capital_r)
	assert_lt(at_ring, VortexTransit.ring_scale(fit, 12.0), "a capital shrinks more than a fighter")
	assert_almost_eq(at_ring * capital_r, VortexTransit.MARGIN * VortexTransit.ring_radius_m(fit), 1e-3,
			"it fits inside the ring with the margin")
	for i: int in 41:
		var depth: float = fit.depth_m * float(i) / 40.0
		var s: float = VortexTransit.scale_at(fit, depth, capital_r)
		assert_true(s * capital_r <= VortexTransit.MARGIN * VortexTransit.inner_radius_m(fit, depth) + 1e-3,
				"never wider than the funnel allows (%.0f m)" % depth)


func test_a_ship_too_wide_for_the_mouth_shrinks_in_smoothly_in_front_of_it() -> void:
	var fit: VortexFit = _gate()
	var r: float = 900.0  # wider than the mouth's half height allows
	var at_mouth: float = VortexTransit.scale_at(fit, 0.0, r)
	assert_lt(at_mouth, 1.0)
	assert_almost_eq(VortexTransit.scale_at(fit, -1.0, r), at_mouth, 0.005, "no jump at the mouth")
	assert_almost_eq(VortexTransit.scale_at(fit, 1.0, r), at_mouth, 0.005)
	assert_eq(VortexTransit.scale_at(fit, -(r / VortexTransit.MARGIN), r), 1.0, "whole far enough in front")


func test_an_arriving_ship_starts_on_the_ring_and_leaves_at_its_place_in_the_mouth() -> void:
	var fit: VortexFit = _gate()
	var start: Vector3 = VortexTransit.arrival_start(fit, Vector2(100.0, -50.0))
	assert_almost_eq(start.z, fit.depth_m, 1e-4, "on the base")
	assert_almost_eq(Vector2(start.x, start.y).length(), Vector2(100.0, -50.0).length() * VortexTransit.RING_SHARE, 1e-3,
			"its offset shrunk to the ring")
	assert_eq(VortexTransit.arrival_exit(fit, Vector2(100.0, -50.0)), Vector3(100.0, -50.0, 0.0))
	var outside: Vector3 = VortexTransit.arrival_exit(fit, Vector2(0.0, 5000.0))
	assert_true(fit.contains(Vector2(outside.x, outside.y)), "a place outside the rim comes out at its edge")
	var in_ring: Vector3 = VortexTransit.arrival_start(fit, Vector2(0.0, 5000.0))
	assert_lt(Vector2(in_ring.x, in_ring.y).length(), VortexTransit.ring_radius_m(fit) + 1e-3, "and starts inside the ring")


func test_a_passage_takes_between_its_shortest_and_longest_time() -> void:
	assert_almost_eq(VortexTransit.transit_speed(1200.0, 200.0), 200.0, 1e-4, "a gate's arrival flies at its own speed")
	assert_almost_eq(VortexTransit.transit_speed(96.0, 200.0), 96.0 / VortexTransit.MIN_TRANSIT_S, 1e-4,
			"a shallow point is crossed no faster than the shortest passage")
	assert_almost_eq(VortexTransit.transit_speed(96.0, 0.0), 96.0 / VortexTransit.MAX_TRANSIT_S, 1e-4,
			"a ship at rest still comes out")


func test_a_departing_ship_is_through_when_its_nose_touches_the_base() -> void:
	var fit: VortexFit = _gate()
	assert_false(VortexTransit.reached_base(fit, 1100.0, 5.0))
	assert_true(VortexTransit.reached_base(fit, 1196.0, 5.0))
	assert_true(VortexTransit.reached_base(fit, 1300.0, 0.0), "or past it")


func test_the_lateral_radius_is_across_the_line_of_flight() -> void:
	var long_box := AABB(Vector3(-3.0, -4.0, -20.0), Vector3(6.0, 8.0, 40.0))
	assert_almost_eq(VortexTransit.lateral_radius(long_box), 5.0, 1e-4, "its length does not count")


func test_the_ring_flash_comes_up_fast_and_dies_away() -> void:
	assert_eq(VortexTransit.flash_level(-0.1), 0.0)
	assert_almost_eq(VortexTransit.flash_level(VortexTransit.FLASH_RISE_S), 1.0, 1e-4, "the peak")
	assert_almost_eq(VortexTransit.flash_level(VortexTransit.FLASH_RISE_S + VortexTransit.FLASH_FALL_S * 0.5), 0.5, 1e-4)
	assert_eq(VortexTransit.flash_level(VortexTransit.FLASH_RISE_S + VortexTransit.FLASH_FALL_S), 0.0, "out")
	assert_almost_eq(VortexTransit.flash_radius_m(_gate()), VortexTransit.FLASH_RING_SIZE * VortexTransit.ring_radius_m(_gate()),
			1e-4, "sized to the ring")
