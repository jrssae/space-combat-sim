extends GutTest
## Damage by what is hit on the Omega in the real main scene (M10-T08, D12.5, AC8's first clause; M10-T65, Q72): the player's
## bolts land on the section of the surface volume the core's sweep entered, and its points and the hull's go down together;
## engines lost take their nozzles off the flight step and their mounts with them; the bridge lost leaves a hulk with no power,
## which winds down and then drifts (M10-T10); the reactor at 0 blows it at once; a mount shot off hurts only itself and the hull;
## a magazine at 0 blows and the destruction director takes the ship; the console lists and hurts sections.

const TYPE: StringName = &"ea_omega"
const SPEED_UP: float = 4.0
const DRUM_SECTIONS: Array[String] = ["drum_hub", "hangar_r", "hangar_l"]
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


# The Omega for `faction` broadside on to the player, its drum's pivot `range_m` ahead of the player's nose.
func _spawn_broadside(faction: StringName, range_m: float = 1200.0) -> CapitalShip:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(TYPE, faction, "EAS Agamemnon", rest)
	assert_not_null(cap, "the Omega is generated (scripts/gen_assets.sh)")
	if cap == null:
		return null
	var player: Basis = main.ship.global_basis
	var basis := Basis(player.z, player.y, -player.x)  # its starboard side toward the player
	var target: Vector3 = main.ship.global_position - player.z * range_m
	main.world.spawn(cap, main.world.to_universe(target - basis * cap.rotors[0].pivot), basis)
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


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute_tokens(Array(line.split(" ")))


static func _section_hp(cap: CapitalShip) -> float:
	var total: float = 0.0
	for name: String in cap.damage.sections:
		total += cap.damage.sections[name].hp
	return total


func test_bolts_land_on_the_section_of_the_volume_the_core_swept() -> void:
	var cap: CapitalShip = _spawn_broadside(RENEGADES)
	if cap == null:
		return
	await wait_physics_frames(3)
	var hits: Array[HitInfo] = []
	cap.section_hit.connect(func(_section: String, info: HitInfo) -> void: hits.append(info))
	(main.input_source as FakeInputSource).hold(&"fire")
	await _fly(4.0, func() -> bool: return hits.size() >= 3)
	(main.input_source as FakeInputSource).release(&"fire")
	assert_gt(hits.size(), 0, "the Starfury's bolts land on the drum")
	for info: HitInfo in hits:
		assert_gte(info.volume, 0, "the core named the volume it entered")
		var section: String = str(info.get_meta(CapitalShip.SECTION_META))
		assert_eq(section, cap.sections.volume_sections("drum")[info.volume], "named by that volume's section")
		assert_true(DRUM_SECTIONS.has(section), section)
	var hurt: int = 0
	for name: String in DRUM_SECTIONS:
		if cap.damage.sections[name].state != CapitalSection.State.INTACT:
			hurt += 1
	assert_gt(hurt, 0, "a drum section took the points")
	assert_almost_eq(_section_hp(cap), cap.damageable.hull.hp, 0.01, "the sections hold the hull's points between them")
	assert_lt(cap.damageable.hull.hp, cap.spec.hull_max)


func test_engines_lost_take_their_nozzles_a_lost_bridge_leaves_a_drifting_hulk_and_the_reactor_blows_it() -> void:
	var cap: CapitalShip = _spawn_broadside(Factions.EARTH_ALLIANCE, 4000.0)
	if cap == null:
		return
	var disabled: Array[bool] = []
	cap.ship_disabled.connect(func() -> void: disabled.append(true))
	await wait_physics_frames(3)
	var out: ConsoleResult = _run("capital damage engine_r 2250")
	assert_true(out.ok, out.error)
	assert_eq(cap.damage.sections["engine_r"].state, CapitalSection.State.DISABLED)
	var thrust: float = CapitalPropulsion.main_count(cap.layout) * cap.flight_spec.pod_main_thrust
	assert_almost_eq(thrust, 2.0 * cap.spec.pod_main_thrust, 1.0, "the two port nacelles' thrust, as built, on the flight step")
	for i: int in cap.layout.nozzle_positions.size():
		assert_lt(cap.layout.nozzle_positions[i].x, 0.0, "every nozzle at a port nacelle")
	assert_gte(cap.flight_slot, 0, "flown again")
	assert_false(cap.mount_works("interceptor_stern_r"), "the engine's interceptor went with it")
	assert_true(cap.mount_works("interceptor_stern_l"))
	assert_almost_eq(cap.damage.thrust_fraction(), 0.5, 1e-6)
	var hull_before: float = cap.damageable.hull.hp
	out = _run("capital damage bridge 1500")
	assert_true(out.ok, out.error)
	assert_eq(cap.damage.sections["bridge"].state, CapitalSection.State.DISABLED, "the bridge is lost")
	assert_almost_eq(hull_before - cap.damageable.hull.hp, 750.0, 0.01, "a subsystem hit: the hull takes half (Q72)")
	assert_eq(disabled, [true], "no bridge: a hulk")
	assert_true(cap.damage.is_disabled)
	assert_false(cap.mount_works("beam_aft_top_r"), "no power: nothing fires")
	assert_false(cap.mount_works("plasma_top_1"))
	assert_true(cap.damage.live_bays().is_empty(), "nothing launches or docks")
	assert_eq(cap.hulk_stages.stage, HulkStages.Stage.POWER_LOST, "it winds down in stages (M10-T10)")
	await _fly(cap.hulk_stages.cold_s + 0.5, func() -> bool: return cap.hulk_stages.is_cold())
	assert_true(cap.hulk_stages.is_cold())
	assert_eq(cap.flight_spec.pod_main_thrust, 0.0, "cold: no thrust")
	assert_eq(cap.flight_command().rot, Vector3.ZERO, "the helm gives no command")
	var v0: Vector3 = cap.linear_velocity
	cap.set_course(Vector3.FORWARD, v0 + Vector3(0.0, 0.0, -20.0))
	await _fly(3.0)
	assert_lt((cap.linear_velocity - v0).length(), 0.05, "it drifts on its last motion")
	assert_false(cap.damageable.hull.destroyed)
	var destroyed: Array[CapitalBody] = []
	main.director.capital_destroyed.connect(func(c: CapitalBody, _info: HitInfo) -> void: destroyed.append(c))
	assert_true(_run("capital damage reactor 4100").ok)
	assert_false(cap.damage.is_destroyed, "the reactor still holds")
	assert_true(_run("capital damage reactor 100").ok)
	assert_eq(cap.damage.blown, "reactor", "the reactor at 0 blows it at once (no shut-down stage)")
	assert_true(cap.damageable.hull.destroyed, "the hull with it")
	await wait_physics_frames(2)
	assert_eq(destroyed, [cap] as Array[CapitalBody], "the destruction director took its death")


func test_a_magazine_at_zero_blows_and_the_ship_is_destroyed() -> void:
	var cap: CapitalShip = _spawn_broadside(Factions.EARTH_ALLIANCE, 4000.0)
	if cap == null:
		return
	await wait_physics_frames(3)
	var destroyed: Array[CapitalBody] = []
	main.director.capital_destroyed.connect(func(c: CapitalBody, _info: HitInfo) -> void: destroyed.append(c))
	assert_true(_run("capital damage missile_top 1300").ok, "the battery over the magazine")
	assert_eq(cap.damage.live_mounts().size(), cap.damage.mounts.size() - 1, "shot off at its 1 200 points")
	assert_eq(cap.damage.sections["magazine"].state, CapitalSection.State.INTACT, "only the part hit takes it (Q72)")
	assert_almost_eq(cap.damageable.hull.hp, cap.spec.hull_max - 650.0, 0.01, "the hull half of it")
	assert_true(_run("capital damage magazine 3000").ok)
	assert_eq(cap.damage.blown, "magazine")
	assert_true(cap.damageable.hull.destroyed)
	await wait_physics_frames(2)
	assert_eq(destroyed, [cap] as Array[CapitalBody])
	assert_false(cap.visible, "it left play")


func test_the_console_lists_and_heals_the_sections() -> void:
	var cap: CapitalShip = _spawn_broadside(Factions.EARTH_ALLIANCE, 4000.0)
	if cap == null:
		return
	await wait_physics_frames(3)
	# Its one launch bay is in the bow (the maintainer, 2026-11-21): losing the bow loses the launches.
	assert_true(_run("capital damage bow 3000").ok)
	var listed: ConsoleResult = _run("capital sections")
	assert_true(listed.ok, listed.error)
	assert_eq(listed.lines.size(), cap.damage.sections.size() + 2, "a line a section, the hull's and one for the ship")
	assert_string_contains("\n".join(listed.lines), "bow (structure) disabled")
	assert_string_contains("\n".join(listed.lines), "bays 0/1")
	assert_eq(DebugConsole.registry.read("capital.bays").get("value"), "0/1")
	assert_false(_run("capital damage nowhere 10").ok, "an unknown section is refused")
	cap.damageable.restore()
	assert_eq(cap.damage.sections["bow"].state, CapitalSection.State.INTACT, "whole again")
	assert_eq(cap.damage.live_bays().size(), 1)
