extends GutTest
## The Asimov-class liner in the real main scene (M10-T53 stage 1; the hull checklist's headless test), on its generated asset: it
## spawns from its catalogue entry under an author's name, unarmed and without a jump engine, its habitat band turning on its own
## body, each liner in its own name's band livery and bar count (Q86, Q95), and it flies on its mains and brakes on its retros, as traffic needs
## (Q85: it cruises from the gate and holds station off Babylon 5).

const TYPE: StringName = &"ea_asimov"
const SPEED_UP: float = 4.0

var main: Main
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


func before_each() -> void:
	get_tree().paused = false
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.scenario_seed = 3
	add_child_autofree(main)
	await wait_physics_frames(2)


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup


func _fly(seconds: float) -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < seconds:
		await get_tree().physics_frame
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup


func _spawn(display_name: String, ahead_m: float) -> CapitalShip:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(TYPE, Factions.EARTH_ALLIANCE, display_name, rest)
	assert_not_null(cap, "the liner is generated (scripts/gen_assets.sh)")
	if cap != null:
		main.world.spawn(cap, main.world.to_universe(main.ship.global_position + Vector3(0.0, 0.0, -ahead_m)), Basis.IDENTITY)
	return cap


func test_it_spawns_named_unarmed_with_its_band_turning() -> void:
	var spawned: ConsoleResult = DebugConsole.registry.execute_tokens(["capital", "spawn", String(TYPE), "4000"])
	assert_true(spawned.ok, spawned.error)
	var flight: CapitalFlight = CapitalFlight.of(main.world)
	assert_not_null(flight)
	if flight == null or flight.ships().is_empty():
		return
	var cap: CapitalShip = flight.ships()[0]
	await wait_physics_frames(3)
	assert_eq(cap.targetable.display_name, "EAS Asimov", "the show's liner first")
	assert_eq(cap.spec.hull_max, 9000.0, "the loadout's hull points (T03)")
	assert_false(cap.can_open_jump_point(), "it travels by the gates")
	assert_eq(CapitalPropulsion.main_count(cap.layout), 4, "four engines")
	assert_eq(cap.rotors.size(), 1, "the habitat band turns on its own body")
	var rotor: CapitalRotor = cap.rotors[0]
	var a0: float = rotor.angle
	await _fly(4.0)
	assert_almost_eq(fposmod(rotor.angle - a0, TAU), rotor.spin_rad_s * 4.0, 0.05, "the band turns at its spin")
	assert_true(cap.skin_variant == 0.0, "the Asimov wears the show's green, with six bars")


func test_each_liner_wears_its_names_livery_on_both_pieces() -> void:
	var cap: CapitalShip = _spawn("EAS Heinlein", 6000.0)
	if cap == null:
		return
	assert_eq(cap.skin_variant, 2.0, "the third name: the third livery, six bars")
	var hull_mesh: MeshInstance3D = cap.hull_piece.get_node("HullMesh") as MeshInstance3D
	assert_eq(float(hull_mesh.get_instance_shader_parameter(&"skin_variant")), 2.0)
	var material: Material = hull_mesh.mesh.surface_get_material(0) if hull_mesh.mesh != null else null
	assert_true(material is ShaderMaterial and (material as ShaderMaterial).shader == BandTintMaterial.SHADER, "one shared band-tint material")
	var band: MeshInstance3D = cap.rotors[0].visual_pivot.get_child(0).get_node("HullMesh") as MeshInstance3D
	assert_eq(float(band.get_instance_shader_parameter(&"skin_variant")), 2.0, "the turning band in the same livery")
	var band_material: ShaderMaterial = band.mesh.surface_get_material(0) as ShaderMaterial
	assert_gt(float(band_material.get_shader_parameter(&"bar_radius")), 100.0, "the band's material draws the bars")
	assert_null((material as ShaderMaterial).get_shader_parameter(&"bar_radius"), "the hull's does not")
	var eight: CapitalShip = _spawn("EAS Clarke", 9000.0)
	if eight != null:
		assert_eq(eight.skin_variant, 3.0 + BandTintMaterial.MAX_LIVERIES, "the fourth name: amber, eight bars")


func test_it_flies_on_its_mains_and_brakes_on_its_retros() -> void:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = _spawn("EAS Clarke", 5000.0)
	if cap == null:
		return
	assert_gt(4.0 * cap.spec.pod_main_thrust / cap.spec.mass, 0.5, "half a metre a second squared: 120 m/s cruise in four minutes (Q85)")
	cap.set_course(Vector3.FORWARD, rest + Vector3(0.0, 0.0, -10.0))
	await _fly(25.0)
	assert_lt((cap.linear_velocity - rest).z, -8.0, "its mains brought it up toward 10 m/s")
	cap.set_course(Vector3.FORWARD, rest)
	await _fly(30.0)
	assert_lt((cap.linear_velocity - rest).length(), 1.5, "its retros stopped it: it can hold station")
	assert_gt((-cap.global_basis.z).dot(Vector3.FORWARD), 0.995, "its bow held on its heading")
