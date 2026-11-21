extends TestSteps
## The Panama-class transport and the construction tender in the game (M10-T51, M10-T55): each imports as a textured mesh
## with a low texture set, flies through the one flight model with zero damping, and in play is a pooled, unarmed Earth
## Alliance civilian that shows its running lights, takes hull damage and breaks into its chunks. Neither is drawn by random
## traffic: a mission names them. Skips, saying why, without the generated assets.

const TYPES: Array[StringName] = [&"ea_panama", &"ea_construction_tender"]
## The hull points of T03's loadouts (`data/capitals/loadouts.json`, Q53).
const HULL_POINTS: Dictionary[StringName, float] = {&"ea_panama": 600.0, &"ea_construction_tender": 300.0}
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh and import first"
## Godot's importer may weld a few vertices; the box must still match the manifest's to a centimetre.
const AABB_TOLERANCE_M: float = 0.01


func _skipped() -> bool:
	for type: StringName in TYPES:
		if not Hardpoints.load_file(ShipCatalog.spec_for(type).hardpoints_path()).valid:
			pending("%s is not generated (%s)" % [type, GEN_ASSETS_HINT])
			return true
	return false


func test_each_imports_as_a_textured_mesh_with_a_low_texture_set() -> void:
	if _skipped():
		return
	for type: StringName in TYPES:
		var asset_id: String = ShipCatalog.spec_for(type).asset_id
		var section: Dictionary = MeshAssets.read_manifest(asset_id).get("mesh", {})
		assert_eq(String(section.get("file", "")), asset_id + ".glb")
		var mesh: Mesh = MeshAssets.for_asset(asset_id)
		assert_not_null(mesh, "%s imported (%s)" % [asset_id, GEN_ASSETS_HINT])
		if mesh == null:
			continue
		var material := mesh.surface_get_material(0) as StandardMaterial3D
		assert_true(material != null and material.albedo_texture != null and material.normal_texture != null, "%s draws with its maps" % asset_id)
		var lo: Array = section["aabb_min"]
		var hi: Array = section["aabb_max"]
		var aabb: AABB = mesh.get_aabb()
		assert_almost_eq(aabb.position, Vector3(lo[0], lo[1], lo[2]), Vector3.ONE * AABB_TOLERANCE_M, "%s box corner" % asset_id)
		assert_almost_eq(aabb.end, Vector3(hi[0], hi[1], hi[2]), Vector3.ONE * AABB_TOLERANCE_M, "%s box end" % asset_id)
		assert_eq(mesh.get_faces().size() / 3, int(section["triangles"]), "%s triangles" % asset_id)
		var low: Dictionary = ((section["surfaces"] as Array)[0] as Dictionary).get("detail", {}).get("low", {})
		for key: String in ["albedo", "normal", "orm", "emissive"]:
			var map: Texture2D = load(ShipSpec.ASSET_ROOT.path_join(asset_id).path_join(String(low.get(key, "")))) as Texture2D
			assert_not_null(map, "%s: the low set's %s map is imported" % [asset_id, key])
			if map != null:
				assert_eq(map.get_width() * 2, int(section["atlas_px"]), "%s: the low %s map is a mip level down" % [asset_id, key])


func test_each_flies_newtonian_with_zero_damping_and_turns_by_torque_alone() -> void:
	if _skipped():
		return
	var world := WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	var thrusting: Array[Ship] = []
	var turning: Array[Ship] = []
	for i: int in TYPES.size():
		for row: int in 2:
			var ship: Ship = Ship.create(ShipCatalog.spec_for(TYPES[i]), world)
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
		var layout: ThrusterLayout = ship.get_layout()
		var mains: int = layout.nozzles_in_group(ThrusterLayout.Group.L_MAIN).size() + layout.nozzles_in_group(ThrusterLayout.Group.R_MAIN).size()
		var expected: float = spec.pod_main_thrust * mains / spec.mass
		var along: float = ship.linear_velocity.dot(-ship.global_basis.z)
		assert_almost_eq(along, expected, expected * 0.15, "%s: the spec's thrust over its mass after a second" % spec.asset_id)
		assert_lt(ship.angular_velocity.length(), 0.02, "%s: full mains make no turn (the thrust line meets the centre of mass)" % spec.asset_id)
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


func test_in_play_each_is_an_earth_alliance_civilian_that_breaks_into_its_chunks() -> void:
	if _skipped():
		return
	var main := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(3)
	var destroyed: Array[Combatant] = []
	main.director.ship_destroyed.connect(func(c: Combatant, _info: HitInfo) -> void: destroyed.append(c))
	for i: int in TYPES.size():
		var type: StringName = TYPES[i]
		assert_eq(main.ensure_pool(type, 1), 1, "%s: the pool builds one, watched like the scenario's own" % type)
		var at: Vector3 = main.ship.global_position + Vector3(900.0 * (i + 1), 0.0, -1200.0)
		var c: Combatant = main.ships.acquire("WORK %d" % i, main.world.to_universe(at), Basis.IDENTITY, Vector3.ZERO, IdleBrain.new(true), type)
		assert_not_null(c, "%s: the pool gives one" % type)
		if c == null:
			continue
		await _ticks(2)
		assert_true(c.civilian, "%s carries the civilian role" % type)
		assert_eq(c.faction, Factions.EARTH_ALLIANCE, "%s flies for Earth" % type)
		assert_not_null(c.ship.get_node_or_null(^"RunningLights"), "%s shows running lights" % type)
		assert_eq(c.ship.get_hardpoints().turrets.size(), 0, "%s is unarmed (Q53)" % type)
		assert_false(ShipCatalog.civilian_types().has(type), "%s stays out of the random traffic's pool" % type)
		var max_hp: float = c.damageable.hull.max_hp
		assert_eq(max_hp, c.ship.spec.hull_max)
		assert_eq(max_hp, HULL_POINTS[type], "%s: the loadout's hull points" % type)
		c.damageable.apply_hit(HitInfo.new(c.ship.get_instance_id(), 0, Factions.RAIDERS, max_hp * 0.25, c.ship.global_position, Vector3.UP, 0.0))
		assert_almost_eq(c.damageable.hull.fraction(), 0.75, 1e-4, "%s takes hull damage" % type)
		var before: int = main.debris.active_chunk_count()
		c.damageable.apply_hit(HitInfo.new(c.ship.get_instance_id(), 0, Factions.RAIDERS, max_hp, c.ship.global_position, Vector3.UP, 0.0))
		await _ticks(1)
		var chunks: int = c.ship.get_hardpoints().chunks.size()
		assert_gt(chunks, 2, "%s has its chunks" % type)
		assert_eq(main.debris.active_chunk_count() - before, chunks, "%s breaks into its %d chunks" % [type, chunks])
		assert_has(destroyed, c, "%s was destroyed" % type)
