extends GutTest
## Far capitals fire (M10-T85): a capital beyond the low-attention tier's radius fires its guns and launchers as seeded rolls
## on its tier row, landed on the damage store. Two Omegas broadside out there take about what they take up close; a far
## Omega leaves a disguised renegade alone until it fires; a hulk out there is silent; and a ship crossing the tier's edge
## keeps its rate of fire, with neither a burst nor a pause. Beams are held in the comparisons: they fire from tier rows by
## their own kernel (M10-T12), where the far helm turns the ships differently from the near one.

const SPEED_UP: float = 16.0
const RENEGADES: StringName = &"renegades"
## Two Omegas broadside this far apart, the first this far ahead of the player (far) or this near (in play).
const GAP_M: float = 2400.0
const FAR_M: float = 15000.0
const NEAR_M: float = 3000.0

var main: Main
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8
var _radius_backup: Variant = null


func before_each() -> void:
	get_tree().paused = false
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame
	_radius_backup = Settings.get_value(&"tier_radius_m")
	await _launch()


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	Settings.set_value(&"tier_radius_m", _radius_backup)
	DebugConsole.flags.invulnerable = false


func _launch() -> void:
	if main != null and is_instance_valid(main):
		remove_child(main)
		main.free()
		await get_tree().physics_frame
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.scenario_seed = 7
	add_child_autofree(main)
	await wait_physics_frames(2)
	DebugConsole.flags.invulnerable = true


func _omega(display_name: String, faction: StringName, ahead_m: float) -> CapitalShip:
	var cap: CapitalShip = CapitalShip.create(&"ea_omega", faction, display_name, main.world.rest_velocity())
	assert_not_null(cap, "the Omega is generated (scripts/gen_assets.sh)")
	if cap == null:
		return null
	var nose: Basis = main.ship.global_basis
	main.world.spawn(cap, main.world.to_universe(main.ship.global_position - nose.z * ahead_m), nose.rotated(nose.y, PI * 0.5))
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


func _guns() -> CapitalGuns:
	return CapitalGuns.of(main.world)


func _core() -> Object:
	return SimCore.for_tree(get_tree()).core


func _far(cap: CapitalShip) -> bool:
	return bool(_core().tier_has(cap.get_instance_id()))


# A pair broadside `ahead_m` off, beams held; the hull points both lost in `seconds`.
func _duel(ahead_m: float, seconds: float) -> Dictionary:
	var a: CapitalShip = _omega("EAS Agamemnon", Factions.EARTH_ALLIANCE, ahead_m)
	var b: CapitalShip = _omega("Raider Omega", Factions.RAIDERS, ahead_m + GAP_M)
	if a == null or b == null:
		return {}
	await wait_physics_frames(1)
	for cap: CapitalShip in [a, b]:
		CapitalBeams.of(main.world).hold(cap, true)
		if cap.hangar != null:
			cap.hangar.empty()  # no wings: far hangars launch none, and anti-fighter launchers would chase them in play
	await _fly(4.0)
	var far: bool = _far(a) and _far(b)
	var before: float = a.damageable.hull.hp + b.damageable.hull.hp
	await _fly(seconds)
	return {"far": far, "lost": before - a.damageable.hull.hp - b.damageable.hull.hp, "still_far": _far(a) and _far(b)}


func test_far_omegas_broadside_take_about_what_they_take_in_play() -> void:
	var near: Dictionary = await _duel(NEAR_M, 60.0)
	await _launch()
	var far: Dictionary = await _duel(FAR_M, 60.0)
	if near.is_empty() or far.is_empty():
		return
	assert_false(bool(near["far"]), "in play")
	assert_true(bool(far["far"]) and bool(far["still_far"]), "out there, tier rows throughout")
	var ratio: float = float(far["lost"]) / maxf(float(near["lost"]), 1.0)
	gut.p("guns and launchers broadside, 60 s: %.0f hull points in play, %.0f far (x%.2f)" % [near["lost"], far["lost"], ratio])
	assert_gt(float(far["lost"]), 0.0, "far capitals fire")
	assert_between(ratio, 0.5, 2.5, "about the near fight's damage")


func test_a_far_omega_leaves_a_disguised_renegade_alone_until_it_fires() -> void:
	var omega: CapitalShip = _omega("EAS Agamemnon", Factions.EARTH_ALLIANCE, FAR_M)
	var renegade: CapitalShip = _omega("Renegade", RENEGADES, FAR_M + GAP_M)
	if omega == null or renegade == null:
		return
	omega.damageable.invulnerable = true
	renegade.damageable.invulnerable = true
	var on_renegade: Array = _log_far_hits(renegade, omega)
	var on_omega: Array = _log_far_hits(omega, renegade)
	await wait_physics_frames(1)
	_guns().hold(renegade, true)
	await _fly(12.0)
	assert_true(_far(omega) and _far(renegade), "both far")
	assert_true(renegade.targetable.is_disguised(), "it broadcasts Earth Alliance (Q55)")
	assert_eq(on_renegade.size(), 0, "the far Omega's guns and launchers leave it alone")
	_guns().hold(renegade, false)
	await _fly(12.0, func() -> bool: return not renegade.targetable.is_disguised())
	assert_false(renegade.targetable.is_disguised(), "its far fire at Earth Alliance gives it away")
	await _fly(12.0, func() -> bool: return not on_renegade.is_empty())
	assert_false(on_omega.is_empty(), "its far hits land")
	assert_false(on_renegade.is_empty(), "now the far Omega fires back")


func test_a_far_hulk_is_silent() -> void:
	var hulk: CapitalShip = _omega("EAS Agamemnon", Factions.EARTH_ALLIANCE, FAR_M)
	var raider: CapitalShip = _omega("Raider Omega", Factions.RAIDERS, FAR_M + GAP_M)
	if hulk == null or raider == null:
		return
	raider.damageable.invulnerable = true
	var on_raider: Array = _log_far_hits(raider, hulk)
	await _fly(4.0)
	assert_true(_far(hulk), "far")
	assert_true(DebugConsole.registry.execute_tokens(["capital", "focus", String(hulk.name)]).ok)
	assert_true(DebugConsole.registry.execute_tokens(["capital", "disable"]).ok)
	assert_true(hulk.is_hulk(), "disabled: a hulk row")
	var before: int = on_raider.size()
	await _fly(15.0)
	assert_eq(on_raider.size(), before, "no power, no fire (Q72, Q78)")


func test_crossing_the_tiers_edge_neither_bursts_nor_pauses() -> void:
	var a: CapitalShip = _omega("EAS Agamemnon", Factions.EARTH_ALLIANCE, FAR_M)
	var b: CapitalShip = _omega("Raider Omega", Factions.RAIDERS, FAR_M + GAP_M)
	if a == null or b == null:
		return
	b.damageable.invulnerable = true
	await wait_physics_frames(1)
	CapitalBeams.of(main.world).hold(a, true)
	_guns().hold(b, true)
	await _fly(20.0)
	assert_true(_far(a), "far")
	var far_rate: float = await _shot_rate(a, 20.0)
	# The tier's edge moves out past them: both promote into play with their mounts' timers as the rolls left them.
	Settings.set_value(&"tier_radius_m", 40000.0)
	var spike: float = await _shot_rate(a, 3.0)
	assert_false(_far(a), "in play")
	var near_rate: float = await _shot_rate(a, 20.0)
	Settings.set_value(&"tier_radius_m", 10000.0)  # and back out
	await _fly(6.0)
	assert_true(_far(a), "far again")
	var back_rate: float = await _shot_rate(a, 20.0)
	gut.p("shots a second: far %.2f, the 3 s of the hand-over %.2f, in play %.2f, far again %.2f" % [far_rate, spike, near_rate,
			back_rate])
	assert_gt(far_rate, 0.0, "it fires far")
	assert_between(spike, 0.3 * near_rate, 2.0 * near_rate, "no burst and no pause at the hand-over")
	assert_between(far_rate, 0.5 * near_rate, 2.0 * near_rate, "about the same rate either side")
	assert_between(back_rate, 0.5 * far_rate, 1.5 * far_rate, "and again out there")


# Shots a second `ship`'s guns and launchers fire over the next `seconds` (near bolts or far rolls: the mounts' own counts).
func _shot_rate(ship: CapitalShip, seconds: float) -> float:
	var start: int = _shots_of(ship)
	await _fly(seconds)
	return float(_shots_of(ship) - start) / seconds


func _shots_of(ship: CapitalShip) -> int:
	var n: int = 0
	for k: int in _guns().mounts_of(ship):
		n += int(_guns().state(k)["shots"])
	return n


# Every far hit `shooter` lands on `target` (its summaries; cause bolt).
func _log_far_hits(target: CapitalShip, shooter: CapitalShip) -> Array:
	var log: Array = []
	var shooter_id: int = shooter.get_instance_id()
	target.damageable.hits_landed.connect(func(summary: HitSummary) -> void:
		if summary.cause == HitInfo.CAUSE_BOLT and summary.attackers.has(shooter_id):
			log.append(summary.damage))
	return log
