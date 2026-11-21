extends GutTest
## Holding X aborts an autopilot (M8-T32, maintainer 2026-11-19), on the real main scene: the gate jump while it lines up and runs
## in, docking while it approaches and flies the lane. A full hold (data: 1 s) ends it with the ship free at its velocity, the
## shots stopped and the controls back; half a hold does nothing; a tap toggles nothing; past the point of no return (the gate's
## funnel, the docking bay's inner doors) nothing aborts and the prompt is gone. Docking flies with the physics rate and the time
## scale raised together.

const DT: float = 1.0 / 60.0
const SPEED_UP: float = 8.0

var main: Main
var source: FakeInputSource
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	get_tree().paused = false
	ContactScan.invalidate()


func _start(scenario: String) -> void:
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.scenario_path = scenario
	main.raider_pool_size = 0
	main.ally_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(3)


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _fast() -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))


func _normal() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup


# Holds X for `seconds` (as the pad, or as Shift when `keyboard`), then lets go for a tick.
func _hold_x(seconds: float, keyboard: bool = false) -> void:
	source.hold(InputAdapter.AUTOTRACK, 1.0, keyboard)
	await _ticks(roundi(seconds / DT))
	source.release(InputAdapter.AUTOTRACK)
	await _ticks(2)


func _until(done: Callable, limit_ticks: int) -> bool:
	for i: int in limit_ticks:
		if done.call():
			return true
		await get_tree().physics_frame
	return bool(done.call())


func test_the_gate_jump_aborts_on_a_full_hold_only_and_not_from_the_funnel() -> void:
	await _start(ScenarioLoader.FREE_FLIGHT_PATH)
	var gate: Jumpgate = main.gates.gate()
	assert_true(main.gates._cmd_gate({&"action": &"approach", &"option": "1.9"}).ok)
	await _ticks(3)
	assert_eq(main.gates.start_jump(gate), "")
	await _ticks(30)
	assert_eq(main.autopilot_abort.offered(), AutopilotAbort.GATE, "lining up: the abort is offered")
	assert_eq(main.autopilot_abort.prompt_line(), "HOLD X / SHIFT / MOUSE 4: ABORT", "the prompt names the live bindings")
	source.hold(InputAdapter.AUTOTRACK)
	await _ticks(2)
	source.release(InputAdapter.AUTOTRACK)
	await _ticks(2)
	assert_false(main.adapter.autotrack_on, "a tap of X toggles nothing while the autopilot flies")
	await _hold_x(0.5)
	assert_true(main.gates.jump.is_active(), "half a hold does nothing")
	source.hold(InputAdapter.AUTOTRACK)
	await _ticks(45)
	assert_gt(main.autopilot_abort.progress(), 0.5, "the bar fills")
	await _ticks(20)
	var velocity: Vector3 = main.ship.linear_velocity
	source.release(InputAdapter.AUTOTRACK)
	await _ticks(2)
	assert_false(main.gates.jump.is_active(), "a 1 s hold aborted the jump")
	assert_eq(main.gates.jump.ended_why, "aborted by the pilot")
	assert_false(main.controls_locked(), "the controls are back")
	assert_false(main.camera_rig.is_playing_shot(), "the cinematic cut")
	assert_lt(main.ship.linear_velocity.distance_to(velocity), 5.0, "the ship flies on as it was")
	assert_eq(main.autopilot_abort.aborts, 1)
	assert_eq(main.autopilot_abort.prompt_line(), "", "the prompt is gone")
	assert_false(main.adapter.autotrack_on, "and auto-track stayed off")
	# Again, this time held until the ship is in the vortex's funnel: no abort from there on.
	assert_true(main.gates._cmd_gate({&"action": &"approach", &"option": "1.9"}).ok)
	await _ticks(3)
	assert_eq(main.gates.start_jump(gate), "")
	var transits: VortexTransits = VortexTransits.of(main.world)
	var in_funnel: bool = await _until(func() -> bool: return transits != null and transits.is_passing(main.ship), 60 * 40)
	assert_true(in_funnel, "the ship reached the funnel (%s)" % main.gates.jump.state_name())
	assert_eq(main.autopilot_abort.offered(), &"", "in the funnel: no abort")
	assert_false(DebugConsole.registry.execute("autopilot abort")[0].ok, "the console's abort obeys the same rule")
	source.hold(InputAdapter.AUTOTRACK)
	var finished: bool = await _until(func() -> bool: return not main.gates.jump.is_active(), 60 * 30)
	source.release(InputAdapter.AUTOTRACK)
	assert_true(finished)
	assert_eq(main.gates.jump.completed, 1, "the jump went on to the end (%s)" % main.gates.jump.ended_why)
	assert_eq(main.autopilot_abort.aborts, 1)


func test_docking_aborts_from_the_approach_by_keyboard_and_not_past_the_inner_doors() -> void:
	await _start("res://data/scenarios/station_dock.json")
	if main.far_props.station == null:
		pending("the babylon5_station asset is not generated")
		return
	assert_eq(main.docking.start_player(), "")
	await _ticks(20)
	assert_eq(main.autopilot_abort.offered(), AutopilotAbort.DOCK, "approaching: the abort is offered")
	var velocity: Vector3 = main.ship.linear_velocity
	await _hold_x(1.1, true)  # Shift: the keyboard's X
	assert_null(main.docking.player_visit(), "a 1 s hold of Shift aborted the docking")
	assert_eq(main.docking.last_visit.state, DockVisit.State.CANCELLED, "the visit ended where it was")
	assert_false(main.controls_locked(), "the controls are back")
	assert_false(main.camera_rig.is_playing_shot(), "the docking's shots stopped")
	assert_false(main.docking.shots.is_running())
	assert_lt(main.ship.linear_velocity.distance_to(velocity), 30.0, "the ship flies on, released at its velocity")
	# Again, through the inner doors: no abort from there on.
	assert_eq(main.docking.start_player(), "")
	_fast()
	var inside: bool = await _until(func() -> bool:
		return main.docking.player_visit() != null and main.docking.player_visit().state >= DockVisit.State.INSIDE, 60 * 8 * 200)
	_normal()
	assert_true(inside, "the ship went through the inner doors (%s)" % main.docking.describe())
	assert_eq(main.autopilot_abort.offered(), &"", "past the inner doors: no abort")
	assert_eq(main.autopilot_abort.prompt_line(), "", "and no prompt")
	assert_false(DebugConsole.registry.execute("autopilot abort")[0].ok)
	main.docking.cancel_player("test over")
