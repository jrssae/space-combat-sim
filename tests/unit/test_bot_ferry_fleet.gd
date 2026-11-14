extends GutTest
## The ferry bots inside a `BotFleet` (M7-T11, the cargo scene): they hang from the frame, take the fleet's alarm, hide in the bay's
## wall when fighting starts and come back after the quiet. A bare fleet on plain nodes; the Saturn is in the integration test.

const DT: float = 1.0 / 60.0
const BAY: Dictionary = {
	"cargo_bay_hold": Vector3(0.0, 339.0, -4700.0), "cargo_bay_entry": Vector3(0.0, 339.0, -3534.0),
	"cargo_bay_clear_min": Vector3(-32.1, 327.5, -3580.0), "cargo_bay_clear_max": Vector3(32.1, 354.2, -3512.0),
}

var origin: Node3D
var frame_parent: Node3D
var drum_pivot: Node3D
var fleet: BotFleet
var plan: CargoFerryPlan


func before_each() -> void:
	origin = Node3D.new()
	frame_parent = Node3D.new()
	drum_pivot = Node3D.new()
	origin.add_child(frame_parent)
	origin.add_child(drum_pivot)
	add_child_autofree(origin)
	fleet = BotFleet.new()
	assert_true(fleet.build_on(origin, frame_parent, drum_pivot, BotData.load_file(), BoxMesh.new()))
	fleet.set_physics_process(false)
	origin.add_child(fleet)
	plan = CargoFerryPlan.build(BAY, Hardpoints.load_collision_only(BotCargoScene.HARDPOINTS))
	var cycle_s: float = BotCargoScene.trip_seconds(plan)
	for lane: int in 5:
		var routes: Array[BotRoute] = plan.routes_for(lane)
		var m := BotFerryMotion.new()
		m.setup(routes[0], routes[1], Vector3.UP, 3.0 * float(lane))
		BotCargoScene.warm(m, cycle_s * float(lane) / 5.0)
		fleet.add_ferry_bot(m)


func _step(seconds: float) -> void:
	for i: int in int(seconds / DT):
		fleet._physics_process(DT)


func test_the_ferry_bots_hang_from_the_frame_and_are_ambient() -> void:
	assert_eq(fleet.ferry_bots.size(), 5)
	for bot: MaintenanceBot in fleet.ferry_bots:
		assert_eq(bot.get_parent(), frame_parent, "on the frame: they never turn with the drum")
		assert_eq(bot.home_body, StationHardpoints.FRAME)
		assert_eq(bot.find_children("*", "Targetable", true, false).size(), 0)
		assert_eq(bot.find_children("*", "CollisionObject3D", true, false).size(), 0)
	assert_eq(fleet.bots.size(), BotData.load_file().bot_count(), "the loop bots are untouched")


func test_they_fly_the_route_in_the_stations_frame() -> void:
	_step(10.0)
	for bot: MaintenanceBot in fleet.ferry_bots:
		assert_almost_eq(bot.position, bot.motion.position, Vector3.ONE * 1e-5)
	origin.global_position += Vector3(5000.0, -300.0, 12000.0)
	for bot: MaintenanceBot in fleet.ferry_bots:
		assert_almost_eq(origin.to_local(bot.global_position), bot.motion.position, Vector3.ONE * 1e-3, "a rebase changes nothing on the station")


func test_fighting_near_the_bay_sends_every_ferry_bot_inside_and_after_the_quiet_they_go_again() -> void:
	_step(5.0)
	for i: int in 12:
		fleet.note_combat_at(origin.to_global(plan.entry))
		_step(10.0)
	assert_eq(fleet.ferry_hidden_count(), 5, "all inside the bay's wall (none visible)")
	for bot: MaintenanceBot in fleet.ferry_bots:
		assert_false(bot.visible)
	_step(BotAlert.QUIET_S + BotFerryMotion.HIDDEN_S + 3.0 * 5.0 + 20.0)
	assert_lt(fleet.ferry_hidden_count(), 5, "out again after the quiet")
	var trips: int = 0
	_step(400.0)
	for bot: MaintenanceBot in fleet.ferry_bots:
		trips += (bot.motion as BotFerryMotion).trips
	assert_gt(trips, 3, "and shuttling")


func test_bots_hide_holds_the_ferry_in_too_and_clear_removes_it() -> void:
	DebugConsole.registry.execute("bots hide")
	_step(150.0)
	assert_eq(fleet.ferry_hidden_count(), 5)
	fleet.clear_ferry()
	assert_eq(fleet.ferry_bots.size(), 0)
	assert_eq(frame_parent.get_child_count(), fleet.bots.size() - drum_count(), "the ferry bots are gone from the frame")


func drum_count() -> int:
	var n: int = 0
	for bot: MaintenanceBot in fleet.bots:
		n += 1 if bot.home_body == StationHardpoints.DRUM else 0
	return n
