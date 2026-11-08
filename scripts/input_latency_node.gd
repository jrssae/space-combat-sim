extends Node
## Measures the input latency on the real renderer (M4-T24, Q53): the wall-clock time from a pad press to the first frame
## in which the player's ship answers it. The press is a full pitch-up on a fake input source (what `Main` samples in its
## physics step, as the pad is), made at a random point of a frame; the answer is the ship's angular velocity changing. The
## press is repeated `presses` times, a second apart, after a warm-up with the scene the console `exec` builds (a bench
## layout around the player, as the fullscreen check does). Prints one `[latency]` line with the mean, median, worst and
## best latency in milliseconds and in frames, the frame time over the window and the step mode, then quits.
##
## Arguments after `--`: exec="<console statements>" warmup=<s> presses=<n> mode=<delayed|threaded> steps=<n>
## (Engine.max_physics_steps_per_frame, 0 keeps the setting's) scale3d=<1080p|factor>.

const RESPONSE_RAD_S: float = 0.004
const HOLD_S: float = 0.3
const GAP_S: float = 1.0

var main: Main
var options: Dictionary = {"exec": "", "warmup": "6", "presses": "20", "mode": "", "steps": "0", "scale3d": "1080p"}
var source: FakeInputSource
var _rng := RandomNumberGenerator.new()
var _started_usec: int = 0
var _state: String = "warmup"
var _press_usec: int = 0
var _press_frames: int = 0
var _w0: Vector3 = Vector3.ZERO
var _next_at_usec: int = 0
var _latencies_ms := PackedFloat64Array()
var _latency_frames := PackedInt64Array()
var _frame_ms := PackedFloat64Array()
var _last_frame_usec: int = 0
var _done: int = 0
var _ticks: int = 0
var _window_start_usec: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = arg.split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	_rng.seed = 23
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.waves_auto_start = false
	source = FakeInputSource.new()
	main.input_source = source
	var tree: SceneTree = get_tree()
	tree.root.add_child.call_deferred(main)
	tree.set_deferred(&"current_scene", main)
	tree.process_frame.connect(_on_frame)
	tree.physics_frame.connect(func() -> void: if _state != "warmup" and _state != "done": _ticks += 1)
	main.ready.connect(_set_up_scene.call_deferred, CONNECT_ONE_SHOT)


func _set_up_scene() -> void:
	_run("god on")
	_run("wave stop")
	_run("despawn all")
	_run("camera chase")
	if not String(options["mode"]).is_empty():
		_run("set settings.sim_step %s" % options["mode"])
	if int(options["steps"]) > 0:
		Engine.max_physics_steps_per_frame = int(options["steps"])
	if not String(options["exec"]).is_empty():
		_run(String(options["exec"]))
	var scale: String = String(options["scale3d"])
	if scale == "1080p":
		var height: float = float(get_viewport().get_visible_rect().size.y)
		get_viewport().scaling_3d_scale = clampf(1080.0 / maxf(height, 1.0), 0.1, 1.0)
	elif scale.is_valid_float():
		get_viewport().scaling_3d_scale = clampf(scale.to_float(), 0.1, 1.0)
	_started_usec = Time.get_ticks_usec()
	_last_frame_usec = _started_usec
	_next_at_usec = _started_usec + int(float(options["warmup"]) * 1_000_000.0)
	print("[latency] mode %s, max steps a frame %d, %s presses after %s s, exec: %s" % [String(Settings.get_value(&"sim_step")),
			Engine.max_physics_steps_per_frame, options["presses"], options["warmup"], options["exec"]])


func _run(line: String) -> void:
	for result: ConsoleResult in DebugConsole.registry.execute(line):
		if not result.ok:
			print("[latency] console error on '%s': %s" % [line, "; ".join(result.lines)])


# One frame: the frame time once measuring, the press when its moment comes, the answer when the ship turns.
func _on_frame() -> void:
	if _started_usec == 0 or main.combatant == null or not is_instance_valid(main.combatant.ship):
		return
	var now: int = Time.get_ticks_usec()
	var ship: Ship = main.combatant.ship
	if _state != "warmup":
		_frame_ms.append(float(now - _last_frame_usec) / 1000.0)
	elif now >= _next_at_usec:
		_window_start_usec = now
	_last_frame_usec = now
	match _state:
		"warmup", "gap":
			if now >= _next_at_usec:
				# The press lands somewhere inside this frame's work, as a player's does.
				OS.delay_usec(_rng.randi_range(0, 8000))
				_w0 = ship.angular_velocity
				source.hold(InputAdapter.PITCH_UP, 1.0)
				_press_usec = Time.get_ticks_usec()
				_press_frames = 0
				_state = "pressed"
		"pressed":
			_press_frames += 1
			if (ship.angular_velocity - _w0).length() > RESPONSE_RAD_S:
				_latencies_ms.append(float(now - _press_usec) / 1000.0)
				_latency_frames.append(_press_frames)
				_state = "held"
				_next_at_usec = now + int(HOLD_S * 1_000_000.0)
			elif now - _press_usec > 2_000_000:
				print("[latency] press %d: no answer within 2 s" % (_done + 1))
				_state = "held"
				_next_at_usec = now
		"held":
			if now >= _next_at_usec:
				source.release(InputAdapter.PITCH_UP)
				_done += 1
				if _done >= int(options["presses"]):
					_finish()
					return
				_state = "gap"
				_next_at_usec = now + int(GAP_S * 1_000_000.0)


func _finish() -> void:
	_state = "done"
	var sorted: PackedFloat64Array = _latencies_ms.duplicate()
	sorted.sort()
	var frames_sorted: PackedInt64Array = _latency_frames.duplicate()
	frames_sorted.sort()
	var frame_sorted: PackedFloat64Array = _frame_ms.duplicate()
	frame_sorted.sort()
	var window_s: float = float(Time.get_ticks_usec() - _window_start_usec) / 1_000_000.0
	var speed: String = "%.2f" % (float(_ticks) / maxf(window_s * float(Engine.physics_ticks_per_second), 1.0))
	print("[latency] %d presses: latency ms mean %.1f median %.1f worst %.1f best %.1f; frames mean %.2f worst %d; frame ms mean %.2f p99 %.2f (%.1f FPS); sim speed %s; mode %s" % [
			sorted.size(), _mean(sorted), _median(sorted), sorted[sorted.size() - 1] if not sorted.is_empty() else 0.0,
			sorted[0] if not sorted.is_empty() else 0.0, _mean_i(frames_sorted), frames_sorted[frames_sorted.size() - 1] if not frames_sorted.is_empty() else 0,
			_mean(frame_sorted), frame_sorted[int(float(frame_sorted.size() - 1) * 0.99)] if not frame_sorted.is_empty() else 0.0,
			1000.0 / maxf(_mean(frame_sorted), 0.001), speed, String(Settings.get_value(&"sim_step"))])
	get_tree().quit()


static func _mean(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sum: float = 0.0
	for v: float in values:
		sum += v
	return sum / float(values.size())


static func _mean_i(values: PackedInt64Array) -> float:
	if values.is_empty():
		return 0.0
	var sum: float = 0.0
	for v: int in values:
		sum += float(v)
	return sum / float(values.size())


static func _median(sorted: PackedFloat64Array) -> float:
	return sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0
