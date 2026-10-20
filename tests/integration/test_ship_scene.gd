extends GutTest
## The ship scene headless (architecture §3, §6.4, §7.4; M1-T10 done-when): every part present, the GDGS hull node
## loaded and the fallback mesh hidden under `--headless`, body settings from the ShipSpec and the hardpoints,
## collision primitives, muzzles and cockpit anchor, the API Main (M1-T15) calls (commands and their edges, assist,
## reset, the camera rig wiring), `SplatStatus`, and the `ship` / `render` console entries.
##
## Hardpoints and manifest values are read from the generated files here, independently of `Hardpoints`, so a parser
## bug cannot hide in both. What the hull looks like is (H).

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const HARDPOINTS_PATH: String = "res://assets/generated/starfury_aurora/hardpoints.json"
const MANIFEST_PATH: String = "res://assets/generated/starfury_aurora/manifest.json"
const CAMERA_RIG_PATH: String = "res://src/camera/camera_rig.tscn"
const ENVIRONMENT_PATH: String = "res://src/environment/space_environment.tscn"
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh, then scripts/run_tests.sh (it imports first)"
const TOL: float = 1e-4
const SHIP_KEYS: Array[StringName] = [&"position", &"universe_position", &"velocity", &"speed", &"body_velocity",
		&"angular_rate_dps", &"assist_on", &"trim", &"pod_yaw", &"main_levels", &"retro_levels", &"mass_flow", &"fuel_kg", &"fuel_fraction"]

var world: WorldFrame
var spec: ShipSpec
var ship: Ship
var hardpoints: Dictionary
var _assist_default_backup: Variant


func before_each() -> void:
	_assist_default_backup = Settings.get_value(&"assist_default")
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	spec = load(SPEC_PATH) as ShipSpec
	hardpoints = _read_json(HARDPOINTS_PATH)
	assert_false(hardpoints.is_empty(), "hardpoints.json exists (%s)" % GEN_ASSETS_HINT)
	ship = _spawn_ship(spec, Vector3.ZERO)


func after_each() -> void:
	Settings.set_value(&"assist_default", _assist_default_backup)


func _spawn_ship(p_spec: ShipSpec, at: Vector3) -> Ship:
	var made: Ship = Ship.create(p_spec, world)
	world.spawn(made, world.to_universe(at))
	return made


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


static func _vec(value: Variant) -> Vector3:
	var a: Array = value
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _vec_tol(tol: float = TOL) -> Vector3:
	return Vector3(tol, tol, tol)


func _console(line: String) -> ConsoleResult:
	var results: Array[ConsoleResult] = DebugConsole.registry.execute(line)
	assert_eq(results.size(), 1, "one statement: " + line)
	return results[0]


func _collision_nodes(body: Node) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for child: Node in body.get_children():
		if child is CollisionShape3D:
			out.append(child as CollisionShape3D)
	return out


# --- structure ---------------------------------------------------------------------------------------------------


func test_scene_instantiates_with_every_part() -> void:
	assert_true(ship is RigidBody3D, "the ship is a RigidBody3D")
	assert_eq(ship.name, &"PlayerShip")
	assert_eq(ship.get_parent(), world, "spawned under World")
	assert_true(ship.is_in_group(WorldFrame.SHIFTABLE_GROUP), "rebased with the world")
	assert_true(ship.get_node(^"HullSplats") is GaussianSplatNode, "HullSplats is a GDGS node")
	assert_true(ship.get_node(^"HullMeshFallback") is MeshInstance3D)
	assert_true(ship.get_node(^"CockpitInterior") is MeshInstance3D)
	assert_true(ship.get_node(^"Thrusters") is Node3D, "attach point for thruster visuals (M1-T13)")
	assert_true(ship.get_node(^"Guns") is Node3D, "attach point for the cannons (M1-T13)")
	assert_true(ship.get_node(^"Targeting") is TargetingController)
	assert_true(ship.get_node(^"CockpitAnchor") is Marker3D)
	assert_eq(ship.thrusters.get_child_count(), 0, "no thruster visuals yet")


func test_splat_hull_is_present_and_the_fallback_hidden_headless() -> void:
	assert_eq(DisplayServer.get_name(), "headless", "precondition: running headless")
	assert_eq(SplatStatus.active_backend(), SplatStatus.BACKEND_HEADLESS, "headless is not 'no backend'")
	var manifest: Dictionary = _read_json(MANIFEST_PATH)
	assert_false(manifest.is_empty(), "manifest exists (%s)" % GEN_ASSETS_HINT)
	var gaussian: GaussianResource = ship.hull_splats.gaussian
	assert_not_null(gaussian, "hull splats loaded (%s)" % GEN_ASSETS_HINT)
	if gaussian != null:
		assert_eq(gaussian.point_count, int(manifest["lods"][0]["splats"]), "the starfury_aurora PLY")
	assert_true(ship.hull_splats.visible, "splats visible")
	assert_false(ship.hull_mesh_fallback.visible, "fallback hidden")
	assert_false(ship.is_fallback_mesh_active())
	assert_eq(ship.hull_splats.transform, GaussianSplatNode.get_model_orientation_correction(),
			"identity in the scene; GDGS applies its own Rz(180) on entering the tree (§9.1)")
	assert_not_null(ship.hull_mesh_fallback.mesh, "fallback mesh loaded")
	assert_not_null(ship.cockpit_interior.mesh, "cockpit interior mesh loaded")


func test_body_mass_inertia_and_centre_of_mass() -> void:
	assert_eq(ship.mass, spec.mass, "mass from the ShipSpec")
	assert_eq(ship.inertia, spec.inertia, "inertia from the ShipSpec")
	assert_eq(ship.center_of_mass_mode, RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM)
	assert_almost_eq(ship.center_of_mass, _vec(hardpoints["center_of_mass"]), _vec_tol(), "hardpoints CoM")
	assert_eq(ship.spec, spec)
	assert_eq(ship.world, world)


func test_collision_shapes_come_from_the_hardpoints() -> void:
	var entries: Array = hardpoints["collision"]
	var nodes: Array[CollisionShape3D] = _collision_nodes(ship)
	assert_eq(nodes.size(), entries.size(), "one CollisionShape3D per primitive")
	assert_eq(entries.size(), 9, "fuselage, four pods, four struts")
	for entry: Dictionary in entries:
		var label: String = entry["name"]
		var node := ship.get_node_or_null(NodePath(("Collision_" + label).to_pascal_case())) as CollisionShape3D
		assert_not_null(node, "shape for %s" % label)
		if node == null:
			continue
		assert_almost_eq(node.position, _vec(entry["position"]), _vec_tol(), "%s position" % label)
		var columns: Dictionary = entry["basis"]
		var basis: Basis = node.transform.basis
		assert_true(basis.is_conformal() and is_equal_approx(basis.determinant(), 1.0), "%s is a pure rotation" % label)
		if entry["type"] == "box":
			assert_true(node.shape is BoxShape3D, "%s is a box" % label)
			assert_almost_eq((node.shape as BoxShape3D).size, _vec(entry["size"]), _vec_tol(), "%s size" % label)
			assert_almost_eq(basis.x, _vec(columns["x"]), _vec_tol(1e-4), "%s local x" % label)
			assert_almost_eq(basis.y, _vec(columns["y"]), _vec_tol(1e-4), "%s local y" % label)
			assert_almost_eq(basis.z, _vec(columns["z"]), _vec_tol(1e-4), "%s local z" % label)
		else:
			assert_eq(entry["type"], "capsule")
			assert_true(node.shape is CapsuleShape3D, "%s is a capsule" % label)
			var capsule := node.shape as CapsuleShape3D
			assert_almost_eq(capsule.radius, float(entry["radius"]), TOL, "%s radius" % label)
			assert_almost_eq(capsule.height, float(entry["height"]), TOL, "%s height" % label)
			# Godot's capsule runs along its local Y; the hardpoints name the primitive's axis it must lie along.
			assert_almost_eq(basis.y, _vec(columns[entry["axis"]]), _vec_tol(1e-4), "%s long axis" % label)


func test_one_muzzle_marker_per_hardpoint_under_guns() -> void:
	var entries: Array = hardpoints["muzzles"]
	var muzzles: Array[Node3D] = ship.get_muzzles()
	assert_eq(muzzles.size(), entries.size(), "one marker per muzzle")
	assert_eq(entries.size(), 2, "two cannons")
	assert_eq(ship.guns.get_child_count(), entries.size(), "Guns holds only the markers")
	for i: int in entries.size():
		var entry: Dictionary = entries[i]
		var marker: Node3D = muzzles[i]
		assert_true(marker is Marker3D, "muzzle %d is a Marker3D" % i)
		assert_eq(marker.get_parent(), ship.guns)
		assert_eq(marker.name, StringName(("Muzzle_" + str(entry["name"])).to_pascal_case()))
		assert_almost_eq(marker.position, _vec(entry["position"]), _vec_tol(), "muzzle %d position" % i)
		assert_almost_eq(-marker.transform.basis.z, _vec(entry["direction"]), _vec_tol(), "muzzle %d fires down -Z" % i)
	muzzles.clear()
	assert_eq(ship.get_muzzles().size(), entries.size(), "get_muzzles hands out a copy")


func test_cockpit_anchor_and_chase_offset() -> void:
	var camera: Dictionary = hardpoints["cockpit_camera"]
	assert_almost_eq(ship.cockpit_anchor.position, _vec(camera["position"]), _vec_tol(), "eye point")
	assert_almost_eq(-ship.cockpit_anchor.transform.basis.z, _vec(camera["forward"]), _vec_tol(), "looks forward")
	assert_almost_eq(ship.cockpit_anchor.transform.basis.y, _vec(camera["up"]), _vec_tol(), "up is up")
	assert_almost_eq(ship.get_chase_offset(), _vec(hardpoints["chase_anchor"]["position"]), _vec_tol())


func test_layout_and_the_idle_output_before_the_first_tick() -> void:
	var layout: ThrusterLayout = ship.get_layout()
	assert_true(layout.valid, layout.error)
	assert_eq(layout.nozzle_count(), 2 * (hardpoints["pods"] as Array).size(), "a main and a retro per pod")
	assert_almost_eq(layout.center_of_mass, ship.center_of_mass, _vec_tol(), "lever arms about the body's CoM")
	assert_true(ship.get_hardpoints().valid)
	var out: FlightOutput = ship.get_flight_output()
	assert_not_null(out)
	assert_eq(out.nozzle_forces.size(), layout.nozzle_count(), "one entry per nozzle")
	assert_eq(out.main_levels, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), "idle main levels per pod")
	assert_eq(out.retro_levels, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), "idle retro levels per pod")
	assert_eq(out.torque_b, Vector3.ZERO)


func test_setup_again_rebuilds_without_duplicates() -> void:
	ship.setup(spec, world)
	assert_eq(_collision_nodes(ship).size(), (hardpoints["collision"] as Array).size(), "no duplicate shapes")
	assert_eq(ship.guns.get_child_count(), (hardpoints["muzzles"] as Array).size(), "no duplicate muzzles")
	assert_eq(ship.get_muzzles().size(), 2)
	assert_true(ship.get_layout().valid)


func test_missing_generated_assets_only_warn_and_the_ship_coasts() -> void:
	var ghost_spec: ShipSpec = spec.duplicate() as ShipSpec
	ghost_spec.asset_id = "no_such_ship"
	var ghost: Ship = _spawn_ship(ghost_spec, Vector3(0.0, 300.0, 0.0))
	assert_false(ghost.get_layout().valid, "no hardpoints, no layout")
	assert_false(ghost.get_hardpoints().valid)
	assert_null(ghost.hull_splats.gaussian, "no splats")
	assert_eq(_collision_nodes(ghost).size(), 0)
	assert_eq(ghost.get_muzzles().size(), 0)
	assert_eq(ghost.get_chase_offset(), Ship.DEFAULT_CHASE_OFFSET)
	await get_tree().physics_frame
	ghost.linear_velocity = Vector3(0.0, 0.0, -5.0)
	var cmd := FlightCommand.new()
	cmd.main_left = 1.0
	cmd.main_right = 1.0
	ghost.set_flight_command(cmd)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_almost_eq(ghost.linear_velocity, Vector3(0.0, 0.0, -5.0), _vec_tol(), "no thrust without a layout, still Newtonian")


# --- the API Main uses -------------------------------------------------------------------------------------------


func test_forward_and_body_frame_velocities_follow_the_basis() -> void:
	var turned := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(10.0, 0.0, 0.0))
	ship.reset_to(turned)
	assert_almost_eq(ship.forward(), Vector3(-1.0, 0.0, 0.0), _vec_tol(), "yawed 90 deg left: nose along -X")
	assert_almost_eq(ship.forward(), -ship.global_basis.z, _vec_tol())
	ship.linear_velocity = Vector3(-10.0, 0.0, 3.0)
	ship.angular_velocity = Vector3(0.5, 0.0, 0.0)
	assert_almost_eq(ship.body_velocity(), Vector3(-3.0, 0.0, -10.0), _vec_tol(), "10 m/s forward, 3 m/s left")
	assert_almost_eq(ship.body_angular_velocity(), Vector3(0.0, 0.0, 0.5), _vec_tol(), "world +X is body +Z (aft) here")


func test_reset_to_teleports_at_rest_and_clears_the_assist_state() -> void:
	ship.assist_on = true
	var cmd := FlightCommand.new()
	cmd.main_right = 1.0
	await get_tree().physics_frame
	ship.set_flight_command(cmd)
	for i: int in 20:
		await get_tree().physics_frame
	var settled_cmd: float = ship.get_flight_output().pod_yaw_cmd
	assert_lt(settled_cmd, -0.4, "RT alone: pod yaw command builds up to the left")
	var target := Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(5.0, -2.0, 40.0))
	ship.reset_to(target)
	assert_almost_eq(ship.global_position, target.origin, _vec_tol(), "teleported")
	assert_true(ship.global_basis.is_equal_approx(target.basis), "oriented")
	assert_eq(ship.linear_velocity, Vector3.ZERO, "at rest")
	assert_eq(ship.angular_velocity, Vector3.ZERO, "not spinning")
	assert_eq(ship.get_flight_output().pod_yaw_cmd, 0.0, "idle output after the reset")
	await get_tree().physics_frame
	# The smoothing restarted from zero: one tick of first-order smoothing toward the full command.
	var one_tick: float = -spec.pod_yaw_gain * (1.0 - exp(-(1.0 / Engine.physics_ticks_per_second) / spec.pod_yaw_smoothing_s))
	assert_almost_eq(ship.get_flight_output().pod_yaw_cmd, one_tick, 1e-6, "smoothed pod yaw restarted")
	assert_almost_eq(ship.global_position, target.origin, _vec_tol(0.05), "stayed where it was put")


func test_assist_defaults_to_the_setting() -> void:
	Settings.set_value(&"assist_default", false)
	var off: Ship = _spawn_ship(spec, Vector3(0.0, 200.0, 0.0))
	assert_false(off.assist_on, "assist_default = false")
	Settings.set_value(&"assist_default", true)
	var on: Ship = _spawn_ship(spec, Vector3(0.0, 400.0, 0.0))
	assert_true(on.assist_on, "assist_default = true")


func test_set_assist_emits_only_on_change() -> void:
	ship.assist_on = true
	watch_signals(ship)
	ship.assist_on = false
	ship.assist_on = false
	ship.set_assist(true)
	assert_signal_emit_count(ship, "assist_toggled", 2)
	assert_signal_emitted_with_parameters(ship, "assist_toggled", [false], 0)
	assert_signal_emitted_with_parameters(ship, "assist_toggled", [true], 1)


func test_assist_toggle_clears_the_smoothed_pod_yaw() -> void:
	ship.assist_on = true
	var cmd := FlightCommand.new()
	cmd.main_right = 1.0
	await get_tree().physics_frame
	ship.set_flight_command(cmd)
	for i: int in 20:
		await get_tree().physics_frame
	assert_lt(ship.get_flight_output().pod_yaw_cmd, -0.4, "built up")
	ship.assist_on = false
	ship.assist_on = true
	await get_tree().physics_frame
	var one_tick: float = -spec.pod_yaw_gain * (1.0 - exp(-(1.0 / Engine.physics_ticks_per_second) / spec.pod_yaw_smoothing_s))
	assert_almost_eq(ship.get_flight_output().pod_yaw_cmd, one_tick, 1e-6, "restarted from zero")


func test_toggle_assist_edge_acts_once_even_if_the_command_is_not_refreshed() -> void:
	ship.assist_on = true
	watch_signals(ship)
	var cmd := FlightCommand.new()
	cmd.toggle_assist = true
	await get_tree().physics_frame
	ship.set_flight_command(cmd)
	for i: int in 4:
		await get_tree().physics_frame
	assert_false(ship.assist_on, "toggled off")
	assert_signal_emit_count(ship, "assist_toggled", 1, "once, not every tick")
	ship.set_flight_command(cmd)  # a new edge
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(ship.assist_on, "toggled back on")
	assert_signal_emit_count(ship, "assist_toggled", 2)


func test_combat_edges_reach_targeting_once_and_fire_is_held() -> void:
	var alpha: NavBuoy = NavBuoy.create("NAV ALPHA")
	world.spawn(alpha, world.to_universe(Vector3(0.0, 0.0, -500.0)))
	var bravo: NavBuoy = NavBuoy.create("NAV BRAVO")
	world.spawn(bravo, world.to_universe(Vector3(0.0, 0.0, -900.0)))
	assert_eq(ship.targeting.selected_id(), TargetingSystem.NO_TARGET)
	var cmd := CombatCommand.new()
	cmd.target_next = true
	cmd.fire = true
	await get_tree().physics_frame
	ship.set_combat_command(cmd)
	assert_eq(ship.get_combat_command(), cmd)
	await get_tree().physics_frame
	assert_eq(ship.targeting.selected_name(), "NAV ALPHA", "target_next selected the nearest buoy")
	for i: int in 3:
		await get_tree().physics_frame
	assert_eq(ship.targeting.selected_name(), "NAV ALPHA", "a stale command does not cycle again")
	assert_false(ship.get_combat_command().target_next, "edges cleared once seen")
	assert_true(ship.get_combat_command().fire, "fire stays held")
	ship.set_combat_command(cmd)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(ship.targeting.selected_name(), "NAV BRAVO", "a new edge cycles")


func test_camera_rig_wiring_shows_the_interior_only_in_the_cockpit() -> void:
	assert_false(ship.cockpit_interior.visible, "hidden until a camera says otherwise")
	ship.set_cockpit_interior_visible(true)
	assert_true(ship.cockpit_interior.visible)
	assert_true(ship.is_cockpit_interior_visible())
	ship.set_cockpit_interior_visible(false)
	assert_false(ship.cockpit_interior.visible)

	var rig: CameraRig = (load(CAMERA_RIG_PATH) as PackedScene).instantiate() as CameraRig
	world.add_child(rig)
	rig.setup(ship, ship.cockpit_anchor, ship.get_chase_offset(), ship.set_cockpit_interior_visible)
	rig.set_mode(CameraRig.Mode.COCKPIT)
	assert_true(ship.cockpit_interior.visible, "first person: interior drawn")
	assert_almost_eq(rig.cockpit_camera.global_position, ship.cockpit_anchor.global_position, _vec_tol(1e-3),
			"the cockpit camera sits on the anchor")
	rig.set_mode(CameraRig.Mode.CHASE)
	assert_false(ship.cockpit_interior.visible, "chase: interior hidden")
	assert_eq(rig.chase_config.offset_local, ship.get_chase_offset())


func test_use_fallback_mesh_swaps_the_hull() -> void:
	ship.use_fallback_mesh(true)
	assert_true(ship.hull_mesh_fallback.visible)
	assert_false(ship.hull_splats.visible)
	assert_true(ship.is_fallback_mesh_active())
	ship.use_fallback_mesh(false)
	assert_false(ship.hull_mesh_fallback.visible)
	assert_true(ship.hull_splats.visible)


# --- console: ship -----------------------------------------------------------------------------------------------


func test_console_ship_provider_and_assist_command() -> void:
	var registry: ConsoleRegistry = DebugConsole.registry
	assert_true(registry.has_command(&"assist"), "Ship registers command 'assist'")
	var provider: ConsoleStateProvider = registry.get_provider(&"ship")
	assert_not_null(provider, "Ship registers provider 'ship'")
	assert_eq(provider.keys(), SHIP_KEYS, "the §6.4 keys")
	for key: StringName in SHIP_KEYS:
		# `fuel_kg` (M2-T14) is writable so a tank can be emptied from the console; see test_reaction_mass.gd.
		assert_eq(provider.is_writable(key), key == &"assist_on" or key == &"fuel_kg", "%s writable only if assist_on or fuel_kg" % key)
	assert_string_contains(registry.help(&"assist")[0], "assist [on|off]")

	ship.assist_on = true
	var result: ConsoleResult = _console("assist off")
	assert_true(result.ok, result.text())
	assert_eq(result.lines, PackedStringArray(["ship.assist_on = false"]))
	assert_false(ship.assist_on)
	assert_eq(_console("assist").lines, PackedStringArray(["ship.assist_on = true"]), "no argument toggles")
	assert_true(_console("set ship.assist_on false").ok)
	assert_false(ship.assist_on)
	assert_false(_console("set ship.trim 0.5").ok, "read-only key")
	assert_false(registry.resolve("ship.reset_to")["ok"], "methods are not keys")


func test_console_ship_values() -> void:
	world.rebase(Vector3(1000.0, 0.0, 0.0))  # the ship is now at local x = -1000, universe x = 0
	ship.linear_velocity = Vector3(3.0, 0.0, -4.0)
	var registry: ConsoleRegistry = DebugConsole.registry
	assert_eq(registry.format_path("ship.speed"), "ship.speed = 5.00 m/s")
	assert_eq(registry.format_path("ship.position"), "ship.position = (-1000.00, 0.00, 0.00) m")
	assert_eq(registry.format_path("ship.universe_position"), "ship.universe_position = [0.00, 0.00, 0.00] m")
	assert_eq(registry.format_path("ship.velocity"), "ship.velocity = (3.00, 0.00, -4.00) m/s")
	assert_eq(registry.format_path("ship.body_velocity"), "ship.body_velocity = (3.00, 0.00, -4.00) m/s")
	assert_eq(registry.format_path("ship.main_levels"), "ship.main_levels = {ur: 0.00, lr: 0.00, ul: 0.00, ll: 0.00}")
	assert_eq(registry.format_path("ship.trim"), "ship.trim = 0.00")
	assert_eq(registry.format_path("ship.pod_yaw"), "ship.pod_yaw = 0.00 deg/s")
	var text: String = _console("state ship").text()
	for key: StringName in SHIP_KEYS:
		assert_string_contains(text, "ship.%s = " % key)


func test_console_reads_live_flight_output() -> void:
	ship.assist_on = true
	var cmd := FlightCommand.new()
	cmd.main_right = 1.0
	await get_tree().physics_frame
	ship.set_flight_command(cmd)
	for i: int in 3:
		await get_tree().physics_frame
	var registry: ConsoleRegistry = DebugConsole.registry
	var out: FlightOutput = ship.get_flight_output()
	assert_eq(registry.read("ship.pod_yaw")["value"], out.pod_yaw_cmd * spec.rate_max.y, "pod_yaw in deg/s")
	assert_lt(float(registry.read("ship.pod_yaw")["value"]), 0.0, "RT alone: yaw left in pilot terms")
	var mains: Dictionary = registry.read("ship.main_levels")["value"]
	assert_eq(mains["ur"], out.main_levels[0])
	assert_eq(registry.read("ship.mass_flow")["value"], out.mass_flow_kg_s)
	assert_gt(float(registry.read("ship.mass_flow")["value"]), 0.0)


func test_console_entries_leave_with_the_ship() -> void:
	assert_true(DebugConsole.registry.has_provider(&"ship"))
	world.remove_child(ship)
	assert_false(DebugConsole.registry.has_provider(&"ship"), "provider unregistered on exit")
	assert_false(DebugConsole.registry.has_command(&"assist"), "command unregistered on exit")
	ship.free()
	ship = null


# --- SplatStatus -------------------------------------------------------------------------------------------------


func _add_splat_status() -> SplatStatus:
	var status := SplatStatus.new()
	status.name = "SplatStatus"
	add_child_autofree(status)
	return status


func test_splat_status_backend_ids() -> void:
	assert_eq(SplatStatus.backend_id("Compute"), SplatStatus.BACKEND_COMPUTE)
	assert_eq(SplatStatus.backend_id("Raster"), SplatStatus.BACKEND_RASTER)
	assert_false(SplatStatus.needs_fallback(SplatStatus.BACKEND_COMPUTE))
	assert_false(SplatStatus.needs_fallback(SplatStatus.BACKEND_RASTER))
	assert_false(SplatStatus.needs_fallback(SplatStatus.BACKEND_HEADLESS), "headless keeps the splat path")
	assert_true(SplatStatus.needs_fallback(SplatStatus.BACKEND_NONE), "a screen and no backend: meshes")


func test_splat_status_starts_with_splats_headless() -> void:
	var status: SplatStatus = _add_splat_status()
	assert_false(status.is_fallback_active())
	assert_false(status.is_fallback_forced())
	assert_false(ship.is_fallback_mesh_active(), "the ship keeps its splats")


func test_fallback_command_switches_ship_buoy_and_sky() -> void:
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.current = true
	var env: SpaceEnvironment = (load(ENVIRONMENT_PATH) as PackedScene).instantiate() as SpaceEnvironment
	add_child_autofree(env)
	var buoy: NavBuoy = NavBuoy.create("NAV ALPHA")
	world.spawn(buoy, world.to_universe(Vector3(0.0, 0.0, -500.0)))
	var status: SplatStatus = _add_splat_status()
	watch_signals(status)

	var result: ConsoleResult = _console("fallback on")
	assert_true(result.ok, result.text())
	assert_eq(result.lines, PackedStringArray(["render.fallback = true"]))
	assert_true(status.is_fallback_active())
	assert_true(ship.is_fallback_mesh_active(), "ship hull on the mesh")
	assert_true(ship.hull_mesh_fallback.visible)
	assert_false(ship.hull_splats.visible)
	assert_true(buoy.is_fallback_mesh_active(), "buoy on the mesh")
	assert_true(env.is_fallback_sky_active(), "panorama sky")
	assert_signal_emitted_with_parameters(status, "fallback_changed", [true])

	result = _console("fallback off")
	assert_true(result.ok, result.text())
	assert_false(ship.is_fallback_mesh_active())
	assert_true(ship.hull_splats.visible)
	assert_false(buoy.is_fallback_mesh_active())
	assert_false(env.is_fallback_sky_active())

	assert_eq(_console("fallback").lines, PackedStringArray(["render.fallback = true"]), "no argument toggles")
	assert_true(ship.is_fallback_mesh_active())
	assert_eq(status.toggle_fallback(), "", "Main's F4 toggle")
	assert_false(ship.is_fallback_mesh_active())
	assert_signal_emit_count(status, "fallback_changed", 4)


func test_forced_fallback_reaches_nodes_spawned_later() -> void:
	var status: SplatStatus = _add_splat_status()
	assert_eq(status.set_fallback(true), "")
	var late: Ship = _spawn_ship(spec, Vector3(0.0, 500.0, 0.0))
	var buoy: NavBuoy = NavBuoy.create("NAV LATE")
	world.spawn(buoy, world.to_universe(Vector3(0.0, 0.0, -800.0)))
	assert_true(late.is_fallback_mesh_active(), "a ship spawned after the switch uses the mesh")
	assert_true(late.hull_mesh_fallback.visible)
	assert_true(buoy.is_fallback_mesh_active(), "so does a buoy")
	status.set_fallback(false)
	assert_false(late.is_fallback_mesh_active())


func test_render_provider_and_entries_leave_with_the_status() -> void:
	var status: SplatStatus = _add_splat_status()
	var registry: ConsoleRegistry = DebugConsole.registry
	var provider: ConsoleStateProvider = registry.get_provider(&"render")
	assert_not_null(provider, "SplatStatus registers provider 'render'")
	var expected_keys: Array[StringName] = [&"splat_backend", &"fallback", &"fps", &"gpu"]
	assert_eq(provider.keys(), expected_keys, "the §6.4 keys")
	assert_true(provider.is_writable(&"fallback"))
	assert_false(provider.is_writable(&"splat_backend"))
	assert_true(registry.has_command(&"fallback"))
	assert_string_contains(registry.help(&"fallback")[0], "fallback [on|off]")
	assert_eq(registry.format_path("render.splat_backend"), "render.splat_backend = headless")
	assert_eq(registry.format_path("render.fallback"), "render.fallback = false")
	assert_true(registry.read("render.fps")["ok"])
	assert_true(registry.read("render.gpu")["ok"])
	remove_child(status)
	assert_false(registry.has_provider(&"render"), "provider unregistered on exit")
	assert_false(registry.has_command(&"fallback"), "command unregistered on exit")
	status.free()
