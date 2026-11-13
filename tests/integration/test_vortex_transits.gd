extends GutTest
## Ships through a jump vortex's funnel (M6-T22, `VortexTransits`), headless: a ship arriving out of a ship-made point starts at
## its black ring, shrunk, in a flash, and flies out growing to its whole size at the mouth; one departing down a point shrinks
## to the ring, flashes and is handed back whole; the same through the gate, which stays open until its last ship is through.
## The ship's AI pilot is held for the passage.

const RAIDER_SPEC: String = "res://assets/ships/raider_delta_v.tres"
const DT: float = 1.0 / 60.0

var world: WorldFrame
var raider: Combatant
var brain: FullThrottleBrain
var pool: JumpPointPool
var transits: VortexTransits


## A pilot that would fly off at full thrust if it were let think: proof the passage holds it.
class FullThrottleBrain extends PilotBrain:
	var thinks: int = 0

	func think(_p: Perception, _dt: float) -> PilotCommand:
		thinks += 1
		var cmd := PilotCommand.new()
		cmd.flight.main_left = 1.0
		cmd.flight.main_right = 1.0
		cmd.flight.strafe = Vector2(1.0, 0.0)
		return cmd


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
	world.spawn(raider.ship, world.to_universe(Vector3.ZERO))
	brain = FullThrottleBrain.new()
	raider.driver.brain = brain
	pool = JumpPointPool.new()
	pool.world = world
	world.add_child(pool)
	pool.prepare(2)
	transits = VortexTransits.attach(world)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _local(vortex: JumpVortex) -> Vector3:
	return vortex.true_frame().affine_inverse() * raider.ship.global_position


# The ship placed at `at` (World), nose along `heading`, flying `velocity`.
func _place(at: Vector3, heading: Vector3, velocity: Vector3) -> void:
	raider.ship.reset_to(Transform3D(Basis.looking_at(heading, Vector3.UP), at))
	raider.ship.linear_velocity = velocity


# Flies the passage out, at most `limit_s`; returns [seconds, scales seen, depths seen].
func _fly_out(vortex: JumpVortex, limit_s: float) -> Array:
	var scales := PackedFloat32Array()
	var depths := PackedFloat32Array()
	var ticks: int = 0
	while transits.is_passing(raider.ship) and ticks < roundi(limit_s / DT):
		await _frames(1)
		ticks += 1
		scales.append(transits.scale_of(raider.ship))
		depths.append(_local(vortex).z)
	return [ticks * DT, scales, depths]


func test_a_ship_comes_out_of_a_point_shrunk_and_grows_to_its_whole_size_at_the_mouth() -> void:
	var exit_at := Vector3(0.0, 0.0, -500.0)
	var exit_velocity := Vector3(0.0, 0.0, -100.0)
	_place(exit_at, Vector3.FORWARD, exit_velocity)
	await _frames(1)
	var point: JumpVortex = pool.open_for(world.to_universe(exit_at), Vector3.FORWARD, raider.ship.bounding_radius())
	assert_true(transits.begin_arrival(raider.ship, point, exit_at, exit_velocity))
	brain.thinks = 0  # what it thought before the passage
	var start: Vector3 = _local(point)
	assert_almost_eq(start.z, point.fit.depth_m, 0.5, "it waits on the funnel's base")
	assert_lt(Vector2(start.x, start.y).length(), VortexTransit.ring_radius_m(point.fit), "inside the black ring")
	assert_eq(transits.scale_of(raider.ship), VortexTransit.HELD_SCALE, "as good as gone through the point's opening flash")
	assert_eq(transits.flash_count(), 0)
	var waited: int = 0
	while point.age_s < VortexTransit.emerge_age_s(0.0) and waited < 300:
		await _frames(1)
		waited += 1
	await _frames(1)
	assert_almost_eq(_local(point).z, point.fit.depth_m, 10.0, "then comes out at the ring")
	var ring: float = transits.scale_of(raider.ship)
	assert_almost_eq(ring, VortexTransit.ring_scale(point.fit, VortexTransit.lateral_radius(raider.damageable.ram_bounds)), 1e-4,
			"shrunk to the ring")
	assert_lt(ring, 0.5)
	assert_eq(transits.flash_count(), 1, "out of a white flash at the ring")
	assert_true(raider.driver.in_passage, "its pilot is held")
	var flown: Array = await _fly_out(point, 10.0)
	var seconds: float = flown[0]
	var scales: PackedFloat32Array = flown[1]
	var depths: PackedFloat32Array = flown[2]
	assert_false(transits.is_passing(raider.ship), "out of the funnel")
	assert_between(seconds, VortexTransit.MIN_TRANSIT_S * 0.9, VortexTransit.MAX_TRANSIT_S + 0.5, "a passage that reads")
	for i: int in range(1, scales.size()):
		assert_true(scales[i] >= scales[i - 1] - 1e-5, "it only grows on the way out")
		assert_true(depths[i] <= depths[i - 1] + 1e-3, "and only comes out")
	assert_eq(transits.scale_of(raider.ship), 1.0)
	assert_eq(raider.damageable.hull_scale, 1.0, "its hit volumes are whole")
	assert_lt(_local(point).z, 0.5, "at the mouth")
	assert_lt(raider.ship.linear_velocity.distance_to(exit_velocity), 1.0, "leaving with its spawn's velocity")
	assert_eq(brain.thinks, 0, "its pilot did not fly it through the funnel")
	assert_false(raider.driver.in_passage, "and has it back")
	assert_eq(transits.arrivals_done, 1)
	await _frames(30)
	assert_gt(brain.thinks, 0, "it thinks again")


func test_a_ship_departing_down_a_point_shrinks_to_the_ring_flashes_and_is_handed_back_whole() -> void:
	var mouth := Vector3(0.0, 0.0, -300.0)
	var point: JumpVortex = pool.open_with(Transform3D(Basis.IDENTITY, mouth), VortexFit.for_ship(raider.ship.bounding_radius()),
			JumpVortex.Direction.DEPARTURE)
	_place(mouth, Vector3.BACK, Vector3(0.0, 0.0, 60.0))
	var through: Array[Node] = []
	var smallest: Array[float] = [1.0]
	assert_true(transits.begin_departure(raider.ship, point, func(body: Node3D) -> void:
		through.append(body)
		smallest[0] = minf(smallest[0], raider.damageable.hull_scale)))
	var least: float = 1.0
	var ticks: int = 0
	while through.is_empty() and ticks < 600:
		await _frames(1)
		ticks += 1
		least = minf(least, transits.scale_of(raider.ship))
	assert_eq(through.size(), 1, "handed back once its nose touched the base")
	assert_lt(least, 0.5, "it shrank on the way down")
	assert_almost_eq(least, VortexTransit.RING_SHARE, 0.1, "about to the ring's share")
	assert_eq(smallest[0], 1.0, "whole again when handed back")
	assert_eq(transits.flashes_shown, 1, "a white flash at the ring")
	assert_eq(brain.thinks, 0, "its pilot was held")
	assert_eq(point.passing, 0)


func test_through_the_gate_in_and_out_the_vortex_held_open_for_the_last_ship() -> void:
	var gate: Jumpgate = Jumpgate.create("JUMPGATE")
	world.spawn(gate, world.to_universe(Vector3(0.0, 0.0, -6000.0)))
	await _frames(2)
	assert_true(gate.open_vortex(JumpVortex.Direction.ARRIVAL))
	while not gate.vortex.is_open_for(JumpVortex.Direction.ARRIVAL):
		await _frames(1)
	var offset := Vector3(40.0, 0.0, 0.0)
	var xform: Transform3D = gate.arrival_transform(offset)
	raider.ship.reset_to(xform)
	raider.ship.linear_velocity = gate.arrival_velocity()
	gate.bring_through(raider.ship)
	var at: Vector3 = gate.local_of(raider.ship.global_position)
	assert_almost_eq(at.z, gate.fit.depth_m, 1.0, "out of the gate's ring, 1 200 m behind its mouth")
	assert_almost_eq(at.x, offset.x * VortexTransit.RING_SHARE, 0.5, "its place shrunk to the ring")
	assert_almost_eq(transits.scale_of(raider.ship), VortexTransit.RING_SHARE, 1e-3, "a fighter keeps its share of the funnel")
	var flown: Array = await _fly_out(gate.vortex, 12.0)
	assert_false(transits.is_passing(raider.ship))
	assert_gt(float(flown[0]), VortexTiming.DEFAULT_HOLD_S, "longer than the vortex's own hold")
	assert_true(gate.vortex.is_open_for(JumpVortex.Direction.ARRIVAL), "the vortex was kept open until it was through")
	var out: Vector3 = gate.local_of(raider.ship.global_position)
	assert_lt(out.z, 1.0, "out of the mouth")
	assert_almost_eq(out.x, offset.x, 2.0, "at its place")
	assert_eq(transits.scale_of(raider.ship), 1.0)
	# Out again: the departure open, the ship flying in from 300 m in front of the mouth.
	while gate.vortex.is_active():
		await _frames(1)
	assert_true(gate.open_vortex(JumpVortex.Direction.DEPARTURE, 1.0))
	while not gate.vortex.is_open_for(JumpVortex.Direction.DEPARTURE):
		await _frames(1)
	var in_dir: Vector3 = gate.global_basis * gate.departure_forward
	_place(gate.global_transform * Vector3(0.0, 0.0, -300.0), in_dir, in_dir * 200.0)
	var handed: Array[int] = [0]
	gate.send_departure(raider.ship, func(_ship: Node3D) -> void: handed[0] += 1)
	var least: float = 1.0
	for i: int in 12 * 60:
		await _frames(1)
		least = minf(least, transits.scale_of(raider.ship))
		if handed[0] > 0:
			break
	assert_eq(handed[0], 1, "handed back at the ring")
	assert_eq(gate.departed, 1)
	assert_lt(least, 0.3, "shrunk on its way down")
	assert_gt(gate.local_of(raider.ship.global_position).z, gate.fit.depth_m * 0.9, "at the base, 1 200 m in")
	assert_eq(raider.damageable.hull_scale, 1.0, "whole when handed back")
	await _frames(2)
	assert_ne(gate.vortex.phase_name(), "open", "the gate closes once its last ship is through")
