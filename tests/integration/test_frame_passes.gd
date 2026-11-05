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
var _output: FlightOutput = null


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


# --- the far dots -----------------------------------------------------------------------------------------------------------


func test_the_far_dots_write_each_ships_drawn_place_paint_and_size_each_frame() -> void:
	Settings.set_value(&"far_ship_dot_m", 500.0)
	var ships: Array[Combatant] = _ships(6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for step: int in 4:
		for c: Combatant in ships:
			c.ship.global_position = camera.global_position + Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized() \
					* rng.randf_range(800.0, 3000.0)
			c.ship.reset_physics_interpolation()
		await get_tree().process_frame
		await get_tree().process_frame
		var dots: FarDots = FarDots.of(world)
		assert_eq(dots.dot_count(), ships.size(), "step %d: every ship a dot" % step)
		var off: int = 0
		for i: int in dots.dot_count():
			var ship: Ship = null
			for c: Combatant in ships:
				if c.ship.get_global_transform_interpolated().origin.distance_to(dots.dot_position(i)) < 1e-3:
					ship = c.ship
			if ship == null or not is_equal_approx(dots.dot_radius(i), ship.bounding_radius()) \
					or dots.dot_paint(i) != FarDots.asset_paint(ship.spec.asset_id):
				off += 1
			else:
				var t: Transform3D = dots.instance_transform(i)
				off += 0 if t.basis == Basis.IDENTITY else 1
		assert_eq(off, 0, "step %d: each dot at its ship, with its paint and its hull's size" % step)


func test_ships_turning_into_dots_together_cost_one_refresh_a_frame() -> void:
	Settings.set_value(&"far_ship_dot_m", 500.0)
	var ships: Array[Combatant] = _ships(10)
	var dots: FarDots = FarDots.attach(world)
	await get_tree().process_frame
	for c: Combatant in ships:
		c.ship.global_position = camera.global_position + Vector3(0.0, 0.0, -2000.0)
	var before: int = dots.refresh_count
	for i: int in 3:
		await get_tree().process_frame
	assert_eq(dots.dot_count(), 10)
	assert_lte(dots.refresh_count - before, 3, "one refresh a frame, not one per ship that turned (the T11 minor)")


# --- the plumes --------------------------------------------------------------------------------------------------------------



func _source() -> FlightOutput:
	return _output


func _instanced_visuals() -> ThrusterVisuals:
	var layout := ThrusterLayout.load_file("res://tests/fixtures/hardpoints_nominal.json")
	assert_true(layout.valid, layout.error)
	var made := ThrusterVisuals.new()
	made.instanced = true
	world.add_child(made)
	made.setup(layout, _source)
	return made


func _output_of(rng: RandomNumberGenerator) -> FlightOutput:
	var made := FlightOutput.new()
	made.main_levels = PackedFloat64Array([rng.randf(), rng.randf(), rng.randf(), rng.randf()])
	made.retro_levels = PackedFloat64Array([rng.randf(), 0.0, rng.randf(), 0.0])
	made.rcs_force_level = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), 0.0)
	made.rcs_torque_level = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	return made


func test_the_plumes_pass_follows_the_per_frame_smoothing_and_holds_once_settled() -> void:
	var visuals: ThrusterVisuals = _instanced_visuals()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var expected := PackedFloat64Array()
	expected.resize(visuals.glow_count())
	var worst: float = 0.0
	for phase: int in 6:
		_output = _output_of(rng) if phase % 3 != 2 else null
		var targets: PackedFloat64Array = ThrusterGlowLevels.targets(ThrusterLayout.load_file("res://tests/fixtures/hardpoints_nominal.json"), _output)
		for frame: int in 70:  # held for over a second: it settles in each phase
			visuals.frame_update(DT)
			for i: int in expected.size():
				expected[i] = ThrusterGlowLevels.smooth(expected[i], targets[i], DT, visuals.smoothing_s)
				worst = maxf(worst, absf(visuals.glow_level(i) - expected[i]))
		assert_true(visuals.is_settled(), "phase %d: held long enough to settle" % phase)
	assert_lte(worst, ThrusterVisuals.SETTLE_LEVEL, "every plume within a ten-thousandth of the per-frame smoothing")


func test_a_settled_ship_leaves_its_buffer_alone_until_the_output_changes() -> void:
	var visuals: ThrusterVisuals = _instanced_visuals()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	_output = _output_of(rng)
	for frame: int in 90:
		visuals.frame_update(DT)
	assert_true(visuals.is_settled())
	var held: Transform3D = visuals.instance_transform(0)
	var level: float = visuals.glow_level(0)
	for frame: int in 5:
		visuals.frame_update(DT)
	assert_eq(visuals.instance_transform(0), held, "nothing moves")
	_output = _output_of(rng)
	visuals.frame_update(DT)
	assert_false(visuals.is_settled(), "a new output wakes it")
	assert_ne(visuals.glow_level(0), level)


func test_a_hidden_lean_ship_leaves_the_plumes_pass_and_comes_back_when_shown() -> void:
	var ships: Array[Combatant] = _ships(1)
	var visuals: ThrusterVisuals = ships[0].thrusters
	assert_true(visuals.instanced)
	assert_true(_passes().has_plumes(visuals), "a lean ship in play")
	assert_false(visuals.is_processing(), "no _process of its own")
	ships[0].ship.set_far_dot(true)
	assert_false(_passes().has_plumes(visuals), "a far dot draws no plume")
	ships[0].ship.set_far_dot(false)
	assert_true(_passes().has_plumes(visuals))
	pool.release(ships[0])
	assert_false(_passes().has_plumes(visuals), "parked")


# --- the muzzle flashes ------------------------------------------------------------------------------------------------------


func test_a_flash_animates_in_the_pass_exactly_as_its_own_advance_did_and_leaves_when_over() -> void:
	var holder := Node3D.new()
	world.add_child(holder)
	var in_pass: MuzzleFlash = MuzzleFlash.create()
	var by_hand: MuzzleFlash = MuzzleFlash.create()
	holder.add_child(in_pass)
	holder.add_child(by_hand)
	assert_false(_passes().has_flash(in_pass), "an idle flash is not in the pass")
	in_pass.trigger()
	by_hand.trigger()
	_passes().remove_flash(by_hand)  # this one is stepped by hand, the reference
	assert_true(_passes().has_flash(in_pass), "a triggered flash joins the pass")
	var off: int = 0
	for frame: int in 8:
		_passes().advance_flashes(DT)
		by_hand.advance(DT)
		if in_pass.visible != by_hand.visible or in_pass.scale != by_hand.scale or in_pass.transparency != by_hand.transparency \
				or in_pass.light_emitter().energy != by_hand.light_emitter().energy:
			off += 1
	assert_eq(off, 0, "the same size, fade and light every frame")
	assert_true(in_pass.is_idle())
	assert_false(_passes().has_flash(in_pass), "over: it left the pass")


func test_no_lean_ship_runs_a_process_callback_of_its_own() -> void:
	var ships: Array[Combatant] = _ships(2)
	ships += _ships(1, ShipPool.ALLY_TYPE)
	await get_tree().process_frame
	for c: Combatant in ships:
		assert_true(c.ship.lean)
		var processing: PackedStringArray = PackedStringArray()
		for node: Node in [c.ship] + c.ship.find_children("*", "", true, false):
			if node.is_processing():
				processing.append(String(c.ship.get_path_to(node)))
		assert_eq(processing, PackedStringArray(), "%s: no node of the ship processes each frame (M4-T36)" % c.ship.spec.asset_id)


# --- the hit flashes ---------------------------------------------------------------------------------------------------------


func test_a_hit_flash_animates_in_the_pass_and_goes_back_to_the_pool() -> void:
	var ships: Array[Combatant] = _ships(1)
	var flash: ImpactFlash = ImpactFlash.create(Color(3.0, 1.0, 0.5), 1)
	flash.position = Vector3(0.0, 1.0, -2.0)
	ships[0].ship.add_child(flash)
	assert_true(_passes().has_impact(flash), "a showing flash is in the pass")
	var off: int = 0
	var age: float = 0.0
	while age + DT < ImpactFlash.FLASH_S:
		_passes().advance_impacts(DT)
		age += DT
		var life: float = age / ImpactFlash.FLASH_S
		if not flash.visible or not flash.scale.is_equal_approx(Vector3.ONE * (ImpactFlash.FLASH_SIZE_M * lerpf(0.6, 1.0, life))) \
				or not is_equal_approx(flash.transparency, life):
			off += 1
	assert_eq(off, 0, "it grows and fades as its own _process made it")
	_passes().advance_impacts(DT)
	assert_false(_passes().has_impact(flash), "over: out of the pass")
	assert_false(ships[0].ship.is_ancestor_of(flash), "off the ship")
	assert_eq(flash.get_parent(), _passes(), "kept in the pool")
	assert_same(ImpactFlash.create(Color.WHITE, 2), flash, "and handed out for the next hit")
	flash.free()
