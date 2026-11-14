extends GutTest
## `CargoFerryPlan` (M7-T11, the cargo scene): a Saturn 3 backs in at the cargo bay's hold point (its nose away from the bay, its
## pods nearest it) and the ferry bots' routes run from the bay's back wall to the pods' aft faces, each bot on its own lanes.

const BAY: Dictionary = {
	"cargo_bay_hold": Vector3(0.0, 339.0, -4700.0), "cargo_bay_entry": Vector3(0.0, 339.0, -3534.0),
	"cargo_bay_clear_min": Vector3(-32.1, 327.5, -3580.0), "cargo_bay_clear_max": Vector3(32.1, 354.2, -3512.0),
}

var plan: CargoFerryPlan


func before_each() -> void:
	plan = CargoFerryPlan.build(BAY, Hardpoints.load_collision_only(BotCargoScene.HARDPOINTS))
	assert_true(plan.valid, plan.error)


func test_the_freighter_faces_away_from_the_bay() -> void:
	var pose: Transform3D = plan.freighter_transform()
	assert_eq(pose.origin, BAY["cargo_bay_hold"], "at the hold point")
	var nose: Vector3 = -pose.basis.z  # a ship's nose is -Z
	var to_bay: Vector3 = (BAY["cargo_bay_entry"] as Vector3) - pose.origin
	assert_lt(nose.dot(to_bay.normalized()), -0.999, "its forward points away from cargo_bay_entry: it backs in")
	assert_true(pose.basis.orthonormalized().is_equal_approx(pose.basis), "a proper rotation")
	assert_gt((pose.basis.z).dot(to_bay.normalized()), 0.999, "its stern is toward the bay")


func test_the_pods_are_the_end_nearest_the_bay() -> void:
	assert_eq(plan.pod_stops.size(), 3, "top, right and left pods")
	var entry: Vector3 = BAY["cargo_bay_entry"]
	for i: int in plan.pod_stops.size():
		var box: AABB = plan.pod_boxes[i]
		assert_lt(box.get_center().distance_to(entry), plan.hold.distance_to(entry), "pod %d is nearer the bay than the hold point" % i)
		assert_almost_eq(plan.pod_stops[i].z - box.end.z, CargoFerryPlan.STANDOFF_M, 0.01, "a bot waits the standoff behind pod %d's aft face" % i)
		assert_almost_eq(plan.pod_stops[i].x, box.get_center().x, 0.01, "in line with its pod")


func test_each_route_runs_from_the_back_wall_to_a_pod() -> void:
	for lane: int in 6:
		var routes: Array[BotRoute] = plan.routes_for(lane)
		var out: BotRoute = routes[0]
		var back: BotRoute = routes[1]
		var stop: Vector3 = plan.pod_stops[lane % 3]
		assert_gt(out.length_m, 1000.0, "the whole way out the slot")
		assert_gt(out.point_at(0.0).z, plan.wall_z, "starts inside the bay's back wall")
		assert_almost_eq(out.point_at(out.length_m), stop, Vector3.ONE * 0.01, "ends behind its pod")
		assert_almost_eq(back.point_at(0.0), stop, Vector3.ONE * 0.01, "the way back starts there")
		assert_gt(back.point_at(back.length_m).z, plan.wall_z, "and ends inside the wall")
		assert_almost_eq(out.point_at(300.0).x, -back.point_at(back.length_m - 300.0).x, 0.5, "the lanes are on opposite sides of the bay's line")
		assert_almost_eq(absf(out.point_at(300.0).x), CargoFerryPlan.LANE_X_M, 0.5)


func test_the_routes_run_smoothly() -> void:
	var out: BotRoute = plan.routes_for(0)[0]
	var s: float = 20.0  # the first metres are the bay's wall, where the bot is hidden
	var worst: float = 0.0
	while s < out.length_m - 2.0:
		worst = maxf(worst, out.direction_at(s).angle_to(out.direction_at(s + 2.0)))
		s += 2.0
	assert_lt(rad_to_deg(worst), 6.0, "the heading turns under 6 degrees in 2 m (%.2f)" % rad_to_deg(worst))


func test_a_bad_bay_or_freighter_is_said() -> void:
	assert_false(CargoFerryPlan.build({}, []).valid)
	assert_false(CargoFerryPlan.build(BAY, [] as Array[Dictionary]).valid, "no pods, no plan")
	var sideways: Dictionary = BAY.duplicate()
	sideways["cargo_bay_entry"] = Vector3(500.0, 339.0, -4600.0)
	assert_string_contains(CargoFerryPlan.build(sideways, Hardpoints.load_collision_only(BotCargoScene.HARDPOINTS)).error, "+Z")
