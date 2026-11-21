extends GutTest
## A gate jump asked at speed (M8-T18, D84, AC14) on the real main scene: the ship flies at the gate on its axis, is offered the
## jump at the speed-scaled reach, holds X, and the autopilot takes it as it comes: line-up (an overshoot and a turn back when it is
## too fast to stop), the run-in, the departure shot timed from the predicted arrival at the mouth, out through the orange vortex
## and back through the blue one. Far from the gate sim time is sped up with `Engine.time_scale`; near it the step is the game's.

const SPEED_UP: float = 8.0
## Beyond this from the gate the sped-up step is safe: nothing to hit, nothing timed.
const FAST_BEYOND_M: float = 25000.0

var main: Main
var source: FakeInputSource
var gate: Jumpgate
var _scale_backup: float = 1.0
var _steps_backup: int = 8


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame


func after_each() -> void:
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	get_tree().paused = false
	ContactScan.invalidate()


func _start() -> void:
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.raider_pool_size = 0
	main.ally_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(2)
	gate = main.gates.gate()


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func test_a_jump_asked_at_200_mps_runs_through_the_mouth() -> void:
	await _jump_at(200.0)


func test_a_jump_asked_at_1_km_s_runs_through_the_mouth() -> void:
	await _jump_at(1000.0)


func test_a_jump_asked_at_3_km_s_overshoots_turns_and_runs_through_the_mouth() -> void:
	if OS.get_environment("GUT_SLOW") != "1":
		pending("slow: a 3 km/s jump flies about five minutes of sim time (GUT_SLOW=1)")
		return
	await _jump_at(3000.0)


# The player on the gate's axis just inside the reach for `speed`, flying at the gate, asks for the jump with a 2 s hold of X.
func _jump_at(speed: float) -> void:
	await _start()
	assert_not_null(gate)
	var capability: ShipCapability = main.gates.ship_capability()
	var reach: float = GateJumpRequest.range_m(speed, capability.a_main)
	var at: Vector3 = gate.global_transform * Vector3(0.0, 0.0, -(reach - 150.0))
	main.ship.reset_to(Transform3D(Basis.looking_at(gate.global_position - at, gate.global_basis.y), at))
	assert_true(main.ship.targeting.select_id(gate.targetable.get_instance_id()))
	var inbound: Vector3 = (gate.global_position - at).normalized()
	main.ship.linear_velocity = main.world.anchored_velocity() + inbound * speed
	await _ticks(1)
	main.ship.linear_velocity = main.world.anchored_velocity() + inbound * speed
	assert_almost_eq(main.gates.request_range_m(gate), reach, reach * 0.02, "%.0f m/s: offered from %.1f km" % [speed, reach / 1000.0])
	assert_not_null(main.interactions.offer(), "the hold is offered at the speed-scaled reach")
	assert_not_null(main.interactions.cue(), "and the cue shows")
	assert_string_contains(main.interactions.prompt_line(), "m/s", "the status line carries the closing speed")
	source.hold(InputAdapter.AUTOTRACK)
	for i: int in 140:
		await _ticks(1)
		if main.gates.jump.is_active():
			break
	source.release(InputAdapter.AUTOTRACK)
	assert_true(main.gates.jump.is_active(), "%.0f m/s: the 2 s hold asked for the jump (%s)" % [speed, main.gates.jump_refusal()])
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	var saw_run_in: bool = false
	var eta: float = -1.0
	var crossed_s: float = -1.0
	var first_shot: String = ""
	var shot_at_crossing: String = ""
	var cut_seen_s: float = -1.0
	var take: CinematicShot = null
	var take_s: float = 0.0
	var longest_take_s: float = 0.0
	var longest_take: String = ""
	var takes: int = 0
	var shortest_take_s: float = INF
	var shortest_take: String = ""
	var was_z: float = gate.local_of(main.ship.global_position).z
	var mouth_z: float = gate.fit.mouth_z_m
	var farthest: float = 0.0
	for i: int in 60 * 900:
		var distance: float = main.ship.global_position.distance_to(gate.global_position)
		farthest = maxf(farthest, distance)
		Engine.time_scale = SPEED_UP if distance > FAST_BEYOND_M and main.gates.jump.state == GateJump.State.LINE_UP else 1.0
		await _ticks(1)
		var state: GateJump.State = main.gates.jump.state
		# Every camera take under 3 s, a feature take under 5 s (maintainer, 2026-11-19).
		var now_take: CinematicShot = main.camera_rig.playing_shot() if main.camera_rig.is_playing_shot() else null
		if now_take != take:
			if take != null and now_take != null and take_s < shortest_take_s:
				shortest_take_s = take_s
				shortest_take = String(take.id)
			take = now_take
			take_s = 0.0
			takes += 1
		elif take != null and Engine.time_scale == 1.0:
			take_s += 1.0 / 60.0
			var limit: float = 5.0 if _is_feature(String(take.id)) else 3.0
			if take_s - limit > longest_take_s - 3.0 or longest_take.is_empty():
				longest_take_s = take_s - limit + 3.0  # how far the worst take came to its own limit, on the 3 s scale
				longest_take = "%s (%.2f s of %.0f)" % [take.id, take_s, limit]
		var z: float = gate.local_of(main.ship.global_position).z
		if state == GateJump.State.RUN_IN:
			if not saw_run_in:
				saw_run_in = true
				eta = main.gates.run_in_eta_s
				assert_true(main.camera_rig.is_playing_shot(), "the departure shot starts with the run-in")
				first_shot = String(main.camera_rig.playing_shot().id) if main.camera_rig.is_playing_shot() else ""
			var playing: String = String(main.camera_rig.playing_shot().id) if main.camera_rig.is_playing_shot() else ""
			if cut_seen_s < 0.0 and playing.begins_with("gate_mouth_"):
				cut_seen_s = main.gates.jump.state_s
			if crossed_s < 0.0 and was_z < mouth_z and z >= mouth_z:
				crossed_s = main.gates.jump.state_s
				shot_at_crossing = playing
		was_z = z
		if not main.gates.jump.is_active():
			break
	Engine.time_scale = 1.0
	assert_eq(main.gates.jump.completed, 1, "%.0f m/s: the jump finished (%s)" % [speed, main.gates.jump.ended_why])
	assert_true(saw_run_in, "it ran in")
	assert_eq(gate.departed, 1, "out through the orange vortex")
	assert_eq(gate.arrived, 1, "and back through the blue one")
	assert_gt(crossed_s, 0.0, "it crossed the mouth during the run-in")
	assert_gt(eta, 0.0, "the run-in predicted its arrival")
	assert_almost_eq(crossed_s, eta, 2.0, "%.0f m/s: at the mouth %.1f s into the run-in, predicted %.1f s" % [speed, crossed_s, eta])
	var sequence: PackedStringArray = main.gates.shots.sequence()
	assert_eq(first_shot, "gate_approach_" + sequence[0].get_slice("/", 1), "an approach take opens the run-in (M8-T29)")
	assert_true(shot_at_crossing.begins_with("gate_mouth_"), "a mouth take is on at the mouth (%s)" % shot_at_crossing)
	assert_eq(main.gates.shots.pool.when(GateShotPool.MOUTH, shot_at_crossing.trim_prefix("gate_mouth_")), GateShotPool.ENTRY,
			"one made for the entry")
	assert_almost_eq(cut_seen_s, main.gates.shots.pool.cut_s(eta), 0.1, "the mouth takes start on the predicted arrival's clock")
	assert_lt(cut_seen_s, crossed_s, "before the ship reaches the mouth")
	assert_lt(longest_take_s, 3.0, "no take held to its limit, 3 s or a feature's 5 s (the closest: %s)" % longest_take)
	assert_gt(takes, 6, "the jump is cut into many takes")
	assert_gte(shortest_take_s, GateShotPool.MIN_HOLD_S - 2.0 / 60.0, "no take under 1 s (the shortest: %s, %.2f s)" % [
			shortest_take, shortest_take_s])
	assert_true(main.ship.visible)
	assert_false(main.controls_locked(), "the controls are back")
	gut.p("%.0f m/s: reach %.1f km, farthest %.1f km out, at the mouth %.1f s into the run-in (predicted %.1f s), shots %s, cut at %.1f s" % [speed,
			reach / 1000.0, farthest / 1000.0, crossed_s, eta, " ".join(main.gates.shots.sequence()), cut_seen_s])


# A take marked `feature` in the gate's pools may run up to 5 s (maintainer, 2026-11-19).
func _is_feature(shot_id: String) -> bool:
	var pool: GateShotPool = main.gates.shots.pool
	for slot: StringName in GateShotPool.SLOTS:
		for id: String in pool.ids(slot):
			if shot_id == "gate_%s_%s" % [slot, id]:
				return pool.is_feature(slot, id)
	return false
