extends GutTest
## The player's gate jump made safe (M8-T17; maintainer's play-test, 2026-11-20), on the real main scene: a jump asked at speed
## from the side, just inside 10 km, never kills the player (the autopilot once flew it into the far arm); a player killed in its
## run-in and respawned finds its wing flying back to formation round it, nothing placed; an AI ship on its own departure run when the player comes
## out of the gate stands aside until the arrival is through, then departs.

## Formation's far closure over the profile's cruise (`FormationState::FAR_EXTRA_MPS`, native/src/brain_behaviours.rs).
const FAR_EXTRA_MPS: float = 100.0
const SPEED_UP: float = 8.0

var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


func _fast() -> void:
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))


func _normal() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup


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



func _wingmen_beside_player(order: String) -> Array[Combatant]:
	var basis: Basis = main.ship.global_basis
	var out: Array[Combatant] = []
	for slot: int in [1, 2]:
		var at: Vector3 = Formation.slot_point(main.ship.global_position, -basis.z, basis.y, wing.slot_offset(slot))
		out.append(_ally(wing.callsign(slot), at, -basis.z, slot))
	assert_true(DebugConsole.registry.execute("wing order %s" % order)[0].ok)
	await _ticks(10)
	return out


func test_a_jump_asked_at_speed_from_the_side_never_kills_the_player() -> void:
	await _start()
	main.combatant.damageable.invulnerable = false
	var wingmen: Array[Combatant] = await _wingmen_beside_player("cover")
	var axis: Vector3 = (gate.global_basis * gate.departure_forward).normalized()
	var start: Vector3 = gate.global_position + gate.global_basis.x * 12000.0 - axis * 3000.0
	main.ship.reset_to(Transform3D(Basis.looking_at((gate.global_position - start).normalized(), Vector3.UP), start))
	main.ship.linear_velocity = main.world.rest_velocity() + (gate.global_position - start).normalized() * 1500.0
	var asked: String = "not yet"
	var away_seen: bool = false
	for i: int in 60 * 240:
		await get_tree().physics_frame
		if asked == "not yet" and main.ship.global_position.distance_to(gate.global_position) < 9900.0:
			asked = main.gates.start_jump(gate)
			assert_eq(asked, "", "taken just inside 10 km at 1.5 km/s")
		away_seen = away_seen or wing.leader_away
		if asked == "" and not main.gates.jump.is_active() or not main.player_alive:
			break
	assert_true(main.player_alive, "the player lived")
	assert_eq(main.gates.jump.completed, 1, "out and back (%s)" % main.gates.jump.ended_why)
	assert_true(away_seen, "under COVER ME the wing broke off for the jump")
	assert_false(wing.leader_away, "and is the player's again")
	for c: Combatant in wingmen:
		assert_false(c.damageable.hull.destroyed, "%s lived" % c.display_name)


func test_a_player_killed_in_its_run_in_finds_its_wing_flying_back_after_respawning() -> void:
	await _start()
	assert_true(main.gates._cmd_gate({&"action": &"approach", &"option": "1.9"}).ok)
	await _ticks(2)
	var wingmen: Array[Combatant] = await _wingmen_beside_player("form")
	assert_eq(main.gates.start_jump(gate), "")
	assert_true(await _until(func() -> bool: return main.gates.wing_jump._sent_all, 60 * 60), "the run-in: the wing handed to the gate")
	main.combatant.damageable.invulnerable = false
	main.combatant.damageable.kill(HitInfo.CAUSE_CONSOLE)
	await _ticks(30)
	assert_false(main.player_alive)
	main.respawn()
	assert_false(main.gates.jump.is_active(), "the jump ended with the ship")
	assert_true(main.gates.wing_jump.followers.is_empty() and main.gates.wing_jump.sent.is_empty(), "no jump state left")
	assert_false(wing.leader_away)
	assert_eq(wing.order, AiContext.Order.FORM_ON_ME, "under its last order")
	for c: Combatant in wingmen:
		assert_true(c.ship.visible and not wing.is_away(c) and not c.driver.in_passage, "%s flies again" % c.display_name)
	# They fly back, nothing placed: the bound is the way home at formation's far closure, plus a minute to turn and settle.
	var far_mps: float = AiProfile.load_named(&"ally_starfury").cruise_mps + FAR_EXTRA_MPS
	var farthest: float = 0.0
	for c: Combatant in wingmen:
		farthest = maxf(farthest, c.ship.global_position.distance_to(main.ship.global_position))
	var bound_s: float = farthest / far_mps + 60.0
	var max_step: float = wingmen[0].ship.spec.assist_speed_max_mps / 60.0
	var last: Array[UniversePos] = []  # universe positions: a frame rebase moves no ship
	for c: Combatant in wingmen:
		last.append(main.world.to_universe(c.ship.global_position))
	_fast()
	var formed: bool = false
	var jumped: String = ""
	var elapsed_s: float = 0.0
	while elapsed_s < bound_s:
		await get_tree().physics_frame
		elapsed_s += 1.0 / 60.0
		formed = true
		for i: int in wingmen.size():
			var at: UniversePos = main.world.to_universe(wingmen[i].ship.global_position)
			var step: float = last[i].offset_to(at).length()
			if step > max_step and jumped.is_empty():
				jumped = "%s moved %.0f m in a tick" % [wingmen[i].display_name, step]
			last[i] = at
			formed = formed and wingmen[i].ship.global_position.distance_to(main.ship.global_position) < 300.0
		if formed:
			break
	_normal()
	assert_eq(jumped, "", "no wingman was placed: each flew")
	assert_true(formed, "back in formation within %.0f s (%.1f km at %.0f m/s); took %.0f s" % [bound_s, farthest / 1000.0, far_mps, elapsed_s])
	gut.p("fly-back: %.1f km in %.0f s (bound %.0f s)" % [farthest / 1000.0, elapsed_s, bound_s])


func test_an_ai_departure_stands_aside_for_the_players_arrival_then_departs() -> void:
	await _start()
	assert_true(main.gates._cmd_gate({&"action": &"approach", &"option": "1.9"}).ok)
	await _ticks(2)
	assert_eq(main.gates.start_jump(gate), "")
	assert_true(await _until(func() -> bool: return main.gates.jump.state == GateJump.State.ARRIVING, 60 * 60), "the player is coming out")
	var frame: Transform3D = gate.vortex.true_frame()
	var leaving: Combatant = _ally("LEAVING", frame * Vector3(0.0, 0.0, -1300.0), frame.basis.z)
	leaving.ship.linear_velocity = main.world.rest_velocity() + frame.basis.z.normalized() * 150.0
	var departed: Array[bool] = [false]
	gate.send_departure(leaving.ship, func(_s: Node3D) -> void: departed[0] = true)
	var strayed: bool = false
	while gate.vortex.is_active() and gate.vortex.direction == JumpVortex.Direction.ARRIVAL or main.gates.jump.is_active():
		await get_tree().physics_frame
		if gate.vortex.direction == JumpVortex.Direction.ARRIVAL and gate.vortex.is_active():
			strayed = strayed or VortexHazard.caught(gate.vortex).has(leaving.ship)
			assert_false(leaving.driver.in_passage and gate.vortex.timing.phase(gate.vortex.age_s) >= VortexTiming.Phase.FLASH,
					"the gate does not fly it in while the arrival has the gate")
	assert_false(strayed, "it kept out of the arrival's funnel")
	assert_true(main.player_alive)
	assert_gt(gate.held_back, 0, "its departure waited")
	assert_true(await _until(func() -> bool: return departed[0], 60 * 60), "then it departed")
	assert_false(leaving.damageable.hull.destroyed)
