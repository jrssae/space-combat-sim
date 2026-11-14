extends GutTest
## The station's traffic lanes (M7-T10, Q8 as refined): the docking lane matches the drum's turn from before the mouth and
## ends short of the airlock's wall; the freighter's lane turns short of the hold point, backs in nose away and leaves the
## way it came; the pods' path is the cargo bay's.

const SPIN: float = 0.148
const DRUM: Vector3 = Vector3(0.0, 0.0, -1000.0)


func _hardpoints() -> StationHardpoints:
	var h := StationHardpoints.new()
	h.spin_rad_s = SPIN
	h.main_docking_bay = {"main_docking_bay_approach": [Vector3(0, 0, -4050), Vector3(0, 0, -2850)],
			"main_docking_bay_mouth": Vector3(0, 0, -2550), "main_docking_bay_airlock": Vector3(0, 0, -2360),
			"spin_axis": Vector3.BACK, "spin_rad_s": SPIN}
	h.cargo_bay = {"cargo_bay_approach": [Vector3(0, 339, -5800), Vector3(0, 339, -4700)], "cargo_bay_hold": Vector3(0, 339, -4700),
			"cargo_bay_hold_forward": Vector3.BACK, "cargo_bay_path": [Vector3(0, 339, -4640), Vector3(0, 339, -3534)]}
	return h


func test_the_docking_lane_is_on_the_drums_axis_and_matches_its_turn_from_before_the_mouth() -> void:
	var plan: DockingPlan = DockingPlan.build(_hardpoints(), DRUM)
	assert_true(plan.valid, plan.error)
	assert_eq(plan.dock_in.size(), 4)
	assert_eq(plan.dock_in[0]["at"], Vector3(0, 0, -5050), "the drum's points, moved to the station's frame")
	assert_eq(plan.dock_in[0]["spin"], Vector3.ZERO, "no roll asked on the way to the approach's far point")
	for k: int in [1, 2, 3]:
		assert_eq(plan.dock_in[k]["spin"], Vector3.BACK * SPIN, "the drum's turn from the approach's near point on")
	assert_eq(plan.mouth, Vector3(0, 0, -3550))
	assert_eq(plan.airlock, Vector3(0, 0, -3360 - DockingPlan.AIRLOCK_SHORT_M), "short of the airlock's wall")
	assert_eq(plan.dock_in[3]["at"], plan.airlock)
	assert_eq(plan.dock_out[0]["at"], plan.mouth, "out is the same lane backwards")
	assert_eq(plan.dock_out[2]["at"], plan.dock_in[0]["at"])
	assert_eq(plan.dock_out[2]["spin"], Vector3.ZERO, "free of the drum's turn once clear")


func test_the_freighters_lane_turns_short_backs_in_nose_away_and_leaves_the_way_it_came() -> void:
	var plan: DockingPlan = DockingPlan.build(_hardpoints(), DRUM)
	var lane: Array[Dictionary] = plan.freighter
	assert_eq(plan.away, Vector3.FORWARD, "the nose away from the bay")
	assert_eq(lane[1]["at"], Vector3(0, 339, -4700 - DockingPlan.TURN_SHORT_M), "the turning point, short of the hold point")
	assert_gt(float(lane[1]["hold_s"]), 0.0, "it comes to rest there")
	assert_eq(lane[1]["face"], Vector3.ZERO, "flown to nose first")
	var hold: Dictionary = lane[plan.freighter_hold_index]
	assert_eq(hold["at"], Vector3(0, 339, -4700))
	assert_eq(hold["face"], Vector3.FORWARD, "backed in: the leg to the hold point keeps the nose away")
	assert_eq(float(hold["hold_s"]), DockingPlan.WAIT_S)
	assert_eq(lane[lane.size() - 1]["at"], lane[0]["at"], "and out the way it came")
	assert_eq(lane[lane.size() - 1]["face"], Vector3.ZERO, "nose first")
	assert_eq(plan.pod_path[plan.pod_path.size() - 1], Vector3(0, 339, -3534), "the pods end at the bay's entry")
	assert_false(DockingPlan.TUNNEL_TYPES.has(DockingPlan.FREIGHTER_TYPE), "a Saturn never enters the tunnel")


func test_a_lane_becomes_a_route_in_the_stations_place() -> void:
	var plan: DockingPlan = DockingPlan.build(_hardpoints(), DRUM)
	var world := WorldFrame.new()
	add_child_autofree(world)
	var turned := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(100.0, 0.0, 0.0))
	var route: Route = DockingPlan.route_of(plan.dock_in, turned, world, 45.0, "DOCK")
	assert_true(route.lane)
	assert_eq(route.count(), 4)
	assert_almost_eq(world.universe_to_local(route.waypoint(0).position), turned * Vector3(0, 0, -5050), Vector3.ONE * 0.01)
	assert_almost_eq(route.waypoint(1).spin, turned.basis * Vector3.BACK * SPIN, Vector3.ONE * 1e-5, "the turn in the World's axes")


func test_a_station_without_its_bays_gives_no_plan() -> void:
	var h := StationHardpoints.new()
	var plan: DockingPlan = DockingPlan.build(h, DRUM)
	assert_false(plan.valid)
	assert_string_contains(plan.error, "main docking bay")
