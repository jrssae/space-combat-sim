extends GutTest
## `BotTrip` (M7-T35): a maintenance bot's trip is its way out, its stop and the same way back, so a bot called home turns round
## where it is.


func _route(a: Vector3, b: Vector3) -> BotRoute:
	return BotRoute.from_points(PackedVector3Array([a, b]))


func _trip() -> BotTrip:
	var out: Array[Dictionary] = [
		BotTrip.fly(_route(Vector3.ZERO, Vector3(0, 0, -100)), BotTrip.Frame.STATION, 25.0),
		BotTrip.spin_up(355.0, -1000.0),
		BotTrip.fly(_route(Vector3(355, 0, 0), Vector3(355, 0, 200)), BotTrip.Frame.DRUM, 8.0),
		BotTrip.hold(5.0)]
	return BotTrip.symmetric("test", out, BotTrip.work(3), true)


func test_the_way_back_mirrors_the_way_out() -> void:
	var trip: BotTrip = _trip()
	assert_eq(trip.steps.size(), 9)
	assert_eq(trip.middle, 4)
	assert_eq(int(trip.steps[4]["kind"]), BotTrip.Kind.WORK)
	assert_eq(int(trip.steps[7]["kind"]), BotTrip.Kind.SPIN_DOWN, "getting on the drum is undone by getting off it")
	var out_route: BotRoute = trip.steps[0]["route"]
	var back_route: BotRoute = trip.steps[8]["route"]
	assert_almost_eq(back_route.point_at(0.0), out_route.point_at(out_route.length_m), Vector3.ONE * 1e-4)
	assert_almost_eq(back_route.point_at(back_route.length_m), Vector3.ZERO, Vector3.ONE * 1e-4, "it ends where it started")
	assert_true(trip.repair)


func test_called_home_it_takes_the_mirror_of_a_flight_and_skips_the_mirror_of_a_stop() -> void:
	var trip: BotTrip = _trip()
	assert_eq(trip.home_step(0), 8, "flying out: fly the same leg back")
	assert_eq(trip.home_step(2), 6, "crawling along the drum: crawl back")
	assert_eq(trip.home_step(3), 6, "holding: no second hold on the way home")
	assert_eq(trip.home_step(4), 5, "working: straight on home")
	assert_eq(trip.home_step(6), -1, "already going home")


func test_a_transit_mirrors_its_ends() -> void:
	var step: Dictionary = BotTrip.transit(Vector3(1, 2, 3), BotTrip.Frame.STATION, Vector3(4, 5, 6), BotTrip.Frame.GATE, 250.0, 10.0)
	var back: Dictionary = BotTrip.mirrored(step)
	assert_eq(back["from"], Vector3(4, 5, 6))
	assert_eq(back["from_frame"], BotTrip.Frame.GATE)
	assert_eq(back["to_frame"], BotTrip.Frame.STATION)
