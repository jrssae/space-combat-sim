extends GutTest
## A squadron Starfury's way from its hand-off to its slot (M8-T03, D81): it starts with the hand-off state, ends on the slot at
## rest with the formation's heading, never dips back inside the drum, goes round the side away from the spine, lights its mains after the flip
## and its retros last.

const PIVOT := Vector3(0.0, 0.0, -1000.0)
const DRUM_R: float = 244.5


# A hand-off at `angle_deg` on the drum: nose out, the rail's speed out plus the drum's turn.
func _handoff(angle_deg: float) -> Dictionary:
	var a: float = deg_to_rad(angle_deg)
	var out := Vector3(cos(a), sin(a), 0.0)
	var tangent := Vector3(-sin(a), cos(a), 0.0)
	var basis := Basis.looking_at(out, Vector3.FORWARD)
	return {"transform": Transform3D(basis, PIVOT + out * DRUM_R + Vector3(0.0, 0.0, -890.0)),
			"velocity": out * 61.0 + tangent * (0.148 * DRUM_R)}


func _slot() -> Transform3D:
	var up := Vector3(0.0, -1.0, 0.0)
	return Transform3D(Basis(up.cross(Vector3.BACK), up, Vector3.BACK), PIVOT + up * 650.0 + Vector3(-120.0, 0.0, -870.0))


func test_it_starts_with_the_hand_off_and_ends_on_the_slot_at_rest() -> void:
	var start: Dictionary = _handoff(30.0)
	var path := FormUpPath.create(start, _slot(), PIVOT, 90.0)
	var s0: Dictionary = path.state_at(0.0)
	assert_almost_eq((s0["transform"] as Transform3D).origin, (start["transform"] as Transform3D).origin, Vector3.ONE * 1e-3)
	assert_almost_eq(s0["velocity"] as Vector3, start["velocity"] as Vector3, Vector3.ONE * 1e-3, "no jump in velocity at the release")
	assert_true((s0["transform"] as Transform3D).basis.is_equal_approx((start["transform"] as Transform3D).basis), "nose out still")
	for t: float in [path.duration_s, path.duration_s + 5.0]:
		var end: Dictionary = path.state_at(t)
		assert_almost_eq((end["transform"] as Transform3D).origin, _slot().origin, Vector3.ONE * 1e-2, "on the slot")
		assert_eq(end["velocity"], Vector3.ZERO, "at rest against the station")
		assert_eq(end["angular"], Vector3.ZERO)
		var nose: Vector3 = -(end["transform"] as Transform3D).basis.z
		assert_almost_eq(nose, Vector3.FORWARD, Vector3.ONE * 1e-3, "flipped to the formation's heading")
	assert_true(path.done(path.duration_s))
	assert_false(path.done(path.duration_s - 0.1))


func test_the_velocity_is_the_rate_of_the_position() -> void:
	var path := FormUpPath.create(_handoff(200.0), _slot(), PIVOT, 90.0)
	var dt: float = 1e-3
	for t: float in [0.5, 2.0, 4.0, 6.0]:
		var a: Vector3 = (path.state_at(t - dt)["transform"] as Transform3D).origin
		var b: Vector3 = (path.state_at(t + dt)["transform"] as Transform3D).origin
		assert_almost_eq(path.state_at(t)["velocity"] as Vector3, (b - a) / (2.0 * dt), Vector3.ONE * 0.05, "at %.1f s" % t)


func test_it_never_dips_inside_the_drum_and_goes_round_away_from_the_spine() -> void:
	# Released all round the drum (the spine's sector, around 90 degrees, is where no drop starts), it never crosses 90 degrees.
	for angle: float in [-60.0, -10.0, 20.0, 150.0, 200.0, 250.0, 320.0]:
		var path := FormUpPath.create(_handoff(angle), _slot(), PIVOT, 90.0)
		for i: int in 71:
			var p: Vector3 = (path.state_at(float(i) * 0.1)["transform"] as Transform3D).origin - PIVOT
			var r: float = Vector2(p.x, p.y).length()
			assert_gt(r, DRUM_R - 1.0, "released at %.0f deg: outside the drum at %.1f s (r %.1f)" % [angle, float(i) * 0.1, r])
			var at: float = fposmod(rad_to_deg(atan2(p.y, p.x)), 360.0)
			assert_false(at > 80.0 and at < 100.0 and r < 500.0, "released at %.0f deg: under the spine at %.1f s" % [angle, float(i) * 0.1])


func test_the_mains_light_after_the_flip_and_the_retros_last() -> void:
	var path := FormUpPath.create(_handoff(10.0), _slot(), PIVOT, 90.0, 7.0, 2.5, 3.0, 2.0)
	assert_eq(path.state_at(0.5)["main"], 0.0, "cold while it flips")
	assert_eq(path.state_at(2.6)["main"], 1.0, "the mains light as the flip ends")
	assert_eq(path.state_at(4.0)["main"], 1.0)
	assert_eq(path.state_at(4.0)["retro"], 0.0)
	assert_eq(path.state_at(6.0)["retro"], 1.0)
	assert_eq(path.state_at(7.5)["retro"], 0.0, "on the slot: everything cold")
	assert_gt((path.state_at(1.0)["angular"] as Vector3).length(), 0.05, "turning in the flip")
	assert_eq(path.state_at(3.0)["angular"], Vector3.ZERO, "the flip is over")
