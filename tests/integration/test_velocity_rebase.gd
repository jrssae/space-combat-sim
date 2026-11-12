extends TestSteps
## The velocity rebase (M6-T05, D64, Q8, AC1): a boost takes `dv` off every local velocity and gives it to the frame, so no
## universe position and no universe velocity changes: ships, tier rows, a capital and its cruise, bolt rows, a bolt node,
## debris, a staged wreck, an explosion, particle emitters, a far flash. A buoy and the rocks stay with the anchor while the
## frame flies on. A boost is no ram. The automatic boost fires at the threshold and returns to the anchor under half of it.
##
## Universe velocity here is the local velocity plus `WorldFrame.origin_velocity`, summed in 64-bit.

const FreeFall: GDScript = preload("res://tests/integration/test_free_fall.gd")
const STARFURY_SPEC: String = "res://assets/ships/starfury_aurora.tres"
const DV := Vector3(1500.0, -200.0, 800.0)
## One float32 step of a 2 000 m/s velocity is 1.2e-4 m/s: what taking `dv` off a velocity may round by, per axis.
const VELOCITY_TOL: float = 5.0e-4
const TIER_RADIUS_M: float = 10000.0
const FAR := Vector3(300.0, 0.0, -15000.0)

var w: TierWorld
var world: WorldFrame
var debris: DebrisPool
var fx: FxPool
var flashes: FarFlashes
var rams: RamResolver
var buoy: NavBuoy
var field: AsteroidField
var near: Combatant
var far: Combatant
var cap: CapitalStandin
var far_cap: CapitalStandin
var bolt: Projectile
var explosion: Explosion
var shards: Array[DebrisChunk] = []
var wreck: StagedWreck
var emitter: int = 0
var _saved: Dictionary = {}
var _ram_backup: bool = true


## Reads late in every tick, once the movers that step themselves have stepped: there a bolt's place and a hull's are of
## the same instant.
class LateSampler extends Node:
	var read: Callable = Callable()
	var rows: Array = []

	func _init() -> void:
		process_physics_priority = 900

	func _physics_process(_delta: float) -> void:
		rows.append(read.call())


func before_each() -> void:
	_saved = TierWorld.save_settings()
	_ram_backup = bool(Settings.get_value(&"ram_damage"))
	Settings.set_value(&"ram_damage", true)
	TierWorld.set_tier(TIER_RADIUS_M)
	Factions.reset()
	ContactScan.invalidate()
	w = TierWorld.new()
	w.build(self, 4, 2)
	world = w.world
	debris = DebrisPool.new()
	debris.name = "Debris"
	world.add_child(debris)
	fx = FxPool.new()
	fx.name = "Fx"
	world.add_child(fx)
	flashes = FarFlashes.attach(world)
	rams = RamResolver.new()
	rams.name = "RamResolver"
	rams.world = world
	w.space.add_child(rams)


func after_each() -> void:
	w.free_world()
	TierWorld.restore_settings(_saved)
	Settings.set_value(&"ram_damage", _ram_backup)
	Factions.reset()
	ContactScan.invalidate()
	ContactScan.clear_statics()


# One of everything that holds a velocity, and the anchor-tied things beside them.
func _populate() -> void:
	w.player.ship.assist_on = false
	w.player.ship.linear_velocity = Vector3(30.0, 5.0, -120.0)
	near = w.pool.acquire("NEAR", world.to_universe(Vector3(400.0, 50.0, -600.0)), Basis.IDENTITY, Vector3(-20.0, 0.0, 60.0),
			IdleBrain.new())
	far = w.pool.acquire("FAR", world.to_universe(FAR), Basis.IDENTITY, Vector3(10.0, -4.0, 25.0), IdleBrain.new())
	cap = w.cruiser(Factions.EARTH_ALLIANCE, "NEAR CRUISER", Vector3(-2000.0, 300.0, 1500.0), Vector3(0.0, 0.0, -30.0))
	far_cap = w.cruiser(Factions.EARTH_ALLIANCE, "FAR CRUISER", Vector3(-3000.0, 0.0, -16000.0), Vector3(12.0, 0.0, -30.0))
	buoy = NavBuoy.create("NAV TEST", Vector3(2.0, 0.0, 0.0))
	world.spawn(buoy, world.to_universe(Vector3(900.0, -100.0, 300.0)))
	field = w.standins.add_asteroids([{"offset": Vector3(0.0, 0.0, 0.0), "radius": 40.0},
			{"offset": Vector3(500.0, 200.0, -100.0), "radius": 25.0}], world.to_universe(Vector3(3000.0, 500.0, -2500.0)))
	await _ticks(6)  # the far ones become tier rows
	var now_s: float = SimClock.now()
	var weapon: WeaponSpec = w.player.cannon.weapon
	for k: int in 3:
		w.sim.add_bolt(Vector3(50.0 * float(k), 20.0, 300.0), Vector3(40.0, 0.0, 900.0 + 10.0 * float(k)), Factions.RAIDERS, 0,
				weapon, now_s)
	bolt = PulseCannon.PROJECTILE_SCENE.instantiate() as Projectile
	bolt.lifetime_s = 30.0
	w.projectiles.add_child(bolt)
	bolt.launch(Vector3(-80.0, 10.0, 200.0), Vector3(0.0, 60.0, -1400.0), now_s)
	shards = debris.burst(&"nothing", [] as Array[Dictionary], Transform3D(Basis.IDENTITY, Vector3(150.0, -60.0, -90.0)),
			Vector3(15.0, 25.0, -45.0), Vector3(0.0, 1.0, 0.0), 7)
	var hardpoints: Hardpoints = Hardpoints.load_file((load(STARFURY_SPEC) as ShipSpec).hardpoints_path())
	wreck = debris.stage_wreck(&"starfury_aurora", hardpoints.chunks, Transform3D(Basis.IDENTITY, Vector3(-300.0, 80.0, 40.0)),
			Vector3(-35.0, 0.0, 70.0), Vector3(0.2, 0.0, 0.0), 11)
	explosion = Explosion.create(12.0, Vector3(55.0, -5.0, 20.0), true)
	world.add_child(explosion)
	explosion.global_position = Vector3(220.0, 0.0, -310.0)
	emitter = fx.burst(FxSpecs.HIT, Vector3(10.0, 20.0, 30.0), Vector3.UP, Vector3(70.0, 0.0, -10.0), 5.0)
	flashes.add(Vector3(-5000.0, 100.0, 8000.0), Vector3(0.0, 90.0, -40.0), 30.0, 1.0e9)
	await get_tree().physics_frame  # the start of a tick: Jolt's last step is in, nothing of this tick has run


static func _add(out: Dictionary, key: String, world_frame: WorldFrame, at: Vector3, velocity: Vector3) -> void:
	var u: UniversePos = world_frame.to_universe(at)
	var w_frame: PackedFloat64Array = world_frame.origin_velocity
	out[key] = PackedFloat64Array([u.x, u.y, u.z, velocity.x + w_frame[0], velocity.y + w_frame[1], velocity.z + w_frame[2]])


# Everything that moves on its own, by name: universe position, then universe velocity (six numbers, 64-bit).
func _movers() -> Dictionary:
	var out: Dictionary = {}
	_add(out, "player", world, w.player.ship.global_position, w.player.ship.linear_velocity)
	_add(out, "near ship", world, near.ship.global_position, near.ship.linear_velocity)
	_add(out, "near capital", world, cap.global_position, cap.linear_velocity)
	_add(out, "near capital's cruise", world, cap.global_position, cap.cruise_velocity)
	for row: Array in [["tier ship", far.ship], ["tier capital", far_cap]]:
		var state: Dictionary = w.sim.core.tier_state((row[1] as Node).get_instance_id())
		if not state.is_empty():
			_add(out, row[0], world, state["position"], state["velocity"])
			if state.has("cruise") and row[1] == far_cap:
				_add(out, "tier capital's cruise", world, state["position"], state["cruise"])
	var columns: Array = w.sim.core.bolt_columns()
	for i: int in int(columns[11]):
		_add(out, "bolt row %d" % i, world, (columns[2] as PackedVector3Array)[i], (columns[12] as PackedVector3Array)[i])
	_add(out, "bolt node", world, bolt.global_position, bolt.velocity)
	for i: int in shards.size():
		_add(out, "shard %d" % i, world, shards[i].global_position, shards[i].velocity)
	_add(out, "wreck", world, wreck.origin, wreck.velocity)
	_add(out, "explosion", world, explosion.global_position, explosion.velocity)
	_add(out, "emitter", world, fx._nodes[fx._slot_of(emitter)].global_position, fx.velocity_of(emitter))
	if not flashes._positions.is_empty():  # a flash is over in a moment
		_add(out, "far flash", world, flashes._positions[0] + flashes.position, flashes._velocities[0])
	return out


# What stands still against the anchor, the same way: a buoy with its own slow drift, and the rocks.
func _anchored() -> Dictionary:
	var out: Dictionary = {}
	var rest: PackedFloat64Array = world.origin_velocity
	_add(out, "buoy", world, buoy.global_position, buoy.velocity - Vector3(rest[0], rest[1], rest[2]))
	for i: int in 2:
		_add(out, "rock %d" % i, world, StaticRows.position_of(field.row_id(i)), -Vector3(rest[0], rest[1], rest[2]))
	_add(out, "rock field", world, field.global_position, -Vector3(rest[0], rest[1], rest[2]))
	return out


# The largest change of universe position and of universe velocity between two samples, and the change of their sums.
static func _change(before: Dictionary, after: Dictionary) -> Dictionary:
	var worst_u: float = 0.0
	var worst_v: float = 0.0
	var sums := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var worst_name: String = ""
	for key: String in before:
		var a: PackedFloat64Array = before[key]
		var b: PackedFloat64Array = after[key]
		for i: int in 6:
			sums[i] += b[i] - a[i]
		var du: float = Vector3(b[0] - a[0], b[1] - a[1], b[2] - a[2]).length()
		var dv: float = Vector3(b[3] - a[3], b[4] - a[4], b[5] - a[5]).length()
		if dv > worst_v:
			worst_name = key
		worst_u = maxf(worst_u, du)
		worst_v = maxf(worst_v, dv)
	return {"du": worst_u, "dv": worst_v, "worst": worst_name, "count": before.size(),
			"sum_u": Vector3(sums[0], sums[1], sums[2]).length(), "sum_v": Vector3(sums[3], sums[4], sums[5]).length()}


func test_a_forced_boost_leaves_every_universe_position_and_velocity_as_it_was() -> void:
	await _populate()
	assert_true(far.ship.is_tier_parked() and far_cap.is_tier_parked(), "the far ship and capital are tier rows")
	var before: Dictionary = _movers()
	var still: Dictionary = _anchored()
	assert_true(before.has("tier ship") and before.has("tier capital") and before.has("bolt row 2"), "rows are in the sample")
	assert_gt(shards.size(), 0, "debris flies")
	var version: int = w.sim.core.rows_version()
	world.apply_boost(DV)
	assert_eq(world.boosts, 1)
	assert_false(world.riding(), "the frame is off its anchor")
	assert_eq(world.origin_velocity, PackedFloat64Array([DV.x, DV.y, DV.z]))
	assert_eq(world.rest_velocity(), -DV, "the anchor's velocity in the local frame")
	assert_gt(w.sim.core.rows_version(), version, "the rows count as moved, so a think across the boost is declined")
	assert_almost_eq(near.ship.linear_velocity, Vector3(-20.0, 0.0, 60.0) - DV, Vector3.ONE * VELOCITY_TOL)
	var change: Dictionary = _change(before, _movers())
	var held: Dictionary = _change(still, _anchored())
	gut.p("boost %s over %d movers: universe position moved by at most %.9f m, universe velocity by %.6f m/s (%s); sums moved by %.9f m and %.6f m/s; cost %d us" % [
			DV, change["count"], change["du"], change["dv"], change["worst"], change["sum_u"], change["sum_v"], world.last_boost_us])
	assert_gte(int(change["count"]), 20, "ships, rows, bolts, debris, a wreck, an explosion, an emitter and a flash")
	assert_eq(float(change["du"]), 0.0, "a boost moves nothing")
	assert_lt(float(change["dv"]), VELOCITY_TOL, "every universe velocity kept (worst: %s)" % change["worst"])
	assert_lt(float(change["sum_v"]), VELOCITY_TOL * float(change["count"]), "and so is their sum")
	assert_eq(float(held["du"]), 0.0, "the buoy and the rocks have not moved yet")
	assert_lt(float(held["dv"]), VELOCITY_TOL, "and they still stand against the anchor")
	# The way back: the frame's velocity returns to every local velocity.
	world.apply_boost_to_anchor()
	assert_true(world.riding())
	assert_eq(world.boosts, 2)
	var back: Dictionary = _change(before, _movers())
	assert_eq(float(back["du"]), 0.0)
	assert_lt(float(back["dv"]), 2.0 * VELOCITY_TOL, "back on the anchor with the velocities it left with (worst: %s)" % back["worst"])
	await _ticks(1)
	assert_eq(world.origin_velocity, PackedFloat64Array([0.0, 0.0, 0.0]), "at rest against the anchor after the tick")


func test_off_the_anchor_everything_flies_on_and_the_anchored_things_stay_with_the_anchor() -> void:
	await _populate()
	var start: Dictionary = _movers()
	var still: Dictionary = _anchored()
	var origin_at_start: UniversePos = world.origin
	var rock_body_before: Vector3 = (PhysicsServer3D.body_get_state(field._bodies[0], PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D).origin
	world.apply_boost(DV)
	var ticks: int = 30
	await _ticks(ticks)
	var t: float = float(ticks) / float(Engine.physics_ticks_per_second)
	var flown: Vector3 = origin_at_start.offset_to(world.origin)
	assert_almost_eq(flown, DV * t, Vector3.ONE * 0.01, "the local origin flew on at the frame's velocity")
	var now: Dictionary = _movers()
	# Whatever coasts must be where its universe velocity puts it: the frame's motion and its own add up to what it had.
	for key: String in ["player", "bolt row 0", "bolt row 2", "bolt node", "shard 0", "explosion"]:
		var a: PackedFloat64Array = start[key]
		var b: PackedFloat64Array = now[key]
		var expected := Vector3(a[3], a[4], a[5]) * t
		var moved := Vector3(b[0] - a[0], b[1] - a[1], b[2] - a[2])
		assert_lt(moved.distance_to(expected), 0.05, "%s coasted %s, its universe velocity gives %s" % [key, moved, expected])
	var held: Dictionary = _change(still, _anchored())
	assert_almost_eq(Vector3(now["player"][3], now["player"][4], now["player"][5]), Vector3(30.0, 5.0, -120.0),
			Vector3.ONE * VELOCITY_TOL, "the player kept its universe velocity")
	# The buoy drifts at 2 m/s against the anchor; the rocks do not move at all.
	var buoy_before: PackedFloat64Array = still["buoy"]
	var buoy_now: PackedFloat64Array = _anchored()["buoy"]
	assert_almost_eq(Vector3(buoy_now[0] - buoy_before[0], buoy_now[1] - buoy_before[1], buoy_now[2] - buoy_before[2]),
			Vector3(2.0, 0.0, 0.0) * t, Vector3.ONE * 0.01, "the buoy stayed with the anchor, at its own 2 m/s")
	for key: String in ["rock 0", "rock 1", "rock field"]:
		var a: PackedFloat64Array = still[key]
		var b: PackedFloat64Array = _anchored()[key]
		assert_lt(Vector3(b[0] - a[0], b[1] - a[1], b[2] - a[2]).length(), 0.01, "%s stayed where it is in the universe" % key)
	assert_lt(float(held["dv"]), VELOCITY_TOL)
	var rock_body_now: Vector3 = (PhysicsServer3D.body_get_state(field._bodies[0], PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D).origin
	assert_almost_eq(rock_body_now - rock_body_before, -DV * t, Vector3.ONE * 0.05, "the rock's body moved with its row")
	assert_lt(buoy.global_position.distance_to(Vector3(900.0, -100.0, 300.0) - DV * t), 5.0, "in local terms the buoy fell behind")


func test_a_boost_in_the_middle_of_a_gentle_touch_is_no_ram() -> void:
	# Two Starfuries nose to nose closing at 4 m/s: no damage. A 2 000 m/s boost while the contact is being measured would
	# read as a lethal change of velocity if the tracker kept the old frame's velocities.
	var other: Combatant = ShipAssembly.build(load(STARFURY_SPEC) as ShipSpec, world, w.projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: "OTHER",
	})
	world.spawn(other.ship, world.to_universe(Vector3(0.0, 0.0, -12.0)), Basis(Vector3.UP, PI))
	other.ship.assist_on = false
	other.ship.linear_velocity = Vector3(0.0, 0.0, 2.0)
	w.player.ship.assist_on = false
	w.player.damageable.invulnerable = false
	w.player.ship.linear_velocity = Vector3(0.0, 0.0, -2.0)
	var infos: Array[HitInfo] = []
	rams.ram_resolved.connect(func(info: HitInfo) -> void: infos.append(info))
	var boosted_at: int = -1
	var windows_at_boost: int = 0
	for tick: int in 400:
		await _ticks(1)
		if boosted_at < 0 and int(rams.tracker.open_windows()) > 0:
			windows_at_boost = int(rams.tracker.open_windows())
			world.apply_boost(Vector3(0.0, 300.0, 2000.0))
			boosted_at = tick
		if boosted_at >= 0 and tick > boosted_at + 20:
			break
	assert_gt(boosted_at, 0, "the hulls touched and a contact window was open (%d) when the boost fell" % windows_at_boost)
	assert_eq(infos.size(), 0, "no ram: %s" % [infos.map(func(i: HitInfo) -> float: return i.damage)])
	assert_eq(w.player.damageable.hull.fraction(), 1.0)
	assert_eq(other.damageable.hull.fraction(), 1.0)


func test_the_automatic_boost_fires_at_the_threshold_and_returns_under_half_of_it() -> void:
	var ship: Ship = w.player.ship
	ship.assist_on = false
	world.focus = ship
	world.auto_boost_speed_mps = 2000.0
	ship.linear_velocity = Vector3(0.0, 0.0, -1990.0)
	await _ticks(3)
	assert_eq(world.boosts, 0, "under the threshold the frame rides its anchor")
	assert_true(world.riding())
	var before: UniversePos = world.to_universe(ship.global_position)
	ship.linear_velocity = Vector3(0.0, 0.0, -2010.0)
	await _ticks(2)  # resumes at the start of a tick: the one before it ran the rule and took the boost at its end
	assert_eq(world.boosts, 1, "over it, the frame boosts onto the focus")
	assert_false(world.riding())
	assert_eq(ship.linear_velocity, Vector3.ZERO, "the focus is at rest in the frame")
	assert_almost_eq(world.origin_velocity[2], -2010.0, 1e-9)
	await _ticks(4)
	assert_eq(world.boosts, 1, "and stays there")
	var flown: Vector3 = before.offset_to(world.to_universe(ship.global_position))
	assert_almost_eq(flown, Vector3(0.0, 0.0, -2010.0) * 6.0 / 60.0, Vector3.ONE * 0.01, "the ship flew on at 2 010 m/s through the boost")
	# 1 100 m/s against the anchor: still over half the threshold.
	ship.linear_velocity = Vector3(0.0, 0.0, 910.0)
	await _ticks(2)
	assert_eq(world.boosts, 1)
	# 990 m/s against the anchor: back onto it.
	ship.linear_velocity = Vector3(0.0, 0.0, 1020.0)
	await _ticks(2)
	assert_eq(world.boosts, 2, "under half the threshold against the anchor, the frame boosts back")
	assert_true(world.riding())
	assert_almost_eq(ship.linear_velocity, Vector3(0.0, 0.0, -990.0), Vector3.ONE * VELOCITY_TOL)
	assert_eq(world.origin_velocity, PackedFloat64Array([0.0, 0.0, 0.0]))
	var origin_then: UniversePos = world.origin
	await _ticks(3)
	assert_eq(world.origin.distance_to(origin_then), 0.0, "riding again: the origin stays")
	assert_eq(world.boosts, 2)


func test_a_position_rebase_and_a_boost_in_one_tick_leave_the_ship_on_its_path() -> void:
	var ship: Ship = w.player.ship
	ship.assist_on = false
	world.focus = ship
	world.auto_boost_speed_mps = 2000.0
	world.auto_rebase_distance_m = 40.0
	await _ticks(1)
	var rebases: int = world.rebases
	# 45 m out and over the threshold at the start of a tick: the World's slot finds both to do.
	ship.global_position = Vector3(0.0, 0.0, -45.0)
	ship.linear_velocity = Vector3(0.0, 300.0, -2400.0)
	var before: UniversePos = world.to_universe(ship.global_position)
	await _ticks(1)
	assert_gt(world.rebases, rebases, "the position rebase fell")
	assert_eq(world.boosts, 1, "and the velocity rebase with it")
	await _ticks(5)
	var flown: Vector3 = before.offset_to(world.to_universe(ship.global_position))
	assert_almost_eq(flown, Vector3(0.0, 300.0, -2400.0) * 6.0 / 60.0, Vector3.ONE * 0.01, "six ticks of its own motion, no jump")
	assert_lt(ship.global_position.length(), 40.0 + 1.0, "near the local origin")
	assert_lt(ship.linear_velocity.length(), 1.0, "and slow in the frame")


func test_a_body_parked_for_the_tier_settles_the_boosts_it_sat_out() -> void:
	await _populate()
	var cruise_before: Vector3 = far_cap.cruise_velocity
	world.apply_boost(DV)
	Settings.set_value(&"tier_radius_m", 40000.0)  # everything near: the rows hand their state back
	await _ticks(4)
	assert_false(far.ship.is_tier_parked() or far_cap.is_tier_parked(), "both promoted")
	assert_almost_eq(far.ship.linear_velocity + DV, Vector3(10.0, -4.0, 25.0), Vector3.ONE * 0.5, "the ship came back in the frame of now")
	assert_almost_eq(far_cap.cruise_velocity + DV, cruise_before, Vector3.ONE * VELOCITY_TOL, "the capital still cruises at what it held against the anchor")
	assert_almost_eq(far_cap.linear_velocity + DV, cruise_before, Vector3.ONE * 1.0)
	assert_almost_eq(cap.cruise_velocity + DV, Vector3(0.0, 0.0, -30.0), Vector3.ONE * VELOCITY_TOL, "and so does the one that was never parked")


func test_with_the_core_gone_a_tiered_ship_comes_back_with_the_boost_taken_off_its_velocity() -> void:
	far = w.pool.acquire("ORPHAN", world.to_universe(FAR), Basis.IDENTITY, Vector3(10.0, -4.0, 25.0), IdleBrain.new())
	await _ticks(4)
	assert_true(far.ship.is_tier_parked(), "a tier row")
	world.apply_boost(DV)
	assert_eq(far.ship.linear_velocity, Vector3(10.0, -4.0, 25.0), "the parked body sat the boost out")
	await _ticks(1)
	w.sim.get_parent().remove_child(w.sim)
	w.sim.free()  # the rows are lost with the core
	await _ticks(2)
	assert_false(far.ship.is_tier_parked(), "promoted when the core went")
	assert_almost_eq(far.ship.linear_velocity, Vector3(10.0, -4.0, 25.0) - DV, Vector3.ONE * VELOCITY_TOL,
			"back with the velocity it was parked with, in the frame of now")


func test_off_its_anchor_in_orbit_the_frame_falls_at_its_own_origin() -> void:
	var system: StarSystem = FreeFall.fixture_system()
	assert_true(world.anchor_on_rail(system, &"post"))
	world.rebase(Vector3(20000.0, 3000.0, -1000.0))  # 20 km from the anchor: the tide is felt at the local origin
	await _ticks(1)
	assert_true(world.gravity_active())
	var tide: Vector3 = world.gravity_residual(Vector3.ZERO)
	assert_gt(tide.length(), 0.01, "riding, the local origin feels the pull against the anchor's")
	var probe := Vector3(1000.0, 0.0, 0.0)
	var probe_riding: Vector3 = world.gravity_residual(probe)
	world.apply_boost(Vector3(0.0, 0.0, -500.0))
	await _ticks(1)
	world.sample_gravity(SimClock.now())  # the tick's sample, which this test reads ahead of
	assert_eq(world.gravity_residual(Vector3.ZERO), Vector3.ZERO, "off the anchor it falls with its own origin")
	assert_almost_eq(world.gravity_residual(probe), probe_riding - tide, Vector3.ONE * 1e-4,
			"and a mover feels the pull at its place less the origin's")
	var falling: PackedFloat64Array = world.origin_velocity
	assert_gt(Vector3(falling[0], falling[1], falling[2] + 500.0).length(), 0.5 * tide.length() / 60.0, "the frame's own velocity takes that pull")
	assert_true(_exec("ride").ok)
	await _ticks(2)
	assert_eq(world.origin_velocity, PackedFloat64Array([0.0, 0.0, 0.0]), "back on the anchor, exactly at rest")
	assert_almost_eq(world.gravity_residual(Vector3.ZERO).length(), tide.length(), 0.01, "and riding again")
	world.clear_anchor()


func test_a_boost_asked_for_is_taken_at_the_end_of_the_tick_so_bolts_and_bodies_change_frames_together() -> void:
	# A bolt row and a bolt node step themselves inside the tick, the ship in Jolt's step after it. Asked for at the start of
	# a tick, the boost must leave all three on their universe paths to the millimetre, tick by tick.
	var ship: Ship = w.player.ship
	ship.assist_on = false
	ship.linear_velocity = Vector3(0.0, 0.0, -100.0)
	await _ticks(2)
	var now_s: float = SimClock.now()
	w.sim.add_bolt(Vector3(0.0, 30.0, 0.0), Vector3(0.0, 0.0, -900.0), Factions.RAIDERS, 0, w.player.cannon.weapon, now_s)
	bolt = PulseCannon.PROJECTILE_SCENE.instantiate() as Projectile
	bolt.lifetime_s = 30.0
	w.projectiles.add_child(bolt)
	bolt.launch(Vector3(0.0, -30.0, 0.0), Vector3(0.0, 0.0, -900.0), now_s)
	await _ticks(2)
	var sampler := LateSampler.new()
	sampler.read = func() -> Array[UniversePos]:
		var columns: Array = w.sim.core.bolt_columns()
		return [world.to_universe(ship.global_position), world.to_universe(bolt.global_position),
				world.to_universe((columns[2] as PackedVector3Array)[0])]
	w.space.add_child(sampler)
	await _ticks(4)
	world.boost(Vector3(0.0, 300.0, -2000.0))
	assert_eq(world.boosts, 0, "asked for, not taken yet")
	await _ticks(5)
	world.boost_to_anchor()
	await _ticks(4)
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var speeds: Array[float] = [100.0, 900.0, 900.0]
	var worst: float = 0.0
	for n: int in range(1, sampler.rows.size()):
		for k: int in 3:
			worst = maxf(worst, absf(sampler.rows[n - 1][k].distance_to(sampler.rows[n][k]) - speeds[k] * dt))
	assert_gte(sampler.rows.size(), 12)
	assert_eq(world.boosts, 2, "the boost and the way back were taken")
	assert_true(world.riding())
	assert_lt(worst, 0.002, "the ship, the bolt node and the bolt row each flew its own speed every tick (worst off by %.4f m)" % worst)


func test_the_console_boosts_and_the_provider_reads_the_frame() -> void:
	var registry: ConsoleRegistry = DebugConsole.registry
	var result: ConsoleResult = _console("boost 100 0 -250")
	assert_true(result.ok, result.error)
	assert_eq(world.boosts, 0, "asked for: taken when the tick ends")
	await _ticks(2)
	assert_eq(registry.format_path("world.origin_velocity"), "world.origin_velocity = [100.00, 0.00, -250.00] m/s")
	assert_eq(registry.read("world.boosts")["value"], 1)
	assert_eq(registry.read("world.riding")["value"], false)
	assert_true(registry.read("world.boost_us")["ok"])
	assert_eq(registry.read("world.auto_boost_speed_mps")["value"], 0.0, "a bare World never boosts by itself")
	assert_true(_console("ride").ok)
	await _ticks(2)
	assert_eq(registry.read("world.riding")["value"], true)
	assert_true(_console("boost 0 0 0").ok, "nothing to do is not an error")
	await _ticks(2)
	assert_eq(world.boosts, 2)
