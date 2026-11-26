extends GutTest
## The numbers and decisions of docking at a ship (M10-T53, Q84): `ShipDockRules`, and the lane autopilot's nose direction and
## fine seek that a craft backing onto a collar needs (`DockAutopilot`).


func _capability() -> ShipCapability:
	var cap := ShipCapability.new()
	cap.a_main = 8.0
	cap.a_retro = 4.0
	cap.a_rcs = Vector2(3.0, 3.0)
	cap.rate_max_rad = Vector3(0.6, 0.6, 0.8)
	return cap


func test_a_hulls_options_lie_over_the_defaults() -> void:
	var liner: Dictionary = ShipDockRules.options(&"ea_asimov")
	for key: String in ShipDockRules.DEFAULTS:
		assert_true(liner.has(key), "every option is filled in: %s" % key)
	assert_eq((liner["keep_out"] as Array).size(), 2, "the liner's sphere and spine")
	assert_false(liner.has("_doc"), "a note in the data is not an option")
	var other: Dictionary = ShipDockRules.options(&"no_such_hull")
	assert_eq((other["keep_out"] as Array).size(), 0)
	assert_eq(float(other["gap_m"]), float(liner["gap_m"]))


func test_the_way_to_a_lane_goes_round_the_hull() -> void:
	var opts: Dictionary = ShipDockRules.options(&"ea_asimov")
	var goal := Vector3(56.0, -43.0, -405.0)
	var way: DockKeepOut = ShipDockRules.keep_out(opts, goal)
	assert_eq(way.inside(goal), -1, "the lane starts clear of the hull's boxes")
	assert_eq(way.next_target(Vector3(60.0, -40.0, -900.0)), goal, "from ahead of the bow, straight there")
	var from_astern := Vector3(0.0, 0.0, 900.0)
	var first: Vector3 = way.next_target(from_astern)
	assert_ne(first, goal, "from astern the sphere is in the way")
	assert_false(way.blocked(from_astern, first), "its first turning point is in the clear")
	assert_lt(way.distance_left(from_astern), 3000.0, "and a way round is known")


func test_no_docking_while_the_ship_is_under_way() -> void:
	var opts: Dictionary = ShipDockRules.options(&"ea_asimov")
	assert_false(ShipDockRules.under_way(0.5, opts), "holding station (Q84)")
	assert_true(ShipDockRules.under_way(40.0, opts))


func test_a_craft_turns_onto_the_lane_once_it_is_there_and_slow() -> void:
	var opts: Dictionary = ShipDockRules.options(&"")
	assert_true(ShipDockRules.joins(8.0, 2.0, opts))
	assert_false(ShipDockRules.joins(60.0, 2.0, opts), "not there yet")
	assert_false(ShipDockRules.joins(8.0, 30.0, opts), "still too fast")


func test_it_backs_down_the_lane_only_once_it_points_as_it_will_lie() -> void:
	var opts: Dictionary = ShipDockRules.options(&"")
	assert_true(ShipDockRules.aligned(Basis.IDENTITY, Vector3.FORWARD, Vector3.UP, opts))
	assert_false(ShipDockRules.aligned(Basis(Vector3.UP, deg_to_rad(20.0)), Vector3.FORWARD, Vector3.UP, opts), "nose 20 degrees off")
	assert_false(ShipDockRules.aligned(Basis(Vector3.BACK, deg_to_rad(40.0)), Vector3.FORWARD, Vector3.UP, opts), "rolled 40 degrees")
	assert_eq(ShipDockRules.lane_speed(150.0, false, 8.0, opts), 0.0, "it waits where it is until it is lined up")
	assert_eq(ShipDockRules.lane_speed(150.0, true, 8.0, opts), float(opts["lane_mps"]), "then down the lane")


func test_the_lane_ends_at_a_walk_and_eases_onto_the_lock() -> void:
	var opts: Dictionary = ShipDockRules.options(&"")
	var final_mps: float = float(opts["final_mps"])
	var last: float = INF
	for to_go: float in [200.0, 60.0, 30.0, 26.0, 25.0, 10.0, 2.0, 0.5, 0.1]:
		var speed: float = ShipDockRules.lane_speed(to_go, true, 0.8, opts)
		assert_lte(speed, last, "never faster nearer in (%.1f m)" % to_go)
		assert_gt(speed, 0.0, "it keeps closing (%.1f m)" % to_go)
		last = speed
	assert_eq(ShipDockRules.lane_speed(25.0, true, 8.0, opts), final_mps, "the last metres at a walk")
	assert_almost_eq(ShipDockRules.lane_speed(1.0, true, 8.0, opts), 0.5, 1e-6, "easing onto the lock")
	assert_lt(ShipDockRules.lane_speed(-2.0, true, 8.0, opts), 0.0, "past its place it comes back out")
	assert_gte(ShipDockRules.lane_speed(-50.0, true, 8.0, opts), -final_mps)


func test_the_mains_brake_a_craft_that_backs_in() -> void:
	var cap: ShipCapability = _capability()
	assert_eq(ShipDockRules.brake_mps2(-1.0, cap), cap.a_main, "nose out: the mains stop it")
	assert_eq(ShipDockRules.brake_mps2(1.0, cap), cap.a_retro, "nose in: the retros")
	var careful: ShipCapability = ShipDockRules.cautious(_capability(), ShipDockRules.options(&""))
	assert_almost_eq(careful.a_main, 4.0, 1e-6, "the approach plans with half its mains")


func test_a_craft_is_taken_once_it_is_on_its_place_and_slow() -> void:
	var opts: Dictionary = ShipDockRules.options(&"")
	assert_true(ShipDockRules.captured(Vector3(0.1, 0.2, -0.3), 0.4, opts))
	assert_false(ShipDockRules.captured(Vector3(0.0, 1.5, 0.0), 0.4, opts), "off to the side")
	assert_false(ShipDockRules.captured(Vector3(0.1, 0.0, 0.0), 9.0, opts), "too fast")


func test_the_lane_holds_the_nose_out_while_the_craft_backs_in() -> void:
	var cap: ShipCapability = _capability()
	# At rest on the axis, nose 30 degrees off the way out, asked to back in at 1.5 m/s.
	var basis := Basis(Vector3.UP, deg_to_rad(30.0))
	var turning: FlightCommand = DockAutopilot.lane(Vector3.ZERO, Vector3.ZERO, basis, Vector3.ZERO, Vector3.BACK, 1.5, cap, 0.0,
			Vector3.FORWARD, true)
	assert_ne(turning.rot.y, 0.0, "it turns its nose onto the way out")
	var plain: FlightCommand = DockAutopilot.lane(Vector3.ZERO, Vector3.ZERO, Basis.IDENTITY, Vector3.ZERO, Vector3.BACK, 1.5, cap, 0.0,
			Vector3.FORWARD, true)
	assert_almost_eq(plain.rot.y, 0.0, 1e-6, "lined up: no turn")
	assert_gt(plain.retro_left, 0.0, "the retros push it backwards down the lane")
	assert_eq(plain.main_left, 0.0)
	var nose_in: FlightCommand = DockAutopilot.lane(Vector3.ZERO, Vector3.ZERO, Basis.IDENTITY, Vector3.ZERO, Vector3.FORWARD, 20.0, cap)
	assert_gt(nose_in.main_left, 0.0, "without a nose of its own the lane flies nose in, as the station's (M8-T06)")


func test_the_fine_seek_sheds_what_the_coarse_one_leaves() -> void:
	var cap: ShipCapability = _capability()
	var drift := Vector3(0.4, 0.0, 0.3)
	var coarse: Dictionary = PilotSteering.seek(drift, Vector3.ZERO, Basis.IDENTITY, cap, PilotSteering.HORIZON_S, true)
	assert_eq(coarse["strafe"], Vector2.ZERO, "under 1 m/s the pilots' seek coasts")
	var fine: Dictionary = DockAutopilot.fine_seek(drift, Vector3.ZERO, Basis.IDENTITY, cap)
	assert_lt((fine["strafe"] as Vector2).x, 0.0, "the fine one pushes back against the drift")
	assert_gt(float(fine["main"]), 0.0, "and against the drift astern")
	assert_eq(float(fine["retro"]), 0.0)
