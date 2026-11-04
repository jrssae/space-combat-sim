extends Node
## Photographs one ship for the maintainer's look sheet (M4-T30a, checkpoint 1b): the game's main scene, the player alone and
## hidden, the `sheet` command parking the ship ahead of the chase camera at each distance, lit from behind the camera and from
## behind the ship, drawn as splats, as T27's painted mesh and as the textured mesh, each shot held for a few frames and saved;
## then the cockpit view; then one sheet of every shot side by side with its GPU time. Run by scripts/look_sheet.sh on the real
## renderer, fullscreen with the 3D at 1 080 lines.
##
## Arguments after `--`: asset=<id> out=<dir> distances=<m,m,...> looks=<splat,painted,textured> lights=<lit,dark>
## settle=<frames> tile=<width> scale3d=<1080p|factor>
##
## With `liveries=<wing:number,...>` (M4-T30b, checkpoint 1c) the columns are the textured mesh in each wing's livery instead of the
## looks, plus one column of earlier shots read from disk (`compare=<path pattern with %d for metres and %s for lit or dark>`,
## headed `compare_label`), and the cockpit view is taken lit and dark; `prefix` names the shots and `sheet` the sheet's path.

const DEFAULT_LOOKS: Array[String] = ["splat", "painted", "textured"]
const LABEL_H: int = 28

var main: Main
var options: Dictionary = {"asset": "starfury_aurora", "out": "/tmp", "distances": "8,30,150,600", "looks": "splat,painted,textured",
		"lights": "lit,dark", "settle": "40", "tile": "960", "scale3d": "1080p", "liveries": "", "compare": "", "compare_label": "T30A",
		"prefix": "m4_t30a", "sheet": ""}
var shots: Array[Dictionary] = []  # queued: {distance, light, look} or {cockpit: true}
var _index: int = -1
var _frame: int = 0
var _tiles: Dictionary = {}  # key -> Image (the tile) and its gpu ms
var _gpu: Dictionary = {}
var _vram: Dictionary = {}
var _font: Dictionary = {}


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = arg.split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.waves_auto_start = false
	main.input_source = FakeInputSource.new()
	var tree: SceneTree = get_tree()
	tree.root.add_child.call_deferred(main)
	tree.set_deferred(&"current_scene", main)
	main.ready.connect(_start.call_deferred, CONNECT_ONE_SHOT)


func _start() -> void:
	for line: String in ["god on", "wave stop", "despawn all", "camera chase", "flare off", "fps off"]:
		_run(line)
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false  # the pictures are of the ship, not the HUD
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var liveries: String = String(options["liveries"])
	for light: String in String(options["lights"]).split(","):
		for distance: String in String(options["distances"]).split(","):
			if liveries.is_empty():
				for look: String in String(options["looks"]).split(","):
					shots.append({"distance": float(distance), "light": light, "look": look})
			else:
				for livery: String in liveries.split(","):
					shots.append({"distance": float(distance), "light": light, "look": "textured", "livery": livery})
	if liveries.is_empty():
		shots.append({"cockpit": true})
	else:
		for light: String in String(options["lights"]).split(","):
			shots.append({"cockpit": true, "light": light})
	get_tree().process_frame.connect(_on_frame)
	_next()


func _run(line: String) -> void:
	for result: ConsoleResult in DebugConsole.registry.execute(line):
		if not result.ok:
			print("[sheet] console error on '%s': %s" % [line, "; ".join(result.lines)])


func _key(shot: Dictionary) -> String:
	if shot.has("cockpit"):
		return "cockpit_%s" % shot["light"] if shot.has("light") else "cockpit"
	if shot.has("livery"):
		return "%s_%dm_%s" % [String(shot["livery"]).split(":")[0], int(shot["distance"]), shot["light"]]
	return "%s_%dm_%s" % [shot["look"], int(shot["distance"]), shot["light"]]


func _next() -> void:
	_index += 1
	_frame = 0
	if _index >= shots.size():
		_finish()
		return
	var shot: Dictionary = shots[_index]
	if shot.has("cockpit"):
		_run("sheet off")
		_run("set settings.ship_render mesh")
		_run("camera cockpit")
		var look_scene := main.get_node_or_null(^"LookScene") as LookScene
		if shot.has("light") and look_scene != null and look_scene.key_star != null:
			look_scene.set_light(StringName(shot["light"]))
	else:
		_run("sheet %s %d %s %s %s" % [options["asset"], int(shot["distance"]), shot["light"], shot["look"], shot.get("livery", "")])


func _on_frame() -> void:
	_hold_3d_scale()
	if _index < 0 or _index >= shots.size():
		return
	_frame += 1
	if _frame < int(options["settle"]):
		return
	var shot: Dictionary = shots[_index]
	var key: String = _key(shot)
	var image: Image = get_viewport().get_texture().get_image()
	var gpu: float = float(DebugConsole.registry.read("render.gpu_ms")["value"])
	var vram: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	_gpu[key] = gpu
	_vram[key] = vram
	var path: String = "%s/%s_%s_%s.png" % [options["out"], options["prefix"], options["asset"], key]
	image.save_png(path)
	print("[sheet] %s: gpu ms %.2f, video memory %.0f MB, %dx%d -> %s" % [key, gpu, vram, image.get_width(), image.get_height(), path])
	var tile_w: int = int(options["tile"])
	var tile_h: int = int(float(tile_w) * float(image.get_height()) / float(image.get_width()))
	image.resize(tile_w, tile_h, Image.INTERPOLATE_LANCZOS)
	_tiles[key] = image
	_next()


func _hold_3d_scale() -> void:
	var wanted: String = String(options["scale3d"])
	if wanted.is_empty():
		return
	var root: Window = get_tree().root
	var scale: float = minf(1.0, 1080.0 / float(maxi(root.size.y, 1))) if wanted == "1080p" else float(wanted)
	if scale > 0.0 and not is_equal_approx(root.scaling_3d_scale, scale):
		root.scaling_3d_scale = scale


# One sheet: a column per look (or per livery, plus the earlier shots), a row per light and distance, the cockpit view last; each
# tile labelled with its GPU time.
func _finish() -> void:
	var looks: PackedStringArray = String(options["looks"]).split(",")
	if not String(options["liveries"]).is_empty():
		_finish_liveries()
		return
	var lights: PackedStringArray = String(options["lights"]).split(",")
	var distances: PackedStringArray = String(options["distances"]).split(",")
	var tile_w: int = int(options["tile"])
	var first: Image = _tiles.values()[0] if not _tiles.is_empty() else null
	if first == null:
		print("[sheet] nothing captured")
		get_tree().quit(1)
		return
	var tile_h: int = first.get_height()
	var rows: int = lights.size() * distances.size() + 1
	var sheet: Image = Image.create(looks.size() * tile_w, rows * (tile_h + LABEL_H) + LABEL_H, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.08, 0.08, 0.09))
	for c: int in looks.size():
		_label(sheet, c * tile_w + 8, 6, looks[c].to_upper())
	var row: int = 0
	for light: String in lights:
		for distance: String in distances:
			for c: int in looks.size():
				var key: String = "%s_%dm_%s" % [looks[c], int(distance), light]
				var x: int = c * tile_w
				var y: int = LABEL_H + row * (tile_h + LABEL_H)
				if _tiles.has(key):
					sheet.blit_rect(_tiles[key], Rect2i(0, 0, tile_w, tile_h), Vector2i(x, y))
					_label(sheet, x + 8, y + tile_h + 6, "%s M %s GPU %.2f MS" % [distance, light.to_upper(), _gpu[key]])
			row += 1
	if _tiles.has("cockpit"):
		var x: int = ((looks.size() - 1) / 2) * tile_w
		var y: int = LABEL_H + row * (tile_h + LABEL_H)
		sheet.blit_rect(_tiles["cockpit"], Rect2i(0, 0, tile_w, tile_h), Vector2i(x, y))
		_label(sheet, x + 8, y + tile_h + 6, "COCKPIT VIEW GPU %.2f MS" % _gpu["cockpit"])
	var path: String = "%s/m4_t30_%s_sheet.png" % [options["out"], options["asset"]]
	sheet.save_png(path)
	print("[sheet] sheet %dx%d -> %s" % [sheet.get_width(), sheet.get_height(), path])
	get_tree().quit(0)


# The livery sheet (checkpoint 1c): a column per wing, then the earlier shots from disk; the cockpit lit and dark last.
func _finish_liveries() -> void:
	var wings: Array[String] = []
	for livery: String in String(options["liveries"]).split(","):
		wings.append(livery.split(":")[0])
	var compare: String = String(options["compare"])
	var columns: Array[String] = wings.duplicate()
	if not compare.is_empty():
		columns.append("compare")
	var lights: PackedStringArray = String(options["lights"]).split(",")
	var distances: PackedStringArray = String(options["distances"]).split(",")
	var tile_w: int = int(options["tile"])
	var tile_h: int = (_tiles.values()[0] as Image).get_height()
	var rows: int = lights.size() * distances.size() + 1
	var sheet: Image = Image.create(columns.size() * tile_w, rows * (tile_h + LABEL_H) + LABEL_H, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.08, 0.08, 0.09))
	for c: int in columns.size():
		_label(sheet, c * tile_w + 8, 6, String(options["compare_label"]) if columns[c] == "compare" else columns[c].to_upper())
	var row: int = 0
	for light: String in lights:
		for distance: String in distances:
			var y: int = LABEL_H + row * (tile_h + LABEL_H)
			for c: int in columns.size():
				var x: int = c * tile_w
				var tile: Image = null
				var label: String = "%s M %s" % [distance, light.to_upper()]
				if columns[c] == "compare":
					var path: String = compare % [int(distance), light]
					tile = Image.load_from_file(path) if FileAccess.file_exists(path) else null
					if tile != null:
						tile.resize(tile_w, tile_h, Image.INTERPOLATE_LANCZOS)
				else:
					var key: String = "%s_%dm_%s" % [columns[c], int(distance), light]
					tile = _tiles.get(key)
					label += " GPU %.2f MS" % float(_gpu.get(key, 0.0))
				if tile != null:
					sheet.blit_rect(tile, Rect2i(0, 0, tile_w, tile_h), Vector2i(x, y))
				_label(sheet, x + 8, y + tile_h + 6, label)
			row += 1
	var y0: int = LABEL_H + row * (tile_h + LABEL_H)
	var k: int = 0
	for light: String in lights:
		var key: String = "cockpit_%s" % light
		if _tiles.has(key):
			sheet.blit_rect(_tiles[key], Rect2i(0, 0, tile_w, tile_h), Vector2i(k * tile_w, y0))
			_label(sheet, k * tile_w + 8, y0 + tile_h + 6, "COCKPIT %s GPU %.2f MS" % [light.to_upper(), _gpu[key]])
		k += 1
	var path: String = String(options["sheet"])
	if path.is_empty():
		path = "%s/%s_%s_sheet.png" % [options["out"], options["prefix"], options["asset"]]
	sheet.save_png(path)
	print("[sheet] sheet %dx%d -> %s" % [sheet.get_width(), sheet.get_height(), path])
	get_tree().quit(0)


# A 5 by 7 bitmap font, 3 px per dot, for the labels: digits, the letters the labels use, space, point.
func _label(image: Image, x: int, y: int, text: String) -> void:
	if _font.is_empty():
		_font = {
			"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"], "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
			"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"], "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
			"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"], "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
			"6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"], "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
			"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"], "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
			"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"], "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
			"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"], "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
			"G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"], "I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
			"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"], "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
			"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"], "N": ["10001", "10001", "11001", "10101", "10011", "10001", "10001"],
			"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"], "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
			"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"], "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
			"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"], "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
			"V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"], "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
			"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"], ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
			" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
			"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"], "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
			"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"], "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
			"Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"], "J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
			"Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
		}
	var dot: int = 3
	var cursor: int = x
	for ch: String in text:
		var glyph: Array = _font.get(ch, _font[" "])
		for r: int in 7:
			var bits: String = glyph[r]
			for c: int in 5:
				if bits[c] == "1":
					image.fill_rect(Rect2i(cursor + c * dot, y + r * dot, dot, dot), Color.WHITE)
		cursor += 6 * dot
