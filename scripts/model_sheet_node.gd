extends Node
## Photographs a generated model that the game does not know yet (M10-T50: a hull with no `ShipSpec` or catalogue entry), for
## its option and look sheets: the game's main scene and light, the model's textured mesh with the game's own materials parked
## ahead of the chase camera for each shot, held a few frames and saved. `scripts/model_sheet.sh` lays the shots out.
##
## Arguments after `--`: out=<dir> settle=<frames> shots=<shot>,<shot>,... where a shot is
## `name|asset[:option]|distance_m|view|low or high|lit or dark|aim|livery`: `view` one of VIEWS; `aim` the model point
## (`x;y;z`, its own frame) held `distance_m` ahead of the camera (empty: its centre); `livery` a `wing:number` (empty: plain).
## `lit+bays` or `dark+bays` also lights every bay's red lamp, as an open door does in the game (M10-T22). A `livery` of
## `name:<ship name>` paints the hull's name marks for that name (M10-T67).
## An option is read from `<asset>_options/<option>/<asset>/`, as the hull sheets'. An asset of `-` is a shot of the empty
## scene, whose video memory is the baseline for the model's.

const VIEWS: PackedStringArray = ["three_quarter", "rear_quarter", "top", "bottom", "side", "front"]
const YAW_DEG: float = 38.0
const PITCH_DEG: float = 16.0
const FIELDS: int = 8

var main: Main
var options: Dictionary = {"out": "", "settle": "50", "shots": ""}
var shots: Array[PackedStringArray] = []
var _key_star: DirectionalLight3D = null
var _model: MeshInstance3D = null
var _bay_lamps: Array[LightEmitter] = []
var _index: int = -1
var _frame: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = arg.split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	for shot: String in String(options["shots"]).split(",", false):
		var fields: PackedStringArray = shot.split("|")
		if fields.size() >= 5:
			fields.resize(FIELDS)
			shots.append(fields)
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.waves_auto_start = false
	main.input_source = FakeInputSource.new()
	var tree: SceneTree = get_tree()
	tree.root.add_child.call_deferred(main)
	tree.set_deferred(&"current_scene", main)
	main.ready.connect(_start.call_deferred, CONNECT_ONE_SHOT)


func _start() -> void:
	for line: String in ["god on", "wave stop", "despawn all", "camera chase", "flare off", "fps off", "scaled hide"]:
		for result: ConsoleResult in DebugConsole.registry.execute(line):
			if not result.ok:
				print("[model sheet] console error on %s: %s" % [line, "; ".join(result.lines)])
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false  # the pictures are of the model, not the HUD
	if main.overlay != null:
		main.overlay.visible = false
	for child: Node in main.world.get_children():
		if child is Node3D:
			(child as Node3D).visible = false  # the scenario's own ships and props stay out of the picture
	if main.space_environment != null:
		main.space_environment.hold_key_star(true)  # the sheet turns the light itself
		_key_star = main.space_environment.key_star
	get_tree().process_frame.connect(_on_frame)
	_next()


func _next() -> void:
	_index += 1
	_frame = 0
	var rig: LightRig = LightRig.of(main)
	for lamp: LightEmitter in _bay_lamps:
		if rig != null:
			rig.remove_emitter(lamp)
	_bay_lamps.clear()
	if _model != null:
		_model.queue_free()
		_model = null
	if _index >= shots.size():
		print("[model sheet] renderer %s, gpu %s" % [DebugConsole.registry.read("render.renderer")["value"],
				DebugConsole.registry.read("render.gpu")["value"]])
		get_tree().quit()
		return
	var shot: PackedStringArray = shots[_index]
	Settings.set_value(&"texture_detail", StringName(shot[4]))
	if shot[1] == "-":
		return
	var error: String = _park(shot)
	if not error.is_empty():
		print("[model sheet] %s: %s" % [shot[0], error])
		_next()


# Puts the shot's model ahead of the camera, turned as its view asks, and sets the light.
func _park(shot: PackedStringArray) -> String:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return "no current camera"
	var asset_id: String = shot[1].get_slice(":", 0)
	var root: String = ShipSpec.ASSET_ROOT
	if shot[1].contains(":"):
		root = root.path_join("%s_options" % asset_id).path_join(shot[1].get_slice(":", 1))
	var mesh: Mesh = MeshAssets.for_asset(asset_id, root)
	if mesh == null:
		return "%s is not generated or not imported under %s" % [asset_id, root]
	_model = MeshInstance3D.new()
	_model.mesh = mesh
	main.world.add_child(_model)
	_add_rotors(asset_id, root)
	var section: Dictionary = MeshAssets.livery_section(asset_id, root)
	if not section.is_empty():
		var wing: PackedStringArray = shot[7].split(":")
		Livery.for_wing(wing[0], int(wing[1]) if wing.size() > 1 else 0, section).apply(_model)
	var basis: Basis = _basis(camera, shot[3])
	var aim := Vector3.ZERO
	var parts: PackedStringArray = shot[6].split(";")
	if parts.size() == 3:
		aim = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	var at: Vector3 = camera.global_position - camera.global_basis.z * float(shot[2])
	_model.global_transform = Transform3D(basis, at - basis * aim)
	_light(camera, shot[5].begins_with("dark"))
	if shot[5].ends_with("+bays"):
		_add_bay_lamps(asset_id, root)
	if shot.size() > 7 and shot[7].begins_with("name:"):
		_add_marks(asset_id, root, shot[7].trim_prefix("name:"))
	return ""


# The hull's painted name marks for a ship of that name (a capital's name letter, M10-T67), as the game paints them; the
# faction-only marks stay off.
func _add_marks(asset_id: String, root: String, display_name: String) -> void:
	var dir: String = root.path_join(asset_id)
	var hp: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("hardpoints.json")))
	if not hp is Dictionary or not (hp as Dictionary).get("mark_atlas") is Dictionary:
		return
	for node: HullMarkNode in HullMarkNode.build_all(HullMarks.marks_of(hp), hp["mark_atlas"], dir, display_name):
		node.visible = node.only_faction == &""
		_model.add_child(node)


# Every bay's red lamp at full strength, so its open hall reads as the game lights it.
func _add_bay_lamps(asset_id: String, root: String) -> void:
	var hp: Variant = JSON.parse_string(FileAccess.get_file_as_string(root.path_join(asset_id).path_join("hardpoints.json")))
	var rig: LightRig = LightRig.of(main)
	if not hp is Dictionary or rig == null:
		return
	for light: Variant in (hp as Dictionary).get("lights", []):
		if light is Dictionary and str((light as Dictionary).get("role", "")) == "bay":
			var c: Array = light.get("colour", [1.0, 0.0, 0.0]) as Array
			var lamp := LightEmitter.new(str(light["name"]), LightEmitter.PRIORITY_CABIN, Color(float(c[0]), float(c[1]), float(c[2])),
					BayDoors.LIGHT_ENERGY, float(light.get("range_m", 50.0)), BayDoors.LIGHT_ATTENUATION)
			lamp.anchor = _model
			var at: Array = light["position"]
			lamp.offset = Vector3(float(at[0]), float(at[1]), float(at[2]))
			rig.add_emitter(lamp)
			_bay_lamps.append(lamp)


# A capital's rotating pieces (M10-T21: the Omega's drum) drawn at rest on their pivots, so the model is whole.
func _add_rotors(asset_id: String, root: String) -> void:
	var pieces: Variant = MeshAssets.read_manifest(asset_id, root).get("pieces", {})
	if not pieces is Dictionary:
		return
	for piece_name: String in (pieces as Dictionary):
		var entry: Dictionary = pieces[piece_name]
		if not entry.has("pivot") or not entry.has("mesh"):
			continue
		var rotor := MeshInstance3D.new()
		rotor.mesh = MeshAssets.load_textured(root.path_join(asset_id), entry["mesh"])
		var pivot: Array = entry["pivot"]
		rotor.position = Vector3(float(pivot[0]), float(pivot[1]), float(pivot[2]))
		_model.add_child(rotor)


# Turns the key star as the look sheets do: over the camera's shoulder onto the model, or from behind it so only a rim shows.
func _light(camera: Camera3D, dark: bool) -> void:
	if _key_star == null:
		return
	var direction: Vector3 = (camera.global_basis * (LookScene.DARK_LIGHT if dark else LookScene.LIT_LIGHT)).normalized()
	_key_star.global_transform = Transform3D(Basis.looking_at(direction, camera.global_basis.y), _key_star.global_position)


# The model's turn for a view, in the camera's frame: its nose towards the camera and off to one side, or square on.
func _basis(camera: Camera3D, view: String) -> Basis:
	var cam: Basis = camera.global_basis
	var to_camera: Vector3 = cam.z
	match view:
		"top":
			return Basis.looking_at(cam.y, to_camera).orthonormalized()
		"bottom":
			return Basis.looking_at(cam.y, -to_camera).orthonormalized()
		"front":
			return Basis.looking_at(to_camera, cam.y).orthonormalized()
		"side":
			return Basis.looking_at(-cam.x, cam.y).orthonormalized()
		"rear_quarter":
			return Basis.looking_at(to_camera, cam.y).rotated(cam.y, deg_to_rad(180.0 - YAW_DEG)).rotated(cam.x, deg_to_rad(-PITCH_DEG)).orthonormalized()
	return Basis.looking_at(to_camera, cam.y).rotated(cam.y, deg_to_rad(YAW_DEG)).rotated(cam.x, deg_to_rad(-PITCH_DEG)).orthonormalized()


func _on_frame() -> void:
	if _index < 0 or _index >= shots.size() or (_model == null and shots[_index][1] != "-"):
		return
	_frame += 1
	if _frame < int(options["settle"]):
		return
	var shot: PackedStringArray = shots[_index]
	var path: String = "%s/%s.png" % [options["out"], shot[0]]
	get_viewport().get_texture().get_image().save_png(path)
	print("[model sheet] %s: video memory %.0f MB -> %s" % [shot[0], Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, path])
	_next()
