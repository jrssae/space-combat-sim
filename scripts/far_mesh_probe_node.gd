extends Node
## What capital hulls cost the GPU near and far, with and without their far meshes (M10-T89): the game's main scene with the player
## alone and its world hidden, then one phase per entry of `phases`, each a set of generated capitals drawn as the game draws them
## (`RenderPiece`, every piece at its pivot) at a distance from the camera, the far meshes used as the phase says
## (`FarMeshRange`: auto, full, far). Each phase prints its draw calls, triangles, frame and GPU time and video memory, and saves
## a picture. Run it on the real renderer: scripts/far_mesh_probe.sh.
##
## Arguments after `--`: out=<dir> settle=<frames> frames=<frames> phases=<phase,...>, a phase `<asset>[+<asset>...]@<km>@<mode>`
## (one of each asset, side by side across the view) or `fleet<n>@<km>@<mode>` (n capitals of the assets in `fleet_assets`,
## spread over the view from km to twice as far); `empty` draws nothing: the baseline.

var main: Main
var options: Dictionary = {"out": "", "settle": "60", "frames": "120", "phases": "", "fleet_assets": "ea_omega,ea_nova,ea_hyperion"}
var _phases: PackedStringArray = []
var _nodes: Array[Node3D] = []
var _index: int = -1
var _frame: int = 0
var _draws := PackedFloat64Array()
var _tris := PackedFloat64Array()
var _gpu := PackedFloat64Array()
var _frame_ms := PackedFloat64Array()
var _last_usec: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = arg.split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	_phases = String(options["phases"]).split(",", false)
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.waves_auto_start = false
	main.input_source = FakeInputSource.new()
	get_tree().root.add_child.call_deferred(main)
	get_tree().set_deferred(&"current_scene", main)
	main.ready.connect(_start.call_deferred, CONNECT_ONE_SHOT)


func _start() -> void:
	for line: String in ["god on", "wave stop", "despawn all", "camera chase", "flare off", "fps off", "scaled hide"]:
		DebugConsole.registry.execute(line)
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	if main.overlay != null:
		main.overlay.visible = false
	for child: Node in main.world.get_children():
		if child is Node3D:
			(child as Node3D).visible = false
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	get_tree().process_frame.connect(_on_frame)
	_next()


# One capital of `asset_id`, every piece at its pivot, its origin at `at` (World-local), turned by `yaw`.
func _capital(asset_id: String, at: Vector3, yaw: float) -> Node3D:
	var manifest: Dictionary = MeshAssets.read_manifest(asset_id)
	var dir: String = ShipSpec.ASSET_ROOT.path_join(asset_id)
	var root := Node3D.new()
	main.world.add_child(root)
	var pieces: Dictionary = manifest.get("pieces", {"hull": {"mesh": manifest.get("mesh", {})}})
	for piece_name: String in pieces:
		var piece := RenderPiece.new()
		piece.build(dir, pieces[piece_name])
		var pivot: Array = pieces[piece_name].get("pivot", [0.0, 0.0, 0.0])
		piece.position = Vector3(pivot[0], pivot[1], pivot[2])
		root.add_child(piece)
	root.global_transform = Transform3D(Basis.from_euler(Vector3(0.25, yaw, 0.0)), at)
	_nodes.append(root)
	return root


func _ahead(distance_m: float, side: float, up: float) -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var basis: Basis = camera.global_transform.basis
	return camera.global_position - basis.z * distance_m + basis.x * side + basis.y * up


func _next() -> void:
	_index += 1
	_frame = 0
	for node: Node3D in _nodes:
		node.queue_free()
	_nodes.clear()
	for series: PackedFloat64Array in [_draws, _tris, _gpu, _frame_ms]:
		series.clear()
	if _index >= _phases.size():
		print("[far] renderer %s, gpu %s, %s" % [DebugConsole.registry.read("render.renderer")["value"],
				DebugConsole.registry.read("render.gpu")["value"], get_viewport().get_visible_rect().size])
		get_tree().quit()
		return
	var fields: PackedStringArray = _phases[_index].split("@")
	if fields[0] == "empty":
		return
	var km: float = float(fields[1])
	var mode: int = FarMeshRange.mode_named(fields[2] if fields.size() > 2 else "auto")
	FarMeshRange.mode = mode as FarMeshRange.Mode
	var camera: Camera3D = get_viewport().get_camera_3d()
	var half_w: float = tan(deg_to_rad(camera.fov) * 0.5) * float(get_viewport().get_visible_rect().size.aspect())
	if fields[0].begins_with("fleet"):
		var n: int = int(fields[0].trim_prefix("fleet"))
		var assets: PackedStringArray = String(options["fleet_assets"]).split(",")
		var rng := RandomNumberGenerator.new()
		rng.seed = 89
		for k: int in n:
			var d: float = km * 1000.0 * rng.randf_range(1.0, 2.0)
			_capital(assets[k % assets.size()], _ahead(d, rng.randf_range(-0.7, 0.7) * half_w * d, rng.randf_range(-0.3, 0.3) * d * 0.5),
					rng.randf_range(-PI, PI))
	else:
		var assets: PackedStringArray = fields[0].split("+")
		var d: float = km * 1000.0
		for k: int in assets.size():
			var side: float = (float(k) - 0.5 * float(assets.size() - 1)) * 0.5 * half_w * d
			_capital(assets[k], _ahead(d, side, 0.0), 2.2)


func _on_frame() -> void:
	if _index < 0 or _index >= _phases.size():
		return
	_frame += 1
	var now: int = Time.get_ticks_usec()
	if _frame > int(options["settle"]):
		_frame_ms.append(float(now - _last_usec) / 1000.0)
		_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		_draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_tris.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_last_usec = now
	if _frame < int(options["settle"]) + int(options["frames"]):
		return
	var path: String = "%s/%s.png" % [options["out"], _phases[_index].replace("@", "_").replace("+", "_")]
	get_viewport().get_texture().get_image().save_png(path)
	print("[far] %s: draw calls %.0f, triangles %.0f, frame %.2f ms, gpu %.3f ms, renderer video %.0f MB, card %.0f MB" % [
			_phases[_index], _median(_draws), _median(_tris), _median(_frame_ms), _median(_gpu),
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, _card_mb()])
	_next()


static func _card_mb() -> float:
	var reading: VramReading = VramReading.read(0, RenderingServer.get_video_adapter_name())
	return reading.used_bytes / 1048576.0 if reading.has_total() else -1.0


static func _median(values: PackedFloat64Array) -> float:
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0
