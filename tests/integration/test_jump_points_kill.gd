extends GutTest
## Jump points kill (M8-T17, maintainer 2026-11-19), on the real main scene: a ship sitting where a vortex forms is destroyed as it
## forms, one still in it is destroyed as it closes, at the gate and at a point a ship opened, the player included; the point's
## opener and the ships it carries are spared; no one is credited; the HUD warns a pilot sitting in a mouth about to form.

var main: Main
var gate: Jumpgate


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func after_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = false
	ContactScan.invalidate()


func _start() -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.raider_pool_size = 2
	main.ally_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(3)
	gate = main.gates.gate()
	main.combatant.damageable.invulnerable = false


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _raider_at(at: Vector3, name: String = "TRAPPED") -> Combatant:
	main.ensure_free(&"raider_fighter", 1)
	var made: Dictionary = BrainFactory.from_behaviour({"type": "idle"}, main.world.to_universe(at), 1)
	return main.ships.acquire(name, main.world.to_universe(at), Basis.IDENTITY, main.world.rest_velocity(),
			made["brain"] as PilotBrain, &"raider_fighter")


func _until(done: Callable, limit: int) -> bool:
	for i: int in limit:
		if done.call():
			return true
		await get_tree().physics_frame
	return bool(done.call())


func test_the_gate_kills_a_ship_where_it_forms_and_one_still_in_it_as_it_closes() -> void:
	await _start()
	assert_true(main.gates._cmd_gate({&"action": &"approach", &"option": "3"}).ok, "near the gate, where its ships fly in full")
	await _ticks(3)
	var trapped: Combatant = _raider_at(gate.vortex.true_frame() * Vector3(0.0, 0.0, 500.0))
	var causes: Array[StringName] = []
	trapped.damageable.hit_taken.connect(func(info: HitInfo) -> void: causes.append(info.cause))
	assert_true(main.gates._cmd_gate({&"action": &"open", &"option": "arrival", &"hold_s": 3.0}).ok)
	await _ticks(20)
	assert_true(gate.vortex.is_forming(), "the arms' lead-in first")
	assert_false(trapped.damageable.hull.destroyed, "not before it forms")
	assert_true(await _until(func() -> bool: return not gate.vortex.is_forming(), 60 * 5))
	await _ticks(2)
	assert_true(trapped.damageable.hull.destroyed, "a ship where the vortex formed is destroyed")
	assert_eq(causes, [HitInfo.CAUSE_VORTEX] as Array[StringName], "by the vortex, no one credited")
	assert_eq(gate.vortex.form_kills, 1)
	# One flown in while it is open, and still there when it closes.
	var late: Combatant = _raider_at(gate.vortex.true_frame() * Vector3(0.0, 100.0, 400.0), "LATE")
	assert_true(await _until(func() -> bool: return not gate.vortex.is_active(), 60 * 15), "it closed")
	assert_true(late.damageable.hull.destroyed, "a ship still in it as it closes is destroyed")
	assert_eq(gate.vortex.close_kills, 1)
	# The console's way to test it.
	assert_true(main.gates._cmd_gate({&"action": &"trap", &"option": "raider"}).ok)


func test_a_ship_opened_point_kills_but_spares_its_opener() -> void:
	await _start()
	var nose: Vector3 = -main.ship.global_basis.z
	var xform := Transform3D(Basis.looking_at(-nose, main.ship.global_basis.y), main.ship.global_position + nose * 1500.0)
	var opener: Combatant = _raider_at(xform * Vector3(0.0, 0.0, 120.0), "OPENER")
	var victim: Combatant = _raider_at(xform * Vector3(0.0, 20.0, 60.0), "VICTIM")
	await _ticks(2)
	var fit := VortexFit.new(300.0, 300.0 * VortexFit.POINT_DEPTH_RATIO)
	var point: JumpVortex = main.gates.console_points.open_with(xform, fit, JumpVortex.Direction.DEPARTURE, 5.0)
	assert_not_null(point)
	point.hold_by(opener.ship, 5000.0)  # as a carrier holds the point it opened
	assert_true(await _until(func() -> bool: return not point.is_forming() and point.age_s > 0.0, 60 * 5))
	await _ticks(2)
	assert_true(victim.damageable.hull.destroyed, "a ship in a point's funnel as it forms is destroyed")
	assert_false(opener.damageable.hull.destroyed, "its opener is spared")
	assert_eq(point.form_kills, 1)


func test_the_player_is_warned_then_not_spared() -> void:
	await _start()
	assert_true(main.gates._cmd_gate({&"action": &"trap", &"option": "player"}).ok)
	await _ticks(3)
	assert_eq(VortexHazard.warning(main.ship, get_tree()), "", "no warning while nothing forms")
	assert_true(main.gates._cmd_gate({&"action": &"open", &"option": "arrival", &"hold_s": 3.0}).ok)
	await _ticks(10)
	assert_true(gate.vortex.is_forming())
	var frame: HudFrame = HudLayout.compute(main._build_hud_input())
	assert_eq(frame.ack_line, VortexHazard.WARNING, "the HUD warns the pilot sitting where it is about to form")
	assert_true(await _until(func() -> bool: return not gate.vortex.is_forming(), 60 * 5))
	await _ticks(2)
	assert_false(main.player_alive, "the player is not spared")


func test_a_ship_the_gate_carries_out_is_spared() -> void:
	await _start()
	assert_true(DebugConsole.registry.execute("transit arrive gate fighter")[0].ok)
	var transits: VortexTransits = VortexTransits.of(main.world)
	assert_true(await _until(func() -> bool: return transits != null and transits.count() > 0, 60 * 8), "a fighter is on its way out")
	var carried: Array[RigidBody3D] = transits.bodies_in(gate.vortex)
	assert_false(carried.is_empty())
	assert_true(await _until(func() -> bool: return not gate.vortex.is_active(), 60 * 30), "the vortex closed behind it")
	for body: RigidBody3D in carried:
		var damageable: Damageable = Damageable.of(body)
		assert_false(damageable != null and damageable.hull.destroyed, "the ship it carried out lives")
	assert_eq(gate.vortex.form_kills + gate.vortex.close_kills, 0)
