extends GutTest
## The turrets' balance on every Saturn (M5-T16, Q31, AC19): a lone Saturn of any variant, with its own turrets and its
## spec after Q30's shared engine, beats two raiders now and then (1 to 3 of 10 seeds) and three raiders never. A fight runs
## until the Saturn is destroyed or no raider is left fighting (each destroyed or more than 5 km off), capped at 600 s of
## sim time; the Saturn wins when it is alive at the end. Seeded and headless through the native core, as
## `test_turret_defence`; slow (about a hundred fights), so behind `GUT_SLOW`. `TURRET_BALANCE_ONLY=<type>[:<raiders>]`
## runs one variant (and one raid size) while tuning.

const VARIANTS: Array[StringName] = [&"saturn_3_freighter", &"saturn_4_transport", &"saturn_4_tanker",
		&"saturn_8_transport", &"saturn_8_tanker"]
const SEEDS: int = 10
const CAP_S: float = 600.0
## A raider this far from the Saturn has left the fight.
const LEFT_M: float = 5000.0
const RAIDER_AI: Dictionary = {"type": "ai", "profile": "raider"}
const CIVILIAN_AI: Dictionary = {"type": "ai", "profile": "civilian"}
const ONLY_ENV: String = "TURRET_BALANCE_ONLY"
## Ticks per real tick: the physics rate and the time scale raised together, so each step is still 1/60 s of sim time.
const SPEED_UP: float = 8.0

var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


@warning_ignore("untyped_declaration")  # GutTest declares it untyped
func should_skip_script():
	return SlowTests.skip_reason()


func before_each() -> void:
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame


func after_each() -> void:
	_restore_speed()


func _skipped() -> bool:
	for type: StringName in VARIANTS:
		if not MeshAssets.read_manifest(String(type)).has("turret"):
			pending("%s is not generated (scripts/gen_assets.sh), so it has no turrets" % type)
			return true
	return false


func test_a_saturn_sometimes_beats_two_raiders() -> void:
	if _skipped():
		return
	for type: StringName in _variants(2):
		var wins: int = await _sweep(type, 2)
		assert_between(wins, 1, 3, "%s against two raiders wins 1 to 3 of %d (%d)" % [type, SEEDS, wins])


func test_a_saturn_never_beats_three_raiders() -> void:
	if _skipped():
		return
	for type: StringName in _variants(3):
		var wins: int = await _sweep(type, 3)
		assert_eq(wins, 0, "%s against three raiders never wins (%d of %d)" % [type, wins, SEEDS])


# The variants to fight `raiders` raiders: all, or the one `TURRET_BALANCE_ONLY` names.
func _variants(raiders: int) -> Array[StringName]:
	var only: String = OS.get_environment(ONLY_ENV)
	if only.is_empty():
		return VARIANTS
	var parts: PackedStringArray = only.split(":")
	if parts.size() > 1 and int(parts[1]) != raiders:
		return []
	return [StringName(parts[0])]


# Ten seeded fights of a lone `type` against `raiders` raiders; the Saturn's wins.
func _sweep(type: StringName, raiders: int) -> int:
	var wins: int = 0
	var lines := PackedStringArray()
	for seed_value: int in range(1, SEEDS + 1):
		var f: Dictionary = await _fight(type, raiders, seed_value)
		if bool(f["won"]):
			wins += 1
		lines.append("seed %d %s" % [seed_value, _line(f)])
	gut.p("BALANCE %s vs %d raiders: %d of %d won\n    %s" % [type, raiders, wins, SEEDS, "\n    ".join(lines)])
	return wins


# One fight: the Saturn at the origin on the civilian profile, `raiders` raiders 2.4 km off its bow and above.
func _fight(type: StringName, raiders: int, seed_value: int) -> Dictionary:
	await get_tree().process_frame
	var scene: TurretScene = TurretScene.build(self, &"threaded", 1)
	var saturn: Combatant = scene.ship(type, Factions.EARTH_ALLIANCE, "SATURN", Vector3.ZERO, CIVILIAN_AI, seed_value, true)
	var raider_ships: Array[Combatant] = []
	for i: int in raiders:
		var at := Vector3(-300.0 + 600.0 * i, 400.0, -2400.0 - 150.0 * i)
		raider_ships.append(scene.ship(&"raider_fighter", Factions.RAIDERS, "RAIDER %d" % (i + 1), at, RAIDER_AI,
				seed_value * 10 + i, false, Basis.looking_at(-at.normalized(), Vector3.UP)))
	for c: Combatant in scene.ships:
		scene.park_on_death(c)
	scene.attach()
	await get_tree().physics_frame
	var t0: float = SimClock.now()
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	var end: String = "cap"
	while SimClock.now() - t0 < CAP_S:
		await get_tree().physics_frame
		if saturn.damageable.hull.destroyed:
			end = "destroyed"
			break
		if raider_ships.all(func(r: Combatant) -> bool: return _out_of_fight(r, saturn)):
			end = "raiders gone"
			break
	_restore_speed()
	var f: Dictionary = {"won": not saturn.damageable.hull.destroyed, "end": end, "time_s": SimClock.now() - t0,
			"hull": saturn.damageable.hull.fraction(),
			"raiders": raider_ships.map(func(r: Combatant) -> String:
				return "dead" if r.damageable.hull.destroyed else ("left %.0f%%" % (100.0 * r.damageable.hull.fraction())
						if _out_of_fight(r, saturn) else "%.0f%%" % (100.0 * r.damageable.hull.fraction()))),
			"turret_shots": scene.shots_total(),
			"turret_hits": raider_ships.reduce(func(n: int, r: Combatant) -> int: return n + scene.hits_on(r, saturn), 0)}
	await scene.free_scene(get_tree())
	return f


static func _out_of_fight(r: Combatant, saturn: Combatant) -> bool:
	return r.damageable.hull.destroyed or r.ship.global_position.distance_to(saturn.ship.global_position) > LEFT_M


func _restore_speed() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup


static func _line(f: Dictionary) -> String:
	return "%s: %s at %.1f s, Saturn %.0f %%, raiders %s, turrets %d hits of %d shots" % [
		"WIN" if bool(f["won"]) else "loss", String(f["end"]), float(f["time_s"]), 100.0 * float(f["hull"]),
		str(f["raiders"]), int(f["turret_hits"]), int(f["turret_shots"])]
