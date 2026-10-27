extends GutTest
## AC10, the demo moves in Jolt (M3-T09, architecture §16 D37): each of the five `Manoeuvres` flies a real allied Starfury
## (`starfury_ally`, the instructor's hull, assist forced on as every AI ship) through the real flight model and the real
## `AiPilotDriver` (avoidance included), from 60 m/s straight ahead, at the game's 60 Hz step. The test measures each goal
## from the body's own motion, not from the move's report: the up axis's turn about the nose (roll), the velocity against
## the starting one (flip and burn), the displacement in the frame moving with the starting velocity (strafe box), the
## heading against the starting one (pod turn), the speed and turn rate (all stop).
##
## The five ships fly at once in one world, 6 km apart (no ship's avoidance sees another on a collision course).

const ALLY_TYPE: StringName = &"starfury_ally"
const START_MPS: float = 60.0
const APART_M: float = 6000.0
## Sim seconds the slowest move (the strafe box, about 20 s) may take, and the settling after a move ends.
const MAX_S: float = 40.0
const SETTLE_S: float = 1.0

var _scale_backup: float = 1.0


## Flies one `Manoeuvre` and nothing else.
class ManoeuvreBrain extends PilotBrain:
	var move: Manoeuvre

	func _init(p_move: Manoeuvre) -> void:
		move = p_move
		wanted_target_id = PilotBrain.TARGET_NONE

	func think(p: Perception, dt: float) -> PilotCommand:
		var cmd := PilotCommand.new()
		cmd.flight = move.step(p, dt)
		desired_velocity = move.desired_velocity
		has_desired_velocity = move.has_desired_velocity
		return cmd


func before_each() -> void:
	_scale_backup = Engine.time_scale
	Engine.time_scale = 1.0
	ContactScan.invalidate()


func after_each() -> void:
	Engine.time_scale = _scale_backup
	ContactScan.invalidate()


func _run_for(demo: StringName, world: WorldFrame, projectiles: Node3D, at: Vector3) -> Dictionary:
	var c: Combatant = ShipAssembly.build(ShipCatalog.spec_for(ALLY_TYPE), world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: "ALPHA %s" % demo,
		ShipAssembly.OPT_FORCE_ASSIST: true,
		ShipAssembly.OPT_AI: true,
	})
	world.spawn(c.ship, world.to_universe(at))
	var move: Manoeuvre = Manoeuvres.create(demo)
	return {"demo": demo, "combatant": c, "move": move, "ticks": 0, "done_tick": -1, "settled": false,
			"start": Vector3.ZERO, "v0": Vector3.ZERO, "forward0": Vector3.ZERO, "right0": Vector3.ZERO,
			"up_prev": Vector3.ZERO, "rolled_rad": 0.0, "peak_roll_dps": 0.0, "corners": [] as Array[Vector3],
			"legs_done": 0, "at_done": {}, "main_left_max": 0.0, "main_right_max": 0.0}


# Every tick, after the drivers and the ships (the body as the next perception will see it).
func _sample(run: Dictionary, dt: float) -> void:
	var c: Combatant = run["combatant"]
	var ship: Ship = c.ship
	var move: Manoeuvre = run["move"]
	var ticks: int = run["ticks"]
	if ticks == 0:
		run["start"] = ship.global_position
		run["v0"] = ship.linear_velocity
		run["forward0"] = ship.forward()
		run["right0"] = ship.global_basis.x
		run["up_prev"] = ship.global_basis.y
	run["ticks"] = ticks + 1
	var t: float = float(ticks) * dt  # since the move's first tick (the first sample sees the same, unstepped body)
	var up: Vector3 = ship.global_basis.y
	run["rolled_rad"] = float(run["rolled_rad"]) + atan2((run["up_prev"] as Vector3).cross(up).dot(ship.forward()),
			(run["up_prev"] as Vector3).dot(up))
	run["up_prev"] = up
	run["peak_roll_dps"] = maxf(float(run["peak_roll_dps"]), absf(rad_to_deg(ship.body_angular_velocity().z)))
	var levels: PackedFloat64Array = ship.get_flight_output().group_levels
	if levels.size() == ThrusterLayout.GROUP_COUNT and not move.done:
		run["main_left_max"] = maxf(float(run["main_left_max"]), levels[ThrusterLayout.Group.L_MAIN])
		run["main_right_max"] = maxf(float(run["main_right_max"]), levels[ThrusterLayout.Group.R_MAIN])
	var rel: Vector3 = ship.global_position - (run["start"] as Vector3) - (run["v0"] as Vector3) * t
	if move.id == &"strafe_box":
		var legs: int = int(move.result()["legs_done"])
		if legs != int(run["legs_done"]):
			(run["corners"] as Array[Vector3]).append(rel)
			run["legs_done"] = legs
	if move.done and int(run["done_tick"]) < 0:
		run["done_tick"] = ticks + 1
		run["at_done"] = _measure(run, rel)
	if int(run["done_tick"]) >= 0 and float(ticks + 1 - int(run["done_tick"])) * dt >= SETTLE_S and not bool(run["settled"]):
		run["settled"] = true
		run["settled_measure"] = _measure(run, rel)


func _measure(run: Dictionary, rel: Vector3) -> Dictionary:
	var ship: Ship = (run["combatant"] as Combatant).ship
	var nose: Vector3 = ship.forward()
	var v0: Vector3 = run["v0"]
	return {"roll_deg": rad_to_deg(float(run["rolled_rad"])),
			"speed_mps": ship.linear_velocity.length(),
			"along_mps": ship.linear_velocity.dot(v0.normalized()),
			"rate_dps": rad_to_deg(ship.angular_velocity.length()),
			"yaw_deg": rad_to_deg(atan2(nose.dot(run["right0"]), nose.dot(run["forward0"]))),
			"rel": rel}


func test_each_demo_meets_its_goal_in_jolt() -> void:
	var world := WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	var runs: Array[Dictionary] = []
	for i: int in Manoeuvres.NAMES.size():
		runs.append(_run_for(Manoeuvres.NAMES[i], world, projectiles, Vector3(APART_M * (float(i) - 2.0), 0.0, 0.0)))
	await get_tree().physics_frame
	for run: Dictionary in runs:
		var c: Combatant = run["combatant"]
		c.ship.linear_velocity = Vector3(0.0, 0.0, -START_MPS)
		c.driver.brain = ManoeuvreBrain.new(run["move"] as Manoeuvre)
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var ticker := PhysicsTicker.new()
	ticker.on_tick = func() -> void:
		for run: Dictionary in runs:
			_sample(run, dt)
	add_child_autofree(ticker)
	var max_ticks: int = roundi((MAX_S + SETTLE_S) / dt)
	while ticker.ticks < max_ticks:
		await get_tree().physics_frame
		var all_settled: bool = true
		for run: Dictionary in runs:
			all_settled = all_settled and bool(run["settled"])
		if all_settled:
			break
	var by_demo: Dictionary = {}
	for run: Dictionary in runs:
		var move: Manoeuvre = run["move"]
		assert_true(move.done, "%s finished" % run["demo"])
		assert_false(move.timed_out, "%s met its goal before the timeout" % run["demo"])
		assert_true(bool(run["settled"]), "%s settled" % run["demo"])
		by_demo[run["demo"]] = run
		if not bool(run["settled"]):
			return
		gut.p("%s: %.2f s, report %s" % [run["demo"], float(run["done_tick"]) * dt, str(move.result())])
	_check_roll(by_demo[&"roll"])
	_check_flip_and_burn(by_demo[&"flip_and_burn"])
	_check_strafe_box(by_demo[&"strafe_box"])
	_check_pod_turn(by_demo[&"pod_turn"])
	_check_all_stop(by_demo[&"all_stop"])


func _check_roll(run: Dictionary) -> void:
	var done: Dictionary = run["at_done"]
	var settled: Dictionary = run["settled_measure"]
	gut.p("roll: up axis turned %.1f deg at the end, %.1f deg settled; peak %.1f deg/s; nose moved %.2f deg" % [done["roll_deg"],
			settled["roll_deg"], run["peak_roll_dps"], abs(settled["yaw_deg"])])
	assert_almost_eq(float(settled["roll_deg"]), 360.0, 10.0, "roll 360 +- 10 degrees")
	assert_almost_eq(float(run["peak_roll_dps"]), 90.0, 2.0, "at the roll rate limit")


func _check_flip_and_burn(run: Dictionary) -> void:
	var done: Dictionary = run["at_done"]
	var settled: Dictionary = run["settled_measure"]
	gut.p("flip and burn: at the end %.2f m/s (%.2f along the start), settled %.2f m/s; mains up to %.2f / %.2f" % [
			done["speed_mps"], done["along_mps"], settled["speed_mps"], run["main_left_max"], run["main_right_max"]])
	assert_true(float(done["along_mps"]) < 0.0 or float(done["speed_mps"]) < 2.0, "velocity reversed or under 2 m/s")
	assert_true(float(settled["along_mps"]) < 0.0 or float(settled["speed_mps"]) < 2.0, "and it stays so")
	assert_almost_eq(float(run["main_left_max"]), 1.0, 1e-6, "the mains burned at full")


func _check_strafe_box(run: Dictionary) -> void:
	var corners: Array[Vector3] = run["corners"]
	assert_eq(corners.size(), 4, "four legs")
	if corners.size() != 4:
		return
	var right: Vector3 = run["right0"]
	var up: Vector3 = (run["forward0"] as Vector3).cross(right).normalized() * -1.0
	var directions: Array[Vector3] = [right, up, -right, -up]
	var legs := PackedFloat64Array()
	var previous := Vector3.ZERO
	for i: int in 4:
		var leg: Vector3 = corners[i] - previous
		legs.append(leg.length())
		assert_gt(leg.normalized().dot(directions[i]), 0.98, "leg %d along its axis" % (i + 1))
		assert_gt(leg.length(), 40.0, "leg %d over 40 m" % (i + 1))
		previous = corners[i]
	var settled: Dictionary = run["settled_measure"]
	gut.p("strafe box: legs %s m, back within %.2f m of the moving start (%.2f m a second later), nose moved %.2f deg" % [
			str(legs), corners[3].length(), (settled["rel"] as Vector3).length(), abs(settled["yaw_deg"])])
	assert_lt(corners[3].length(), 30.0, "returns within 30 m of its start")


func _check_pod_turn(run: Dictionary) -> void:
	var done: Dictionary = run["at_done"]
	var settled: Dictionary = run["settled_measure"]
	gut.p("pod turn: %.1f deg right at the end, %.1f deg settled; left main up to %.2f, right main %.2f" % [done["yaw_deg"],
			settled["yaw_deg"], run["main_left_max"], run["main_right_max"]])
	assert_gt(float(settled["yaw_deg"]), 30.0, "the nose turned right by over 30 degrees")
	assert_gt(float(run["main_left_max"]), 0.0, "on the left main")
	assert_eq(float(run["main_right_max"]), 0.0, "alone")


func _check_all_stop(run: Dictionary) -> void:
	var done: Dictionary = run["at_done"]
	var settled: Dictionary = run["settled_measure"]
	gut.p("all stop: at the end %.3f m/s and %.3f deg/s; settled %.3f m/s and %.3f deg/s" % [done["speed_mps"], done["rate_dps"],
			settled["speed_mps"], settled["rate_dps"]])
	assert_lt(float(done["speed_mps"]), 0.5, "below 0.5 m/s")
	assert_lt(float(done["rate_dps"]), 1.0, "and 1 degree/s")
