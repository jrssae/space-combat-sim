extends GutTest
## Holding a jump point (M6-T23, the maintainer's rule), headless: a fighter cannot open a point, a capital stand-in can and holds
## it; the point collapses with its closing flash and kills the ship in its funnel when its opener flies past its hold range
## (twice its length from the mouth) or is destroyed; an opener leaving through its own point holds it a few seconds for the
## ships behind it, then the point collapses on whatever is still inside.

const RAIDER_SPEC: String = "res://assets/ships/raider_delta_v.tres"
const DT: float = 1.0 / 60.0

var world: WorldFrame
var raider: Combatant
var cap: CapitalStandin
var pool: JumpPointPool
var transits: VortexTransits


func before_each() -> void:
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	raider = ShipAssembly.build(load(RAIDER_SPEC) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.RAIDERS,
		ShipAssembly.OPT_DISPLAY_NAME: "RAIDER 1",
		ShipAssembly.OPT_AI: true,
	})
	world.spawn(raider.ship, world.to_universe(Vector3(0.0, 0.0, -1000.0)))
	cap = CapitalStandin.create(&"cruiser", Factions.RAIDERS, "CRUISER 1", Vector3.ZERO)
	world.spawn(cap, world.to_universe(Vector3.ZERO), Basis.IDENTITY)
	pool = JumpPointPool.new()
	pool.world = world
	world.add_child(pool)
	pool.prepare(4)
	transits = VortexTransits.attach(world)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


# The cruiser's own arrival point at its place, the raider waiting in its funnel to come out beside it.
func _capital_point_with_the_raider_inside() -> JumpVortex:
	var point: JumpVortex = pool.open_for(world.to_universe(cap.global_position), Vector3.FORWARD, cap.cross_radius_m(),
			JumpVortex.Direction.ARRIVAL, false, cap)
	var exit: Transform3D = CarrierJumps.ride_transform(point, 0, raider.ship)
	raider.ship.reset_to(exit)
	assert_true(transits.begin_arrival(raider.ship, point, exit.origin, Vector3.ZERO))
	return point


func test_a_fighter_cannot_open_a_point_and_a_capital_holds_its_own() -> void:
	var refused: JumpVortex = pool.open_for(world.to_universe(raider.ship.global_position), Vector3.FORWARD,
			raider.ship.bounding_radius(), JumpVortex.Direction.ARRIVAL, true, raider.ship)
	assert_null(refused, "a raider cannot open a jump point")
	assert_eq(pool.refused, 1)
	assert_eq(pool.open_count(), 0)
	var point: JumpVortex = pool.open_for(world.to_universe(cap.global_position), Vector3.FORWARD, cap.cross_radius_m(),
			JumpVortex.Direction.ARRIVAL, false, cap)
	assert_not_null(point, "a cruiser stand-in can")
	assert_true(point.held)
	assert_eq(point.opener, cap)
	assert_almost_eq(point.hold_range_m, 600.0, 1e-3, "twice the cruiser's 300 m")
	await _frames(5)
	assert_true(point.held and point.is_active(), "it holds while its opener is near")
	assert_eq(pool.collapses, 0)
	var free: JumpVortex = pool.open_for(world.to_universe(Vector3(0.0, 2000.0, 0.0)), Vector3.FORWARD, 10.0)
	assert_false(free.held, "a point with no opener (a debug tool's) is held by nothing")


func test_a_point_collapses_when_its_opener_flies_out_of_range_killing_the_ship_in_its_funnel() -> void:
	var point: JumpVortex = _capital_point_with_the_raider_inside()
	await _frames(3)
	assert_true(transits.is_passing(raider.ship), "the raider is in the funnel")
	var mouth: Vector3 = point.true_frame().origin
	cap.global_position = mouth + Vector3(0.0, 0.0, -590.0)  # just inside 600 m
	await _frames(2)
	assert_eq(pool.collapses, 0, "within its range it holds")
	cap.global_position = mouth + Vector3(0.0, 0.0, -650.0)
	await _frames(2)
	assert_eq(pool.collapses, 1, "past twice its length from the mouth the point collapses")
	assert_eq(pool.last_collapse, JumpCapability.OUT_OF_RANGE)
	assert_eq(point.phase_name(), "end_flash", "the closing flash at once")
	assert_true(raider.damageable.hull.destroyed, "the ship in its funnel is destroyed")
	assert_false(transits.is_passing(raider.ship))
	assert_eq(pool.collapse_kills, 1)
	assert_false(cap.damageable.hull.destroyed, "the opener itself flies on")


func test_a_point_collapses_when_its_opener_is_destroyed() -> void:
	var point: JumpVortex = _capital_point_with_the_raider_inside()
	var killer: Array[HitInfo] = []
	raider.damageable.destroyed.connect(func(info: HitInfo) -> void: killer.append(info))
	await _frames(2)
	assert_true(cap.damageable.kill())
	await _frames(2)
	assert_eq(pool.last_collapse, JumpCapability.DESTROYED)
	assert_eq(point.phase_name(), "end_flash")
	assert_true(raider.damageable.hull.destroyed)
	assert_eq(killer.size(), 1)
	assert_eq(killer[0].cause, HitInfo.CAUSE_VORTEX_COLLAPSE)
	assert_eq(killer[0].shooter_id, 0, "no one is credited with the kill")


func test_a_capital_opens_no_second_point_until_its_drive_has_recharged() -> void:
	# M8-T08, D83: the jump in empties the drive; the pool refuses another point until the class's recharge has passed.
	var first: JumpVortex = pool.open_for(world.to_universe(cap.global_position), Vector3.FORWARD, cap.cross_radius_m(),
			JumpVortex.Direction.ARRIVAL, false, cap)
	assert_not_null(first)
	assert_false(JumpCapability.drive_ready(cap, SimClock.now()), "opening a point empties its drive")
	assert_almost_eq(JumpCapability.recharge_left_s(cap, SimClock.now()), CapitalData.jump_recharge_s(&"cruiser"), 0.1)
	var xform := Transform3D(Basis.looking_at(Vector3.BACK, Vector3.UP), Vector3(0.0, 0.0, -400.0))
	var fit := VortexFit.new(60.0, 96.0)
	assert_null(pool.open_with(xform, fit, JumpVortex.Direction.DEPARTURE, VortexTiming.DEFAULT_HOLD_S, cap),
			"still recharging: no point out")
	assert_null(pool.open_for(world.to_universe(Vector3(0.0, 900.0, 0.0)), Vector3.FORWARD, cap.cross_radius_m(),
			JumpVortex.Direction.ARRIVAL, false, cap))
	assert_eq(pool.refused_charging, 2)
	assert_eq(pool.refused, 0, "not for want of a drive")
	assert_eq(pool.open_count(), 1)
	cap.jump_drive.fire(SimClock.now() - cap.jump_drive.recharge_s - 1.0)  # as if its recharge had passed a second ago
	assert_not_null(pool.open_with(xform, fit, JumpVortex.Direction.DEPARTURE, VortexTiming.DEFAULT_HOLD_S, cap),
			"recharged, it opens its point out")
	assert_false(JumpCapability.drive_ready(cap, SimClock.now()), "which empties it again")
	assert_not_null(pool.open_with(Transform3D(Basis.IDENTITY, Vector3(0.0, -900.0, 0.0)), fit, JumpVortex.Direction.ARRIVAL),
			"a point with no opener needs no drive")


func test_an_opener_leaving_through_its_own_point_holds_it_briefly_then_it_collapses_on_whatever_is_inside() -> void:
	# The cruiser flies into its own departure point 50 m ahead at 150 m/s; the raider follows far behind, slowly.
	var r: float = maxf(VortexFit.POINT_RADII_PER_SHIP * cap.cross_radius_m(), VortexFit.MIN_POINT_RADIUS_M)
	var xform := Transform3D(Basis.looking_at(Vector3.BACK, Vector3.UP), Vector3(0.0, 0.0, -50.0))
	var point: JumpVortex = pool.open_with(xform, VortexFit.new(r, r * VortexFit.POINT_DEPTH_RATIO),
			JumpVortex.Direction.DEPARTURE, VortexTiming.DEFAULT_HOLD_S, cap)
	assert_not_null(point)
	while not point.is_passable_for(JumpVortex.Direction.DEPARTURE):
		await _frames(1)
	cap.global_position = point.true_frame().origin + Vector3(0.0, 0.0, -1.0)
	cap.linear_velocity = Vector3(0.0, 0.0, -150.0)
	var through: Array[Node3D] = []
	assert_true(transits.begin_departure(cap, point, func(body: Node3D) -> void: through.append(body)))
	raider.ship.reset_to(Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), point.true_frame().origin))
	raider.ship.linear_velocity = Vector3(0.0, 0.0, -5.0)
	assert_true(transits.begin_departure(raider.ship, point, func(_body: Node3D) -> void: pass))
	var ticks: int = 0
	while through.is_empty() and ticks < 600:
		await _frames(1)
		ticks += 1
	assert_eq(through.size(), 1, "the cruiser went through its ring")
	assert_gte(point.opener_through_at_s, 0.0, "its point knows its opener has gone through")
	var through_at: float = SimClock.now()
	while SimClock.now() - through_at < JumpCapability.OWN_DEPARTURE_HOLD_S - 0.3:
		await _frames(1)
		assert_eq(pool.collapses, 0, "held for the ships behind it")
		assert_true(point.is_active())
	while pool.collapses == 0 and SimClock.now() - through_at < JumpCapability.OWN_DEPARTURE_HOLD_S + 0.5:
		await _frames(1)
	assert_eq(pool.collapses, 1, "then it closes")
	assert_eq(pool.last_collapse, JumpCapability.OPENER_THROUGH)
	assert_true(raider.damageable.hull.destroyed, "the raider still in the funnel dies")
