extends GutTest
## How civilians flee (M5-T16, Q24, Q25, AC13) through the native core on seeded scenes: a freighter under threat runs to the
## far side of a warship of its own people (not to a nearer ship of another people), panic spreads to its people's
## civilians within about radar range and no farther, and two attacked freighters close up; one on its route turns from a raider
## and keeps running, and one under fire runs without jinking while its turrets answer (M7-T55). The flight is the native
## brains' (`native/src/civilian.rs` through the retreat), one tick behind on the frozen rows; the same fight gives the same bits
## with the job on its thread and on the main thread, and with one thread and six. Skips, saying why, without the native
## library or the Saturn 4's generated asset.

const FREIGHTER: StringName = &"saturn_4_transport"
const CIVILIAN_AI: Dictionary = {"type": "ai", "profile": "civilian"}
const RAIDER_AI: Dictionary = {"type": "ai", "profile": "raider"}
const IDLE: Dictionary = {"type": "idle"}
## Ticks per real tick: the physics rate and the time scale raised together, so each step is still 1/60 s of sim time.
const SPEED_UP: float = 4.0
const TICKS: int = 300

var _rate_backup: int = 60
var _scale_backup: float = 1.0


func before_each() -> void:
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup


func _skipped() -> bool:
	if not Hardpoints.load_file(ShipCatalog.spec_for(FREIGHTER).hardpoints_path()).valid:
		pending("the Saturn 4 is not generated (scripts/gen_assets.sh)")
		return true
	return false


func test_an_attacked_freighter_shelters_behind_a_warship_of_its_people() -> void:
	if _skipped():
		return
	var scene: TurretScene = await _scene()
	var raider_at := Vector3(0.0, 0.0, -1500.0)
	var freighter: Combatant = scene.ship(FREIGHTER, Factions.EARTH_ALLIANCE, "SATURN", Vector3.ZERO, CIVILIAN_AI, 1, true)
	scene.ship(&"raider_fighter", Factions.RAIDERS, "RAIDER", raider_at, IDLE, 2)
	var starfury: Combatant = scene.ship(&"starfury_ally", Factions.EARTH_ALLIANCE, "ALPHA", Vector3(900.0, 0.0, 0.0), IDLE, 3)
	scene.ship(&"narn_transport", &"narn", "NARN", Vector3(350.0, 0.0, 0.0), IDLE, 4, true)
	scene.attach()
	await _fly(scene, 4.0)
	var seen: Dictionary = _describe(freighter)
	assert_eq(String(seen.get("behaviour", "")), "retreat", "it runs: %s" % seen)
	assert_eq(String(seen.get("state", "")), "shelter", "to a warship: %s" % seen)
	assert_eq(String(seen.get("goal", "")), "ALPHA", "the Starfury, not the nearer Narn ship: %s" % seen)
	var start: Vector3 = freighter.ship.global_position
	await _fly(scene, 20.0)
	var at: Vector3 = freighter.ship.global_position
	var warship: Vector3 = starfury.ship.global_position
	var far_side: Vector3 = (warship - raider_at).normalized()
	var moved: Vector3 = at - start
	gut.p("shelter: moved %s m (%.0f m) toward the far side %s" % [moved.snappedf(1.0), moved.length(), far_side.snappedf(0.01)])
	assert_gt(moved.length(), 100.0, "it flew")
	var point: Vector3 = warship + far_side * maxf(3.0 * freighter.damageable.bounding_radius, 150.0)
	assert_gt(moved.normalized().dot((point - start).normalized()), 0.8, "toward the point beyond the warship from the raider")
	assert_lt(at.distance_to(point), start.distance_to(point), "closer to it than it started")
	await scene.free_scene(get_tree())


func test_panic_spreads_to_kin_within_radar_range_and_no_farther() -> void:
	if _skipped():
		return
	var scene: TurretScene = await _scene()
	var attacked: Combatant = scene.ship(FREIGHTER, Factions.EARTH_ALLIANCE, "ATTACKED", Vector3.ZERO, CIVILIAN_AI, 1, true)
	scene.ship(&"raider_fighter", Factions.RAIDERS, "RAIDER", Vector3(0.0, 0.0, -1500.0), IDLE, 2)
	# 4.5 km from the attacked one and 4.7 km from the raider (seen, but beyond the 3 km that sets a civilian running).
	var near: Combatant = scene.ship(FREIGHTER, Factions.EARTH_ALLIANCE, "NEAR", Vector3(4500.0, 0.0, 0.0), CIVILIAN_AI, 3, true)
	# 6 km from the attacked one: beyond its alarm, and beyond the raider's sensors.
	var far: Combatant = scene.ship(FREIGHTER, Factions.EARTH_ALLIANCE, "FAR", Vector3(-6000.0, 0.0, 0.0), CIVILIAN_AI, 4, true)
	scene.attach()
	await _fly(scene, 6.0)
	assert_eq(String(_describe(attacked).get("behaviour", "")), "retreat", "the attacked one runs")
	assert_eq(String(_describe(near).get("behaviour", "")), "retreat", "its kin within radar range runs too: %s" % _describe(near))
	assert_ne(String(_describe(far).get("behaviour", "")), "retreat", "kin beyond it does not: %s" % _describe(far))
	await scene.free_scene(get_tree())


func test_two_attacked_freighters_end_closer_together() -> void:
	if _skipped():
		return
	var scene: TurretScene = await _scene()
	# A raider between them and ahead: alone, each would run away from it, out and apart.
	var a: Combatant = scene.ship(FREIGHTER, Factions.EARTH_ALLIANCE, "SATURN A", Vector3(-750.0, 0.0, 0.0), CIVILIAN_AI, 1, true)
	var b: Combatant = scene.ship(FREIGHTER, Factions.EARTH_ALLIANCE, "SATURN B", Vector3(750.0, 0.0, 0.0), CIVILIAN_AI, 2, true)
	scene.ship(&"raider_fighter", Factions.RAIDERS, "RAIDER", Vector3(0.0, 0.0, -1000.0), IDLE, 3)
	scene.attach()
	var before: float = a.ship.global_position.distance_to(b.ship.global_position)
	await _fly(scene, 30.0)
	var after: float = a.ship.global_position.distance_to(b.ship.global_position)
	gut.p("grouping: %.0f m apart, then %.0f m after 30 s (%s, %s)" % [before, after, _describe(a).get("state"),
			_describe(b).get("state")])
	assert_lt(after, before - 100.0, "they closed up")
	assert_gt(a.ship.global_position.z + b.ship.global_position.z, 100.0, "while running away from the raider")
	await scene.free_scene(get_tree())


func test_a_freighter_on_its_route_turns_from_a_raider_ahead_toward_shelter() -> void:
	# M7-T55 (m5-054): a civilian on its way kept flying its route at the raider; now it turns round and burns for the far
	# side of a warship of its people, keeping at it while the raider is in sight.
	if _skipped():
		return
	var scene: TurretScene = await _scene()
	var freighter: Combatant = scene.ship(FREIGHTER, Factions.EARTH_ALLIANCE, "SATURN", Vector3.ZERO, CIVILIAN_AI, 1, true)
	var route := Route.new()
	route.pace = Route.PACE_NONE
	route.cruise_mps = 40.0
	route.add(scene.world.to_universe(Vector3(0.0, 0.0, -30000.0)))
	BehaviourFollowPath.attach(freighter.driver.brain as AiPilot, route)
	freighter.ship.linear_velocity = Vector3(0.0, 0.0, -40.0)
	var raider_at := Vector3(0.0, 0.0, -3600.0)
	scene.ship(&"raider_fighter", Factions.RAIDERS, "RAIDER", raider_at, IDLE, 2)
	var starfury: Combatant = scene.ship(&"starfury_ally", Factions.EARTH_ALLIANCE, "ALPHA", Vector3(2500.0, 0.0, 1500.0), IDLE, 3)
	scene.attach()
	await _fly(scene, 3.0)
	assert_eq(String(_describe(freighter).get("behaviour", "")), "follow_path", "on its way while the raider is far")
	var onset: Array[float] = [-1.0]
	await _fly_until(scene, 30.0, func() -> bool:
		if String(_describe(freighter).get("behaviour", "")) == "retreat":
			onset[0] = SimClock.now()
		return onset[0] >= 0.0)
	assert_gte(onset[0], 0.0, "it runs once the raider is within its flee range")
	var point: Vector3 = starfury.ship.global_position + (starfury.ship.global_position - raider_at).normalized() \
			* maxf(3.0 * freighter.damageable.bounding_radius, 150.0)
	var from_raider: float = freighter.ship.global_position.distance_to(raider_at)
	var from_point: float = freighter.ship.global_position.distance_to(point)
	var kinds: Dictionary = {}
	await _fly_until(scene, 60.0, func() -> bool:
		kinds[String(_describe(freighter).get("behaviour", ""))] = true
		return false)
	var now_raider: float = freighter.ship.global_position.distance_to(raider_at)
	var now_point: float = freighter.ship.global_position.distance_to(point)
	gut.p("route flee: from the raider %.0f -> %.0f m, from the shelter %.0f -> %.0f m, behaviours %s" % [from_raider,
			now_raider, from_point, now_point, kinds.keys()])
	assert_eq(kinds.keys(), ["retreat"], "it kept running, never back onto its route")
	assert_gt(now_raider, from_raider + 300.0, "away from the raider")
	assert_lt(now_point, from_point - 300.0, "toward the shelter beyond the Starfury")
	await scene.free_scene(get_tree())


func test_fired_on_it_runs_without_jinking_while_its_turrets_answer() -> void:
	# M7-T55: a hit no longer throws a freighter into a fighter's jink (which held it where it was); it keeps running, its
	# turrets firing back.
	if _skipped():
		return
	var scene: TurretScene = await _scene()
	var freighter: Combatant = scene.ship(FREIGHTER, Factions.EARTH_ALLIANCE, "SATURN", Vector3.ZERO, CIVILIAN_AI, 1, true)
	var starfury: Combatant = scene.ship(&"starfury_ally", Factions.EARTH_ALLIANCE, "ALPHA", Vector3(2000.0, 0.0, 1500.0), IDLE, 3)
	var raiders: Array[Combatant] = []
	for i: int in 2:
		var at := Vector3(-300.0 + 600.0 * i, 100.0, -3500.0)
		raiders.append(scene.ship(&"raider_fighter", Factions.RAIDERS, "RAIDER %d" % (i + 1), at,
				{"type": "ai", "profile": "raider", "orders": "attack", "objective": "SATURN"}, 11 + i, false,
				Basis.looking_at(-at.normalized(), Vector3.UP)))
	scene.attach()
	var hits: Array[int] = [0]
	freighter.damageable.hit_taken.connect(func(_info: HitInfo) -> void: hits[0] += 1)
	var kinds: Dictionary = {}
	var start: Vector3 = freighter.ship.global_position
	await _fly_until(scene, 45.0, func() -> bool:
		if not freighter.damageable.is_active():
			return true
		var kind: String = String(_describe(freighter).get("behaviour", ""))
		if not kinds.is_empty() or kind == "retreat":
			kinds[kind] = true
		return false)
	var moved: Vector3 = freighter.ship.global_position - start
	var to_shelter: Vector3 = (starfury.ship.global_position - start).normalized()
	gut.p("fired on: %d hits, behaviours from the first flight %s, turret shots %d, moved %s" % [hits[0], kinds.keys(),
			scene.shots_total(), moved.snappedf(1.0)])
	assert_gt(hits[0], 0, "the raiders hit it")
	assert_true(kinds.has("retreat"), "it ran")
	assert_false(kinds.has("evade"), "and never jinked where it was: %s" % [kinds.keys()])
	assert_gt(scene.shots_total(), 0, "its turrets fired back while it ran")
	assert_gt(moved.dot(to_shelter), 100.0, "toward the Starfury's side")
	await scene.free_scene(get_tree())


func test_threaded_equals_delayed_tick_for_tick() -> void:
	if _skipped():
		return
	var delayed: Dictionary = await _seeded_fight(&"delayed", 6)
	var threaded: Dictionary = await _seeded_fight(&"threaded", 6)
	assert_gt(int(delayed["fleeing"]), 0, "civilians fled in the fight")
	for key: String in ["rows", "commands"]:
		var first: int = _first_difference(delayed[key], threaded[key])
		assert_eq(first, -1, "%s: the same bits every tick (first difference at tick %d)" % [key, first])


func test_one_thread_and_six_give_the_same_flight() -> void:
	if _skipped():
		return
	var one: Dictionary = await _seeded_fight(&"threaded", 1)
	var six: Dictionary = await _seeded_fight(&"threaded", 6)
	for key: String in ["rows", "commands"]:
		var first: int = _first_difference(one[key], six[key])
		assert_eq(first, -1, "%s: the same bits with one thread and six (first difference at tick %d)" % [key, first])


# A fresh scene on the threaded step with one thread.
func _scene(mode: StringName = &"threaded", threads: int = 1) -> TurretScene:
	await get_tree().process_frame
	await get_tree().physics_frame
	return TurretScene.build(self, mode, threads)


# Flies the scene `seconds` of sim time, `SPEED_UP` ticks a real tick.
func _fly(scene: TurretScene, seconds: float) -> void:
	var t0: float = SimClock.now()
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	while SimClock.now() - t0 < seconds:
		await get_tree().physics_frame
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	assert_not_null(scene.sim, "the core is attached")


# Flies the scene until `done` says so or `seconds` of sim time pass, `SPEED_UP` ticks a real tick.
func _fly_until(scene: TurretScene, seconds: float, done: Callable) -> void:
	var t0: float = SimClock.now()
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	while SimClock.now() - t0 < seconds and not bool(done.call()):
		await get_tree().physics_frame
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	assert_not_null(scene.sim, "the core is attached")


func _describe(c: Combatant) -> Dictionary:
	var pilot := c.driver.brain as AiPilot if c.driver != null else null
	return pilot.describe() if pilot != null else {}


# Three freighters of two peoples, a Starfury and two attacking raiders: `TICKS` ticks with the step `mode` and `threads`
# threads; per tick the rows' and the commands' digests.
func _seeded_fight(mode: StringName, threads: int) -> Dictionary:
	var scene: TurretScene = await _scene(mode, threads)
	var civilians: Array[Combatant] = [
		scene.ship(FREIGHTER, Factions.EARTH_ALLIANCE, "SATURN A", Vector3(-750.0, 0.0, 0.0), CIVILIAN_AI, 1, true),
		scene.ship(FREIGHTER, Factions.EARTH_ALLIANCE, "SATURN B", Vector3(750.0, 0.0, 0.0), CIVILIAN_AI, 2, true),
		scene.ship(&"narn_transport", &"narn", "NARN", Vector3(0.0, 400.0, 1200.0), CIVILIAN_AI, 3, true),
	]
	scene.ship(&"starfury_ally", Factions.EARTH_ALLIANCE, "ALPHA", Vector3(1500.0, 0.0, 800.0), IDLE, 4)
	for i: int in 2:
		var at := Vector3(-400.0 + 800.0 * i, 200.0, -1600.0)
		scene.ship(&"raider_fighter", Factions.RAIDERS, "RAIDER %d" % (i + 1), at, RAIDER_AI, 11 + i, false,
				Basis.looking_at(-at.normalized(), Vector3.UP))
	scene.attach()
	var rows := PackedInt64Array()
	var commands := PackedInt64Array()
	var fleeing: int = 0
	for t: int in TICKS:
		await get_tree().physics_frame
		rows.append(int(scene.sim.core.rows_digest()))
		commands.append(int(scene.sim.core.commands_digest()))
	for c: Combatant in civilians:
		if String(_describe(c).get("behaviour", "")) in ["retreat", "evade"]:
			fleeing += 1
	await scene.free_scene(get_tree())
	return {"rows": rows, "commands": commands, "fleeing": fleeing}


static func _first_difference(a: PackedInt64Array, b: PackedInt64Array) -> int:
	for i: int in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return i
	return -1 if a.size() == b.size() else mini(a.size(), b.size())
