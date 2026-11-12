extends TestSteps
## Broadcast contacts, the player's half (M3-T17, Q21, AC25): on the real main scene with the combat sandbox, a buoy at 900 km
## and an ally at 90 km are candidates and can be selected (their range in the target box), an ally at 110 km and a
## non-broadcasting raider at 30 km are not; beyond the radar's 25 km a broadcast contact sits on the rim in its true
## direction; `broadcast_range_m = INF` works at 1e9 m; ranges survive a rebase.

const FAR_BUOY_M: float = 900000.0

var main: Main
var source: FakeInputSource


func before_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.waves_auto_start = false
	main.ally_pool_size = 8  # the sandbox's three wingmen (M3-T10) and room for this test's allies
	add_child_autofree(main)
	await _ticks(2)


func after_each() -> void:
	DebugConsole.flags.invulnerable = false


func _buoy(buoy_name: String) -> NavBuoy:
	for buoy: NavBuoy in main.buoys:
		if buoy.display_name == buoy_name:
			return buoy
	return null


# A point `offset` (player body axes are World axes at the start: nose along -Z) from the player, through universe positions.
func _from_player(offset: Vector3) -> UniversePos:
	return main.world.to_universe(main.ship.global_position).plus_local(offset)


func _place_buoy(buoy_name: String, offset: Vector3) -> NavBuoy:
	var buoy: NavBuoy = _buoy(buoy_name)
	buoy.velocity = Vector3.ZERO
	buoy.global_position = main.world.universe_to_local(_from_player(offset))
	return buoy


func _ally(ship_name: String, offset: Vector3) -> Combatant:
	return main.ships.acquire(ship_name, _from_player(offset), Basis.IDENTITY, Vector3.ZERO, null, ShipPool.ALLY_TYPE)


func _raider(ship_name: String, offset: Vector3) -> Combatant:
	return main.ships.acquire(ship_name, _from_player(offset), Basis.IDENTITY, Vector3.ZERO, null, ShipPool.DEFAULT_TYPE)


func _candidate_names() -> PackedStringArray:
	var out := PackedStringArray()
	for info: TargetInfo in main.ship.targeting.candidates():
		out.append(info.display_name)
	return out


func test_buoys_and_allies_broadcast_and_raiders_do_not() -> void:
	assert_eq(_buoy("NAV ALPHA").targetable.broadcast_range_m, NavBuoy.BROADCAST_RANGE_M)
	assert_eq(NavBuoy.BROADCAST_RANGE_M, 1.0e6, "1 000 km (M3 Q21; back from M5-T10's 10 000 km, Q41)")
	assert_eq(ShipPool.ALLY_BROADCAST_RANGE_M, 1.0e5, "100 km")
	var ally: Combatant = _ally("ALPHA 7", Vector3(0.0, 0.0, -1000.0))
	var raider: Combatant = _raider("RAIDER 9", Vector3(0.0, 0.0, -1000.0))
	assert_eq(ally.targetable.broadcast_range_m, ShipPool.ALLY_BROADCAST_RANGE_M)
	assert_eq(raider.targetable.broadcast_range_m, 0.0)
	assert_eq(main.ship.targeting.system.sensor_range_m, TargetingSystem.SENSOR_RANGE_M)


func test_far_broadcasts_are_candidates_and_out_of_range_ones_are_not() -> void:
	_place_buoy("NAV ALPHA", Vector3(0.0, 0.0, -FAR_BUOY_M))
	_ally("ALPHA 7", Vector3(90000.0, 0.0, 0.0))
	_ally("ALPHA 8", Vector3(-110000.0, 0.0, 0.0))
	_raider("RAIDER 9", Vector3(0.0, 30000.0, 0.0))
	await _ticks(2)
	var names: PackedStringArray = _candidate_names()
	assert_has(names, "NAV ALPHA", "the 900 km buoy")
	assert_has(names, "ALPHA 7", "the 90 km ally")
	assert_does_not_have(names, "ALPHA 8", "the 110 km ally is beyond its 100 km broadcast")
	assert_does_not_have(names, "RAIDER 9", "a raider at 30 km does not broadcast and is beyond the 25 km sensors")
	assert_has(names, "NAV BRAVO", "the near buoys stay")


func test_a_far_broadcast_can_be_selected_and_shows_its_range() -> void:
	_place_buoy("NAV ALPHA", Vector3(0.0, 0.0, -FAR_BUOY_M))
	await _ticks(2)
	assert_true(main.ship.targeting.select_by_name("NAV ALPHA"))
	await _ticks(2)
	assert_eq(main.ship.targeting.selected_name(), "NAV ALPHA", "the selection holds beyond the sensor range")
	var readout: TargetReadout = main.ship.targeting.selected_readout()
	assert_almost_eq(readout.range_m, FAR_BUOY_M, 1.0)
	assert_eq(DebugConsole.registry.format_path("targeting.selected"), "targeting.selected = NAV ALPHA")


func test_the_radar_puts_a_far_broadcast_on_the_rim_in_its_true_direction() -> void:
	_place_buoy("NAV ALPHA", Vector3(0.0, 0.0, -FAR_BUOY_M))
	_ally("ALPHA 7", Vector3(90000.0, 0.0, 0.0))
	await _ticks(2)
	var dots: Array[RadarModel.Dot] = RadarModel.plot(RadarContacts.from_infos(main.ship.targeting.candidates()), 0,
			main.ship.global_position, main.ship.global_basis, Factions.EARTH_ALLIANCE).to_dots()
	var by_id: Dictionary = {}
	for dot: RadarModel.Dot in dots:
		by_id[dot.id] = dot
	var buoy_dot: RadarModel.Dot = by_id.get(_buoy("NAV ALPHA").targetable.get_instance_id())
	assert_not_null(buoy_dot)
	assert_true(buoy_dot.rim, "beyond 25 km: on the rim")
	var ahead: Vector3 = RadarModel.radar_direction(main.ship.global_basis.transposed() * Vector3(0.0, 0.0, -1.0))
	assert_almost_eq(buoy_dot.point, ahead, Vector3.ONE * 1e-3, "dead ahead, at the rim")
	var near_dot: RadarModel.Dot = by_id.get(_buoy("NAV BRAVO").targetable.get_instance_id())
	assert_false(near_dot.rim, "a near buoy is drawn inside the sphere as before")
	assert_lt(near_dot.point.length(), 1.0)


func test_an_infinite_broadcast_is_heard_at_a_million_kilometres() -> void:
	var buoy: NavBuoy = _place_buoy("NAV ECHO", Vector3(0.0, 1.0e9, 0.0))
	buoy.targetable.broadcast_range_m = INF
	await _ticks(2)
	assert_has(_candidate_names(), "NAV ECHO")
	assert_true(main.ship.targeting.select_by_name("NAV ECHO"))
	assert_almost_eq(main.ship.targeting.selected_readout().range_m, 1.0e9, 200.0, "float32 at 1e9 m rounds to 64 m")
	buoy.targetable.broadcast_range_m = 0.0
	await _ticks(2)
	assert_does_not_have(_candidate_names(), "NAV ECHO", "no broadcast, no contact")
	assert_eq(main.ship.targeting.selected_name(), "", "and the selection is dropped")


func test_ranges_survive_a_rebase() -> void:
	_place_buoy("NAV ALPHA", Vector3(0.0, 0.0, -FAR_BUOY_M))
	await _ticks(2)
	assert_true(main.ship.targeting.select_by_name("NAV ALPHA"))
	var before: float = main.ship.targeting.selected_readout().range_m
	for i: int in 3:
		main.world.rebase(Vector3(4000.0, -1500.0, 2500.0))
		await _ticks(1)
	assert_eq(main.ship.targeting.selected_name(), "NAV ALPHA")
	assert_almost_eq(main.ship.targeting.selected_readout().range_m, before, 1.0)
