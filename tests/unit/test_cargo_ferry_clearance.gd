extends GutTest
## The cargo ferry's routes keep their distance from the station's drawn hull and from the Saturn 3 backed in at the hold point
## (M7-T11, the cargo scene), for every lane, out and back. The last metres at the bay's back wall (the machinery stands close there) are the bots' way in and out of
## it, by design, and are left out.

const DIR: String = "res://assets/generated/babylon5_station/"
const HULL_CLEARANCE_M: float = 8.0
const SATURN_CLEARANCE_M: float = 5.0
const WALL_M: float = 20.0
const EVERY: int = 3

var plan: CargoFerryPlan
var hull: BotMeshField
var saturn: BotMeshField


func before_all() -> void:
	var manifest: Dictionary = MeshAssets.read_manifest(Station.ASSET_ID)
	var hp: StationHardpoints = StationHardpoints.from_manifest(manifest)
	assert_true(hp.valid, hp.error)
	var shapes: Array[Dictionary] = Hardpoints.load_collision_only(BotCargoScene.HARDPOINTS)
	plan = CargoFerryPlan.build(hp.cargo_bay, shapes)
	assert_true(plan.valid, plan.error)
	hull = BotMeshField.of_faces(BotMeshField.faces_of_glb(DIR + "babylon5_station_frame.glb"))
	saturn = BotMeshField.of_faces(BotMeshField.faces_of_collision(shapes, plan.freighter_transform()))


func test_the_hold_point_leaves_the_freighter_clear_of_the_station() -> void:
	var least: float = INF
	for p: Vector3 in plan.pod_stops:
		least = minf(least, hull.distance(p, 400.0))
	assert_gt(least, 100.0, "the pods' end of the Saturn is over 100 m from the hull (%.0f)" % least)
	assert_eq(saturn.triangle_count() > 100, true)


func test_every_lane_clears_the_hull_and_the_saturn() -> void:
	for lane: int in 12:
		var routes: Array[BotRoute] = plan.routes_for(lane)
		for k: int in 2:
			var route: BotRoute = routes[k]
			var from_s: float = WALL_M if k == 0 else 0.0
			var to_s: float = route.length_m if k == 0 else route.length_m - WALL_M
			var least_hull: float = INF
			var least_saturn: float = INF
			var s: float = from_s
			while s <= to_s:
				var p: Vector3 = route.point_at(s)
				least_hull = minf(least_hull, hull.distance(p, 60.0))
				least_saturn = minf(least_saturn, saturn.distance(p, 60.0))
				s += float(EVERY)
			var label: String = "lane %d %s" % [lane, "out" if k == 0 else "back"]
			assert_gte(least_hull, HULL_CLEARANCE_M, "%s keeps %.1f m from the hull" % [label, least_hull])
			assert_gte(least_saturn, SATURN_CLEARANCE_M, "%s keeps %.1f m from the Saturn" % [label, least_saturn])


func test_the_wall_end_of_a_route_does_end_in_the_bays_wall() -> void:
	# The sunk end is inside the hull: the nearest triangle is close, as a bot being hidden by the wall needs.
	var end: Vector3 = plan.routes_for(0)[0].point_at(0.0)
	assert_lt(hull.distance(end, 60.0), 12.0, "the start of a route is at the wall (%.1f m off a face)" % hull.distance(end, 60.0))
