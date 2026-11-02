extends GutTest
## AC30 in the real scene (M3-T21, Q23): exactly 8 `Light3D` nodes, all the rig's, before `World`; every ship level, chunk and buoy
## loads lit with records GDGS's own codec reads back as the splats' surface normals; the sky does not; the cabin light is an
## emitter in the cockpit camera only; `relight` and the knobs reach every node live; the `lights` provider. Headless, so no GPU:
## how it looks is P9 and AC35.

const RELIGHT_KEYS: Array[StringName] = [&"splat_relight", &"relight_ambient", &"relight_unlit_level", &"relight_light_gain"]

var main: Main
var rig: SplatLightRig


func before_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.waves_auto_start = false
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	rig = main.space_environment.light_rig


func after_each() -> void:
	DebugConsole.flags.invulnerable = false
	for key: StringName in RELIGHT_KEYS:
		Settings.reset(key)


func _exec(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _collect(node: Node, type: Variant, out: Array) -> Array:
	if is_instance_of(node, type):
		out.append(node)
	for child: Node in node.get_children():
		_collect(child, type, out)
	return out


func _lamp(energy: float = 2.0, at: Vector3 = Vector3(1.0, 2.0, 3.0)) -> LightEmitter:
	var emitter := LightEmitter.new("lamp", LightEmitter.PRIORITY_NOZZLE, Color(0.2, 0.4, 0.8), energy, 12.0, 0.5)
	emitter.position = at
	return emitter


# --- the eight slots ---------------------------------------------------------------------------------------------


func test_the_scene_holds_only_the_rigs_eight_lights() -> void:
	var lights: Array = _collect(main, Light3D, [])
	assert_eq(lights.size(), 8, "the key star and seven omni slots, with no explosion alive")
	var slots: Array[Light3D] = rig.slots()
	assert_eq(slots.size(), 8)
	for light: Variant in lights:
		assert_true(slots.has(light), "%s is not a slot" % (light as Node).name)


func test_the_key_star_is_slot_zero_and_the_rest_are_omni() -> void:
	var slots: Array[Light3D] = rig.slots()
	assert_eq(slots[0], main.space_environment.key_star)
	assert_true(slots[0] is DirectionalLight3D)
	for i: int in range(1, 8):
		assert_true(slots[i] is OmniLight3D)
		assert_false(slots[i].shadow_enabled)


func test_unused_slots_sit_at_energy_zero() -> void:
	for i: int in range(1, 8):
		assert_eq(rig.slots()[i].light_energy, 0.0)


func test_the_rig_comes_before_the_world_in_the_tree() -> void:
	# GDGS's walk for lights stops after 20 000 nodes: with 500 ships, a rig behind them would not be found.
	var env: int = main.space_environment.get_index()
	assert_lt(env, main.world.get_index())
	assert_true(main.space_environment.is_ancestor_of(rig))


func test_a_ship_finds_the_rig() -> void:
	assert_eq(SplatLightRig.of(main.ship), rig)


# --- emitters ----------------------------------------------------------------------------------------------------


func test_a_picked_emitter_fills_a_slot() -> void:
	var lamp := _lamp()
	rig.add_emitter(lamp)
	rig.update(Vector3.ZERO)
	var slot := rig.slots()[1] as OmniLight3D
	assert_eq(slot.global_position, Vector3(1.0, 2.0, 3.0))
	assert_eq(slot.light_energy, 2.0)
	assert_eq(slot.light_color, Color(0.2, 0.4, 0.8))
	assert_eq(slot.omni_range, 12.0)
	assert_eq(slot.omni_attenuation, 0.5)
	rig.remove_emitter(lamp)


func test_a_slot_follows_its_emitter_at_once() -> void:
	var lamp := _lamp()
	rig.add_emitter(lamp)
	rig.update(Vector3.ZERO)
	lamp.position = Vector3(-4.0, 0.0, 9.0)
	lamp.energy = 0.5
	rig.update(Vector3.ZERO)
	var slot := rig.slots()[1] as OmniLight3D
	assert_eq(slot.global_position, Vector3(-4.0, 0.0, 9.0))
	assert_eq(slot.light_energy, 0.5)
	rig.remove_emitter(lamp)


func test_a_removed_emitter_leaves_its_slot_dark() -> void:
	var lamp := _lamp()
	rig.add_emitter(lamp)
	rig.update(Vector3.ZERO)
	rig.remove_emitter(lamp)
	rig.update(Vector3.ZERO)
	assert_eq(rig.slots()[1].light_energy, 0.0)


func test_an_emitter_on_a_node_moves_with_it_and_goes_when_it_goes() -> void:
	var body := Node3D.new()
	body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(body)
	body.global_position = Vector3(10.0, 0.0, 0.0)
	var lamp := _lamp()
	lamp.anchor = body
	lamp.offset = Vector3(0.0, 1.0, 0.0)
	rig.add_emitter(lamp)
	rig.update(Vector3.ZERO)
	assert_almost_eq((rig.slots()[1] as OmniLight3D).global_position.distance_to(Vector3(10.0, 1.0, 0.0)), 0.0, 1e-4)
	body.free()
	rig.update(Vector3.ZERO)
	assert_eq(rig.slots()[1].light_energy, 0.0, "the emitter's node is gone, and so is the light")
	assert_eq(rig.candidate_count(), 0)


func test_never_more_than_eight_lights_shine() -> void:
	var emitters: Array[LightEmitter] = []
	for i: int in 30:
		emitters.append(_lamp(1.0 + i, Vector3(float(i), 0.0, 0.0)))
		rig.add_emitter(emitters[i])
	rig.update(Vector3.ZERO)
	var shining: int = 0
	for light: Light3D in rig.slots():
		shining += 1 if light.light_energy > 0.0 else 0
	assert_eq(shining, 8)
	assert_eq(_collect(main, Light3D, []).size(), 8, "no node is created for them")
	for emitter: LightEmitter in emitters:
		rig.remove_emitter(emitter)


# --- the cabin -----------------------------------------------------------------------------------------------------


func test_the_cabin_light_counts_only_in_the_cockpit_camera() -> void:
	assert_eq(rig.candidate_count(), 0, "chase camera: no cabin light")
	main.camera_rig.set_mode(CameraRig.Mode.COCKPIT)
	assert_eq(rig.candidate_count(), 1)
	rig.update(main.camera_rig.cockpit_camera.global_position)
	var picked: Array[LightEmitter] = []
	for emitter: LightEmitter in rig.picked():
		if emitter != null:
			picked.append(emitter)
	assert_eq(picked.size(), 1)
	assert_eq(picked[0].priority, LightEmitter.PRIORITY_CABIN)
	assert_eq(picked[0].energy, float(Settings.get_value(&"cockpit_light_energy")))
	var eye: Vector3 = main.ship.get_global_transform_interpolated() * main.ship.cockpit_anchor.position
	assert_lt(picked[0].position.distance_to(eye), 1.0, "just behind and above the pilot's eyes")
	assert_eq(_collect(main, Light3D, []).size(), 8, "the ship has no light node of its own")
	main.camera_rig.set_mode(CameraRig.Mode.CHASE)
	assert_eq(rig.candidate_count(), 0)


func test_a_freed_ship_takes_its_cabin_light_with_it() -> void:
	main.camera_rig.set_mode(CameraRig.Mode.COCKPIT)
	assert_eq(rig.candidate_count(), 1)
	main.camera_rig.set_mode(CameraRig.Mode.CHASE)
	var ship := Ship.create(main.ship.spec, main.world)
	main.world.spawn(ship, main.world.to_universe(Vector3(0.0, 500.0, 0.0)))
	ship.set_cockpit_interior_visible(true)
	assert_eq(rig.candidate_count(), 1)
	ship.free()
	assert_eq(rig.candidate_count(), 0)


# --- who is lit ----------------------------------------------------------------------------------------------------


func test_every_ship_level_chunk_and_buoy_is_lit_and_the_sky_is_not() -> void:
	main.debris.prepare(&"raider_fighter")
	main.debris.prepare(&"starfury_aurora")
	var nodes: Array = _collect(main, GaussianSplatNode, [])
	assert_gt(nodes.size(), 20, "the player's levels, the pools and the debris")
	var lit: int = 0
	for value: Variant in nodes:
		var node: GaussianSplatNode = value
		if node == main.space_environment.sky_splats:
			continue
		assert_true(node.relight_enabled, "%s is lit" % node.get_path())
		assert_false(node.relight_cast_shadows, "%s casts no shadow" % node.get_path())
		assert_not_null(node.lighting, "%s has records" % node.get_path())
		assert_true(node.lighting.matches_source(node.gaussian), "%s: records for its splats" % node.get_path())
		lit += 1
	assert_gt(lit, 20)
	assert_false(main.space_environment.sky_splats.relight_enabled, "stars are emitters")
	assert_null(main.space_environment.sky_splats.lighting)


func test_every_buoy_is_lit() -> void:
	var buoy := NavBuoy.create("NAV TEST")
	main.world.spawn(buoy, main.world.to_universe(Vector3(0.0, 600.0, 0.0)))
	assert_true(buoy.splats.relight_enabled)
	assert_not_null(buoy.splats.lighting)
	assert_true(buoy.splats.lighting.matches_source(buoy.splats.gaussian))
	buoy.queue_free()


func test_every_node_of_a_resource_shares_one_bake() -> void:
	# GDGS warns and uses the first node's bake when nodes of one resource disagree.
	var by_resource: Dictionary = {}
	for value: Variant in _collect(main, GaussianSplatNode, []):
		var node: GaussianSplatNode = value
		if node.gaussian == null:
			continue
		if by_resource.has(node.gaussian):
			assert_eq(node.lighting, by_resource[node.gaussian], str(node.get_path()))
		else:
			by_resource[node.gaussian] = node.lighting


# --- assigned before the tree ------------------------------------------------------------------------------------


func test_a_ship_has_its_records_before_its_splats_enter_the_tree() -> void:
	# Assigned later, each node would make GDGS re-merge every splat in the scene.
	var ship := Ship.create(main.ship.spec, main.world)
	var hull := ship.get_node(^"HullSplats") as GaussianSplatNode
	var at_entry: Array = []
	hull.tree_entered.connect(func() -> void: at_entry.append(hull.lighting))
	main.world.spawn(ship, main.world.to_universe(Vector3(0.0, 700.0, 0.0)))
	assert_eq(at_entry.size(), 1)
	assert_not_null(at_entry[0], "the records were there when the node entered")
	ship.queue_free()


func test_a_buoy_has_its_records_before_its_splats_enter_the_tree() -> void:
	var buoy := NavBuoy.create("NAV ORDER")
	var splats := buoy.get_node(^"BuoySplats") as GaussianSplatNode
	var at_entry: Array = []
	splats.tree_entered.connect(func() -> void: at_entry.append(splats.lighting))
	main.world.spawn(buoy, main.world.to_universe(Vector3(0.0, 800.0, 0.0)))
	assert_eq(at_entry.size(), 1)
	assert_not_null(at_entry[0], "the records were there when the node entered")
	buoy.queue_free()


func test_a_debris_chunk_has_its_records_before_it_enters_the_tree() -> void:
	var hardpoints: Hardpoints = Hardpoints.load_file(ShipCatalog.spec_for(&"raider_fighter").hardpoints_path())
	var entry: Dictionary = hardpoints.chunks[0]
	var chunk: DebrisChunk = DebrisChunk.create(entry, ShipSpec.ASSET_ROOT.path_join("raider_fighter"), true)
	autofree(chunk)
	assert_false(chunk.splats.is_inside_tree())
	assert_not_null(chunk.splats.lighting)
	assert_true(chunk.splats.relight_enabled)


# --- the records are the splats' surface ---------------------------------------------------------------------------


# Reads the covariance GDGS imported for a splat: its thin axis is the surface normal, so this crosses the importer's order and
# frame with GDGS's own decode of the records.
func _thin_axis_error(gaussian: GaussianResource, lighting: GaussianLightingResource, index: int) -> float:
	var base: int = index * 60
	var data: PackedFloat32Array = gaussian.point_data_float
	var cov := Basis(
		Vector3(data[base + 4], data[base + 5], data[base + 6]),
		Vector3(data[base + 5], data[base + 7], data[base + 8]),
		Vector3(data[base + 6], data[base + 8], data[base + 9]))
	var normal: Vector3 = lighting.read_splat(index)["normal"]
	var trace: float = cov.x.x + cov.y.y + cov.z.z
	return normal.dot(cov * normal) / trace


func test_records_line_up_with_what_gdgs_imported() -> void:
	# A disc 12.5x wider than thick: along its normal the variance is about 0.3 % of the trace, along a wrong axis about 50 %.
	var paths: Array[PackedStringArray] = []
	for level: int in 4:
		var dir: String = "res://assets/generated/starfury_aurora"
		var ply: String = "starfury_aurora.ply" if level == 0 else "starfury_aurora_lod%d.ply" % level
		paths.append(PackedStringArray([dir.path_join(ply), dir.path_join("starfury_aurora_lod%d.light" % level)]))
	paths.append(PackedStringArray(["res://assets/generated/raider_fighter/raider_fighter_chunk_hump.ply",
			"res://assets/generated/raider_fighter/raider_fighter_chunk_hump.light"]))
	paths.append(PackedStringArray(["res://assets/generated/nav_buoy/nav_buoy.ply", "res://assets/generated/nav_buoy/nav_buoy_lod0.light"]))
	for pair: PackedStringArray in paths:
		var gaussian := load(pair[0]) as GaussianResource
		var lighting: GaussianLightingResource = SplatLightingLoader.load_file(pair[1])
		assert_not_null(gaussian, pair[0])
		assert_not_null(lighting, pair[1])
		assert_eq(lighting.source_point_count, gaussian.point_count, pair[1])
		var worst: float = 0.0
		for i: int in 400:
			worst = maxf(worst, _thin_axis_error(gaussian, lighting, i * gaussian.point_count / 400))
		assert_lt(worst, 0.01, "%s: the normal is each splat's thin axis" % pair[1])


func test_a_buoy_barrel_faces_outwards_in_the_world() -> void:
	# The node's Rz(180) brings the PLY frame back, as the shader does with `object_linear`; the sign is what lights the right side.
	var buoy := NavBuoy.create("NAV FACING")
	main.world.spawn(buoy, main.world.to_universe(Vector3(0.0, 900.0, 0.0)))
	var splats: GaussianSplatNode = buoy.splats
	var lighting: GaussianLightingResource = splats.lighting
	var checked: int = 0
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated/nav_buoy/manifest.json"))
	var hull_splats: int = int((manifest as Dictionary)["counts"]["hull"])  # the manifest's first part, so the file's first splats
	for i: int in range(0, hull_splats, 7):
		var p: Vector3 = splats.basis * splats.gaussian.xyz[i]
		if absf(p.y) > 0.8:
			continue  # only the plain barrel, not its shoulders
		var n: Vector3 = (splats.basis * (lighting.read_splat(i)["normal"] as Vector3)).normalized()
		var radial := Vector3(p.x, 0.0, p.z).normalized()
		assert_gt(n.dot(radial), 0.9, "splat %d" % i)
		checked += 1
	assert_gt(checked, 50)
	buoy.queue_free()


# --- settings and console ------------------------------------------------------------------------------------------


func test_relight_switches_every_lit_node_and_never_the_sky() -> void:
	var lit: Array = _collect(main.world, GaussianSplatNode, [])
	assert_gt(lit.size(), 5)
	assert_true(_exec("relight off").ok)
	assert_eq(Settings.get_value(&"splat_relight"), false)
	for node: Variant in lit:
		assert_false((node as GaussianSplatNode).relight_enabled)
	assert_true(_exec("relight on").ok)
	for node: Variant in lit:
		assert_true((node as GaussianSplatNode).relight_enabled)
	assert_false(main.space_environment.sky_splats.relight_enabled)
	assert_true(_exec("relight").ok, "no argument toggles")
	assert_eq(Settings.get_value(&"splat_relight"), false)


func test_the_knobs_reach_every_lit_node_live() -> void:
	var node := main.ship.hull_splats
	Settings.set_value(&"relight_ambient", 0.5)
	Settings.set_value(&"relight_unlit_level", 0.05)
	Settings.set_value(&"relight_light_gain", 1.5)
	assert_almost_eq(node.relight_ambient.g, 0.5, 1e-5)
	assert_almost_eq(node.relight_unlit_level, 0.05, 1e-5)
	assert_almost_eq(node.relight_light_gain, 1.5, 1e-5)
	var buoys: Array = _collect(main.targets, GaussianSplatNode, [])
	for buoy: Variant in buoys:
		assert_almost_eq((buoy as GaussianSplatNode).relight_light_gain, 1.5, 1e-5)


func test_the_default_knobs_read_near_the_old_baked_brightness_and_keep_the_dark_side_legible() -> void:
	# Pins the default values only: the shader formula is recomputed here, so a change to GDGS's own factor is not caught.
	# GDGS: factor = unlit + gain * (ambient * AO + star energy * star colour * cos), multiplying the PLY colour. The baked rig gave
	# about 1.2 on a hull facing the key light and 0.36 on its belly.
	var unlit: float = Settings.get_value(&"relight_unlit_level")
	var gain: float = Settings.get_value(&"relight_light_gain")
	var ambient: float = Settings.get_value(&"relight_ambient")
	var star: float = main.space_environment.key_star.light_energy
	var dark: float = unlit + gain * ambient
	var lit: float = dark + gain * star
	assert_gt(dark, 0.2)
	assert_lt(dark, 0.4)
	assert_gt(lit, 1.0)
	assert_lt(lit, 1.4)


func test_the_lights_provider_reports_picks_candidates_and_cost() -> void:
	var lamp := _lamp()
	rig.add_emitter(lamp)
	rig.update(Vector3.ZERO)
	var picked: Variant = DebugConsole.registry.read("lights.picked")["value"]
	assert_eq(Array(picked as PackedStringArray), ["lamp"])
	assert_eq(DebugConsole.registry.read("lights.candidates")["value"], 1)
	assert_eq(DebugConsole.registry.read("lights.active")["value"], 2, "the key star and the lamp")
	assert_true(DebugConsole.registry.read("lights.cost_us")["ok"])
	assert_gte(int(DebugConsole.registry.read("lights.cost_us")["value"]), 0)
	rig.remove_emitter(lamp)
	assert_true(_exec("state lights").ok)
