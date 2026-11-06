extends "res://scripts/look_sheet_node.gd"
## The livery concept sheet (M4-T30b, the concept stop): the textured Starfury in each wing's livery from above, below and the side,
## through the game's own renderer, material and lights, then the canopy at 8 m and the cockpit view, lit and dark (Q36). One sheet:
## a row per livery, the canopy and cockpit row last. Run by scripts/livery_concepts.sh on the real renderer.
##
## Arguments after `--`: out=<png> liveries=<wing:number,...> settle=<frames> tile=<width>

const VIEWS: Array[String] = ["top", "bottom", "side"]
const ORTHO_TOP_M: float = 11.5
const ORTHO_SIDE_M: float = 8.5
const CAMERA_DISTANCE_M: float = 40.0

var _queue: Array[Dictionary] = []
var _stage: Node3D = null
var _hull: MeshInstance3D = null
var _camera: Camera3D = null
var _section: Dictionary = {}
var _order: Array[String] = []


func _ready() -> void:
	options = {"out": "/tmp/m4_t30b_livery_concepts.png", "liveries": "alpha:2,beta:3,delta:7,zeta:1,kilo:4", "settle": "12",
			"tile": "640", "scale3d": ""}
	super._ready()


func _start() -> void:
	for line: String in ["god on", "wave stop", "despawn all", "camera chase", "flare off", "fps off"]:
		_run(line)
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	main.overlay.visible = false
	_section = MeshAssets.livery_section("starfury_aurora")
	_stage = Node3D.new()
	main.world.add_child(_stage)
	_stage.global_position = main.ship.global_position + Vector3(0.0, 400.0, 0.0)
	_hull = MeshInstance3D.new()
	_hull.mesh = MeshAssets.for_asset("starfury_aurora")
	_stage.add_child(_hull)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.far = 200.0
	_stage.add_child(_camera)
	for spec: String in String(options["liveries"]).split(","):
		var pair: PackedStringArray = spec.split(":")
		for view: String in VIEWS:
			_queue.append({"wing": pair[0], "number": int(pair[1]) if pair.size() > 1 else 0, "view": view})
	for light: String in ["lit", "dark"]:
		_queue.append({"canopy": light, "wing": "alpha", "number": 1})
	for light: String in ["lit", "dark"]:
		_queue.append({"cockpit": light})
	get_tree().process_frame.connect(_on_frame)
	_index = -1
	_next()


func _key(shot: Dictionary) -> String:
	if shot.has("cockpit"):
		return "cockpit_%s" % shot["cockpit"]
	if shot.has("canopy"):
		return "canopy_%s" % shot["canopy"]
	return "%s_%s" % [shot["wing"], shot["view"]]


func _next() -> void:
	_index += 1
	_frame = 0
	if _index >= _queue.size():
		_finish()
		return
	shots = _queue
	var shot: Dictionary = _queue[_index]
	if shot.has("cockpit"):
		_stage.visible = false
		main.ship.visible = true
		_run("camera cockpit")
		main.camera_rig.active_camera().make_current()
		_light_from(main.camera_rig.active_camera(), shot["cockpit"] == "lit")
		return
	var livery: Livery = Livery.for_wing(shot["wing"], shot["number"], _section)
	livery.apply(_hull)
	main.ship.visible = false
	_camera.make_current()
	if shot.has("canopy"):
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = 50.0
		var target: Vector3 = _stage.global_position + Vector3(0.0, 0.4, -3.6)
		_camera.global_position = target + Vector3(3.2, 2.6, -6.8).normalized() * 8.0
		_camera.look_at(target, Vector3.UP)
		_light_from(_camera, shot["canopy"] == "lit")
		return
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var origin: Vector3 = _stage.global_position
	match String(shot["view"]):
		"top":
			_camera.size = ORTHO_TOP_M
			_camera.global_position = origin + Vector3(0.0, CAMERA_DISTANCE_M, 0.0)
			_camera.look_at(origin, Vector3(0.0, 0.0, -1.0))
		"bottom":
			_camera.size = ORTHO_TOP_M
			_camera.global_position = origin + Vector3(0.0, -CAMERA_DISTANCE_M, 0.0)
			_camera.look_at(origin, Vector3(0.0, 0.0, -1.0))
		_:
			_camera.size = ORTHO_SIDE_M
			_camera.global_position = origin + Vector3(-CAMERA_DISTANCE_M, 0.0, 0.0)
			_camera.look_at(origin, Vector3.UP)
	_light_from(_camera, true)


# The key star from over the camera's shoulder (lit) or from behind what it looks at (dark), as the look sheet's.
func _light_from(camera: Camera3D, lit: bool) -> void:
	var star: DirectionalLight3D = main.space_environment.key_star
	var direction: Vector3 = (camera.global_basis * (LookScene.LIT_LIGHT if lit else LookScene.DARK_LIGHT)).normalized()
	var up: Vector3 = camera.global_basis.y if absf(direction.dot(camera.global_basis.y)) < 0.99 else camera.global_basis.x
	star.global_transform = Transform3D(Basis.looking_at(direction, up), star.global_position)


func _on_frame() -> void:
	if _index < 0 or _index >= _queue.size():
		return
	_frame += 1
	if _frame < int(options["settle"]):
		return
	var key: String = _key(_queue[_index])
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = String(options["out"]).get_basename() + "_" + key + ".png"
	image.save_png(path)
	print("[sheet] %s -> %s" % [key, path])
	var tile_w: int = int(options["tile"])
	image.resize(tile_w, int(float(tile_w) * float(image.get_height()) / float(image.get_width())), Image.INTERPOLATE_LANCZOS)
	_tiles[key] = image
	_order.append(key)
	_next()


func _finish() -> void:
	var tile_w: int = int(options["tile"])
	var first: Image = _tiles.values()[0]
	var tile_h: int = first.get_height()
	var wings: PackedStringArray = []
	for spec: String in String(options["liveries"]).split(","):
		wings.append(spec)
	var rows: int = wings.size() + 1
	var sheet: Image = Image.create(VIEWS.size() * tile_w, rows * (tile_h + LABEL_H), false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.08, 0.08, 0.09))
	# Each tile's label sits above it.
	for r: int in wings.size():
		var pair: PackedStringArray = wings[r].split(":")
		var named: bool = (_section.get("liveries", {}) as Dictionary).has(pair[0])
		for c: int in VIEWS.size():
			var key: String = "%s_%s" % [pair[0], VIEWS[c]]
			var y: int = r * (tile_h + LABEL_H)
			_label(sheet, c * tile_w + 8, y + 4, "%s %s %s%s" % [pair[0].to_upper(), "%02d" % int(pair[1]) if pair.size() > 1 else "",
					VIEWS[c].to_upper(), "" if named else " FALLBACK"])
			if _tiles.has(key):
				sheet.blit_rect(_tiles[key], Rect2i(0, 0, tile_w, tile_h), Vector2i(c * tile_w, y + LABEL_H))
	# The last row: the canopy and the cockpit, lit and dark, four to a row.
	var small_w: int = VIEWS.size() * tile_w / 4
	var y0: int = wings.size() * (tile_h + LABEL_H)
	var extra: Array[String] = ["canopy_lit", "canopy_dark", "cockpit_lit", "cockpit_dark"]
	for k: int in extra.size():
		if not _tiles.has(extra[k]):
			continue
		var image: Image = (_tiles[extra[k]] as Image).duplicate()
		image.resize(small_w, int(float(small_w) * float(tile_h) / float(tile_w)), Image.INTERPOLATE_LANCZOS)
		_label(sheet, k * small_w + 8, y0 + 4, extra[k].replace("_", " ").to_upper())
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(k * small_w, y0 + LABEL_H))
	sheet.save_png(String(options["out"]))
	print("[sheet] concepts %dx%d -> %s" % [sheet.get_width(), sheet.get_height(), options["out"]])
	get_tree().quit(0)
