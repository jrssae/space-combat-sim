extends GutTest
## AvoidanceMath (M3-T05, AC5, architecture §16 D33): the pure collision-avoidance filter on a brain's desired velocity.
## Head-on, crossing and overtaking threats get a sideways dodge that lifts the closest approach of the filtered velocity
## above the sum of radii plus the margin; opening, distant and wide contacts get none; matched velocities (formation) only
## push apart inside the margin; a dead-centre tie breaks by seed; nothing is ever NaN.

const OWN_RADIUS: float = 10.0
const CONTACT_RADIUS: float = 10.0
const SEED: int = 7


func _cap() -> ShipCapability:
	var cap := ShipCapability.new()
	cap.a_main = 30.0
	cap.a_retro = 15.0
	cap.a_rcs = Vector2(10.0, 10.0)
	cap.rate_max_rad = Vector3(deg_to_rad(60.0), deg_to_rad(60.0), deg_to_rad(90.0))
	return cap


func _contact(position: Vector3, velocity: Vector3 = Vector3.ZERO, radius: float = CONTACT_RADIUS) -> Contact:
	var c := Contact.new()
	c.id = 1
	c.position = position
	c.velocity = velocity
	c.bounding_radius = radius
	c.is_ship = true
	return c


func _reach(radius: float = CONTACT_RADIUS) -> float:
	return OWN_RADIUS + radius + AvoidanceMath.MARGIN_M


## The filter for one contact, own ship at the origin flying `v` (and wanting `v`).
func _filter_one(v: Vector3, c: Contact, seed_value: int = SEED) -> Dictionary:
	var contacts: Array[Contact] = [c]
	return AvoidanceMath.filter(Vector3.ZERO, v, OWN_RADIUS, contacts, v, _cap(), seed_value)


## How close the own ship (at the origin, flying `v`) passes the contact, over all future time.
func _miss(v: Vector3, c: Contact) -> float:
	return AvoidanceMath.closest_approach(Vector3.ZERO - c.position, v - c.velocity, INF)


func _assert_finite(v: Vector3, why: String) -> void:
	assert_true(is_finite(v.x) and is_finite(v.y) and is_finite(v.z), "%s: %s is finite" % [why, v])


# --- closest approach -----------------------------------------------------------------------------------------------


func test_closest_approach_is_the_distance_at_the_closest_time_within_the_horizon() -> void:
	# 100 m ahead, 3 m to the side, closing at 50 m/s: closest after 2 s, 3 m off.
	assert_almost_eq(AvoidanceMath.closest_approach(Vector3(3.0, 0.0, -100.0), Vector3(0.0, 0.0, 50.0), INF), 3.0, 1e-4)
	assert_almost_eq(AvoidanceMath.closest_approach(Vector3(3.0, 0.0, -100.0), Vector3(0.0, 0.0, 50.0), 1.0),
			Vector3(3.0, 0.0, -50.0).length(), 1e-3, "cut at the horizon")
	assert_almost_eq(AvoidanceMath.closest_approach(Vector3(0.0, 0.0, -100.0), Vector3(0.0, 0.0, -50.0), INF), 100.0, 1e-4,
			"opening: now is the closest")
	assert_almost_eq(AvoidanceMath.closest_approach(Vector3(0.0, 40.0, 0.0), Vector3.ZERO, INF), 40.0, 1e-4, "no relative motion")


# --- dodges -----------------------------------------------------------------------------------------------------------


func test_head_on_produces_a_sideways_dodge_that_clears_the_margin() -> void:
	var v := Vector3(0.0, 0.0, -75.0)
	var c := _contact(Vector3(0.0, 0.0, -600.0), Vector3(0.0, 0.0, 75.0))
	assert_lt(_miss(v, c), 1e-3, "dead on: a collision")
	var r: Dictionary = _filter_one(v, c)
	var out: Vector3 = r["v_des"]
	assert_gt(_miss(out, c), _reach(), "the filtered velocity passes outside the radii plus the margin")
	assert_almost_eq((out - v).dot(Vector3.BACK), 0.0, 1e-3, "sideways: the closing speed is kept")
	assert_false(r["urgent"], "4 s out there is time to turn")


func test_the_dodge_goes_away_from_the_side_the_contact_passes_on() -> void:
	var v := Vector3(0.0, 0.0, -75.0)
	var right := _filter_one(v, _contact(Vector3(4.0, 0.0, -600.0), Vector3(0.0, 0.0, 75.0)))
	assert_lt(((right["v_des"] as Vector3) - v).x, 0.0, "it passes on the right: dodge left")
	var below := _filter_one(v, _contact(Vector3(0.0, -4.0, -600.0), Vector3(0.0, 0.0, 75.0)))
	assert_gt(((below["v_des"] as Vector3) - v).y, 0.0, "it passes below: dodge up")


func test_crossing_produces_a_dodge_that_clears_the_margin() -> void:
	# Both reach (0, 0, -400) after 4 s: the contact comes in from the right at 100 m/s.
	var v := Vector3(0.0, 0.0, -100.0)
	var c := _contact(Vector3(400.0, 0.0, -400.0), Vector3(-100.0, 0.0, 0.0))
	assert_lt(_miss(v, c), 1e-3)
	var out: Vector3 = _filter_one(v, c)["v_des"]
	assert_gt(_miss(out, c), _reach())


func test_overtaking_produces_a_dodge_that_clears_the_margin() -> void:
	# Catching a slower ship 60 m ahead at 20 m/s: 3 s to contact.
	var v := Vector3(0.0, 0.0, -120.0)
	var c := _contact(Vector3(0.0, 1.0, -60.0), Vector3(0.0, 0.0, -100.0))
	assert_lt(_miss(v, c), _reach())
	var out: Vector3 = _filter_one(v, c)["v_des"]
	assert_gt(_miss(out, c), _reach())


func test_a_static_prop_with_no_hull_is_avoided_by_own_radius_plus_margin() -> void:
	var v := Vector3(0.0, 0.0, -100.0)
	var buoy := _contact(Vector3(0.0, 0.0, -500.0), Vector3.ZERO, 0.0)
	buoy.is_ship = false
	var out: Vector3 = _filter_one(v, buoy)["v_des"]
	assert_gt(_miss(out, buoy), _reach(0.0))


func test_opening_distant_and_wide_contacts_leave_the_velocity_alone() -> void:
	var v := Vector3(0.0, 0.0, -75.0)
	var cases: Dictionary = {
		"opening (behind, flying away)": _contact(Vector3(0.0, 0.0, 100.0), Vector3(0.0, 0.0, 50.0)),
		"distant (beyond the horizon)": _contact(Vector3(0.0, 0.0, -4900.0), Vector3(0.0, 0.0, 75.0)),
		"wide (passes 100 m off)": _contact(Vector3(100.0, 0.0, -600.0), Vector3(0.0, 0.0, 75.0)),
	}
	for why: String in cases:
		var r: Dictionary = _filter_one(v, cases[why])
		assert_eq(r["v_des"], v, why)
		assert_false(r["urgent"], why)


func test_the_horizon_is_the_time_to_stop_but_at_least_4_s() -> void:
	var cap := _cap()
	var v := Vector3(0.0, 0.0, -150.0)
	# Closing at 150 m/s with 15 m/s^2 of retro: 10 s to stop. A collision 9 s out is a threat, 11 s out is not.
	var near: Array[Contact] = [_contact(Vector3(0.0, 0.0, -150.0 * 9.0))]
	var far: Array[Contact] = [_contact(Vector3(0.0, 0.0, -150.0 * 11.0))]
	assert_ne(AvoidanceMath.filter(Vector3.ZERO, v, OWN_RADIUS, near, v, cap, SEED)["v_des"], v, "9 s out")
	assert_eq(AvoidanceMath.filter(Vector3.ZERO, v, OWN_RADIUS, far, v, cap, SEED)["v_des"], v, "11 s out")
	# Slow: 10 m/s needs well under 4 s to stop, yet a collision 3.8 s out is still a threat.
	var slow := Vector3(0.0, 0.0, -10.0)
	var slow_near: Array[Contact] = [_contact(Vector3(0.0, 0.0, -_reach() - 3.0))]
	assert_ne(AvoidanceMath.filter(Vector3.ZERO, slow, OWN_RADIUS, slow_near, slow, cap, SEED)["v_des"], slow, "at least 4 s")


func test_the_dodge_is_against_the_desired_velocity_not_only_the_current_one() -> void:
	# Coasting sideways now, but the brain wants to fly straight at a buoy 400 m ahead: the wish is corrected.
	var buoy := _contact(Vector3(0.0, 0.0, -400.0), Vector3.ZERO, 2.0)
	var contacts: Array[Contact] = [buoy]
	var wanted := Vector3(0.0, 0.0, -100.0)
	var r: Dictionary = AvoidanceMath.filter(Vector3.ZERO, Vector3(50.0, 0.0, 0.0), OWN_RADIUS, contacts, wanted, _cap(), SEED)
	assert_gt(_miss(r["v_des"], buoy), _reach(2.0))


func test_urgent_when_the_closest_approach_is_too_close_to_turn() -> void:
	var v := Vector3(0.0, 0.0, -75.0)
	# 1 s out at 150 m/s closing: the turn alone (90 deg at 60 deg/s) takes longer.
	var r: Dictionary = _filter_one(v, _contact(Vector3(2.0, 0.0, -150.0), Vector3(0.0, 0.0, 75.0)))
	assert_true(r["urgent"])
	assert_ne(r["v_des"], v)


func test_several_threats_add_up() -> void:
	var v := Vector3(0.0, 0.0, -75.0)
	var a := _contact(Vector3(3.0, 0.0, -600.0), Vector3(0.0, 0.0, 75.0))
	var b := _contact(Vector3(0.0, 3.0, -500.0), Vector3(0.0, 0.0, 75.0))
	var both: Array[Contact] = [a, b]
	var out: Vector3 = AvoidanceMath.filter(Vector3.ZERO, v, OWN_RADIUS, both, v, _cap(), SEED)["v_des"]
	assert_lt((out - v).x, 0.0, "away from the first")
	assert_lt((out - v).y, 0.0, "and from the second")


# --- formation (matched velocities) ---------------------------------------------------------------------------------


func test_matched_velocities_outside_the_margin_are_left_alone() -> void:
	var v := Vector3(0.0, 0.0, -100.0)
	assert_eq(_filter_one(v, _contact(Vector3(50.0, 0.0, 0.0), v))["v_des"], v, "a wingman 50 m off")
	assert_eq(_filter_one(v, _contact(Vector3(50.0, 0.0, 0.0), v + Vector3(-1.0, 0.0, 0.0)))["v_des"], v,
			"and one drifting in at 1 m/s (slot keeping)")


func test_matched_velocities_inside_the_margin_push_apart_gently() -> void:
	var v := Vector3(0.0, 0.0, -100.0)
	var r: Dictionary = _filter_one(v, _contact(Vector3(25.0, 0.0, 0.0), v))
	var push: Vector3 = (r["v_des"] as Vector3) - v
	assert_lt(push.x, 0.0, "away from the wingman on the right")
	assert_almost_eq(push.normalized(), Vector3.LEFT, Vector3.ONE * 1e-4, "straight apart")
	assert_lt(push.length(), 10.0, "gently")
	assert_false(r["urgent"], "nobody is closing")


func test_inside_the_margin_and_closing_cancels_the_closing_speed_and_is_urgent() -> void:
	var v := Vector3(0.0, 0.0, -100.0)
	var r: Dictionary = _filter_one(v, _contact(Vector3(25.0, 0.0, 0.0), v + Vector3(-20.0, 0.0, 0.0)))
	var out: Vector3 = r["v_des"]
	assert_lt(out.x, -20.0, "more than the 20 m/s it closes at, away")
	assert_true(r["urgent"])


# --- ties and NaN ---------------------------------------------------------------------------------------------------


func test_a_dead_centre_tie_breaks_by_seed() -> void:
	var v := Vector3(0.0, 0.0, -100.0)
	var buoy := _contact(Vector3(0.0, 0.0, -500.0), Vector3.ZERO, 2.0)
	var a: Vector3 = (_filter_one(v, buoy, 1)["v_des"] as Vector3) - v
	var a_again: Vector3 = (_filter_one(v, buoy, 1)["v_des"] as Vector3) - v
	var b: Vector3 = (_filter_one(v, buoy, 2)["v_des"] as Vector3) - v
	assert_eq(a, a_again, "the same seed, the same dodge")
	assert_gt(a.length(), 0.1)
	assert_gt(b.length(), 0.1)
	assert_gt(a.normalized().distance_to(b.normalized()), 1e-3, "another seed, another side")
	assert_almost_eq(a.dot(Vector3.FORWARD), 0.0, 1e-3, "sideways")
	assert_gt(_miss(v + a, buoy), _reach(2.0))


func test_two_ships_dead_on_dodge_apart_whatever_their_seeds() -> void:
	# Each ship computes its own dodge; whatever the two seeds, the dodges must not cancel (at least 90 degrees apart).
	var va := Vector3(0.0, 0.0, -75.0)
	var vb := Vector3(0.0, 0.0, 75.0)
	var pa := Vector3.ZERO
	var pb := Vector3(0.0, 0.0, -600.0)
	var worst: float = -INF
	for seed_a: int in 25:
		for seed_b: int in 25:
			var seen_by_a: Array[Contact] = [_contact(pb, vb)]
			var seen_by_b: Array[Contact] = [_contact(pa, va)]
			var da: Vector3 = (AvoidanceMath.filter(pa, va, OWN_RADIUS, seen_by_a, va, _cap(), seed_a * 7919)["v_des"] as Vector3) - va
			var db: Vector3 = (AvoidanceMath.filter(pb, vb, OWN_RADIUS, seen_by_b, vb, _cap(), seed_b * 104729)["v_des"] as Vector3) - vb
			worst = maxf(worst, da.normalized().dot(db.normalized()))
	assert_lt(worst, 0.0, "the two dodges always open the gap (worst cosine %.3f)" % worst)


func test_degenerate_inputs_never_give_nan() -> void:
	var cap := _cap()
	var cases: Array[Dictionary] = [
		{"why": "same place, no motion", "own": Vector3.ZERO, "v": Vector3.ZERO, "c": _contact(Vector3.ZERO)},
		{"why": "same place, moving", "own": Vector3.ZERO, "v": Vector3(0.0, 0.0, -50.0), "c": _contact(Vector3.ZERO)},
		{"why": "vertical approach", "own": Vector3.ZERO, "v": Vector3(0.0, 80.0, 0.0), "c": _contact(Vector3(0.0, 400.0, 0.0))},
		{"why": "zero radii", "own": Vector3.ZERO, "v": Vector3(0.0, 0.0, -50.0), "c": _contact(Vector3(0.0, 0.0, -100.0), Vector3.ZERO, 0.0)},
		{"why": "alongside, about to pass", "own": Vector3.ZERO, "v": Vector3(0.0, 0.0, -100.0), "c": _contact(Vector3(1.0, 0.0, -36.0))},
		{"why": "exactly on the margin", "own": Vector3.ZERO, "v": Vector3(0.0, 0.0, -100.0), "c": _contact(Vector3(0.0, 0.0, -_reach() - 1.0))},
	]
	for case: Dictionary in cases:
		var contacts: Array[Contact] = [case["c"] as Contact]
		var r: Dictionary = AvoidanceMath.filter(case["own"], case["v"], OWN_RADIUS, contacts, case["v"], cap, SEED)
		_assert_finite(r["v_des"], case["why"])
	var none: Array[Contact] = []
	assert_eq(AvoidanceMath.filter(Vector3.ZERO, Vector3.ONE, OWN_RADIUS, none, Vector3.ONE, cap, SEED)["v_des"], Vector3.ONE,
			"no contacts")
