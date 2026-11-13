extends GutTest
## A ship scaled in a jump vortex's funnel (M6-T22, `TransitScale`): Jolt collides with its shrunk shapes (a ship at half scale
## collides at its half-size shape), its hit volumes, bounds and the radius its marker and the core read follow, its mass,
## inertia and zero damping stay, and putting it back restores every transform exactly. Both kinds of ship: the lean AI ship
## (shapes as owners of the body) and the player's (a node per shape).

const RAIDER_SPEC: String = "res://assets/ships/raider_delta_v.tres"
const PLAYER_SPEC: String = "res://assets/ships/starfury_aurora.tres"

var world: WorldFrame
var projectiles: Node3D


func before_each() -> void:
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)


func _ship(spec_path: String, ai: bool, at: Vector3) -> Combatant:
	var made: Combatant = ShipAssembly.build(load(spec_path) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.RAIDERS if ai else Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: "SHIP %s" % spec_path.get_file(),
		ShipAssembly.OPT_AI: ai,
	})
	world.spawn(made.ship, world.to_universe(at))
	return made


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


# Whether Jolt finds the ship's body at World point `p`.
func _jolt_hits(ship: Ship, p: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = p
	q.collision_mask = 0xFFFFFFFF
	for hit: Dictionary in ship.get_world_3d().direct_space_state.intersect_point(q, 8):
		if hit["collider"] == ship:
			return true
	return false


# Whether any of `shapes` (body frame, scaled by `factor` about the origin) holds the body-frame point `p`.
static func _held(shapes: Array[HitShape], factor: float, p: Vector3) -> bool:
	for shape: HitShape in shapes:
		if shape.scaled(factor).contains(p):
			return true
	return false


# Points round the hull, body frame: along each hit volume's axes out past its full size.
static func _probes(shapes: Array[HitShape]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for shape: HitShape in shapes:
		var reach: Vector3 = shape.half_extents if shape.kind == HitShape.Kind.BOX \
				else Vector3(shape.radius, shape.half_segment + shape.radius, shape.radius)
		for axis: int in 3:
			for share: float in [0.2, 0.4, 0.6, 0.8, 0.95]:
				var d := Vector3.ZERO
				d[axis] = reach[axis] * share
				out.append(shape.transform * d)
	return out


func _check_collides_at(c: Combatant, factor: float) -> void:
	var ship: Ship = c.ship
	var base: Array[HitShape] = []
	for shape: HitShape in c.damageable.shapes:
		base.append(shape.scaled(1.0 / c.damageable.hull_scale))
	var probes: Array[Vector3] = _probes(base)
	var agree: int = 0
	var in_full_not_half: int = 0
	for p: Vector3 in probes:
		var expected: bool = _held(base, factor, p)
		if _jolt_hits(ship, ship.global_transform * p) == expected:
			agree += 1
		if _held(base, 1.0, p) and not expected:
			in_full_not_half += 1
			assert_false(_jolt_hits(ship, ship.global_transform * p), "a point of the whole hull outside the scaled one misses")
	if factor < 1.0:
		assert_gt(in_full_not_half, 3, "some probes lie between the two sizes")
	assert_gt(float(agree) / float(probes.size()), 0.97, "Jolt collides with the hull at %.2f of its size (%d of %d probes)" % [
			factor, agree, probes.size()])


func test_a_lean_ship_at_half_scale_collides_at_its_half_size_shape() -> void:
	var c: Combatant = _ship(RAIDER_SPEC, true, Vector3.ZERO)
	await _frames(2)
	var mass: float = c.ship.mass
	var inertia: Vector3 = c.ship.inertia
	var radius: float = c.damageable.bounding_radius
	var scaler := TransitScale.new(c.ship)
	scaler.apply(0.5)
	await _frames(2)
	_check_collides_at(c, 0.5)
	assert_almost_eq(c.damageable.bounding_radius, radius * 0.5, 1e-3, "the hit volumes' bound halves")
	assert_almost_eq(c.targetable.get_bounding_radius(), radius * 0.5, 1e-3, "the marker's size (the HUD's brackets) follows")
	assert_eq(c.ship.mass, mass, "the mass is kept")
	assert_eq(c.ship.inertia, inertia, "the inertia is kept")
	assert_eq(c.ship.linear_damp, 0.0)
	assert_eq(c.ship.linear_damp_mode, RigidBody3D.DAMP_MODE_REPLACE)
	scaler.restore()
	await _frames(2)
	_check_collides_at(c, 1.0)
	assert_almost_eq(c.damageable.bounding_radius, radius, 1e-6, "whole again")


func test_the_players_ship_scales_its_shape_nodes_and_meshes() -> void:
	var c: Combatant = _ship(PLAYER_SPEC, false, Vector3(200.0, 0.0, 0.0))
	await _frames(2)
	var hull_xform: Transform3D = c.ship.hull.transform
	var scaler := TransitScale.new(c.ship)
	scaler.apply(0.5)
	await _frames(2)
	_check_collides_at(c, 0.5)
	assert_almost_eq(c.ship.hull.transform.basis.get_scale().x, 0.5, 1e-5, "the hull mesh is drawn at half size")
	assert_eq(c.ship.transform.basis.get_scale(), Vector3.ONE, "the body itself is never scaled")
	scaler.restore()
	assert_eq(c.ship.hull.transform, hull_xform, "put back exactly")


func test_the_meshes_follow_every_change_and_the_shapes_follow_in_steps() -> void:
	var c: Combatant = _ship(RAIDER_SPEC, true, Vector3.ZERO)
	await _frames(1)
	var scaler := TransitScale.new(c.ship)
	scaler.apply(0.99)
	assert_almost_eq(scaler.visual_scale, 0.99, 1e-6)
	assert_eq(scaler.collision_scale, 1.0, "a 1 % change waits for the next step")
	scaler.apply(0.7, false)
	assert_eq(scaler.collision_scale, 1.0, "nor while its turn has not come")
	scaler.apply(0.7)
	assert_almost_eq(scaler.collision_scale, 0.7, 1e-6, "past the step the shapes follow")
	assert_almost_eq(c.damageable.hull_scale, 0.7, 1e-6)
	scaler.apply(1.0)
	assert_eq(scaler.collision_scale, 1.0, "exactly whole at the end")


func test_a_bolt_misses_where_only_the_whole_hull_was() -> void:
	var c: Combatant = _ship(RAIDER_SPEC, true, Vector3.ZERO)
	await _frames(1)
	var whole: Array[HitShape] = c.damageable.shapes.duplicate()
	var target := Vector3.INF
	for p: Vector3 in _probes(whole):
		if _held(whole, 1.0, p) and not _held(whole, 0.25, p):
			target = p
			break
	assert_ne(target, Vector3.INF, "a point of the whole hull outside the quarter-size one")
	var a: Vector3 = target + Vector3(0.0, 0.0, -0.05)
	var b: Vector3 = target + Vector3(0.0, 0.0, 0.05)
	assert_true(_swept(c.damageable.shapes, a, b), "a bolt through it hits the whole hull")
	var scaler := TransitScale.new(c.ship)
	scaler.apply(0.25)
	assert_false(_swept(c.damageable.shapes, a, b), "the hit sweep sees the shrunk hull")
	scaler.restore()
	assert_true(_swept(c.damageable.shapes, a, b), "and the whole one again")


static func _swept(shapes: Array[HitShape], a: Vector3, b: Vector3) -> bool:
	for shape: HitShape in shapes:
		if shape.sweep(a, b) >= 0.0:
			return true
	return false
