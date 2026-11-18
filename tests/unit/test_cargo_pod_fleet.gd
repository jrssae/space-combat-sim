extends GutTest
## The cargo pods in a `CargoPodFleet` (M7-T34; T30's ferry bots in a `BotFleet` before): they hang from the frame, heed the alarm,
## hide in the bay's wall when fighting starts and come back after the quiet. A bare fleet on plain nodes, its alarm its own; with a
## crew it reads the crew's log. The Saturn is in the integration test.

const DT: float = 1.0 / 60.0
const BAY: Dictionary = {
	"cargo_bay_hold": Vector3(0.0, 339.0, -4700.0), "cargo_bay_entry": Vector3(0.0, 339.0, -3534.0),
	"cargo_bay_clear_min": Vector3(-32.1, 327.5, -3580.0), "cargo_bay_clear_max": Vector3(32.1, 354.2, -3512.0),
}

var origin: Node3D
var frame_parent: Node3D
var fleet: CargoPodFleet
var plan: CargoFerryPlan


func before_each() -> void:
	origin = Node3D.new()
	frame_parent = Node3D.new()
	origin.add_child(frame_parent)
	add_child_autofree(origin)
	fleet = CargoPodFleet.new()
	fleet.build_on(origin, frame_parent)
	fleet.set_physics_process(false)
	origin.add_child(fleet)
	plan = CargoFerryPlan.build(BAY, Hardpoints.load_collision_only(CargoPodScene.HARDPOINTS))
	var cycle_s: float = CargoPodScene.trip_seconds(plan)
	for lane: int in 5:
		var routes: Array[BotRoute] = plan.routes_for(lane)
		var m := CargoPodMotion.new()
		m.setup(routes[0], routes[1], Vector3.UP, 3.0 * float(lane))
		CargoPodScene.warm(m, cycle_s * float(lane) / 5.0)
		fleet.add_pod(m)


func _step(seconds: float) -> void:
	for i: int in int(seconds / DT):
		fleet._physics_process(DT)


func test_the_pods_hang_from_the_frame_and_are_ambient() -> void:
	assert_eq(fleet.pods.size(), 5)
	for craft: CargoPodCraft in fleet.pods:
		assert_eq(craft.get_parent(), frame_parent, "on the frame: they never turn with the drum")
		assert_not_null(craft.rig, "the cargo pod's model and arms")
		assert_eq(craft.find_children("*", "Targetable", true, false).size(), 0)
		assert_eq(craft.find_children("*", "CollisionObject3D", true, false).size(), 0)


func test_they_fly_the_route_in_the_stations_frame() -> void:
	_step(10.0)
	for craft: CargoPodCraft in fleet.pods:
		assert_almost_eq(craft.position, craft.motion.position, Vector3.ONE * 1e-5)
	origin.global_position += Vector3(5000.0, -300.0, 12000.0)
	for craft: CargoPodCraft in fleet.pods:
		assert_almost_eq(origin.to_local(craft.global_position), craft.motion.position, Vector3.ONE * 1e-3, "a rebase changes nothing on the station")


func test_fighting_near_the_bay_sends_every_pod_inside_and_after_the_quiet_they_go_again() -> void:
	_step(5.0)
	for i: int in 12:
		fleet.note_combat_at(origin.to_global(plan.entry))
		_step(10.0)
	assert_eq(fleet.hidden_count(), 5, "all inside the bay's wall (none visible)")
	for craft: CargoPodCraft in fleet.pods:
		assert_false(craft.visible)
	_step(BotAlert.QUIET_S + CargoPodMotion.HIDDEN_S + 3.0 * 5.0 + 20.0)
	assert_lt(fleet.hidden_count(), 5, "out again after the quiet")
	var trips: int = 0
	_step(400.0)
	for craft: CargoPodCraft in fleet.pods:
		trips += craft.motion.trips
	assert_gt(trips, 3, "and shuttling")


func test_pods_hide_holds_them_in_and_clear_removes_them() -> void:
	DebugConsole.registry.execute("pods hide")
	_step(150.0)
	assert_eq(fleet.hidden_count(), 5)
	DebugConsole.registry.execute("pods show")
	assert_false(fleet.held_in)
	fleet.clear()
	assert_eq(fleet.pods.size(), 0)
	assert_eq(frame_parent.get_child_count(), 0, "the pods are gone from the frame")


func test_with_a_crew_the_pods_heed_the_crews_alarm() -> void:
	var crew := BotFleet.new()
	assert_true(crew.build_on(origin, origin, BotData.load_file(), BoxMesh.new()))
	crew.set_physics_process(false)
	origin.add_child(crew)
	var pods := CargoPodFleet.new()
	pods.build_on(origin, frame_parent, crew)
	assert_same(pods.alert, crew.alert, "one log of fighting for the crew and the pods")
	crew.note_hit_at(origin.to_global(plan.entry))
	assert_true(pods.alert.is_alarmed(plan.entry, pods.now_s()), "a hit the crew hears stops the pods too")
	pods.free()
