extends GutTest
## RadarModel (M2-T08, AC10b): contacts on the radar sphere by bearing, scaled linearly to 5 km and logarithmically beyond,
## dropped past the 25 km sensor range, coloured by faction, ordered for drawing.

const TOL: float = 1e-6


func _dot(offset_body: Vector3, faction: StringName = Factions.RAIDERS, viewer: StringName = Factions.EARTH_ALLIANCE) -> RadarModel.Dot:
	return RadarModel.dot_for(1, offset_body, faction, false, Vector3.ZERO, Basis.IDENTITY, viewer)


func test_the_six_bearings() -> void:
	var r: float = RadarModel.radius_for_range(1000.0)
	var ahead: Vector3 = _dot(Vector3(0.0, 0.0, -1000.0)).point
	var astern: Vector3 = _dot(Vector3(0.0, 0.0, 1000.0)).point
	var above: Vector3 = _dot(Vector3(0.0, 1000.0, 0.0)).point
	var below: Vector3 = _dot(Vector3(0.0, -1000.0, 0.0)).point
	var right: Vector3 = _dot(Vector3(1000.0, 0.0, 0.0)).point
	var left: Vector3 = _dot(Vector3(-1000.0, 0.0, 0.0)).point
	assert_almost_eq(ahead, Vector3(0.0, r, 0.0), Vector3.ONE * TOL, "ahead: up the screen")
	assert_almost_eq(astern, Vector3(0.0, -r, 0.0), Vector3.ONE * TOL)
	assert_almost_eq(above, Vector3(0.0, 0.0, r), Vector3.ONE * TOL, "above: toward the viewer")
	assert_almost_eq(below, Vector3(0.0, 0.0, -r), Vector3.ONE * TOL)
	assert_almost_eq(right, Vector3(r, 0.0, 0.0), Vector3.ONE * TOL)
	assert_almost_eq(left, Vector3(-r, 0.0, 0.0), Vector3.ONE * TOL)


func test_bearing_follows_the_ships_orientation() -> void:
	# A ship turned 90 degrees left (nose along world -X): a contact at world -X is dead ahead.
	var turned := Basis(Vector3.UP, deg_to_rad(90.0))
	var dot: RadarModel.Dot = RadarModel.dot_for(1, Vector3(-500.0, 0.0, 0.0), Factions.RAIDERS, false, Vector3.ZERO, turned, Factions.EARTH_ALLIANCE)
	assert_almost_eq(dot.point.normalized(), Vector3(0.0, 1.0, 0.0), Vector3.ONE * TOL)


func test_bearing_is_taken_from_the_ships_position() -> void:
	var dot: RadarModel.Dot = RadarModel.dot_for(1, Vector3(100.0, 0.0, -2000.0), Factions.RAIDERS, false, Vector3(100.0, 0.0, -1000.0), Basis.IDENTITY, Factions.EARTH_ALLIANCE)
	assert_almost_eq(dot.range_m, 1000.0, 1e-6)
	assert_almost_eq(dot.point.x, 0.0, TOL)


func test_range_is_linear_to_5_km() -> void:
	assert_eq(RadarModel.radius_for_range(0.0), 0.0)
	assert_almost_eq(RadarModel.radius_for_range(2500.0), 0.5 * RadarModel.LINEAR_RADIUS, TOL)
	assert_almost_eq(RadarModel.radius_for_range(5000.0), RadarModel.LINEAR_RADIUS, TOL)
	assert_almost_eq(RadarModel.radius_for_range(1000.0) * 2.0, RadarModel.radius_for_range(2000.0), TOL, "linear")


func test_range_is_logarithmic_beyond_5_km_up_to_25() -> void:
	var at_5: float = RadarModel.radius_for_range(5000.0)
	var at_25: float = RadarModel.radius_for_range(25000.0)
	assert_almost_eq(at_25, 1.0, TOL, "the sensor limit is the sphere's edge")
	var geometric: float = RadarModel.radius_for_range(5000.0 * sqrt(5.0))  # the geometric mean of 5 and 25 km
	assert_almost_eq(geometric, 0.5 * (at_5 + at_25), 1e-9, "equal ratios, equal steps")
	assert_lt(RadarModel.radius_for_range(10000.0), RadarModel.radius_for_range(20000.0))
	assert_almost_eq(RadarModel.radius_for_range(1.0e6), 1.0, TOL, "clamped")


func test_contacts_beyond_the_sensor_range_are_dropped() -> void:
	assert_not_null(_dot(Vector3(0.0, 0.0, -24999.0)))
	assert_null(_dot(Vector3(0.0, 0.0, -25001.0)))


func test_colour_follows_the_relation() -> void:
	assert_eq(_dot(Vector3(0.0, 0.0, -100.0), Factions.RAIDERS).color, Factions.HOSTILE_COLOR)
	assert_eq(_dot(Vector3(0.0, 0.0, -100.0), Factions.EARTH_ALLIANCE).color, Factions.FRIENDLY_COLOR)
	assert_eq(_dot(Vector3(0.0, 0.0, -100.0), Factions.NEUTRAL).color, Factions.NEUTRAL_COLOR)
	assert_eq(_dot(Vector3(0.0, 0.0, -100.0), &"who_knows").color, Factions.NEUTRAL_COLOR, "unknown reads yellow")


func test_stalk_foot_is_the_point_on_the_equatorial_plane() -> void:
	var dot: RadarModel.Dot = _dot(Vector3(300.0, 400.0, -500.0))
	assert_eq(dot.foot.z, 0.0)
	assert_eq(dot.foot.x, dot.point.x)
	assert_eq(dot.foot.y, dot.point.y)
	assert_true(dot.above)
	assert_false(_dot(Vector3(300.0, -400.0, -500.0)).above)


func test_dots_are_drawn_far_to_near_with_the_selection_last() -> void:
	var infos: Array[TargetInfo] = [
		TargetInfo.new(3, "NEAR", Factions.RAIDERS, Vector3(0.0, 0.0, -500.0)),
		TargetInfo.new(1, "FAR", Factions.RAIDERS, Vector3(0.0, 0.0, -9000.0)),
		TargetInfo.new(2, "MID", Factions.RAIDERS, Vector3(0.0, 0.0, -3000.0)),
		TargetInfo.new(4, "GONE", Factions.RAIDERS, Vector3(0.0, 0.0, -90000.0)),
	]
	var dots: Array[RadarModel.Dot] = RadarModel.dots(infos, 1, Vector3.ZERO, Basis.IDENTITY, Factions.EARTH_ALLIANCE)
	assert_eq(dots.size(), 3, "the 90 km one is out of range")
	assert_eq([dots[0].id, dots[1].id, dots[2].id], [2, 3, 1], "far to near, then the selected (id 1) last")
	assert_true(dots[2].selected)


func test_the_screen_mapping_puts_the_nose_up_and_the_right_on_the_right() -> void:
	var centre := Vector2(500.0, 500.0)
	var nose: Vector2 = RadarModel.to_screen(Vector3(0.0, 1.0, 0.0), centre, 100.0)
	var right: Vector2 = RadarModel.to_screen(Vector3(1.0, 0.0, 0.0), centre, 100.0)
	var origin: Vector2 = RadarModel.to_screen(Vector3.ZERO, centre, 100.0)
	assert_eq(origin, centre)
	assert_lt(nose.y, centre.y, "up the screen")
	assert_almost_eq(nose.x, centre.x, 1e-6)
	assert_gt(right.x, centre.x)
	var above: Vector2 = RadarModel.to_screen(Vector3(0.0, 0.0, 1.0), centre, 100.0)
	var below: Vector2 = RadarModel.to_screen(Vector3(0.0, 0.0, -1.0), centre, 100.0)
	assert_lt(above.y, below.y, "above the ship's plane draws higher than below it")


func test_the_unit_sphere_stays_inside_its_pixel_radius_roughly() -> void:
	for i: int in 24:
		var a: float = TAU * float(i) / 24.0
		var p: Vector2 = RadarModel.to_screen(Vector3(cos(a), sin(a), 0.0), Vector2.ZERO, 100.0)
		assert_lt(p.length(), 100.0 * 1.25, "the slow perspective only stretches a little")
