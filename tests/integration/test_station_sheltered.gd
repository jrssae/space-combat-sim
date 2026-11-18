extends GutTest
## Ships inside the station (M7-T62, maintainer 2026-11-16): a civilian that has crossed into the main docking bay's black void is
## inside the station and unavailable. It drops out of the player's targeting (a selected one is dropped), the radar, the AI's
## targeting and the core's hull rows (what the hit sweep, the rams and the mines walk), and comes back once it is out past the
## doors' plane. On the real main scene, flown with the physics rate and the time scale raised together.

const SCENARIO: String = "res://data/scenarios/station_launch.json"
const SPEED_UP: float = 8.0
const HULL: StringName = &"skylark_transport"

var main: Main
var station: Station
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	get_tree().paused = false
	ContactScan.invalidate()


func _start() -> bool:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = SCENARIO
	main.raider_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	station = main.far_props.station
	if station == null or station.airlock == null:
		return false
	main.combatant.damageable.invulnerable = true
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	return true


# Flies until `done` or `limit_s` of sim time; whether it was done.
func _until(done: Callable, limit_s: float) -> bool:
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < limit_s:
		if done.call():
			return true
		await get_tree().physics_frame
	return bool(done.call())


# Whether `c` is on the player's radar now.
func _on_radar(c: Combatant) -> bool:
	return RadarContacts.gather(get_tree(), main.ship, main.ship.targeting.system.sensor_range_m).ids.has(c.targetable.get_instance_id())


# Whether `c` is among the player's target candidates now.
func _a_candidate(c: Combatant) -> bool:
	for info: TargetInfo in main.ship.targeting.candidates():
		if info.id == c.targetable.get_instance_id():
			return true
	return false


# Whether the core walks `c`'s hull for shots, rams and blasts.
func _a_hull_row(c: Combatant) -> bool:
	var sim: SimCore = SimCore.for_tree(get_tree())
	return (sim.core.hull_columns()[0] as PackedInt64Array).has(c.ship.get_instance_id())


# How far `c`'s origin lies past the doors' plane, into the void.
func _depth(c: Combatant) -> float:
	return station.airlock.depth_of(station.to_local(c.ship.global_position))


# A raider `out_m` in front of the bay's mouth and `side_m` off its axis, hostile to the traffic, picking its own targets.
func _raider_before_the_bay(out_m: float, side_m: float) -> Combatant:
	var mouth: Vector3 = main.traffic.plan.mouth
	var place: Vector3 = station.global_transform * (mouth - station.airlock.axis * out_m + Vector3.RIGHT * side_m)
	main.ensure_free(ShipPool.DEFAULT_TYPE, 1)
	var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": "raider", "orders": "engage"},
			main.world.to_universe(place), 62)
	if not bool(made["ok"]):
		return null
	var raider: Combatant = main.ships.acquire("RAIDER 62", main.world.to_universe(place),
			Basis.looking_at(station.global_basis * station.airlock.axis, station.global_basis.y), main.world.rest_velocity(), made["brain"],
			ShipPool.DEFAULT_TYPE)
	if raider != null:
		raider.damageable.invulnerable = true
	return raider


func test_a_docking_civilian_is_available_outside_and_unavailable_once_inside_the_void() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	assert_eq(main.traffic.dock(HULL, true), "")
	var c: Combatant = main.traffic.last_ship()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var marker_id: int = c.targetable.get_instance_id()
	assert_false(c.ship.inside_station, "on the lane, outside")
	assert_true(c.targetable.is_active())
	assert_true(_on_radar(c), "on the radar outside")
	assert_true(_a_candidate(c), "a target candidate outside")
	assert_true(main.ship.targeting.select_id(marker_id), "the player selects it outside")
	assert_true(_a_hull_row(c), "its hull can be hit outside")
	var ship: Ship = c.ship
	var seen: Dictionary = {"depth_in": INF}
	assert_true(await _until(func() -> bool:
		if ship.inside_station:
			seen["depth_in"] = _depth(c)
		return ship.inside_station, 150.0), "it crossed into the void")
	assert_between(float(seen["depth_in"]), 0.0, 2.0, "inside as its origin crossed the doors' plane")
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(main.traffic.inside_count(), 1)
	assert_false(c.targetable.is_active(), "no longer a target")
	assert_ne(main.ship.targeting.system.selected_id(), marker_id, "the player's selection of it was dropped")
	assert_false(_on_radar(c), "off the radar")
	assert_false(_a_candidate(c), "not a target candidate")
	assert_false(main.ship.targeting.select_id(marker_id), "the player cannot select it inside")
	assert_false(_a_hull_row(c), "out of the hit sweep, the rams and the mines")
	assert_false(ship.is_far_dot(), "never a far dot drawn over the station")
	var status: ConsoleResult = DebugConsole.registry.execute("traffic status")[0]
	assert_string_contains("\n".join(status.lines), "1 inside")
	assert_true(await _until(func() -> bool: return main.traffic.docked_count > 0, 150.0), "it docked")
	assert_eq(main.traffic.inside_count(), 0)
	assert_false(ship.inside_station, "the pool cleared it on parking")


func test_an_undocking_civilian_is_unavailable_in_the_void_and_available_once_out() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	# The raider meets no one but the civilian: the player's wing back to its pool, and the player sheltered as a docked ship is (it
	# sits in a Cobra bay). It waits beyond the civilian's flee range (3 km) but within its own sight of the void (5 km).
	assert_true(DebugConsole.registry.execute("despawn all")[0].ok)
	main.ship.inside_station = true
	assert_true(main.traffic.lanes_ready(), "the bay's lanes are planned")
	var raider: Combatant = _raider_before_the_bay(4000.0, 300.0)
	assert_not_null(raider, "a raider in front of the bay")
	if raider == null:
		return
	assert_eq(main.traffic.undock(HULL), "")
	var c: Combatant = main.traffic.last_ship()
	c.damageable.invulnerable = true
	var marker_id: int = c.targetable.get_instance_id()
	assert_true(Factions.is_hostile(raider.faction, c.faction), "the raider is hostile to it")
	assert_true(c.ship.inside_station, "inside from the start")
	var ship: Ship = c.ship
	assert_false(c.targetable.is_active(), "no target in the void")
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(raider.ship.targeting.select_id(marker_id), "the raider's targeting cannot select it in the void")
	var seen: Dictionary = {"radar_inside": false, "hull_inside": false, "raider_inside": false, "frames_inside": 0,
			"depth_out": -INF}
	assert_true(await _until(func() -> bool:
		if ship.inside_station:
			seen["frames_inside"] = int(seen["frames_inside"]) + 1
			seen["raider_inside"] = bool(seen["raider_inside"]) or raider.ship.targeting.system.selected_id() == marker_id
			seen["radar_inside"] = bool(seen["radar_inside"]) or _on_radar(c)
			seen["hull_inside"] = bool(seen["hull_inside"]) or _a_hull_row(c)
		else:
			seen["depth_out"] = _depth(c)
		return not ship.inside_station, 120.0), "it came out past the doors' plane")
	assert_gt(int(seen["frames_inside"]), 60, "it waited in the void for the doors")
	assert_false(bool(seen["radar_inside"]), "never on the radar inside")
	assert_false(bool(seen["hull_inside"]), "never a hull to hit inside")
	assert_false(bool(seen["raider_inside"]), "the raider's AI never targeted it inside")
	assert_between(float(seen["depth_out"]), -2.0, 0.0, "out as its origin crossed the doors' plane")
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(main.traffic.inside_count(), 0)
	assert_true(c.targetable.is_active(), "a target again")
	assert_true(_on_radar(c), "on the radar again")
	assert_true(main.ship.targeting.select_id(marker_id), "the player selects it again")
	assert_true(_a_hull_row(c), "its hull can be hit again")
	assert_true(raider.ship.targeting.select_id(marker_id), "the raider's targeting selects it again")
	raider.ship.targeting.clear_selection()
	assert_true(await _until(func() -> bool: return raider.ship.targeting.system.selected_id() == marker_id, 40.0),
			"the raider's AI takes it once it is out (it holds %d)" % raider.ship.targeting.system.selected_id())
