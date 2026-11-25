extends GutTest
## The `capital` brain in the real main scene (M10-T16, D12.10): two hostile Omegas released to their brains approach bow-on,
## engage at 0.7 x their main weapon's range and turn to bring their mounts to bear, their heavy weapons ordered onto each
## other; an Omega on orders holds its course and still names its target; one under a third of its hull withdraws through its
## own jump point, and with no exit it fights on; Earth Alliance fighters fly attack runs on a raider Omega, raiders never take
## an Earth Alliance one; the console's `capbrain` command and `capital_brain` provider.

const SPEED_UP: float = 8.0

var main: Main
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8
var _tier_backup: Variant = null


func before_each() -> void:
	get_tree().paused = false
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame
	_tier_backup = Settings.get_value(&"tier_radius_m")
	Settings.set_value(&"tier_radius_m", 30000.0)  # every ship a real body: a tier row's capital keeps its last cruise
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.scenario_seed = 5
	add_child_autofree(main)
	await wait_physics_frames(2)
	DebugConsole.flags.invulnerable = true


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	Settings.set_value(&"tier_radius_m", _tier_backup)
	DebugConsole.flags.invulnerable = false
	ContactScan.invalidate()


# An Omega for `faction`, `ahead_m` along the player's nose, its bow along the player's turned by `yaw_deg`, at rest and
# left to its brain.
func _omega(display_name: String, faction: StringName, ahead_m: float, yaw_deg: float = 0.0) -> CapitalShip:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(&"ea_omega", faction, display_name, rest)
	assert_not_null(cap, "the Omega is generated (scripts/gen_assets.sh)")
	if cap == null:
		return null
	var nose: Basis = main.ship.global_basis
	var basis: Basis = nose.rotated(nose.y, deg_to_rad(yaw_deg))
	main.world.spawn(cap, main.world.to_universe(main.ship.global_position - nose.z * ahead_m), basis)
	return cap


func _fly(seconds: float, done: Callable = Callable()) -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < seconds:
		await get_tree().physics_frame
		if done.is_valid() and bool(done.call()):
			break
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup


func _brains() -> CapitalBrains:
	return CapitalBrains.of(main.world)


func _state(cap: CapitalShip) -> StringName:
	return _brains().brain_state(cap).get("state", &"")


func _bearing(cap: CapitalShip, other: CapitalShip) -> float:
	return (-cap.global_basis.z).dot((other.global_position - cap.global_position).normalized())


# `cap`'s hull down to `fraction` of its points, its sections whole (below the withdraw line, above a hulk's).
func _hurt(cap: CapitalShip, fraction: float) -> void:
	cap.damageable.hull.hp = fraction * cap.damageable.hull.max_hp
	SimCore.for_tree(get_tree()).core.note_hull(cap.get_instance_id(), cap.damageable.hull.hp, cap.damageable.hull.max_hp)


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute_tokens(line.split(" ", false))


func test_two_omegas_approach_bow_on_then_engage_at_their_range_and_turn_their_mounts_to_bear() -> void:
	var a: CapitalShip = _omega("Omega A", Factions.EARTH_ALLIANCE, 3000.0, 20.0)
	var b: CapitalShip = _omega("Raider Omega", Factions.RAIDERS, 11000.0, 180.0)
	if a == null or b == null:
		return
	CapitalGuns.of(main.world).hold(a, true)  # a long look: nobody dies first
	CapitalGuns.of(main.world).hold(b, true)
	CapitalBeams.of(main.world).hold(a, true)
	CapitalBeams.of(main.world).hold(b, true)
	await _fly(60.0)
	assert_eq(_state(a), &"approach", "8 km apart, it closes")
	assert_eq(int(_brains().brain_state(a)["order"]), b.get_instance_id(), "its heavy weapons ordered onto the other")
	assert_gt(_bearing(a, b), 0.9, "bow on while it closes")
	var gap: float = a.global_position.distance_to(b.global_position)
	await _fly(400.0, func() -> bool: return _state(a) == &"engage" and _state(b) == &"engage")
	assert_eq(_state(a), &"engage", "in range it engages")
	assert_lt(a.global_position.distance_to(b.global_position), gap, "they closed")
	await _fly(150.0)
	var held: float = a.global_position.distance_to(b.global_position)
	var main_range: float = 4000.0  # the Omega's pulse cannons carry its most dps
	assert_almost_eq(held, 0.7 * main_range, 0.35 * main_range, "it holds about 0.7 of its main weapon's range")
	var attitude: int = int(_brains().brain_state(a)["attitude"])
	assert_ne(attitude, 0, "the Omega's mounts bear best off the bow, not bow-on")
	assert_lt(_bearing(a, b), 0.6, "it turned its hull to bring them round")


func test_on_orders_it_holds_its_course_and_still_names_its_target() -> void:
	var a: CapitalShip = _omega("Omega A", Factions.EARTH_ALLIANCE, 3000.0, 90.0)
	var b: CapitalShip = _omega("Raider Omega", Factions.RAIDERS, 11000.0, 90.0)
	if a == null or b == null:
		return
	var rest: Vector3 = main.world.rest_velocity()
	var bow: Vector3 = -a.global_basis.z
	a.set_course(bow, rest)
	await _fly(20.0)
	var s: Dictionary = _brains().brain_state(a)
	assert_eq(s["state"], &"hold", "on orders")
	assert_true(bool(s["held"]))
	assert_eq(int(s["order"]), b.get_instance_id(), "it still names its target")
	assert_gt((-a.global_basis.z).dot(bow), 0.999, "the bow stayed where the orders put it")
	assert_lt((a.linear_velocity - rest).length(), 1.0, "and it holds still")
	a.release_helm()
	await _fly(20.0)
	assert_eq(_state(a), &"approach", "released, its brain steers again")


func test_under_a_third_of_its_hull_it_withdraws_through_its_own_point() -> void:
	var a: CapitalShip = _omega("Omega A", Factions.EARTH_ALLIANCE, 3000.0)
	var b: CapitalShip = _omega("Raider Omega", Factions.RAIDERS, 9000.0)
	if a == null or b == null:
		return
	CapitalGuns.of(main.world).hold(b, true)
	CapitalBeams.of(main.world).hold(b, true)
	_hurt(a, 0.25)
	await _fly(10.0, func() -> bool: return not _brains().withdrawing_via(a).is_empty())
	assert_eq(_brains().withdrawing_via(a), CapitalWithdraw.VIA_OWN_POINT, "it opened its own point")
	assert_eq(_state(a), &"withdraw")
	var gone: Array[bool] = [false]
	_brains().withdrew.connect(func(ship: CapitalShip, _via: StringName) -> void: gone[0] = gone[0] or ship == a)
	await _fly(240.0, func() -> bool: return gone[0])
	assert_true(gone[0], "it went through and left play")


func test_with_no_way_out_it_fights_on() -> void:
	var a: CapitalShip = _omega("Omega A", Factions.EARTH_ALLIANCE, 3000.0)
	var b: CapitalShip = _omega("Raider Omega", Factions.RAIDERS, 6000.0)
	if a == null or b == null:
		return
	CapitalGuns.of(main.world).hold(b, true)
	CapitalBeams.of(main.world).hold(b, true)
	a.jump_drive.fire(SimClock.now())  # its drive just emptied: no point of its own
	for gate: Node in get_tree().get_nodes_in_group(Jumpgate.GROUP):
		gate.remove_from_group(Jumpgate.GROUP)  # and no gate: nowhere to go
	_hurt(a, 0.25)
	await _fly(10.0, func() -> bool: return bool(_brains().brain_state(a).get("withdraw_asked", false)))
	assert_true(bool(_brains().brain_state(a)["withdraw_asked"]), "it wanted out")
	await _fly(2.0)
	assert_eq(_brains().withdrawing_via(a), &"", "nowhere to go")
	assert_true(_state(a) == &"engage" or _state(a) == &"approach", "so it fights on (%s)" % _state(a))


func test_with_its_drive_empty_it_makes_for_the_gate() -> void:
	var a: CapitalShip = _omega("Omega A", Factions.EARTH_ALLIANCE, 3000.0)
	if a == null:
		return
	assert_false(get_tree().get_nodes_in_group(Jumpgate.GROUP).is_empty(), "free flight has a gate")
	a.jump_drive.fire(SimClock.now())
	_hurt(a, 0.25)
	await _fly(10.0, func() -> bool: return not _brains().withdrawing_via(a).is_empty())
	assert_eq(_brains().withdrawing_via(a), CapitalWithdraw.VIA_GATE)
	assert_eq(_state(a), &"withdraw")
	var gate: Jumpgate = get_tree().get_nodes_in_group(Jumpgate.GROUP)[0] as Jumpgate
	var before: float = a.global_position.distance_to(gate.global_position)
	await _fly(60.0)
	assert_lt(a.global_position.distance_to(gate.global_position), before, "it flies for it")


func test_fighters_run_on_a_raider_omega_and_raiders_leave_an_earth_alliance_one_alone() -> void:
	main.ships.prepare(ShipPool.ALLY_TYPE, 1)
	main.ships.prepare(ShipPool.DEFAULT_TYPE, 1)
	var hostile: CapitalShip = _omega("Raider Omega", Factions.RAIDERS, 5000.0)
	if hostile == null:
		return
	CapitalGuns.of(main.world).hold(hostile, true)
	CapitalBeams.of(main.world).hold(hostile, true)
	var at: UniversePos = main.world.to_universe(main.ship.global_position - main.ship.global_basis.z * 1500.0)
	var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": "ally_starfury"}, at, hash("ZETA 9"))
	var ally: Combatant = main.ships.acquire("ZETA 9", at, main.ship.global_basis, main.world.rest_velocity(),
			made["brain"] as PilotBrain, ShipPool.ALLY_TYPE)
	assert_not_null(ally)
	var legs: Dictionary = {}
	await _fly(90.0, func() -> bool:
		var state: String = str((ally.driver.brain as AiPilot).describe().get("state", ""))
		if state.begins_with("capital"):
			legs[state] = true
		return legs.has("capital inbound") and legs.has("capital break"))
	assert_true(legs.has("capital setup") or legs.has("capital inbound"), "it set up a run (%s)" % [legs.keys()])
	assert_true(legs.has("capital inbound"), "ran in on a subsystem")
	assert_true(legs.has("capital break"), "and broke off at the run's end")
	main.ships.release(ally)
	# A raider beside an Earth Alliance Omega and nothing else: it never takes the warship.
	var ours: CapitalShip = _omega("Omega A", Factions.EARTH_ALLIANCE, 9000.0, 90.0)
	var raider_at: UniversePos = main.world.to_universe(ours.global_position + ours.global_basis.x * 3000.0)
	var made_raider: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": "raider"}, raider_at, hash("RAIDER 9"))
	var raider: Combatant = main.ships.acquire("RAIDER 9", raider_at, Basis.IDENTITY, main.world.rest_velocity(),
			made_raider["brain"] as PilotBrain, ShipPool.DEFAULT_TYPE)
	assert_not_null(raider)
	var attacked: Array[bool] = [false]
	await _fly(20.0, func() -> bool:
		var d: Dictionary = (raider.driver.brain as AiPilot).describe()
		attacked[0] = attacked[0] or str(d.get("state", "")).begins_with("capital")
		return attacked[0])
	assert_false(attacked[0], "raiders never attack warships")


func test_the_console_shows_and_steers_a_brain() -> void:
	var a: CapitalShip = _omega("Omega A", Factions.EARTH_ALLIANCE, 3000.0)
	if a == null:
		return
	await _fly(1.0)
	var r: ConsoleResult = _run("capbrain")
	assert_true(r.ok, str(r.lines))
	assert_string_contains(" ".join(r.lines), "Omega A")
	assert_true(_run("capbrain hold").ok)
	await _fly(1.0)
	assert_true(bool(_brains().brain_state(a)["held"]), "hold gives it orders")
	assert_true(_run("capbrain free").ok)
	assert_false(bool(_brains().brain_state(a)["held"]))
	assert_eq(int(DebugConsole.registry.read("capital_brain.ships")["value"]), 1)
	for key: String in ["states", "applied", "stale", "withdrawals", "gone", "focus"]:
		assert_true(DebugConsole.registry.read("capital_brain." + key).has("value"), key)
