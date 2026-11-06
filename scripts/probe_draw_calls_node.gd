extends Node
## What one hull costs in Godot's draw calls, by kind (M4-T27, the question T11 left). The game's main scene with the player alone,
## then 40 copies of one kind 100 to 400 m ahead, 90 frames each, the mean draw calls, triangles and objects of the last 60: the
## textured mesh in view, the same hidden, the same behind the camera, and the OBJ. One line per phase. Run it on the real renderer:
## the counts are the renderer's.
##
## Arguments after `--`: count=<n> (40), from=<phase> (0: the phases before it are skipped, the player alone always runs),
## asset=<id> (raider_fighter), wings=<a,b,...> (M4-T30b: the textured copies take these wings' liveries in turn, each with its own
## number), to=<phase> (the last phase run).

const FRAMES: int = 60
const SETTLE: int = 20

var main: Main
var count: int = 40
var from: int = 0
var asset: String = "raider_fighter"
var wings: PackedStringArray = PackedStringArray()
var to: int = 99
var _nodes: Array[Node3D] = []
var _phase: int = -1
var _frame: int = 0
var _draws := PackedFloat64Array()
var _tris := PackedFloat64Array()
var _objects := PackedFloat64Array()
var _phases: Array[String] = ["player alone", "textured meshes in view", "textured meshes hidden", "textured meshes behind the camera",
		"OBJs"]


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = arg.split("=", true, 1)
		if pair.size() == 2 and pair[0] == "count":
			count = int(pair[1])
		elif pair.size() == 2 and pair[0] == "from":
			from = int(pair[1])
		elif pair.size() == 2 and pair[0] == "asset":
			asset = pair[1]
		elif pair.size() == 2 and pair[0] == "wings":
			wings = pair[1].split(",")
		elif pair.size() == 2 and pair[0] == "to":
			to = int(pair[1])
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.waves_auto_start = false
	main.input_source = FakeInputSource.new()
	get_tree().root.add_child.call_deferred(main)
	main.ready.connect(_start.call_deferred, CONNECT_ONE_SHOT)


func _start() -> void:
	for line: String in ["god on", "wave stop", "despawn all", "camera chase"]:
		DebugConsole.registry.execute(line)
	get_tree().process_frame.connect(_on_frame)
	_next_phase()


func _place(i: int, behind: bool) -> Transform3D:
	var golden: float = PI * (3.0 - sqrt(5.0))
	var t: float = float(i) / float(maxi(count - 1, 1))
	var ahead: Vector3 = Vector3(sqrt(t) * 120.0 * cos(golden * i), sqrt(t) * 70.0 * sin(golden * i), -lerpf(100.0, 400.0, t))
	if behind:
		ahead.z = -ahead.z + 60.0
	return main.ship.global_transform * Transform3D(Basis.IDENTITY, ahead)


func _clear() -> void:
	for node: Node3D in _nodes:
		node.queue_free()
	_nodes.clear()


func _build(phase: int) -> void:
	_clear()
	var dir: String = ShipSpec.ASSET_ROOT.path_join(asset)
	var obj_mesh := load(dir.path_join(asset + ".obj")) as Mesh
	for i: int in (0 if phase == 0 else count):
		var node := MeshInstance3D.new()
		if phase == 4:
			node.mesh = obj_mesh
		else:
			node.mesh = MeshAssets.for_asset(asset)
			if not wings.is_empty():
				Livery.for_wing(wings[i % wings.size()], i / wings.size() + 1, MeshAssets.livery_section(asset)).apply(node)
		node.visible = phase != 2
		main.world.add_child(node)
		node.global_transform = _place(i, phase == 3)
		_nodes.append(node)


func _next_phase() -> void:
	if _phase >= 0:
		print("[probe] %d %s: %d copies, draw calls mean %.1f, triangles mean %.0f, objects mean %.1f, at %.0f s" % [_phase, _phases[_phase],
				0 if _phase == 0 else count, _mean(_draws), _mean(_tris), _mean(_objects), Time.get_ticks_msec() * 1e-3])
	_phase += 1
	if _phase > 0 and _phase < from:
		_phase = from
	_frame = 0
	_draws.clear()
	_tris.clear()
	_objects.clear()
	if _phase >= _phases.size() or _phase > to:
		_clear()
		get_tree().quit(0)
		return
	_build(_phase)


func _on_frame() -> void:
	_frame += 1
	if _frame > SETTLE:
		_draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_tris.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		_objects.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	if _frame >= FRAMES:
		_next_phase()


static func _mean(values: PackedFloat64Array) -> float:
	var sum: float = 0.0
	for value: float in values:
		sum += value
	return sum / maxf(1.0, float(values.size()))
