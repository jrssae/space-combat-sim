extends GutTest
## PulseCannon, Projectile and MuzzleFlash with a plain RigidBody3D standing in for the ship and Marker3D muzzles at
## the hardpoints fixture's positions (architecture §6.3, §7.1; AC7). The Ship scene does not exist yet, so the cannon
## is wired by hand exactly as Main will: `setup(body, muzzles, projectiles_parent)` and `set_combat_command(cmd)`.
##
## Time is controlled: SimClock's own processing is switched off for each test and the clock is advanced by hand, so
## rates and lifetimes are exact. `cannon.step(now)` runs one cannon tick synchronously (no awaits between a
## spawn and the checks that read it), plus one test through the real physics loop. What the bolts, flash and
## glow look like is (H).

const FIXTURE: String = "res://tests/fixtures/hardpoints_nominal.json"
const DT: float = 1.0 / 60.0
const SPEED_MPS: float = 400.0
const LIFETIME_S: float = 4.0
const MATERIAL_DIR: String = "res://assets/materials/"

var world: WorldFrame
var projectiles_node: Node3D
var body: RigidBody3D
var muzzle_nodes: Array[Node3D] = []
var muzzle_local: Array[Vector3] = []
var cannon: PulseCannon
var cmd: CombatCommand
var fired_muzzles: Array[int] = []
var fired_times: Array[float] = []

var _saved_clock_s: float = 0.0
var _clock_was_processing: bool = true


func before_each() -> void:
	_saved_clock_s = SimClock.now()
	_clock_was_processing = SimClock.is_physics_processing()
	SimClock.set_physics_process(false)  # tests advance the clock by hand
	SimClock.reset(100.0)
	fired_muzzles.clear()
	fired_times.clear()

	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles_node = Node3D.new()
	projectiles_node.name = "Projectiles"
	world.add_child(projectiles_node)

	body = _make_body()
	body.transform = Transform3D(Basis.from_euler(Vector3(0.3, 1.2, -0.4)), Vector3(10.0, -20.0, 30.0))
	body.linear_velocity = Vector3(5.0, -3.0, 12.0)
	world.add_child(body)

	var muzzles_data: Array = _read_muzzles()
	muzzle_nodes.clear()
	muzzle_local.clear()
	for entry: Dictionary in muzzles_data:
		var local: Vector3 = _vec3(entry["position"])
		var marker := Marker3D.new()
		marker.name = "Muzzle_%s" % entry["name"]
		marker.position = local
		body.add_child(marker)
		muzzle_nodes.append(marker)
		muzzle_local.append(local)

	cannon = PulseCannon.new()
	cannon.name = "PulseCannon"
	body.add_child(cannon)
	cannon.setup(body, muzzle_nodes, projectiles_node)
	cannon.projectile_fired.connect(_on_fired)
	cannon.set_physics_process(false)  # tests call step() themselves, except the real-loop test
	cmd = CombatCommand.new()
	cannon.set_combat_command(cmd)


func after_each() -> void:
	SimClock.reset(_saved_clock_s)
	SimClock.set_physics_process(_clock_was_processing)


func _on_fired(muzzle_index: int, _projectile: Projectile) -> void:
	fired_muzzles.append(muzzle_index)
	fired_times.append(SimClock.now())


## A frictionless, gravity-free body with the ship's Newtonian settings (architecture §5.4).
func _make_body() -> RigidBody3D:
	var ship := RigidBody3D.new()
	ship.name = "StandInShip"
	ship.gravity_scale = 0.0
	ship.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	ship.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	ship.linear_damp = 0.0
	ship.angular_damp = 0.0
	ship.can_sleep = false
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	ship.add_child(shape)
	return ship


func _read_muzzles() -> Array:
	var file := FileAccess.open(FIXTURE, FileAccess.READ)
	assert_not_null(file, "fixture opens")
	var data: Variant = JSON.parse_string(file.get_as_text())
	assert_true(data is Dictionary, "fixture is a JSON object")
	var muzzles: Array = (data as Dictionary)["muzzles"]
	assert_eq(muzzles.size(), 2, "the fixture has two muzzles")
	return muzzles


static func _vec3(value: Variant) -> Vector3:
	var parts: Array = value
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


func _vec_tol(tol: float) -> Vector3:
	return Vector3(tol, tol, tol)


## One 1/60 s tick: the clock moves on, then the cannon steps at the new time.
func _tick() -> void:
	SimClock.advance(DT)
	cannon.step(SimClock.now())


func _bolts() -> Array[Projectile]:
	var found: Array[Projectile] = []
	for child: Node in projectiles_node.get_children():
		if child is Projectile and not child.is_queued_for_deletion():
			found.append(child as Projectile)
	return found


## One tick with `weapon_next` pressed (and the trigger as it is), then released.
func _press_weapon_next() -> void:
	cmd.weapon_next = true
	cannon.set_combat_command(cmd)
	_tick()
	cmd.weapon_next = false
	cannon.set_combat_command(cmd)


func _hold_fire_for(seconds: float) -> void:
	cmd.fire = true
	cannon.set_combat_command(cmd)
	for i: int in roundi(seconds / DT):
		_tick()


# --- materials ------------------------------------------------------------------------------------------------


func test_materials_are_unshaded_additive_and_emissive() -> void:
	for material_name: String in ["thruster_glow", "projectile", "muzzle_flash"]:
		var material := load(MATERIAL_DIR + material_name + ".tres") as StandardMaterial3D
		assert_not_null(material, "%s.tres loads as a StandardMaterial3D" % material_name)
		if material == null:
			continue
		assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED, "%s unshaded" % material_name)
		assert_eq(material.blend_mode, BaseMaterial3D.BLEND_MODE_ADD, "%s additive" % material_name)
		assert_ne(material.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, "%s blends" % material_name)
		assert_true(material.emission_enabled, "%s emissive" % material_name)


func test_glow_and_flash_materials_billboard_and_keep_scale() -> void:
	for material_name: String in ["thruster_glow", "muzzle_flash"]:
		var material := load(MATERIAL_DIR + material_name + ".tres") as StandardMaterial3D
		assert_eq(material.billboard_mode, BaseMaterial3D.BILLBOARD_ENABLED, material_name)
		assert_true(material.billboard_keep_scale, "%s keeps the node scale so the glow can grow" % material_name)
		assert_not_null(material.albedo_texture, "%s has its soft round falloff" % material_name)


# --- spawning (AC7) -------------------------------------------------------------------------------------------


func test_nothing_spawns_while_the_trigger_is_up() -> void:
	for i: int in 30:
		_tick()
	assert_eq(_bolts().size(), 0)
	assert_eq(fired_muzzles.size(), 0)


func test_projectile_spawns_at_the_muzzle() -> void:
	cmd.fire = true
	_tick()
	var bolts: Array[Projectile] = _bolts()
	assert_eq(bolts.size(), 1, "the first shot comes out on the press")
	assert_eq(fired_muzzles, [0] as Array[int], "ALTERNATING starts at muzzle 0")
	var expected: Vector3 = body.global_transform * muzzle_local[0]
	assert_almost_eq(bolts[0].global_position, expected, _vec_tol(1e-4), "at the muzzle's world position")
	assert_almost_eq(bolts[0].global_position, muzzle_nodes[0].global_position, _vec_tol(1e-4))
	assert_eq(bolts[0].get_parent(), projectiles_node, "under World/Projectiles, not under the ship")


func test_projectile_velocity_is_body_velocity_plus_400_forward() -> void:
	cmd.fire = true
	_tick()
	var bolt: Projectile = _bolts()[0]
	var forward: Vector3 = -body.global_basis.z
	assert_almost_eq(bolt.velocity, body.linear_velocity + forward * SPEED_MPS, _vec_tol(1e-3))
	assert_almost_eq((bolt.velocity - body.linear_velocity).length(), SPEED_MPS, 1e-3, "400 m/s relative to the shooter")
	assert_almost_eq(bolt.velocity.dot(forward), body.linear_velocity.dot(forward) + SPEED_MPS, 1e-3)
	assert_ne(body.linear_velocity, Vector3.ZERO, "the stand-in really is moving")


func test_a_stationary_ship_fires_at_400_along_its_nose() -> void:
	body.linear_velocity = Vector3.ZERO
	cmd.fire = true
	_tick()
	var bolt: Projectile = _bolts()[0]
	assert_almost_eq(bolt.velocity, -body.global_basis.z * SPEED_MPS, _vec_tol(1e-3))


func test_muzzle_speed_is_tunable() -> void:
	cannon.muzzle_speed_mps = 250.0
	cmd.fire = true
	_tick()
	var bolt: Projectile = _bolts()[0]
	assert_almost_eq((bolt.velocity - body.linear_velocity).length(), 250.0, 1e-3)


func test_projectile_is_oriented_along_its_velocity() -> void:
	cmd.fire = true
	_tick()
	var bolt: Projectile = _bolts()[0]
	assert_almost_eq(-bolt.global_basis.z, bolt.velocity.normalized(), _vec_tol(1e-4))
	assert_almost_eq(bolt.global_basis.get_scale(), Vector3.ONE, _vec_tol(1e-4), "the bolt is not stretched by the launch")


func test_projectile_is_a_thin_capsule_about_a_metre_and_a_half_long_on_its_forward_axis() -> void:
	cmd.fire = true
	_tick()
	var bolt: Projectile = _bolts()[0]
	var mesh_node := bolt.get_node("Bolt") as MeshInstance3D
	assert_not_null(mesh_node)
	assert_true(mesh_node.mesh is CapsuleMesh)
	var extent: Vector3 = (mesh_node.transform * mesh_node.get_aabb()).size
	assert_almost_eq(extent.x, 0.1, 1e-3, "0.1 m across")
	assert_almost_eq(extent.y, 0.1, 1e-3)
	assert_almost_eq(extent.z, 1.5, 1e-3, "1.5 m along -Z, the flight direction")
	var material := mesh_node.mesh.surface_get_material(0) as StandardMaterial3D
	assert_not_null(material)
	assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_eq(material.blend_mode, BaseMaterial3D.BLEND_MODE_ADD)


func test_a_zero_velocity_launch_keeps_a_valid_orientation() -> void:
	# A ship flying backwards at exactly the muzzle speed leaves a stationary bolt; its orientation must not break.
	body.linear_velocity = body.global_basis.z * SPEED_MPS
	cmd.fire = true
	_tick()
	var bolt: Projectile = _bolts()[0]
	assert_almost_eq(bolt.velocity, Vector3.ZERO, _vec_tol(1e-3))
	assert_true(bolt.global_basis.is_finite())


func test_projectile_moves_in_a_straight_line_at_its_velocity() -> void:
	cmd.fire = true
	_tick()
	var bolt: Projectile = _bolts()[0]
	bolt.set_physics_process(false)
	var start: Vector3 = bolt.global_position
	var velocity: Vector3 = bolt.velocity
	bolt._physics_process(0.5)
	assert_almost_eq(bolt.global_position, start + velocity * 0.5, _vec_tol(1e-3))
	bolt._physics_process(0.25)
	assert_almost_eq(bolt.global_position, start + velocity * 0.75, _vec_tol(1e-3))
	assert_eq(bolt.velocity, velocity, "kinematic: nothing changes the velocity")


func test_projectile_keeps_flying_after_the_ship_turns_away() -> void:
	cmd.fire = true
	_tick()
	var bolt: Projectile = _bolts()[0]
	var velocity: Vector3 = bolt.velocity
	body.global_transform = Transform3D(Basis.from_euler(Vector3(-1.0, 0.2, 2.0)), Vector3(900.0, 0.0, 0.0))
	bolt.set_physics_process(false)
	var start: Vector3 = bolt.global_position
	bolt._physics_process(1.0)
	assert_almost_eq(bolt.global_position, start + velocity, _vec_tol(1e-3), "independent of the ship once launched")


# --- lifetime -------------------------------------------------------------------------------------------------


func test_projectile_expires_four_seconds_after_launch() -> void:
	cmd.fire = true
	var launched_at: float = SimClock.now() + DT
	_tick()
	var bolt: Projectile = _bolts()[0]
	assert_almost_eq(bolt.lifetime_s, LIFETIME_S, 1e-9)
	assert_almost_eq(bolt.expires_at_s, launched_at + LIFETIME_S, 1e-9)
	assert_false(bolt.is_expired(launched_at + LIFETIME_S - 0.001))
	assert_true(bolt.is_expired(launched_at + LIFETIME_S))


func test_projectile_frees_itself_after_four_seconds_of_sim_time() -> void:
	cmd.fire = true
	_tick()
	cmd.fire = false
	var bolt: Projectile = _bolts()[0]
	SimClock.advance(LIFETIME_S - 0.5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(is_instance_valid(bolt) and not bolt.is_queued_for_deletion(), "still flying at 3.5 s")
	SimClock.advance(1.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	assert_false(is_instance_valid(bolt), "gone after 4 s")
	assert_eq(_bolts().size(), 0)


func test_lifetime_follows_the_sim_clock_not_the_wall_clock() -> void:
	cmd.fire = true
	_tick()
	cmd.fire = false
	var bolt: Projectile = _bolts()[0]
	for i: int in 10:  # plenty of real frames; the sim clock is frozen
		await get_tree().physics_frame
	assert_true(is_instance_valid(bolt) and not bolt.is_queued_for_deletion(), "a frozen clock keeps it alive")


func test_projectile_is_in_world_shiftable_and_follows_a_rebase() -> void:
	cmd.fire = true
	_tick()
	var bolt: Projectile = _bolts()[0]
	assert_true(bolt.is_in_group(WorldFrame.SHIFTABLE_GROUP))
	var before: Vector3 = bolt.global_position
	var universe_before: UniversePos = world.to_universe(before)
	world.rebase(Vector3(1000.0, -50.0, 25.0))
	assert_almost_eq(bolt.global_position, before - Vector3(1000.0, -50.0, 25.0), _vec_tol(1e-3))
	var universe_after: UniversePos = world.to_universe(bolt.global_position)
	assert_almost_eq(universe_after.distance_to(universe_before), 0.0, 1e-3, "same place in the universe")


# --- fire modes (AC7) -----------------------------------------------------------------------------------------


func test_alternating_fires_four_hertz_from_alternating_muzzles() -> void:
	_hold_fire_for(2.0)
	assert_eq(fired_muzzles, [0, 1, 0, 1, 0, 1, 0, 1] as Array[int], "8 shots in 2 s, muzzles taking turns")
	assert_eq(_bolts().size(), 8)
	for i: int in range(1, fired_times.size()):
		assert_almost_eq(fired_times[i] - fired_times[i - 1], 0.25, 1e-6, "4 Hz")


func test_alternating_shots_leave_from_their_own_muzzles() -> void:
	# The first two shots, at the ship's pose when each fired (the stand-in is not stepped by physics here).
	_hold_fire_for(0.3)
	var bolts: Array[Projectile] = _bolts()
	assert_eq(bolts.size(), 2)
	for i: int in 2:
		assert_almost_eq(bolts[i].global_position, muzzle_nodes[i].global_position, _vec_tol(1e-4), "shot %d at muzzle %d" % [i, i])
	assert_gt(bolts[0].global_position.distance_to(bolts[1].global_position), 1.0, "the muzzles are apart")


func test_linked_fires_two_hertz_from_both_muzzles_together() -> void:
	_press_weapon_next()
	_hold_fire_for(2.0)
	assert_eq(cannon.gate.mode, PulseCannonGate.Mode.LINKED)
	assert_eq(fired_muzzles, [0, 1, 0, 1, 0, 1, 0, 1] as Array[int], "4 volleys of 2 in 2 s")
	assert_eq(_bolts().size(), 8)
	var volley_times: Array[float] = []
	for i: int in range(0, fired_times.size(), 2):
		assert_almost_eq(fired_times[i], fired_times[i + 1], 1e-9, "both muzzles in the same tick")
		volley_times.append(fired_times[i])
	assert_eq(volley_times.size(), 4)
	for i: int in range(1, volley_times.size()):
		assert_almost_eq(volley_times[i] - volley_times[i - 1], 0.5, 1e-6, "2 Hz")


func test_weapon_next_cycles_modes_and_wraps() -> void:
	assert_eq(cannon.gate.mode, PulseCannonGate.Mode.ALTERNATING)
	cmd.weapon_next = true
	cannon.set_combat_command(cmd)
	_tick()
	assert_eq(cannon.gate.mode, PulseCannonGate.Mode.LINKED)
	cannon.set_combat_command(cmd)
	_tick()
	assert_eq(cannon.gate.mode, PulseCannonGate.Mode.ALTERNATING, "wraps")
	cannon.set_combat_command(cmd)
	_tick()
	assert_eq(cannon.gate.mode, PulseCannonGate.Mode.LINKED)


func test_weapon_next_is_an_edge_it_acts_once_per_command() -> void:
	cmd.weapon_next = true
	cannon.set_combat_command(cmd)
	for i: int in 5:
		_tick()  # the same command, no fresh set_combat_command
	assert_eq(cannon.gate.mode, PulseCannonGate.Mode.LINKED, "cycled once, not five times")


func test_weapon_next_without_a_command_does_nothing() -> void:
	cannon.set_combat_command(null)
	for i: int in 5:
		_tick()
	assert_eq(cannon.gate.mode, PulseCannonGate.Mode.ALTERNATING)
	assert_eq(_bolts().size(), 0)


func test_switching_mode_while_firing_never_raises_the_rate_of_fire() -> void:
	var seconds: float = 6.0
	cmd.fire = true
	for tick: int in roundi(seconds / DT):
		cmd.weapon_next = tick % 7 == 0
		cannon.set_combat_command(cmd)
		_tick()
	var ceiling: int = ceili(seconds / 0.25) + 2
	assert_true(_bolts().size() <= ceiling, "%d projectiles in %.0f s (limit %d)" % [_bolts().size(), seconds, ceiling])
	assert_gt(_bolts().size(), 16, "and it kept firing")


func test_the_cooldown_carries_over_a_mode_switch() -> void:
	cmd.fire = true
	_tick()  # ALTERNATING shot, 0.25 s cooldown
	assert_eq(_bolts().size(), 1)
	cmd.weapon_next = true
	cannon.set_combat_command(cmd)
	cmd.weapon_next = false
	for i: int in 10:  # 0.167 s
		_tick()
	assert_eq(_bolts().size(), 1, "still cooling after the switch")
	for i: int in 5:  # 0.25 s after the shot
		_tick()
	assert_eq(_bolts().size(), 3, "the linked volley comes when the old cooldown ends, not a fresh 0.5 s later")


func test_releasing_the_trigger_stops_the_fire() -> void:
	_hold_fire_for(0.5)
	var count: int = _bolts().size()
	cmd.fire = false
	cannon.set_combat_command(cmd)
	for i: int in 120:
		_tick()
	assert_eq(_bolts().size(), count)


func test_an_unwired_cannon_keeps_its_first_shot() -> void:
	var loose := PulseCannon.new()
	add_child_autofree(loose)
	loose.set_physics_process(false)
	loose.set_combat_command(cmd)
	cmd.fire = true
	loose.step(SimClock.now())  # nothing to shoot from: no spawn, and no error
	assert_eq(loose.gate.cooldown_remaining(SimClock.now()), 0.0, "the gate was not spent")


# --- through the real physics loop ----------------------------------------------------------------------------


func test_physics_process_drives_the_cannon() -> void:
	cannon.set_physics_process(true)
	cmd.fire = true
	cannon.set_combat_command(cmd)
	for i: int in 4:
		await get_tree().physics_frame
	assert_eq(_bolts().size(), 1, "the first shot came out on the first tick, then the (frozen) clock holds the cooldown")
	SimClock.advance(0.3)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(_bolts().size(), 2, "and the next once the cooldown has passed")
	assert_eq(fired_muzzles, [0, 1] as Array[int])


# --- muzzle flash ---------------------------------------------------------------------------------------------


func _flash_under(muzzle: Node3D) -> MuzzleFlash:
	for child: Node in muzzle.get_children():
		if child is MuzzleFlash:
			return child as MuzzleFlash
	return null


func test_each_muzzle_has_a_hidden_flash_quad() -> void:
	for muzzle: Node3D in muzzle_nodes:
		var flash: MuzzleFlash = _flash_under(muzzle)
		assert_not_null(flash, "flash under %s" % muzzle.name)
		assert_false(flash.visible)
		assert_false(flash.is_active())
		assert_true(flash.mesh is QuadMesh)
		assert_eq(flash.mesh.surface_get_material(0).resource_path, MATERIAL_DIR + "muzzle_flash.tres")


func test_a_shot_flashes_its_muzzle_for_50_ms() -> void:
	cmd.fire = true
	_tick()
	var flash: MuzzleFlash = _flash_under(muzzle_nodes[0])
	assert_true(flash.visible and flash.is_active())
	assert_false(_flash_under(muzzle_nodes[1]).visible, "only the muzzle that fired")
	var start_scale: float = flash.scale.x
	flash.advance(0.025)
	assert_true(flash.visible, "still showing at 25 ms")
	assert_gt(flash.scale.x, start_scale, "growing")
	flash.advance(0.024)
	assert_true(flash.visible, "still showing at 49 ms")
	flash.advance(0.002)
	assert_false(flash.visible, "gone after 50 ms")
	assert_false(flash.is_active())


func test_a_linked_volley_flashes_both_muzzles() -> void:
	cannon.gate.cycle_mode()
	cmd.fire = true
	_tick()
	for muzzle: Node3D in muzzle_nodes:
		assert_true(_flash_under(muzzle).visible)


func test_the_flash_rides_with_the_ship() -> void:
	cmd.fire = true
	_tick()
	var flash: MuzzleFlash = _flash_under(muzzle_nodes[0])
	assert_almost_eq(flash.global_position, muzzle_nodes[0].global_position, _vec_tol(1e-4))
	body.global_position += Vector3(100.0, 0.0, 0.0)
	assert_almost_eq(flash.global_position, muzzle_nodes[0].global_position, _vec_tol(1e-4), "a child of the muzzle")


func test_setup_again_replaces_the_flashes() -> void:
	cannon.setup(body, muzzle_nodes, projectiles_node)
	for muzzle: Node3D in muzzle_nodes:
		var flashes: int = 0
		for child: Node in muzzle.get_children():
			if child is MuzzleFlash:
				flashes += 1
		assert_eq(flashes, 1, "one live flash under %s" % muzzle.name)


# --- console --------------------------------------------------------------------------------------------------


func _console(line: String) -> ConsoleResult:
	var results: Array[ConsoleResult] = DebugConsole.registry.execute(line)
	assert_eq(results.size(), 1, "one statement: " + line)
	return results[0]


func test_console_provider_is_registered_with_a_writable_mode() -> void:
	var provider: ConsoleStateProvider = DebugConsole.registry.get_provider(&"weapons")
	assert_not_null(provider, "weapons provider")
	assert_eq(Array(provider.keys()), [&"mode", &"cooldown_s"])
	assert_true(provider.is_writable(&"mode"))
	assert_false(provider.is_writable(&"cooldown_s"))


func test_console_mode_reads_and_writes() -> void:
	assert_eq(_console("get weapons.mode").lines, PackedStringArray(["weapons.mode = alternating"]))
	var result: ConsoleResult = _console("set weapons.mode linked")
	assert_true(result.ok, result.text())
	assert_eq(cannon.gate.mode, PulseCannonGate.Mode.LINKED)
	assert_eq(_console("get weapons.mode").lines, PackedStringArray(["weapons.mode = linked"]))
	result = _console("set weapons.mode alternating")
	assert_true(result.ok, result.text())
	assert_eq(cannon.gate.mode, PulseCannonGate.Mode.ALTERNATING)


func test_console_mode_rejects_an_unknown_value() -> void:
	var result: ConsoleResult = _console("set weapons.mode burst")
	assert_false(result.ok)
	assert_eq(cannon.gate.mode, PulseCannonGate.Mode.ALTERNATING, "unchanged")


func test_console_mode_follows_weapon_next() -> void:
	cmd.weapon_next = true
	cannon.set_combat_command(cmd)
	_tick()
	assert_eq(_console("get weapons.mode").lines, PackedStringArray(["weapons.mode = linked"]))


func test_console_cooldown_counts_down_and_is_read_only() -> void:
	assert_eq(DebugConsole.registry.read("weapons.cooldown_s")["value"], 0.0, "ready")
	cmd.fire = true
	_tick()
	cmd.fire = false
	assert_almost_eq(float(DebugConsole.registry.read("weapons.cooldown_s")["value"]), 0.25, 1e-9)
	SimClock.advance(0.1)
	assert_almost_eq(float(DebugConsole.registry.read("weapons.cooldown_s")["value"]), 0.15, 1e-9)
	assert_string_contains(_console("get weapons.cooldown_s").lines[0], "weapons.cooldown_s = 0.15")
	var result: ConsoleResult = _console("set weapons.cooldown_s 0")
	assert_false(result.ok)
	assert_string_contains(result.error, "read-only")


func test_console_entries_leave_with_the_cannon() -> void:
	body.remove_child(cannon)
	assert_null(DebugConsole.registry.get_provider(&"weapons"), "provider unregistered on exit")
	cannon.free()
	cannon = null
