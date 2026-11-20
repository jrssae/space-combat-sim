extends GutTest
## Arrivals survive their own vortex (M8-T17 fix, maintainer 2026-11-20), on the real main scene: every ship an opening brings
## through is spared by both of its sweeps, however it comes out (flown out of the ring or, too small on screen, placed) and even
## if it lingers in the mouth or turns back into it before it closes: the player's round trip, a raid out of the gate, a carrier
## out of its own point with fighters on its cradles. A ship merely nearby still dies.

var main: Main
var gate: Jumpgate


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func after_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = false
	ContactScan.invalidate()


func _start(raiders: int) -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.raider_pool_size = raiders
	main.ally_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(3)
	gate = main.gates.gate()
	main.combatant.damageable.invulnerable = false


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _until(done: Callable, limit: int) -> bool:
	for i: int in limit:
		if done.call():
			return true
		await get_tree().physics_frame
	return bool(done.call())


func _kills() -> int:
	var total: int = 0
	for node: Node in get_tree().get_nodes_in_group(JumpVortex.GROUP):
		total += (node as JumpVortex).form_kills + (node as JumpVortex).close_kills
	return total


# Sets `body` at rest at `local` in `vortex`'s frame (inside its funnel for z >= 0).
func _put(body: RigidBody3D, vortex: JumpVortex, local: Vector3) -> void:
	var xform := Transform3D(body.global_basis, vortex.true_frame() * local)
	if body is Ship:
		(body as Ship).reset_to(xform)
	else:
		body.global_transform = xform
	body.linear_velocity = main.world.rest_velocity()
	body.angular_velocity = Vector3.ZERO


func _raider(name: String, at: Vector3, xform_basis: Basis, velocity: Vector3, behaviour: Dictionary) -> Combatant:
	var made: Dictionary = BrainFactory.from_behaviour(behaviour, main.world.to_universe(at), hash(name))
	return main.ships.acquire(name, main.world.to_universe(at), xform_basis, velocity, made["brain"] as PilotBrain, &"raider_fighter")


func test_the_player_comes_back_out_of_the_gate_alive_even_lingering_in_its_mouth() -> void:
	await _start(2)
	assert_true(main.gates._cmd_gate({&"action": &"approach", &"option": "1.9"}).ok)
	await _ticks(3)
	assert_eq(main.gates.start_jump(gate), "")
	assert_true(await _until(func() -> bool: return not main.gates.jump.is_active(), 60 * 60), "the round trip ended")
	assert_eq(main.gates.jump.completed, 1, "out and back (%s)" % main.gates.jump.ended_why)
	assert_true(main.player_alive, "the player came back out alive")
	assert_true(gate.vortex.is_active() and gate.vortex.direction == JumpVortex.Direction.ARRIVAL, "its arrival still open")
	# The pilot stops in the mouth and waits there, and a raider strays into the funnel: only the raider dies as it closes.
	_put(main.ship, gate.vortex, Vector3(0.0, 0.0, 30.0))
	var stray: Combatant = _raider("STRAY", gate.vortex.true_frame() * Vector3(0.0, 200.0, 400.0), Basis.IDENTITY,
			main.world.rest_velocity(), {"type": "idle"})
	assert_not_null(stray)
	assert_true(await _until(func() -> bool: return not gate.vortex.is_active(), 60 * 20), "the arrival closed")
	assert_true(main.player_alive, "its own arrival spared the player, lingering in its mouth")
	assert_false(main.combatant.damageable.hull.destroyed)
	assert_true(stray.damageable.hull.destroyed, "a ship merely in it is still destroyed")
	assert_eq(gate.vortex.close_kills, 1)


func test_a_raid_out_of_the_gate_comes_out_alive() -> void:
	await _start(6)
	assert_true(main.gates._cmd_gate({&"action": &"approach", &"option": "4"}).ok, "4 km out: its ships fly in full")
	await _ticks(3)
	var raid: Array[Combatant] = []
	for k: int in 6:
		var offset := Vector3((float(k) - 2.5) * 120.0, 0.0, 0.0)
		gate.request_arrival(func() -> void:
			var xform: Transform3D = gate.arrival_transform(offset)
			var c: Combatant = _raider("RAID %d" % k, xform.origin, xform.basis, gate.arrival_velocity() + main.world.rest_velocity(),
					{"type": "ai", "profile": "raider", "orders": "attack", "target": "player"})
			if c != null:
				gate.bring_through(c.ship)
				raid.append(c))
	assert_true(await _until(func() -> bool: return raid.size() == 6, 60 * 15), "all six came through")
	await _ticks(2)
	# One turns back into the mouth before it closes.
	_put(raid[0].ship, gate.vortex, Vector3(0.0, 0.0, 100.0))
	assert_true(await _until(func() -> bool: return not gate.vortex.is_active(), 60 * 20), "the arrival closed")
	for c: Combatant in raid:
		assert_false(c.damageable.hull.destroyed, "%s survived its own arrival" % c.display_name)
	assert_eq(_kills(), 0, "no vortex killed anyone")
	assert_true(main.player_alive)


func test_a_carrier_out_of_its_own_point_with_docked_fighters_comes_out_alive() -> void:
	await _start(0)
	assert_true(DebugConsole.registry.execute("transit docked")[0].ok)
	var carriers: CarrierJumps = CarrierJumps.attach(main.world)
	assert_not_null(carriers)
	assert_eq(carriers.runs().size(), 1)
	var run: CarrierRun = carriers.runs()[0]
	var point: JumpVortex = run.arrival
	var riders: Array[RigidBody3D] = run.fighters.duplicate()
	assert_eq(riders.size(), TransitConsole.DOCKED_FIGHTERS, "six fighters on its cradles")
	assert_true(await _until(func() -> bool: return not point.is_forming(), 60 * 10), "the point formed")
	assert_true(await _until(func() -> bool: return not point.is_active() or point.opener != run.carrier, 60 * 40),
			"the point closed")
	var carrier_hull: Damageable = Damageable.of(run.carrier)
	assert_false(carrier_hull != null and carrier_hull.hull.destroyed, "the carrier came out of its own point alive")
	for body: RigidBody3D in riders:
		var d: Damageable = Damageable.of(body)
		assert_false(d != null and d.hull.destroyed, "%s came out on its cradle alive" % body.name)
	assert_eq(point.form_kills + point.close_kills, 0, "its point killed no one")
