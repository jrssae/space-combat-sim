extends GutTest
## `CargoFerryPlan.for_freighter` and `FreighterCargo`'s cargo chunks (M7-T30) for each of the five Saturns: which chunks are cargo,
## the order they come off, one bot for a Saturn 3 pod and two for a long pod or a tank, the tanks turned onto their side before the
## bay's mouth, every pod fitting the bay's opening, and each bot's route ending at its hold on the pod.

const BAY: Dictionary = {
	"cargo_bay_hold": Vector3(0.0, 339.0, -4700.0), "cargo_bay_entry": Vector3(0.0, 339.0, -3534.0),
	"cargo_bay_clear_min": Vector3(-32.1, 327.5, -3580.0), "cargo_bay_clear_max": Vector3(32.1, 354.2, -3512.0),
}
## Each hull's cargo chunks (in the order they come off), and bots a pod.
const HULLS: Dictionary = {
	"saturn_3_freighter": {"cargo": ["pod_top", "pod_l", "pod_r"], "bots": 1, "roll": false},
	"saturn_4_transport": {"cargo": ["pods_l", "pods_r"], "bots": 2, "roll": false},
	"saturn_4_tanker": {"cargo": ["tank_l", "tank_r"], "bots": 2, "roll": true},
	"saturn_8_transport": {"cargo": ["pods_2l", "pods_2r", "pods_1l", "pods_1r"], "bots": 2, "roll": false},
	"saturn_8_tanker": {"cargo": ["tanks_2l", "tanks_2r", "tanks_1l", "tanks_1r"], "bots": 2, "roll": true},
}


static func plan_for(hull: String) -> CargoFerryPlan:
	return CargoFerryPlan.for_freighter(BAY, FreighterCargo.chunk_boxes_of(hull),
			Hardpoints.load_collision_only(ShipSpec.ASSET_ROOT.path_join(hull).path_join("hardpoints.json")))


func test_the_cargo_chunks_of_each_hull() -> void:
	for hull: String in HULLS:
		var names := PackedStringArray()
		for entry: Dictionary in FreighterCargo.chunk_boxes_of(hull):
			if FreighterCargo.is_cargo(String(entry["name"])):
				names.append(entry["name"])
		var want: Array = HULLS[hull]["cargo"]
		assert_eq(names.size(), want.size(), "%s carries %s" % [hull, ", ".join(names)])
		for n: String in want:
			assert_true(names.has(n), "%s has its %s as cargo" % [hull, n])
	assert_false(FreighterCargo.is_cargo("bow"))
	assert_false(FreighterCargo.is_cargo("engine"))
	assert_false(FreighterCargo.is_cargo("hull_1"))


func test_each_hull_has_a_trip_a_pod_nearest_the_bay_first() -> void:
	for hull: String in HULLS:
		var plan: CargoFerryPlan = plan_for(hull)
		assert_true(plan.valid, "%s: %s" % [hull, plan.error])
		if not plan.valid:
			continue
		var order := PackedStringArray()
		for trip: CargoTrip in plan.trips:
			order.append(trip.pod_name)
			assert_eq(trip.bot_count(), int(HULLS[hull]["bots"]), "%s %s bots" % [hull, trip.pod_name])
			assert_eq(trip.roll, bool(HULLS[hull]["roll"]), "%s %s turns onto its side" % [hull, trip.pod_name])
		assert_eq(order, PackedStringArray(HULLS[hull]["cargo"]), "%s's pods come off nearest the bay first" % hull)


func test_a_trip_runs_from_the_hull_into_the_back_wall() -> void:
	for hull: String in HULLS:
		var plan: CargoFerryPlan = plan_for(hull)
		for trip: CargoTrip in plan.trips:
			var label: String = "%s %s" % [hull, trip.pod_name]
			var chunk: AABB = _chunk(hull, trip.pod_name)
			var on_hull: Vector3 = plan.freighter_transform() * chunk.get_center()
			assert_almost_eq(trip.centre_at(0.0), on_hull, Vector3.ONE * 0.01, "%s starts where it sits" % label)
			var end: Vector3 = trip.centre_at(trip.carry.length_m)
			assert_gt(end.z - trip.size.z * 0.5, plan.wall_z, "%s ends wholly behind the back wall" % label)
			assert_almost_eq(Vector2(end.x, end.y), Vector2(plan.bay_mid.x, plan.bay_mid.y), Vector2.ONE * 0.01, "%s on the bay's line" % label)
			assert_gt(trip.unberth_s, 0.0, "%s lifts off first" % label)
			assert_lt(trip.unberth_s, trip.commit_s, label)
			assert_lt(trip.commit_s, trip.carry.length_m, label)
			var held_on_hull: bool = false
			for k: int in trip.bot_count():
				held_on_hull = held_on_hull or trip.grab_s[k] == 0.0
				var route: BotRoute = trip.out_routes[k]
				assert_almost_eq(route.point_at(route.length_m), trip.bot_position(k, trip.grab_s[k]), Vector3.ONE * 0.01,
						"%s bot %d ends at its hold" % [label, k])
				assert_gt(route.point_at(0.0).z, plan.wall_z, "%s bot %d comes out of the back wall" % [label, k])
				var standoff: float = absf(trip.offsets[k].z) - trip.size.z * 0.5
				assert_almost_eq(standoff, CargoFerryPlan.STANDOFF_M, 0.01, "%s bot %d holds an end from the standoff" % [label, k])
			assert_true(held_on_hull, "%s: a bot takes it on the hull" % label)
			if trip.bot_count() == 2:
				assert_gt(trip.offsets[0].z, 0.0, "%s: bot 0 at the end toward the bay" % label)
				assert_lt(trip.offsets[1].z, 0.0, "%s: bot 1 at the far end" % label)


func test_every_pod_fits_the_bays_opening_and_a_tank_is_on_its_side_before_the_mouth() -> void:
	var clear_min: Vector3 = BAY["cargo_bay_clear_min"]
	var clear_max: Vector3 = BAY["cargo_bay_clear_max"]
	for hull: String in HULLS:
		var plan: CargoFerryPlan = plan_for(hull)
		for trip: CargoTrip in plan.trips:
			var label: String = "%s %s" % [hull, trip.pod_name]
			# The moment its leading face reaches the bay's mouth.
			var s: float = CargoFerryPlan._s_at_z(trip.carry, plan.throat_z - trip.size.z * 0.5)
			var pose: Transform3D = trip.pose_at(s)
			var box: AABB = pose * AABB(-trip.size * 0.5, trip.size)
			assert_gt(box.position.x, clear_min.x, "%s fits the opening's width" % label)
			assert_lt(box.end.x, clear_max.x, "%s fits the opening's width" % label)
			assert_gt(box.position.y, clear_min.y, "%s clears the bay's floor (%.1f m)" % [label, box.position.y - clear_min.y])
			assert_lt(box.end.y, clear_max.y, "%s clears the bay's roof (%.1f m)" % [label, clear_max.y - box.end.y])
			if trip.roll:
				assert_almost_eq(trip.roll_angle(pose.origin.z), PI * 0.5, 1e-4, "%s is on its side at the mouth" % label)
				assert_almost_eq(trip.roll_angle(trip.centre_at(trip.unberth_s).z), 0.0, 1e-4, "%s comes off upright" % label)
			else:
				assert_eq(trip.roll_angle(pose.origin.z), 0.0, "%s does not turn" % label)


func test_the_bots_routes_run_smoothly() -> void:
	for hull: String in HULLS:
		var plan: CargoFerryPlan = plan_for(hull)
		for trip: CargoTrip in plan.trips:
			var routes: Array[BotRoute] = trip.out_routes.duplicate()
			routes.append(trip.carry)
			for route: BotRoute in routes:
				var worst: float = 0.0
				for i: int in range(1, route.samples.size() - 1):
					if route == trip.carry and _at_stop(trip, route.along[i]):
						continue  # the pod stops at the corners of its way off the hull
					var a: Vector3 = route.samples[i] - route.samples[i - 1]
					var b: Vector3 = route.samples[i + 1] - route.samples[i]
					if a.length() > 0.01 and b.length() > 0.01:
						worst = maxf(worst, rad_to_deg(a.angle_to(b)))
				assert_lt(worst, 40.0, "%s %s: no sharp corner (%.0f deg)" % [hull, trip.pod_name, worst])


func test_a_bad_bay_or_a_hull_without_cargo_is_said() -> void:
	assert_false(CargoFerryPlan.for_freighter({}, FreighterCargo.chunk_boxes_of("saturn_3_freighter"), []).valid, "no bay, no plan")
	var plan: CargoFerryPlan = CargoFerryPlan.for_freighter(BAY, [{"name": "bow", "box": AABB(Vector3.ONE * -5.0, Vector3.ONE * 10.0)}], [])
	assert_false(plan.valid)
	assert_string_contains(plan.error, "cargo")


func _at_stop(trip: CargoTrip, at: float) -> bool:
	for stop: float in trip.stops:
		if absf(stop - at) < 0.01:
			return true
	return false


func _chunk(hull: String, pod_name: String) -> AABB:
	for entry: Dictionary in FreighterCargo.chunk_boxes_of(hull):
		if entry["name"] == pod_name:
			return entry["box"]
	return AABB()
