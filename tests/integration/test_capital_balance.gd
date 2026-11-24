extends GutTest
## Balance fight B10 (docs/assets-capital.md, "Balance fights"; Q53, Q76): twelve allied Starfuries on engage at will against a
## lone hostile Omega holding still, none launched (T17) and no interceptors yet (T13). Q53's bar: the Omega lasts 10 to 15 min
## and the squadron loses about half. The real main scene, Jolt and the native core at the game's 60 Hz step, sped up.

const SCENARIO_PATH: String = "res://tests/fixtures/scenarios/capital_balance.json"
const SPEED_UP: float = 16.0
const LIMIT_S: float = 1200.0
## The Omega 9 km ahead of the player, out of its guns' and beams' reach; the squadron 3 km short of it, inside its sensors.
const OMEGA_AHEAD_M: float = 9000.0
const SEEDS: Array[int] = [1, 2, 3]
const DIAG_SEEDS: Array[int] = [1]
## The bar (Q53): the Omega lasts this long, s, and the squadron loses this many of its 12.
const LASTS_S: Vector2 = Vector2(600.0, 900.0)
const LOST: Vector2i = Vector2i(4, 8)

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


func _launch(seed_value: int) -> Main:
	var main := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = SCENARIO_PATH
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


func _spawn_omega(main: Main) -> CapitalShip:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(&"ea_omega", Factions.RAIDERS, "Raider Omega", rest)
	assert_not_null(cap, "the Omega is generated (scripts/gen_assets.sh)")
	if cap == null:
		return null
	var nose: Basis = main.ship.global_basis
	var basis: Basis = nose.rotated(nose.y, deg_to_rad(90.0))  # broadside on to the squadron's approach
	main.world.spawn(cap, main.world.to_universe(main.ship.global_position - nose.z * OMEGA_AHEAD_M), basis)
	cap.set_course(Vector3.ZERO, rest)
	return cap


# One fight: [seconds the Omega lasted (LIMIT_S when it held), Starfuries lost, its hull share left, damage from the squadron].
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
	rates.sort()
	var rate_text: String = "none" if rates.is_empty() else "median %.1f, p25 %.1f, p75 %.1f deg/s (%d)" % [rates[rates.size() / 2],
			rates[rates.size() / 4], rates[rates.size() * 3 / 4], rates.size()]
	gut.p("  seed %d marks: %s; squadron shots %d; its damage taken by cause and hit: %s; Starfuries 1-3 km off swing round the Omega at %s" % [
			seed_value, ", ".join(marks), shots[0], by_kind, rate_text])
	await _close(main)
	return [lasted, lost, left, taken[0]]


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
		lines.append("seed %d: %.0f s, %d lost, Omega at %.0f %%, %.0f taken" % [seed_value, r[0], r[1], 100.0 * float(r[2]), r[3]])
		if float(r[0]) >= LASTS_S.x and float(r[0]) <= LASTS_S.y and int(r[1]) >= LOST.x and int(r[1]) <= LOST.y:
			in_bar += 1
	gut.p("B10: " + "; ".join(lines))
	assert_gte(in_bar, 2, "the Omega lasts %d to %d s and the squadron loses %d to %d, in 2 of %d seeds: %s" % [LASTS_S.x, LASTS_S.y,
			LOST.x, LOST.y, SEEDS.size(), "; ".join(lines)])
