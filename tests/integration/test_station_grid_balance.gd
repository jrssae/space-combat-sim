extends GutTest
## The defence grid's balance (M7-T07, D75, AC6): the grid alone beats 12 raiders, or one capital ship (M4's capital stand-in in
## M7), as long as the enemy stays in its fire. "Beats" means the whole enemy force destroyed within the fight's limit; the
## station is never destroyed (Q5). Seeded and headless through the native core, three seeds each, as Q31 pinned the Saturns.
## A balance file, so behind `GUT_BALANCE`.
##
## - **The raid**: 12 raiders on the raider profile, ordered to attack the station (its name as their objective), start in a
##   loose box 0.8 to 1.6 km off the bow. They fire first; the grid answers.
## - **The capital**: a cruiser stand-in holding station 2.2 to 2.7 km off the bow tower (placed by the seed). The stand-in's own director picks fighters
##   only, so this file fires its weapons at the bow (its eight guns' bolts once a second each, its two beams every 2 s, a
##   missile every 3 s): the interceptors take its bolts and missiles, its beams get through (D75).

const RAID_SIZE: int = 12
const RAID_LIMIT_S: float = 180.0
const CAPITAL_LIMIT_S: float = 300.0
const SEEDS: Array[int] = [1, 2, 3]
const RAIDER: StringName = &"raider_fighter"
const RAIDER_AI: Dictionary = {"type": "ai", "profile": "raider", "orders": "attack", "objective": Station.DISPLAY_NAME}
const CAPITAL_CLASS: StringName = &"cruiser"
## The capital's weapons as this file fires them (the stand-ins' own cadences, M4-T07 and T12).
const GUN_INTERVAL_S: float = TurretStandin.SHOT_INTERVAL_S
const MISSILE_INTERVAL_S: float = 3.0
## Ticks per real tick: the physics rate and the time scale raised together, so each step is still 1/60 s of sim time.
const SPEED_UP: float = 8.0

var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


@warning_ignore("untyped_declaration")  # GutTest declares it untyped
func should_skip_script():
	return BalanceTests.skip_reason()


func before_each() -> void:
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame


func after_each() -> void:
	_restore_speed()


func test_the_grid_alone_beats_twelve_raiders() -> void:
	var lines := PackedStringArray()
	for seed_value: int in SEEDS:
		var f: Dictionary = await _fight(seed_value, false)
		if f.is_empty():
			pending("the babylon5_station asset is not generated")
			return
		lines.append("seed %d %s" % [seed_value, _line(f)])
		assert_true(bool(f["won"]), "seed %d: every raider destroyed inside %.0f s (%s)" % [seed_value, RAID_LIMIT_S, _line(f)])
	gut.p("BALANCE grid vs %d raiders:\n    %s" % [RAID_SIZE, "\n    ".join(lines)])


func test_the_grid_alone_beats_one_capital() -> void:
	var lines := PackedStringArray()
	for seed_value: int in SEEDS:
		var f: Dictionary = await _fight(seed_value, true)
		if f.is_empty():
			pending("the babylon5_station asset is not generated")
			return
		lines.append("seed %d %s" % [seed_value, _line(f)])
		assert_true(bool(f["won"]), "seed %d: the capital destroyed inside %.0f s (%s)" % [seed_value, CAPITAL_LIMIT_S, _line(f)])
		assert_gt(int(f["intercepts"]), 0, "seed %d: its bolts and missiles were shot down" % seed_value)
		assert_gt(int(f["beam_hits"]), 0, "seed %d: its beams got through" % seed_value)
	gut.p("BALANCE grid vs one %s stand-in:\n    %s" % [CAPITAL_CLASS, "\n    ".join(lines)])


# One fight: the station at the origin and the raid or the capital off its bow, flown until the enemy is destroyed or the limit.
func _fight(seed_value: int, capital: bool) -> Dictionary:
	await get_tree().process_frame
	await get_tree().physics_frame
	var scene: TurretScene = TurretScene.build(self, &"threaded", 1)
	var station := Station.new()
	station.name = "Station"
	if not station.build():
		station.free()
		await scene.free_scene(get_tree())
		return {}
	scene.world.spawn(station, scene.world.to_universe(Vector3.ZERO))
	var bow: Vector3 = station.to_world(station.hardpoints.mount("H1")["position"], StationHardpoints.FRAME)
	var enemies: Array[Node3D] = []
	var hulls: Array[Damageable] = []
	var cap: CapitalStandin = null
	if capital:
		cap = CapitalStandin.create(CAPITAL_CLASS, Factions.RAIDERS, "CRUISER", Vector3.ZERO)
		cap.world = scene.world
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var at: Vector3 = bow + Vector3(rng.randf_range(-400.0, 400.0), rng.randf_range(300.0, 700.0),
				-rng.randf_range(2200.0, 2700.0))
		scene.world.spawn(cap, scene.world.to_universe(at), Basis.looking_at((bow - at).normalized(), Vector3.UP))
		enemies.append(cap)
		hulls.append(cap.damageable)
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for i: int in RAID_SIZE:
			var at: Vector3 = bow + Vector3(rng.randf_range(-500.0, 500.0), rng.randf_range(150.0, 600.0),
					rng.randf_range(-1600.0, -800.0))
			var c: Combatant = scene.ship(RAIDER, Factions.RAIDERS, "RAIDER %d" % (i + 1), at, RAIDER_AI, seed_value * 100 + i,
					false, Basis.looking_at(Vector3.BACK, Vector3.UP))
			scene.park_on_death(c)
			enemies.append(c.ship)
			hulls.append(c.damageable)
	var health_before: float = _health(station)
	var beam_hits: Array[int] = [0]
	scene.resolver.hit_resolved.connect(func(info: HitInfo) -> void:
		if cap != null and info.shooter_id == cap.get_instance_id() and info.damage == BeamStandin.DAMAGE:
			beam_hits[0] += 1)
	scene.attach()
	TurretMount.rebind_all()
	await get_tree().physics_frame
	var t0: float = SimClock.now()
	var limit: float = CAPITAL_LIMIT_S if capital else RAID_LIMIT_S
	var next_gun: Array[float] = []
	if cap != null:
		for k: int in cap.guns().size():
			next_gun.append(t0 + GUN_INTERVAL_S * float(k) / float(cap.guns().size()))
	var next_beam: float = t0
	var next_missile: float = t0 + 0.5
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	var won: bool = false
	var in_fire_ticks: int = 0
	var ticks: int = 0
	while SimClock.now() - t0 < limit:
		await get_tree().physics_frame
		ticks += 1
		if hulls.all(func(h: Damageable) -> bool: return h.hull.destroyed):
			won = true
			break
		if cap != null and not cap.damageable.hull.destroyed:
			var now: float = SimClock.now()
			cap.step_engines(1.0 / 60.0)
			_capital_fire(cap, station, now, next_gun)
			if now >= next_beam:
				next_beam += BeamStandin.INTERVAL_S
				for k: int in cap.beams().size():
					cap.beams()[k].fire(_aim(station, k), now, scene.bolts)
			if now >= next_missile:
				next_missile += MISSILE_INTERVAL_S
				_missile(cap, station, scene, now)
		in_fire_ticks += 1 if _any_in_fire(station, enemies, hulls) else 0
	_restore_speed()
	var r: PackedInt64Array = station.grid.readouts()
	var left: int = hulls.filter(func(h: Damageable) -> bool: return not h.hull.destroyed).size()
	var f: Dictionary = {"won": won, "time_s": SimClock.now() - t0, "left": left, "light": r[0], "heavy": r[1],
			"intercepts": r[2], "missiles": r[3], "blocked": r[4], "station_lost": health_before - _health(station),
			"beam_hits": beam_hits[0], "in_fire": float(in_fire_ticks) / float(maxi(ticks, 1)),
			"capital_hull": cap.damageable.hull.fraction() if cap != null else -1.0}
	await scene.free_scene(get_tree())
	return f


# The capital's guns, each on its cadence, at the bow from where it sits.
func _capital_fire(cap: CapitalStandin, station: Station, now: float, next_gun: Array[float]) -> void:
	var guns: Array[TurretStandin] = cap.guns()
	for k: int in guns.size():
		if now < next_gun[k]:
			continue
		next_gun[k] += GUN_INTERVAL_S
		var from: Vector3 = guns[k].global_position
		var direction: Vector3 = (_aim(station, k) - from).normalized()
		TurretStandin.launch_bolt(cap, from, cap.linear_velocity + direction * TurretStandin.MUZZLE_SPEED_MPS, now)


# A missile from the capital's bow straight at the bow's hull (the stand-in's missile, unguided: its target does not move).
func _missile(cap: CapitalStandin, station: Station, scene: TurretScene, now: float) -> void:
	var from: Vector3 = cap.global_position - cap.global_basis.z * (cap.length_m() * 0.5 + 10.0)
	var missile := MissileStandin.PROJECTILE_SCENE.instantiate() as Projectile
	scene.bolts.add_child(missile)
	missile.configure(MissileStandin.weapon())
	missile.set_kind(Projectile.KIND_MISSILE)
	missile.shooter_id = cap.get_instance_id()
	missile.faction = cap.faction
	missile.launch(from, (_aim(station, 0) - from).normalized() * MissileStandin.SPEED_MPS, now)


# Where the capital aims: just under the bow's grid mounts, on the hull (H1, H2, the bow battery, the first spine station).
func _aim(station: Station, k: int) -> Vector3:
	var names: Array[String] = ["H1", "H2", "I5", "L9"]
	var entry: Dictionary = station.hardpoints.mount(names[k % names.size()])
	var under: Vector3 = (entry["position"] as Vector3) - (entry["up"] as Vector3).normalized() * 4.0
	return station.to_world(under, String(entry["body"]))


# Whether some live enemy is inside a light gun's range of its mount (a capital: a heavy cannon's).
static func _any_in_fire(station: Station, enemies: Array[Node3D], hulls: Array[Damageable]) -> bool:
	for i: int in enemies.size():
		if hulls[i].hull.destroyed:
			continue
		for m: TurretMount in station.grid.mounts:
			if m.grid_kind == StationGrid.Kind.INTERCEPTOR:
				continue
			if m.global_position.distance_to(enemies[i].global_position) <= m.weapon.turret_range_m:
				return true
	return false


static func _health(station: Station) -> float:
	var sum: float = 0.0
	for h: float in station.sections.health:
		sum += h
	return sum


func _restore_speed() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup


static func _line(f: Dictionary) -> String:
	return "%s at %.1f s, %d left, in fire %.0f %%, light %d, heavy %d shots, shot down %d (missiles %d), blocked %d, beams through %d, station lost %.0f, capital hull %.0f %%" % [
		"WIN" if bool(f["won"]) else "LOSS", float(f["time_s"]), int(f["left"]), 100.0 * float(f["in_fire"]), int(f["light"]),
		int(f["heavy"]), int(f["intercepts"]), int(f["missiles"]), int(f["blocked"]), int(f["beam_hits"]),
		float(f["station_lost"]), 100.0 * float(f["capital_hull"])]
