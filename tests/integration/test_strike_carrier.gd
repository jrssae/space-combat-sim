extends GutTest
## The raiders' strike carrier in the real main scene (M12-T19, Q25 to Q30), headless: it is built from its generated hull with
## its compound collision, comes out of its own jump point with its fighters docked, launches them, stands off, calls them back,
## waits, jumps out with those that docked and hands them to their pool; a fighter not home in time is left behind; destroyed,
## it takes its docked fighters with it.
##
## M8-T08 (D83): its fighters go home when three of the raid are left, or one alone under 20 % hull; it flees at 50 % damage or
## when every survivor has docked; with its drive recharged it jumps through its own point, else it runs for the jumpgate (and
## gets away through it), or with no gate from the enemy until the drive is ready. A carrier with no cradles holds its course
## until its drive has recharged.

const SEED: int = 5
## Ticks per real tick: the physics rate and the time scale raised together, so each step is still 1/60 s of sim time.
const SPEED_UP: float = 4.0

var main: Main
var carriers: CarrierJumps
var _rate_backup: int = 60
var _scale_backup: float = 1.0


func before_each() -> void:
	get_tree().paused = false
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.scenario_seed = SEED
	add_child_autofree(main)
	await wait_physics_frames(2)
	DebugConsole.flags.invulnerable = true
	main.ships.prepare(ShipPool.DEFAULT_TYPE, 8)
	carriers = CarrierJumps.attach(main.world)


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute_tokens(line.split(" ", false))


func _fly(seconds: float, done: Callable = Callable()) -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < seconds:
		await get_tree().physics_frame
		if done.is_valid() and bool(done.call()):
			break
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup


# The carrier comes in with six fighters docked; returns its run once it stands off with them launched.
func _bring_in_docked() -> CarrierRun:
	assert_true(_run("transit docked").ok)
	var run: CarrierRun = carriers.runs()[0]
	await _fly(60.0, func() -> bool: return run.state == CarrierRun.State.STANDOFF)
	return run


func test_the_hull_is_a_capital_body_built_from_its_asset() -> void:
	var cap: CapitalStandin = CapitalStandin.create(CapitalStandin.STRIKE_CARRIER, Factions.RAIDERS, "STRIKE 1", Vector3.ZERO)
	main.world.spawn(cap, main.world.to_universe(Vector3(0.0, 3000.0, 0.0)), Basis.IDENTITY)
	await wait_physics_frames(2)
	assert_not_null(cap.spec, "its numbers come from its ShipSpec")
	assert_eq(cap.spec.asset_id, "raider_strike_carrier")
	assert_almost_eq(cap.mass, cap.spec.mass, 1.0)
	assert_eq(cap.targetable.kind, Targetable.Kind.CAPITAL)
	assert_eq(cap.targetable.faction, Factions.RAIDERS)
	assert_almost_eq(cap.damageable.hull.max_hp, cap.spec.hull_max, 1e-3, "hull points only (Q28)")
	assert_true(cap.can_open_jump_point(), "it opens its own jump points")
	assert_true(JumpCapability.can_open(cap))
	assert_eq(cap.guns().size() + cap.interceptors().size() + cap.beams().size(), 0, "no weapons (Q25)")
	assert_eq(cap.linear_damp, 0.0)
	assert_eq(cap.angular_damp, 0.0)
	assert_eq(cap.linear_damp_mode, RigidBody3D.DAMP_MODE_REPLACE, "zero damping")
	var manifest: Dictionary = MeshAssets.read_manifest("raider_strike_carrier")
	var shapes: int = 0
	var hulls: int = 0
	for child: Node in cap.get_children():
		if child is CollisionShape3D:
			shapes += 1
			hulls += 1 if (child as CollisionShape3D).shape is ConvexPolygonShape3D else 0
	var listed: int = 0
	for piece: Dictionary in (manifest["collision"] as Dictionary)["pieces"]:
		listed += (piece["shapes"] as Array).size()
	assert_eq(shapes, listed, "every shape of the manifest's compound")
	assert_gt(hulls, 30, "the rings are convex sectors, not one box")
	assert_eq(cap.damageable.shapes.size(), shapes, "and a hit volume for each")
	var dims: Dictionary = manifest["dimensions_m"]
	assert_almost_eq(cap.length_m(), float(dims["length"]), 0.5, "the class's box is the hull's")
	assert_almost_eq(2.0 * cap.half_extents().x, float(dims["span"]), 0.5)
	assert_almost_eq(2.0 * cap.half_extents().y, float(dims["height"]), 0.5)
	assert_not_null(cap.dock)
	assert_eq(cap.dock.cradles.count(), 18, "eighteen cradles")
	assert_false(cap.jump_anchor.is_empty(), "and where it opens its point")
	assert_lt((cap.jump_anchor["position"] as Vector3).z, -200.0, "ahead of its bow")


func test_its_engines_and_helm_hold_a_course_and_turn_it() -> void:
	var cap: CapitalStandin = CapitalStandin.create(CapitalStandin.STRIKE_CARRIER, Factions.RAIDERS, "STRIKE 2", Vector3.ZERO)
	cap.world = main.world
	main.world.spawn(cap, main.world.to_universe(Vector3(0.0, 3000.0, 0.0)), Basis.IDENTITY)
	await wait_physics_frames(2)
	cap.cruise_velocity = cap.linear_velocity + Vector3(0.0, 0.0, -20.0)
	cap.heading = Vector3.LEFT
	var v0: Vector3 = cap.linear_velocity
	for i: int in 1200:
		cap.step_engines(1.0 / 60.0)  # forces are re-applied every tick
		await get_tree().physics_frame
	assert_almost_eq((cap.linear_velocity - v0).z, -20.0, 1.5, "its engines brought it to the cruise it was given")
	assert_gt((-cap.global_basis.z).dot(Vector3.LEFT), 0.15, "its helm is turning the bow to port")
	assert_lt(cap.angular_velocity.length(), deg_to_rad(cap.spec.rate_max.y) + 0.01, "no faster than its turn rate")
	var speed: float = cap.linear_velocity.length()
	for i: int in 120:
		await get_tree().physics_frame  # no force applied: nothing slows it
	assert_almost_eq(cap.linear_velocity.length(), speed, 1e-3, "it coasts: no damping")


func test_it_jumps_in_with_its_fighters_docked_and_launches_them() -> void:
	assert_true(_run("transit docked").ok)
	assert_eq(carriers.runs().size(), 1)
	var run: CarrierRun = carriers.runs()[0]
	var cap: CapitalStandin = run.carrier
	assert_eq(cap.ship_class, CapitalStandin.STRIKE_CARRIER, "the raiders' raids come behind the strike carrier")
	assert_eq(run.arrival.opener, cap, "it opened the point itself")
	assert_eq(cap.dock.docked_count(), 6, "its fighters ride in on its cradles (Q29)")
	assert_eq(run.fighters.size(), 6)
	for body: RigidBody3D in run.fighters:
		assert_false(body.is_visible_in_tree(), "a docked fighter is out of play")
		assert_false(VortexTransits.of(main.world).is_passing(body), "and flies no funnel of its own")
	await _fly(60.0, func() -> bool: return run.state == CarrierRun.State.STANDOFF)
	assert_eq(run.state, CarrierRun.State.STANDOFF, "clear of its point and its fighters out, it stands off")
	assert_eq(cap.dock.docked_count(), 0)
	assert_eq(cap.dock.launches, 6)
	assert_eq(carriers.fighters_launched, 6)
	for body: RigidBody3D in run.fighters:
		assert_true(body.is_visible_in_tree(), "launched: in play")
		assert_false(cap.dock.is_handling(body as Ship), "and on its own")
		assert_gt(body.global_position.distance_to(cap.global_position), 30.0, "clear of the hull")
		assert_false(Damageable.of(body).hull.destroyed, "unhurt by its launch")
	assert_eq(cap.damageable.hull.fraction(), 1.0, "nothing scraped the carrier")


func _kill(body: RigidBody3D) -> void:
	Damageable.of(body).kill()


# Brings the carrier's hull down to `share` of its points.
func _hull_to(cap: CapitalStandin, share: float) -> void:
	var hull: HullHealth = cap.damageable.hull
	cap.damageable.apply_hit(HitInfo.new(cap.get_instance_id(), 0, &"", hull.hp - share * hull.max_hp, cap.global_position,
			Vector3.ZERO, 0.0, HitInfo.CAUSE_CONSOLE))


func test_it_calls_its_fighters_back_and_jumps_out_with_them() -> void:
	var run: CarrierRun = await _bring_in_docked()
	var cap: CapitalStandin = run.carrier
	var free_before: int = main.ships.free_count(ShipPool.DEFAULT_TYPE)
	assert_true(_run("carrier charge").ok)  # as if its drive's recharge had passed
	assert_true(_run("carrier recall").ok)
	await _fly(5.0, func() -> bool: return run.state == CarrierRun.State.FLEEING)
	assert_eq(run.state, CarrierRun.State.FLEEING)
	assert_eq(run.flee_reason, CarrierTactics.FLEE_RAID_OVER)
	assert_eq(run.move, CarrierTactics.MOVE_WAIT, "its drive ready, it holds still for its fighters")
	assert_eq(cap.dock.returning_count() + cap.dock.docked_count(), 6, "every fighter is called back to a cradle")
	await _fly(float(run.options["wait_s"]) + 5.0, func() -> bool: return run.state == CarrierRun.State.LEAVING)
	assert_eq(run.state, CarrierRun.State.LEAVING)
	assert_eq(run.recovered, 6, "all six docked again within its wait (Q27)")
	assert_eq(run.left_behind, 0)
	assert_not_null(run.departure, "it opened its own point to leave by")
	assert_eq(run.departure.opener, cap)
	var departed: int = carriers.carriers_departed
	await _fly(70.0, func() -> bool: return carriers.carriers_departed > departed)
	assert_eq(carriers.carriers_departed, departed + 1, "it went through its point")
	assert_eq(run.left_via, CarrierRun.VIA_POINT)
	assert_eq(carriers.gate_departures, 0)
	assert_lt(SimClock.now() - run.state_at_s, CarrierJumps.LEAVE_LIMIT_S, "flying through it, not giving up on a point that collapsed")
	assert_eq(carriers.free_count(), carriers.size(), "and is back in its pool")
	assert_eq(main.ships.free_count(ShipPool.DEFAULT_TYPE), free_before + 6, "its docked fighters went back to theirs")
	assert_eq(cap.dock.docked_count(), 0)
	assert_eq(cap.damageable.hull.fraction(), 1.0, "no fighter scraped it coming home")


func test_a_fighter_not_home_in_time_is_left_behind() -> void:
	var run: CarrierRun = await _bring_in_docked()
	var cap: CapitalStandin = run.carrier
	run.options["wait_s"] = 0.5
	var far: Ship = run.fighters[0] as Ship
	far.global_position = cap.global_position + Vector3(0.0, 9000.0, 0.0)  # too far to be home in half a second
	assert_true(_run("carrier charge").ok)
	assert_true(_run("carrier recall").ok)
	await _fly(20.0, func() -> bool: return run.state == CarrierRun.State.LEAVING)
	assert_eq(run.state, CarrierRun.State.LEAVING)
	assert_gt(run.left_behind, 0, "it did not wait")
	assert_false(cap.dock.is_handling(far), "the fighter is let go")
	assert_true(far.is_visible_in_tree(), "and flies on")
	assert_false(run.fighters.has(far), "no longer its own")
	assert_eq(cap.dock.returning_count(), 0)


func test_its_fighters_go_home_when_only_three_of_the_raid_are_left() -> void:
	# D83: at three left they are all called home; every survivor docked, the carrier flees.
	var run: CarrierRun = await _bring_in_docked()
	var cap: CapitalStandin = run.carrier
	var raid: Array[RigidBody3D] = run.fighters.duplicate()
	_kill(raid[0])
	_kill(raid[1])
	await _fly(2.0)
	assert_eq(cap.dock.returning_count(), 0, "four of six left: they fight on")
	assert_lt(run.recalled_at_s, 0.0)
	_kill(raid[2])
	await _fly(2.0, func() -> bool: return run.recalled_at_s >= 0.0)
	assert_gte(run.recalled_at_s, 0.0, "three left: called home")
	assert_eq(cap.dock.returning_count(), 3, "all three of them")
	assert_eq(run.state, CarrierRun.State.STANDOFF, "the carrier stands off while they come")
	await _fly(float(run.options["wait_s"]) + 5.0, func() -> bool: return run.state == CarrierRun.State.FLEEING)
	assert_eq(run.state, CarrierRun.State.FLEEING, "every survivor docked: it flees")
	assert_eq(run.flee_reason, CarrierTactics.FLEE_ALL_DOCKED)
	assert_eq(cap.dock.docked_count(), 3)
	assert_eq(run.left_behind, 0)
	assert_eq(cap.damageable.hull.fraction(), 1.0, "unhurt: it fled for its fighters' sake alone")


func test_with_every_fighter_lost_it_flees() -> void:
	var run: CarrierRun = await _bring_in_docked()
	for body: RigidBody3D in run.fighters.duplicate():
		_kill(body)
	await _fly(3.0, func() -> bool: return run.state == CarrierRun.State.FLEEING)
	assert_eq(run.state, CarrierRun.State.FLEEING)
	assert_eq(run.flee_reason, CarrierTactics.FLEE_ALL_DOCKED, "no survivor is left to wait for")


func test_it_flees_once_it_has_taken_half_its_hull_in_damage() -> void:
	var run: CarrierRun = await _bring_in_docked()
	var cap: CapitalStandin = run.carrier
	_hull_to(cap, 0.55)
	await _fly(2.0)
	assert_eq(run.state, CarrierRun.State.STANDOFF, "45 % damage: it stays")
	_hull_to(cap, 0.5)
	await _fly(3.0, func() -> bool: return run.state == CarrierRun.State.FLEEING)
	assert_eq(run.state, CarrierRun.State.FLEEING, "50 % damage: it flees (D83)")
	assert_eq(run.flee_reason, CarrierTactics.FLEE_HURT)
	assert_eq(cap.dock.returning_count() + cap.dock.docked_count(), 0,
			"under attack with its drive empty it keeps its fighters out (the play-test rules of 2026-11-20)")
	assert_true(_run("carrier charge").ok)
	await _fly(2.0, func() -> bool: return cap.dock.returning_count() + cap.dock.docked_count() == 6)
	assert_eq(cap.dock.returning_count() + cap.dock.docked_count(), 6, "able to jump, it calls every fighter home")
	assert_true(_run("carrier hurt").ok)
	assert_lt(cap.damageable.hull.fraction(), float(run.options["retreat_hull"]), "the console's `hurt` takes it under the same share")


func test_with_its_drive_recharging_it_runs_for_the_gate_and_gets_away() -> void:
	# D83: the gate needs no drive. Put 2.5 km in front of the gate with its fighters far behind, it runs in and is gone.
	var run: CarrierRun = await _bring_in_docked()
	var cap: CapitalStandin = run.carrier
	var gate: Jumpgate = main.gates.gate()
	assert_not_null(gate, "free flight has its jumpgate")
	cap.global_transform = Transform3D(Basis.looking_at(gate.global_basis.z, gate.global_basis.y),
			gate.global_transform * Vector3(200.0, 0.0, -2500.0))
	cap.linear_velocity = main.world.rest_velocity()
	cap.reset_physics_interpolation()
	run.options["wait_s"] = 5.0
	assert_gt(JumpCapability.recharge_left_s(cap, SimClock.now()), 120.0, "its drive is far from recharged")
	assert_true(_run("carrier recall").ok)
	await _fly(5.0, func() -> bool: return run.move == CarrierTactics.MOVE_GATE)
	assert_eq(run.state, CarrierRun.State.FLEEING)
	assert_eq(run.move, CarrierTactics.MOVE_GATE, "still recharging: it runs for the gate")
	assert_eq(run.gate, gate)
	assert_null(run.departure, "it opens no point of its own")
	var opened: int = main.gates.console_points.opened
	await _fly(150.0, func() -> bool: return carriers.gate_departures > 0)
	assert_eq(carriers.gate_departures, 1, "through the gate's vortex")
	assert_eq(run.left_via, CarrierRun.VIA_GATE)
	assert_eq(run.state, CarrierRun.State.DONE)
	assert_eq(main.gates.console_points.opened, opened, "no jump point was opened for it")
	assert_false(JumpCapability.drive_ready(cap, SimClock.now()), "its drive was still recharging")
	assert_eq(run.left_behind, 6, "its fighters, 50 km behind, were not home in time (Q30)")
	assert_eq(carriers.free_count(), carriers.size(), "it is back in its pool")
	assert_false(cap.damageable.hull.destroyed)


func test_with_no_gate_it_runs_until_its_drive_is_ready_then_jumps() -> void:
	var run: CarrierRun = await _bring_in_docked()
	var cap: CapitalStandin = run.carrier
	main.gates.gate().remove_from_group(Jumpgate.GROUP)  # a place with no gate
	run.options["wait_s"] = 1.0
	assert_true(_run("carrier recall").ok)
	await _fly(5.0, func() -> bool: return run.move == CarrierTactics.MOVE_RUN)
	assert_eq(run.move, CarrierTactics.MOVE_RUN, "no gate and no drive: it runs")
	var v0: Vector3 = cap.linear_velocity
	var departed: int = carriers.carriers_departed
	await _fly(25.0)
	assert_eq(run.state, CarrierRun.State.FLEEING, "it cannot leave yet")
	assert_null(run.departure)
	assert_eq(carriers.carriers_departed, departed)
	assert_gt((cap.linear_velocity - v0).length(), CarrierJumps.CARRIER_SPEED_MPS, "faster than its cruise")
	var status: ConsoleResult = _run("carrier status")
	assert_string_contains(status.lines[0], "recharging")
	assert_string_contains(status.lines[0], "flees (raid_over: run)")
	assert_gt(float(DebugConsole.registry.read("carriers.drive_left_s")["value"]), 0.0)
	assert_true(_run("carrier charge").ok)
	await _fly(60.0, func() -> bool: return run.state == CarrierRun.State.LEAVING)
	assert_eq(run.state, CarrierRun.State.LEAVING, "its drive ready, it slows onto its bow and opens its own point")
	assert_not_null(run.departure)
	await _fly(70.0, func() -> bool: return carriers.carriers_departed > departed)
	assert_eq(carriers.carriers_departed, departed + 1)
	assert_eq(run.left_via, CarrierRun.VIA_POINT)
	assert_lt(SimClock.now() - run.state_at_s, CarrierJumps.LEAVE_LIMIT_S, "through its point, not given up on")
	assert_eq(carriers.gate_departures, 0)


func test_a_carrier_with_no_cradles_holds_its_course_until_its_drive_has_recharged() -> void:
	carriers.ensure_free(CarrierJumps.DEFAULT_CLASS)
	var points: JumpPointPool = main.gates.console_points
	var at: Vector3 = main.ship.global_position + Vector3(0.0, 0.0, -3000.0)
	var run: CarrierRun = carriers.run_for(points, main.world.to_universe(at), Vector3.RIGHT, Factions.EARTH_ALLIANCE,
			{"class": "cruiser"})
	assert_not_null(run)
	var cap: CapitalStandin = run.carrier
	assert_eq(cap.ship_class, &"cruiser")
	assert_false(JumpCapability.drive_ready(cap, SimClock.now()), "the jump in emptied its drive")
	var departed: int = carriers.carriers_departed
	await _fly(20.0)
	assert_eq(run.state, CarrierRun.State.HOLDING, "its drive recharging, it holds its course")
	assert_null(run.departure)
	assert_false(run.arrival.held, "its arrival point let go to close by its timing")
	assert_eq(points.collapses, 0, "not collapsed by its moving off")
	cap.jump_drive.charge()
	await _fly(3.0, func() -> bool: return run.state == CarrierRun.State.LEAVING)
	assert_eq(run.state, CarrierRun.State.LEAVING, "recharged, it opens its point out")
	await _fly(30.0, func() -> bool: return carriers.carriers_departed > departed)
	assert_eq(carriers.carriers_departed, departed + 1)


# --- the maintainer's play-test of 2026-11-20 ----------------------------------------------------------------------------


func _station() -> Station:
	return get_tree().get_nodes_in_group(Station.GROUP)[0] as Station


# The carrier's speed against the frame's rest, m/s.
func _speed(cap: CapitalStandin) -> float:
	return (cap.linear_velocity - main.world.rest_velocity()).length()


func test_far_from_the_player_its_launched_fighters_stay_its_own() -> void:
	# The bug: beyond the tier's radius its launched fighters were parked in the low-attention tier, read as lost, and the
	# carrier called the rest home or fled at once ("it launched only a few").
	assert_true(_run("transit docked").ok)
	var run: CarrierRun = carriers.runs()[0]
	var cap: CapitalStandin = run.carrier
	main.ship.global_position += Vector3(0.0, 14000.0, 0.0)  # the raid is now well beyond the tier's 10 km
	await _fly(60.0, func() -> bool: return run.state == CarrierRun.State.STANDOFF)
	await _fly(15.0)
	assert_eq(run.state, CarrierRun.State.STANDOFF, "it stands off: nobody is lost")
	assert_lt(run.recalled_at_s, 0.0, "and nobody is called home")
	assert_eq(cap.dock.launches, 6, "all six were launched")
	assert_eq(cap.dock.returning_count() + cap.dock.docked_count(), 0)
	for body: RigidBody3D in run.fighters:
		assert_true(body.is_visible_in_tree(), "a launched fighter flies on its own body")
		assert_false(body.has_meta(TierDirector.TIER_META), "not parked in the tier")
		assert_true((body as Ship).tier_exempt, "exempt while it is the carrier's")
	var one: Ship = run.fighters[0] as Ship
	run.options["wait_s"] = 0.5
	one.global_position = cap.global_position + Vector3(9000.0, 0.0, 0.0)
	assert_true(_run("carrier charge").ok)
	assert_true(_run("carrier recall").ok)
	await _fly(20.0, func() -> bool: return run.left_behind > 0)
	assert_gt(run.left_behind, 0)
	assert_false(one.tier_exempt, "left behind, it is the tier's again")


func test_hit_with_its_drive_empty_it_launches_every_docked_fighter_at_once() -> void:
	assert_true(_run("transit docked").ok)
	var run: CarrierRun = carriers.runs()[0]
	var cap: CapitalStandin = run.carrier
	await _fly(30.0, func() -> bool: return run.state == CarrierRun.State.HOLDING)
	assert_eq(cap.dock.docked_count(), 6, "clear of its point, its fighters still on their cradles")
	assert_false(JumpCapability.drive_ready(cap, SimClock.now()), "the jump in emptied its drive")
	_hull_to(cap, 0.97)
	await _fly(0.2)
	assert_eq(cap.dock.docked_count(), 0, "hit, and unable to jump away: every cradle lets go")
	assert_eq(cap.dock.busy_count(), 6, "all six leaving together (one at a time takes 2 s to start and 1.75 s more)")
	await _fly(10.0, func() -> bool: return cap.dock.launches == 6)
	assert_eq(cap.dock.launches, 6)
	assert_eq(carriers.fighters_launched, 6)
	for body: RigidBody3D in run.fighters:
		assert_false(Damageable.of(body).hull.destroyed, "unhurt by leaving together")


func test_hit_with_its_drive_ready_it_launches_them_in_turn() -> void:
	assert_true(_run("transit docked").ok)
	var run: CarrierRun = carriers.runs()[0]
	var cap: CapitalStandin = run.carrier
	await _fly(30.0, func() -> bool: return run.state == CarrierRun.State.HOLDING)
	assert_true(_run("carrier charge").ok)
	_hull_to(cap, 0.97)
	await _fly(0.2)
	assert_gte(cap.dock.docked_count(), 5, "able to jump away, it is not cornered: no scramble")


func test_cornered_it_throws_out_the_fighters_it_had_called_home() -> void:
	var run: CarrierRun = await _bring_in_docked()
	var cap: CapitalStandin = run.carrier
	var raid: Array[RigidBody3D] = run.fighters.duplicate()
	for i: int in 3:
		_kill(raid[i])
	await _fly(float(run.options["wait_s"]) + 5.0, func() -> bool: return cap.dock.docked_count() == 3)
	assert_eq(cap.dock.docked_count(), 3, "three left: home and docked")
	_hull_to(cap, 0.9)
	await _fly(1.0, func() -> bool: return cap.dock.docked_count() == 0)
	assert_eq(cap.dock.docked_count(), 0, "under attack with its drive empty: out again, all three")
	await _fly(6.0)
	assert_eq(cap.dock.returning_count() + cap.dock.docked_count(), 0, "and not called home while that lasts")
	assert_true(_run("carrier charge").ok)
	await _fly(3.0, func() -> bool: return cap.dock.returning_count() + cap.dock.docked_count() == 3)
	assert_eq(cap.dock.returning_count() + cap.dock.docked_count(), 3, "able to jump, it calls them home again")
	var departed: int = carriers.carriers_departed
	await _fly(float(run.options["wait_s"]) + 90.0, func() -> bool: return carriers.carriers_departed > departed)
	assert_eq(carriers.carriers_departed, departed + 1, "and jumps out")
	assert_gte(run.recovered, 2, "with those that made it aboard")


func test_called_home_from_far_off_they_reach_a_carrier_that_is_turning() -> void:
	# Found with the weave: the docking path followed the carrier's turn at any range, so a fighter kilometres out was asked
	# for hundreds of m/s sideways and flew away for ever (the wave never ended).
	var run: CarrierRun = await _bring_in_docked()
	var cap: CapitalStandin = run.carrier
	var raid: Array[RigidBody3D] = run.fighters.duplicate()
	var side: Vector3 = cap.global_basis.x
	for i: int in raid.size():
		raid[i].global_position = cap.global_position + side * 9000.0 + cap.global_basis.y * 200.0 * float(i)
		raid[i].linear_velocity = cap.linear_velocity
	main.ship.global_position = cap.global_position - side * 15000.0  # nobody near for it to back away from
	for i: int in 3:
		_kill(raid[i])
	await _fly(3.0, func() -> bool: return cap.dock.returning_count() == 3)
	assert_eq(cap.dock.returning_count(), 3, "three left, 9 km out: called home")
	await _fly(8.0)  # its helm and engines settle onto the course it holds for them
	var course: Vector3 = cap.linear_velocity - main.world.rest_velocity()
	var bow: Vector3 = -cap.global_basis.z
	var swung: float = 0.0
	var veered: float = 0.0
	var furthest: float = 0.0
	for i: int in 40:
		await _fly(5.0, func() -> bool: return cap.dock.docked_count() == 3)
		if cap.dock.returning_count() > 0:
			swung = maxf(swung, rad_to_deg(bow.angle_to(-cap.global_basis.z)))
			veered = maxf(veered, rad_to_deg(course.angle_to(cap.linear_velocity - main.world.rest_velocity())))
			assert_gt(_speed(cap), 0.5 * float(run.options["weave_mps"]), "under way all the while")
		for k: int in range(3, raid.size()):
			if not JumpCapability.is_destroyed(raid[k]) and not cap.dock.is_docked(raid[k] as Ship):
				furthest = maxf(furthest, raid[k].global_position.distance_to(cap.global_position))
		if cap.dock.docked_count() == 3:
			break
	assert_eq(cap.dock.docked_count(), 3, "all three made it home")
	assert_lt(swung, 10.0, "the carrier held its heading for them (%.0f degrees)" % swung)
	assert_lt(veered, 15.0, "and a steady course (%.0f degrees)" % veered)
	assert_lt(furthest, 9500.0, "none flew off on the way (%.0f m)" % furthest)
	assert_eq(cap.damageable.hull.fraction(), 1.0, "and none rammed it")


func test_standing_off_it_stays_outside_the_stations_guns() -> void:
	var run: CarrierRun = await _bring_in_docked()
	var cap: CapitalStandin = run.carrier
	var station: Station = _station()
	var reach_m: float = station.grid.reach_m()
	var margin_m: float = float(run.options["grid_margin_m"])
	assert_gt(reach_m, 6000.0, "the heavy cannons reach 6 km from their mounts")
	var out: Vector3 = (cap.global_position - station.global_position).normalized()
	cap.global_position = station.global_position + out * (reach_m + 0.4 * margin_m)  # inside the margin it keeps
	cap.linear_velocity = main.world.rest_velocity()
	main.ship.global_position = cap.global_position + out * 12000.0  # nobody near to move it
	var nearest: float = INF
	for i: int in 24:
		await _fly(5.0)
		nearest = minf(nearest, cap.global_position.distance_to(station.global_position))
	assert_gt(nearest, reach_m, "never inside the reach of the guns (%.0f m, reach %.0f m)" % [nearest, reach_m])
	assert_gt(cap.global_position.distance_to(station.global_position), reach_m + margin_m - 400.0, "and back out by its margin")
	assert_eq(run.state, CarrierRun.State.STANDOFF)


func test_it_never_sits_still() -> void:
	var run: CarrierRun = await _bring_in_docked()
	var cap: CapitalStandin = run.carrier
	var station: Station = _station()
	var out: Vector3 = (cap.global_position - station.global_position).normalized()
	cap.global_position = station.global_position + out * (station.grid.reach_m() + float(run.options["grid_margin_m"]) + 8000.0)
	cap.linear_velocity = main.world.rest_velocity()
	main.ship.global_position = cap.global_position + out * 12000.0  # nothing to back away from, nothing to keep clear of
	await _fly(20.0)
	var weave_mps: float = float(run.options["weave_mps"])
	var first: Vector3 = cap.linear_velocity - main.world.rest_velocity()
	var turned: float = 0.0
	for i: int in 30:
		await _fly(3.0)
		assert_between(_speed(cap), 0.5 * weave_mps, CarrierJumps.CARRIER_SPEED_MPS, "always under way, slowly")
		turned = maxf(turned, rad_to_deg(first.angle_to(cap.linear_velocity - main.world.rest_velocity())))
	assert_gt(turned, 90.0, "and its course keeps turning: a weave, not a straight line")
	assert_eq(run.state, CarrierRun.State.STANDOFF)
	assert_true(_run("carrier charge").ok)
	assert_true(_run("carrier recall").ok)
	await _fly(3.0, func() -> bool: return run.move == CarrierTactics.MOVE_WAIT)
	assert_eq(run.move, CarrierTactics.MOVE_WAIT)
	await _fly(4.0)
	assert_gt(_speed(cap), 0.5 * weave_mps, "waiting for its fighters it still does not sit still")


func test_its_run_for_the_gate_goes_round_the_stations_guns() -> void:
	var run: CarrierRun = await _bring_in_docked()
	var cap: CapitalStandin = run.carrier
	var station: Station = _station()
	var gate: Jumpgate = main.gates.gate()
	var keep_m: float = station.grid.reach_m() + float(run.options["grid_margin_m"])
	var from_gate: Vector3 = (station.global_position - gate.global_position).normalized()
	cap.global_position = station.global_position + from_gate * (keep_m + 3000.0)  # the station lies between it and the gate
	cap.linear_velocity = main.world.rest_velocity()
	main.ship.global_position = cap.global_position + from_gate * 20000.0
	run.options["wait_s"] = 1.0
	assert_true(_run("carrier recall").ok)
	await _fly(5.0, func() -> bool: return run.move == CarrierTactics.MOVE_GATE)
	assert_eq(run.move, CarrierTactics.MOVE_GATE, "its drive recharging, it runs for the gate")
	var course: Vector3 = (cap.cruise_velocity - main.world.rest_velocity()).normalized()
	var to_station: Vector3 = station.global_position - cap.global_position
	var miss_m: float = (to_station - course * to_station.dot(course)).length()
	assert_gt(miss_m, station.grid.reach_m(), "its course passes outside the guns' reach (%.0f m off the station)" % miss_m)
	assert_gt(course.dot((gate.global_position - cap.global_position).normalized()), 0.5, "while still making for the gate")


func test_it_backs_away_from_an_attacker_with_its_stern_to_it() -> void:
	var run: CarrierRun = await _bring_in_docked()
	var cap: CapitalStandin = run.carrier
	var player: Ship = main.ship
	var away: Vector3 = cap.global_basis.x  # the player comes in on its beam, well inside its stand-off
	player.global_position = cap.global_position - away * 0.4 * float(run.options["standoff_m"])
	player.linear_velocity = cap.linear_velocity
	var v0: Vector3 = cap.linear_velocity
	var bow0: float = (-cap.global_basis.z).dot(away)
	await _fly(12.0)
	assert_eq(run.state, CarrierRun.State.STANDOFF, "an attacker alone does not end its raid")
	assert_gt(cap.heading.dot(away), 0.95, "its helm turns its stern to the attacker (Q30)")
	assert_gt((-cap.global_basis.z).dot(away), bow0 + 0.1, "and the bow comes round")
	assert_gt((cap.linear_velocity - v0).dot(away), 10.0, "it backs away")


func test_a_badly_hurt_fighter_is_called_back_alone() -> void:
	var run: CarrierRun = await _bring_in_docked()
	var cap: CapitalStandin = run.carrier
	var hurt: Ship = run.fighters[0] as Ship
	var hull: Damageable = Damageable.of(hurt)
	var keep: float = 0.5 * float(run.options["fighter_return_hull"]) * hull.hull.max_hp
	hull.apply_hit(HitInfo.new(hurt.get_instance_id(), 0, &"", hull.hull.hp - keep, hurt.global_position, Vector3.ZERO, 0.0,
			HitInfo.CAUSE_CONSOLE))
	var scratched: Ship = run.fighters[1] as Ship
	var other: Damageable = Damageable.of(scratched)
	other.apply_hit(HitInfo.new(scratched.get_instance_id(), 0, &"", 0.75 * other.hull.max_hp, scratched.global_position,
			Vector3.ZERO, 0.0, HitInfo.CAUSE_CONSOLE))
	await _fly(2.0)
	assert_almost_eq(float(run.options["fighter_return_hull"]), 0.2, 1e-6, "under 20 % of its hull (D83)")
	assert_false(cap.dock.is_handling(scratched), "at 25 % it fights on")
	assert_true(cap.dock.is_handling(hurt), "under its share of hull it is called back (Q27)")
	assert_eq(cap.dock.returning_count(), 1, "alone")
	await _fly(90.0, func() -> bool: return cap.dock.is_docked(hurt))
	assert_true(cap.dock.is_docked(hurt), "and docks")
	assert_eq(run.state, CarrierRun.State.STANDOFF, "while the raid goes on")


func test_a_carrier_that_stays_still_launches_its_fighters() -> void:
	assert_true(_run("transit docked").ok)
	var run: CarrierRun = carriers.runs()[0]
	var cap: CapitalStandin = run.carrier
	run.then = CarrierJumps.THEN_STAY
	await _fly(60.0, func() -> bool: return run.state == CarrierRun.State.STAYING)
	assert_eq(run.state, CarrierRun.State.STAYING, "it stays in play")
	assert_eq(cap.dock.launches, 6, "with its fighters launched first (Q29)")


func test_destroyed_it_takes_its_docked_fighters_with_it() -> void:
	assert_true(_run("transit docked").ok)
	var run: CarrierRun = carriers.runs()[0]
	var cap: CapitalStandin = run.carrier
	await _fly(1.0)
	var docked: Array[RigidBody3D] = run.fighters.duplicate()
	assert_eq(cap.dock.docked_count(), 6)
	var causes: Array[StringName] = []
	Damageable.of(docked[0]).destroyed.connect(func(info: HitInfo) -> void: causes.append(info.cause))
	assert_true(_run("carrier kill").ok)
	await wait_physics_frames(4)
	assert_true(cap.damageable.hull.destroyed)
	assert_eq(cap.dock.lost_docked, 6)
	for body: RigidBody3D in docked:
		assert_true(Damageable.of(body).hull.destroyed, "a docked fighter dies with its carrier (Q28)")
	assert_eq(causes, [HitInfo.CAUSE_CARRIER_LOST] as Array[StringName], "with no one credited")
	assert_eq(carriers.runs().size(), 0, "its run is over")
	assert_false(run.arrival.is_active() and run.arrival.held, "and the point it held collapses")


func test_the_console_reports_the_carrier() -> void:
	assert_false(_run("carrier").ok, "no carrier at work yet")
	assert_true(_run("transit carrier").ok)
	var run: CarrierRun = carriers.runs()[0]
	assert_eq(run.fighters.size(), 2, "two fighters out of its point beside it (Q29)")
	assert_eq(run.carrier.dock.docked_count(), 0)
	var status: ConsoleResult = _run("carrier status")
	assert_true(status.ok)
	assert_string_contains(status.lines[0], "arriving")
	assert_string_contains(status.lines[0], "drive recharging", "the jump in emptied its drive (M8-T08)")
	assert_eq(String(DebugConsole.registry.read("carriers.flee")["value"]), "", "it is not fleeing")
	assert_eq(int(DebugConsole.registry.read("carriers.docked")["value"]), 0)
	assert_eq(String(DebugConsole.registry.read("carriers.state")["value"]), "arriving")
	assert_almost_eq(float(DebugConsole.registry.read("carriers.hull")["value"]), 1.0, 1e-6)
