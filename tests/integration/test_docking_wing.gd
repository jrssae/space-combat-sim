extends GutTest
## The player's wingmen while the player docks (M8-T06; maintainer's play-test, 2026-11-20: "ai wing starfuries must break off
## when the player docks to the main docking bay. they follow their last order of hold fire vs attack until the player's
## starfury is re-launched"). In `station_dock`: under a hold-fire order they leave the formation for a stand-off beside the
## bow, hold there and do not fire; under a fighting order they fight what comes; a wingman docking itself keeps doing that;
## after the launch, or at once on an abort, they are the player's wing again under the order they had. Flown with the
## physics rate and the time scale raised together.

const SCENARIO: String = "res://data/scenarios/station_dock.json"
const SPEED_UP: float = 8.0

var main: Main
var station: Station
var wing: Wing
var two: Combatant
var three: Combatant
var shots: Array[int] = [0]
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()
	shots = [0]
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	get_tree().paused = false
	ContactScan.invalidate()


func _start(raiders: int = 0) -> bool:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = SCENARIO
	main.raider_pool_size = raiders
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(2)
	station = main.far_props.station
	if station == null:
		return false
	main.combatant.damageable.invulnerable = true
	wing = main.wings.player_wing()
	two = _ship("ALPHA 2")
	three = _ship("ALPHA 3")
	for c: Combatant in [two, three]:
		c.cannon.shot_fired.connect(func(_muzzle: int, _at: Vector3) -> void: shots[0] += 1)
	return true


func _fast() -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _until(done: Callable, limit_s: float) -> bool:
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < limit_s:
		if done.call():
			return true
		await get_tree().physics_frame
	return bool(done.call())


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _ship(ship_name: String) -> Combatant:
	for c: Combatant in main.ships.alive():
		if c.display_name == ship_name:
			return c
	return null


func _pilot(c: Combatant) -> AiPilot:
	return c.driver.brain as AiPilot


# How far `ship` is from the docking lane's line, m.
func _off_lane(ship: Ship) -> float:
	var plan: DockingPlan = main.docking.plan
	var axis: Vector3 = (plan.mouth - (plan.dock_in[0]["at"] as Vector3)).normalized()
	return DockAutopilot.off_axis_m(station.global_transform.affine_inverse() * ship.global_position, plan.mouth, axis)


func _to_mouth(ship: Ship) -> float:
	return ship.global_position.distance_to(station.global_transform * main.docking.plan.mouth)


# What the roster says `c` is doing: the director's row and the HUD's tag for it.
func _roster(c: Combatant) -> Array[String]:
	for row: Dictionary in main.wings.hud_roster():
		if row["callsign"] == c.display_name:
			return [str(row["behaviour"]), HudLayout.roster_tag(str(row["behaviour"]), str(row["target"]), bool(row["down"]))]
	return ["", ""]


# A raider `out_m` to the side of the player, flying `brain`.
func _raider(raider_name: String, out_m: float, behaviour: Dictionary) -> Combatant:
	var at: Vector3 = main.ship.global_position + station.global_basis.x * out_m + station.global_basis.y * -300.0
	var made: Dictionary = BrainFactory.from_behaviour(behaviour, main.world.to_universe(at), hash(raider_name))
	assert_true(bool(made["ok"]), str(made.get("error", "")))
	var raider: Combatant = main.ships.acquire(raider_name, main.world.to_universe(at), Basis.IDENTITY, main.world.rest_velocity(),
			made["brain"] as PilotBrain, ShipPool.DEFAULT_TYPE)
	assert_not_null(raider)
	return raider


func _assert_broken_off(order: AiContext.Order, label: String) -> void:
	assert_true(wing.leader_away, "%s: the wing knows its leader is docking" % label)
	for c: Combatant in [two, three]:
		var ctx: AiContext = _pilot(c).context
		assert_eq(ctx.order, order, "%s: %s flies %s" % [label, c.display_name, AiContext.order_word(order)])
		assert_false(ctx.has_slot, "%s: %s holds no slot on the docking player" % [label, c.display_name])
		assert_eq(ctx.leader_id, 0, "%s: and follows nobody" % label)
		assert_not_null(ctx.route, "%s: %s has its stand-off" % [label, c.display_name])
		assert_eq(ctx.route.name if ctx.route != null else "", DockingDirector.STAND_OFF_ROUTE)


func _assert_rejoined(order: AiContext.Order, label: String) -> void:
	assert_false(wing.leader_away, "%s: the leader is back" % label)
	assert_eq(wing.order, order, "%s: the wing's order is the one it had" % label)
	for c: Combatant in [two, three]:
		var ctx: AiContext = _pilot(c).context
		assert_eq(ctx.order, order, "%s: %s is back under %s" % [label, c.display_name, AiContext.order_word(order)])
		assert_true(ctx.has_slot, "%s: %s has its slot again" % [label, c.display_name])
		assert_ne(ctx.leader_id, 0)
		assert_null(ctx.route, "%s: the stand-off is forgotten" % label)


func test_under_form_up_hold_fire_the_wingmen_hold_clear_do_not_fire_and_rejoin_after_the_launch() -> void:
	if not await _start(1):
		pending("the babylon5_station asset is not generated")
		return
	assert_true(_run("wing order form_hold").ok)
	# A raider sitting 900 m off, in easy reach: they hold their fire all the same.
	var raider: Combatant = _raider("RAIDER 1", 900.0, {"type": "idle", "hold": true})
	raider.damageable.invulnerable = true
	await _ticks(5)
	var start_to_mouth: float = minf(_to_mouth(two.ship), _to_mouth(three.ship))
	assert_true(_run("dock player").ok)
	await _ticks(3)
	_assert_broken_off(AiContext.Order.FORM_HOLD_FIRE, "docking")
	assert_false(_pilot(two).context.route.yield_to_attack, "a hold-fire stand-off stands aside for no fight")
	_fast()
	var nearest_mouth: Array[float] = [INF]
	var held: Array[bool] = [false]
	var ok: bool = await _until(func() -> bool:
		for c: Combatant in [two, three]:
			nearest_mouth[0] = minf(nearest_mouth[0], _to_mouth(c.ship))
		if not held[0] and _roster(two)[0] == "holding":
			held[0] = true
			assert_eq(_roster(two)[1], "HOLD", "the roster's row says so")
		return main.docking.docked_count == 1, 150.0)
	assert_true(ok, "the player docks (%s)" % main.docking.describe())
	assert_true(held[0], "the roster read HOLD while they stood off")
	assert_gt(nearest_mouth[0], start_to_mouth - 100.0, "no wingman followed the player toward the bay (nearest %.0f m, from %.0f m)" % [
			nearest_mouth[0], start_to_mouth])
	assert_true(wing.leader_away, "inside and on the rack they stay broken off")
	assert_true(await _until(func() -> bool: return main.docking.player_visit() == null, 60.0), "launched again")
	for c: Combatant in [two, three]:
		assert_gt(_off_lane(c.ship), 600.0, "%s stood well clear of the docking lane (%.0f m off it)" % [c.display_name, _off_lane(c.ship)])
	assert_eq(shots[0], 0, "and never fired, with a raider in reach")
	await _ticks(2)
	_assert_rejoined(AiContext.Order.FORM_HOLD_FIRE, "after the launch")
	var leader: Ship = main.ship
	ok = await _until(func() -> bool:
		return two.ship.global_position.distance_to(leader.global_position) < 700.0 \
				and three.ship.global_position.distance_to(leader.global_position) < 700.0, 300.0)
	assert_true(ok, "they form up on the player again (%.0f m and %.0f m off)" % [two.ship.global_position.distance_to(leader.global_position),
			three.ship.global_position.distance_to(leader.global_position)])
	assert_eq(shots[0], 0, "still holding their fire")


func test_under_form_on_me_the_wingmen_fight_what_comes_and_rejoin_after_the_launch() -> void:
	if not await _start(2):
		pending("the babylon5_station asset is not generated")
		return
	assert_eq(wing.order, AiContext.Order.FORM_ON_ME, "the scenario's order")
	for c: Combatant in [two, three]:
		c.damageable.invulnerable = true  # the fight, not their losses
	for n: int in 2:
		_raider("RAIDER %d" % (n + 1), 1800.0 + 200.0 * float(n), {"type": "ai", "profile": "raider"})
	await _ticks(5)
	assert_eq(shots[0], 0, "in formation under FORM ON ME nothing was in their guns' reach yet")
	assert_true(_run("dock player").ok)
	await _ticks(3)
	_assert_broken_off(AiContext.Order.ENGAGE_AT_WILL, "docking")
	assert_true(_pilot(two).context.route.yield_to_attack, "the stand-off stands aside for a fight")
	_fast()
	var attacked: Array[bool] = [false]
	var ok: bool = await _until(func() -> bool:
		for c: Combatant in [two, three]:
			var pilot: AiPilot = _pilot(c)
			attacked[0] = attacked[0] or (pilot.current != null and pilot.current.id == &"attack")
		return main.docking.player_visit() == null and main.docking.docked_count == 1, 240.0)
	assert_true(ok, "the player docks and launches again (%s)" % main.docking.describe())
	assert_true(attacked[0], "the wingmen went for the raiders on their own")
	assert_gt(shots[0], 0, "and fired")
	await _ticks(2)
	_assert_rejoined(AiContext.Order.FORM_ON_ME, "after the launch")


func test_an_abort_brings_the_wingmen_back_at_once() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	assert_true(_run("dock player").ok)
	await _ticks(30)
	_assert_broken_off(AiContext.Order.ENGAGE_AT_WILL, "docking")
	assert_true(main.docking.abort_offered())
	assert_eq(main.docking.abort(), "", "the pilot aborts")
	_assert_rejoined(AiContext.Order.FORM_ON_ME, "the tick of the abort")
	await _ticks(2)
	_assert_rejoined(AiContext.Order.FORM_ON_ME, "after the abort")
	assert_false(main.controls_locked())


func test_a_wingman_that_is_docking_itself_keeps_docking() -> void:
	if not await _start():
		pending("the babylon5_station asset is not generated")
		return
	three.damageable.hull.apply(three.damageable.hull.max_hp * 0.85)
	await _ticks(3)
	assert_not_null(main.docking.visit_of("ALPHA 3"), "below 25 % it goes to dock")
	var docker: PilotBrain = three.driver.brain
	assert_true(_run("dock player").ok)
	await _ticks(5)
	assert_eq(three.driver.brain, docker, "its docking pilot flies on")
	assert_ne((docker as AiPilot).context.route.name, DockingDirector.STAND_OFF_ROUTE, "on its way to the bay, not to a stand-off")
	assert_not_null(main.docking.visit_of("ALPHA 3"))
	assert_eq(_roster(three)[1], "DOCKING", "its row still reads DOCKING")
	assert_eq(_pilot(two).context.route.name, DockingDirector.STAND_OFF_ROUTE, "the other wingman stands off")
