extends GutTest
## The Nova-class dreadnought in the real main scene (M10-T23; the hull checklist's headless test), on its generated asset: it
## spawns from its catalogue entry under the show's Schwarzkopf and then the next scientist on its list, each Nova wearing its own
## name's first letter, flies on the native flight step, takes the player's fire on its sections (flown by the renegades, so the
## Starfury's guns can hurt it, and wearing their red X) and, when destroyed, leaves play by the destruction director's plan
## with its sections gone from the core. Its own guns wait for T14.

const TYPE: StringName = &"ea_nova"
const SPEED_UP: float = 4.0
const RANGE_M: float = 1000.0
const RENEGADES: StringName = &"renegades"
const HANGAR_Z: float = 690.0  # the hangar block's flank, authored metres aft of the boom's tip

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


# The Nova for `faction` broadside on to the player, its hangar block's flank `range_m` ahead of the nose.
func _spawn_broadside(faction: StringName, range_m: float = RANGE_M) -> CapitalShip:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(TYPE, faction, "EAS Schwarzkopf", rest)
	assert_not_null(cap, "the Nova is generated (scripts/gen_assets.sh)")
	if cap == null:
		return null
	var player: Basis = main.ship.global_basis
	var basis := Basis(player.z, player.y, -player.x)  # its starboard side toward the player
	var offset: Array = MeshAssets.read_manifest(String(TYPE)).get("centroid_offset", [0.0, 0.0, 0.0])
	var flank: Vector3 = Vector3(0.0, 0.0, HANGAR_Z) - Vector3(float(offset[0]), float(offset[1]), float(offset[2]))  # in the body frame
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


# The name letters on `cap`'s lower plates (or, with `faction_marks`, the faction-only marks).
func _letters(cap: CapitalShip, faction_marks: bool = false) -> Array[HullMarkNode]:
	var out: Array[HullMarkNode] = []
	for node: HullMarkNode in _marks(cap, "Initial" if not faction_marks else ""):
		if node.only_faction.is_empty() != faction_marks:
			out.append(node)
	return out


# The painted marks on `cap`'s hull whose node names hold `part` (every one for an empty `part`).
func _marks(cap: CapitalShip, part: String) -> Array[HullMarkNode]:
	var out: Array[HullMarkNode] = []
	for node: Node in cap.hull_piece.get_children():
		if node is HullMarkNode and (part.is_empty() or String(node.name).contains(part)):
			out.append(node)
	return out


# The glyph atlas cell `cap`'s letters show (all its letters show the same one).
func _cell(cap: CapitalShip) -> Vector2i:
	var letters: Array[HullMarkNode] = _letters(cap)
	assert_eq(letters.size(), 2, "a letter on each lower plate")
	if letters.is_empty():
		return Vector2i(-1, -1)
	var m: StandardMaterial3D = letters[0].material_override as StandardMaterial3D
	return Vector2i(roundi(m.uv1_offset.x * 6.0), roundi(m.uv1_offset.y * 6.0))


func test_it_spawns_named_and_two_novas_wear_their_own_letters() -> void:
	var spawned: ConsoleResult = DebugConsole.registry.execute_tokens(["capital", "spawn", String(TYPE), "4000"])
	assert_true(spawned.ok, spawned.error)
	var flight: CapitalFlight = CapitalFlight.of(main.world)
	assert_not_null(flight)
	if flight == null or flight.ships().is_empty():
		return
	var first: CapitalShip = flight.ships()[0]
	await wait_physics_frames(3)
	assert_eq(first.targetable.display_name, "EAS Schwarzkopf", "the show's Nova first")
	assert_eq(first.faction, Factions.EARTH_ALLIANCE)
	assert_eq(first.capital_class, &"dreadnought")
	assert_almost_eq(first.targetable.broadcast_range_m, 1.0e6, 1e-3, "a dreadnought is heard 1 000 km out (Q51)")
	assert_almost_eq(first.jump_drive.recharge_s, CapitalData.jump_recharge_s(&"dreadnought"), 1e-6, "a dreadnought's drive recharge")
	assert_eq(first.spec.hull_max, 36000.0, "the loadout's hull points (T03, Q53)")
	assert_true(first.can_open_jump_point(), "it opens its own points")
	assert_eq(first.spec.propulsion, CapitalPropulsion.REACTION)
	assert_eq(CapitalPropulsion.main_count(first.layout), 4, "four nacelles")
	assert_true(first.surfaces_held())
	assert_eq(first.rotors.size(), 0, "no rotating section")
	var spawned_again: ConsoleResult = DebugConsole.registry.execute_tokens(["capital", "spawn", String(TYPE), "9000"])
	assert_true(spawned_again.ok)
	var second: CapitalShip = flight.ships()[-1]
	assert_eq(second.targetable.display_name, "EAS Einstein", "the next name on the list")
	var atlas: Dictionary = first._hardpoints["mark_atlas"]
	assert_eq(_cell(first), HullMarks.cell_of("S", atlas), "the Schwarzkopf wears an S")
	assert_eq(_cell(second), HullMarks.cell_of("E", atlas), "the Einstein an E")
	var letters: Array[HullMarkNode] = _letters(first)
	if letters.size() == 2:
		assert_lt(letters[0].position.x * letters[1].position.x, 0.0, "one to each side")
		assert_lt(letters[0].position.y, -50.0, "low on the command block")


func test_its_name_and_emblem_are_painted_on_each_vertical_plate() -> void:
	var cap: CapitalShip = CapitalShip.create(TYPE, Factions.EARTH_ALLIANCE, "EAS Schwarzkopf", main.world.rest_velocity())
	assert_not_null(cap)
	if cap == null:
		return
	main.world.spawn(cap, main.world.to_universe(main.ship.global_position + Vector3(0.0, 0.0, -9000.0)), Basis.IDENTITY)
	assert_eq(_marks(cap, "MarkName").size(), 2 * "SCHWARZKOPF".length() + 4, "the whole name on each plate, on a board ringed in black (M10-T67)")
	assert_eq(_marks(cap, "Panel").size(), 2, "a light board behind each name")
	var emblems: Array[HullMarkNode] = _marks(cap, "MarkEmblem")
	assert_eq(emblems.size(), 2, "an emblem on each plate")
	if emblems.size() == 2:
		assert_lt(emblems[0].position.x * emblems[1].position.x, 0.0, "one to each side")


func test_the_red_x_marks_show_on_a_renegade_nova_only() -> void:
	var rest: Vector3 = main.world.rest_velocity()
	var shown: Dictionary = {}
	for faction: StringName in [Factions.EARTH_ALLIANCE, RENEGADES]:
		var cap: CapitalShip = CapitalShip.create(TYPE, faction, "EAS Halsey", rest)
		assert_not_null(cap)
		if cap == null:
			continue
		main.world.spawn(cap, main.world.to_universe(main.ship.global_position + Vector3(0.0, 0.0, -9000.0)), Basis.IDENTITY)
		var xs: int = 0
		for node: HullMarkNode in _letters(cap, true):
			if node.visible:
				xs += 1
		shown[faction] = xs
	assert_eq(shown.get(Factions.EARTH_ALLIANCE), 0, "a loyal Nova wears no X")
	assert_eq(shown.get(RENEGADES), 3, "a renegade one wears three: each vertical plate and the roof")


func test_it_flies_on_its_mains_and_brakes_on_its_retros() -> void:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(TYPE, Factions.EARTH_ALLIANCE, "EAS Schwarzkopf", rest)
	assert_not_null(cap)
	if cap == null:
		return
	main.world.spawn(cap, main.world.to_universe(main.ship.global_position + Vector3(0.0, 0.0, -4000.0)), Basis.IDENTITY)
	cap.set_course(Vector3.FORWARD, rest + Vector3(0.0, 0.0, -10.0))
	await _fly(25.0)
	assert_true(CapitalFlight.of(main.world).flown.has(cap), "the native step flew it")
	assert_lt((cap.linear_velocity - rest).z, -8.0, "its mains brought it up toward 10 m/s")
	cap.set_course(Vector3.FORWARD, rest)
	await _fly(30.0)
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
	assert_true(hits.has("hangar"), "on the hangar block it was aimed at (%s)" % [hits])
	var names: Array[String] = []
	for raw: Variant in MeshAssets.read_manifest(String(TYPE)).get("sections", []):
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
