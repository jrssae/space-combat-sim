extends GutTest
## A capital's helm turning onto a course (M10-T16 fix round 2): the Nova and the Omega, told a heading 90 and 180 degrees off
## their bow (`capital helm 0 <yaw>`), turn onto it and settle level, their top back on the World's up, not left rolled. A
## half turn is flown as a turn, not a loop.

const SPEED_UP: float = 16.0
## Settled: the bow within this of its heading and the top within this of level, deg.
const BOW_DEG: float = 2.0
const LEVEL_DEG: float = 3.0

var main: Main
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8
var _tier_backup: Variant = null


func before_each() -> void:
	get_tree().paused = false
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame
	_tier_backup = Settings.get_value(&"tier_radius_m")
	Settings.set_value(&"tier_radius_m", 30000.0)
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.scenario_seed = 5
	add_child_autofree(main)
	await wait_physics_frames(2)
	DebugConsole.flags.invulnerable = true


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	Settings.set_value(&"tier_radius_m", _tier_backup)
	DebugConsole.flags.invulnerable = false


# `type` 4 km ahead of the player, level, at rest, told `yaw_deg` off its bow as `capital helm 0 <yaw>` does; flown until
# it settles. [the bow's error, the roll off level, the most it rolled on the way, the most it pitched], deg.
func _turn(type: StringName, yaw_deg: float) -> Array[float]:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(type, Factions.EARTH_ALLIANCE, "Turner", rest)
	assert_not_null(cap, "%s is generated (scripts/gen_assets.sh)" % type)
	if cap == null:
		return [180.0, 180.0, 180.0, 180.0]
	main.world.spawn(cap, main.world.to_universe(main.ship.global_position - main.ship.global_basis.z * 4000.0), Basis.IDENTITY)
	await wait_physics_frames(2)
	var heading: Vector3 = (-cap.global_basis.z).rotated(cap.global_basis.y, deg_to_rad(yaw_deg))
	cap.set_course(heading, rest)
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	var most_roll: float = 0.0
	var most_pitch: float = 0.0
	var t0: float = SimClock.now()
	var settled_s: float = 0.0
	while SimClock.now() - t0 < 600.0 and settled_s < 20.0:
		await get_tree().physics_frame
		most_roll = maxf(most_roll, _roll_deg(cap))
		most_pitch = maxf(most_pitch, rad_to_deg(absf(asin(clampf((-cap.global_basis.z).dot(Vector3.UP), -1.0, 1.0)))))
		var ok: bool = _bow_deg(cap, heading) < BOW_DEG and _roll_deg(cap) < LEVEL_DEG and cap.angular_velocity.length() < 1e-3
		settled_s = settled_s + get_physics_process_delta_time() * SPEED_UP if ok else 0.0
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	var out: Array[float] = [_bow_deg(cap, heading), _roll_deg(cap), most_roll, most_pitch]
	gut.p("%s %+.0f deg: bow off %.2f, roll %.2f (most %.1f), most pitch %.1f, after %.0f s" % [type, yaw_deg, out[0], out[1],
			out[2], out[3], SimClock.now() - t0])
	cap.queue_free()
	await wait_physics_frames(2)
	return out


func _bow_deg(cap: CapitalShip, heading: Vector3) -> float:
	return rad_to_deg((-cap.global_basis.z).angle_to(heading))


# How far the top leans off the World's up about the bow, deg.
func _roll_deg(cap: CapitalShip) -> float:
	var nose: Vector3 = -cap.global_basis.z
	var level: Vector3 = (Vector3.UP - nose * Vector3.UP.dot(nose)).normalized()
	return rad_to_deg(cap.global_basis.y.angle_to(level))


func test_the_nova_and_the_omega_turn_onto_a_course_and_settle_level() -> void:
	for type: StringName in [&"ea_nova", &"ea_omega"]:
		for yaw: float in [90.0, 180.0, -90.0]:
			var r: Array[float] = await _turn(type, yaw)
			assert_lt(r[0], BOW_DEG, "%s %+.0f: on its heading" % [type, yaw])
			assert_lt(r[1], LEVEL_DEG, "%s %+.0f: level again (roll %.1f deg)" % [type, yaw, r[1]])
			assert_lt(r[3], 10.0, "%s %+.0f: a turn, not a loop (pitched %.1f deg)" % [type, yaw, r[3]])
