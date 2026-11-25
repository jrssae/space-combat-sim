extends GutTest
## Balance fights B10 and B1 (docs/assets-capital.md, "Balance fights"; Q53, Q76). B10: twelve allied Starfuries on engage at
## will against a lone hostile Omega holding still, none launched (T17), its interceptors working (T13); Q53's bar: the Omega
## lasts 10 to 15 min and the squadron loses about half. B1: two Omegas broadside on; the bar 4 to 8 min. The real main scene,
## Jolt and the native core at the game's 60 Hz step, sped up. Each fight reports the share of the hostile shots headed for an
## Omega that its interceptors took (Q53's anchor: about half the Starfuries' bolts, 40 % of a capital's). No retune with T13
## (Q78, Q81): both bars are reported and a miss is left pending until the later rebalance.

const SCENARIO_PATH: String = "res://tests/fixtures/scenarios/capital_balance.json"
const DUEL_PATH: String = "res://tests/fixtures/scenarios/capital_duel.json"
const SPEED_UP: float = 16.0
const LIMIT_S: float = 1200.0
## The Omega 9 km ahead of the player, out of its guns' and beams' reach; the squadron 3 km short of it, inside its sensors.
const OMEGA_AHEAD_M: float = 9000.0
const SEEDS: Array[int] = [1, 2, 3]
const DIAG_SEEDS: Array[int] = [1]
## The bar (Q53): the Omega lasts this long, s, and the squadron loses this many of its 12.
const LASTS_S: Vector2 = Vector2(600.0, 900.0)
const LOST: Vector2i = Vector2i(4, 8)
## B1: the two Omegas this far apart, the nearer as far ahead of the player as B10's, and Q53's bar, s.
const DUEL_GAP_M: float = 3000.0
const DUEL_LIMIT_S: float = 900.0
const DUEL_LASTS_S: Vector2 = Vector2(240.0, 480.0)
## Flip when the capitals are rebalanced (after T13, Q78 and Q81): the bars are then asserted.
const BARS_ASSERTED: bool = false

var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8
var _tier_backup: Variant = null


@warning_ignore("untyped_declaration")  # GutTest declares it untyped
func should_skip_script():
	return BalanceTests.skip_reason()


func before_each() -> void:
	get_tree().paused = false
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame
	_tier_backup = Settings.get_value(&"tier_radius_m")
	Settings.set_value(&"tier_radius_m", 30000.0)  # every ship a real body: a tier row capital fires nothing yet (T85)
	DebugConsole.flags.invulnerable = true  # the player is a bystander
	ContactScan.invalidate()


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	Settings.set_value(&"tier_radius_m", _tier_backup)
	DebugConsole.flags.invulnerable = false
	ContactScan.invalidate()


func _launch(seed_value: int, path: String = SCENARIO_PATH) -> Main:
	var main := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = path
	main.scenario_seed = seed_value
	add_child(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return main


func _close(main: Main) -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	remove_child(main)
	main.free()
	ContactScan.invalidate()
	await get_tree().physics_frame


func _spawn_omega(main: Main, faction: StringName = Factions.RAIDERS, title: String = "Raider Omega",
		ahead_m: float = OMEGA_AHEAD_M) -> CapitalShip:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(&"ea_omega", faction, title, rest)
	assert_not_null(cap, "the Omega is generated (scripts/gen_assets.sh)")
	if cap == null:
		return null
	var nose: Basis = main.ship.global_basis
	var basis: Basis = nose.rotated(nose.y, deg_to_rad(90.0))  # broadside on to the squadron's approach
	main.world.spawn(cap, main.world.to_universe(main.ship.global_position - nose.z * ahead_m), basis)
	cap.set_course(Vector3.ZERO, rest)
	return cap


# One fight: [seconds the Omega lasted (LIMIT_S when it held), Starfuries lost, its hull share left, damage from the squadron,
# the hostile shots its batteries saw headed for it, and of those shot down].
func _fight(seed_value: int) -> Array:
	var main: Main = await _launch(seed_value)
	var omega: CapitalShip = _spawn_omega(main)
	if omega == null:
		await _close(main)
		return []
	var taken: Array[float] = [0.0]
	omega.damageable.damaged.connect(func(_info: HitInfo, applied: float) -> void: taken[0] += applied)
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	var start: int = main.ships.alive(ShipPool.ALLY_TYPE).size()
	var shots: Array[int] = [0]
	var by_kind: Dictionary = {}
	var rates := PackedFloat64Array()
	for c: Combatant in main.ships.alive(ShipPool.ALLY_TYPE):
		c.cannon.shot_fired.connect(func(_m: int, _at: Vector3) -> void: shots[0] += 1)
		c.damageable.damaged.connect(func(info: HitInfo, applied: float) -> void:
			var key: String = "%s %.0f" % [info.cause, info.damage if info.cause != &"beam" else 0.0]
			by_kind[key] = float(by_kind.get(key, 0.0)) + applied)
	var t0: float = SimClock.now()
	var marks: PackedStringArray = []
	var next_mark: float = 120.0
	while SimClock.now() - t0 < LIMIT_S and is_instance_valid(omega) and omega.damageable.hull.hp > 0.0 and not omega.is_hulk() \
			and main.ships.alive(ShipPool.ALLY_TYPE).size() > 0:
		await get_tree().physics_frame
		if fmod(SimClock.now() - t0, 1.0) < 0.017:
			_sample_rates(main, omega, rates)
		if OS.get_environment("B10_DIAG") == "1" and fmod(SimClock.now() - t0, 15.0) < 0.017:
			var r: ConsoleResult = DebugConsole.registry.execute_tokens(["ai", "ZETA 1"])
			var alpha: Array = main.ships.alive(ShipPool.ALLY_TYPE)
			var d: float = (alpha[0] as Combatant).ship.global_position.distance_to(omega.global_position) if not alpha.is_empty() else -1.0
			gut.p("  t %.0f d %.0f shots %d: %s" % [SimClock.now() - t0, d, shots[0], " | ".join(r.lines).left(600)])
		if SimClock.now() - t0 >= next_mark:
			marks.append("%.0fs %.0f%% %d" % [next_mark, 100.0 * omega.damageable.hull.fraction(),
					main.ships.alive(ShipPool.ALLY_TYPE).size()])
			next_mark += 120.0
	var lasted: float = SimClock.now() - t0
	var lost: int = start - main.ships.alive(ShipPool.ALLY_TYPE).size()
	var left: float = omega.damageable.hull.fraction() if is_instance_valid(omega) else 0.0
	var share: PackedInt64Array = _share(main, omega)
	rates.sort()
	var rate_text: String = "none" if rates.is_empty() else "median %.1f, p25 %.1f, p75 %.1f deg/s (%d)" % [rates[rates.size() / 2],
			rates[rates.size() / 4], rates[rates.size() * 3 / 4], rates.size()]
	gut.p("  seed %d marks: %s; squadron shots %d; its damage taken by cause and hit: %s; Starfuries 1-3 km off swing round the Omega at %s" % [
			seed_value, ", ".join(marks), shots[0], by_kind, rate_text])
	await _close(main)
	return [lasted, lost, left, taken[0], share[0], share[1]]


# `cap`'s interceptors' share: [hostile shots seen headed for its hull, of those shot down].
func _share(main: Main, cap: CapitalShip) -> PackedInt64Array:
	var guns: CapitalGuns = CapitalGuns.of(main.world)
	return guns.intercept_share(cap) if guns != null and is_instance_valid(cap) else PackedInt64Array([0, 0])


func _pct(share: PackedInt64Array) -> float:
	return 100.0 * float(share[1]) / float(share[0]) if share[0] > 0 else 0.0


# How fast each Starfury 1 to 3 km from the Omega swings round it, deg/s: what its turrets must traverse to follow.
func _sample_rates(main: Main, omega: CapitalShip, out: PackedFloat64Array) -> void:
	for c: Combatant in main.ships.alive(ShipPool.ALLY_TYPE):
		var r: Vector3 = c.ship.global_position - omega.global_position
		var d: float = r.length()
		if d < 1000.0 or d > 3000.0:
			continue
		var v: Vector3 = c.ship.linear_velocity - omega.linear_velocity
		out.append(rad_to_deg(r.cross(v).length() / (d * d)))


func test_twelve_starfuries_take_a_lone_omega_in_ten_to_fifteen_minutes_losing_about_half() -> void:
	var lines := PackedStringArray()
	var in_bar: int = 0
	for seed_value: int in (DIAG_SEEDS if OS.get_environment("B10_DIAG") == "1" else SEEDS):
		var r: Array = await _fight(seed_value)
		if r.is_empty():
			return
		lines.append("seed %d: %.0f s, %d lost, Omega at %.0f %%, %.0f taken, interceptors took %d of %d (%.0f %%)" % [seed_value,
				r[0], r[1], 100.0 * float(r[2]), r[3], r[5], r[4], _pct(PackedInt64Array([r[4], r[5]]))])
		if float(r[0]) >= LASTS_S.x and float(r[0]) <= LASTS_S.y and int(r[1]) >= LOST.x and int(r[1]) <= LOST.y:
			in_bar += 1
	gut.p("B10: " + "; ".join(lines))
	_judge(in_bar >= 2, "the Omega lasts %d to %d s and the squadron loses %d to %d, in 2 of %d seeds: %s" % [LASTS_S.x, LASTS_S.y,
			LOST.x, LOST.y, SEEDS.size(), "; ".join(lines)])


# One duel: [seconds until one Omega was out (DUEL_LIMIT_S when neither), the winner's hull share, the loser's, and each Omega's
# interceptors' share of the shots headed for it (ours, theirs)].
func _duel(seed_value: int) -> Array:
	var main: Main = await _launch(seed_value, DUEL_PATH)
	var ours: CapitalShip = _spawn_omega(main, Factions.EARTH_ALLIANCE, "Omega", OMEGA_AHEAD_M)
	var theirs: CapitalShip = _spawn_omega(main, Factions.RAIDERS, "Raider Omega", OMEGA_AHEAD_M + DUEL_GAP_M)
	if ours == null or theirs == null:
		await _close(main)
		return []
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < DUEL_LIMIT_S and _fighting(ours) and _fighting(theirs):
		await get_tree().physics_frame
	var lasted: float = SimClock.now() - t0
	var a: float = ours.damageable.hull.fraction() if _fighting(ours) else 0.0
	var b: float = theirs.damageable.hull.fraction() if _fighting(theirs) else 0.0
	var shares: Array = [_share(main, ours), _share(main, theirs)]
	await _close(main)
	return [lasted, maxf(a, b), minf(a, b), shares[0], shares[1]]


# Whether `cap` is still in the fight: there, not destroyed and not disabled.
func _fighting(cap: CapitalShip) -> bool:
	return is_instance_valid(cap) and cap.damageable.hull.hp > 0.0 and not cap.is_hulk()


# Passes, or until the rebalance leaves a miss pending with the numbers (no retune with T13, Q78 and Q81).
func _judge(met: bool, text: String) -> void:
	if met:
		assert_true(true, text)
	elif BARS_ASSERTED:
		assert_true(false, text)
	else:
		pending("until the capitals' rebalance (Q78, Q81): " + text)


func test_two_omegas_fight_for_four_to_eight_minutes() -> void:
	var lines := PackedStringArray()
	var in_bar: int = 0
	for seed_value: int in SEEDS:
		var r: Array = await _duel(seed_value)
		if r.is_empty():
			return
		lines.append("seed %d: %.0f s, winner at %.0f %%, loser at %.0f %%, interceptors took %.0f %% and %.0f %%" % [seed_value,
				r[0], 100.0 * float(r[1]), 100.0 * float(r[2]), _pct(r[3]), _pct(r[4])])
		if float(r[0]) >= DUEL_LASTS_S.x and float(r[0]) <= DUEL_LASTS_S.y:
			in_bar += 1
	gut.p("B1: " + "; ".join(lines))
	_judge(in_bar >= 2, "two Omegas fight %d to %d s, in 2 of %d seeds: %s" % [DUEL_LASTS_S.x, DUEL_LASTS_S.y, SEEDS.size(),
			"; ".join(lines)])
