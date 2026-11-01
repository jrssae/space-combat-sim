extends GutTest
## Broadcast contacts, the AI's half, and the pilot objective (M3-T17, Q21, AC25): every AI ship hears the same broadcasts at
## the same ranges whatever its faction (a separate `Perception.broadcasts` list; `contacts`, which avoidance and the fire lane
## read, stay the near 5 km scan), and a raider given a buoy as its objective (`ai <name> objective <target>`, or the spawn's
## `objective`) flies to it from 200 km and closes inside 2 km.

const FAR_BUOY_M: float = 900000.0

var main: Main
var _scale_backup: float = 1.0


func before_each() -> void:
	_scale_backup = Engine.time_scale
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.waves_auto_start = false
	main.ally_pool_size = 8  # the sandbox's three wingmen (M3-T10) and room for this test's allies
	add_child_autofree(main)
	await _ticks(2)


func after_each() -> void:
	Engine.time_scale = _scale_backup
	DebugConsole.flags.invulnerable = false


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _exec(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _buoy(buoy_name: String) -> NavBuoy:
	for buoy: NavBuoy in main.buoys:
		if buoy.display_name == buoy_name:
			return buoy
	return null


func _from_player(offset: Vector3) -> UniversePos:
	return main.world.to_universe(main.ship.global_position).plus_local(offset)


func _place_buoy(buoy_name: String, offset: Vector3) -> NavBuoy:
	var buoy: NavBuoy = _buoy(buoy_name)
	buoy.velocity = Vector3.ZERO
	buoy.global_position = main.world.universe_to_local(_from_player(offset))
	return buoy


func _ai_ship(ship_name: String, type: StringName, offset: Vector3, behaviour: Dictionary = {}) -> Combatant:
	var spec: Dictionary = {"type": "ai", "profile": "raider" if type == ShipPool.DEFAULT_TYPE else "ally_starfury"}
	spec.merge(behaviour, true)
	var made: Dictionary = BrainFactory.from_behaviour(spec, _from_player(Vector3.ZERO), hash(ship_name))
	assert_true(bool(made["ok"]), str(made.get("error", "")))
	return main.ships.acquire(ship_name, _from_player(offset), Basis.IDENTITY, Vector3.ZERO, made["brain"] as PilotBrain, type)


func _names(contacts: Array[Contact]) -> PackedStringArray:
	var out := PackedStringArray()
	for c: Contact in contacts:
		out.append(c.name)
	return out


func _perceive(combatant: Combatant) -> Perception:
	ContactScan.invalidate()
	return combatant.driver.perceive()


func test_every_ai_ship_hears_the_same_broadcasts_and_its_contacts_stay_near() -> void:
	_place_buoy("NAV ALPHA", Vector3(0.0, 0.0, -FAR_BUOY_M))
	var raider: Combatant = _ai_ship("RAIDER 9", ShipPool.DEFAULT_TYPE, Vector3(0.0, 0.0, -1000.0))
	var ally: Combatant = _ai_ship("ALPHA 6", ShipPool.ALLY_TYPE, Vector3(0.0, 0.0, -1200.0))
	main.ships.acquire("ALPHA 7", _from_player(Vector3(90000.0, 0.0, -1000.0)), Basis.IDENTITY, Vector3.ZERO, null, ShipPool.ALLY_TYPE)
	main.ships.acquire("ALPHA 8", _from_player(Vector3(-110000.0, 0.0, -1000.0)), Basis.IDENTITY, Vector3.ZERO, null, ShipPool.ALLY_TYPE)
	await _ticks(2)
	for who: Combatant in [raider, ally]:
		var p: Perception = _perceive(who)
		var heard: PackedStringArray = _names(p.broadcasts)
		assert_has(heard, "NAV ALPHA", "%s hears the 900 km buoy" % who.display_name)
		assert_has(heard, "ALPHA 7", "and the 90 km ally")
		assert_does_not_have(heard, "ALPHA 8", "not the 110 km one")
		assert_does_not_have(heard, "NAV BRAVO", "a buoy inside 5 km is a near contact, not a broadcast")
		var near: PackedStringArray = _names(p.contacts)
		assert_has(near, "NAV BRAVO")
		assert_does_not_have(near, "NAV ALPHA", "avoidance and the fire lane see only the near scan")
		assert_does_not_have(near, "ALPHA 7")
		var alliance: Contact = p.broadcasts[heard.find("ALPHA 7")]
		assert_eq(alliance.relation, Factions.relation(who.faction, Factions.EARTH_ALLIANCE), "stamped with the hearer's relation")
	var far_buoy: Contact = _perceive(raider).broadcasts[_names(_perceive(raider).broadcasts).find("NAV ALPHA")]
	assert_almost_eq(far_buoy.position.distance_to(raider.ship.global_position), FAR_BUOY_M - 1000.0, 2.0)


func test_the_console_sets_and_clears_an_objective() -> void:
	var raider: Combatant = _ai_ship("RAIDER 9", ShipPool.DEFAULT_TYPE, Vector3(0.0, 0.0, -30000.0))
	await _ticks(1)
	var pilot := raider.driver.brain as AiPilot
	var result: ConsoleResult = _exec("ai RAIDER 9 objective NAV ALPHA")
	assert_true(result.ok, str(result.lines))
	assert_eq(pilot.context.objective_name, "NAV ALPHA")
	await _ticks(2)
	assert_eq(pilot.describe().get("objective"), "NAV ALPHA")
	assert_false(_exec("ai RAIDER 9 objective NAV NOWHERE").ok, "an unknown target is refused")
	assert_eq(pilot.context.objective_name, "NAV ALPHA", "and changes nothing")
	assert_true(_exec("ai raider 9 objective none").ok)
	assert_eq(pilot.context.objective_name, "")
	assert_true(_exec("ai RAIDER 9").ok, "the plain describe still works")


func test_a_spawns_objective_reaches_the_pilot() -> void:
	var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": "raider", "objective": "NAV ALPHA"},
			UniversePos.new(), 1)
	assert_true(bool(made["ok"]))
	assert_eq((made["brain"] as AiPilot).context.objective_name, "NAV ALPHA")
	var bad: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": "raider", "objective": 7}, UniversePos.new(), 1)
	assert_false(bool(bad["ok"]), "objective must be a name")


func test_a_raider_flies_to_its_objective_from_200_km_and_closes_inside_2_km() -> void:
	var buoy: NavBuoy = _place_buoy("NAV ALPHA", Vector3(0.0, 0.0, -50000.0))
	var raider: Combatant = _ai_ship("RAIDER 9", ShipPool.DEFAULT_TYPE, Vector3(0.0, 0.0, -250000.0), {"objective": "NAV ALPHA"})
	var start_m: float = raider.ship.global_position.distance_to(buoy.global_position)
	assert_almost_eq(start_m, 200000.0, 5.0)
	Engine.time_scale = 8.0
	var t0: float = SimClock.now()
	var closest: float = INF
	var top_speed: float = 0.0
	while SimClock.now() - t0 < 900.0 and closest > 2000.0 and raider.ship.can_process():
		await _ticks(1)
		closest = minf(closest, raider.ship.global_position.distance_to(buoy.global_position))
		top_speed = maxf(top_speed, raider.ship.linear_velocity.length())
	Engine.time_scale = 1.0
	gut.p("objective: 200 km closed to %.0f m in %.0f s, top speed %.0f m/s" % [closest, SimClock.now() - t0, top_speed])
	assert_lt(closest, 2000.0, "closed inside 2 km")
	assert_eq((raider.driver.brain as AiPilot).current.id, &"attack", "attacking it")
	assert_eq(raider.ship.targeting.selected_name(), "NAV ALPHA", "with it selected")
