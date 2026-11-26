extends TestSteps
## The Centauri shuttle and the Minbari Flyer in the game (M10-T58): each imports as a textured mesh with a low texture set,
## flies through the one flight model with zero damping, and in play is a pooled civilian of its faction that only a mission
## places, shows its running lights, takes hull damage and breaks into its chunks. The shuttle is unarmed on a reaction drive
## whose plumes fit its two big nozzles (Q93); the Flyer carries two plasma guns of about a Starfury's power, turns slower than
## one, and its gravitic drive makes no plume: only the thrusters at its bow do (Q91, Q92), the blades' pods firing forward and
## the inner pods swinging their plumes for the side and vertical thrust (Q97). Both are finished: in the ship line-up and in
## free flight's traffic, and the Flyer turns on a pursuer it cannot shake (Q97). Skips, saying why, without the generated assets.

const SHUTTLE: StringName = &"centauri_shuttle"
const FLYER: StringName = &"minbari_flyer"
const TYPES: Array[StringName] = [SHUTTLE, FLYER]
const FACTIONS: Dictionary[StringName, StringName] = {SHUTTLE: &"centauri", FLYER: &"minbari"}
const STARFURY_SPEC: String = "res://assets/ships/starfury_aurora.tres"
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
			world.spawn(ship, world.to_universe(Vector3(500.0 * i, 500.0 * row, 0.0)))
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


# One of `type` built as the game builds it, with its plumes as nodes, alone in a bare world.
func _built(type: StringName, world: WorldFrame, at: Vector3) -> Combatant:
	var c: Combatant = ShipAssembly.build(ShipCatalog.spec_for(type), world, world.get_node(^"Projectiles") as Node3D,
			{ShipAssembly.OPT_FACTION: FACTIONS[type], ShipAssembly.OPT_DISPLAY_NAME: String(type), ShipAssembly.OPT_CIVILIAN: true})
	world.spawn(c.ship, world.to_universe(at))
	return c


func _bare_world() -> WorldFrame:
	var world := WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	return world


# The pod nozzles that are mains (or, not `mains`, the forward-firing ones), as plume indices.
func _nozzles(layout: ThrusterLayout, mains: bool) -> Array[int]:
	var out: Array[int] = []
	for i: int in layout.nozzle_count():
		if ThrusterLayout.is_main_group(layout.nozzle_groups[i]) == mains:
			out.append(i)
	return out


func test_the_flyers_gravitic_drive_lights_but_makes_no_plume_and_its_blade_thrusters_do() -> void:
	if _skipped():
		return
	var world: WorldFrame = _bare_world()
	var flyer: Combatant = _built(FLYER, world, Vector3.ZERO)
	await _ticks(2)
	var spec: ShipSpec = flyer.ship.spec
	assert_true(CapitalPropulsion.is_gravitic(spec), "a gravitic drive (Q92)")
	assert_almost_eq(spec.pod_retro_thrust, spec.gravitic_fraction * spec.pod_main_thrust, 1.0, "it brakes at its gravitic share, no flip")
	var layout: ThrusterLayout = flyer.ship.get_layout()
	var thrusters: ThrusterVisuals = flyer.thrusters
	assert_false(thrusters.main_plumes)
	var burn := FlightCommand.new()
	burn.main_left = 1.0
	burn.main_right = 1.0
	flyer.ship.set_assist(false)
	flyer.ship.set_flight_command(burn)
	await _ticks(3)
	thrusters.advance(1.0)
	for i: int in _nozzles(layout, true):
		assert_gt(thrusters.glow_level(i), 0.9, "the drive is at full thrust")
		assert_false(thrusters.glow_shown(i), "and draws no plume")
		assert_false(thrusters.glow(i).visible)
		assert_gt(thrusters.nozzle_light(i).energy, 0.0, "but it glows: its light follows the thrust")
	# Braking (Q97): the two pods on each blade fire forward from their holes; the pod's own retro nozzle draws nothing.
	var brake := FlightCommand.new()
	brake.retro_left = 1.0
	brake.retro_right = 1.0
	flyer.ship.set_flight_command(brake)
	await _ticks(3)
	thrusters.advance(1.0)
	for i: int in _nozzles(layout, false):
		assert_gt(thrusters.glow_level(i), 0.9, "it brakes")
		assert_false(thrusters.glow_shown(i), "the blade's pods draw the braking thrust, not its nose")
	assert_eq(layout.rcs_nozzles.size(), 6, "two forward pods a blade and an inner pod a side, and no other port")
	var blades: int = 0
	var inner: Array[int] = []
	for j: int in layout.rcs_nozzles.size():
		var port: Dictionary = layout.rcs_nozzles[j]
		var at: Vector3 = port["position"]
		assert_eq(port["exhaust"], Vector3.FORWARD, "%s opens forward: no inward set" % port["name"])
		assert_lt(at.z, flyer.ship.get_layout().center_of_mass.z - 10.0, "%s is at the bow" % port["name"])
		if (port["swing"] as PackedFloat64Array).is_empty():
			blades += 1
			assert_gt(absf(at.x), 8.0, "%s is out on a blade" % port["name"])
			assert_true(thrusters.glow_shown(layout.nozzle_count() + j), "%s plumes as it brakes" % port["name"])
			assert_almost_eq(thrusters.plume_direction(layout.nozzle_count() + j), Vector3.FORWARD, Vector3.ONE * 1e-5)
		else:
			inner.append(layout.nozzle_count() + j)
			assert_between(absf(at.x), 6.0, 8.0, "%s is just inside a blade" % port["name"])
			assert_false(thrusters.glow_shown(layout.nozzle_count() + j), "%s is dark with no side thrust asked" % port["name"])
	assert_eq(blades, 4)
	assert_eq(inner.size(), 2)
	# Side and vertical thrust (Q97): the inner pods swing their plumes against it, up and down almost to the vertical,
	# inboard far over and outboard only a little, where the blade stands.
	var heave := FlightCommand.new()
	heave.strafe = Vector2(0.0, 1.0)
	flyer.ship.set_flight_command(heave)
	await _ticks(3)
	thrusters.advance(1.0)
	for i: int in inner:
		assert_true(thrusters.glow_shown(i), "an inner pod plumes for the lift")
		assert_lt(thrusters.plume_direction(i).y, -0.99, "its plume swung down, 85 degrees from straight ahead")
	var sway := FlightCommand.new()
	sway.strafe = Vector2(1.0, 0.0)
	flyer.ship.set_flight_command(sway)
	await _ticks(3)
	thrusters.advance(1.0)
	for i: int in inner:
		var way: Vector3 = thrusters.plume_direction(i)
		var starboard: bool = (layout.rcs_nozzles[i - layout.nozzle_count()]["position"] as Vector3).x > 0.0
		assert_lt(way.x, 0.0, "a push to starboard: both plumes go to port")
		assert_almost_eq(rad_to_deg(asin(-way.x)), 80.0 if starboard else 20.0, 0.5,
				"the starboard pod swings inboard, the port pod outboard as far as its blade lets it")
	# The handling follows the swing: less side thrust than lift, by what the outboard limit gives up.
	assert_almost_eq(spec.rcs_force_max.x / spec.rcs_force_max.y, (sin(deg_to_rad(80.0)) + sin(deg_to_rad(20.0))) / (2.0 * sin(deg_to_rad(85.0))), 0.01)


func test_the_flyer_carries_two_plasma_guns_of_a_starfurys_power_and_turns_slower() -> void:
	if _skipped():
		return
	var world: WorldFrame = _bare_world()
	var flyer: Combatant = _built(FLYER, world, Vector3.ZERO)
	var shuttle: Combatant = _built(SHUTTLE, world, Vector3(300.0, 0.0, 0.0))
	await _ticks(2)
	var starfury := load(STARFURY_SPEC) as ShipSpec
	var spec: ShipSpec = flyer.ship.spec
	var muzzles: Array[Node3D] = flyer.ship.get_muzzles()
	assert_eq(muzzles.size(), 2, "two guns (Q91)")
	assert_almost_eq(muzzles[0].position.x, -muzzles[1].position.x, 1e-4, "either side of the nose")
	assert_between(absf(muzzles[0].position.x), 3.0, 4.5, "in the gun pods beside the central pod")
	for muzzle: Node3D in muzzles:
		assert_almost_eq(-muzzle.basis.z, Vector3.FORWARD, Vector3.ONE * 1e-5, "firing forward")
	assert_eq(flyer.cannon.weapon, spec.weapon, "its cannon is the plasma gun")
	assert_eq(spec.weapon.damage, starfury.weapon.damage, "a Starfury's damage a bolt")
	assert_eq(spec.weapon.shot_interval_s, starfury.weapon.shot_interval_s, "at a Starfury's rate")
	for axis: int in 3:
		assert_lt(spec.rate_max[axis], starfury.rate_max[axis], "it turns slower than a Starfury")
	assert_lt(spec.pod_main_thrust * 2.0 / spec.mass, starfury.pod_main_thrust * 4.0 / starfury.mass, "and gathers speed slower")
	assert_lt(spec.rcs_force_max.x / spec.mass, starfury.rcs_force_max.x / starfury.mass)
	# The shuttle (Q93): no guns, a reaction drive whose plumes fit its two big nozzles.
	assert_eq(shuttle.ship.get_muzzles().size(), 0, "the shuttle is unarmed")
	assert_null(shuttle.ship.spec.weapon)
	assert_false(CapitalPropulsion.is_gravitic(shuttle.ship.spec), "a reaction drive")
	assert_gt(shuttle.ship.spec.pod_retro_thrust, 0.0, "retros as built")
	var thrusters: ThrusterVisuals = shuttle.thrusters
	assert_true(thrusters.main_plumes)
	assert_almost_eq(thrusters.main_radius_m, 0.4 * shuttle.ship.spec.main_plume_scale, 1e-6)
	var layout: ThrusterLayout = shuttle.ship.get_layout()
	assert_eq(_nozzles(layout, true).size(), 2, "two main nozzles")
	var burn := FlightCommand.new()
	burn.main_left = 1.0
	burn.main_right = 1.0
	shuttle.ship.set_assist(false)
	shuttle.ship.set_flight_command(burn)
	await _ticks(3)
	thrusters.advance(1.0)
	for i: int in _nozzles(layout, true):
		assert_true(thrusters.glow_shown(i), "a plume from each main nozzle")
		assert_gt(thrusters.cone(i).scale.x, 1.0, "as wide as the nozzle it leaves")
	var lifts: Dictionary = {}
	for port: Dictionary in layout.rcs_nozzles:
		assert_lt(absf((port["position"] as Vector3).x), 20.0, "%s: no thruster at a wing tip" % port["name"])
		if String(port["name"]).contains("_root_"):
			lifts[port["name"]] = layout.nozzle_count() + layout.rcs_nozzles.find(port)
	# The wing roots lift and roll it (Q97): a port up and a port down on each.
	assert_eq(lifts.size(), 4, "a lift port up and down on each wing's root")
	var up := FlightCommand.new()
	up.strafe = Vector2(0.0, 1.0)
	shuttle.ship.set_flight_command(up)
	await _ticks(3)
	thrusters.advance(1.0)
	for port_name: String in lifts:
		assert_eq(thrusters.glow_shown(lifts[port_name]), port_name.ends_with("_down"), "%s: the ports firing down lift the hull" % port_name)
	var roll := FlightCommand.new()
	roll.rot = Vector3(0.0, 0.0, 1.0)
	shuttle.ship.set_flight_command(roll)
	await _ticks(3)
	thrusters.advance(1.0)
	assert_ne(thrusters.glow_shown(lifts["r_root_up"]), thrusters.glow_shown(lifts["l_root_up"]), "a roll fires one wing's upper port")
	assert_eq(thrusters.glow_shown(lifts["r_root_up"]), thrusters.glow_shown(lifts["l_root_down"]), "and the other wing's lower one")


func test_in_play_each_is_a_civilian_of_its_faction_that_breaks_into_its_chunks() -> void:
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
		assert_true(ShipCatalog.is_civilian(type), "%s carries the civilian role" % type)
		assert_eq(ShipCatalog.faction_for(type), FACTIONS[type])
		assert_false(ShipCatalog.civilian_types().has(type), "%s stays out of the missions' random civilian" % type)
		assert_eq(LookScene.pool_types().get(String(type)), type, "its look sheet parks one")
		assert_eq(main.ensure_pool(type, 1), 1, "%s: the pool builds one, watched like the scenario's own" % type)
		var at: Vector3 = main.ship.global_position + Vector3(400.0 * (i + 1), 0.0, -600.0)
		var c: Combatant = main.ships.acquire("CRAFT %d" % i, main.world.to_universe(at), Basis.IDENTITY, Vector3.ZERO, IdleBrain.new(true), type)
		assert_not_null(c, "%s: the pool gives one" % type)
		if c == null:
			continue
		await _ticks(2)
		assert_true(c.civilian, "%s is a civilian in play" % type)
		assert_eq(c.faction, FACTIONS[type], "%s flies for its own" % type)
		assert_not_null(c.ship.get_node_or_null(^"RunningLights"), "%s shows running lights" % type)
		assert_eq(c.ship.get_hardpoints().turrets.size(), 0, "%s has no turrets" % type)
		assert_eq(c.ship.get_muzzle_transforms().size(), 2 if type == FLYER else 0, "%s: guns on the Flyer only" % type)
		assert_eq(c.thrusters.main_plumes, type == SHUTTLE, "%s: only the reaction drive plumes" % type)
		var max_hp: float = c.damageable.hull.max_hp
		assert_eq(max_hp, c.ship.spec.hull_max)
		c.damageable.apply_hit(HitInfo.new(c.ship.get_instance_id(), 0, Factions.RAIDERS, max_hp * 0.25, c.ship.global_position, Vector3.UP, 0.0))
		assert_almost_eq(c.damageable.hull.fraction(), 0.75, 1e-4, "%s takes hull damage" % type)
		var before: int = main.debris.active_chunk_count()
		c.damageable.apply_hit(HitInfo.new(c.ship.get_instance_id(), 0, Factions.RAIDERS, max_hp, c.ship.global_position, Vector3.UP, 0.0))
		await _ticks(1)
		var chunks: int = c.ship.get_hardpoints().chunks.size()
		assert_gt(chunks, 2, "%s has its chunks" % type)
		assert_eq(main.debris.active_chunk_count() - before, chunks, "%s breaks into its %d chunks" % [type, chunks])
		assert_has(destroyed, c, "%s was destroyed" % type)


func test_an_armed_flyer_runs_from_a_raider_and_turns_on_it_when_it_cannot_shake_it() -> void:
	# Q97: the Saturn civilians' flight, a little more aggressive. A lone raider that stays 800 m astern is first run from,
	# then fought. The rule itself is tested in the native core; this is the profile, the hull and its guns together.
	if _skipped() or not Hardpoints.load_file(ShipCatalog.spec_for(&"raider_fighter").hardpoints_path()).valid:
		pending("the Flyer or the raider is not generated (%s)" % GEN_ASSETS_HINT)
		return
	await get_tree().process_frame
	await get_tree().physics_frame
	var scene: TurretScene = TurretScene.build(self)
	var behaviour: Dictionary = ShipCatalog.civilian_behaviour(FLYER)
	var flyer: Combatant = scene.ship(FLYER, FACTIONS[FLYER], "FLYER", Vector3.ZERO, behaviour, 1, true)
	var raider: Combatant = scene.ship(&"raider_fighter", Factions.RAIDERS, "RAIDER", Vector3(0.0, 0.0, 800.0))
	scene.attach()
	var pilot := flyer.driver.brain as AiPilot
	assert_eq(pilot.base_profile.resource_path, AiProfile.PATHS[&"civilian_armed"])
	var seen: Array[String] = []
	var fired: bool = false
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < 16.0:
		# The raider keeps its place astern whatever the Flyer does: a pursuer it cannot shake.
		raider.ship.global_position = flyer.ship.global_position + Vector3(0.0, 0.0, 800.0)
		raider.ship.linear_velocity = flyer.ship.linear_velocity
		await get_tree().physics_frame
		var now: String = String(pilot.describe().get("behaviour", ""))
		if seen.is_empty() or seen.back() != now:
			seen.append(now)
		fired = fired or int(scene.sim.core.bolt_count()) > 0
	gut.p("the Flyer's behaviours: %s" % [seen])
	assert_has(seen, "retreat", "it runs first")
	assert_has(seen, "attack", "then turns on the raider it could not shake")
	assert_lt(seen.find("retreat"), seen.find("attack"), "in that order")
	assert_true(fired, "and fires its plasma guns")
	await scene.free_scene(get_tree())
