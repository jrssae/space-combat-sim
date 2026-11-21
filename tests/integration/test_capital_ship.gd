extends GutTest
## A capital ship in the real main scene (M10-T07, D12.4, AC7), headless, on T05's test cruiser: built from its catalogue entry
## with no damping, its compound collision, a rotating section and its sections as the core's surfaces; flown by the native
## flight step from its helm (reaction with retros brakes with its bow held, one with no retros flips, a gravitic one slides);
## carried through a rebase; handed to the low-attention tier and back; rammed on a named section; opening and holding its own
## jump point; driven from the console.

const TYPE: StringName = &"capital_test_cruiser"
const SPEED_UP: float = 4.0
const AHEAD := Vector3(0.0, 0.0, -2500.0)

var main: Main
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8
var _radius_backup: float = 10000.0


func before_each() -> void:
	get_tree().paused = false
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame
	_radius_backup = float(Settings.get_value(&"tier_radius_m"))
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.scenario_seed = 3
	add_child_autofree(main)
	await wait_physics_frames(2)
	DebugConsole.flags.invulnerable = true


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	Settings.set_value(&"tier_radius_m", _radius_backup)
	DebugConsole.flags.invulnerable = false


func _spawn(at: Vector3 = AHEAD, velocity: Vector3 = Vector3.ZERO, spec: ShipSpec = null) -> CapitalShip:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(TYPE, Factions.EARTH_ALLIANCE, "TEST CRUISER", rest + velocity, spec)
	assert_not_null(cap, "the test cruiser is generated (scripts/gen_assets.sh)")
	main.world.spawn(cap, main.world.to_universe(main.ship.global_position + at), Basis.IDENTITY)
	cap.set_course(Vector3.FORWARD, rest + velocity)
	return cap


func _fly(seconds: float, done: Callable = Callable()) -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < seconds:
		await get_tree().physics_frame
		if done.is_valid() and bool(done.call()):
			break
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute_tokens(line.split(" ", false))


static func _in_jolt(body: PhysicsBody3D) -> bool:
	return PhysicsServer3D.body_get_space(body.get_rid()).is_valid()


func test_the_body_is_built_from_its_spec_and_manifest_with_no_damping() -> void:
	var cap: CapitalShip = _spawn()
	await wait_physics_frames(3)
	assert_eq(cap.spec.asset_id, "capital_test_cruiser")
	assert_almost_eq(cap.mass, cap.spec.mass, 1.0)
	assert_eq(cap.inertia, cap.spec.inertia, "inertia from the spec")
	assert_eq(cap.linear_damp, 0.0)
	assert_eq(cap.angular_damp, 0.0)
	assert_eq(cap.linear_damp_mode, RigidBody3D.DAMP_MODE_REPLACE, "zero damping, the project's not combined in")
	assert_eq(cap.angular_damp_mode, RigidBody3D.DAMP_MODE_REPLACE)
	assert_eq(cap.gravity_scale, 0.0)
	assert_eq(cap.targetable.kind, Targetable.Kind.CAPITAL)
	assert_almost_eq(cap.targetable.broadcast_range_m, 2.0e5, 1e-3, "a cruiser is heard 200 km out (Q51)")
	assert_eq(cap.capital_class, &"cruiser")
	var manifest: Dictionary = MeshAssets.read_manifest("capital_test_cruiser")
	var hull_shapes: int = 0
	var rotor_shapes: int = 0
	for piece: Dictionary in (manifest["collision"] as Dictionary)["pieces"]:
		if str(piece["piece"]) == "hull":
			hull_shapes += (piece["shapes"] as Array).size()
		else:
			rotor_shapes += (piece["shapes"] as Array).size()
	assert_eq(cap.hull_shape_count(), hull_shapes, "every hull section's shapes on the one body")
	assert_eq(cap.damageable.shapes.size(), hull_shapes, "with a hit volume each")
	assert_eq(cap.rotors.size(), 1, "the habitat ring turns on its own body")
	var rotor: CapitalRotor = cap.rotors[0]
	assert_true(rotor is AnimatableBody3D)
	assert_eq(rotor.shape_count, rotor_shapes)
	assert_true(_in_jolt(rotor) and _in_jolt(cap))
	assert_true(cap.surfaces_held(), "the sections are the core's surfaces")
	assert_gt(int(SimCore.for_tree(get_tree()).core.surface_volume_count(rotor.get_instance_id())), 0, "the rotor's too")
	assert_true(cap.can_open_jump_point(), "the test hull opens its own points (Q51)")
	assert_eq(cap.spec.propulsion, CapitalPropulsion.REACTION)
	var a0: float = rotor.angle
	await _fly(2.0)
	assert_almost_eq(fposmod(rotor.angle - a0, TAU), rotor.spin_rad_s * 2.0, 0.05, "the ring turns at its spin")
	var expected: Transform3D = rotor.pose_for(cap.global_transform, rotor.angle)
	assert_lt(rotor.global_position.distance_to(expected.origin), 0.5, "on its pivot on the hull")


func test_the_chunks_draw_with_their_own_pieces_maps() -> void:
	var cap: CapitalShip = _spawn()
	var habitat: Mesh = cap.chunk_mesh("habitat")
	var bow: Mesh = cap.chunk_mesh("bow")
	assert_not_null(habitat)
	assert_not_null(bow)
	var rotor_entry: Dictionary = ((MeshAssets.read_manifest("capital_test_cruiser")["pieces"] as Dictionary)["rotor"] as Dictionary)["mesh"]
	var rotor_maps: Dictionary = MeshAssets.piece_materials(ShipSpec.ASSET_ROOT.path_join("capital_test_cruiser"), rotor_entry)
	assert_true(rotor_maps.values().has(habitat.surface_get_material(0)), "the ring's chunk takes the ring's maps")
	assert_false(rotor_maps.values().has(bow.surface_get_material(0)), "the bow's takes the hull's")


func test_reaction_with_retros_flies_out_and_brakes_with_its_bow_held() -> void:
	var cap: CapitalShip = _spawn()
	await wait_physics_frames(3)
	var rest: Vector3 = main.world.rest_velocity()
	cap.set_course(Vector3.FORWARD, rest + Vector3(0.0, 0.0, -15.0))
	await _fly(20.0)
	var flight: CapitalFlight = CapitalFlight.of(main.world)
	assert_true(flight.flown.has(cap), "the native step flew it")
	assert_lt((cap.linear_velocity - rest).z, -12.0, "its mains brought it up toward 15 m/s")
	cap.set_course(Vector3.FORWARD, rest)
	await _fly(25.0)
	assert_lt((cap.linear_velocity - rest).length(), 1.5, "its retros stopped it")
	assert_false(cap.helm.flipping)
	assert_gt((-cap.global_basis.z).dot(Vector3.FORWARD), 0.995, "with its bow on its heading the whole time")


func test_reaction_without_retros_flips_to_brake() -> void:
	var spec: ShipSpec = (load("res://assets/ships/capital_test_cruiser.tres") as ShipSpec).duplicate() as ShipSpec
	spec.pod_retro_thrust = 0.0
	var cap: CapitalShip = _spawn(AHEAD, Vector3(0.0, 0.0, -10.0), spec)
	await wait_physics_frames(3)
	var rest: Vector3 = main.world.rest_velocity()
	cap.set_course(Vector3.FORWARD, rest)
	var flipped: Array[bool] = [false]
	var turned_most: Array[float] = [1.0]
	await _fly(150.0, func() -> bool:
		flipped[0] = flipped[0] or cap.helm.flipping
		turned_most[0] = minf(turned_most[0], (-cap.global_basis.z).dot(Vector3.FORWARD))
		return flipped[0] and not cap.helm.flipping and (cap.linear_velocity - rest).length() < 1.0)
	assert_true(flipped[0], "with no retros it turned to burn against its motion")
	assert_lt(turned_most[0], -0.9, "its bow came round past the beam")
	assert_lt((cap.linear_velocity - rest).length(), 1.0, "and its mains stopped it")


func test_a_gravitic_hull_slides_and_brakes_without_turning() -> void:
	var spec: ShipSpec = (load("res://assets/ships/capital_test_cruiser.tres") as ShipSpec).duplicate() as ShipSpec
	spec.propulsion = CapitalPropulsion.GRAVITIC
	spec.pod_retro_thrust = 0.0
	spec.gravitic_fraction = 0.5
	var cap: CapitalShip = _spawn(AHEAD, Vector3(0.0, 0.0, -10.0), spec)
	await wait_physics_frames(3)
	var rest: Vector3 = main.world.rest_velocity()
	cap.set_course(Vector3.FORWARD, rest + Vector3(5.0, 0.0, 0.0))
	await _fly(20.0)
	var v: Vector3 = cap.linear_velocity - rest
	assert_almost_eq(v.z, 0.0, 1.0, "braked along its nose")
	assert_almost_eq(v.x, 5.0, 1.0, "and slid sideways")
	assert_false(cap.helm.flipping)
	assert_gt((-cap.global_basis.z).dot(Vector3.FORWARD), 0.995, "without turning")


func test_a_rebase_carries_the_hull_and_its_rotor_without_a_ram() -> void:
	var cap: CapitalShip = _spawn()
	await wait_physics_frames(3)
	var hp: float = cap.damageable.hull.hp
	var before: UniversePos = main.world.to_universe(cap.global_position)
	main.world.rebase(Vector3(4000.0, 0.0, 0.0))
	await wait_physics_frames(3)
	var after: UniversePos = main.world.to_universe(cap.global_position)
	assert_lt(before.distance_to(after), 1.0, "the hull keeps its universe place")
	var rotor: CapitalRotor = cap.rotors[0]
	assert_lt(rotor.global_position.distance_to(rotor.pose_for(cap.global_transform, rotor.angle).origin), 0.5,
			"the rotor came with it")
	var swept: Vector3 = PhysicsServer3D.body_get_state(rotor.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	assert_lt(swept.length(), 50.0, "moved as a teleport, not a 240 km/s sweep")
	assert_eq(cap.damageable.hull.hp, hp, "nothing rammed")


func test_the_tier_takes_it_as_a_row_and_gives_it_back() -> void:
	Settings.set_value(&"tier_radius_m", 30000.0)
	var cap: CapitalShip = _spawn(Vector3(0.0, 0.0, -15000.0), Vector3(0.0, 0.0, -5.0))
	await wait_physics_frames(3)
	assert_false(cap.is_tier_parked())
	Settings.set_value(&"tier_radius_m", 10000.0)
	await _fly(1.0, func() -> bool: return cap.is_tier_parked())
	assert_true(cap.is_tier_parked(), "15 km out it is a tier row")
	assert_false(_in_jolt(cap) or _in_jolt(cap.rotors[0]), "hull and rotor out of Jolt")
	assert_false(CapitalFlight.of(main.world).flown.has(cap), "the flight step leaves a parked hull alone")
	var row_at: Vector3 = TierDirector.flying_position(cap)
	await _fly(2.0)
	assert_lt(TierDirector.flying_position(cap).z, row_at.z - 5.0, "its row cruises on")
	Settings.set_value(&"tier_radius_m", 30000.0)
	await _fly(1.0, func() -> bool: return not cap.is_tier_parked())
	assert_false(cap.is_tier_parked(), "back within the radius it is a body again")
	await wait_physics_frames(2)
	assert_true(_in_jolt(cap) and _in_jolt(cap.rotors[0]))
	var rotor: CapitalRotor = cap.rotors[0]
	assert_lt(rotor.global_position.distance_to(rotor.pose_for(cap.global_transform, rotor.angle).origin), 1.0,
			"its rotor beside it")
	assert_lt((cap.linear_velocity - main.world.rest_velocity()).z, -3.0, "with its row's motion")


func test_a_ram_lands_on_the_section_it_hit() -> void:
	var cap: CapitalShip = _spawn()
	await wait_physics_frames(3)
	var bow: Vector3 = cap.global_transform * Vector3(0.0, 0.0, -130.0)
	# A raider with no pilot coasting straight at the bow.
	var c: Combatant = ShipAssembly.build(load("res://assets/ships/raider_delta_v.tres") as ShipSpec, main.world,
			main.projectiles, {ShipAssembly.OPT_FACTION: Factions.RAIDERS, ShipAssembly.OPT_DISPLAY_NAME: "RAMMER"})
	main.world.spawn(c.ship, main.world.to_universe(bow + Vector3(0.0, 0.0, -150.0)))
	c.ship.linear_velocity = main.world.rest_velocity() + Vector3(0.0, 0.0, 60.0)
	# A raider 250 times lighter barely moves the hull: its limits lowered so the small change it gets lands as a ram.
	cap.damageable.ram_safe_dv_mps = 0.02
	cap.damageable.ram_lethal_dv_mps = 2.0
	var rams: Array[HitInfo] = []
	main.rams.ram_resolved.connect(func(info: HitInfo) -> void:
		if info.target_id == cap.get_instance_id():
			rams.append(info))
	var sections: Array[String] = []
	cap.section_hit.connect(func(section: String, _info: HitInfo) -> void: sections.append(section))
	await _fly(5.0, func() -> bool: return not sections.is_empty())
	gut.p("rammer at %s v %s, hull v %s, hp %.0f" % [cap.to_local(c.ship.global_position), c.ship.linear_velocity - main.world.rest_velocity(), cap.linear_velocity - main.world.rest_velocity(), cap.damageable.hull.hp])
	assert_false(rams.is_empty(), "the fighter rammed the hull")
	assert_eq(sections.size() > 0 and sections[0] == "bow", true, "named by the section it hit: %s" % [sections])
	assert_eq(cap.last_section, "bow")


func test_it_opens_and_holds_its_own_jump_point() -> void:
	var cap: CapitalShip = _spawn()
	await wait_physics_frames(3)
	var pool := JumpPointPool.new()
	pool.world = main.world
	main.world.add_child(pool)
	pool.prepare(2)
	var point: JumpVortex = cap.open_own_point(pool)
	assert_not_null(point, "a jump-capable hull opens its own point")
	assert_true(point.held)
	assert_eq(point.opener, cap)
	assert_almost_eq(point.hold_range_m, 650.0 + cap.length_m(), 2.0, "held to a length past its anchor")
	var mouth: Vector3 = point.true_frame().origin
	assert_lt(mouth.distance_to(cap.global_transform * (cap.jump_anchor["position"] as Vector3)), 1.0, "at its anchor")
	await _fly(3.0)
	assert_true(point.held and point.is_active(), "it holds while the hull is near")
	assert_eq(pool.collapses, 0)
	assert_null(cap.open_own_point(pool), "its drive needs its recharge before another")
	cap.global_position = mouth + Vector3(0.0, 0.0, 2000.0)
	await wait_physics_frames(3)
	assert_eq(pool.collapses, 1, "out of its hold range the point collapses")


func test_the_console_spawns_steers_and_reads_it() -> void:
	var spawned: ConsoleResult = _run("capital spawn %s 3000" % TYPE)
	assert_true(spawned.ok, spawned.error)
	var flight: CapitalFlight = CapitalFlight.of(main.world)
	assert_not_null(flight, "the capital flight came with the ship")
	if flight == null:
		return
	assert_eq(flight.ships().size(), 1)
	await wait_physics_frames(3)
	assert_true(_run("capital helm 8").ok)
	var read: Dictionary = DebugConsole.registry.read("capital.collision")
	assert_true(bool(read.get("ok", false)))
	assert_string_contains(str(read.get("value", "")), "in the core")
	assert_string_contains(str(DebugConsole.registry.read("capital.propulsion").get("value", "")), "retros")
	assert_true(_run("capital jump").ok, "it opens its own point from the console")
	assert_string_contains(str(DebugConsole.registry.read("capital.jump").get("value", "")), "holds a point")
	assert_true(_run("capital").ok)
