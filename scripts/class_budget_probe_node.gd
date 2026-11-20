extends Node
## What a fleet costs the GPU when every hull is at its class's ceiling (M10-T05, Q38): the measurement behind the class budgets
## in docs/assets-capital.md. The game's main scene with the player alone and its world hidden, then one phase per line of
## `phases`: stand-in hulls built here to a class's numbers (triangles with the importer's levels of detail, one surface and
## one set of four block-compressed maps per atlas, the shared detail tile laid over them as the game lays it), several types
## per class so their textures are not shared, spread ahead of the camera. Each phase prints its frame rate, GPU time, draw
## calls, triangles and video memory, and saves a picture. Run it on the real renderer: scripts/class_budget_probe.sh.
##
## Arguments after `--`: out=<dir> settle=<frames> frames=<frames> classes=<name:length_m:triangles:atlas_px:atlases,...>
## phases=<name|class:types:copies;...|lod or full|close,...> (`close`: the first hull 50 m off the camera). A phase named
## `asset:<id>[@<yaw>[@<range in lengths>]]` shows that generated asset instead (every piece at its pivot), and `empty` nothing:
## the baseline.

const DETAIL_TILE_M: float = 16.0
const MAPS: Array[String] = ["albedo", "normal", "orm", "emissive"]

var main: Main
var options: Dictionary = {"out": "", "settle": "90", "frames": "240", "classes": "", "phases": ""}
var classes: Dictionary = {}
var phases: Array[PackedStringArray] = []
var _nodes: Array[Node3D] = []
var _index: int = -1
var _frame: int = 0
var _frame_ms := PackedFloat64Array()
var _gpu_ms := PackedFloat64Array()
var _draws := PackedFloat64Array()
var _tris := PackedFloat64Array()
var _last_usec: int = 0
var _texture_bytes: int = 0
var _source_tris: int = 0
var _detail: Dictionary = {}
var _lod_threshold: float = 1.0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = arg.split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	for entry: String in String(options["classes"]).split(",", false):
		var f: PackedStringArray = entry.split(":")
		classes[f[0]] = {"length": float(f[1]), "triangles": int(f[2]), "atlas_px": int(f[3]), "atlases": int(f[4])}
	for entry: String in String(options["phases"]).split(",", false):
		phases.append(entry.split("|"))
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.waves_auto_start = false
	main.input_source = FakeInputSource.new()
	var tree: SceneTree = get_tree()
	tree.root.add_child.call_deferred(main)
	tree.set_deferred(&"current_scene", main)
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
	_lod_threshold = get_viewport().mesh_lod_threshold
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	get_tree().process_frame.connect(_on_frame)
	_next()


# --- stand-in hulls ---------------------------------------------------------------------------------------------------
# A block-compressed map of `px` with mipmaps, its content a few flat patches (the card's cost is the format's, not the picture's).
func _map(px: int, kind: String, rng: RandomNumberGenerator) -> ImageTexture:
	var image := Image.create(px, px, false, Image.FORMAT_RGB8)
	var base: Color = Color(0.5, 0.5, 1.0) if kind == "normal" else (Color.BLACK if kind == "emissive" else Color(0.35, 0.37, 0.4))
	image.fill(base)
	for i: int in 48:
		var size := Vector2i(rng.randi_range(px / 64, px / 6), rng.randi_range(px / 64, px / 6))
		var shade: Color = base.lerp(Color(rng.randf(), rng.randf(), rng.randf()), 0.08 if kind == "normal" else 0.25)
		image.fill_rect(Rect2i(Vector2i(rng.randi_range(0, px - size.x), rng.randi_range(0, px - size.y)), size),
				base if kind == "emissive" else shade)
	image.generate_mipmaps()
	image.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_NORMAL if kind == "normal" else Image.COMPRESS_SOURCE_GENERIC)
	_texture_bytes += image.get_data_size()
	return ImageTexture.create_from_image(image)


func _detail_tile() -> Dictionary:
	if _detail.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var albedo := Image.create(1024, 1024, false, Image.FORMAT_RGBA8)
		albedo.fill(Color(0.9, 0.9, 0.9, 0.35))
		for i: int in 96:
			var at := Vector2i(rng.randi_range(0, 1000), rng.randi_range(0, 1000))
			albedo.fill_rect(Rect2i(at, Vector2i(rng.randi_range(8, 200), 6)), Color(0.5, 0.5, 0.5, 1.0))
		albedo.generate_mipmaps()
		albedo.compress(Image.COMPRESS_S3TC)
		_texture_bytes += albedo.get_data_size()
		_detail = {"albedo": ImageTexture.create_from_image(albedo), "normal": _map(1024, "normal", rng)}
	return _detail


# A material as `MeshAssets.textured_material` makes one, with the shared tile over it (`apply_world_detail`).
func _material(px: int, rng: RandomNumberGenerator) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.albedo_texture = _map(px, "albedo", rng)
	material.normal_enabled = true
	material.normal_texture = _map(px, "normal", rng)
	var orm: ImageTexture = _map(px, "orm", rng)
	material.ao_enabled = true
	material.ao_texture = orm
	material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.roughness_texture = orm
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	material.metallic = 1.0
	material.metallic_texture = orm
	material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	material.emission_enabled = true
	material.emission_texture = _map(px, "emissive", rng)
	var detail: Dictionary = _detail_tile()
	material.detail_enabled = true
	material.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	material.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	material.detail_albedo = detail["albedo"]
	material.detail_normal = detail["normal"]
	material.uv2_triplanar = true
	material.uv2_triplanar_sharpness = 4.0
	material.uv2_scale = Vector3.ONE / DETAIL_TILE_M
	return material


# A hull-shaped mesh of about `triangles` triangles in `atlases` surfaces along its length, with the importer's levels of detail.
func _hull_mesh(length: float, triangles: int, atlases: int, rng: RandomNumberGenerator) -> ArrayMesh:
	var importer := ImporterMesh.new()
	var per: int = maxi(triangles / atlases, 64)
	var rows: int = maxi(int(sqrt(per / 8.0)), 2)  # along the length; four times as many round the girth
	var cols: int = maxi(per / (2 * rows), 8)
	var half := Vector2(length * 0.1, length * 0.07)
	var phase: float = rng.randf() * TAU
	for a: int in atlases:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for r: int in rows + 1:
			var t: float = (float(a) + float(r) / float(rows)) / float(atlases)
			var taper: float = 0.35 + 0.65 * sin(PI * clampf(0.12 + 0.8 * t, 0.0, 1.0))
			for c: int in cols + 1:
				var turn: float = TAU * float(c) / float(cols)
				var bump: float = 1.0 + 0.04 * sin(9.0 * turn + phase) * sin(40.0 * t + phase)
				var side := Vector2(cos(turn), sin(turn))
				# A rounded box: the girth's circle pushed out toward its corners.
				var box: float = 1.0 / maxf(maxf(absf(side.x), absf(side.y)), 0.5) * 0.85
				st.set_uv(Vector2(float(c) / float(cols), float(r) / float(rows)))
				st.add_vertex(Vector3(side.x * half.x * taper * box * bump, side.y * half.y * taper * box * bump, (t - 0.5) * length))
		for r: int in rows:
			for c: int in cols:
				var i: int = r * (cols + 1) + c
				for k: int in [i, i + 1, i + cols + 1, i + 1, i + cols + 2, i + cols + 1]:
					st.add_index(k)
		st.generate_normals()
		st.generate_tangents()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	importer.generate_lods(60.0, 25.0, [])
	return importer.get_mesh()


func _fleet(layout: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261120
	var slot: int = 0
	var golden: float = PI * (3.0 - sqrt(5.0))
	for group: String in layout.split(";", false):
		var f: PackedStringArray = group.split(":")
		var budget: Dictionary = classes[f[0]]
		var length: float = budget["length"]
		for type: int in int(f[1]):
			var mesh: ArrayMesh = _hull_mesh(length, int(budget["triangles"]), int(budget["atlases"]), rng)
			for s: int in mesh.get_surface_count():
				mesh.surface_set_material(s, _material(int(budget["atlas_px"]), rng))
			for copy: int in int(f[2]):
				var node := MeshInstance3D.new()
				node.mesh = mesh
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
				main.world.add_child(node)
				# Big hulls far and spread wide, small ones near: the fleet fills the view, no hull hiding another whole.
				var range_m: float = clampf(length * 1.6, 60.0, 6000.0) * (0.7 + 0.6 * rng.randf())
				var across: float = 0.55 * range_m * sqrt(float(slot % 23 + 1) / 23.0)
				var at := Vector3(across * cos(golden * slot), 0.5 * across * sin(golden * slot), -range_m)
				node.global_transform = main.ship.global_transform * Transform3D(Basis.from_euler(Vector3(0.0, rng.randf_range(-0.9, 0.9), 0.0)), at)
				_nodes.append(node)
				_source_tris += int(budget["triangles"])
				slot += 1


# `spec` is `<asset id>[@<yaw rad>[@<range in lengths>]]`: how the hull is turned to the camera and how far off it stands.
func _asset(spec: String) -> void:
	var fields: PackedStringArray = spec.split("@")
	var asset_id: String = fields[0]
	var yaw: float = float(fields[1]) if fields.size() > 1 else 2.2
	var range_lengths: float = float(fields[2]) if fields.size() > 2 else 1.1
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
		_source_tris += int(pieces[piece_name]["mesh"]["triangles"])
	var length: float = float(manifest.get("dimensions_m", {}).get("length", 100.0))
	root.global_transform = main.ship.global_transform * Transform3D(Basis.from_euler(Vector3(0.25, yaw, 0.0)), Vector3(0.0, 0.0, -range_lengths * length))
	_nodes.append(root)


# --- phases -----------------------------------------------------------------------------------------------------------
func _next() -> void:
	_index += 1
	_frame = 0
	for node: Node3D in _nodes:
		node.queue_free()
	_nodes.clear()
	_texture_bytes = 0
	_source_tris = 0
	_detail = {}
	for series: PackedFloat64Array in [_frame_ms, _gpu_ms, _draws, _tris]:
		series.clear()
	if _index >= phases.size():
		print("[budget] renderer %s, gpu %s, %s" % [DebugConsole.registry.read("render.renderer")["value"],
				DebugConsole.registry.read("render.gpu")["value"], get_viewport().get_visible_rect().size])
		get_tree().quit()
		return
	var phase: PackedStringArray = phases[_index]
	get_viewport().mesh_lod_threshold = 0.0 if phase.size() > 2 and phase[2] == "full" else _lod_threshold
	if phase[0].begins_with("asset:"):
		_asset(phase[0].trim_prefix("asset:"))
	elif phase.size() > 1 and not phase[1].is_empty():
		_fleet(phase[1])
		if phase.size() > 3 and phase[3] == "close":
			# The first hull across the whole view from 50 m off its flank, the rest of the fleet behind it.
			var length: float = (_nodes[0] as MeshInstance3D).mesh.get_aabb().size.z
			_nodes[0].global_transform = main.ship.global_transform * Transform3D(Basis.from_euler(Vector3(0.0, 1.35, 0.0)),
					Vector3(0.0, 0.0, -(50.0 + 0.1 * length)))


static func _card_mb() -> float:
	var reading: VramReading = VramReading.read(0, RenderingServer.get_video_adapter_name())
	return reading.used_bytes / 1048576.0 if reading.has_total() else -1.0


static func _median(values: PackedFloat64Array) -> float:
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0


func _on_frame() -> void:
	if _index < 0 or _index >= phases.size():
		return
	_frame += 1
	var now: int = Time.get_ticks_usec()
	if _frame > int(options["settle"]):
		_frame_ms.append(float(now - _last_usec) / 1000.0)
		_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		_draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_tris.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_last_usec = now
	if _frame < int(options["settle"]) + int(options["frames"]):
		return
	var phase: PackedStringArray = phases[_index]
	var name: String = phase[0].replace(":", "_").replace("@", "_")
	var path: String = "%s/%s.png" % [options["out"], name]
	get_viewport().get_texture().get_image().save_png(path)
	var frame: float = _median(_frame_ms)
	print("[budget] %s: hulls %d, fps %.0f (frame %.2f ms), gpu %.2f ms, draw calls %.0f, triangles drawn %.0f of %d, textures built %.0f MB, renderer textures %.0f MB, renderer video %.0f MB, card %.0f MB -> %s" % [
			phase[0], _nodes.size(), 1000.0 / maxf(frame, 0.001), frame, _median(_gpu_ms), _median(_draws), _median(_tris), _source_tris,
			_texture_bytes / 1048576.0, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, _card_mb(), path])
	_next()
