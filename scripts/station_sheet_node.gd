extends Node
## Photographs the Babylon 5 station for the maintainer's look sheet (M7-T04): the game's main scene with the station at its
## place, the drum held still so the Cobra arms stay where the shots expect them, the key star turned to light the hull from over
## the camera's shoulder; one shot per view (`VIEWS`: 50 m off a Cobra bay and off the docking aperture, 200 m off a band, 1 km,
## then 10 and 100 km by `far view`). Each shot saves its frame and prints the `render` provider's numbers. Before the game loads,
## the station's two pieces are loaded alone to read what their maps take on the GPU (the card's VRAM before and after, and the
## textures' own bytes).
##
## Arguments after `--`: out=<dir> settle=<frames>. Run by scripts/station_sheet.sh on the real renderer.

const SYSFS_VRAM: String = "/sys/class/drm/card1/device/mem_info_vram_used"
## Each view: a name, then the camera and its aim in the station frame of docs/assets-station.md (z aft from the bow tip, x to
## starboard, y up) and the field of view; or a `far` distance in km for `far view station`.
## A view with `glint` [point, normal] in the station frame turns the key star so its mirror image off that surface meets the camera:
## the sun's specular highlight across the plating (metal, not plastic).
const VIEWS: Array[Dictionary] = [
	{"name": "bay_50m", "at": Vector3(300.0, -55.0, 1085.0), "aim": Vector3(243.0, 0.0, 1150.0), "fov": 62.0},
	{"name": "bay_glint_50m", "at": Vector3(292.0, 22.0, 1110.0), "aim": Vector3(243.0, 0.0, 1150.0), "fov": 62.0,
			"glint": [Vector3(243.0, 0.0, 1170.0), Vector3(1.0, 0.0, 0.0)]},
	{"name": "bay_head_60m", "at": Vector3(345.0, 45.0, 615.0), "aim": Vector3(300.0, 0.0, 720.0), "fov": 62.0},
	{"name": "bay_doors_50m", "at": Vector3(287.0, 16.0, 1118.0), "aim": Vector3(239.0, 0.0, 1160.0), "fov": 62.0},
	{"name": "aperture_50m", "at": Vector3(40.0, -45.0, 420.0), "aim": Vector3(0.0, 0.0, 495.0), "fov": 62.0},
	{"name": "aperture_150m", "at": Vector3(150.0, -110.0, 340.0), "aim": Vector3(0.0, 0.0, 500.0), "fov": 60.0},
	{"name": "band_200m", "at": Vector3(560.0, -300.0, 1860.0), "aim": Vector3(0.0, 0.0, 2150.0), "fov": 60.0},
	{"name": "band_glint_50m", "at": Vector3(395.0, 240.0, 1990.0), "aim": Vector3(361.0, 208.0, 2040.0), "fov": 62.0,
			"glint": [Vector3(361.0, 208.0, 2060.0), Vector3(0.866, 0.5, 0.0)]},
	{"name": "grazing_1km", "at": Vector3(760.0, 330.0, 600.0), "aim": Vector3(0.0, 120.0, 3200.0), "fov": 50.0,
			"glint": [Vector3(295.0, 295.0, 2600.0), Vector3(0.707, 0.707, 0.0)]},
	{"name": "1km", "at": Vector3(700.0, 380.0, 700.0), "aim": Vector3(0.0, 0.0, 1500.0), "fov": 55.0},
	{"name": "10km", "far": 10.0},
	{"name": "100km", "far": 100.0},
]
## M7-T19's sets (`views=<set>`): `t19` the cost views (from a Cobra bay, the aperture, 1 km, 10 km, 1 000 km), `fly` a pass along
## the station's underside about 200 m off the hull from the bow to the reactor (section joins and levels of detail), `doors` the
## Cobra-bay doors close up (the near-only props). The default set is T04's look sheet.
const VIEW_SETS: Dictionary = {
	"t19": [
		{"name": "bay_50m", "at": Vector3(300.0, -55.0, 1085.0), "aim": Vector3(243.0, 0.0, 1150.0), "fov": 62.0},
		{"name": "aperture_50m", "at": Vector3(40.0, -45.0, 420.0), "aim": Vector3(0.0, 0.0, 495.0), "fov": 62.0},
		{"name": "1km", "at": Vector3(700.0, 380.0, 700.0), "aim": Vector3(0.0, 0.0, 1500.0), "fov": 55.0},
		{"name": "10km", "far": 10.0},
		{"name": "1000km", "far": 1000.0},
	],
	"doors": [
		{"name": "bay_doors_50m", "at": Vector3(287.0, 16.0, 1118.0), "aim": Vector3(239.0, 0.0, 1160.0), "fov": 62.0},
		{"name": "bay_doors_20m", "at": Vector3(262.0, 4.0, 1140.0), "aim": Vector3(239.0, 0.0, 1160.0), "fov": 62.0},
		{"name": "bay_doors_300m", "at": Vector3(520.0, -120.0, 1000.0), "aim": Vector3(243.0, 0.0, 1150.0), "fov": 50.0},
	],
	"fly": [
		{"name": "fly_01_bow", "at": Vector3(60.0, -540.0, 200.0), "aim": Vector3(0.0, 0.0, 900.0), "fov": 62.0},
		{"name": "fly_02_sphere", "at": Vector3(60.0, -560.0, 800.0), "aim": Vector3(0.0, 0.0, 1500.0), "fov": 62.0},
		{"name": "fly_03_waist", "at": Vector3(60.0, -540.0, 1300.0), "aim": Vector3(0.0, 0.0, 2000.0), "fov": 62.0},
		{"name": "fly_04_ring", "at": Vector3(60.0, -620.0, 1750.0), "aim": Vector3(0.0, 0.0, 2500.0), "fov": 62.0},
		{"name": "fly_05_green", "at": Vector3(60.0, -540.0, 2600.0), "aim": Vector3(0.0, 0.0, 3300.0), "fov": 62.0},
		{"name": "fly_06_green", "at": Vector3(60.0, -545.0, 3500.0), "aim": Vector3(0.0, 0.0, 4200.0), "fov": 62.0},
		{"name": "fly_07_green", "at": Vector3(60.0, -540.0, 4300.0), "aim": Vector3(0.0, 0.0, 5000.0), "fov": 62.0},
		{"name": "fly_08_aft_band", "at": Vector3(60.0, -620.0, 5000.0), "aim": Vector3(0.0, 0.0, 5700.0), "fov": 62.0},
		{"name": "fly_09_hub", "at": Vector3(60.0, -550.0, 5650.0), "aim": Vector3(0.0, 0.0, 6350.0), "fov": 62.0},
		{"name": "fly_10_truss", "at": Vector3(60.0, -320.0, 6500.0), "aim": Vector3(0.0, 0.0, 7200.0), "fov": 62.0},
		{"name": "fly_11_shaft", "at": Vector3(60.0, -330.0, 7250.0), "aim": Vector3(0.0, 0.0, 7900.0), "fov": 62.0},
		{"name": "fly_12_reactor", "at": Vector3(60.0, -380.0, 7800.0), "aim": Vector3(0.0, 0.0, 8100.0), "fov": 62.0},
	],
}
const LIT_LIGHT: Vector3 = Vector3(0.3, -0.35, -1.0)  # camera frame: over the camera's left shoulder, as the look sheets

var main: Main
var options: Dictionary = {"out": "user://", "settle": "90", "views": ""}
var _views: Array = VIEWS
var _index: int = -1
var _frame: int = 0
var _station: StationStandin = null
var _origin_z: float = 4000.0
var _timed_us: int = 0  # when the timed frames of this shot began
const TIMED_FRAMES: int = 60  # the last frames before each capture, timed for a steady frame rate


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = arg.split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	_views = VIEW_SETS.get(String(options["views"]), VIEWS)
	await _measure_maps()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.waves_auto_start = false
	main.input_source = FakeInputSource.new()
	get_tree().root.add_child.call_deferred(main)
	get_tree().set_deferred(&"current_scene", main)
	main.ready.connect(_start.call_deferred, CONNECT_ONE_SHOT)


# What the station's maps take: the card's VRAM before and after the two pieces load (textures upload on load), and the bytes of
# every map as imported (compressed, with mipmaps).
func _measure_maps() -> void:
	var before: int = _vram_bytes()
	var manifest: Dictionary = MeshAssets.read_manifest(StationStandin.ASSET_ID)
	var dir: String = ShipSpec.ASSET_ROOT.path_join(StationStandin.ASSET_ID)
	var held: Array[Mesh] = []
	var bytes: int = 0
	var seen: Dictionary = {}
	for piece: String in ["drum", "frame"]:
		var entry: Dictionary = (manifest.get("pieces", {}) as Dictionary).get(piece, {})
		held.append(MeshAssets.load_textured(dir, entry.get("mesh", {})))
		for surface: Dictionary in (entry.get("mesh", {}) as Dictionary).get("surfaces", []):
			var files: Array = [surface.get("albedo"), surface.get("normal"), surface.get("orm"), surface.get("emissive")]
			var detail: Dictionary = surface.get("world_detail", {})
			files += [detail.get("albedo"), detail.get("normal")]
			for file: Variant in files:
				if file == null or seen.has(file):
					continue
				seen[file] = true
				var texture: Texture2D = load(dir.path_join(String(file))) as Texture2D
				if texture != null:
					var image: Image = texture.get_image()
					bytes += image.get_data().size()
					print("[station_sheet] map %s: %dx%d format %d mipmaps %s, %.1f MB" % [file, image.get_width(), image.get_height(),
							image.get_format(), image.has_mipmaps(), image.get_data().size() / 1048576.0])
	await get_tree().process_frame
	await get_tree().process_frame
	var after: int = _vram_bytes()
	print("[station_sheet] maps %.1f MB as imported; card VRAM %.1f -> %.1f MB (+%.1f MB) loading both pieces" % [bytes / 1048576.0,
			before / 1048576.0, after / 1048576.0, (after - before) / 1048576.0])
	held.clear()


func _vram_bytes() -> int:
	var file: FileAccess = FileAccess.open(SYSFS_VRAM, FileAccess.READ)
	return int(file.get_line().strip_edges()) if file != null else -1  # sysfs gives no length, so a line, not the whole text


func _start() -> void:
	for line: String in ["god on", "wave stop", "despawn all", "flare off", "fps off"]:
		_run(line)
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	if main.overlay != null:
		main.overlay.visible = false
	main.ship.visible = false
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if main.far_props.station == null:
		_run("far station")
	_station = main.far_props.station
	if _station == null:
		print("[station_sheet] the station is not generated")
		get_tree().quit(1)
		return
	_origin_z = float((MeshAssets.read_manifest(StationStandin.ASSET_ID).get("centroid_offset", [0.0, 0.0, 4000.0]) as Array)[2])
	_station.set_process(false)  # the arms stay where the shots expect them
	_station.drum_pivot.basis = Basis.IDENTITY
	if main.space_environment != null:
		main.space_environment.hold_key_star(true)
	get_tree().process_frame.connect(_on_frame)
	_next()


func _run(line: String) -> void:
	for result: ConsoleResult in DebugConsole.registry.execute(line):
		if not result.ok:
			print("[station_sheet] console error on '%s': %s" % [line, "; ".join(result.lines)])


# The station frame's point as an offset in the station node's own frame (the asset's origin sits `_origin_z` aft of the bow).
func _local(p: Vector3) -> Array[float]:
	return [p.x, p.y, p.z - _origin_z]


func _next() -> void:
	_index += 1
	_frame = 0
	if _index >= _views.size():
		get_tree().quit(0)
		return
	var view: Dictionary = _views[_index]
	if view.has("far"):
		_run("far view station %s" % view["far"])
		return
	var key: Dictionary = {"position": {"actor": "station", "offset": _local(view["at"])},
			"look_at": {"actor": "station", "offset": _local(view["aim"])}, "fov": view["fov"]}
	var made: Dictionary = CinematicShot.from_dict(StringName(view["name"]), {"keys": [key.merged({"t": 0.0}), key.merged({"t": 3600.0})]})
	main.camera_rig.play_shot(made["shot"], _pose, _origin_to_local)


func _pose(actor: String) -> Variant:
	return _station.global_transform if actor == "station" and is_instance_valid(_station) else null


func _origin_to_local(offset: PackedFloat64Array) -> Vector3:
	return main.world.universe_to_local(UniversePos.new(offset[0], offset[1], offset[2], main.world.origin.system_id))


func _light_from_camera() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var star: DirectionalLight3D = main.space_environment.key_star if main.space_environment != null else null
	if camera == null or star == null:
		return
	var direction: Vector3 = (camera.global_basis * LIT_LIGHT).normalized()
	var view: Dictionary = _views[_index]
	if view.has("glint"):
		# Light that leaves the surface toward the camera: the mirror of the camera's direction about the surface's normal.
		var glint: Array = view["glint"]
		var at: Vector3 = glint[0]
		var point: Vector3 = _station.to_global(Vector3(at.x, at.y, at.z - _origin_z))
		var normal: Vector3 = (_station.global_basis * (glint[1] as Vector3)).normalized()
		var to_camera: Vector3 = (camera.global_position - point).normalized()
		direction = -(2.0 * normal.dot(to_camera) * normal - to_camera).normalized()
	var up: Vector3 = camera.global_basis.y if absf(direction.dot(camera.global_basis.y)) < 0.99 else camera.global_basis.x
	star.global_transform = Transform3D(Basis.looking_at(direction, up), star.global_position)


func _on_frame() -> void:
	if _index < 0 or _index >= _views.size():
		return
	_light_from_camera()
	_frame += 1
	if _frame == int(options["settle"]) - TIMED_FRAMES:
		_timed_us = Time.get_ticks_usec()
	if _frame < int(options["settle"]):
		return
	var steady_fps: float = TIMED_FRAMES / maxf((Time.get_ticks_usec() - _timed_us) / 1e6, 1e-6)
	var name: String = String(_views[_index]["name"])
	var camera: Camera3D = get_viewport().get_camera_3d()
	print("[station_sheet] %s: camera %s at %s, station at %s" % [name, camera.get_path() if camera != null else "none",
			camera.global_position if camera != null else Vector3.ZERO, _station.global_position])
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/station_%s.png" % [options["out"], name]
	image.save_png(path)
	var stats: Array[String] = []
	for key: String in ["renderer", "fps", "draw_calls", "triangles", "vram_mb", "gpu_ms"]:
		stats.append("%s=%s" % [key, str(DebugConsole.registry.read("render.%s" % key).get("value", "?"))])
	print("[station_sheet] %s: %s steady_fps=%.0f card_vram_mb=%.0f station_meshes_shown=%d -> %s" % [name, " ".join(stats), steady_fps,
			_vram_bytes() / 1048576.0, _shown(_station), path])
	_next()


# The station's meshes drawn now (sections, props, the dot), for the cost readout.
func _shown(node: Node) -> int:
	var count: int = 1 if node is GeometryInstance3D and (node as GeometryInstance3D).is_visible_in_tree() else 0
	for child: Node in node.get_children():
		count += _shown(child)
	return count
