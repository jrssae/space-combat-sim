extends GutTest
## The capitals' interceptor batteries (M10-T13, Q81) in the real main scene, on the native rows: an Omega's batteries shoot
## down a raider Omega's missile salvos and a raider Hyperion's torpedoes (three pulses each) headed for it; they take part of a
## Starfury flight's linked bolts and never a beam; a lost battery and a hulk fire no pulse; the Nova's four pods fire two pulses a
## second each; the console's `intercept` command and `interceptors` provider. The station grid, on the same kernel, takes a
## tough shot's toughness too.

const SPEED_UP: float = 4.0
const STARFURY_WEAPON: String = "res://assets/weapons/pulse_cannon_ef.tres"

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


# A capital of `type` for `faction`, `ahead_m` along the player's nose and `side_m` to its right, turned by `yaw_deg`, holding
# still, invulnerable, its beams holding their fire.
func _spawn(type: StringName, display_name: String, faction: StringName, ahead_m: float, side_m: float = 0.0,
		yaw_deg: float = 0.0) -> CapitalShip:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(type, faction, display_name, rest)
	assert_not_null(cap, "%s is generated (scripts/gen_assets.sh)" % type)
	if cap == null:
		return null
	var nose: Basis = main.ship.global_basis
	var basis: Basis = nose.rotated(nose.y, deg_to_rad(yaw_deg))
	main.world.spawn(cap, main.world.to_universe(main.ship.global_position - nose.z * ahead_m + nose.x * side_m), basis)
	cap.set_course(-basis.z, rest)
	CapitalBeams.of(main.world).hold(cap, true)
	cap.damageable.invulnerable = true
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


# Pulses each of `ship`'s batteries fired so far, by mount name.
func _pulses(ship: CapitalShip) -> Dictionary:
	var out: Dictionary = {}
	for k: int in _guns().interceptors_of(ship):
		var s: Dictionary = _guns().state(k)
		out[str((s["mount"] as Dictionary)["name"])] = int(s["shots"])
	return out


func _sum(d: Dictionary) -> int:
	var n: int = 0
	for v: Variant in d.values():
		n += int(v)
	return n


# A bolt of `faction` fired by `shooter_id` from `from` at `to` at `speed`, a core row of `weapon`.
func _bolt(from: Vector3, to: Vector3, speed: float, faction: StringName, shooter_id: int, weapon: WeaponSpec) -> int:
	var sim: SimCore = SimCore.current()
	return sim.add_bolt(from, main.world.rest_velocity() + (to - from).normalized() * speed, faction, shooter_id, weapon,
			SimClock.now())


func test_an_omega_shoots_down_missile_salvos_and_torpedoes_headed_for_it() -> void:
	# 9 km ahead, out of the missiles' reach of the player (anti-fighter: they would go for a fighter first); the Hyperion's
	# torpedo tubes turned onto the Omega.
	var omega: CapitalShip = _spawn(&"ea_omega", "EAS Agamemnon", Factions.EARTH_ALLIANCE, 9000.0)
	var raider: CapitalShip = _spawn(&"ea_omega", "Raider Omega", Factions.RAIDERS, 9000.0, 3000.0)
	var torpedoes: CapitalShip = _spawn(&"ea_hyperion", "Raider Hyperion", Factions.RAIDERS, 9000.0, -3000.0, -90.0)
	if omega == null or raider == null or torpedoes == null:
		return
	_guns().hold(omega, true)  # its guns and launchers: only its batteries work here
	assert_eq(_guns().interceptors_of(omega).size(), 8, "the Omega's eight batteries are on the rows")
	assert_eq(_guns().interceptors_of(torpedoes).size(), 4, "the Hyperion's four")
	_guns().reset_stats()
	await _fly(60.0, func() -> bool: return _guns().downed[2] > 0 and _guns().downed[3] > 0)
	var share: PackedInt64Array = _guns().intercept_share(omega)
	gut.p("the Omega's batteries: %d pulses; down bolts %d, heavy %d, missiles %d, torpedoes %d; its share %d of %d" % [
			_guns().pulses, _guns().downed[0], _guns().downed[1], _guns().downed[2], _guns().downed[3], share[1], share[0]])
	assert_gt(_guns().missiles_launched, 0, "the raiders launch")
	assert_gt(_guns().downed[2], 0, "missiles shot down")
	assert_gt(_guns().downed[3], 0, "a torpedo shot down (three pulses each)")
	assert_gt(share[0], 0, "shots seen headed for its hull")
	assert_gt(share[1], 0, "and some of them shot down")
	var r: PackedInt64Array = _guns().intercept_readouts()
	assert_gte(r[1], r[2] + 2 * r[3] + r[4] + 3 * r[5], "every heavy bolt took two pulses and every torpedo three")


func test_part_of_a_starfury_flights_linked_bolts_is_taken_and_a_beam_never() -> void:
	var raider: CapitalShip = _spawn(&"ea_omega", "Raider Omega", Factions.RAIDERS, 1800.0, 0.0, 90.0)
	if raider == null:
		return
	_guns().hold(raider, true)
	await wait_physics_frames(2)
	var weapon: WeaponSpec = load(STARFURY_WEAPON) as WeaponSpec
	var shooter: int = main.ship.get_instance_id()
	var hits: Array[int] = [0]
	raider.section_hit.connect(func(_section: String, info: HitInfo) -> void:
		if info.shooter_id == shooter and info.cause == HitInfo.CAUSE_BOLT:
			hits[0] += 1)
	_guns().reset_stats()
	# Six Starfuries on their attack run 800 m off the raider's beam, each firing its linked pair every quarter second (Q76):
	# more than the four batteries on that side can take.
	var fired: int = 0
	var side: Vector3 = raider.global_basis.z
	var off: Vector3 = (main.ship.global_position - raider.global_position).normalized()
	for k: int in 16:
		for f: int in 6:
			var to: Vector3 = raider.global_position + raider.global_basis.z * (float(f) * 60.0 - 150.0)
			var from: Vector3 = to + off * 800.0 + raider.global_basis.y * (100.0 + 20.0 * float(k % 3))
			for s: float in [-1.0, 1.0]:
				_bolt(from + side * s, to + side * s, weapon.muzzle_speed_mps, Factions.EARTH_ALLIANCE, shooter, weapon)
				fired += 1
		await _fly(0.25)
	await _fly(3.0)
	var down: int = _guns().downed[0]
	gut.p("six Starfuries' linked bolts at an Omega: %d fired, %d shot down, %d landed" % [fired, down, hits[0]])
	assert_gt(down, 0, "the batteries take some")
	assert_gt(hits[0], 0, "and some land")
	# Beams: the player's side's Omega beams the raider; the raider's batteries take nothing while only beams fly.
	var ours: CapitalShip = _spawn(&"ea_omega", "EAS Agamemnon", Factions.EARTH_ALLIANCE, 1800.0, 2500.0, 90.0)
	if ours == null:
		return
	_guns().hold(ours, true)
	CapitalBeams.of(main.world).hold(ours, false)
	var beamed: Array[int] = [0]
	raider.section_hit.connect(func(_section: String, info: HitInfo) -> void:
		if info.cause == &"beam":
			beamed[0] += 1)
	var met: int = int(_guns().intercept_readouts()[1])
	await _fly(30.0, func() -> bool: return beamed[0] > 3)
	assert_gt(beamed[0], 0, "the beams reach the raider's hull")
	assert_eq(int(_guns().intercept_readouts()[1]), met, "no pulse met a beam")


func test_a_lost_battery_and_a_hulk_fire_no_pulse() -> void:
	var raider: CapitalShip = _spawn(&"ea_omega", "Raider Omega", Factions.RAIDERS, 1800.0, 0.0, 90.0)
	if raider == null:
		return
	_guns().hold(raider, true)
	raider.damageable.invulnerable = false  # the console's damage and disable must land
	await wait_physics_frames(2)
	assert_true(_run("capital focus %s" % String(raider.name)).ok)
	var weapon: WeaponSpec = WeaponSpec.of_weapon(&"ea_pulse_medium")
	var stream: Callable = func(seconds: float) -> void:
		var t0: float = SimClock.now()
		while SimClock.now() - t0 < seconds:
			var from: Vector3 = main.ship.global_position - main.ship.global_basis.z * 30.0
			_bolt(from, raider.global_position, 1200.0, Factions.EARTH_ALLIANCE, main.ship.get_instance_id(), weapon)
			await _fly(0.2)
	await stream.call(4.0)
	var first: Dictionary = _pulses(raider)
	var busy: String = ""
	for name: String in first:
		if int(first[name]) > 0 and busy == "":
			busy = name
	assert_ne(busy, "", "a battery fires: %s" % [first])
	if busy == "":
		return
	raider.damage.mounts[busy].hp = 1.0
	assert_true(_run("capital damage %s 1" % busy).ok)
	assert_false(raider.mount_works(busy), "lost")
	await stream.call(4.0)
	var second: Dictionary = _pulses(raider)
	assert_eq(second[busy], first[busy], "the lost battery fires no more")
	assert_gt(_sum(second), _sum(first), "the others still do")
	assert_true(_run("capital disable").ok)
	assert_true(raider.is_hulk(), "the bridge out: a hulk")
	await _fly(1.0)
	var silent: Dictionary = _pulses(raider)
	await stream.call(4.0)
	assert_eq(_pulses(raider), silent, "a hulk has no power for its batteries")


func test_the_novas_four_pods_fire_two_pulses_a_second_each() -> void:
	var nova: CapitalShip = _spawn(&"ea_nova", "Raider Nova", Factions.RAIDERS, 1600.0, 0.0, 90.0)
	if nova == null:
		return
	_guns().hold(nova, true)
	await wait_physics_frames(2)
	assert_eq(_guns().interceptors_of(nova).size(), 4, "its four pods")
	var weapon: WeaponSpec = WeaponSpec.of_weapon(&"ea_pulse_medium")
	var up: Vector3 = nova.global_basis.y
	var t0: float = SimClock.now()
	var before: Dictionary = {}
	while SimClock.now() - t0 < 6.0:
		for s: float in [-1.0, 1.0]:
			var from: Vector3 = nova.global_position + up * (900.0 * s) + nova.global_basis.x * 400.0
			_bolt(from, nova.global_position, 1200.0, Factions.EARTH_ALLIANCE, main.ship.get_instance_id(), weapon)
		await _fly(0.1)
		if before.is_empty() and SimClock.now() - t0 >= 2.0:
			before = _pulses(nova)
	var after: Dictionary = _pulses(nova)
	gut.p("the Nova's pods over 4 s: %s" % [after])
	assert_gt(_sum(after) - _sum(before), 0, "the pods fire")
	for name: String in after:
		assert_lte(int(after[name]) - int(before.get(name, 0)), 9, "%s fires at most two pulses a second" % name)


func test_the_console_reports_and_holds_the_interceptors() -> void:
	var raider: CapitalShip = _spawn(&"ea_omega", "Raider Omega", Factions.RAIDERS, 1800.0, 0.0, 90.0)
	if raider == null:
		return
	_guns().hold(raider, true)
	await wait_physics_frames(2)
	assert_true(_run("capital focus %s" % String(raider.name)).ok)
	var info: ConsoleResult = _run("intercept")
	assert_true(info.ok, info.error)
	assert_eq(info.lines.size(), 2 + 8, "the counts, the share and one line a battery")
	assert_eq(int(DebugConsole.registry.read("interceptors.batteries")["value"]), 8)
	assert_eq(int(DebugConsole.registry.read("capital_guns.mounts")["value"]), 18, "the gun count leaves the batteries out")
	assert_true(_run("intercept hold").ok)
	var weapon: WeaponSpec = WeaponSpec.of_weapon(&"ea_pulse_medium")
	for k: int in 10:
		_bolt(main.ship.global_position, raider.global_position, 1200.0, Factions.EARTH_ALLIANCE, main.ship.get_instance_id(), weapon)
		await _fly(0.2)
	assert_eq(_sum(_pulses(raider)), 0, "held, its batteries never fire")
	assert_true(_run("intercept free").ok)
	for k: int in 10:
		_bolt(main.ship.global_position, raider.global_position, 1200.0, Factions.EARTH_ALLIANCE, main.ship.get_instance_id(), weapon)
		await _fly(0.2)
	assert_gt(_sum(_pulses(raider)), 0, "free again, they fire")
	for key: String in ["pulses", "down_bolt", "down_heavy", "down_missile", "down_torpedo", "met", "in_flight", "share"]:
		assert_true(DebugConsole.registry.read("interceptors." + key).has("value"), key)
