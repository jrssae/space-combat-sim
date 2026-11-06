extends Node
## Compares the anti-aliasing modes on one scene in one process (M4-T38, and T40's upscalers after it): a bench layout is flown
## for `warmup` seconds, then (with `pause=on`) frozen, and the modes take turns in `rounds` rounds, each measured over
## `frames` frames after `settle` frames. Taking turns in one process cancels the GPU's clock changes, which between separate
## runs swing the GPU time more than any mode does. Prints one line per mode (GPU ms mean and median over every round, FPS) and
## saves a screenshot per mode from the first round, for the look comparisons (H).
##
## Arguments after `--`: layout=<name> n=<ships> seed=<k> warmup=<s> pause=<on|off> modes=<a,b,...> rounds=<r> frames=<f>
## settle=<f> scale3d=<1080p|factor|setting> camera=<chase|cockpit> shots=<dir> exec="<console statements once the scene is set>"
## glow=<on|off> (a control: the environment's glow switched for the whole run)
## upscalers=<upscaler:preset,...> (M4-T40: the turns are upscalers instead of anti-aliasing modes, e.g. native,fsr2:quality,
## fsr1:0.75; a number is a custom scale; give scale3d=setting so the presets set the 3D's size)

var options: Dictionary = {"layout": "battle", "n": "300", "seed": "1", "warmup": "10", "pause": "on",
		"modes": ",".join(PackedStringArray(AntiAliasingMode.MODES)), "rounds": "4", "frames": "90", "settle": "30",
		"scale3d": "1080p", "camera": "chase", "shots": "", "exec": "", "glow": "on", "upscalers": ""}
var main: Main
var _modes: PackedStringArray
var _gpu: Dictionary = {}
var _frame: Dictionary = {}
var _round: int = 0
var _mode_index: int = 0
var _phase: StringName = &"warmup"
var _count: int = 0
var _started_usec: int = 0
var _last_usec: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = arg.split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	_modes = String(options["modes"]).split(",", false)
	if not String(options["upscalers"]).is_empty():
		_modes = String(options["upscalers"]).split(",", false)
	for mode: String in _modes:
		_gpu[mode] = PackedFloat64Array()
		_frame[mode] = PackedFloat64Array()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.waves_auto_start = false
	main.input_source = FakeInputSource.new()
	var tree: SceneTree = get_tree()
	tree.root.add_child.call_deferred(main)
	tree.set_deferred(&"current_scene", main)
	tree.process_frame.connect(_on_frame)
	main.ready.connect(_set_up.call_deferred, CONNECT_ONE_SHOT)


func _set_up() -> void:
	_run("god on")
	_run("wave stop")
	_run("despawn all")
	_run("camera %s" % options["camera"])
	_run("bench %s %s %d warmup=0 seed=%s label=aa_compare/bench" % [options["layout"], options["n"],
			int(float(options["warmup"])) + 600, options["seed"]])
	if not String(options["exec"]).is_empty():
		_run(String(options["exec"]))
	var environment: Environment = get_viewport().find_world_3d().environment
	if environment != null and String(options["glow"]) == "off":
		environment.glow_enabled = false
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_started_usec = Time.get_ticks_usec()
	_last_usec = _started_usec


func _on_frame() -> void:
	if _started_usec == 0:
		return
	_hold_3d_scale()
	var now: int = Time.get_ticks_usec()
	var frame_ms: float = float(now - _last_usec) * 1e-3
	_last_usec = now
	match _phase:
		&"warmup":
			if float(now - _started_usec) * 1e-6 >= float(options["warmup"]):
				if String(options["pause"]) == "on":
					_run("pause on")
				_begin_mode()
		&"settle":
			_count += 1
			if _count >= int(options["settle"]):
				_phase = &"measure"
				_count = 0
		&"measure":
			var mode: String = _modes[_mode_index]
			# A packed array read from a Dictionary is a copy: append, then store it back.
			var gpu: PackedFloat64Array = _gpu[mode]
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
			_gpu[mode] = gpu
			var frames: PackedFloat64Array = _frame[mode]
			frames.append(frame_ms)
			_frame[mode] = frames
			_count += 1
			if _count >= int(options["frames"]):
				if _round == 0 and not String(options["shots"]).is_empty():
					_shot(mode)
				_next_mode()


func _begin_mode() -> void:
	if String(options["upscalers"]).is_empty():
		Settings.set_value(&"anti_aliasing", StringName(_modes[_mode_index]))
	else:
		_run("upscale %s" % _modes[_mode_index].replace(":", " "))
	_phase = &"settle"
	_count = 0


func _next_mode() -> void:
	_mode_index += 1
	if _mode_index >= _modes.size():
		_mode_index = 0
		_round += 1
		if _round >= int(options["rounds"]):
			_finish()
			return
	_begin_mode()


func _shot(mode: String) -> void:
	var dir: String = String(options["shots"])
	DirAccess.make_dir_recursive_absolute(dir)
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [dir, mode.replace(":", "_")])


func _finish() -> void:
	var scale: float = get_tree().root.scaling_3d_scale
	var lines: int = roundi(get_tree().root.size.y * scale)
	print("[aa_compare] %s %s, %d rounds, 3D %d lines (scale %.3f) in a %dx%d window, pause %s, glow %s, %s frames a turn" % [
			options["layout"], options["n"], int(options["rounds"]), lines, scale, get_tree().root.size.x, get_tree().root.size.y,
			options["pause"], options["glow"], options["frames"]])
	for mode: String in _modes:
		var gpu: PackedFloat64Array = _gpu[mode]
		var frames: PackedFloat64Array = _frame[mode]
		print("[aa_compare] %s: gpu ms mean %.3f median %.3f, frame ms mean %.2f (%.1f FPS)" % [mode, _mean(gpu), _median(gpu),
				_mean(frames), 1000.0 / maxf(_mean(frames), 1e-6)])
	get_tree().quit()


func _hold_3d_scale() -> void:
	var wanted: String = String(options["scale3d"])
	if wanted == "setting":
		return
	if Settings.get_value(&"upscaler") != &"bilinear":
		Settings.set_value(&"upscaler", &"bilinear")  # a held scale is a bilinear stretch, as before M4-T40
	var root: Window = get_tree().root
	var scale: float = minf(1.0, 1080.0 / float(maxi(root.size.y, 1))) if wanted == "1080p" else float(wanted)
	if scale > 0.0 and not is_equal_approx(root.scaling_3d_scale, scale):
		root.scaling_3d_scale = scale


func _run(line: String) -> void:
	for result: ConsoleResult in DebugConsole.registry.execute(line):
		if not result.ok:
			print("[aa_compare] console error on '%s': %s" % [line, result.error])


static func _mean(values: PackedFloat64Array) -> float:
	var sum: float = 0.0
	for v: float in values:
		sum += v
	return sum / maxf(values.size(), 1.0)


static func _median(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]
