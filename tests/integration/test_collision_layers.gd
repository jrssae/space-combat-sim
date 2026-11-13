extends TestSteps
## Jolt collision layers and the far ships' interpolation (M4-T14, architecture §17.12). Every kind of body pairs with whatever can
## hit it, AI fighters with each other too (Q33: contacts and rams as on the base); rocks never pair with rocks; a bolt and a mine
## have no body; a rebase's interpolation reset skips the nodes that are not interpolated, which a far dot's ship is not.

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const RAIDER_SPEC_PATH: String = "res://assets/ships/raider_delta_v.tres"
const FACING := Basis(Vector3.UP, PI)
const SLOW_GAP_M: float = 12.0

var world: WorldFrame
var projectiles: Node3D
var rams: RamResolver
var infos: Array[HitInfo] = []
var _saved: Dictionary = {}
var _contacts_seen: int = 0


class ContactCounter extends Node:
	var bodies: Array[RigidBody3D] = []
	var total: int = 0

	func _init() -> void:
		process_physics_priority = 205  # after the ships' step of the last tick, before the ram resolver

	func _physics_process(_delta: float) -> void:
		for body: RigidBody3D in bodies:
			var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(body.get_rid())
			if state != null:
				total += state.get_contact_count()


func before_each() -> void:
	for key: StringName in [&"ram_damage"]:
		_saved[key] = Settings.get_value(key)
		Settings.reset(key)
	Settings.set_value(&"ram_damage", true)
	DebugConsole.flags.invulnerable = false
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	rams = RamResolver.new()
	rams.name = "RamResolver"
	rams.world = world
	add_child_autofree(rams)
	infos.clear()
	rams.ram_resolved.connect(func(info: HitInfo) -> void: infos.append(info))


func after_each() -> void:
	for key: StringName in _saved:
		Settings.set_value(key, _saved[key])
	StaticRows.clear()


func _fighter(display: String, faction: StringName, at: Vector3, player: bool = false) -> Combatant:
	var combatant: Combatant = ShipAssembly.build(load(SPEC_PATH) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: faction,
		ShipAssembly.OPT_DISPLAY_NAME: display,
		ShipAssembly.OPT_IS_PLAYER: player,
		ShipAssembly.OPT_LEAN: not player,
	})
	world.spawn(combatant.ship, world.to_universe(at), Basis.IDENTITY)
	return combatant


func _place(combatant: Combatant, position: Vector3, basis: Basis, velocity: Vector3) -> void:
	combatant.ship.reset_to(Transform3D(basis, position))
	combatant.ship.linear_velocity = velocity


## Two fighters nose to nose `gap` m apart, closing at `closing` m/s.
func _head_on(a: Combatant, b: Combatant, closing: float, gap: float = SLOW_GAP_M) -> void:
	_place(a, Vector3.ZERO, Basis.IDENTITY, Vector3(0.0, 0.0, -0.5 * closing))
	_place(b, Vector3(0.0, 0.0, -gap), FACING, Vector3(0.0, 0.0, 0.5 * closing))


func _counter(a: Combatant, b: Combatant) -> ContactCounter:
	var counter := ContactCounter.new()
	counter.bodies = [a.ship, b.ship]
	add_child_autofree(counter)
	return counter


# --- the table -----------------------------------------------------------------------------------------------------


func test_the_table_pairs_everything_but_rocks_with_rocks() -> void:
	var kinds: Array[StringName] = [&"player", &"fighter", &"capital", &"rock"]
	var expected: Dictionary = {
		"player player": true, "player fighter": true, "player capital": true, "player rock": true,
		"fighter fighter": true, "fighter capital": true, "fighter rock": true,
		"capital capital": true, "capital rock": true,
		"rock rock": false,
	}
	for a: StringName in kinds:
		for b: StringName in kinds:
			var key: String = "%s %s" % [a, b]
			var flip: String = "%s %s" % [b, a]
			var want: bool = expected.get(key, expected.get(flip, false))
			assert_eq(CollisionLayers.collide(CollisionLayers.layer_of(a), CollisionLayers.mask_of(a),
					CollisionLayers.layer_of(b), CollisionLayers.mask_of(b)), want, key)


func test_a_pair_collides_when_either_masks_the_others_layer() -> void:
	assert_true(CollisionLayers.collide(1, 2, 2, 0), "a's mask holds b's layer")
	assert_true(CollisionLayers.collide(1, 0, 2, 1), "b's mask holds a's layer")
	assert_false(CollisionLayers.collide(1, 4, 2, 8), "neither does")


func test_each_kind_of_body_gets_its_layer_and_mask() -> void:
	var player: Combatant = _fighter("PLAYER", Factions.EARTH_ALLIANCE, Vector3.ZERO, true)
	var ai: Combatant = _fighter("AI", Factions.RAIDERS, Vector3(0.0, 0.0, -500.0))
	await _ticks(2)
	assert_eq(player.ship.collision_layer, CollisionLayers.layer_of(&"player"), "a ship that is not lean is the player's kind")
	assert_eq(player.ship.collision_mask, CollisionLayers.mask_of(&"player"))
	assert_eq(ai.ship.collision_layer, CollisionLayers.layer_of(&"fighter"))
	assert_eq(ai.ship.collision_mask, CollisionLayers.mask_of(&"fighter"))
	var cap: CapitalStandin = CapitalStandin.create(&"cruiser", Factions.RAIDERS, "CAP", Vector3.ZERO)
	cap.world = world
	world.spawn(cap, world.to_universe(Vector3(0.0, 0.0, -3000.0)))
	assert_eq(cap.collision_layer, CollisionLayers.layer_of(&"capital"))
	assert_eq(cap.collision_mask, CollisionLayers.mask_of(&"capital"))
	# A rock lives as a body only near a ship (M6-T21): the one 20 m off the fighter's centre, not the one 5.5 km out.
	var field := AsteroidField.new()
	world.spawn(field, world.to_universe(Vector3(0.0, 0.0, -6000.0)))
	field.build([{"offset": Vector3.ZERO, "radius": 50.0}, {"offset": Vector3(0.0, 0.0, 5430.0), "radius": 50.0}] \
			as Array[Dictionary], world.get_world_3d().space, world)
	await _ticks(1)
	var near: RID = field.body_rids()[1]
	assert_eq(PhysicsServer3D.body_get_collision_layer(near), CollisionLayers.layer_of(&"rock"))
	assert_eq(PhysicsServer3D.body_get_collision_mask(near), CollisionLayers.mask_of(&"rock"))
	var far: RID = field.body_rids()[0]
	assert_eq(PhysicsServer3D.body_get_collision_layer(far), 0, "a dormant rock: nothing touches it")
	assert_eq(PhysicsServer3D.body_get_collision_mask(far), 0)


# --- fighters meeting (Q33: they collide in Jolt, as on the base) ---------------------------------------------------


func test_two_fighters_meeting_report_a_jolt_contact_and_exchange_momentum() -> void:
	var a: Combatant = _fighter("A", Factions.EARTH_ALLIANCE, Vector3.ZERO)
	var b: Combatant = _fighter("B", Factions.RAIDERS, Vector3(0.0, 0.0, -500.0))
	await _ticks(2)
	var counter: ContactCounter = _counter(a, b)
	_place(a, Vector3.ZERO, Basis.IDENTITY, Vector3(0.0, 0.0, -30.0))
	_place(b, Vector3(0.0, 0.0, -SLOW_GAP_M), FACING, Vector3.ZERO)
	var momentum_before: float = (a.ship.mass * a.ship.linear_velocity.z) + (b.ship.mass * b.ship.linear_velocity.z)
	await _ticks(20)
	assert_gt(counter.total, 0, "Jolt paired the two fighters")
	assert_lt(b.ship.linear_velocity.z, -5.0, "the one at rest was pushed along the way the other flew")
	assert_gt(a.ship.linear_velocity.z, -25.0, "and the one that hit it slowed")
	var momentum_after: float = (a.ship.mass * a.ship.linear_velocity.z) + (b.ship.mass * b.ship.linear_velocity.z)
	assert_almost_eq(momentum_after / momentum_before, 1.0, 0.05, "the momentum was exchanged, not lost")
	assert_lt(a.ship.linear_velocity.z - b.ship.linear_velocity.z, 2.0, "and they no longer close on each other")


func test_allied_fighters_collide_too() -> void:
	var a: Combatant = _fighter("A", Factions.EARTH_ALLIANCE, Vector3.ZERO)
	var b: Combatant = _fighter("B", Factions.EARTH_ALLIANCE, Vector3(0.0, 0.0, -500.0))
	await _ticks(2)
	var counter: ContactCounter = _counter(a, b)
	_head_on(a, b, 4.0)
	await _ticks(60)
	assert_gt(counter.total, 0)
	assert_lt(a.ship.linear_velocity.length(), 0.5, "they stopped each other (zero restitution)")


func test_a_fighter_head_on_at_thirty_mps_rams_as_on_the_base() -> void:
	var a: Combatant = _fighter("A", Factions.EARTH_ALLIANCE, Vector3.ZERO)
	var b: Combatant = _fighter("B", Factions.RAIDERS, Vector3(0.0, 0.0, -500.0))
	await _ticks(2)
	_head_on(a, b, 30.0)
	await _ticks(15)
	for combatant: Combatant in [a, b]:
		var hull: HullHealth = combatant.damageable.hull
		assert_lte(hull.fraction(), 0.5, "%s lost at least half its hull" % combatant.display_name)
		assert_false(hull.destroyed)
	assert_eq(infos.size(), 2, "one contact ram per ship")
	assert_string_contains(rams.last_ram, "contact", false)
	assert_almost_eq(infos[0].relative_speed_mps, 30.0, 0.5)
	await _ticks(45)
	assert_eq(infos.size(), 2, "and no more while they rest against each other")


func test_two_fighters_at_six_hundred_mps_still_take_the_swept_ram() -> void:
	var a: Combatant = _fighter("A", Factions.EARTH_ALLIANCE, Vector3.ZERO)
	var b: Combatant = _fighter("B", Factions.RAIDERS, Vector3(0.0, 0.0, -500.0))
	await _ticks(2)
	_head_on(a, b, 600.0, 60.0)  # 10 m a tick: past tunnelling speed
	await _ticks(20)
	assert_true(a.damageable.hull.destroyed and b.damageable.hull.destroyed, "the ram resolver wrecked both")
	assert_eq(infos.size(), 2, "one ram per ship")
	assert_string_contains(rams.last_ram, "tunnelling", false)


func test_a_four_mps_bump_between_fighters_hurts_nobody() -> void:
	var a: Combatant = _fighter("A", Factions.EARTH_ALLIANCE, Vector3.ZERO)
	var b: Combatant = _fighter("B", Factions.RAIDERS, Vector3(0.0, 0.0, -500.0))
	await _ticks(2)
	_head_on(a, b, 4.0)
	await _ticks(60)
	assert_eq(a.damageable.hull.fraction(), 1.0)
	assert_eq(b.damageable.hull.fraction(), 1.0)
	assert_eq(infos.size(), 0, "under the safe velocity change a ram is nothing")


func test_the_player_still_bounces_off_a_fighter() -> void:
	var player: Combatant = _fighter("PLAYER", Factions.EARTH_ALLIANCE, Vector3.ZERO, true)
	var ai: Combatant = _fighter("B", Factions.RAIDERS, Vector3(0.0, 0.0, -500.0))
	await _ticks(2)
	var counter: ContactCounter = _counter(player, ai)
	_head_on(player, ai, 4.0)
	await _ticks(60)
	assert_gt(counter.total, 0, "Jolt paired the player with the fighter")
	assert_lt(player.ship.linear_velocity.length(), 0.5, "and they stopped each other")


# --- capitals and rocks --------------------------------------------------------------------------------------------


func test_a_fighter_meets_a_capital_in_jolt() -> void:
	var cap: CapitalStandin = CapitalStandin.create(&"cruiser", Factions.EARTH_ALLIANCE, "CAP", Vector3.ZERO)
	cap.world = world
	world.spawn(cap, world.to_universe(Vector3.ZERO))
	var ai: Combatant = _fighter("B", Factions.RAIDERS, Vector3(0.0, 0.0, 400.0))
	await _ticks(2)
	var counter := ContactCounter.new()
	counter.bodies = [ai.ship]
	add_child_autofree(counter)
	_place(ai, Vector3(0.0, 0.0, 250.0), Basis.IDENTITY, Vector3(0.0, 0.0, -25.0))  # the hull's face is 150 m out
	await _ticks(400)
	assert_gt(counter.total, 0, "a capital pairs with a fighter")


func test_a_fighter_into_a_rock_is_stopped_and_rammed() -> void:
	var field := AsteroidField.new()
	world.spawn(field, world.to_universe(Vector3.ZERO))
	field.build([{"offset": Vector3(0.0, 0.0, -200.0), "radius": 40.0}] as Array[Dictionary], world.get_world_3d().space, world)
	var ai: Combatant = _fighter("B", Factions.RAIDERS, Vector3(0.0, 0.0, 0.0))
	await _ticks(2)
	var counter := ContactCounter.new()
	counter.bodies = [ai.ship]
	add_child_autofree(counter)
	_place(ai, Vector3.ZERO, Basis.IDENTITY, Vector3(0.0, 0.0, -40.0))
	await _ticks(300)
	assert_gt(counter.total, 0, "Jolt paired the fighter with the rock's body")
	assert_gt(ai.ship.linear_velocity.z, -5.0, "the rock stopped it")
	assert_true(ai.damageable.hull.destroyed or ai.damageable.hull.fraction() < 1.0, "and the rock's row rammed it")
	assert_gt(infos.size(), 0)


# --- no body -------------------------------------------------------------------------------------------------------


func test_a_bolt_never_has_a_body() -> void:
	var bolt := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
	projectiles.add_child(bolt)
	bolt.configure(WeaponSpec.new())
	bolt.launch(Vector3.ZERO, Vector3(0.0, 0.0, -500.0), SimClock.now())
	assert_false(bolt.is_class("CollisionObject3D"))
	assert_eq(bolt.find_children("*", "CollisionObject3D", true, false).size(), 0)


func test_a_mine_has_no_body() -> void:
	var standins := StandinDirector.new()
	standins.world = world
	standins.projectiles = projectiles
	world.add_child(standins)
	standins.set_physics_process(false)
	var mines: MineStandin = standins.add_mines([{"offset": Vector3(0.0, 0.0, -300.0), "faction": Factions.RAIDERS},
			{"offset": Vector3(0.0, 0.0, -600.0), "faction": Factions.EARTH_ALLIANCE}] as Array[Dictionary], world.to_universe(Vector3.ZERO))
	assert_false(mines.is_class("CollisionObject3D"))
	assert_eq(mines.find_children("*", "CollisionObject3D", true, false).size(), 0)
	assert_eq(StaticRows.count(), 2, "they are rows")


# --- the rebase settle ---------------------------------------------------------------------------------------------


## Rebases by a small step and returns how many nodes the interpolation reset (at the end of the tick) reached.
func _rebase_resets() -> int:
	world.rebase(Vector3(1.0, 0.0, 0.0))
	await _ticks(1)
	return world.last_settle_resets


func test_the_settle_walks_only_the_interpolated_nodes() -> void:
	var markers: Array[Node3D] = []
	for i: int in 6:
		var marker := Node3D.new()
		world.spawn(marker, UniversePos.new(10.0 * i, 0.0, 0.0))
		markers.append(marker)
	await _ticks(2)
	assert_eq(await _rebase_resets(), 6, "all six reset")
	for i: int in 4:
		markers[i].physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	assert_eq(await _rebase_resets(), 2, "only the two still interpolated")


func test_a_far_ship_is_not_interpolated_and_its_nodes_are_left_out_of_the_settle() -> void:
	var near: Combatant = _fighter("NEAR", Factions.RAIDERS, Vector3(0.0, 0.0, -100.0))
	var far: Combatant = _fighter("FAR", Factions.RAIDERS, Vector3(0.0, 0.0, -9000.0))
	await _ticks(2)
	var with_both: int = await _rebase_resets()
	far.ship.set_far_dot(true)
	assert_eq(far.ship.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_OFF)
	assert_eq(await _rebase_resets(), with_both - 1, "one ship fewer is reset")
	far.ship.set_far_dot(false)
	assert_eq(far.ship.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_INHERIT, "back near, it blends again")
	assert_eq(await _rebase_resets(), with_both)
	assert_eq(near.ship.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_INHERIT)
