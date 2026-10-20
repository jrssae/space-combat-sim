extends GutTest
## TargetingController with live nav buoys spawned from the real scenario through `World.spawn()` (architecture
## §6.3, §9.3, AC8): the five buoys are neutral candidates, `target_next` cycles by range and wraps, `target_ahead`
## picks the buoy nearest the nose, the readout matches the geometry, the selection clears beyond sensor range and
## survives a rebase, and the `targeting` console provider reads and writes the selection. Also the NavBuoy scene
## itself: shared splat resource (checked against the manifest, AC4), beacon, spin, drift, no collision.
##
## Expected values come from the scenario file and the live node positions, never from literals.

const MANIFEST_PATH: String = "res://assets/generated/nav_buoy/manifest.json"
const HARDPOINTS_PATH: String = "res://assets/generated/nav_buoy/hardpoints.json"
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh, then scripts/run_tests.sh (it imports first)"
const RANGE_TOL_M: float = 1e-3
const SPEED_TOL_MPS: float = 1e-3

var world: WorldFrame
var scenario: Dictionary
var buoys: Dictionary = {}  # display name -> NavBuoy
var body: RigidBody3D
var controller: TargetingController


func before_each() -> void:
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	scenario = ScenarioLoader.load(ScenarioLoader.FREE_FLIGHT_PATH)
	assert_true(scenario["ok"], scenario["error"])
	buoys = {}
	for entry: Dictionary in scenario["props"]:
		var buoy: NavBuoy = NavBuoy.create(entry["name"], entry["velocity"])
		world.spawn(buoy, entry["position"])
		buoys[entry["name"]] = buoy
	var player: Dictionary = scenario["player"]
	body = _make_ship()
	world.spawn(body, player["position"], player["basis"])
	controller = TargetingController.new()
	controller.name = "Targeting"
	body.add_child(controller)
	controller.setup(body)


## A frictionless, gravity-free body with the ship's Newtonian settings (architecture §5.4).
func _make_ship() -> RigidBody3D:
	var ship := RigidBody3D.new()
	ship.name = "PlayerShip"
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


func _next() -> CombatCommand:
	var cmd := CombatCommand.new()
	cmd.target_next = true
	return cmd


func _ahead() -> CombatCommand:
	var cmd := CombatCommand.new()
	cmd.target_ahead = true
	return cmd


func _id_of(buoy_name: String) -> int:
	return (buoys[buoy_name] as NavBuoy).targetable.get_instance_id()


## Scenario buoy names sorted by universe distance from the player start (independent of the system under test).
func _names_by_range() -> Array[String]:
	var start: UniversePos = scenario["player"]["position"]
	var entries: Array = (scenario["props"] as Array).duplicate()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return start.distance_to(a["position"]) < start.distance_to(b["position"]))
	var names: Array[String] = []
	for entry: Dictionary in entries:
		names.append(entry["name"])
	return names


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


# --- candidates --------------------------------------------------------------------------------------------------


func test_the_five_scenario_buoys_are_neutral_candidates() -> void:
	await get_tree().physics_frame
	var candidates: Array[TargetInfo] = controller.candidates()
	assert_eq(candidates.size(), 5)
	var names: Array[String] = []
	for info: TargetInfo in candidates:
		names.append(info.display_name)
		assert_eq(info.faction, &"neutral", "%s is neutral" % info.display_name)
		var buoy: NavBuoy = buoys[info.display_name]
		assert_eq(info.id, buoy.targetable.get_instance_id())
		assert_almost_eq(info.position, buoy.global_position, Vector3.ONE * RANGE_TOL_M, "%s position" % info.display_name)
		assert_eq(info.velocity, buoy.velocity, "%s velocity" % info.display_name)
	assert_eq(names, _names_by_range(), "nearest first")
	assert_eq(controller.selected_id(), TargetingSystem.NO_TARGET, "nothing selected at start")
	assert_null(controller.selected_readout())


func test_target_next_cycles_by_range_and_wraps() -> void:
	watch_signals(controller)
	var order: Array[String] = _names_by_range()
	assert_eq(order[0], "NAV ALPHA", "precondition: NAV ALPHA is the nearest buoy")
	var expected: Array[String] = order.duplicate()
	expected.append(order[0])  # wraps to the nearest
	var seen: Array[String] = []
	for i: int in expected.size():
		controller.apply(_next())
		seen.append(controller.selected_name())
		assert_signal_emitted_with_parameters(controller, "target_changed", [_id_of(seen[i])], i)
	assert_eq(seen, expected)
	assert_signal_emit_count(controller, "target_changed", expected.size())


func test_commands_without_target_edges_do_nothing() -> void:
	watch_signals(controller)
	var cmd := CombatCommand.new()
	cmd.fire = true
	cmd.weapon_next = true
	controller.apply(cmd)
	controller.apply(null)
	assert_eq(controller.selected_id(), TargetingSystem.NO_TARGET)
	assert_signal_not_emitted(controller, "target_changed")


func test_target_ahead_picks_the_buoy_nearest_the_nose() -> void:
	controller.apply(_ahead())
	assert_eq(controller.selected_name(), "NAV ALPHA", "facing -Z: NAV ALPHA is dead ahead")
	var bravo: Vector3 = (buoys["NAV BRAVO"] as NavBuoy).global_position
	body.global_basis = ScenarioLoader.basis_facing(bravo - body.global_position)
	controller.apply(_ahead())
	assert_eq(controller.selected_name(), "NAV BRAVO")
	var readout: TargetReadout = controller.selected_readout()
	assert_almost_eq(readout.angle_off_deg, 0.0, 1e-3)


func test_target_ahead_with_nothing_ahead_keeps_the_selection() -> void:
	controller.apply(_next())
	var before: int = controller.selected_id()
	# A heading with every buoy behind the beam (checked below rather than trusted).
	var away := Vector3(-0.6, -0.3, 0.74).normalized()
	for buoy: NavBuoy in buoys.values():
		assert_lt(away.dot(buoy.global_position - body.global_position), 0.0, "precondition: %s is behind" % buoy.display_name)
	body.global_basis = ScenarioLoader.basis_facing(away)
	watch_signals(controller)
	controller.apply(_ahead())
	assert_eq(controller.selected_id(), before, "unchanged")
	assert_signal_not_emitted(controller, "target_changed")


# --- readout -----------------------------------------------------------------------------------------------------


func test_readout_approaching_a_static_buoy_at_ten_metres_per_second() -> void:
	var alpha: NavBuoy = buoys["NAV ALPHA"]
	controller.apply(_next())
	assert_eq(controller.selected_name(), "NAV ALPHA")
	body.linear_velocity = (alpha.global_position - body.global_position).normalized() * 10.0
	for i: int in 5:
		await get_tree().physics_frame
	assert_gt(body.global_position.length(), 0.1, "the ship has moved")
	var readout: TargetReadout = controller.selected_readout()
	assert_not_null(readout)
	assert_almost_eq(readout.range_m, alpha.global_position.distance_to(body.global_position), RANGE_TOL_M)
	assert_almost_eq(readout.closing_mps, 10.0, SPEED_TOL_MPS, "+10 m/s closing")
	assert_almost_eq(readout.angle_off_deg, 0.0, 1e-3, "NAV ALPHA is on the nose")
	assert_eq(readout.display_name, "NAV ALPHA")
	assert_eq(readout.faction, &"neutral")


func test_the_drifting_buoy_has_a_closing_speed_at_a_static_ship() -> void:
	var delta_buoy: NavBuoy = buoys["NAV DELTA"]
	assert_ne(delta_buoy.velocity, Vector3.ZERO, "precondition: NAV DELTA drifts (scenario)")
	assert_true(controller.select_by_name("NAV DELTA"))
	await get_tree().physics_frame
	var readout: TargetReadout = controller.selected_readout()
	var los: Vector3 = delta_buoy.global_position - body.global_position
	assert_almost_eq(readout.closing_mps, -delta_buoy.velocity.dot(los) / los.length(), SPEED_TOL_MPS)
	assert_gt(readout.closing_mps, 0.0, "NAV DELTA drifts towards the start")


# --- clearing ----------------------------------------------------------------------------------------------------


func test_selection_clears_beyond_sensor_range() -> void:
	controller.apply(_next())
	var alpha: NavBuoy = buoys["NAV ALPHA"]
	watch_signals(controller)
	alpha.global_position = Vector3(0.0, 0.0, -(TargetingSystem.SENSOR_RANGE_M + 100.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(controller.selected_id(), TargetingSystem.NO_TARGET)
	assert_signal_emitted_with_parameters(controller, "target_changed", [TargetingSystem.NO_TARGET])
	assert_null(controller.selected_readout())
	assert_eq(controller.candidates().size(), 4, "out of range, out of the list")


func test_selection_clears_when_the_target_is_freed() -> void:
	controller.apply(_next())
	(buoys["NAV ALPHA"] as NavBuoy).free()
	assert_null(controller.selected_readout(), "no readout of a freed target")
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(controller.selected_id(), TargetingSystem.NO_TARGET)


func test_rebase_keeps_the_selection_and_the_readout() -> void:
	assert_true(controller.select_by_name("NAV BRAVO"))
	await get_tree().physics_frame
	var before: float = controller.selected_readout().range_m
	world.rebase(Vector3(5000.0, 0.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(controller.selected_name(), "NAV BRAVO")
	assert_almost_eq(controller.selected_readout().range_m, before, RANGE_TOL_M)


func test_targetables_under_the_ship_are_not_candidates() -> void:
	var own := Targetable.new()
	own.display_name = "SELF"
	body.add_child(own)
	controller.refresh()
	for info: TargetInfo in controller.candidates():
		assert_ne(info.display_name, "SELF")
	assert_eq(controller.candidates().size(), 5)


func test_without_a_body_nothing_happens() -> void:
	var idle := TargetingController.new()
	add_child_autofree(idle)
	idle.apply(_next())
	assert_eq(idle.selected_id(), TargetingSystem.NO_TARGET)
	assert_null(idle.selected_readout())
	assert_eq(idle.candidates().size(), 0)
	assert_false(idle.select_by_name("NAV ALPHA"))


# --- console -----------------------------------------------------------------------------------------------------


func test_console_provider_reads_and_writes_the_selection() -> void:
	var registry: ConsoleRegistry = DebugConsole.registry
	assert_true(registry.has_provider(&"targeting"))
	assert_eq(registry.format_path("targeting.selected"), "targeting.selected = none")
	assert_eq(registry.format_path("targeting.range_m"), "targeting.range_m = none")
	var candidates: PackedStringArray = registry.read("targeting.candidates")["value"]
	assert_eq(candidates.size(), 5)
	assert_true(candidates[0].begins_with("NAV ALPHA "), candidates[0])

	var results: Array[ConsoleResult] = registry.execute("set targeting.selected \"NAV BRAVO\"")
	assert_true(results[0].ok, results[0].text())
	assert_eq(controller.selected_name(), "NAV BRAVO")
	var bravo: NavBuoy = buoys["NAV BRAVO"]
	var range_now: float = registry.read("targeting.range_m")["value"]
	assert_almost_eq(range_now, bravo.global_position.distance_to(body.global_position), RANGE_TOL_M)
	assert_almost_eq(float(registry.read("targeting.closing_mps")["value"]), 0.0, SPEED_TOL_MPS)

	assert_true(registry.write_text("targeting.selected", "nav charlie").ok, "case-insensitive")
	assert_eq(controller.selected_name(), "NAV CHARLIE")
	var refused: ConsoleResult = registry.write_text("targeting.selected", "NAV ZULU")
	assert_false(refused.ok)
	assert_string_contains(refused.error, "expects one of")
	assert_eq(controller.selected_name(), "NAV CHARLIE", "a refused write changes nothing")
	assert_true(registry.write_text("targeting.selected", "none").ok)
	assert_eq(controller.selected_id(), TargetingSystem.NO_TARGET)
	assert_false(registry.write_text("targeting.range_m", "5").ok, "range_m is read-only")


func test_console_provider_leaves_with_the_controller() -> void:
	assert_true(DebugConsole.registry.has_provider(&"targeting"))
	body.remove_child(controller)
	assert_false(DebugConsole.registry.has_provider(&"targeting"), "unregistered in _exit_tree")
	controller.free()


# --- the NavBuoy scene -------------------------------------------------------------------------------------------


func test_buoys_share_one_splat_resource_that_matches_the_manifest() -> void:
	var alpha: NavBuoy = buoys["NAV ALPHA"]
	var bravo: NavBuoy = buoys["NAV BRAVO"]
	var gaussian: GaussianResource = alpha.splats.gaussian
	assert_not_null(gaussian, "nav_buoy.ply imported as a GaussianResource (%s)" % GEN_ASSETS_HINT)
	if gaussian == null:
		return
	assert_same(bravo.splats.gaussian, gaussian, "one shared resource")
	var manifest: Dictionary = _read_json(MANIFEST_PATH)
	var lods: Array = manifest.get("lods", [])
	assert_false(lods.is_empty(), "manifest lists lods")
	if lods.is_empty():
		return
	assert_eq(gaussian.point_count, int((lods[0] as Dictionary)["splats"]), "splat count matches manifest.lods[0]")
	# AC4: the manifest AABB is in the Godot frame; the resource is in the 3DGS frame (Rz 180: x and y negated).
	var lo: Array = manifest["aabb_min"]
	var hi: Array = manifest["aabb_max"]
	var expected_min := Vector3(-float(hi[0]), -float(hi[1]), float(lo[2]))
	var expected_max := Vector3(-float(lo[0]), -float(lo[1]), float(hi[2]))
	assert_almost_eq(gaussian.aabb.position, expected_min, Vector3.ONE * 0.01, "AABB min within 1 cm")
	assert_almost_eq(gaussian.aabb.end, expected_max, Vector3.ONE * 0.01, "AABB max within 1 cm")
	assert_eq(alpha.splats.transform, Transform3D(Basis.from_euler(Vector3(0.0, 0.0, -PI)), Vector3.ZERO),
			"identity in the scene; GDGS applies its own Rz(180) correction on entering the tree")


func test_beacon_sits_at_the_hardpoint_and_blinks_from_sim_clock() -> void:
	var alpha: NavBuoy = buoys["NAV ALPHA"]
	var hp: Dictionary = _read_json(HARDPOINTS_PATH)
	assert_true(hp.has("beacon"), "hardpoints.json has a beacon (%s)" % GEN_ASSETS_HINT)
	if hp.has("beacon"):
		var p: Array = hp["beacon"]["position"]
		assert_almost_eq(alpha.beacon.position, Vector3(float(p[0]), float(p[1]), float(p[2])), Vector3.ONE * 1e-5)
	# 1 Hz, lit for the first quarter of each second.
	assert_true(NavBuoy.beacon_lit(0.0))
	assert_true(NavBuoy.beacon_lit(0.24))
	assert_false(NavBuoy.beacon_lit(0.25))
	assert_false(NavBuoy.beacon_lit(0.99))
	assert_true(NavBuoy.beacon_lit(41.1))
	assert_true(NavBuoy.beacon_lit(0.9, 0.2), "the phase shifts the blink")
	# The node follows SimClock: pick phases that put "now" in the lit and the dark part of the period.
	var now: float = SimClock.now()
	alpha.blink_phase_s = 0.1 - fposmod(now, 1.0)
	alpha._process(0.0)
	assert_true(alpha.beacon.visible, "lit")
	alpha.blink_phase_s = 0.6 - fposmod(now, 1.0)
	alpha._process(0.0)
	assert_false(alpha.beacon.visible, "dark")


func test_buoys_spin_about_their_axis_and_drift() -> void:
	var delta_buoy: NavBuoy = buoys["NAV DELTA"]
	var start: Vector3 = delta_buoy.global_position
	var angle_start: float = delta_buoy.spin_angle_rad
	# Direct step: 1 s of physics turns it 10 degrees about its own +Y and drifts it by its velocity.
	delta_buoy._physics_process(1.0)
	var turned: float = fposmod(delta_buoy.spin_angle_rad - angle_start, TAU)
	assert_almost_eq(turned, deg_to_rad(NavBuoy.SPIN_DPS), 1e-9)
	assert_almost_eq(delta_buoy.global_position, start + delta_buoy.velocity, Vector3.ONE * 1e-4)
	var spun := Basis(Vector3.UP, delta_buoy.spin_angle_rad)
	assert_almost_eq(delta_buoy.basis.x, spun.x, Vector3.ONE * 1e-6, "spawned with the identity basis")
	assert_almost_eq(delta_buoy.basis.y, Vector3.UP, Vector3.ONE * 1e-6, "the spin axis is +Y")
	# Live: spin and drift advance together from the same physics deltas.
	var angle_before: float = delta_buoy.spin_angle_rad
	var pos_before: Vector3 = delta_buoy.global_position
	for i: int in 6:
		await get_tree().physics_frame
	var elapsed: float = fposmod(delta_buoy.spin_angle_rad - angle_before, TAU) / deg_to_rad(NavBuoy.SPIN_DPS)
	assert_gt(elapsed, 0.0, "the buoy keeps spinning")
	assert_almost_eq(delta_buoy.global_position, pos_before + delta_buoy.velocity * elapsed, Vector3.ONE * 1e-4)
	var alpha: NavBuoy = buoys["NAV ALPHA"]
	assert_gt(alpha.spin_angle_rad, 0.0, "static buoys spin too")
	assert_almost_eq(alpha.global_position, world.universe_to_local(scenario["props"][0]["position"]),
			Vector3.ONE * 1e-6, "a buoy without velocity stays put")


func test_buoy_scene_structure_and_groups() -> void:
	var alpha: NavBuoy = buoys["NAV ALPHA"]
	assert_true(alpha.is_in_group(WorldFrame.SHIFTABLE_GROUP))
	assert_eq(alpha.get_parent(), world, "spawned through World")
	assert_true(alpha.targetable.is_in_group(Targetable.GROUP))
	assert_false(alpha.targetable.is_in_group(WorldFrame.SHIFTABLE_GROUP), "moves with its parent, not on its own")
	assert_eq(alpha.targetable.display_name, "NAV ALPHA")
	assert_eq(alpha.targetable.faction, &"neutral")
	assert_true(alpha.splats is GaussianSplatNode)
	assert_true(alpha.beacon is MeshInstance3D)
	var nodes: Array[Node] = alpha.find_children("*", "", true, false)
	for node: Node in nodes:
		assert_false(node is CollisionObject3D or node is CollisionShape3D, "no collision: %s" % node.name)
	assert_not_null(alpha.mesh_fallback.mesh, "fallback mesh loaded (%s)" % GEN_ASSETS_HINT)
	assert_false(alpha.mesh_fallback.visible, "fallback hidden by default")
	assert_true(alpha.splats.visible)
	alpha.use_fallback_mesh(true)
	assert_true(alpha.mesh_fallback.visible)
	assert_false(alpha.splats.visible)
	assert_true(alpha.is_fallback_mesh_active())
	alpha.use_fallback_mesh(false)
	assert_true(alpha.splats.visible)
