extends GutTest
## The frame's per-ship work in one pass per subsystem (M4-T36, architecture §17.21): each pass gives what the per-ship callbacks
## gave on a seeded scene, and no lean ship runs a `_process` of its own.

const DT: float = 1.0 / 60.0

var world: WorldFrame
var projectiles: Node3D
var pool: ShipPool
var player: Combatant
var camera: Camera3D
var _far_backup: Variant


func before_each() -> void:
	_far_backup = Settings.get_value(&"far_ship_dot_m")
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	pool = ShipPool.new()
	pool.name = "Ships"
	world.add_child(pool)
	pool.world = world
	pool.projectiles = projectiles
	player = ShipAssembly.build(load("res://assets/ships/starfury_aurora.tres") as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: "PLAYER",
		ShipAssembly.OPT_CONSOLE_OWNER: true,
	})
	world.spawn(player.ship, world.to_universe(Vector3.ZERO))
	pool.player = player.ship
	camera = Camera3D.new()
	world.add_child(camera)
	camera.make_current()
	await get_tree().process_frame  # the passes node joins the root


func after_each() -> void:
	Settings.set_value(&"far_ship_dot_m", _far_backup)


func _passes() -> FramePasses:
	return FramePasses.of(world)


func _ships(count: int, type: StringName = ShipPool.DEFAULT_TYPE) -> Array[Combatant]:
	assert_eq(pool.prepare(type, count), count)
	var out: Array[Combatant] = []
	for i: int in count:
		var made: Combatant = pool.acquire("SHIP %d" % i, world.to_universe(Vector3(0.0, 0.0, -100.0 * float(i + 1))), Basis.IDENTITY,
				Vector3.ZERO, null, type)
		assert_not_null(made)
		out.append(made)
	return out


# --- the LOD pass ----------------------------------------------------------------------------------------------------------


func test_the_lod_pass_decides_every_ship_as_its_own_switcher_did() -> void:
	Settings.set_value(&"far_ship_dot_m", 2000.0)
	var ships: Array[Combatant] = _ships(12)
	var rng := RandomNumberGenerator.new()
	rng.seed = 36
	var expected: Dictionary = {}
	for c: Combatant in ships:
		expected[c] = false
	var mismatches: int = 0
	for step: int in 8:
		for c: Combatant in ships:
			# Around the dot distance and its return line (1 800 to 2 000 m), where the rule's memory matters.
			var distance: float = rng.randf_range(1500.0, 2400.0)
			c.ship.global_position = camera.global_position + Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized() * distance
			expected[c] = LodSwitcherMath.far_dot(camera.global_position.distance_to(c.ship.global_position), expected[c], 2000.0)
		_passes().update_lod()
		for c: Combatant in ships:
			mismatches += 0 if c.ship.is_far_dot() == expected[c] else 1
	assert_eq(mismatches, 0, "every ship, every step, as LodSwitcherMath decides from the camera's distance")


func test_the_lod_pass_never_makes_the_players_ship_a_dot_and_skips_parked_ships() -> void:
	Settings.set_value(&"far_ship_dot_m", 100.0)
	var ships: Array[Combatant] = _ships(2)
	player.ship.global_position = camera.global_position + Vector3(0.0, 0.0, -5000.0)
	ships[0].ship.global_position = camera.global_position + Vector3(0.0, 0.0, -5000.0)
	pool.release(ships[1])
	_passes().update_lod()
	assert_false(player.ship.is_far_dot(), "the player's ship is never a dot")
	assert_true(ships[0].ship.is_far_dot())
	assert_false(ships[1].ship.is_far_dot(), "a parked ship is left alone")


func test_the_lod_pass_runs_each_frame_and_the_switchers_have_no_process_of_their_own() -> void:
	Settings.set_value(&"far_ship_dot_m", 1000.0)
	var ships: Array[Combatant] = _ships(3)
	ships[2].ship.global_position = camera.global_position + Vector3(0.0, 0.0, -3000.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(ships[2].ship.is_far_dot(), "the frame's pass made it a dot")
	assert_false(ships[0].ship.is_far_dot())
	for c: Combatant in ships:
		var switcher := c.ship.get_node(^"LodSwitcher") as LodSwitcher
		assert_true(_passes().has_switcher(switcher), "registered with the pass")
		assert_false(switcher.is_processing(), "no _process of its own")
