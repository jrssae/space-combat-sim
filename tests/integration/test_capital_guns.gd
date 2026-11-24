extends GutTest
## Capital guns and launchers on the native rows in the real main scene (M10-T14, D12.9, AC9's turret and missile clause): two
## hostile Omegas side by side hit each other section by section with their turrets, and the Omega's missiles strike and blast;
## a lost mount holds its fire and a disabled ship falls silent; a renegade capital broadcasts Earth Alliance from its spawn
## (Q55), so an Omega's guns and launchers leave it alone until its own shot gives it away, and only the one that fired is
## revealed; the Nova's fixed pulse cannons (Q71) fire only along their line, the four aft ones astern, and its hangar pods swivel
## to fire abeam; a disabled capital is engaged only when nothing live is in reach; a ship's own bolts pass through its own drum;
## the console's `gun` command and `capital_guns` provider.

const SPEED_UP: float = 4.0
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
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	DebugConsole.flags.invulnerable = false


# A capital of `type` for `faction`, `ahead_m` along the player's nose and `side_m` to its right, its bow along the player's
# turned by `yaw_deg`, holding still. Its beams hold their fire, so only its guns and launchers are tested.
func _spawn(type: StringName, display_name: String, faction: StringName, ahead_m: float, side_m: float = 0.0,
		yaw_deg: float = 0.0) -> CapitalShip:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(type, faction, display_name, rest)
	assert_not_null(cap, "%s is generated (scripts/gen_assets.sh)" % type)
	if cap == null:
		return null
	var nose: Basis = main.ship.global_basis
	var basis: Basis = nose.rotated(nose.y, deg_to_rad(yaw_deg))
	var at: Vector3 = main.ship.global_position - nose.z * ahead_m + nose.x * side_m
	main.world.spawn(cap, main.world.to_universe(at), basis)
	cap.set_course(-basis.z, rest)
	CapitalBeams.of(main.world).hold(cap, true)
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
	return DebugConsole.registry.execute_tokens(line.split(" ", false))


func _guns() -> CapitalGuns:
	return CapitalGuns.of(main.world)


# Every hit `target` takes from `shooter`, logged as [cause, section, damage].
func _log_hits(target: CapitalShip, shooter: CapitalShip) -> Array:
	var log: Array = []
	var shooter_id: int = shooter.get_instance_id()
	target.section_hit.connect(func(section: String, info: HitInfo) -> void:
		if info.shooter_id == shooter_id:
			log.append([info.cause, section, info.damage]))
	return log


# Shots fired so far by each of `ship`'s mounts, by mount name.
func _shots(ship: CapitalShip) -> Dictionary:
	var out: Dictionary = {}
	for k: int in _guns().mounts_of(ship):
		var s: Dictionary = _guns().state(k)
		out[str((s["mount"] as Dictionary)["name"])] = int(s["shots"])
	return out


func _fired(shots: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for name: String in shots:
		if int(shots[name]) > 0:
			out.append(name)
	return out


func test_two_hostile_omegas_side_by_side_hit_each_other_by_section_and_the_missiles_blast() -> void:
	var omega: CapitalShip = _spawn(&"ea_omega", "EAS Agamemnon", Factions.EARTH_ALLIANCE, 3000.0)
	var raider: CapitalShip = _spawn(&"ea_omega", "Raider Omega", Factions.RAIDERS, 3000.0, 3000.0)
	if omega == null or raider == null:
		return
	var on_raider: Array = _log_hits(raider, omega)
	var on_omega: Array = _log_hits(omega, raider)
	var hull_before: float = raider.damageable.hull.hp
	await wait_physics_frames(2)
	assert_eq(_guns().mounts_of(omega).size(), 18, "the Omega's 4 heavy plasma and 12 pulse turrets and 2 launchers are on the rows")
	await _fly(25.0)
	var causes: Dictionary = {}
	var sections: Dictionary = {}
	for e: Array in on_raider:
		causes[e[0]] = int(causes.get(e[0], 0)) + 1
		sections[e[1]] = true
	assert_gt(int(causes.get(HitInfo.CAUSE_BOLT, 0)), 10, "the Omega's guns hit the raider (%s)" % [causes])
	assert_false(sections.has(""), "every hit named by its section: %s" % [sections.keys()])
	assert_gt(sections.size(), 1, "on more than one section: %s" % [sections.keys()])
	assert_gt(int(causes.get(HitInfo.CAUSE_BLAST, 0)), 0, "a missile's warhead blasts where it strikes (%s)" % [causes])
	assert_gt(_guns().missiles_launched, 0, "missiles launched")
	assert_lt(raider.damageable.hull.hp, hull_before, "the damage lands on the hull through its sections")
	assert_gt(on_omega.size(), 0, "and the raider fires back")
	var fired: PackedStringArray = _fired(_shots(omega))
	assert_true(fired.size() >= 6, "the turrets on the side facing it fire: %s" % [fired])


func test_a_lost_mount_holds_its_fire_and_a_disabled_ship_falls_silent() -> void:
	var omega: CapitalShip = _spawn(&"ea_omega", "EAS Agamemnon", Factions.EARTH_ALLIANCE, 3000.0)
	var raider: CapitalShip = _spawn(&"ea_omega", "Raider Omega", Factions.RAIDERS, 3000.0, 3000.0)
	if omega == null or raider == null:
		return
	raider.damageable.invulnerable = true
	await wait_physics_frames(2)
	assert_true(_run("capital focus %s" % String(omega.name)).ok)
	await _fly(12.0)
	var fired: PackedStringArray = _fired(_shots(omega))
	assert_false(fired.is_empty(), "it fires")
	var lost: String = fired[0]
	omega.damage.mounts[lost].hp = 1.0  # one point left, so a small hit takes the mount and spares its section
	assert_true(_run("capital damage %s 1" % lost).ok)
	assert_false(omega.mount_works(lost), "lost")
	var before: Dictionary = _shots(omega)
	await _fly(12.0)
	var after: Dictionary = _shots(omega)
	assert_eq(after[lost], before[lost], "the lost mount never fires again")
	var index: int = _guns().mounts_of(omega)[after.keys().find(lost)]
	assert_false(bool(_guns().state(index)["works"]), "the rows know it is lost")
	assert_true(_run("capital disable").ok)
	await _fly(25.0, func() -> bool: return _guns().missiles_in_flight() == 0)
	await _fly(3.0)  # its last bolts land
	var log: Array = _log_hits(raider, omega)
	var silent: Dictionary = _shots(omega)
	await _fly(8.0)
	assert_eq(_shots(omega), silent, "a disabled ship's guns and launchers are silent")
	assert_eq(log.size(), 0, "nothing more of its lands")


func test_a_renegade_capital_is_left_alone_until_its_own_shot_gives_it_away() -> void:
	var omega: CapitalShip = _spawn(&"ea_omega", "EAS Agamemnon", Factions.EARTH_ALLIANCE, 3000.0)
	var renegade: CapitalShip = _spawn(&"ea_omega", "Renegade", RENEGADES, 3000.0, 3000.0)
	if omega == null or renegade == null:
		return
	omega.damageable.invulnerable = true
	renegade.damageable.invulnerable = true
	assert_true(renegade.targetable.is_disguised(), "a renegade capital broadcasts Earth Alliance from its spawn (Q55)")
	var on_renegade: Array = _log_hits(renegade, omega)
	var on_omega: Array = _log_hits(omega, renegade)
	_guns().hold(renegade, true)
	await _fly(10.0)
	assert_eq(on_renegade.size(), 0, "the Omega's guns and missiles leave the hull broadcasting Earth Alliance alone")
	for k: int in _guns().mounts_of(omega):
		assert_ne(int(_guns().state(k)["target"]), renegade.get_instance_id(), "no mount picks it, launchers included")
	_guns().hold(renegade, false)
	await _fly(10.0, func() -> bool: return not renegade.targetable.is_disguised())
	assert_false(renegade.targetable.is_disguised(), "its first shot at Earth Alliance gives it away")
	# Both first salvos take a few seconds to cross the 3 km.
	await _fly(15.0, func() -> bool: return not on_renegade.is_empty() and not on_omega.is_empty())
	assert_false(on_renegade.is_empty(), "now the Omega fires back")
	assert_false(on_omega.is_empty(), "the renegade's shots land")


func test_the_novas_fixed_pulse_cannons_fire_only_along_their_line() -> void:
	var nova: CapitalShip = _spawn(&"ea_nova", "EAS Nova", Factions.EARTH_ALLIANCE, 3000.0)
	# A hostile hull lying across the Nova's bow line 3 km ahead (its length spans every fore gun's line).
	var raider: CapitalShip = _spawn(&"ea_omega", "Raider Omega", Factions.RAIDERS, 6000.0, 0.0, 90.0)
	if nova == null or raider == null:
		return
	raider.damageable.invulnerable = true
	var on_raider: Array = _log_hits(raider, nova)
	await wait_physics_frames(2)
	assert_eq(_guns().mounts_of(nova).size(), 14, "12 fixed and 2 swivel pulse cannons (the 4 pods are interceptors, T13)")
	await _fly(10.0)
	var shots: Dictionary = _fixed_only(_shots(nova))
	var aft: PackedStringArray = PackedStringArray()
	var fore: PackedStringArray = PackedStringArray()
	for name: String in _fired(shots):
		(aft if name.begins_with("pulse_aft") else fore).append(name)
	assert_eq(aft.size(), 0, "the aft guns fire astern only")
	assert_gte(fore.size(), 6, "the fore guns on the line fire: %s" % [fore])
	assert_gt(on_raider.size(), 10, "and hit")
	# Turned 20 deg off the line, the hull is held for the helm but not fired on.
	raider.global_position = nova.global_position + (nova.global_basis * Vector3(0.0, 0.0, -3000.0)).rotated(nova.global_basis.y, deg_to_rad(20.0))
	SimCore.touch_moved(raider)
	await _fly(1.0)
	var held: Dictionary = _fixed_only(_shots(nova))
	await _fly(6.0)
	assert_eq(_fixed_only(_shots(nova)), held, "off its line a fixed gun holds its fire")
	var holding: int = 0
	for k: int in _guns().mounts_of(nova):
		holding += 1 if int(_guns().state(k)["target"]) == raider.get_instance_id() else 0
	assert_gt(holding, 0, "the fore guns hold it in their wider cone for the helm")


# `shots` without the Nova's two swivelling hangar pods.
func _fixed_only(shots: Dictionary) -> Dictionary:
	var out: Dictionary = shots.duplicate()
	for name: String in ["pulse_hangar_r", "pulse_hangar_l"]:
		out.erase(name)
	return out


# M10-T14 review: the hangar pods swivel over the block's flank (their fire ahead is blocked by the wing pods) and fire abeam
# at three quarters of the fixed cannons' power; the fixed cannons leave a target abeam alone.
func test_the_novas_hangar_pods_swivel_to_fire_abeam_at_three_quarters_power() -> void:
	var nova: CapitalShip = _spawn(&"ea_nova", "EAS Nova", Factions.EARTH_ALLIANCE, 3000.0)
	var raider: CapitalShip = _spawn(&"ea_omega", "Raider Omega", Factions.RAIDERS, 3000.0, 2500.0)
	if nova == null or raider == null:
		return
	raider.damageable.invulnerable = true
	_guns().hold(raider, true)
	await wait_physics_frames(2)
	var swivel: WeaponSpec = WeaponSpec.of_weapon(&"ea_pulse_cannon_swivel")
	assert_almost_eq(swivel.damage, 0.75 * WeaponSpec.of_weapon(&"ea_pulse_cannon_fixed").damage, 1e-6)
	await _fly(12.0, func() -> bool: return int(_shots(nova).get("pulse_hangar_r", 0)) > 0)
	var shots: Dictionary = _shots(nova)
	assert_gt(int(shots.get("pulse_hangar_r", 0)), 0, "the starboard hangar pod turns abeam and fires: %s" % [shots])
	assert_eq(int(shots.get("pulse_hangar_l", 0)), 0, "the port one cannot see over the block")
	assert_eq(_fired(_fixed_only(shots)).size(), 0, "no fixed cannon fires abeam: %s" % [shots])


# Q55, revealed per ship: of two renegade capitals broadcasting Earth Alliance, only the one that fires gives itself away, and
# only it is engaged.
func test_only_the_renegade_that_fires_is_revealed_and_engaged() -> void:
	var omega: CapitalShip = _spawn(&"ea_omega", "EAS Agamemnon", Factions.EARTH_ALLIANCE, 3000.0)
	var loud: CapitalShip = _spawn(&"ea_omega", "Renegade A", RENEGADES, 3000.0, 3000.0)
	var quiet: CapitalShip = _spawn(&"ea_omega", "Renegade B", RENEGADES, 3000.0, -3000.0)
	if omega == null or loud == null or quiet == null:
		return
	for cap: CapitalShip in [omega, loud, quiet]:
		cap.damageable.invulnerable = true
	_guns().hold(quiet, true)
	var on_quiet: Array = _log_hits(quiet, omega)
	await _fly(15.0, func() -> bool: return not loud.targetable.is_disguised())
	assert_false(loud.targetable.is_disguised(), "the renegade that fires gives itself away")
	assert_true(quiet.targetable.is_disguised(), "the one holding its fire still broadcasts Earth Alliance")
	var on_loud: Array = _log_hits(loud, omega)
	await _fly(15.0)
	assert_false(on_loud.is_empty(), "the Omega engages the one revealed")
	assert_eq(on_quiet.size(), 0, "and never the one still disguised")
	for k: int in _guns().mounts_of(omega):
		assert_ne(int(_guns().state(k)["target"]), quiet.get_instance_id(), "no mount holds it, the port side's included")


# M10-T14 review: a disabled capital draws fire only from mounts with nothing live in reach (it still blasts when it dies).
func test_a_disabled_capital_is_engaged_only_when_nothing_live_is_in_reach() -> void:
	var omega: CapitalShip = _spawn(&"ea_omega", "EAS Agamemnon", Factions.EARTH_ALLIANCE, 3000.0)
	var live: CapitalShip = _spawn(&"ea_omega", "Raider A", Factions.RAIDERS, 3000.0, 3000.0)
	var hulk: CapitalShip = _spawn(&"ea_omega", "Raider B", Factions.RAIDERS, 5600.0, 3000.0)
	if omega == null or live == null or hulk == null:
		return
	_guns().hold(live, true)
	assert_true(_run("capital focus %s" % String(hulk.name)).ok)
	assert_true(_run("capital disable").ok)
	for cap: CapitalShip in [omega, live, hulk]:
		cap.damageable.invulnerable = true  # after the disable, which lands as hits
	await wait_physics_frames(2)
	assert_eq(int(SimCore.current().core.disabled_count()), 1, "the rows know it is disabled")
	var on_live: Array = _log_hits(live, omega)
	var on_hulk: Array = _log_hits(hulk, omega)
	await _fly(15.0)
	assert_false(on_live.is_empty(), "the live raider is engaged")
	for k: int in _guns().mounts_of(omega):
		var s: Dictionary = _guns().state(k)
		if int(s["target"]) == hulk.get_instance_id():
			assert_true(false, "%s holds the hulk with a live raider beside it" % (s["mount"] as Dictionary)["name"])
	gut.p("hits on the live raider %d, on the hulk %d" % [on_live.size(), on_hulk.size()])
	live.queue_free()
	await _fly(15.0, func() -> bool: return not on_hulk.is_empty())
	assert_false(on_hulk.is_empty(), "with nothing live left, the hulk is fair game")


# M10-T14 review: a capital's own bolts and missiles pass through its own rotating section (a separate body), as through its hull.
func test_a_ships_own_bolt_passes_through_its_drum() -> void:
	var omega: CapitalShip = _spawn(&"ea_omega", "EAS Agamemnon", Factions.EARTH_ALLIANCE, 3000.0)
	if omega == null:
		return
	omega.damageable.invulnerable = true
	_guns().hold(omega, true)
	await wait_physics_frames(2)
	assert_false(omega.rotors.is_empty(), "the Omega has its drum")
	var drum: Node3D = omega.rotors[0]
	var sim: SimCore = SimCore.current()
	var spec: WeaponSpec = WeaponSpec.of_weapon(&"ea_pulse_medium")
	var across: Vector3 = omega.global_basis.x
	var hits: Array = []
	omega.section_hit.connect(func(section: String, info: HitInfo) -> void: hits.append([info.shooter_id, section]))
	var shoot: Callable = func(shooter_id: int, faction: StringName) -> void:
		var at: Vector3 = drum.global_position + across * 700.0
		sim.add_bolt(at, main.world.rest_velocity() - across * 1800.0, faction, shooter_id, spec, SimClock.now())
	shoot.call(omega.get_instance_id(), Factions.EARTH_ALLIANCE)
	await _fly(1.0)
	assert_eq(hits.size(), 0, "its own bolt crosses its drum and hull untouched: %s" % [hits])
	shoot.call(0, Factions.RAIDERS)
	await _fly(1.0, func() -> bool: return not hits.is_empty())
	assert_false(hits.is_empty(), "a stranger's bolt on the same line lands")


func test_the_console_lists_mounts_holds_and_fires_a_test_shot() -> void:
	var omega: CapitalShip = _spawn(&"ea_omega", "EAS Agamemnon", Factions.EARTH_ALLIANCE, 3000.0)
	var raider: CapitalShip = _spawn(&"ea_omega", "Raider", Factions.RAIDERS, 3000.0, 3000.0)
	if omega == null or raider == null:
		return
	raider.damageable.invulnerable = true
	_guns().hold(raider, true)
	await wait_physics_frames(2)
	assert_true(_run("capital focus %s" % String(omega.name)).ok)
	var info: ConsoleResult = _run("gun")
	assert_true(info.ok, info.error)
	assert_eq(info.lines.size(), 18, "one line a mount")
	assert_true(_run("gun hold").ok)
	var before: Dictionary = _shots(omega)
	await _fly(4.0)
	assert_eq(_shots(omega), before, "held, it never fires")
	assert_true(_run("gun free").ok)
	var fired: ConsoleResult = _run("gun fire Raider")
	assert_true(fired.ok, fired.error)
	await _fly(8.0, func() -> bool: return _guns().shots > 0)
	assert_gt(_guns().shots, 0, "the test shot fires")
	assert_eq(int(DebugConsole.registry.read("capital_guns.mounts")["value"]), 36, "two Omegas' mounts on the rows")
	assert_false(_run("gun fire nobody").ok, "an unknown target is refused")
	assert_true(_run("gun clear").ok)
