extends GutTest
## A respawn restarts only what a lesson needs (the instructor's route, `test_instructor_route`); the wings and the fight carry
## on (maintainer Q8: a downed wingman is replaced at the next wave; the play-test guide: the wingmen go back to their order).
## On `combat_sandbox` the player's three wingmen keep their slots, behaviours and orders through one respawn and a second; on
## `dogfight` the raiders already shot down stay down and every wing flies on. A ship joining a wing whose old member left play
## in the same tick still gets its slot, and a join the wing cannot take is reported. Back during the death delay is the only
## respawn: the pending one is cancelled. The real main scene, Jolt, the real drivers.

const DOGFIGHT_PATH: String = "res://data/scenarios/dogfight.json"

var main: Main


func before_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true  # the player is a bystander; deaths here are the console's
	ContactScan.invalidate()


func after_each() -> void:
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false
	ContactScan.invalidate()


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _launch(path: String) -> Main:
	var m := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	m.input_source = FakeInputSource.new()
	m.scenario_path = path
	m.waves_auto_start = false
	add_child_autofree(m)
	await _ticks(2)
	return m


func _pilot(c: Combatant) -> AiPilot:
	return c.driver.brain as AiPilot if c != null and c.driver != null else null


func _ship_named(ship_name: String) -> Combatant:
	for c: Combatant in main.ships.alive():
		if c.display_name == ship_name:
			return c
	return null


func _names(list: Array[Combatant]) -> PackedStringArray:
	var out := PackedStringArray()
	for c: Combatant in list:
		out.append(c.display_name)
	return out


# The player's wing as the scenario built it: ALPHA 2-4 in slots 1-3, each flying formation and rally, no slot down.
func _assert_sandbox_wing_whole(wing: Wing, when: String) -> void:
	assert_eq(wing.members().size(), 3, "%s: three wingmen" % when)
	for slot: int in range(1, 4):
		var member: Combatant = wing.member_at(slot)
		assert_not_null(member, "%s: slot %d flown" % [when, slot])
		assert_false(wing.is_lost(slot), "%s: slot %d is not down" % [when, slot])
		if member == null:
			continue
		assert_eq(member.display_name, wing.callsign(slot), "%s: slot %d keeps its callsign" % [when, slot])
		var pilot: AiPilot = _pilot(member)
		assert_not_null(pilot, "%s: %s has its pilot" % [when, member.display_name])
		if pilot != null:
			assert_not_null(pilot.behaviour(&"formation"), "%s: %s keeps its formation behaviour" % [when, member.display_name])
			assert_not_null(pilot.behaviour(&"rally"), "%s: %s keeps its rally behaviour" % [when, member.display_name])
	for row: Dictionary in main.wings.hud_roster():
		assert_false(bool(row["down"]), "%s: the HUD shows %s up" % [when, row["callsign"]])


func test_the_sandbox_wing_keeps_its_three_wingmen_through_two_respawns() -> void:
	main = await _launch(ScenarioLoader.SANDBOX_PATH)
	var wing: Wing = main.wings.player_wing()
	var before: Array[Combatant] = wing.members()
	_assert_sandbox_wing_whole(wing, "at load")
	for round_number: int in [1, 2]:
		main.respawn()
		await _ticks(2)
		_assert_sandbox_wing_whole(wing, "after respawn %d" % round_number)
	assert_eq(wing.members(), before, "the same three ships fly on, never placed again")
	var result: Dictionary = main.wings.give_order(AiContext.Order.FORM_ON_ME)
	assert_true(bool(result["ok"]), str(result["line"]))
	await _ticks(60)
	for member: Combatant in wing.members():
		assert_eq(_pilot(member).context.order, AiContext.Order.FORM_ON_ME, "%s takes the order" % member.display_name)
		assert_eq(str(_pilot(member).describe()["behaviour"]), "formation", "%s forms on the player" % member.display_name)


func test_dogfight_raiders_shot_down_stay_down_and_every_wing_flies_on() -> void:
	main = await _launch(DOGFIGHT_PATH)
	for victim: String in ["RAIDER 1", "RAIDER 5"]:  # RED's leader and one of BLUE's
		assert_true(_ship_named(victim).damageable.kill(), victim)
	await _ticks(2)
	assert_eq(main.ships.alive(ShipPool.DEFAULT_TYPE).size(), 4, "two raiders down before the respawn")
	var brains: Dictionary = {}
	for c: Combatant in main.ships.alive():
		brains[c.display_name] = c.driver.brain
	var wings_before: Dictionary = {}
	for wing: Wing in main.wings.wings:
		wings_before[wing.name] = [wing.leader.display_name if wing.leader != null else "", _names(wing.members())]
	main.respawn()
	await _ticks(2)
	assert_eq(main.ships.alive(ShipPool.DEFAULT_TYPE).size(), 4, "the raiders shot down stay down")
	assert_eq(main.ships.alive(ShipPool.ALLY_TYPE).size(), 4, "every Starfury still in play")
	for c: Combatant in main.ships.alive():
		assert_true(brains.has(c.display_name), "%s was in play before the respawn" % c.display_name)
		assert_same(c.driver.brain, brains.get(c.display_name), "%s flies on, not placed again" % c.display_name)
	for wing: Wing in main.wings.wings:
		var now: Array = [wing.leader.display_name if wing.leader != null else "", _names(wing.members())]
		assert_eq(now, wings_before.get(wing.name), "%s keeps its leader and members" % wing.name)
		for member: Combatant in wing.members():
			assert_not_null(_pilot(member).behaviour(&"formation"), "%s keeps its formation behaviour" % member.display_name)
			assert_not_null(_pilot(member).behaviour(&"rally"), "%s keeps its rally behaviour" % member.display_name)


func test_a_ship_joins_a_wing_whose_old_member_left_play_this_tick() -> void:
	main = await _launch(ScenarioLoader.SANDBOX_PATH)
	var wing: Wing = main.wings.player_wing()
	var old: Combatant = wing.member_at(1)
	main.ships.release(old)  # out of play, still in its slot until the wing is refreshed
	var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": "ally_starfury"}, UniversePos.new(), 11)
	var fresh: Combatant = main.ships.acquire("ALPHA 2", main.world.to_universe(main.ship.global_position).plus_local(
			Vector3(-40.0, 0.0, 40.0)), main.ship.global_basis, Vector3.ZERO, made["brain"] as PilotBrain, ShipPool.ALLY_TYPE)
	assert_ne(fresh, old, "a different pooled Starfury")
	assert_eq(main.wings.join("ALPHA", fresh), wing, "the wing takes it")
	assert_eq(wing.slot_of(fresh), 1, "in the slot the old member left")
	assert_eq(wing.members().size(), 3)
	assert_not_null(_pilot(fresh).behaviour(&"formation"), "briefed: formation")
	assert_not_null(_pilot(fresh).behaviour(&"rally"), "briefed: rally")


func test_a_join_the_wing_cannot_take_is_reported() -> void:
	main = await _launch(ScenarioLoader.SANDBOX_PATH)
	var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": "ally_starfury"}, UniversePos.new(), 12)
	var spare: Combatant = main.ships.acquire("ALPHA 5", main.world.to_universe(main.ship.global_position).plus_local(
			Vector3(0.0, 0.0, 120.0)), main.ship.global_basis, Vector3.ZERO, made["brain"] as PilotBrain, ShipPool.ALLY_TYPE)
	assert_null(main.wings.join("ALPHA", spare), "the wing is full")
	assert_push_warning("ALPHA 5 could not join ALPHA")


func test_back_while_dead_is_the_only_respawn() -> void:
	main = await _launch(ScenarioLoader.FREE_FLIGHT_PATH)
	var respawns: Array[int] = []
	main.player_respawned.connect(func() -> void: respawns.append(Engine.get_physics_frames()))
	DebugConsole.flags.invulnerable = false
	assert_true(DebugConsole.registry.execute("kill player")[0].ok)
	await _ticks(2)
	assert_true(main.director.respawn_pending())
	main.respawn()  # Back, during the death delay
	assert_false(main.director.respawn_pending(), "Back cancels the pending respawn")
	# Fly off; the cancelled timer must not put the ship back at the start 3 s after the death.
	var away := Vector3(0.0, 0.0, -50.0)
	var started_s: float = SimClock.now()
	while SimClock.now() < started_s + DestructionDirector.RESPAWN_DELAY_S + 0.5:
		main.ship.linear_velocity = away
		await _ticks(1)
	assert_eq(respawns.size(), 1, "one respawn, Back's")
	assert_almost_eq(main.ship.linear_velocity, away, Vector3.ONE * 1e-3, "nothing stopped the ship")

