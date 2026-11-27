extends GutTest
## The Centauri shuttle and the Minbari Flyer at Babylon 5's main docking bay (M10-T58, Q99), on the real main scene: each flies
## in through the mouth and the inner doors into the void without touching the bay, the shuttle with its wings folded from
## before the mouth; a shuttle coming out starts folded and spreads its wings once it is clear. Flown with the physics rate and
## the time scale raised together.

const SCENARIO: String = "res://data/scenarios/station_launch.json"
const SPEED_UP: float = 8.0
const VISITORS: Array[StringName] = [&"centauri_shuttle", &"minbari_flyer"]

var main: Main
var station: Station
var rams: int = 0
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()
	rams = 0
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
	for type: StringName in VISITORS:
		if not Hardpoints.load_file(ShipCatalog.spec_for(type).hardpoints_path()).valid:
			return false
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = SCENARIO
	main.raider_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	station = main.far_props.station
	if station == null:
		return false
	main.combatant.damageable.invulnerable = true
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	return true


func _until(done: Callable, limit_s: float) -> bool:
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < limit_s:
		if done.call():
			return true
		await get_tree().physics_frame
	return bool(done.call())


func _watch_rams(c: Combatant) -> void:
	c.damageable.hit_taken.connect(func(info: HitInfo) -> void:
		rams += 1 if info != null and info.cause == HitInfo.CAUSE_RAM else 0)


func test_the_shuttles_fold_is_data_and_the_flyer_has_none() -> void:
	assert_true(WingFold.folds_for_station("centauri_shuttle"))
	assert_eq(float(WingFold.of_asset("centauri_shuttle")["fold_deg"]), 110.0, "110 degrees up (Q99)")
	assert_false(WingFold.folds_for_station("minbari_flyer"), "the Flyer docks as it flies")
	assert_false(WingFold.folds_for_station("ea_atmo_shuttle"), "a liner's Kestrel fits the bay spread (T70)")
	for type: StringName in VISITORS:
		assert_true(DockingPlan.fits_tunnel(type), "%s lands in the main docking bay" % type)
		assert_false(DockingPlan.tunnel_types().has(type), "%s is not drawn where the scenario does not pool it" % type)
		assert_true(DockingPlan.tunnel_types({type: 1}).has(type), "%s is drawn where it is pooled" % type)


func test_each_visitor_flies_into_the_bay_untouched_the_shuttle_folded_from_before_the_mouth() -> void:
	if not await _start():
		pending("the station or a visitor's asset is not generated")
		return
	var lock: StationAirlock = station.airlock
	for type: StringName in VISITORS:
		rams = 0
		var before: int = main.traffic.docked_count
		var asked: ConsoleResult = DebugConsole.registry.execute("traffic dock %s near" % type)[0]
		assert_true(asked.ok, "\n".join(asked.lines))
		var mouth: Vector3 = main.traffic.plan.mouth
		var c: Combatant = main.traffic.last_ship()
		assert_not_null(c, "%s took the lane" % type)
		if c == null:
			continue
		assert_eq(main.ships.type_of(c), type, "as itself")
		_watch_rams(c)
		var ship: Ship = c.ship
		var reach: Vector2 = StationAirlock.hull_reach(ship)
		var seen: Dictionary = {"far_spread": false, "at_mouth": -1.0, "inside": false, "least_fold_inside": 1.0}
		var ok: bool = await _until(func() -> bool:
			if main.traffic.docked_count == before and is_instance_valid(ship) and main.traffic.state_of(c) != &"":
				var fold: WingFoldNode = WingFoldNode.of(ship)
				var amount: float = fold.amount if fold != null else 0.0
				var nose_z: float = station.to_local(ship.global_position).z + reach.x
				if nose_z < mouth.z - StationTraffic.FOLD_IN_M - 200.0:
					seen["far_spread"] = seen["far_spread"] or amount == 0.0
				if nose_z >= mouth.z:
					if float(seen["at_mouth"]) < 0.0:
						seen["at_mouth"] = amount
					seen["least_fold_inside"] = minf(float(seen["least_fold_inside"]), amount)
				seen["inside"] = seen["inside"] or ship.inside_station
			return main.traffic.docked_count > before, 200.0)
		assert_true(ok, "%s docked (%s)" % [type, main.traffic.last_event])
		assert_true(bool(seen["inside"]), "%s was inside the station before it left the world" % type)
		assert_eq(rams, 0, "%s without touching the turning bay or its doors" % type)
		if WingFold.folds_for_station(String(type)):
			assert_true(bool(seen["far_spread"]), "its wings are spread out on the approach")
			assert_eq(float(seen["at_mouth"]), 1.0, "and fully folded as its nose reaches the mouth")
			assert_eq(float(seen["least_fold_inside"]), 1.0, "and stay folded all the way in")
			assert_true(WingFoldNode.of(ship).is_spread(), "back in its pool they are spread again")
			assert_true(ship.hull.visible, "and it is drawn as its one-piece hull")
		else:
			assert_null(WingFoldNode.of(ship), "%s has no fold" % type)
		assert_true(await _until(func() -> bool: return lock.doors.is_shut(), 30.0), "the doors shut before the next one")


func test_a_shuttle_comes_out_folded_and_spreads_its_wings_once_clear() -> void:
	if not await _start():
		pending("the station or a visitor's asset is not generated")
		return
	assert_eq(main.traffic.undock(&"centauri_shuttle"), "")
	var c: Combatant = main.traffic.last_ship()
	assert_not_null(c)
	if c == null:
		return
	_watch_rams(c)
	var ship: Ship = c.ship
	var fold: WingFoldNode = WingFoldNode.of(ship)
	assert_not_null(fold, "it has its fold")
	if fold == null:
		return
	assert_true(fold.is_folded(), "it waited inside folded")
	var mouth: Vector3 = main.traffic.plan.mouth
	var far: Vector3 = main.traffic.plan.dock_in[0]["at"]
	var reach: Vector2 = StationAirlock.hull_reach(ship)
	var seen: Dictionary = {"least_in_bay": 1.0, "spread_at": INF}
	var out: bool = await _until(func() -> bool:
		if not is_instance_valid(ship):
			return false
		var local: Vector3 = station.to_local(ship.global_position)
		if local.z + reach.y > mouth.z:  # its tail still in the mouth
			seen["least_in_bay"] = minf(float(seen["least_in_bay"]), fold.amount)
		elif fold.is_spread() and float(seen["spread_at"]) == INF:
			seen["spread_at"] = mouth.z - local.z
		return local.z < far.z + 200.0, 150.0)
	assert_true(out, "it came out past the approach's far point")
	assert_eq(rams, 0, "without touching the bay or its doors")
	assert_eq(float(seen["least_in_bay"]), 1.0, "folded until its tail was out of the mouth")
	assert_lt(float(seen["spread_at"]), 600.0, "spread soon after (%.0f m out)" % float(seen["spread_at"]))
	assert_gt(float(seen["spread_at"]), StationTraffic.FOLD_OUT_M - 1.0, "and not before it was clear")


func test_dock_show_puts_the_player_beside_the_mouth_clear_of_the_lane() -> void:
	if not await _start():
		pending("the station or a visitor's asset is not generated")
		return
	var asked: ConsoleResult = DebugConsole.registry.execute("traffic dock minbari_flyer show")[0]
	assert_true(asked.ok, "\n".join(asked.lines))
	assert_eq(main.ships.type_of(main.traffic.last_ship()), &"minbari_flyer", "the hull named")
	var from_mouth: Vector3 = station.to_local(main.ship.global_position) - main.traffic.plan.mouth
	assert_almost_eq(from_mouth.z, -StationTraffic.DOCK_VIEW_OUT_M, 1.0, "outside the mouth")
	assert_gt(Vector2(from_mouth.x, from_mouth.y).length(), 60.0, "and well off the lane")
	var refused: ConsoleResult = DebugConsole.registry.execute("traffic dock saturn_3_freighter")[0]
	assert_false(refused.ok, "a Saturn never enters the tunnel")
