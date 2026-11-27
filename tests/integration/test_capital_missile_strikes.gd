extends GutTest
## A capital's missiles and torpedoes strike a capital in play (M10-T85 follow-up, T14's launchers): an Omega's salvo at a
## still Omega and at one turning away lands its warheads, and a Hyperion's torpedoes do. The target's batteries are held, its
## guns too, and the hangars emptied: an Omega's launchers are anti-fighter, so with wings out they chase the wings, and its
## batteries take missiles first (Q81), which is why a duel with both shows no warhead landing.

const SPEED_UP: float = 8.0
const GAP_M: float = 2400.0

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
	main.scenario_seed = 7
	add_child_autofree(main)
	await wait_physics_frames(2)
	DebugConsole.flags.invulnerable = true


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	DebugConsole.flags.invulnerable = false


func _spawn(type: StringName, faction: StringName, label: String, ahead_m: float) -> CapitalShip:
	var cap: CapitalShip = CapitalShip.create(type, faction, label, main.world.rest_velocity())
	assert_not_null(cap, "%s is generated (scripts/gen_assets.sh)" % type)
	if cap == null:
		return null
	var nose: Basis = main.ship.global_basis
	main.world.spawn(cap, main.world.to_universe(main.ship.global_position - nose.z * ahead_m), nose.rotated(nose.y, PI * 0.5))
	return cap


func _fly(seconds: float, done: Callable) -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < seconds:
		await get_tree().physics_frame
		if bool(done.call()):
			break
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup


# A shooter and a target `gap_m` apart broadside: the target silent and its batteries held, the shooter's beams held, no wings.
func _pair(shooter_type: StringName, gap_m: float) -> Array[CapitalShip]:
	var shooter: CapitalShip = _spawn(shooter_type, Factions.EARTH_ALLIANCE, "EAS Shooter", 3000.0)
	var target: CapitalShip = _spawn(&"ea_omega", Factions.RAIDERS, "Raider Omega", 3000.0 + gap_m)
	if shooter == null or target == null:
		return []
	await wait_physics_frames(1)
	var guns: CapitalGuns = CapitalGuns.of(main.world)
	guns.hold(target, true)
	guns.hold_interceptors(target, true)
	CapitalBeams.of(main.world).hold(shooter, true)
	for cap: CapitalShip in [shooter, target]:
		if cap.hangar != null:
			cap.hangar.empty()
	return [shooter, target]


# The warhead blasts `shooter` lands on `target` (their summaries).
func _blasts(target: CapitalShip, shooter: CapitalShip) -> Array:
	var log: Array = []
	var id: int = shooter.get_instance_id()
	target.damageable.hits_landed.connect(func(summary: HitSummary) -> void:
		if summary.cause == HitInfo.CAUSE_BLAST and summary.attackers.has(id):
			log.append(summary.damage))
	return log


func test_an_omegas_salvo_strikes_a_still_omega() -> void:
	var pair: Array[CapitalShip] = await _pair(&"ea_omega", GAP_M)
	if pair.is_empty():
		return
	var blasts: Array = _blasts(pair[1], pair[0])
	await _fly(30.0, func() -> bool: return blasts.size() >= 2)
	assert_gte(blasts.size(), 2, "its first salvo's warheads land")


func test_an_omegas_salvo_strikes_an_omega_turning_away() -> void:
	var pair: Array[CapitalShip] = await _pair(&"ea_omega", GAP_M)
	if pair.is_empty():
		return
	var target: CapitalShip = pair[1]
	var away: Vector3 = target.global_basis.x
	var rest: Vector3 = main.world.rest_velocity()
	target.set_course(away, rest + away * 60.0)
	CapitalGuns.of(main.world).hold(pair[0], true)  # it fires once the target is under way
	await _fly(60.0, func() -> bool: return target.linear_velocity.distance_to(rest) > 15.0)
	assert_gt(target.linear_velocity.distance_to(rest), 15.0, "it is under way")
	CapitalGuns.of(main.world).hold(pair[0], false)
	var blasts: Array = _blasts(target, pair[0])
	await _fly(40.0, func() -> bool: return blasts.size() >= 2)
	assert_gte(blasts.size(), 2, "the missiles follow it and land")


func test_a_hyperions_torpedoes_strike_an_omega() -> void:
	var pair: Array[CapitalShip] = await _pair(&"ea_hyperion", 4000.0)
	if pair.is_empty():
		return
	var blasts: Array = _blasts(pair[1], pair[0])
	await _fly(60.0, func() -> bool: return blasts.size() >= 1)
	assert_gte(blasts.size(), 1, "a torpedo's warhead lands")
