extends GutTest
## The Omega-class destroyer in the real main scene (M10-T21; the hull checklist's headless test), on its generated asset: it
## spawns from its catalogue entry under a Greek name with its rotating section on its own kinematic body, flies on the native
## flight step, takes the player's fire on its sections (flown by the renegades, so the Starfury's guns can hurt it) and, when
## destroyed, leaves play by the destruction director's plan with its sections gone from the core. Its own guns wait for T14.

const TYPE: StringName = &"ea_omega"
const SPEED_UP: float = 4.0
const DRUM_SECTIONS: Array[String] = ["drum_hub", "hangar_r", "hangar_l"]
const RANGE_M: float = 1200.0
const RENEGADES: StringName = &"renegades"

var main: Main
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


func before_all() -> void:
	CapitalHangar.stocked_on_spawn = false  # its capitals are alone here: their hangars stay empty (M10-T17)


func after_all() -> void:
	CapitalHangar.stocked_on_spawn = true


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
	DebugConsole.flags.invulnerable = true


func after_each() -> void:
	(main.input_source as FakeInputSource).release_all()
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	DebugConsole.flags.invulnerable = false


# The Omega for `faction` broadside on to the player, its rotating section's pivot `range_m` ahead of the player's nose.
func _spawn_broadside(faction: StringName, range_m: float = RANGE_M) -> CapitalShip:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(TYPE, faction, "EAS Agamemnon", rest)
	assert_not_null(cap, "the Omega is generated (scripts/gen_assets.sh)")
	if cap == null:
		return null
	var player: Basis = main.ship.global_basis
	var basis := Basis(player.z, player.y, -player.x)  # its starboard side toward the player
	var pivot: Vector3 = cap.rotors[0].pivot
	var target: Vector3 = main.ship.global_position - player.z * range_m
	main.world.spawn(cap, main.world.to_universe(target - basis * pivot), basis)
	cap.set_course(Vector3.ZERO, rest)
	return cap


func _fly(seconds: float, done: Callable = Callable()) -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < seconds:
		await get_tree().physics_frame
		if done.is_valid() and bool(done.call()):
			break
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup


# The painted letters on `cap`'s shields (or, with `faction_marks`, the faction-only marks): one node per shield, each showing `letter`'s cell of the glyph atlas.
func _letters(cap: CapitalShip, faction_marks: bool = false) -> Array[HullMarkNode]:
	var out: Array[HullMarkNode] = []
	for node: Node in cap.hull_piece.get_children():
		if node is HullMarkNode and (node as HullMarkNode).only_faction.is_empty() != faction_marks:
			out.append(node)
	return out


func test_each_omega_wears_its_names_first_letter_on_both_shields() -> void:
	var rest: Vector3 = main.world.rest_velocity()
	var atlas: Dictionary = {}
	for pair: Array in [["EAS Agamemnon", "A"], ["EAS Hector", "H"]]:
		var cap: CapitalShip = CapitalShip.create(TYPE, Factions.EARTH_ALLIANCE, pair[0], rest)
		assert_not_null(cap)
		if cap == null:
			continue
		main.world.spawn(cap, main.world.to_universe(main.ship.global_position + Vector3(0.0, 0.0, -9000.0)), Basis.IDENTITY)
		atlas = cap._hardpoints["mark_atlas"]
		var letters: Array[HullMarkNode] = _letters(cap)
		assert_eq(letters.size(), 2, "%s: a letter on each shield" % pair[0])
		var cell: Vector2i = HullMarks.cell_of(pair[1], atlas)
		for node: HullMarkNode in letters:
			var m: StandardMaterial3D = node.material_override as StandardMaterial3D
			assert_almost_eq(m.uv1_offset.x, float(cell.x) / 6.0, 1e-5, "%s shows its own letter" % pair[0])
			assert_almost_eq(m.uv1_offset.y, float(cell.y) / 6.0, 1e-5)
		assert_lt(letters[0].position.x * letters[1].position.x, 0.0, "one to each side")
		assert_lt(letters[0].position.y, -100.0, "at the bottom of the shield")
	assert_false(atlas.is_empty())


func test_the_red_x_marks_show_on_a_renegade_omega_only() -> void:
	var rest: Vector3 = main.world.rest_velocity()
	var shown: Dictionary = {}
	for faction: StringName in [Factions.EARTH_ALLIANCE, &"renegades"]:
		var cap: CapitalShip = CapitalShip.create(TYPE, faction, "EAS Hector", rest)
		assert_not_null(cap)
		if cap == null:
			continue
		main.world.spawn(cap, main.world.to_universe(main.ship.global_position + Vector3(0.0, 0.0, -9000.0)), Basis.IDENTITY)
		var xs: int = 0
		for node: HullMarkNode in _letters(cap, true):
			if node.visible:
				xs += 1
		shown[faction] = xs
	assert_eq(shown.get(Factions.EARTH_ALLIANCE), 0, "a loyal Omega wears no X")
	assert_eq(shown.get(&"renegades"), 3, "a renegade one wears three")


func test_it_spawns_named_with_its_drum_on_its_own_body() -> void:
	var spawned: ConsoleResult = DebugConsole.registry.execute_tokens(["capital", "spawn", String(TYPE), "4000"])
	assert_true(spawned.ok, spawned.error)
	var flight: CapitalFlight = CapitalFlight.of(main.world)
	assert_not_null(flight)
	if flight == null or flight.ships().is_empty():
		return
	var cap: CapitalShip = flight.ships()[0]
	await wait_physics_frames(3)
	assert_eq(cap.targetable.display_name, "EAS Agamemnon", "the first of the Omegas' Greek names")
	assert_eq(cap.faction, Factions.EARTH_ALLIANCE, "every Omega is Earth Alliance")
	assert_eq(cap.capital_class, &"destroyer")
	assert_almost_eq(cap.targetable.broadcast_range_m, 5.0e5, 1e-3, "a destroyer is heard as a capital, 500 km out (Q51)")
	assert_almost_eq(cap.jump_drive.recharge_s, 90.0, 1e-6, "a destroyer's drive recharge")
	assert_eq(cap.spec.hull_max, 30000.0, "the loadout's hull points (T03, Q53)")
	assert_true(cap.can_open_jump_point(), "it opens its own points (Q49)")
	assert_eq(cap.spec.propulsion, CapitalPropulsion.REACTION)
	assert_eq(CapitalPropulsion.main_count(cap.layout), 4, "four nacelles")
	assert_true(cap.surfaces_held())
	assert_eq(cap.rotors.size(), 1, "the rotating section turns on its own body")
	var rotor: CapitalRotor = cap.rotors[0]
	assert_true(rotor is AnimatableBody3D, "as the station's drum")
	assert_true(PhysicsServer3D.body_get_space(rotor.get_rid()).is_valid(), "in Jolt")
	var on_drum: Array[String] = []
	for entry: Dictionary in cap.sections.on("drum"):
		on_drum.append(str(entry["name"]))
	assert_eq(on_drum, DRUM_SECTIONS, "the hub and both hangars ride the drum")
	var a0: float = rotor.angle
	await _fly(4.0)
	assert_almost_eq(fposmod(rotor.angle - a0, TAU), rotor.spin_rad_s * 4.0, 0.05, "the drum turns at its spin")
	assert_lt(rotor.global_position.distance_to(rotor.pose_for(cap.global_transform, rotor.angle).origin), 0.5, "on its axle")
	var spawned_again: ConsoleResult = DebugConsole.registry.execute_tokens(["capital", "spawn", String(TYPE), "9000"])
	assert_true(spawned_again.ok)
	assert_eq(flight.ships()[-1].targetable.display_name, "EAS Achilles", "the next name on the list")


func test_it_flies_on_its_mains_and_brakes_on_its_retros() -> void:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(TYPE, Factions.EARTH_ALLIANCE, "EAS Agamemnon", rest)
	assert_not_null(cap)
	if cap == null:
		return
	main.world.spawn(cap, main.world.to_universe(main.ship.global_position + Vector3(0.0, 0.0, -4000.0)), Basis.IDENTITY)
	cap.set_course(Vector3.FORWARD, rest + Vector3(0.0, 0.0, -10.0))
	await _fly(20.0)
	assert_true(CapitalFlight.of(main.world).flown.has(cap), "the native step flew it")
	assert_lt((cap.linear_velocity - rest).z, -8.0, "its mains brought it up toward 10 m/s")
	cap.set_course(Vector3.FORWARD, rest)
	await _fly(25.0)
	assert_lt((cap.linear_velocity - rest).length(), 1.5, "its retros stopped it")
	assert_false(cap.helm_flipping(), "no flip: stand-in retros at the mains")
	assert_gt((-cap.global_basis.z).dot(Vector3.FORWARD), 0.995, "its bow held on its heading")
	assert_eq(cap.linear_damp, 0.0)
	assert_eq(cap.linear_damp_mode, RigidBody3D.DAMP_MODE_REPLACE)


func test_it_takes_fire_on_its_sections_and_dies_by_the_plan() -> void:
	var cap: CapitalShip = _spawn_broadside(RENEGADES)
	if cap == null:
		return
	await wait_physics_frames(3)
	var hull0: float = cap.damageable.hull.hp
	var hits: Array[String] = []
	cap.section_hit.connect(func(section: String, _info: HitInfo) -> void: hits.append(section))
	(main.input_source as FakeInputSource).hold(&"fire")
	await _fly(4.0, func() -> bool: return hits.size() >= 3)
	(main.input_source as FakeInputSource).release(&"fire")
	assert_gt(hits.size(), 0, "the Starfury's bolts land on the hull")
	assert_lt(cap.damageable.hull.hp, hull0, "and hurt it")
	for section: String in hits:
		assert_true(DRUM_SECTIONS.has(section), "named by the drum's section they hit (%s)" % section)
	var destroyed: Array[CapitalBody] = []
	main.director.capital_destroyed.connect(func(c: CapitalBody, _info: HitInfo) -> void: destroyed.append(c))
	assert_true(cap.damageable.kill(), "killed")
	await wait_physics_frames(2)
	assert_eq(destroyed, [cap] as Array[CapitalBody], "the destruction director took its death")
	assert_false(cap.visible, "it left play")
	assert_false(cap.can_process())
	assert_false(cap.surfaces_held(), "its sections are gone from the core")
	assert_false(CapitalFlight.of(main.world).flown.has(cap), "and from the flight step")
	assert_lt(main.director.last_blast_position.distance_to(cap.global_position), 1.0, "its blast where it died")
	for raw: Variant in MeshAssets.read_manifest("ea_omega").get("sections", []):
		var section: Dictionary = raw
		assert_not_null(cap.chunk_mesh(str(section["name"])), "a break-up chunk for %s (T11's plan)" % section["name"])
