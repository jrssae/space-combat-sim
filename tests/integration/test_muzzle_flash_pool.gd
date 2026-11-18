extends GutTest
## The lean ships' muzzle flashes from one pool (M4-T35, refactor finding 12; architecture §17.13): a lean ship has no
## `Marker3D` per muzzle and no `MuzzleFlash` node, its cannon fires from the hardpoints' transforms and flashes through the
## World's `MuzzleFlashPool`, which draws every live flash in one multimesh and lights the nose for `EmitterCurves.FLASH_S`.
## The player's ship keeps its markers and flash nodes. The brains' mean muzzle is the same bits from the transforms as it
## was from the markers.

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"

var world: WorldFrame
var projectiles: Node3D


func before_each() -> void:
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)


func _ship(name: String, lean: bool) -> Combatant:
	var c: Combatant = ShipAssembly.build(load(SPEC_PATH) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE, ShipAssembly.OPT_DISPLAY_NAME: name, ShipAssembly.OPT_LEAN: lean})
	world.spawn(c.ship, world.to_universe(Vector3(0.0, 0.0, -100.0 if lean else 100.0)))
	return c


func test_a_lean_ship_has_no_muzzle_markers_and_flashes_through_the_pool() -> void:
	var lean: Combatant = _ship("LEAN", true)
	var full: Combatant = _ship("FULL", false)
	await get_tree().physics_frame
	assert_eq(lean.ship.get_muzzles().size(), 0, "no marker nodes on a lean ship")
	assert_eq(lean.ship.get_muzzle_transforms().size(), 2, "its muzzles are data")
	assert_eq(full.ship.get_muzzles().size(), 2, "the full ship keeps its markers")
	assert_true(lean.cannon.flashes_pooled(), "the lean cannon flashes through the pool")
	assert_false(full.cannon.flashes_pooled(), "the full one under its markers")
	var pool: MuzzleFlashPool = MuzzleFlashPool.attach(world)
	assert_not_null(pool, "one pool under the World")
	assert_eq(pool.get_parent(), world)
	var flashes: int = 0
	for node: Node in lean.ship.find_children("*", "MuzzleFlash", true, false):
		flashes += 1
	assert_eq(flashes, 0, "no MuzzleFlash node on the lean ship")
	assert_eq(pool.active_count(), 0, "nothing flashes yet")
	lean.cannon.on_kernel_fired(1, Vector3.ZERO)
	assert_eq(pool.active_for(lean.ship), 1, "a shot flashes one muzzle")
	pool.advance(0.0)
	assert_eq(pool.drawn, 1, "drawn in the frame")
	pool.advance(0.025)
	assert_eq(pool.drawn, 1, "still drawn at 25 ms")
	pool.advance(0.03)
	assert_eq(pool.drawn, 0, "the quad is gone after 50 ms")
	assert_eq(pool.active_for(lean.ship), 1, "the light outlasts it")
	pool.advance(0.02)
	assert_eq(pool.active_for(lean.ship), 0, "and ends after FLASH_S")
	lean.cannon.on_kernel_fired(0, Vector3.ZERO)
	lean.cannon.on_kernel_fired(1, Vector3.ZERO)
	assert_eq(pool.active_for(lean.ship), 2, "a linked volley flashes both")
	lean.cannon.reset_flashes()
	assert_eq(pool.active_for(lean.ship), 0, "a reset ends them at once")


func test_a_lean_cannons_shot_leaves_where_the_marker_was() -> void:
	var lean: Combatant = _ship("LEAN", true)
	var full: Combatant = _ship("FULL", false)
	await get_tree().physics_frame
	var xf := Transform3D(Basis.from_euler(Vector3(0.3, 1.1, -0.4)), Vector3(1234.5, -67.8, 910.1))
	lean.ship.global_transform = xf
	full.ship.global_transform = xf
	var transforms: Array[Transform3D] = lean.ship.get_muzzle_transforms()
	var markers: Array[Node3D] = full.ship.get_muzzles()
	for i: int in markers.size():
		assert_eq(xf * transforms[i].origin, markers[i].global_position, "muzzle %d: the transform's origin is the marker's position, bit for bit" % i)
	# Both cannons fire on their own gates (no core here): the bolt nodes start at the same places.
	var cmd := CombatCommand.new()
	cmd.fire = true
	lean.cannon.set_combat_command(cmd)
	full.cannon.set_combat_command(cmd)
	lean.cannon.set_mode(PulseCannonGate.Mode.LINKED)
	full.cannon.set_mode(PulseCannonGate.Mode.LINKED)
	lean.cannon.step(1.0)
	full.cannon.step(1.0)
	var starts: Dictionary = {}
	for node: Node in projectiles.get_children():
		var bolt := node as Projectile
		var key: String = "lean" if bolt.shooter_id == lean.ship.get_instance_id() else "full"
		starts[key] = starts.get(key, []) + [bolt.global_position]
	assert_eq(starts["lean"], starts["full"], "the lean cannon's bolts leave where the full one's do")


func test_the_drivers_mean_muzzle_is_the_same_from_the_transforms() -> void:
	var full: Combatant = _ship("FULL", false)
	await get_tree().physics_frame
	full.ship.global_transform = Transform3D(Basis.from_euler(Vector3(-0.7, 0.2, 2.1)), Vector3(-321.0, 45.6, 7890.1))
	var from_markers := Vector3.ZERO
	for muzzle: Node3D in full.ship.get_muzzles():
		from_markers += full.ship.to_local(muzzle.global_position)
	from_markers /= float(full.ship.get_muzzles().size())
	var from_data := Vector3.ZERO
	var xf: Transform3D = full.ship.global_transform
	for muzzle: Transform3D in full.ship.get_muzzle_transforms():
		from_data += full.ship.to_local(xf * muzzle.origin)
	from_data /= float(full.ship.get_muzzle_transforms().size())
	assert_eq(from_data, from_markers, "the mean muzzle the brains aim from is the same bits either way")


func test_a_flash_ends_after_flash_s_whatever_the_pools_clock_reads() -> void:
	# The pool's clock is nonzero once any idle frame has run (the passes advance it by real frame times, and ship assembly
	# attaches the pool), so `(clock + FLASH_S) - birth` may round to a hair under FLASH_S. CI hit it as a flash that
	# outlived its time: the expiry must hold at every clock, not only at zero.
	var lean: Combatant = _ship("LEAN", true)
	await get_tree().physics_frame
	var pool: MuzzleFlashPool = MuzzleFlashPool.attach(world)
	for step: int in 400:
		pool.advance(0.00731 + 0.00013 * step)
		lean.cannon.on_kernel_fired(0, Vector3.ZERO)
		assert_eq(pool.active_for(lean.ship), 1, "step %d: the shot flashes" % step)
		pool.advance(EmitterCurves.FLASH_S)
		if pool.active_count() != 0:
			assert_eq(pool.active_count(), 0, "step %d: a flash is gone after exactly FLASH_S" % step)
			return


func test_the_pool_and_the_bolt_mesh_run_in_the_frames_passes_not_in_a_process_of_their_own() -> void:
	var lean: Combatant = _ship("LEAN", true)
	await get_tree().physics_frame
	var pool: MuzzleFlashPool = MuzzleFlashPool.attach(world)
	var passes: FramePasses = FramePasses.of(world)
	assert_not_null(passes, "the frame's passes exist")
	assert_false(pool.is_processing(), "the pool has no _process of its own (M4-T36's rule)")
	assert_true(passes.has_flash_pool(pool), "it is in the frame's passes")
	lean.cannon.on_kernel_fired(0, Vector3.ZERO)
	passes.advance_flash_pools(0.0)
	assert_eq(pool.drawn, 1, "the pass draws the flash")
	passes.advance_flash_pools(EmitterCurves.FLASH_S)
	assert_eq(pool.active_count(), 0, "and ages it out")
	var mesh := BoltMesh.new(null)
	world.add_child(mesh)
	assert_false(mesh.is_processing(), "the bolt mesh has no _process of its own")
	assert_true(passes.has_bolt_mesh(mesh), "it is in the frame's passes")
	passes.update_bolts()
	assert_eq(mesh.instances_drawn, 0, "nothing to draw without a core")
	world.remove_child(mesh)
	assert_false(passes.has_bolt_mesh(mesh), "out of the tree, out of the pass")
	mesh.free()
	world.remove_child(pool)
	assert_false(passes.has_flash_pool(pool), "the pool too")
	pool.free()
