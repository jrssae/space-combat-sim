extends GutTest
## The nine civilian hulls in the game (M5-T16, AC13, D59): each flies through the one flight model with zero damping, heavy
## and slow, turning by torque alone; in play each carries its people's faction with the civilian role, shows its running
## lights, takes hull damage and breaks into its chunks; raiders attack them through the faction data; a Bokmai flies with
## its 0-3 cargo pods (mass, collision, hit volumes, the far dot) and sheds them as debris when it breaks up. The in-play
## half runs the real main scene on `civilian_showcase`. Skips, saying why, without the generated assets.

const SHOWCASE: String = "res://data/scenarios/civilian_showcase.json"
const BOKMAI: StringName = &"brakiri_bokmai"
## Ticks per real tick: the physics rate and the time scale raised together, so each step is still 1/60 s of sim time.
const SPEED_UP: float = 4.0

var _rate_backup: int = 60
var _scale_backup: float = 1.0


func before_each() -> void:
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	get_tree().paused = false


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup


func _skipped() -> bool:
	for type: StringName in ShipCatalog.CIVILIAN_TYPES:
		if not Hardpoints.load_file(ShipCatalog.spec_for(type).hardpoints_path()).valid:
			pending("%s is not generated (scripts/gen_assets.sh)" % type)
			return true
	return false


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


# --- flight ---------------------------------------------------------------------------------------------------------


func test_every_hull_flies_newtonian_with_zero_damping_and_turns_by_torque_alone() -> void:
	if _skipped():
		return
	var world := WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	var thrusting: Array[Ship] = []
	var turning: Array[Ship] = []
	var types: Array[StringName] = ShipCatalog.CIVILIAN_TYPES
	for i: int in types.size():
		var spec: ShipSpec = ShipCatalog.spec_for(types[i])
		for row: int in 2:
			var ship: Ship = Ship.create(spec, world)
			world.spawn(ship, world.to_universe(Vector3(1500.0 * i, 1500.0 * row, 0.0)))
			(thrusting if row == 0 else turning).append(ship)
	await _ticks(1)
	for ship: Ship in thrusting + turning:
		var id: String = ship.spec.asset_id
		assert_true(ship.get_layout().valid, "%s has a valid thruster layout" % id)
		assert_eq(ship.linear_damp_mode, RigidBody3D.DAMP_MODE_REPLACE, "%s: linear damping replaces the project's" % id)
		assert_eq(ship.angular_damp_mode, RigidBody3D.DAMP_MODE_REPLACE, "%s: angular damping replaces the project's" % id)
		assert_eq(ship.linear_damp, 0.0, "%s: no linear damping" % id)
		assert_eq(ship.angular_damp, 0.0, "%s: no angular damping" % id)
		assert_eq(ship.gravity_scale, 0.0, "%s: no gravity" % id)
		assert_eq(ship.mass, ship.spec.mass, "%s: the spec's mass" % id)
	var full := FlightCommand.new()
	full.main_left = 1.0
	full.main_right = 1.0
	var yaw := FlightCommand.new()
	yaw.rot = Vector3(0.0, 1.0, 0.0)
	for ship: Ship in thrusting:
		ship.set_flight_command(full)
	for ship: Ship in turning:
		ship.set_flight_command(yaw)
	await _ticks(60)
	for ship: Ship in thrusting:
		var spec: ShipSpec = ship.spec
		var mains: int = ship.get_layout().nozzles_in_group(ThrusterLayout.Group.L_MAIN).size() \
				+ ship.get_layout().nozzles_in_group(ThrusterLayout.Group.R_MAIN).size()
		var expected: float = spec.pod_main_thrust * mains / spec.mass * 1.0
		var along: float = ship.linear_velocity.dot(-ship.global_basis.z)
		gut.p("%s: %.2f m/s after 1 s of full mains (spec %.2f), %.1f deg/s pitch rate limit" % [spec.asset_id, along, expected,
				spec.rate_max.x])
		assert_almost_eq(along, expected, expected * 0.15, "%s: heavy and slow, the spec's thrust over its mass" % spec.asset_id)
		ship.set_assist(false)
		ship.set_flight_command(FlightCommand.new())
	for ship: Ship in turning:
		var spin: float = ship.angular_velocity.length()
		assert_gt(spin, 0.0, "%s turns" % ship.spec.asset_id)
		assert_lte(spin, deg_to_rad(ship.spec.rate_max.y) * 1.05, "%s: at most its rate" % ship.spec.asset_id)
		assert_lt(ship.linear_velocity.length(), 0.05, "%s turns by torque only, no push" % ship.spec.asset_id)
	await _ticks(1)
	var speeds: Array[float] = []
	for ship: Ship in thrusting:
		speeds.append(ship.linear_velocity.length())
	await _ticks(60)
	for i: int in thrusting.size():
		assert_almost_eq(thrusting[i].linear_velocity.length(), speeds[i], speeds[i] * 1e-4,
				"%s coasts: no momentum bled" % thrusting[i].spec.asset_id)


# --- in play --------------------------------------------------------------------------------------------------------


func _showcase() -> Main:
	var main := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = SHOWCASE
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(3)
	return main


func test_the_showcase_parks_every_hull_with_its_people_and_role() -> void:
	if _skipped():
		return
	var main: Main = await _showcase()
	assert_eq(main.scenario_ships.size(), 10, "all nine, and a second Bokmai")
	var types: Dictionary = {}
	for c: Combatant in main.scenario_ships:
		var type: StringName = main.ships.type_of(c)
		types[type] = int(types.get(type, 0)) + 1
		assert_true(c.civilian, "%s carries the civilian role" % type)
		assert_eq(c.faction, ShipCatalog.faction_for(type), "%s flies for its people" % type)
		assert_true(Factions.is_hostile(Factions.RAIDERS, c.faction), "raiders prey on %s" % type)
		var lights := c.ship.get_node_or_null(^"RunningLights") as RunningLights
		assert_not_null(lights, "%s shows running lights" % type)
		assert_lt(c.ship.global_position.length(), 2500.0, "%s is parked in view" % type)
	for type: StringName in ShipCatalog.CIVILIAN_TYPES:
		assert_true(types.has(type), "%s is in the showcase" % type)
	assert_eq(int(types[BOKMAI]), 2)


func test_a_bokmai_flies_with_three_pods_or_none() -> void:
	if _skipped():
		return
	var main: Main = await _showcase()
	var laden: Combatant = _named(main, "BOKMAI LADEN")
	var empty: Combatant = _named(main, "BOKMAI EMPTY")
	var spec: ShipSpec = laden.ship.spec
	var hull_shapes: int = laden.ship.get_hardpoints().collision.size()
	assert_not_null(laden.cargo_pods, "a Bokmai has its pods")
	var pod_kg: float = laden.cargo_pods.pod_mass_kg
	assert_gt(pod_kg, 0.0)
	assert_eq(laden.cargo_pods.count, 3)
	assert_eq(empty.cargo_pods.count, 0)
	assert_almost_eq(laden.ship.mass, spec.mass + 3.0 * pod_kg, 1.0, "three pods add their mass")
	assert_almost_eq(empty.ship.mass, spec.mass, 1e-3, "no pods, the hull's mass")
	assert_gt(laden.ship.inertia.x, spec.inertia.x, "and their inertia")
	assert_eq(empty.ship.inertia, spec.inertia)
	assert_gt(laden.damageable.shapes.size(), hull_shapes, "the pods are hit volumes")
	assert_eq(empty.damageable.shapes.size(), hull_shapes)
	assert_eq(_live_shape_owners(laden.ship), _live_shape_owners(empty.ship) + 3, "and Jolt shapes, one a pod")
	var pods_laden: Array = laden.cargo_pods.get_children().filter(func(n: Node) -> bool: return (n as Node3D).visible)
	assert_eq(pods_laden.size(), 3, "three pod meshes show")
	laden.ship.set_far_dot(true)
	assert_false(laden.cargo_pods.visible, "the far dot hides the pods with the hull")
	laden.ship.set_far_dot(false)
	assert_true(laden.cargo_pods.visible)
	# Taken back to the pool and handed out again, a Bokmai flies with every pod.
	main.ships.release(empty)
	var again: Combatant = main.ships.acquire("AGAIN", main.world.to_universe(Vector3(0.0, 0.0, -3000.0)), Basis.IDENTITY,
			Vector3.ZERO, null, BOKMAI)
	assert_same(again, empty)
	assert_eq(again.cargo_pods.count, 3)


func test_the_target_preview_draws_a_bokmai_with_its_pods_and_counts_them() -> void:
	if _skipped():
		return
	var main: Main = await _showcase()
	var laden: Combatant = _named(main, "BOKMAI LADEN")
	var empty: Combatant = _named(main, "BOKMAI EMPTY")
	assert_eq(laden.cargo_pods.mounted_parts().size(), 3, "three pods to draw")
	assert_eq(empty.cargo_pods.mounted_parts().size(), 0)
	assert_not_null(laden.cargo_pods.mounted_parts()[0]["mesh"])
	var director: TargetMenuDirector = main.target_menu
	var preview: TargetPreview = director.preview
	assert_eq(director._facts(laden.targetable.get_instance_id()), {"asset_id": "brakiri_bokmai", "cargo_pods": 3, "cargo_mounts": 3,
			"attacking_you": false})
	assert_eq(director._parts(laden.targetable.get_instance_id()).size(), 4, "the hull and its three pods")
	assert_eq(director._parts(empty.targetable.get_instance_id()).size(), 1)
	assert_eq(director._hull_key(laden.targetable.get_instance_id(), "brakiri_bokmai"), "brakiri_bokmai+3 pods")
	assert_eq(director._hull_key(empty.targetable.get_instance_id(), "brakiri_bokmai"), "brakiri_bokmai")
	# The panel itself, on whichever civilian the ring lists first.
	assert_eq(director.open(), "")
	director.menu.radial.set_highlight(TargetCategories.ORDER.find(TargetCategories.Category.CIVILIAN))
	director.select()
	assert_true(preview.is_showing())
	assert_eq(preview.model.kind, TargetPreviewModel.Kind.SHIP)
	assert_true(preview.wire.has_hull(), "a civilian hull is drawn")
	assert_true(TargetPreviewModel.CLASS_NAMES.values().has(preview.model.subtitle.get_slice(" · ", 0)), preview.model.subtitle)
	director.close()
	assert_false(preview.is_showing())


func test_each_hull_takes_damage_and_breaks_into_its_chunks_a_bokmai_shedding_its_pods() -> void:
	if _skipped():
		return
	var main: Main = await _showcase()
	var destroyed: Array[Combatant] = []
	main.director.ship_destroyed.connect(func(c: Combatant, _info: HitInfo) -> void: destroyed.append(c))
	for c: Combatant in main.scenario_ships.duplicate():
		var name: String = c.display_name
		var max_hp: float = c.damageable.hull.max_hp
		c.damageable.apply_hit(HitInfo.new(c.ship.get_instance_id(), 0, Factions.RAIDERS, max_hp * 0.25, c.ship.global_position,
				Vector3.UP, 0.0))
		assert_almost_eq(c.damageable.hull.fraction(), 0.75, 1e-4, "%s takes hull damage" % name)
		var before: int = main.debris.active_chunk_count()
		var pods: int = c.cargo_pods.count if c.cargo_pods != null else 0
		c.damageable.apply_hit(HitInfo.new(c.ship.get_instance_id(), 0, Factions.RAIDERS, max_hp, c.ship.global_position,
				Vector3.UP, 0.0))
		await _ticks(1)
		var chunks: int = c.ship.get_hardpoints().chunks.size()
		assert_gt(chunks, 2, "%s has its chunks" % name)
		assert_eq(main.debris.active_chunk_count() - before, chunks + pods,
				"%s breaks into its %d chunks and sheds %d pods" % [name, chunks, pods])
		assert_has(destroyed, c, "%s was destroyed" % name)
		assert_false(c.ship.visible, "%s left play" % name)


func test_raiders_attack_civilians_through_the_faction_data() -> void:
	if _skipped():
		return
	var main: Main = await _showcase()
	main.ensure_pool(ShipPool.DEFAULT_TYPE, 1)
	var hits: Array[String] = []
	for c: Combatant in main.scenario_ships:
		c.damageable.hit_taken.connect(func(_info: HitInfo) -> void: hits.append(c.display_name))
	main.combatant.damageable.invulnerable = true
	assert_true(DebugConsole.registry.execute("spawn raider ai 1500")[0].ok)
	var raider: Combatant = main.ships.alive(ShipPool.DEFAULT_TYPE)[0]
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	var t0: float = SimClock.now()
	var target: String = ""
	while SimClock.now() - t0 < 40.0 and hits.is_empty():
		await get_tree().physics_frame
		var seen: Dictionary = (raider.driver.brain as AiPilot).describe()
		if String(seen.get("behaviour", "")) == "attack":
			target = String(seen.get("target", target))
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	gut.p("the raider attacked %s; hits on %s" % [target, hits])
	assert_false(hits.is_empty(), "its bolts hit a civilian within 40 s")
	var names: Array = main.scenario_ships.map(func(c: Combatant) -> String: return c.display_name)
	assert_has(names, target, "it attacked a civilian (%s), not the player" % target)


func _named(main: Main, ship_name: String) -> Combatant:
	for c: Combatant in main.scenario_ships:
		if c.display_name == ship_name:
			return c
	return null


func _live_shape_owners(ship: Ship) -> int:
	var n: int = 0
	for owner_id: int in ship.get_shape_owners():
		if not ship.is_shape_owner_disabled(owner_id):
			n += 1
	return n
