extends GutTest
## A seeded melee (M4-T14 fix round 1, Q33): eight AI fighters flung at each other for 4 s, every one of them in Jolt contacts and
## rams. The digest of every ship's pose, spin and hull every 20 ticks plus each ram is the base's byte for byte (taken from the
## tree before the collision layers, `ce35406`), so Jolt's contact response and the ram damage between fighters are unchanged.
## If a later change moves the flight maths on purpose, take a new digest and say so in the Cycle log. M4-T31 took a new one: the
## Starfury's re-centring moved its collision boxes and centre of mass by under 2 mm (Cycle log, M4-T31).

const BASE_CONTACTS: int = 2959
const BASE_RAMS: int = 11
const BASE_DIGEST_SHA256: String = "505025d712ae53672e5a12d61eba19171e2edd41310cd02fce368a991bc7329d"


const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
var world: WorldFrame
var projectiles: Node3D
var rams: RamResolver
var ram_lines: PackedStringArray = []


func test_digest() -> void:
	Settings.set_value(&"ram_damage", true)
	# Its own physics space: Jolt's result depends on every body the space has held, so a shared space after other tests drifts.
	var own_space := SubViewport.new()
	own_space.own_world_3d = true
	own_space.world_3d = World3D.new()
	add_child_autofree(own_space)
	world = WorldFrame.new()
	world.name = "World"
	own_space.add_child(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	rams = RamResolver.new()
	rams.world = world
	add_child_autofree(rams)
	rams.ram_resolved.connect(func(info: HitInfo) -> void: ram_lines.append("ram %s<-%s dmg %.4f applied %.4f v %.4f" % [
			HitResolver.name_of(info.target_id), HitResolver.name_of(info.shooter_id), info.damage, info.applied, info.relative_speed_mps]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ships: Array[Combatant] = []
	for i: int in 8:
		var c: Combatant = ShipAssembly.build(load(SPEC_PATH) as ShipSpec, world, projectiles, {
			ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE if i % 2 == 0 or i == 5 else Factions.RAIDERS,
			ShipAssembly.OPT_DISPLAY_NAME: "F%d" % i, ShipAssembly.OPT_LEAN: true})
		world.spawn(c.ship, world.to_universe(Vector3(0.0, 0.0, 5000.0 * i)))
		ships.append(c)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for c: Combatant in ships:
		var at := Vector3(rng.randf_range(-60.0, 60.0), rng.randf_range(-30.0, 30.0), rng.randf_range(-60.0, 60.0))
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		c.ship.reset_to(Transform3D(basis, at))
		c.ship.linear_velocity = -at.normalized() * rng.randf_range(15.0, 70.0)
	var lines: PackedStringArray = []
	var contacts: int = 0
	for tick: int in 240:
		await get_tree().physics_frame
		for c: Combatant in ships:
			var st: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(c.ship.get_rid())
			if st != null:
				contacts += st.get_contact_count()
		if tick % 20 == 19:
			for c: Combatant in ships:
				var s: Ship = c.ship
				lines.append("t%d %s p %.6f %.6f %.6f v %.6f %.6f %.6f w %.6f %.6f %.6f hp %.4f %s" % [tick, c.display_name,
						s.global_position.x, s.global_position.y, s.global_position.z, s.linear_velocity.x, s.linear_velocity.y,
						s.linear_velocity.z, s.angular_velocity.x, s.angular_velocity.y, s.angular_velocity.z,
						c.damageable.hull.hp, str(c.damageable.hull.destroyed)])
	lines.append("contacts %d" % contacts)
	lines.append_array(ram_lines)
	var digest: String = "\n".join(lines) + "\n"
	var out: String = OS.get_environment("T14_DIGEST")
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(digest)
		f.close()
	assert_eq(contacts, BASE_CONTACTS, "Jolt contacts between the fighters")
	assert_eq(ram_lines.size(), BASE_RAMS, "rams")
	assert_eq(digest.sha256_text(), BASE_DIGEST_SHA256, "the whole digest")
