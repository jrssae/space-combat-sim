extends TestSteps
## `RockBodies` (M6-T21): only the rocks a rigid hull could reach soon live as Jolt bodies; the rest are rows only, with no
## layer and no mask, and no rebase or drift moves them. A rock that comes back to life stands exactly where it would had it
## lived all along, and one a ship rests against stays live and in contact.

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const ROCK_LAYER: int = CollisionLayers.ROCK

var world: WorldFrame
var projectiles: Node3D


func before_each() -> void:
	StaticRows.clear()
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)


func after_each() -> void:
	StaticRows.clear()


func _fighter(at: Vector3) -> Combatant:
	var combatant: Combatant = ShipAssembly.build(load(SPEC_PATH) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.RAIDERS, ShipAssembly.OPT_DISPLAY_NAME: "B", ShipAssembly.OPT_LEAN: true})
	world.spawn(combatant.ship, world.to_universe(at), Basis.IDENTITY)
	return combatant


# A field at the local origin that follows the World's rebases and drift, as the stand-ins' field does.
func _field(rocks: Array[Dictionary]) -> AsteroidField:
	var field := AsteroidField.new()
	world.spawn(field, world.to_universe(Vector3.ZERO))
	field.add_to_group(WorldFrame.ANCHORED_GROUP)
	field.build(rocks, world.get_world_3d().space, world)
	world.rebased.connect(field.on_rebased)
	world.drifted.connect(field.on_rebased)
	return field


func _body_at(field: AsteroidField, i: int) -> Transform3D:
	return PhysicsServer3D.body_get_state(field.body_rids()[i], PhysicsServer3D.BODY_STATE_TRANSFORM)


func _layer(field: AsteroidField, i: int) -> int:
	return PhysicsServer3D.body_get_collision_layer(field.body_rids()[i])


func test_only_the_rocks_near_a_rigid_hull_live_and_the_rest_are_rows_with_no_layer() -> void:
	var field: AsteroidField = _field([{"offset": Vector3(0.0, 0.0, -60.0), "radius": 40.0},
			{"offset": Vector3(0.0, 0.0, -3000.0), "radius": 40.0}, {"offset": Vector3(2000.0, 0.0, 0.0), "radius": 90.0}])
	_fighter(Vector3.ZERO)
	await _ticks(2)
	assert_eq(StaticRows.solid().ids.size(), 3, "every rock is a row for the hit sweep, the rams and the scan")
	assert_true(field.rock_bodies().is_live(0), "the rock 20 m off the ship lives")
	assert_eq(_layer(field, 0), ROCK_LAYER)
	assert_eq(PhysicsServer3D.body_get_collision_mask(field.body_rids()[0]), CollisionLayers.mask_of(&"rock"))
	for i: int in [1, 2]:
		assert_false(field.rock_bodies().is_live(i), "rock %d, far from every ship, is a row only" % i)
		assert_eq(_layer(field, i), 0, "nothing touches it")
		assert_eq(PhysicsServer3D.body_get_collision_mask(field.body_rids()[i]), 0)
	assert_eq(field.rock_bodies().live_count(), 1)


func test_a_rock_that_comes_back_to_life_stands_exactly_where_it_would_had_it_lived_all_along() -> void:
	var field: AsteroidField = _field([{"offset": Vector3(0.0, 0.0, -60.0), "radius": 40.0},
			{"offset": Vector3(500.0, 0.0, -60.0), "radius": 40.0}])
	var roamer: Combatant = _fighter(Vector3.ZERO)
	_fighter(Vector3(500.0, 0.0, 0.0))  # keeps rock 1 alive all along: the control
	await _ticks(2)
	assert_true(field.rock_bodies().is_live(0) and field.rock_bodies().is_live(1))
	world.rebase(Vector3(1234.5, -20.25, 777.125))
	roamer.ship.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 6000.0)))  # far away: rock 0 goes dormant
	await _ticks(RockBodies.HOLD_TICKS - 1)
	assert_true(field.rock_bodies().is_live(0), "held a moment after its last hull left")
	await _ticks(3)
	assert_false(field.rock_bodies().is_live(0), "then demoted")
	var stale: Transform3D = _body_at(field, 0)
	world.rebase(Vector3(-4321.0, 3.5, -99.75))
	assert_eq(_body_at(field, 0), stale, "a rebase leaves a dormant body where it is: that is the saving")
	world.rebase(Vector3(17.0, 0.0, -2.0))
	roamer.ship.reset_to(Transform3D(Basis.IDENTITY, field.global_position + Vector3(0.0, 0.0, 10.0)))
	await _ticks(2)
	assert_true(field.rock_bodies().is_live(0), "promoted again")
	var placed: Transform3D = field.rock_bodies().placed(0, field.global_transform)
	assert_eq(_body_at(field, 0), placed, "where its owner puts it, to the bit")
	assert_eq(_body_at(field, 1), field.rock_bodies().placed(1, field.global_transform),
			"the same rule as the rock that lived all along")
	assert_almost_eq(_body_at(field, 0).origin.distance_to(StaticRows.position_of(field.row_id(0))), 0.0, 1e-3,
			"and its row agrees")


func test_a_ship_resting_against_a_rock_keeps_it_live_and_in_contact() -> void:
	var field: AsteroidField = _field([{"offset": Vector3(0.0, 0.0, -200.0), "radius": 40.0}])
	var ship: Combatant = _fighter(Vector3.ZERO)
	await _ticks(2)
	assert_false(field.rock_bodies().is_live(0), "160 m from the ship's centre: a row only")
	ship.ship.reset_to(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -100.0)))  # 60 m off the face, still a row only
	ship.ship.linear_velocity = Vector3(0.0, 0.0, -20.0)
	var touching_ticks: int = 0
	var dormant_while_near: int = 0
	for i: int in 300:
		await _ticks(1)
		var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(ship.ship.get_rid())
		if state != null and state.get_contact_count() > 0:
			touching_ticks += 1
		# Within 15 m of the rock's face (the nose is about 4 m out): it must live by then.
		if ship.ship.global_position.distance_to(Vector3(0.0, 0.0, -200.0)) < 55.0 and not field.rock_bodies().is_live(0):
			dormant_while_near += 1
	assert_gt(touching_ticks, 0, "Jolt paired the ship with the rock's body")
	assert_gt(ship.ship.linear_velocity.z, -5.0, "and the rock stopped it")
	assert_eq(dormant_while_near, 0, "never dormant while the ship was near it")


func test_off_the_anchor_a_live_rock_follows_the_drift_and_a_dormant_one_does_not_move() -> void:
	var field: AsteroidField = _field([{"offset": Vector3(0.0, 0.0, -60.0), "radius": 40.0},
			{"offset": Vector3(3000.0, 0.0, 0.0), "radius": 40.0}])
	var ship: Combatant = _fighter(Vector3.ZERO)
	await _ticks(2)
	var far_body: Transform3D = _body_at(field, 1)
	world.boost(Vector3(0.0, 0.0, 30.0))  # the frame flies off its anchor: the field drifts, the ship keeps its motion
	await _ticks(30)
	assert_false(world.riding())
	assert_gt(field.global_position.length(), 10.0, "the field drifted with the anchor")
	assert_true(field.rock_bodies().is_live(0), "the ship flies with the rocks: still near")
	assert_eq(_body_at(field, 0), field.rock_bodies().placed(0, field.global_transform), "the live body followed the drift")
	assert_eq(_body_at(field, 1), far_body, "the dormant one stayed put")
	assert_lt(ship.ship.global_position.distance_to(_body_at(field, 0).origin), 80.0, "and the ship is still beside its rock")
