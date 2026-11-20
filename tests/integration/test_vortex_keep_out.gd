extends GutTest
## AI ships keep clear of jump vortices, and the player's wingmen at a jump (M8-T17; maintainer, 2026-11-20), on the real main
## scene: an AI ship whose way lies through the gate's funnel flies round it while a vortex is announced or open; under FORM ON
## ME the wingmen follow the player through the gate and come back out with it, alive; under a fighting order they break off,
## keep clear of the vortex and rejoin once the player is back.

const STARFURY_SPEC: String = "res://assets/ships/starfury_aurora.tres"

var main: Main
var gate: Jumpgate
var wing: Wing


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func after_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func _start() -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.raider_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(3)
	gate = main.gates.gate()
	wing = main.wings.player_wing()


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _until(done: Callable, limit: int) -> bool:
	for i: int in limit:
		if done.call():
			return true
		await get_tree().physics_frame
	return bool(done.call())


# An AI Starfury of the Earth Alliance at `at`, facing `forward`; in the player's wing at `slot` when it is above 0.
func _ally(name: String, at: Vector3, forward: Vector3, slot: int = 0) -> Combatant:
	var ally: Combatant = ShipAssembly.build(load(STARFURY_SPEC) as ShipSpec, main.world, main.projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: name,
		ShipAssembly.OPT_FORCE_ASSIST: true,
		ShipAssembly.OPT_AI: true,
	})
	main.world.spawn(ally.ship, main.world.to_universe(at), Basis.looking_at(forward, Vector3.UP))
	ally.ship.linear_velocity = main.world.rest_velocity()
	ally.driver.brain = BrainFactory.from_behaviour({"type": "ai", "profile": "ally_starfury"}, UniversePos.new(),
			hash(name))["brain"] as AiPilot
	ally.ship.tier_exempt = true
	if slot > 0:
		assert_eq(main.wings.add_member(wing, ally), slot)
	return ally


# How far `ship` is outside the volume the AI keeps out of round the gate's vortex (negative: inside it).
func _clearance(ship: Node3D) -> float:
	var v: Dictionary = VortexKeepOuts.volume(gate.vortex)
	var a: Vector3 = v["a"]
	var b: Vector3 = v["b"]
	var ab: Vector3 = b - a
	var t: float = clampf((ship.global_position - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return ship.global_position.distance_to(a + ab * t) - float(v["radius"])


# Two wingmen in their slots beside the player, 1.9 km in front of the gate, under `order`.
func _wing_at_the_gate(order: String) -> Array[Combatant]:
	assert_true(main.gates._cmd_gate({&"action": &"approach", &"option": "1.9"}).ok)
	await _ticks(2)
	var basis: Basis = main.ship.global_basis
	var out: Array[Combatant] = []
	for slot: int in [1, 2]:
		var at: Vector3 = Formation.slot_point(main.ship.global_position, -basis.z, basis.y, wing.slot_offset(slot))
		out.append(_ally(wing.callsign(slot), at, -basis.z, slot))
	assert_true(DebugConsole.registry.execute("wing order %s" % order)[0].ok)
	await _ticks(10)
	return out


func test_an_ai_ship_flies_round_a_vortex_announced_across_its_way() -> void:
	await _start()
	assert_true(main.gates._cmd_gate({&"action": &"approach", &"option": "5"}).ok, "the player in front, its ships flown in full")
	await _ticks(2)
	var frame: Transform3D = gate.vortex.true_frame()
	var ship: Combatant = _ally("CROSSING", frame * Vector3(-4200.0, 0.0, 600.0), frame.basis.x)
	var route := Route.new()
	route.name = "ACROSS THE FUNNEL"
	route.pace = Route.PACE_NONE
	route.cruise_mps = 150.0
	route.add(main.world.to_universe(frame * Vector3(4200.0, 0.0, 600.0)), &"", 1.0e9)
	BehaviourFollowPath.attach(ship.driver.brain as AiPilot, route)
	assert_true(main.gates._cmd_gate({&"action": &"open", &"option": "arrival", &"hold_s": 40.0}).ok)
	await _ticks(3)
	var keep: VortexKeepOuts = main.world.get_node_or_null(NodePath(VortexKeepOuts.NODE_NAME)) as VortexKeepOuts
	assert_not_null(keep)
	assert_eq(keep.volumes, 1, "the announced vortex is a no-go volume")
	assert_eq(NativeBrains.host(get_tree()).keep_out_count(), 1, "and the native brains have it")
	var closest: float = INF
	var crossed: bool = false
	for i: int in 60 * 60:
		await get_tree().physics_frame
		if not gate.vortex.is_active():
			break
		closest = minf(closest, _clearance(ship.ship))
		crossed = crossed or (frame.affine_inverse() * ship.ship.global_position).x > 0.0
	assert_false(ship.damageable.hull.destroyed, "it lived")
	assert_gt(closest, -50.0, "it kept out of the funnel and its margin (closest %.0f m)" % closest)
	assert_true(crossed, "and got past it, round the side")
	assert_true(await _until(func() -> bool: return not gate.vortex.is_active(), 60 * 30), "the vortex folded")
	await _ticks(3)
	assert_eq(NativeBrains.host(get_tree()).keep_out_count(), 0, "folded: no volume left")


func test_wingmen_under_form_on_me_jump_with_the_player_and_come_back_out_alive() -> void:
	await _start()
	var wingmen: Array[Combatant] = await _wing_at_the_gate("form")
	assert_eq(main.gates.start_jump(gate), "")
	assert_true(await _until(func() -> bool: return not main.gates.jump.is_active(), 60 * 60), "the round trip ended")
	assert_eq(main.gates.jump.completed, 1, "out and back (%s)" % main.gates.jump.ended_why)
	assert_eq(main.gates.wing_jump.carried, 2, "both wingmen went through and came back out with the player")
	for c: Combatant in wingmen:
		assert_false(c.damageable.hull.destroyed, "%s lived" % c.display_name)
		assert_true(c.ship.visible, "%s is back in sight" % c.display_name)
		assert_false(wing.is_away(c), "%s flies its slot again" % c.display_name)
		assert_lt(c.ship.global_position.distance_to(main.ship.global_position), 2500.0, "%s came out beside the player" % c.display_name)
	assert_eq(gate.vortex.form_kills + gate.vortex.close_kills, 0)


func test_wingmen_under_a_fighting_order_keep_clear_of_the_vortex_and_rejoin() -> void:
	await _start()
	var wingmen: Array[Combatant] = await _wing_at_the_gate("engage")
	assert_eq(main.gates.start_jump(gate), "")
	await _ticks(2)
	assert_true(wing.leader_away, "they broke off for the jump")
	var closest: float = INF
	for i: int in 60 * 60:
		await get_tree().physics_frame
		if not main.gates.jump.is_active():
			break
		if gate.vortex.is_active() and gate.vortex.timing.phase(gate.vortex.age_s) != VortexTiming.Phase.ACTIVATE:
			for c: Combatant in wingmen:
				closest = minf(closest, _clearance(c.ship))
	assert_eq(main.gates.jump.completed, 1, "out and back (%s)" % main.gates.jump.ended_why)
	assert_eq(main.gates.wing_jump.carried, 0, "nobody went with the player")
	assert_gt(closest, -50.0, "they kept out of the funnel and its margin (closest %.0f m)" % closest)
	assert_false(wing.leader_away, "the player is back: they rejoin")
	assert_true(await _until(func() -> bool: return not gate.vortex.is_active(), 60 * 30))
	for c: Combatant in wingmen:
		assert_false(c.damageable.hull.destroyed, "%s lived" % c.display_name)
