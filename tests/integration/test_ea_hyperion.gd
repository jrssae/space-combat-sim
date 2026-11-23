extends GutTest
## The Hyperion-class heavy cruiser in the real main scene (M10-T22; the hull checklist's headless test), on its generated asset:
## it spawns from its catalogue entry under the show's name and the next on its list, wears its name on the roof and the tower,
## flies on the native flight step, takes the player's fire on its sections (flown by the renegades, so the Starfury's guns can
## hurt it) and, when destroyed, leaves play by the destruction director's plan with its sections gone from the core. Its own
## guns wait for T14.

const TYPE: StringName = &"ea_hyperion"
const SPEED_UP: float = 4.0
const RANGE_M: float = 900.0
const RENEGADES: StringName = &"renegades"

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
	DebugConsole.flags.invulnerable = true


func after_each() -> void:
	(main.input_source as FakeInputSource).release_all()
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	DebugConsole.flags.invulnerable = false


# The Hyperion for `faction` broadside on to the player, its forward hull's flank (300 m aft of the bow guns) `range_m` ahead
# of the nose, where the bolts meet solid hull rather than the truss's gaps.
func _spawn_broadside(faction: StringName, range_m: float = RANGE_M) -> CapitalShip:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(TYPE, faction, "EAS Hyperion", rest)
	assert_not_null(cap, "the Hyperion is generated (scripts/gen_assets.sh)")
	if cap == null:
		return null
	var player: Basis = main.ship.global_basis
	var basis := Basis(player.z, player.y, -player.x)  # its starboard side toward the player
	var offset: Array = MeshAssets.read_manifest(String(TYPE)).get("centroid_offset", [0.0, 0.0, 0.0])
	var flank: Vector3 = Vector3(0.0, 0.0, 300.0) - Vector3(float(offset[0]), float(offset[1]), float(offset[2]))  # in the body frame
	var target: Vector3 = main.ship.global_position - player.z * range_m
	main.world.spawn(cap, main.world.to_universe(target - basis * flank), basis)
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


# The painted letters on `cap`'s hull (or, with `faction_marks`, the faction-only marks).
func _letters(cap: CapitalShip, faction_marks: bool = false) -> Array[HullMarkNode]:
	var out: Array[HullMarkNode] = []
	for node: Node in cap.hull_piece.get_children():
		if node is HullMarkNode and (node as HullMarkNode).only_faction.is_empty() != faction_marks:
			out.append(node)
	return out


func test_it_spawns_named_and_wears_its_name() -> void:
	var spawned: ConsoleResult = DebugConsole.registry.execute_tokens(["capital", "spawn", String(TYPE), "4000"])
	assert_true(spawned.ok, spawned.error)
	var flight: CapitalFlight = CapitalFlight.of(main.world)
	assert_not_null(flight)
	if flight == null or flight.ships().is_empty():
		return
	var cap: CapitalShip = flight.ships()[0]
	await wait_physics_frames(3)
	assert_eq(cap.targetable.display_name, "EAS Hyperion", "the show's ship first")
	assert_eq(cap.faction, Factions.EARTH_ALLIANCE)
	assert_eq(cap.capital_class, &"destroyer", "a destroyer's drive recharge and a capital's broadcast (T03)")
	assert_almost_eq(cap.targetable.broadcast_range_m, 5.0e5, 1e-3, "heard as a capital, 500 km out (Q51)")
	assert_almost_eq(cap.jump_drive.recharge_s, 90.0, 1e-6)
	assert_eq(cap.spec.hull_max, 17000.0, "the loadout's hull points (T03, Q53)")
	assert_true(cap.can_open_jump_point(), "it opens its own points (Q49)")
	assert_eq(cap.spec.propulsion, CapitalPropulsion.REACTION)
	assert_eq(CapitalPropulsion.main_count(cap.layout), 4, "three bells, the centre one listed on both sides")
	assert_true(cap.surfaces_held())
	assert_true(cap.rotors.is_empty(), "no rotating section")
	# HYPERION across the roof and on each flank of the tower, its hull number 21 on each flank of the hull, one quad a letter, and the
	# emblem on each flank of the tower as one sharp picture; no red X on a loyal ship.
	var letters: Array[HullMarkNode] = _letters(cap)
	assert_eq(letters.size(), 3 * "HYPERION".length() + 2 * "21".length() + 2, "the name three times, the hull number and the emblem on each flank")
	var emblems: Array[HullMarkNode] = letters.filter(func(n: HullMarkNode) -> bool: return String(n.name).begins_with("MarkMarkEmblem"))
	assert_eq(emblems.size(), 2, "the emblem on each flank of the tower")
	for node: HullMarkNode in emblems:
		var m := node.material_override as StandardMaterial3D
		assert_not_null(m.albedo_texture, "drawn from its own image")
		assert_true(m.emission_enabled, "lit by the lamp under it")
		assert_almost_eq((node.mesh as QuadMesh).size.x, 42.0, 0.01, "as wide as the name is long")
	var outlined: int = 0
	for node: HullMarkNode in letters:
		var tex: Texture2D = (node.material_override as StandardMaterial3D).albedo_texture
		if tex != null and tex.resource_path.ends_with("_marks_outlined.png"):
			outlined += 1
	assert_eq(outlined, "HYPERION".length() + 2 * "21".length(), "the bow's name and the hull numbers are outlined in black")
	for node: HullMarkNode in _letters(cap, true):
		assert_false(node.visible, "a loyal Hyperion wears no X")
	var spawned_again: ConsoleResult = DebugConsole.registry.execute_tokens(["capital", "spawn", String(TYPE), "9000"])
	assert_true(spawned_again.ok)
	assert_eq(flight.ships()[-1].targetable.display_name, "EAS Lexington", "the next name on the list")
	var names: PackedStringArray = ShipNames.names_for(TYPE)
	assert_between(names.size(), 20, 24, "a pool of twenty-odd names")
	assert_eq(names.slice(0, 3), PackedStringArray(["Hyperion", "Lexington", "Clarkstown"]), "the show's three first")


func test_a_renegade_hyperion_wears_the_red_xs() -> void:
	var cap: CapitalShip = CapitalShip.create(TYPE, RENEGADES, "EAS Clarkstown", main.world.rest_velocity())
	assert_not_null(cap)
	if cap == null:
		return
	main.world.spawn(cap, main.world.to_universe(main.ship.global_position + Vector3(0.0, 0.0, -9000.0)), Basis.IDENTITY)
	var xs: int = 0
	for node: HullMarkNode in _letters(cap, true):
		if node.visible:
			xs += 1
	assert_eq(xs, 3, "on the tower's flanks and the roof")


func test_it_flies_on_its_mains_and_brakes_on_its_retros() -> void:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(TYPE, Factions.EARTH_ALLIANCE, "EAS Hyperion", rest)
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
	assert_false(cap.helm.flipping, "no flip: stand-in retros at the mains")
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
	var names: Array[String] = []
	for raw: Variant in MeshAssets.read_manifest("ea_hyperion").get("sections", []):
		names.append(str((raw as Dictionary)["name"]))
	for section: String in hits:
		assert_true(names.has(section), "named by the section they hit (%s)" % section)
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
	for section: String in names:
		assert_not_null(cap.chunk_mesh(section), "a break-up chunk for %s (T11's plan)" % section)


func test_its_bay_doors_are_shut_and_roll_open_on_command() -> void:
	var cap: CapitalShip = CapitalShip.create(TYPE, Factions.EARTH_ALLIANCE, "EAS Hyperion", main.world.rest_velocity())
	assert_not_null(cap)
	if cap == null:
		return
	main.world.add_child(cap)
	assert_eq(cap.bay_doors.size(), 7, "a door for each of the six Starfury bays and the shuttle bay")
	for bay: String in cap.bay_doors:
		assert_false(cap.bay_door_open(bay), "%s is shut when idle" % bay)
	assert_true(cap.set_bay_door("bay_shuttle", true, true))
	assert_true(cap.bay_door_open("bay_shuttle"))
	assert_false(cap.bay_door_open("bay_fury_1_r"), "the others stay shut")
	assert_true(cap.set_bay_door("bay_shuttle", false, true))
	assert_false(cap.bay_door_open("bay_shuttle"))
	assert_false(cap.set_bay_door("bay_nowhere", true), "an unknown bay has no door")
	DebugConsole.registry.execute_tokens(["capital", "spawn", String(TYPE), "4000"])
	var result: ConsoleResult = DebugConsole.registry.execute_tokens(["capital", "doors", "open"])
	assert_true(result.ok, result.error)
	assert_string_contains(DebugConsole.registry.execute_tokens(["capital", "doors"]).text(), "open")
