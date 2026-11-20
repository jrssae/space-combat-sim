extends GutTest
## Every AI pilot clears the mouth of an opening jump point (M8-T17; maintainer's play-test, 2026-11-20), on the real main scene:
## an opening waits for AI ships still in its funnel (`VortexTiming.CLEAR_WAIT_S` at most) while the keep-out flies them out, so
## its forming sweep finds nobody: a ship parked in the gate's funnel, wingmen whose formation slots lie in the mouth, and a ship
## parked in a ship-opened point.

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


# Waits for `vortex` to form; whether each of `ships` was out of its funnel then.
func _formed_clear_of(vortex: JumpVortex, ships: Array[Combatant]) -> Array[bool]:
	var out: Array[bool] = []
	assert_true(await _until(func() -> bool: return vortex.age_s > 0.0 and not vortex.is_forming(), 60 * 15), "it formed")
	for c: Combatant in ships:
		out.append(not VortexHazard.caught(vortex).has(c.ship))
	return out


func test_an_ai_ship_parked_in_the_gates_funnel_leaves_before_it_forms() -> void:
	await _start()
	assert_true(main.gates._cmd_gate({&"action": &"approach", &"option": "4"}).ok)
	await _ticks(2)
	var frame: Transform3D = gate.vortex.true_frame()
	var parked: Combatant = _ally("PARKED", frame * Vector3(150.0, 0.0, 250.0), -frame.basis.z)
	await _ticks(10)
	assert_true(main.gates._cmd_gate({&"action": &"open", &"option": "arrival", &"hold_s": 4.0}).ok)
	var clear: Array[bool] = await _formed_clear_of(gate.vortex, [parked] as Array[Combatant])
	assert_gt(gate.vortex.clear_waited_s, 0.0, "the opening waited for it")
	assert_true(clear[0], "it was out of the funnel when it formed")
	assert_false(parked.damageable.hull.destroyed)
	assert_eq(gate.vortex.form_kills, 0)


func test_wingmen_whose_slots_lie_in_the_mouth_leave_before_it_forms() -> void:
	await _start()
	var frame: Transform3D = gate.vortex.true_frame()
	# The player just in front of the mouth, facing away from the gate: its wingmen's slots behind it lie in the mouth.
	main.combatant.damageable.invulnerable = true  # the player is no AI pilot: it is the wingmen's way out that is tested
	main.ship.reset_to(Transform3D(Basis.looking_at(-frame.basis.z, Vector3.UP), frame * Vector3(0.0, 0.0, -30.0)))
	main.ship.linear_velocity = main.world.rest_velocity()
	await _ticks(2)
	var basis: Basis = main.ship.global_basis
	var wingmen: Array[Combatant] = []
	for slot: int in [1, 2]:
		var at: Vector3 = Formation.slot_point(main.ship.global_position, -basis.z, basis.y, wing.slot_offset(slot))
		wingmen.append(_ally(wing.callsign(slot), at, -basis.z, slot))
	assert_true(DebugConsole.registry.execute("wing order form")[0].ok)
	await _ticks(30)
	var in_mouth: int = 0
	for c: Combatant in wingmen:
		in_mouth += int(VortexHazard.caught(gate.vortex).has(c.ship))
	assert_gt(in_mouth, 0, "a slot lies in the mouth")
	assert_true(main.gates._cmd_gate({&"action": &"open", &"option": "arrival", &"hold_s": 4.0}).ok)
	var clear: Array[bool] = await _formed_clear_of(gate.vortex, wingmen)
	assert_lte(gate.vortex.clear_waited_s, VortexTiming.CLEAR_WAIT_S, "out within the gate's lead-in, or the wait")
	assert_eq(clear, [true, true] as Array[bool], "both left their slots for the mouth's sake")
	for c: Combatant in wingmen:
		assert_false(c.damageable.hull.destroyed, "%s lived" % c.display_name)
	assert_eq(gate.vortex.form_kills, 0)


func test_an_ai_ship_parked_in_a_ship_opened_point_leaves_before_it_forms() -> void:
	await _start()
	var nose: Vector3 = -main.ship.global_basis.z
	var at: Vector3 = main.ship.global_position + nose * 2500.0
	var out_dir: Vector3 = (main.ship.global_basis.x - nose).normalized()
	var points: JumpPointPool = main.gates.console_points
	var point: JumpVortex = points.open_for(main.world.to_universe(at), out_dir, 60.0, JumpVortex.Direction.ARRIVAL, false)
	assert_not_null(point)
	point.stop()  # measured; now park a ship in it and open it again
	var frame: Transform3D = point.true_frame()
	var parked: Combatant = _ally("PARKED", frame * Vector3(40.0, 0.0, point.fit.depth_m * 0.4), out_dir)
	await _ticks(10)
	point = points.open_for(main.world.to_universe(at), out_dir, 60.0, JumpVortex.Direction.ARRIVAL, false)
	assert_not_null(point)
	assert_true(VortexHazard.caught(point).has(parked.ship), "parked in it")
	var clear: Array[bool] = await _formed_clear_of(point, [parked] as Array[Combatant])
	assert_gt(point.clear_waited_s, 0.0, "the point waited for it")
	assert_true(clear[0], "it was out of the point's funnel when it formed")
	assert_false(parked.damageable.hull.destroyed)
	assert_eq(point.form_kills, 0)
