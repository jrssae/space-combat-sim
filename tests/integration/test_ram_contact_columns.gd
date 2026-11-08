extends GutTest
## The ram resolver's contact phase (M4-T34, M4-T35): the resolver reads every rigid hull's contacts in one native call over
## the core's rows and hands the tracker columns. T14's seeded melee (eight fighters flung together for 4 s, thousands of Jolt
## contacts and a dozen rams) in its own physics space gives the rams and the digest of every ship's pose, spin and hull
## that a sample per hull gave (the reference, recorded in `tests/fixtures/parity/ram_contact_columns.json` before M4-T37
## removed `perf_ram_contact_columns` and `perf_native_ram_contacts`).

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const FIXTURE: String = "ram_contact_columns"
const SETTINGS: Array[StringName] = [&"ram_damage"]

var _saved: Dictionary = {}


func before_each() -> void:
	for key: StringName in SETTINGS:
		_saved[key] = Settings.get_value(key)
	Settings.set_value(&"ram_damage", true)


func after_each() -> void:
	for key: StringName in SETTINGS:
		Settings.set_value(key, _saved[key])


# The melee of `test_fighter_melee`, in a fresh physics space: [digest, ram lines, the resolver's contact path].
func _melee() -> Array:
	var own_space := SubViewport.new()
	own_space.own_world_3d = true
	own_space.world_3d = World3D.new()
	add_child_autofree(own_space)
	var world := WorldFrame.new()
	world.name = "World"
	own_space.add_child(world)
	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	var rams := RamResolver.new()
	rams.world = world
	own_space.add_child(rams)  # leaves with this run's world, so the next run has one resolver
	var ram_lines := PackedStringArray()
	rams.ram_resolved.connect(func(info: HitInfo) -> void: ram_lines.append("ram %s<-%s dmg %.6f applied %.6f v %.6f at %s" % [
			HitResolver.name_of(info.target_id), HitResolver.name_of(info.shooter_id), info.damage, info.applied,
			info.relative_speed_mps, var_to_str(info.point)]))
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
		c.ship.reset_to(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)), at))
		c.ship.linear_velocity = -at.normalized() * rng.randf_range(15.0, 70.0)
	var lines := PackedStringArray()
	for tick: int in 240:
		await get_tree().physics_frame
		if tick % 20 == 19:
			for c: Combatant in ships:
				var s: Ship = c.ship
				lines.append("t%d %s %s %s %s %.6f" % [tick, c.display_name, var_to_str(s.global_position),
						var_to_str(s.linear_velocity), var_to_str(s.angular_velocity), c.damageable.hull.hp])
	var path: StringName = rams.contact_path()
	var source: StringName = rams.source()
	own_space.queue_free()
	await get_tree().physics_frame
	return ["\n".join(lines), ram_lines.duplicate(), path, source]


func test_the_melee_rams_the_same_with_the_contacts_in_columns() -> void:
	var recorded: Variant = ParityFixture.stored(FIXTURE, "melee_rams_from_samples")
	var columns: Array = await _melee()
	assert_eq(columns[2], &"native", "the run read the contacts over the core's rows")
	assert_not_null(recorded, "the reference melee was recorded")
	if recorded == null:
		return
	assert_eq(String(columns[3]), recorded["source"], "both gathered their hulls the same way (%s)" % columns[3])
	assert_gt((recorded["rams"] as Array).size(), 5, "the melee rams")
	assert_eq(ParityFixture.encode(columns[1]), recorded["rams"], "the same rams, in the same order, as the recording")
	assert_eq(ParityFixture.digest(columns[0]), recorded["poses"], "the same poses, spins and hulls every 20 ticks")
