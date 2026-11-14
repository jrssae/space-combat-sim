extends Node
## Films the turning drum from outside for the flicker check (M7): the game's main scene with the station at its place and the drum
## turning, the camera held still in the station's frame off a Cobra arm's door row at each distance in `VIEWS`, every frame saved
## so `scripts/flicker_metric.py` can look for lights that change and change back from one frame to the next.
##
## Arguments after `--`: out=<dir> frames=<per view> settle=<frames> views=<names, comma separated> set=<setting:value,...>
## sun=<on|off> (off: the key star hidden, to tell what the sun does from what the station's own lights do).
## Run by scripts/flicker_probe.sh on the real renderer.

## The door row's middle on the arm that starts at +x (station frame of docs/assets-station.md), and the way the camera stands off it.
const AIM: Vector3 = Vector3(243.0, 0.0, 1150.0)
const OFF: Vector3 = Vector3(0.82, 0.28, -0.5)
const VIEWS: Array[Dictionary] = [
	{"name": "50m", "m": 50.0, "fov": 62.0},
	{"name": "300m", "m": 300.0, "fov": 55.0},
	{"name": "1km", "m": 1000.0, "fov": 50.0},
	{"name": "3km", "m": 3000.0, "fov": 50.0},
	# The sun straight behind the core (the drum between the docking sphere and the forward body): the camera in its shadow.
	{"name": "sun_1km", "m": 1000.0, "fov": 50.0, "sun_behind": true},
	{"name": "sun_3km", "m": 3000.0, "fov": 50.0, "sun_behind": true},
	{"name": "sun_10km", "m": 10000.0, "fov": 50.0, "sun_behind": true},
]
## The core's middle on the axis, station frame.
const CORE: Vector3 = Vector3(0.0, 0.0, 1500.0)

var main: Main
var options: Dictionary = {"out": "user://", "frames": "240", "settle": "30", "views": "", "set": "", "sun": "on"}
var _views: Array[Dictionary] = []
var _index: int = -1
var _frame: int = 0
var _station: Station = null
var _origin_z: float = 4000.0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = arg.split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	var wanted: PackedStringArray = String(options["views"]).split(",", false)
	for view: Dictionary in VIEWS:
		if wanted.is_empty() or wanted.has(String(view["name"])):
			_views.append(view)
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.waves_auto_start = false
	main.input_source = FakeInputSource.new()
	get_tree().root.add_child.call_deferred(main)
	get_tree().set_deferred(&"current_scene", main)
	main.ready.connect(_start.call_deferred, CONNECT_ONE_SHOT)


func _start() -> void:
	for line: String in ["god on", "wave stop", "despawn all", "fps off"]:
		_run(line)
	for pair: String in String(options["set"]).split(",", false):
		var kv: PackedStringArray = pair.split(":", true, 1)
		_run("set settings.%s %s" % [kv[0], kv[1]])
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	if main.overlay != null:
		main.overlay.visible = false
	main.ship.visible = false
	if main.far_props.station == null:
		_run("far station")
	_station = main.far_props.station
	if _station == null:
		print("[flicker_probe] the station is not generated")
		get_tree().quit(1)
		return
	_origin_z = float((MeshAssets.read_manifest(StationStandin.ASSET_ID).get("centroid_offset", [0.0, 0.0, 4000.0]) as Array)[2])
	var star: DirectionalLight3D = main.space_environment.key_star if main.space_environment != null else null
	if star != null and String(options["sun"]) == "off":
		star.visible = false
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	print("[flicker_probe] sun=%s star mask=%d star shadows=%s" % [options["sun"], star.light_cull_mask if star != null else -1, star.shadow_enabled if star != null else false])
	get_tree().process_frame.connect(_on_frame)
	_next()


func _run(line: String) -> void:
	for result: ConsoleResult in DebugConsole.registry.execute(line):
		print("[flicker_probe] %s -> %s" % [line, "; ".join(result.lines)])


func _local(p: Vector3) -> Array[float]:
	return [p.x, p.y, p.z - _origin_z]


func _next() -> void:
	_index += 1
	_frame = 0
	if _index >= _views.size():
		get_tree().quit(0)
		return
	var view: Dictionary = _views[_index]
	DirAccess.make_dir_recursive_absolute("%s/%s" % [options["out"], view["name"]])
	var at: Vector3 = AIM + OFF.normalized() * float(view["m"])
	var aim: Vector3 = AIM
	if bool(view.get("sun_behind", false)):
		# Away from the star, in the station's frame: the light travels along the star node's -z.
		var star: DirectionalLight3D = main.space_environment.key_star
		var from_sun: Vector3 = (_station.global_basis.inverse() * -star.global_basis.z).normalized()
		aim = CORE
		at = CORE + from_sun * float(view["m"])
	var key: Dictionary = {"position": {"actor": "station", "offset": _local(at)},
			"look_at": {"actor": "station", "offset": _local(aim)}, "fov": view["fov"]}
	var made: Dictionary = CinematicShot.from_dict(StringName(view["name"]), {"keys": [key.merged({"t": 0.0}), key.merged({"t": 3600.0})]})
	main.camera_rig.play_shot(made["shot"], _pose, _origin_to_local)


func _pose(actor: String) -> Variant:
	return _station.global_transform if actor == "station" and is_instance_valid(_station) else null


func _origin_to_local(offset: PackedFloat64Array) -> Vector3:
	return main.world.universe_to_local(UniversePos.new(offset[0], offset[1], offset[2], main.world.origin.system_id))


func _on_frame() -> void:
	if _index < 0 or _index >= _views.size():
		return
	_frame += 1
	var settle: int = int(options["settle"])
	if _frame <= settle:
		return
	var name: String = String(_views[_index]["name"])
	if _frame == settle + 1:
		var stats: Array[String] = []
		for key: String in ["renderer", "draw_calls", "gpu_ms", "triangles"]:
			stats.append("%s=%s" % [key, str(DebugConsole.registry.read("render.%s" % key).get("value", "?"))])
		print("[flicker_probe] %s: %s drum_deg=%s lights=%s far=%s" % [name, " ".join(stats),
				str(DebugConsole.registry.read("station.drum_deg").get("value", "?")),
				str(DebugConsole.registry.read("lights.picked").get("value", "?")),
				str(DebugConsole.registry.read("far.layout").get("value", "?"))])
	get_viewport().get_texture().get_image().save_png("%s/%s/f%08d.png" % [options["out"], name, _frame - settle - 1])
	if _frame >= settle + int(options["frames"]):
		_next()
