extends GutTest
## Ships inside the station are lit as interiors (M7): a fighter on its rack in a Cobra hall is on the interior layer and comes
## back to the first layer at its hand-off; the station's open bays are trigger volumes that do the same for a ship flying in.

const SCENARIO: String = "res://data/scenarios/station_launch.json"

var main: Main


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = SCENARIO
	main.raider_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	for i: int in 3:
		await get_tree().physics_frame


func after_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func test_a_racked_fighter_is_in_the_interior_light_until_its_hand_off() -> void:
	if main.far_props.station == null:
		fail_test("run scripts/gen_assets.sh and import first")
		return
	assert_true(main.launches.player_launch().size() > 0, "the scenario starts on the rack")
	assert_true(InteriorLight.is_inside(main.ship), "on the rack, in the hall")
	var hull: Array = main.ship.find_children("*", "GeometryInstance3D", true, false)
	assert_gt(hull.size(), 0)
	for node: GeometryInstance3D in hull:
		assert_eq(node.layers & InteriorLight.OUTSIDE_LAYER, 0, "%s is out of the star's light" % node.name)
	main.launches.skip()
	for i: int in 240:
		if main.launches.player_launch().is_empty():
			break
		await get_tree().physics_frame
	assert_true(main.launches.player_launch().is_empty(), "handed over")
	assert_false(InteriorLight.is_inside(main.ship), "in the open again")
	for node: GeometryInstance3D in hull:
		assert_eq(node.layers & LightRig.INTERIOR_LAYER, 0, String(node.name))


func test_the_stations_open_bays_light_a_ship_flying_in_as_an_interior() -> void:
	var station: Station = main.far_props.station
	if station == null:
		fail_test("run scripts/gen_assets.sh and import first")
		return
	var zones := station.get_node_or_null(^"InteriorZones") as InteriorZones
	assert_not_null(zones, "the station carries its bays' volumes")
	if zones == null:
		return
	for zone: String in ["main_docking_bay", "cargo_bay"]:
		var area: Area3D = zones.area(zone)
		assert_not_null(area, zone)
		assert_eq(area.collision_layer, 0, "it touches nothing")
		assert_ne(area.collision_mask & CollisionLayers.FIGHTER, 0, "it sees fighters")
		assert_ne(area.collision_mask & CollisionLayers.PLAYER, 0, "and the player")
	main.launches.skip()
	for i: int in 240:
		if main.launches.player_launch().is_empty():
			break
		await get_tree().physics_frame
	assert_false(InteriorLight.is_inside(main.ship))
	zones.area("main_docking_bay").body_entered.emit(main.ship)
	assert_true(InteriorLight.is_inside(main.ship), "in the tunnel")
	assert_eq(zones.inside["main_docking_bay"], 1)
	zones.area("main_docking_bay").body_exited.emit(main.ship)
	assert_false(InteriorLight.is_inside(main.ship), "out again")
	assert_eq(zones.inside["main_docking_bay"], 0)
	zones.area("cargo_bay").body_entered.emit(station.frame_piece)
	assert_eq(zones.inside["cargo_bay"], 0, "only ships count")


func test_a_ship_in_the_docking_tunnel_is_found_by_the_physics_engine() -> void:
	var station: Station = main.far_props.station
	if station == null:
		fail_test("run scripts/gen_assets.sh and import first")
		return
	var zones := station.get_node_or_null(^"InteriorZones") as InteriorZones
	main.launches.skip()
	for i: int in 240:
		if main.launches.player_launch().is_empty():
			break
		await get_tree().physics_frame
	DebugConsole.flags.invulnerable = true
	var tunnel: Area3D = zones.area("main_docking_bay")
	var out_there: Transform3D = main.ship.global_transform
	main.ship.global_transform = Transform3D(main.ship.global_basis, tunnel.global_position)
	main.ship.linear_velocity = main.world.rest_velocity()
	main.ship.angular_velocity = Vector3.ZERO
	for i: int in 6:
		await get_tree().physics_frame
	assert_eq(zones.inside["main_docking_bay"], 1, "the engine reports the ship in the tunnel")
	assert_true(InteriorLight.is_inside(main.ship))
	main.ship.global_transform = out_there
	for i: int in 6:
		await get_tree().physics_frame
	assert_eq(zones.inside["main_docking_bay"], 0)
	assert_false(InteriorLight.is_inside(main.ship), "and out of it")
	DebugConsole.flags.invulnerable = false
