extends GutTest
## The departure vortex held open for the player's following wingmen (M8-T17; maintainer, 2026-11-20), on the real main scene:
## under FORM ON ME it stays open while a wingman within `GateJump.FOLLOW_RANGE_M` is on its way in, with the camera outside on
## the gate and no black, and closes after the last is through; wingmen in formation trail the player through within seconds; it never waits for a wingman out of range; it closes at once
## when a wingman it waits for dies or the order changes.

const STARFURY_SPEC: String = "res://assets/ships/starfury_aurora.tres"
## A straggler is put this far in front of the mouth as the player crosses it, so the hold lasts long enough to watch.
const STRAGGLER_M: float = 2400.0

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


func _ally(name: String, at: Vector3, forward: Vector3, slot: int) -> Combatant:
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
	assert_eq(main.wings.add_member(wing, ally), slot)
	return ally


# Two wingmen in their slots beside the player 1.9 km in front of the gate, under FORM ON ME, and the jump started.
func _jump_with_wingmen() -> Array[Combatant]:
	assert_true(main.gates._cmd_gate({&"action": &"approach", &"option": "1.9"}).ok)
	await _ticks(2)
	var basis: Basis = main.ship.global_basis
	var out: Array[Combatant] = []
	for slot: int in [1, 2]:
		var at: Vector3 = Formation.slot_point(main.ship.global_position, -basis.z, basis.y, wing.slot_offset(slot))
		out.append(_ally(wing.callsign(slot), at, -basis.z, slot))
	assert_true(DebugConsole.registry.execute("wing order form")[0].ok)
	await _ticks(10)
	assert_eq(main.gates.start_jump(gate), "")
	return out


# Waits for the run-in to start (the followers just handed to the gate), then puts `c` `distance_m` in front of the mouth on the
# axis, at rest: a wingman that has a way to go.
func _straggle(c: Combatant, distance_m: float) -> void:
	assert_true(await _until(func() -> bool: return main.gates.wing_jump._sent_all, 60 * 60), "the run-in started")
	var frame: Transform3D = gate.vortex.true_frame()
	c.ship.reset_to(Transform3D(Basis.looking_at(frame.basis.z, Vector3.UP), frame * Vector3(40.0, 0.0, -distance_m)))
	c.ship.linear_velocity = main.world.rest_velocity()


func test_the_vortex_stays_open_for_following_wingmen_with_the_camera_on_the_gate() -> void:
	await _start()
	var wingmen: Array[Combatant] = await _jump_with_wingmen()
	await _straggle(wingmen[1], STRAGGLER_M)
	var held_s: float = 0.0
	var black_seen: bool = false
	var camera_off: bool = false
	var closed_while_waiting: bool = false
	var takes: PackedStringArray = PackedStringArray()
	var hold_ended_pending: int = -1
	while main.gates.jump.is_active():
		await get_tree().physics_frame
		if main.gates.jump.state == GateJump.State.HOLD:
			held_s += 1.0 / 60.0
			black_seen = black_seen or main.gates.jump.black_level > 0.0
			camera_off = camera_off or not main.camera_rig.is_playing_shot()
			if main.gates.wing_jump.holding() and not gate.vortex.is_open_for(JumpVortex.Direction.DEPARTURE):
				closed_while_waiting = true
		elif held_s > 0.0 and hold_ended_pending < 0:
			hold_ended_pending = main.gates.wing_jump.pending().size()
			takes = main.gates.shots.sequence()
	assert_gt(held_s, 3.0, "the vortex was held for the straggler (%.1f s)" % held_s)
	assert_lt(held_s, GateJump.HOLD_MAX_S, "and let go once it was through")
	assert_false(black_seen, "no black while held")
	assert_false(camera_off, "a take on screen the whole hold")
	assert_false(closed_while_waiting, "open while a wingman was on its way")
	assert_eq(hold_ended_pending, 0, "the last was through before the black")
	var hold_takes: int = 0
	for take: String in takes:
		hold_takes += int(take.begins_with("%s/" % GateShotPool.HOLD))
	assert_gt(hold_takes, 1, "a long hold cuts between angles: %s" % " ".join(takes))
	assert_eq(main.gates.jump.completed, 1, "out and back (%s)" % main.gates.jump.ended_why)
	assert_eq(main.gates.wing_jump.carried, 2, "both came back out with the player")
	for c: Combatant in wingmen:
		assert_false(c.damageable.hull.destroyed, "%s lived" % c.display_name)


func test_wingmen_in_formation_trail_the_player_through_and_the_hold_is_short() -> void:
	await _start()
	var wingmen: Array[Combatant] = await _jump_with_wingmen()
	var held_s: float = 0.0
	var first_hold_take: String = ""
	while main.gates.jump.is_active():
		await get_tree().physics_frame
		if main.gates.jump.state == GateJump.State.HOLD:
			held_s += 1.0 / 60.0
			assert_eq(main.gates.jump.black_level, 0.0)
			if first_hold_take.is_empty():
				var seq: PackedStringArray = main.gates.shots.sequence()
				first_hold_take = seq[seq.size() - 1] if not seq.is_empty() else ""
	assert_between(held_s, 2.0, 8.0, "a short hold, the wingmen close behind the player (%.1f s)" % held_s)
	assert_eq(first_hold_take, "%s/exterior" % GateShotPool.HOLD, "outside the gate first")
	assert_eq(main.gates.wing_jump.carried, 2, "both came back out with the player")
	for c: Combatant in wingmen:
		assert_false(c.damageable.hull.destroyed, "%s lived" % c.display_name)


func test_a_far_wingman_is_let_go_as_the_run_in_starts() -> void:
	await _start()
	var wingmen: Array[Combatant] = await _jump_with_wingmen()
	var far: Combatant = wingmen[1]
	var frame: Transform3D = gate.vortex.true_frame()
	far.ship.tier_exempt = true
	assert_true(await _until(func() -> bool:
		far.ship.reset_to(Transform3D(far.ship.global_basis, frame * Vector3(0.0, 2000.0, -GateJump.FOLLOW_RANGE_M - 1500.0)))
		far.ship.linear_velocity = main.world.rest_velocity()
		return main.gates.wing_jump._sent_all, 60 * 60), "the run-in started")
	assert_false(main.gates.wing_jump.sent.has(far), "the far one is not waited for")
	assert_false(gate.vortex.spares(far.ship), "and keeps clear like every AI pilot")
	var held_s: float = 0.0
	while main.gates.jump.is_active():
		await get_tree().physics_frame
		held_s += 1.0 / 60.0 if main.gates.jump.state == GateJump.State.HOLD else 0.0
	assert_lt(held_s, 6.0, "the hold was for the near one only (%.1f s)" % held_s)
	assert_eq(main.gates.wing_jump.carried, 1, "the near one came back out with the player")
	assert_false(far.damageable.hull.destroyed)


func test_the_hold_ends_at_once_when_a_waited_for_wingman_dies() -> void:
	await _start()
	var wingmen: Array[Combatant] = await _jump_with_wingmen()
	await _straggle(wingmen[1], STRAGGLER_M)
	assert_true(await _until(func() -> bool: return main.gates.jump.state == GateJump.State.HOLD, 60 * 10), "held")
	await _ticks(30)
	assert_true(main.gates.wing_jump.holding(), "still waiting for the straggler")
	wingmen[1].damageable.kill(HitInfo.CAUSE_VORTEX)
	assert_true(await _until(func() -> bool: return main.gates.wing_jump.called_off == 1, 5), "the hold was called off at once")
	assert_false(main.gates.wing_jump.holding(), "nobody else is waited for")
	assert_true(await _until(func() -> bool: return main.gates.jump.state != GateJump.State.HOLD, 60 * 4),
			"the vortex folded and the jump went on")
	assert_true(await _until(func() -> bool: return not main.gates.jump.is_active(), 60 * 30))
	assert_eq(main.gates.jump.completed, 1)


func test_the_hold_ends_at_once_when_the_order_changes() -> void:
	await _start()
	var wingmen: Array[Combatant] = await _jump_with_wingmen()
	await _straggle(wingmen[1], STRAGGLER_M)
	assert_true(await _until(func() -> bool: return main.gates.jump.state == GateJump.State.HOLD, 60 * 10), "held")
	await _ticks(30)
	assert_true(main.gates.wing_jump.holding())
	assert_true(DebugConsole.registry.execute("wing order engage")[0].ok)
	assert_true(await _until(func() -> bool: return not main.gates.wing_jump.holding(), 5), "nobody else is waited for")
	assert_true(await _until(func() -> bool: return main.gates.jump.state != GateJump.State.HOLD, 60 * 4))
	assert_true(await _until(func() -> bool: return not main.gates.jump.is_active(), 60 * 30))
	assert_eq(main.gates.jump.completed, 1)
	assert_false(wingmen[1].damageable.hull.destroyed, "the one left outside kept clear and lived")
