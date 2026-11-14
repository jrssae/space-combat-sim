extends GutTest
## A civilian fired on by a ship that is not its enemy (M7-T29, the maintainer's report: "when attacking a civilian vessel in
## free flight mode, it failed to run"). The player's bolts cannot land on a friendly or neutral hull, so no hit was ever
## heard; now any ship's fire that comes close frightens a civilian: it runs toward its own people and raises their alarm.
## Its turrets answer only a ship that had it selected (the maintainer: stray fire is fled from in silence), and then their
## bolts land on that ship alone. Flown through the native core; threaded against delayed and one thread against six.

const FREIGHTER: StringName = &"saturn_4_transport"
const FIGHTER: StringName = &"starfury_ally"
const CIVILIAN_AI: Dictionary = {"type": "ai", "profile": "civilian"}
const SPEED_UP: float = 4.0

## The most bolts in flight any tick of the last `_fly` saw.
var bolts_seen: int = 0
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


# A Saturn of the fighter's own people at the origin with a turret, a second Saturn 3 km ahead of it (its kin), and a
# Starfury 700 m astern, nose on the first Saturn, with no pilot: the test holds its trigger.
func _scene(mode: StringName = &"threaded", threads: int = 1) -> Dictionary:
	await get_tree().process_frame
	await get_tree().physics_frame
	var scene: TurretScene = TurretScene.build(self, mode, threads)
	var saturn: Combatant = scene.ship(FREIGHTER, Factions.EARTH_ALLIANCE, "SATURN", Vector3.ZERO, CIVILIAN_AI, 1, true)
	var kin: Combatant = scene.ship(FREIGHTER, Factions.EARTH_ALLIANCE, "KIN", Vector3(0.0, 0.0, -3000.0), CIVILIAN_AI, 2, true)
	var fighter: Combatant = scene.ship(FIGHTER, Factions.EARTH_ALLIANCE, "ALPHA 1", Vector3(0.0, 0.0, 700.0))
	var turret: TurretMount = scene.mount(saturn, Vector3(0.0, 30.0, 40.0))
	scene.attach()
	TurretMount.rebind_all()
	return {"scene": scene, "saturn": saturn, "kin": kin, "fighter": fighter, "turret": turret}


# Flies `seconds` of sim time with the fighter's trigger held or not; per tick the digests when `digests` is given.
func _fly(s: Dictionary, seconds: float, fire: bool, digests: Array = []) -> void:
	var scene: TurretScene = s["scene"]
	var fighter: Combatant = s["fighter"]
	var t0: float = SimClock.now()
	bolts_seen = 0
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	while SimClock.now() - t0 < seconds:
		var cmd := CombatCommand.new()
		cmd.fire = fire
		fighter.apply_commands(FlightCommand.new(), cmd)
		await get_tree().physics_frame
		bolts_seen = maxi(bolts_seen, int(scene.sim.core.bolt_count()))
		if not digests.is_empty():
			(digests[0] as Array).append(int(scene.sim.core.rows_digest()))
			(digests[1] as Array).append(int(scene.sim.core.commands_digest()))
			(digests[2] as Array).append(int(scene.sim.core.turret_digest()))
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup


func _describe(c: Combatant) -> Dictionary:
	var pilot := c.driver.brain as AiPilot if c.driver != null else null
	return pilot.describe() if pilot != null else {}


func test_stray_fire_from_a_friend_makes_a_civilian_run_to_its_kin_and_its_turrets_stay_silent() -> void:
	if _skipped():
		return
	var s: Dictionary = await _scene()
	var scene: TurretScene = s["scene"]
	var saturn: Combatant = s["saturn"]
	var kin: Combatant = s["kin"]
	await _fly(s, 3.0, false)
	assert_ne(String(_describe(saturn).get("behaviour", "")), "retreat", "at peace it does not run")
	var start: Vector3 = saturn.ship.global_position
	var speed_before: float = saturn.ship.linear_velocity.length()
	var hull_before: float = saturn.damageable.hull.fraction()
	await _fly(s, 4.0, true)
	assert_gt(bolts_seen, 0, "the fighter fired")
	var seen: Dictionary = _describe(saturn)
	assert_eq(String(seen.get("behaviour", "")), "retreat", "fired on, it runs: %s" % seen)
	assert_eq(String(_describe(kin).get("behaviour", "")), "retreat", "and its kin 3 km off hears the alarm")
	await _fly(s, 16.0, false)
	var moved: Vector3 = saturn.ship.global_position - start
	gut.p("stray fire: moved %s m, speed %.1f -> %.1f m/s, turret shots %d" % [moved.snappedf(1.0), speed_before,
			saturn.ship.linear_velocity.length(), scene.shots_total()])
	assert_gt(moved.length(), 100.0, "it changed its way: it flew off")
	assert_gt(saturn.ship.linear_velocity.length(), speed_before + 10.0, "and its speed")
	assert_lt(moved.normalized().dot(Vector3.BACK), 0.0, "away from the ship that fired, toward its kin")
	assert_eq(saturn.damageable.hull.fraction(), hull_before, "a friend's bolts still pass through it (no damage)")
	assert_eq(scene.shots_total(), 0, "stray fire: its turrets stay silent")
	assert_eq(int(scene.sim.core.provoked_count()), 0)
	await scene.free_scene(get_tree())


func test_a_civilian_fired_on_by_a_ship_that_selected_it_shoots_back_and_its_bolts_land_on_that_ship_only() -> void:
	if _skipped():
		return
	var s: Dictionary = await _scene()
	var scene: TurretScene = s["scene"]
	var saturn: Combatant = s["saturn"]
	var fighter: Combatant = s["fighter"]
	var bystander: Combatant = scene.ship(FIGHTER, Factions.EARTH_ALLIANCE, "ALPHA 2", Vector3(60.0, 80.0, 500.0))
	await _fly(s, 1.0, false)
	assert_true(fighter.ship.targeting.select_id(saturn.targetable.get_instance_id()), "the fighter selects the Saturn")
	fighter.damageable.invulnerable = false
	await _fly(s, 12.0, true)
	gut.p("targeted: turret shots %d, hits on the fighter %d, on the bystander %d, provoked pairs %d" % [scene.shots_total(),
			scene.hits_on(fighter, saturn), scene.hits_on(bystander), int(scene.sim.core.provoked_count())])
	assert_eq(String(_describe(saturn).get("behaviour", "")), "retreat", "it runs all the same")
	assert_gt(int(scene.sim.core.provoked_count()), 0, "the turrets remember who meant it")
	assert_gt(scene.shots_total(), 0, "and fire back")
	assert_gt(scene.hits_on(fighter, saturn), 0, "their bolts land on the ship that fired, though it is a friend")
	assert_eq(scene.hits_on(bystander), 0, "and on nobody else of its people")
	assert_eq(scene.hits_on(saturn), 0, "the fighter's own bolts still pass through the Saturn")
	await scene.free_scene(get_tree())


func test_threaded_equals_delayed_and_one_thread_equals_six() -> void:
	if _skipped():
		return
	var runs: Array = []
	for setup: Array in [[&"delayed", 6], [&"threaded", 6], [&"threaded", 1]]:
		var s: Dictionary = await _scene(setup[0], setup[1])
		var scene: TurretScene = s["scene"]
		var digests: Array = [[], [], []]
		(s["fighter"] as Combatant).ship.targeting.select_id((s["saturn"] as Combatant).targetable.get_instance_id())
		await _fly(s, 6.0, true, digests)
		runs.append(digests)
		await scene.free_scene(get_tree())
	for k: int in 3:
		var what: String = ["rows", "commands", "turrets"][k]
		assert_eq(runs[1][k], runs[0][k], "%s: threaded against delayed, the same bits" % what)
		assert_eq(runs[2][k], runs[1][k], "%s: one thread against six, the same bits" % what)
	assert_gt((runs[0][0] as Array).size(), 300)
