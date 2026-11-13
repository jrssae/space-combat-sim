extends Node
## Photographs the Starfury's finish for the maintainer's look sheet (M7-T17): the game's main scene with one Starfury parked by
## `sheet` in a wing's livery, posed in the camera's frame and lit per shot, in both texture sets. The shots: a sun grazing the decks
## from the far side (its highlight smears across the plating toward the camera), the look sheets' three-quarter view lit from over
## the shoulder, and a close view at about 7 m. Each frame waits for drawn frames, not process frames, so a window the compositor
## stops drawing cannot leave a stale image.
##
## Arguments after `--`: out=<dir> prefix=<name> settle=<drawn frames> livery=<wing:number>. Run by scripts/starfury_metal_sheet.sh.

const SYSFS_VRAM: String = "/sys/class/drm/card1/device/mem_info_vram_used"
const LIT_LIGHT: Vector3 = Vector3(0.3, -0.35, -1.0)  # camera frame: over the camera's left shoulder, as the look sheets
## Each shot: distance (m), the ship's turn off nose-on and its tilt toward the camera (deg), and the light.
const SHOTS: Array[Dictionary] = [
	{"name": "grazing", "d": 20.0, "yaw": 50.0, "pitch": 28.0, "light": "graze", "sun_deg": 12.0},
	{"name": "three_quarter", "d": 22.0, "yaw": 38.0, "pitch": 18.0, "light": "lit"},
	{"name": "close7m", "d": 7.0, "yaw": 30.0, "pitch": 22.0, "light": "half"},
]
const DETAILS: Array[String] = ["high", "low"]
const STALL_FRAMES: int = 2000  # process frames without enough drawn ones: the window is not being drawn

var main: Main
var options: Dictionary = {"out": "user://", "prefix": "shot", "settle": "50", "livery": "alpha:1"}
var _queue: Array[Dictionary] = []
var _index: int = -1
var _frame: int = 0
var _drawn_at: int = 0
var _look: LookScene = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = arg.split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	for detail: String in DETAILS:
		for shot: Dictionary in SHOTS:
			_queue.append(shot.merged({"detail": detail}))
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.waves_auto_start = false
	main.input_source = FakeInputSource.new()
	get_tree().root.add_child.call_deferred(main)
	get_tree().set_deferred(&"current_scene", main)
	main.ready.connect(_start.call_deferred, CONNECT_ONE_SHOT)


func _start() -> void:
	for line: String in ["god on", "wave stop", "despawn all", "flare off", "fps off"]:
		_run(line)
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	if main.overlay != null:
		main.overlay.visible = false
	_look = main.get_node(^"LookScene") as LookScene
	get_tree().process_frame.connect(_on_frame)
	_next()


func _run(line: String) -> void:
	for result: ConsoleResult in DebugConsole.registry.execute(line):
		if not result.ok:
			print("[starfury_metal_sheet] console error on '%s': %s" % [line, "; ".join(result.lines)])


func _next() -> void:
	_index += 1
	_frame = 0
	_drawn_at = Engine.get_frames_drawn()
	if _index >= _queue.size():
		get_tree().quit(0)
		return
	var shot: Dictionary = _queue[_index]
	_run("set settings.texture_detail %s" % shot["detail"])
	_run("sheet starfury_aurora %s lit %s" % [shot["d"], options["livery"]])


# Holds the parked ship where the shot wants it in the camera's frame and turns the key star for the shot.
func _pose() -> void:
	var shot: Dictionary = _queue[_index]
	var camera: Camera3D = get_viewport().get_camera_3d()
	var parked: Combatant = _look.parked()
	if camera == null or parked == null:
		return
	var cam: Transform3D = camera.global_transform
	var at: Vector3 = cam.origin - cam.basis.z * float(shot["d"])
	var to_camera: Vector3 = (cam.origin - at).normalized()
	var basis := Basis.looking_at(to_camera, cam.basis.y).rotated(cam.basis.y, deg_to_rad(float(shot["yaw"]))) \
			.rotated(cam.basis.x, deg_to_rad(float(shot["pitch"]))).orthonormalized()
	var body: Ship = parked.ship
	body.global_transform = Transform3D(basis, at)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	var lit: Vector3 = (cam.basis * LIT_LIGHT).normalized()
	# The light that a surface facing the ship's up would mirror into the camera.
	var normal: Vector3 = basis.y
	var mirror: Vector3 = -(2.0 * normal.dot(to_camera) * normal - to_camera).normalized()
	var direction: Vector3 = lit
	if shot["light"] == "graze":
		# The sun low over the decks on the mirror's bearing, so its highlight runs across them toward the camera.
		var flat: Vector3 = (mirror - normal * mirror.dot(normal)).normalized()
		var sun: float = deg_to_rad(float(shot["sun_deg"]))
		direction = (flat * cos(sun) - normal * sin(sun)).normalized()
	elif shot["light"] == "half":
		direction = (mirror + lit).normalized()
	var star: DirectionalLight3D = main.space_environment.key_star
	var up: Vector3 = cam.basis.y if absf(direction.dot(cam.basis.y)) < 0.99 else cam.basis.x
	star.global_transform = Transform3D(Basis.looking_at(direction, up), star.global_position)


func _on_frame() -> void:
	if _index < 0 or _index >= _queue.size():
		return
	_pose()
	_frame += 1
	if Engine.get_frames_drawn() - _drawn_at < int(options["settle"]):
		if _frame > STALL_FRAMES:
			print("[starfury_metal_sheet] drawing stalled: %d frames drawn in %d (run on X11: --display-driver x11)" % [
					Engine.get_frames_drawn() - _drawn_at, _frame])
			get_tree().quit(2)
		return
	var shot: Dictionary = _queue[_index]
	var path: String = "%s/%s_%s_%s.png" % [options["out"], options["prefix"], shot["detail"], shot["name"]]
	get_viewport().get_texture().get_image().save_png(path)
	var stats: Array[String] = []
	for key: String in ["renderer", "fps", "draw_calls"]:
		stats.append("%s=%s" % [key, str(DebugConsole.registry.read("render.%s" % key).get("value", "?"))])
	var vram: FileAccess = FileAccess.open(SYSFS_VRAM, FileAccess.READ)
	print("[starfury_metal_sheet] %s %s %s card_vram_mb=%.0f -> %s" % [shot["detail"], shot["name"], " ".join(stats),
			(int(vram.get_line()) if vram != null else -1) / 1048576.0, path])
	_next()
