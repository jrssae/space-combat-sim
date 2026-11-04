extends Node
## What one hull costs in Godot's draw calls, by kind (M4-T27, the question T11 left: why a splat node seemed to add about 2). The game's
## main scene with the player alone, then 40 copies of one kind 100 to 400 m ahead, 90 frames each, the mean draw calls, triangles and
## objects of the last 60: bare splat nodes in view, the same hidden, the same behind the camera, the painted mesh, the fallback OBJ,
## the merged depth proxy. One line per phase. Run it on the real renderer: the counts are the renderer's.
##
## Arguments after `--`: count=<n> (40), from=<phase> (0: the phases before it are skipped, the player alone always runs).

const FRAMES: int = 60
const SETTLE: int = 20
const ASSET: String = "raider_fighter"

var main: Main
var count: int = 40
var from: int = 0
var _nodes: Array[Node3D] = []
var _phase: int = -1
var _frame: int = 0
var _draws := PackedFloat64Array()
var _tris := PackedFloat64Array()
var _objects := PackedFloat64Array()
var _phases: Array[String] = ["player alone", "splat nodes in view", "splat nodes hidden", "splat nodes behind the camera",
		"painted meshes", "fallback OBJs", "depth proxies", "proxy and splat node each (a splat ship)"]


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = arg.split("=", true, 1)
		if pair.size() == 2 and pair[0] == "count":
			count = int(pair[1])
		elif pair.size() == 2 and pair[0] == "from":
			from = int(pair[1])
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
	var dir: String = ShipSpec.ASSET_ROOT.path_join(ASSET)
	var fallback := load(dir.path_join(ASSET + ".obj")) as Mesh
	for i: int in (0 if phase == 0 else count):
		var node: Node3D = null
		match phase:
			1, 2, 3, 7:
				var splat := GaussianSplatNode.new()
				splat.gaussian = load(dir.path_join(ASSET + ".ply")) as GaussianResource
				SplatLightingLoader.attach(splat, SplatLod.lighting_path(ASSET, 0))
				node = splat
				if phase == 7:
					var proxy := HullDepthProxy.new()
					proxy.use_mesh(fallback)
					splat.add_child(proxy)
			4:
				var painted := MeshInstance3D.new()
				painted.mesh = PaintMeshes.for_asset(ASSET)
				node = painted
			5:
				var obj := MeshInstance3D.new()
				obj.mesh = fallback
				node = obj
			6:
				var proxy := HullDepthProxy.new()
				proxy.use_mesh(fallback)
				node = proxy
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
	if _phase >= _phases.size():
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
