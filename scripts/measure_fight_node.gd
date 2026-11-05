extends Node
## Measures AC19's fight and the 100-ship scene on the real renderer (run by scripts/measure_m3.sh): frame time, GPU time, draw
## calls and VRAM over a sustained window, with one summary line for the record and a picture of the scene it measured.
##
## Scenes: `held` keeps four Starfuries and nine raiders in view, all firing, so the worst case can be held for as long as it is
## measured. `fight` is a real AI fight with the player's nose kept on it. `hundred` and `hundred_view` are 100 ships, around the player
## and all in view. `quiet` is the player alone, to tell what the fight costs from what the desktop does. Explosions come on a timer in
## the 13-ship scenes, so one is always live.
##
## Arguments after `--`: scene=<name> camera=<chase|cockpit> warmup=<s> window=<s> near=<m> far=<m> steps=<n> label=<text>
## exec="<console statements>" shot=<png path> scale3d=<1080p|factor> (M4-T07: the 3D scale, held every frame;
## 1080p renders the 3D at 1 080 lines whatever the window's size, for the fullscreen check on a larger screen)
## pause_at=<s> (M4-T27: the game paused at that many seconds after the start, so a window can measure the drawing alone)

const WARMUP_S: float = 6.0
const WINDOW_S: float = 20.0
const FRAME_BUDGET_MS: float = 1000.0 / 60.0
## With vsync on, a frame this long has missed a vblank (the display repeats the last picture).
const MISSED_FRAME_MS: float = 25.0
const RAIDERS: int = 9
const WINGMEN: int = 3
const RAIDER_KILL_EVERY_S: float = 3.0
const ALLY_KILL_EVERY_S: float = 7.0
const RAIDER_YAW_DEG: Array[float] = [-26.0, -14.0, 14.0, 26.0, -20.0, 20.0, -8.0, 8.0, 0.0]
const RAIDER_PITCH_DEG: Array[float] = [8.0, -6.0, 10.0, -8.0, -12.0, 12.0, 14.0, -14.0, 16.0]
const ALLY_YAW_DEG: Array[float] = [-32.0, 32.0, 0.0]
const ALLY_PITCH_DEG: Array[float] = [-6.0, -4.0, -18.0]
const ALLY_RANGE_M: Array[float] = [90.0, 140.0, 190.0]
const NOSE_TURN_DEG_S: float = 40.0
const VRAM_CARDS: Array[String] = ["card0", "card1", "card2"]
const MAX_SPIKES_PRINTED: int = 40
## The slowest share of frames the "1 % low" averages, and how many frames open the window for the warm-up check (M4-P2, Q48).
const LOW_SHARE: float = 0.01
const START_FRAMES: int = 60

var main: Main
var options: Dictionary = {"scene": "held", "camera": "chase", "warmup": str(WARMUP_S), "window": str(WINDOW_S), "near": "120", "far": "500",
		"steps": "0", "label": "", "exec": "", "shot": "", "scale3d": "", "pause_at": ""}
var measuring: bool = false
var frame_ms := PackedFloat64Array()
var gpu_ms := PackedFloat64Array()
var render_cpu_ms := PackedFloat64Array()
var physics_ms := PackedFloat64Array()
var process_ms := PackedFloat64Array()
var ships_in_view := PackedFloat64Array()
var nearest_m := PackedFloat64Array()
var bolts := PackedFloat64Array()
var particles_busy := PackedFloat64Array()
var debris_chunks := PackedFloat64Array()
var lights_on := PackedFloat64Array()
var draw_calls := PackedFloat64Array()
var primitives := PackedFloat64Array()
var objects := PackedFloat64Array()
var _paused: bool = false
var ai_us := PackedFloat64Array()
var hit_us := PackedFloat64Array()
var ram_us := PackedFloat64Array()
var fps_samples := PackedFloat64Array()
var spikes := PackedStringArray()
var explosions: int = 0
var vram_before_mb: float = 0.0
var gtt_before_mb: float = 0.0
var vram_peak_mb: float = 0.0
var own_vram_before_mb: float = 0.0
var own_vram_peak_mb: float = 0.0
var gtt_peak_mb: float = 0.0
var _vram_dir: String = ""
var _started_usec: int = 0
var _last_frame_usec: int = 0
var _last_second_usec: int = 0
var _next_raider_kill_s: float = 2.0
var _next_ally_kill_s: float = 4.0
var _next_restore_s: float = 1.0
var _kill_round: int = 0
var _last_kill_usec: int = 0
var _ticks_in_frame: int = 0
var _window_ticks: int = 0
var _window_start_usec: int = 0
var _places: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = arg.split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	_rng.seed = 19
	_vram_dir = _find_vram_dir()
	vram_before_mb = _read_mb("mem_info_vram_used")
	own_vram_before_mb = _own_vram_mb()
	gtt_before_mb = _read_mb("mem_info_gtt_used")
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.waves_auto_start = false
	var source := FakeInputSource.new()
	main.input_source = source
	if _is_hundred():
		main.raider_pool_size = 70
		main.ally_pool_size = 30
	elif options["scene"] != "quiet":
		source.hold(&"fire")
	if int(options["steps"]) > 0:
		Engine.max_physics_steps_per_frame = int(options["steps"])
	var tree: SceneTree = get_tree()
	tree.root.add_child.call_deferred(main)
	tree.set_deferred(&"current_scene", main)
	tree.process_frame.connect(_on_frame)
	tree.physics_frame.connect(_on_tick)
	main.ready.connect(_set_up_scene.call_deferred, CONNECT_ONE_SHOT)


func _is_hundred() -> bool:
	return String(options["scene"]).begins_with("hundred")


func _set_up_scene() -> void:
	_run("god on")
	_run("wave stop")
	match String(options["scene"]):
		"held":
			_place_held_ships()
		"fight":
			_place_fight()
		"hundred":
			_place_hundred(false)
		"hundred_view":
			_place_hundred(true)
		"quiet":
			_run("despawn all")
	_run("camera %s" % options["camera"])
	if not String(options["exec"]).is_empty():
		_run(String(options["exec"]))
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_started_usec = Time.get_ticks_usec()
	_last_frame_usec = _started_usec
	_last_second_usec = _started_usec


# Prints what a console statement said, so the log shows the scene was what it claims.
func _run(line: String) -> void:
	for result: ConsoleResult in DebugConsole.registry.execute(line):
		if not result.ok:
			print("[measure] console error on '%s': %s" % [line, "; ".join(result.lines)])


func _read(path: String) -> Variant:
	return DebugConsole.registry.read(path)["value"]


# A place `yaw_deg` and `pitch_deg` off the player's nose, `range_m` out, in the World frame.
func _ahead(yaw_deg: float, pitch_deg: float, range_m: float) -> Vector3:
	var yaw: float = deg_to_rad(yaw_deg)
	var pitch: float = deg_to_rad(pitch_deg)
	var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	return main.ship.global_position + main.ship.global_basis * direction * range_m


func _raider_place(i: int) -> Vector3:
	var near_m: float = float(options["near"])
	var far_m: float = float(options["far"])
	return _ahead(RAIDER_YAW_DEG[i], RAIDER_PITCH_DEG[i], lerpf(near_m, far_m, float(i) / float(RAIDERS - 1)))


func _spawn_held(ship_name: String, type: StringName, local: Vector3, looking_at: Vector3) -> void:
	var up: Vector3 = main.ship.global_basis.y
	var basis := Basis.looking_at((looking_at - local).normalized(), up)
	var combatant: Combatant = main.ships.acquire(ship_name, main.world.to_universe(local), basis, Vector3.ZERO, MeasureHeldBrain.new(), type)
	if combatant == null:
		print("[measure] pool empty for %s" % ship_name)
		return
	_places[ship_name] = {"type": type, "local": local, "looking_at": looking_at}


# All thirteen in view at combat ranges, raiders firing at the player and the wingmen firing into the raiders.
func _place_held_ships() -> void:
	_run("despawn all")
	var centre: Vector3 = _ahead(0.0, 0.0, float(options["far"]))
	for i: int in RAIDERS:
		_spawn_held("RAIDER %d" % (i + 1), ShipPool.DEFAULT_TYPE, _raider_place(i), main.ship.global_position)
	for i: int in WINGMEN:
		_spawn_held("ALPHA %d" % (i + 2), ShipPool.ALLY_TYPE, _ahead(ALLY_YAW_DEG[i], ALLY_PITCH_DEG[i], ALLY_RANGE_M[i]), centre)


# The sandbox's own wingmen against nine AiPilot raiders starting ahead of the player.
func _place_fight() -> void:
	_run("wing order engage")
	for i: int in RAIDERS:
		_spawn_ai_raider(i)


func _spawn_ai_raider(i: int) -> void:
	var at: UniversePos = main.world.to_universe(_raider_place(i))
	var ship_name: String = main.ships.next_name()
	var spec: Dictionary = {"type": "ai", "profile": "raider"}
	var made: Dictionary = BrainFactory.from_behaviour(spec, at, hash([ship_name, _kill_round]))
	var basis := Basis.looking_at(main.ship.global_basis.z, main.ship.global_basis.y)
	if main.ships.acquire(ship_name, at, basis, Vector3.ZERO, made["brain"] as PilotBrain) == null:
		print("[measure] raider pool empty")


# T20's spiral for `hundred` (200 m to 6 km all round), or all of them in a cone ahead from 150 m to 1.5 km.
func _place_hundred(in_view: bool) -> void:
	_run("despawn all")
	var golden: float = PI * (3.0 - sqrt(5.0))
	for i: int in 100:
		var t: float = float(i) / 99.0
		var local: Vector3
		if in_view:
			var angle: float = golden * i
			local = _ahead(sqrt(t) * 30.0 * cos(angle), sqrt(t) * 18.0 * sin(angle), lerpf(150.0, 1500.0, t))
		else:
			var y: float = 1.0 - 2.0 * t
			var ring: float = sqrt(maxf(0.0, 1.0 - y * y))
			var direction := Vector3(cos(golden * i) * ring, y, sin(golden * i) * ring)
			local = main.ship.global_position + direction * lerpf(200.0, 6000.0, t)
		var type: StringName = ShipPool.ALLY_TYPE if i % 10 < 3 else ShipPool.DEFAULT_TYPE
		var ship_name: String = "ALPHA %d" % (i + 2) if type == ShipPool.ALLY_TYPE else "RAIDER %d" % (i + 1)
		var basis := Basis.looking_at((main.ship.global_position - local).normalized(), main.ship.global_basis.y)
		main.ships.acquire(ship_name, main.world.to_universe(local), basis, Vector3.ZERO, IdleBrain.new(true), type)


# Keeps the nose on the raiders, as a player chasing the fight would, so the fight stays in the picture.
func _on_tick() -> void:
	_ticks_in_frame += 1
	if measuring:
		_window_ticks += 1
	if String(options["scene"]) != "fight" or main == null or not main.player_alive:
		return
	var sum := Vector3.ZERO
	var count: int = 0
	for combatant: Combatant in main.ships.alive(ShipPool.DEFAULT_TYPE):
		sum += combatant.ship.global_position
		count += 1
	if count == 0:
		return
	var wanted: Vector3 = (sum / float(count) - main.ship.global_position).normalized()
	var nose: Vector3 = -main.ship.global_basis.z
	var step: float = deg_to_rad(NOSE_TURN_DEG_S) / float(Engine.physics_ticks_per_second)
	if nose.dot(wanted) < 0.9999:
		var axis: Vector3 = nose.cross(wanted).normalized()
		if axis.length_squared() > 0.5:
			main.ship.global_basis = main.ship.global_basis.rotated(axis, minf(step, nose.angle_to(wanted))).orthonormalized()


func _on_frame() -> void:
	_hold_3d_scale()
	if _started_usec == 0:
		return
	var now: int = Time.get_ticks_usec()
	var elapsed_s: float = float(now - _started_usec) * 1e-6
	if not _is_hundred() and options["scene"] != "quiet":
		_keep_the_fight_going(elapsed_s)
	if not _paused and not String(options["pause_at"]).is_empty() and elapsed_s >= float(options["pause_at"]):
		_paused = true
		_run("pause on")
	var warmup: float = float(options["warmup"])
	if elapsed_s >= warmup:
		if not measuring:
			measuring = true
			_window_start_usec = now
			_last_second_usec = now
		_sample(now)
		if elapsed_s >= warmup + float(options["window"]):
			_finish()
			return
	_last_frame_usec = now


# The 3D scale the run asked for, set again whenever something (Main on a resize) changed it.
func _hold_3d_scale() -> void:
	var wanted: String = String(options["scale3d"])
	if wanted.is_empty():
		return
	var root: Window = get_tree().root
	var scale: float = minf(1.0, 1080.0 / float(maxi(root.size.y, 1))) if wanted == "1080p" else float(wanted)
	if scale > 0.0 and not is_equal_approx(root.scaling_3d_scale, scale):
		root.scaling_3d_scale = scale


# An explosion on a timer and hulls topped up, so the sustained window always has wrecks in it and the same ships in it.
func _keep_the_fight_going(elapsed_s: float) -> void:
	var held: bool = String(options["scene"]) == "held"
	if held and elapsed_s >= _next_restore_s:
		_next_restore_s += 1.0
		_restore_held_ships()
	if elapsed_s >= _next_raider_kill_s:
		_next_raider_kill_s += RAIDER_KILL_EVERY_S
		_kill_round += 1
		var raiders: Array[Combatant] = main.ships.alive(ShipPool.DEFAULT_TYPE)
		if not raiders.is_empty():
			var victim: Combatant = raiders[_kill_round % raiders.size()]
			var victim_name: String = victim.display_name
			if victim.damageable.kill():
				explosions += 1
				_last_kill_usec = Time.get_ticks_usec()
			if held and _places.has(victim_name):
				var place: Dictionary = _places[victim_name]
				_spawn_held(victim_name, place["type"], place["local"], place["looking_at"])
			elif not held:
				_spawn_ai_raider(_kill_round % RAIDERS)
		_run("heal all")
	if held and elapsed_s >= _next_ally_kill_s:
		_next_ally_kill_s += ALLY_KILL_EVERY_S
		var allies: Array[Combatant] = main.ships.alive(ShipPool.ALLY_TYPE)
		if not allies.is_empty():
			var victim: Combatant = allies[_kill_round % allies.size()]
			var victim_name: String = victim.display_name
			if victim.damageable.kill():
				explosions += 1
				_last_kill_usec = Time.get_ticks_usec()
			if _places.has(victim_name):
				var place: Dictionary = _places[victim_name]
				_spawn_held(victim_name, place["type"], place["local"], place["looking_at"])


# Bolts bring down held ships too; the scene is only what it claims if all thirteen stay in it.
func _restore_held_ships() -> void:
	var alive: Dictionary = {}
	for combatant: Combatant in main.ships.alive():
		alive[combatant.display_name] = true
	for ship_name: String in _places:
		if not alive.has(ship_name):
			var place: Dictionary = _places[ship_name]
			_spawn_held(ship_name, place["type"], place["local"], place["looking_at"])


func _sample(now: int) -> void:
	frame_ms.append(float(now - _last_frame_usec) * 1e-3)
	gpu_ms.append(float(_read("render.gpu_ms")))
	render_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())
			+ RenderingServer.get_frame_setup_time_cpu())
	physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1e3)
	process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1e3)
	bolts.append(float(_read("combat.projectiles")))
	particles_busy.append(float(_read("fx.busy")))
	debris_chunks.append(float(_read("debris.active_chunks")))
	lights_on.append(float(_read("lights.active")))
	draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	objects.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	ai_us.append(float(_read("ai.think_us")))
	hit_us.append(float(_read("combat.resolve_us")))
	ram_us.append(float(_read("ram.resolve_us")))
	var camera: Camera3D = main.camera_rig.active_camera()
	var in_view: int = 0
	var nearest: float = 1e12
	for combatant: Combatant in main.ships.alive():
		var at: Vector3 = combatant.ship.global_position
		if camera.is_position_in_frustum(at):
			in_view += 1
		nearest = minf(nearest, at.distance_to(main.ship.global_position))
	if main.player_alive and camera.is_position_in_frustum(main.ship.global_position):
		in_view += 1
	ships_in_view.append(float(in_view))
	nearest_m.append(nearest)
	var this_frame_ms: float = frame_ms[frame_ms.size() - 1]
	if this_frame_ms > MISSED_FRAME_MS and spikes.size() < MAX_SPIKES_PRINTED:
		spikes.append("%.2f s: %.1f ms, %d ticks, gpu %.1f ms, ai %d us, hits %d us, rams %d us, %.2f s after a kill" % [float(now - _started_usec) * 1e-6, this_frame_ms,
				_ticks_in_frame, gpu_ms[gpu_ms.size() - 1], int(ai_us[ai_us.size() - 1]), int(hit_us[hit_us.size() - 1]), int(ram_us[ram_us.size() - 1]),
				float(now - _last_kill_usec) * 1e-6])
	_ticks_in_frame = 0
	if now - _last_second_usec >= 1000000:
		_last_second_usec = now
		fps_samples.append(float(_read("render.fps")))
		vram_peak_mb = maxf(vram_peak_mb, _read_mb("mem_info_vram_used"))
		gtt_peak_mb = maxf(gtt_peak_mb, _read_mb("mem_info_gtt_used"))


func _finish() -> void:
	get_tree().process_frame.disconnect(_on_frame)
	get_tree().physics_frame.disconnect(_on_tick)
	var label: String = String(options["label"])
	if label.is_empty():
		label = "%s_%s" % [options["scene"], options["camera"]]
	var over: int = 0
	var missed: int = 0
	for value: float in frame_ms:
		if value > FRAME_BUDGET_MS:
			over += 1
		if value > MISSED_FRAME_MS:
			missed += 1
	print("[measure] %s: frames %d, fps %.0f (render.fps min %.0f), frame ms mean %.2f p50 %.2f p99 %.2f max %.2f, over 16.67 ms %d (%.2f%%), over 25 ms %d, gpu ms mean %.2f max %.2f, render cpu ms %.2f, worst tick each second ms %.2f, worst process each second ms %.2f" % [
			label, frame_ms.size(), 1000.0 / _mean(frame_ms), _min(fps_samples), _mean(frame_ms), _percentile(frame_ms, 0.5), _percentile(frame_ms, 0.99), _max(frame_ms), over,
			100.0 * float(over) / maxf(1.0, float(frame_ms.size())), missed, _mean(gpu_ms), _max(gpu_ms), _mean(render_cpu_ms), _mean(physics_ms), _mean(process_ms)])
	print("[measure] %s: ships in view min %d mean %.1f max %d of %d, nearest other ship mean %.0f m, far dots %d" % [
			label, _min(ships_in_view), _mean(ships_in_view), _max(ships_in_view), main.ships.alive().size() + 1, _mean(nearest_m),
			int(_read("render.far_dots"))])
	print("[measure] %s: bolts mean %.0f max %d, particle emitters busy mean %.1f max %d, debris chunks mean %.1f max %d, lights mean %.1f max %d, draw calls mean %.0f, explosions %d" % [
			label, _mean(bolts), _max(bolts), _mean(particles_busy), _max(particles_busy), _mean(debris_chunks), _max(debris_chunks), _mean(lights_on), _max(lights_on), _mean(draw_calls),
			explosions])
	print("[measure] %s: last tick's ai.think_us mean %.0f p99 %.0f, combat.resolve_us mean %.0f p99 %.0f, ram.resolve_us mean %.0f p99 %.0f" % [
			label, _mean(ai_us), _percentile(ai_us, 0.99), _mean(hit_us), _percentile(hit_us, 0.99), _mean(ram_us), _percentile(ram_us, 0.99)])
	print("[measure] %s: renderer %s, gpu %s, %dx%d, vsync %d, ambient %.2f, particle_density %.2f, lens_flare %s, motion_blur %s, running_lights %s" % [
			label, _read("render.renderer"), _read("render.gpu"), get_window().size.x, get_window().size.y, DisplayServer.window_get_vsync_mode(),
			float(Settings.get_value(&"ambient_level")), Settings.get_value(&"particle_density"), Settings.get_value(&"lens_flare"), Settings.get_value(&"motion_blur"),
			_read("ship.running_lights")])
	print("[measure] %s: paused %s, triangles mean %.0f max %d, objects mean %.0f, draw calls mean %.0f max %d, frame ms p99 %.2f max %.2f" % [
			label, _paused, _mean(primitives), _max(primitives), _mean(objects), _mean(draw_calls), _max(draw_calls),
			_percentile(frame_ms, 0.99), _max(frame_ms)])  # M4-T27: the render comparison
	var root: Window = get_tree().root
	print("[measure] %s: window %dx%d %s, 3d scale %.2f, 3d scaling mode %d, frame mean ms %.2f, fps mean %.1f, frame p99 ms %.2f, fps 1%% low %.1f" % [label,
			root.size.x, root.size.y,
			"fullscreen" if DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN] else "windowed",
			root.scaling_3d_scale, root.scaling_3d_mode, _mean(frame_ms), 1000.0 / maxf(_mean(frame_ms), 1e-6),
			_percentile(frame_ms, 0.99), PerfStats.low_fps(frame_ms, LOW_SHARE)])  # M4-T07: the fullscreen check; M4-P2: the 1 % low (Q48)
	# How much of real time the simulation kept: a tick slower than a frame leaves the engine at its step cap, so the frame rate
	# then reads the tick, not the renderer (60 ticks a second is real time).
	var window_s: float = float(Time.get_ticks_usec() - _window_start_usec) * 1e-6
	print("[measure] %s: sim ticks %d in %.1f s = %.1f a second (%.2f of real time), ticks a frame mean %.2f" % [
			label, _window_ticks, window_s, float(_window_ticks) / maxf(window_s, 1e-6),
			float(_window_ticks) / maxf(window_s, 1e-6) / float(Engine.physics_ticks_per_second), float(_window_ticks) / maxf(1.0, float(frame_ms.size()))])
	# The window's first frames beside the rest: a loading frame at the start shows here as a first-frames mean far above the window's.
	var first_ms := frame_ms.slice(0, mini(START_FRAMES, frame_ms.size()))
	print("[measure] %s: window start: first %d frames mean ms %.2f max %.2f, the whole window mean ms %.2f max %.2f" % [
			label, first_ms.size(), _mean(first_ms), _max(first_ms), _mean(frame_ms), _max(frame_ms)])
	print("[measure] %s: VRAM before %.0f MB, peak %.0f MB, added %.0f MB; GTT before %.0f MB, peak %.0f MB, added %.0f MB" % [
			label, vram_before_mb, vram_peak_mb, vram_peak_mb - vram_before_mb, gtt_before_mb, gtt_peak_mb, gtt_peak_mb - gtt_before_mb])
	own_vram_peak_mb = maxf(own_vram_peak_mb, _own_vram_mb())
	print("[measure] %s: this process's VRAM before %.0f MB, peak %.0f MB (the kernel's per-process count; the card-wide figures above include the desktop)" % [
			label, own_vram_before_mb, own_vram_peak_mb])
	for spike: String in spikes:
		print("[measure] %s: over 25 ms at %s" % [label, spike])
	var shot: String = String(options["shot"])
	if not shot.is_empty():
		get_viewport().get_texture().get_image().save_png(shot)
		print("[measure] %s: saved %s" % [label, shot])
	get_tree().quit(0)


func _find_vram_dir() -> String:
	for card: String in VRAM_CARDS:
		var directory: String = "/sys/class/drm/%s/device/" % card
		if FileAccess.file_exists(directory + "mem_info_vram_used"):
			return directory
	return ""


func _read_mb(file_name: String) -> float:
	if _vram_dir.is_empty():
		return 0.0
	return FileAccess.get_file_as_string(_vram_dir + file_name).strip_edges().to_float() / 1048576.0


# This process's video memory, from the kernel's per-client counts (each DRM client counted once), so the desktop's own use and
# other programs' do not move it. 0 where the driver does not report it. Read through `cat` because Godot's file reads stall on
# some of the pseudo-files in /proc.
func _own_vram_mb() -> float:
	var output: Array = []
	if OS.execute("sh", ["-c", "cat /proc/%d/fdinfo/* 2>/dev/null" % OS.get_process_id()], output) != 0 or output.is_empty():
		return 0.0
	var seen: Dictionary = {}
	var total_kib: float = 0.0
	var client: String = ""
	var vram_kib: float = -1.0
	for line: String in (String(output[0]) + "\npos:").split("\n"):
		if line.begins_with("pos:"):  # the next descriptor's record starts: close the last one
			if vram_kib >= 0.0 and not client.is_empty() and not seen.has(client):
				seen[client] = true
				total_kib += vram_kib
			client = ""
			vram_kib = -1.0
		elif line.begins_with("drm-client-id:"):
			client = line.get_slice(":", 1).strip_edges()
		elif line.begins_with("drm-memory-vram:"):
			vram_kib = line.get_slice(":", 1).strip_edges().get_slice(" ", 0).to_float()
	return total_kib / 1024.0


static func _mean(values: PackedFloat64Array) -> float:
	var sum: float = 0.0
	for value: float in values:
		sum += value
	return sum / maxf(1.0, float(values.size()))


static func _min(values: PackedFloat64Array) -> float:
	var best: float = INF
	for value: float in values:
		best = minf(best, value)
	return best if values.size() > 0 else 0.0


static func _max(values: PackedFloat64Array) -> float:
	var best: float = -INF
	for value: float in values:
		best = maxf(best, value)
	return best if values.size() > 0 else 0.0


static func _percentile(values: PackedFloat64Array, share: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size() - 1, int(share * float(sorted.size())))]
