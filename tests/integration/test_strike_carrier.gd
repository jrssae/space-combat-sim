extends GutTest
## The raiders' strike carrier in the real main scene (M12-T19, Q25 to Q30), headless: it is built from its generated hull with
## its compound collision, comes out of its own jump point with its fighters docked, launches them, stands off, calls them back,
## waits, jumps out with those that docked and hands them to their pool; a fighter not home in time is left behind; destroyed,
## it takes its docked fighters with it.

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
	assert_eq(shapes, int((manifest["collision"] as Dictionary)["shape_count"]), "every shape of the manifest's compound")
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


func test_it_calls_its_fighters_back_and_jumps_out_with_them() -> void:
	var run: CarrierRun = await _bring_in_docked()
	var cap: CapitalStandin = run.carrier
	var free_before: int = main.ships.free_count(ShipPool.DEFAULT_TYPE)
	assert_true(_run("carrier recall").ok)
	await _fly(5.0, func() -> bool: return run.state == CarrierRun.State.RECALLING)
	assert_eq(run.state, CarrierRun.State.RECALLING)
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
	assert_true(_run("carrier recall").ok)
	await _fly(20.0, func() -> bool: return run.state == CarrierRun.State.LEAVING)
	assert_eq(run.state, CarrierRun.State.LEAVING)
	assert_gt(run.left_behind, 0, "it did not wait")
	assert_false(cap.dock.is_handling(far), "the fighter is let go")
	assert_true(far.is_visible_in_tree(), "and flies on")
	assert_eq(cap.dock.returning_count(), 0)


func test_hurt_past_its_threshold_it_recalls_on_its_own() -> void:
	var run: CarrierRun = await _bring_in_docked()
	assert_true(_run("carrier hurt").ok)
	assert_lt(run.carrier.damageable.hull.fraction(), float(run.options["retreat_hull"]))
	await _fly(3.0, func() -> bool: return run.state == CarrierRun.State.RECALLING)
	assert_eq(run.state, CarrierRun.State.RECALLING, "under its retreat threshold it calls its fighters back (Q30)")


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
	await _fly(2.0)
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
	assert_eq(int(DebugConsole.registry.read("carriers.docked")["value"]), 0)
	assert_eq(String(DebugConsole.registry.read("carriers.state")["value"]), "arriving")
	assert_almost_eq(float(DebugConsole.registry.read("carriers.hull")["value"]), 1.0, 1e-6)
