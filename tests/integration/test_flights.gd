extends GutTest
## Flights of three on the real main scene (M8-T19, D85, AC15): a wing declared `flight` that the player leads is the
## player's own flight of two wingmen, and the wing orders reach only those two; the rest of the squadron, a scenario's or
## the ships a Cobra arm launches, flies in flights of three under its own leads, whose pilots get the flights' rules; a
## station's own wing launches as four flights.

const SCENARIO: String = "res://tests/fixtures/flights/scenario_flights.json"
const STATION: String = "res://tests/fixtures/flights/station_flight.json"

## The launch is waited out at this many times real time.
const SPEED_UP: float = 8.0

var main: Main
var rules: FlightRules
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


func _start(scenario: String) -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = scenario
	main.raider_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(3)
	rules = main.wings.flight_rules


func test_the_player_commands_two_wingmen_and_the_rest_of_the_wing_flies_in_flights() -> void:
	await _start(SCENARIO)
	var own: Wing = main.wings.player_wing()
	assert_eq(own.leader, main.combatant)
	assert_eq(own.flight, 1, "the player's own flight")
	assert_eq(own.size, 2, "two wingmen")
	assert_eq(_names(own.members()), ["ALPHA 2", "ALPHA 3"] as Array[String])
	var alpha: Array[Wing] = main.wings.flights_of("alpha")
	assert_eq(alpha.size(), 2, "the player's flight and one more")
	assert_eq(alpha[0], own)
	var second: Wing = alpha[1]
	assert_eq(second.flight, 2)
	assert_eq(second.leader.display_name, "ALPHA 4", "the fourth ship leads the second flight")
	assert_eq(_names(second.members()), ["ALPHA 5", "ALPHA 6"] as Array[String])
	assert_eq(second.callsign(0), "ALPHA 4", "its callsigns run on")
	assert_eq(second.order, AiContext.Order.ENGAGE_AT_WILL, "under its own AI, whatever the player's order")
	assert_eq(_read("wing.flights"), PackedStringArray(["1: PLAYER + ALPHA 2, ALPHA 3", "2: ALPHA 4 + ALPHA 5, ALPHA 6"]))
	# The pilots: the player's two follow its order; the AI flight's cover each other and stay near their lead.
	for c: Combatant in own.members():
		var ctx: AiContext = _ctx(c)
		assert_eq(ctx.order, AiContext.Order.FORM_ON_ME, c.display_name)
		assert_false(ctx.cover, "%s follows the player's orders" % c.display_name)
		assert_eq(ctx.cohesion_m, 0.0)
	for c: Combatant in second.members():
		var ctx: AiContext = _ctx(c)
		assert_eq(ctx.order, AiContext.Order.ENGAGE_AT_WILL, c.display_name)
		assert_eq(ctx.leader_id, second.leader.targetable.get_instance_id(), "%s flies on ALPHA 4" % c.display_name)
		assert_true(ctx.cover)
		assert_eq(ctx.cohesion_m, rules.cohesion_m)
		assert_eq(ctx.rejoined_m, rules.rejoined_m)
		assert_eq(ctx.slot_offset, Formation.new().offset(second.slot_of(c), 2))
	var lead: AiContext = _ctx(second.leader)
	assert_true(lead.cover, "the lead covers its flight")
	assert_eq(lead.cohesion_m, 0.0, "and is the one the others stay near")
	assert_false(lead.has_slot, "it does not form on the player")
	# The orders reach only the player's two.
	for order: AiContext.Order in [AiContext.Order.FORM_HOLD_FIRE, AiContext.Order.HOLD_POSITION, AiContext.Order.COVER_ME]:
		var result: Dictionary = main.wings.give_order(order)
		assert_true(result["ok"])
		assert_string_starts_with(result["line"], "ALPHA 2: COPY", "one of the player's own answers")
		await _ticks(2)
		for c: Combatant in own.members():
			assert_eq(_ctx(c).order, order, "%s takes the order" % c.display_name)
		assert_eq(_ctx(second.leader).order, AiContext.Order.ENGAGE_AT_WILL, "ALPHA 4 flies on under its own AI")
		for c: Combatant in second.members():
			assert_eq(_ctx(c).order, AiContext.Order.ENGAGE_AT_WILL, "%s too" % c.display_name)
	assert_eq(main.wings.hud_roster().size(), 2, "the roster is the player's flight")
	# A wingman lost leaves its place open in the player's flight: nobody is taken from the others.
	own.members()[0].damageable.kill()
	await _ticks(2)
	assert_eq(_names(own.members()), ["ALPHA 3"] as Array[String])
	assert_eq(_names(second.members()), ["ALPHA 5", "ALPHA 6"] as Array[String])
	assert_eq(main.wings.hud_roster().size(), 2, "the lost wingman reads DOWN")


func test_an_ai_squadron_flies_as_flights_whose_leads_form_on_the_first() -> void:
	await _start(SCENARIO)
	var beta: Array[Wing] = main.wings.flights_of("BETA")
	assert_eq(beta.size(), 2, "four ships: a flight of three and a short one")
	assert_eq(beta[0].leader.display_name, "BETA 1")
	assert_eq(_names(beta[0].members()), ["BETA 2", "BETA 3"] as Array[String])
	assert_eq(beta[1].leader.display_name, "BETA 4")
	assert_eq(beta[1].members().size(), 0)
	assert_eq(beta[1].first_number, 4)
	assert_eq(main.wings.squadron_lead("beta"), beta[0].leader)
	assert_eq(main.wings.flight_strength("BETA"), 4)
	var first: AiContext = _ctx(beta[0].leader)
	assert_false(first.has_slot, "the squadron's lead forms on nobody")
	assert_true(first.cover)
	var second: AiContext = _ctx(beta[1].leader)
	assert_true(second.has_slot, "the second flight's lead holds a slot on the first's")
	assert_eq(second.leader_id, beta[0].leader.targetable.get_instance_id())
	assert_eq(second.slot_offset, Formation.new(Formation.Shape.FINGER_FOUR, Formation.DEFAULT_SPACING_M * rules.lead_spacing).offset(1))
	assert_eq(second.cohesion_m, 0.0, "a lead is not held to a distance")
	assert_not_null((beta[1].leader.driver.brain as AiPilot).behaviour(&"formation"), "it can fly the slot")
	# With nothing to fight the flights form up: wingmen on their leads, the second lead on the first.
	await _ticks(600)
	for c: Combatant in beta[0].members():
		assert_eq((c.driver.brain as AiPilot).current.id, &"formation", c.display_name)
		assert_lt(c.ship.global_position.distance_to(beta[0].leader.ship.global_position), 150.0, "%s is with its lead" % c.display_name)
	assert_eq((beta[1].leader.driver.brain as AiPilot).current.id, &"formation", "BETA 4 forms on BETA 1")
	# The lead lost: the lowest slot leads its flight on, keeps its callsign, and is the squadron's lead now.
	beta[0].leader.damageable.kill()
	await _ticks(2)
	assert_eq(beta[0].leader.display_name, "BETA 2")
	assert_eq(_names(beta[0].members()), ["BETA 3"] as Array[String])
	assert_eq(main.wings.squadron_lead("BETA"), beta[0].leader)
	assert_eq(_ctx(beta[1].leader).leader_id, beta[0].leader.targetable.get_instance_id(), "BETA 4 forms on the new lead")
	assert_true(_ctx(beta[0].leader).cover, "the new lead is briefed as one")
	assert_eq(_ctx(beta[0].leader).cohesion_m, 0.0)
	# The next ship to join takes the flight's open place under the free callsign; with the first flight full it is the second's.
	var place: Dictionary = main.wings.next_flight_place("BETA")
	assert_eq(place["wing"], beta[0])
	assert_gt(int(place["slot"]), 0)
	assert_eq(main.wings.place_callsign(place), "BETA 1", "the downed lead's number is free again")
	var third: Dictionary = main.wings.next_flight_place("BETA", 3)
	assert_eq((third["wing"] as Wing).flight, 3, "asked for the flights from 3 on, a new one is made")
	assert_eq((third["wing"] as Wing).callsign(0), "BETA 7")
	main.wings.drop_empty_flights("BETA")
	assert_eq(main.wings.flights_of("BETA").size(), 2, "a flight nobody took is dropped")


func test_a_launched_wing_fills_the_players_flight_first_and_flies_the_rest_as_flights() -> void:
	await _start(STATION)
	if main.far_props.station == null:
		pending("the babylon5_station asset is not generated")
		return
	var own: Wing = main.wings.player_wing()
	assert_eq(own.size, 2)
	assert_eq(_names(own.members()), ["ALPHA 2", "ALPHA 3"] as Array[String])
	var result: ConsoleResult = DebugConsole.registry.execute("launch wing alpha")[0]
	assert_true(result.ok, result.error)
	var ships: Array = (main.launches.launches[-1]["ships"] as Dictionary).values()
	assert_eq(ships.size(), LaunchDirector.WING_SIZE - 3, "the rest of Alpha: twelve less the player's flight")
	assert_eq(own.size, 2, "the player's flight did not grow")
	assert_eq(_names(own.members()), ["ALPHA 2", "ALPHA 3"] as Array[String])
	var flights: Array[Wing] = main.wings.flights_of("ALPHA")
	assert_eq(flights.size(), 4)
	for k: int in range(1, 4):
		var flight: Wing = flights[k]
		assert_eq(flight.flight, k + 1)
		assert_eq(flight.leader.display_name, "ALPHA %d" % (3 * k + 1))
		assert_eq(_names(flight.members()), ["ALPHA %d" % (3 * k + 2), "ALPHA %d" % (3 * k + 3)] as Array[String])
		assert_eq(flight.home, &"babylon5", "the station's own: it docks here")
		assert_eq(flight.leader.home, &"babylon5")
		assert_false(_ctx(flight.leader).order == AiContext.Order.COVER_ME, "not on the player's order")
	assert_eq(main.wings.flight_strength("ALPHA"), LaunchDirector.WING_SIZE)
	# The player's orders reach its two wingmen only.
	assert_true(DebugConsole.registry.execute("wing order form_hold")[0].ok)
	await _ticks(2)
	for c: Combatant in own.members():
		assert_eq(_ctx(c).order, AiContext.Order.FORM_HOLD_FIRE, c.display_name)
	for k: int in range(1, 4):
		for c: Combatant in flights[k].members():
			assert_eq(_ctx(c).order, AiContext.Order.ENGAGE_AT_WILL, c.display_name)
	# Every place is flown: once the arm is clear, nothing more launches for Alpha.
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	for i: int in 6000:
		if not main.launches.is_launching("alpha"):
			break
		await _ticks(1)
	assert_false(main.launches.is_launching("alpha"), "the launch is over")
	assert_string_contains(main.launches.launch_wing("alpha"), "every place of its flights is flown")
	# A station's own wing is four flights of three.
	assert_true(DebugConsole.registry.execute("launch wing zeta")[0].ok)
	var zeta: Array[Wing] = main.wings.flights_of("ZETA")
	assert_eq(zeta.size(), 4)
	for k: int in 4:
		assert_eq(zeta[k].leader.display_name, "ZETA %d" % (3 * k + 1))
		assert_eq(zeta[k].members().size(), 2)
		assert_eq(zeta[k].order, AiContext.Order.ENGAGE_AT_WILL)
	assert_false(_ctx(zeta[0].leader).has_slot)
	for k: int in range(1, 4):
		assert_eq(_ctx(zeta[k].leader).leader_id, zeta[0].leader.targetable.get_instance_id(), "flight %d forms on ZETA 1" % (k + 1))


func test_a_wing_of_flights_names_no_leader_but_the_player() -> void:
	var base: Dictionary = {"scenario_id": "x", "player": {"position": [0, 0, 0]}, "pools": {"starfury_ally": 1},
			"wings": [{"name": "BETA", "leader": "BETA 1", "flight": true, "members": [{"type": "starfury_ally", "name": "BETA 1",
			"behaviour": {"type": "ai", "profile": "ally_starfury"}}]}]}
	var named: Dictionary = ScenarioLoader.from_data(base, "t")
	assert_false(named["ok"])
	assert_string_contains(named["error"], "a wing of flights names no leader")
	((base["wings"] as Array)[0] as Dictionary)["leader"] = ""
	var plain: Dictionary = ScenarioLoader.from_data(base, "t")
	assert_true(plain["ok"], str(plain.get("error", "")))
	assert_true((plain["wings"] as Array)[0]["flight"])
	((base["wings"] as Array)[0] as Dictionary)["flight"] = "yes"
	assert_string_contains(ScenarioLoader.from_data(base, "t")["error"], "flight must be true or false")
	var loaded: Dictionary = ScenarioLoader.load(SCENARIO)
	assert_true(loaded["ok"], str(loaded.get("error", "")))


func _ctx(c: Combatant) -> AiContext:
	return (c.driver.brain as AiPilot).context


func _names(list: Array[Combatant]) -> Array[String]:
	var out: Array[String] = []
	for c: Combatant in list:
		out.append(c.display_name)
	return out


func _read(path: String) -> Variant:
	var read: Dictionary = DebugConsole.registry.read(path)
	assert_true(read["ok"], "%s: %s" % [path, read["error"]])
	return read["value"]


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame
