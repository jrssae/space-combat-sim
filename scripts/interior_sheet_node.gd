extends Node
## Photographs the Cobra-bay interior behind the menu for the maintainer's look sheet (M7-T09): the front end on the real renderer,
## three moments of the slow camera move with the menu up, then a wide and a close view of the racks, one more moment of the move
## and one door's full rack, without it. Each frame is saved and prints the `render` provider's numbers, a steady frame rate and the card's VRAM. Then
## one sheet: the frames, a strip of the maintainer's Cobra-bay interior references (inspiration only; the sheet is gitignored)
## and the paints' swatches with their metallic and roughness.
##
## Arguments after `--`: out=<dir> settle=<frames>. Run by scripts/interior_sheet.sh.

const SYSFS_VRAM: String = "/sys/class/drm/card1/device/mem_info_vram_used"
const FRONT_END: String = "res://src/frontend/front_end.tscn"
const TIMED_FRAMES: int = 60
## Each shot: a name, the backdrop's view and the move's time, and whether the menu is up.
const SHOTS: Array[Dictionary] = [
	{"name": "menu_t000", "view": "move", "time": 0.0, "menu": true, "label": "Menu, move at 0 s (head end)"},
	{"name": "menu_t060", "view": "move", "time": 60.0, "menu": true, "label": "Menu, move at 60 s"},
	{"name": "menu_t120", "view": "move", "time": 120.0, "menu": true, "label": "Menu, move at 120 s (root end)"},
	{"name": "racks_wide", "view": "wide", "time": -1.0, "menu": false, "label": "Racks, wide (no menu)"},
	{"name": "racks_close", "view": "close", "time": -1.0, "menu": false, "label": "Rack 4, close (no menu)"},
	{"name": "racks_t030", "view": "move", "time": 30.0, "menu": false, "label": "Move at 30 s (no menu)"},
	{"name": "rack_full", "view": "rack", "time": -1.0, "menu": false, "label": "Door 4's full rack, close (no menu)"},
]
const REFERENCES: Array[Dictionary] = [
	{"file": "references/cobra bay interior references/1 SHOW cobra bay interior (most weight).webp", "label": "1 Show capture (most weight)"},
	{"file": "references/cobra bay interior references/2 fan render numbered bays and ceiling clamps (suggestion).jpg",
			"label": "2 Fan render (suggestion)"},
	{"file": "references/cobra bay interior references/3 fan diorama starfury on launch cradle (suggestion).jpg",
			"label": "3 Fan diorama (suggestion)"},
]
const SHEET_SIZE: Vector2i = Vector2i(2400, 2140)

var options: Dictionary = {"out": "", "settle": "120"}
var _front: FrontEnd = null
var _index: int = -1
var _frame: int = 0
var _timed_us: int = 0
var _frames: Array[Image] = []
var _stats: Array[String] = []
var _load_line: String = ""


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=", true, 1)
		if parts.size() == 2:
			options[parts[0]] = parts[1]
	add_child(RenderStatus.new())
	var before: int = _vram_bytes()
	_front = (load(FRONT_END) as PackedScene).instantiate() as FrontEnd
	_front.quit_game = func() -> void: pass
	get_tree().root.add_child.call_deferred(_front)
	await get_tree().process_frame
	await get_tree().process_frame
	_load_line = "front end with the hangar: card VRAM %.0f -> %.0f MB (+%.0f MB); backdrop loaded=%s fighters=%d lamps=%d" % [
			before / 1048576.0, _vram_bytes() / 1048576.0, (_vram_bytes() - before) / 1048576.0, _front.backdrop().is_loaded(),
			_front.backdrop().fighters().size(), _front.backdrop().emitters().size()]
	print("[interior_sheet] ", _load_line)
	get_tree().process_frame.connect(_on_frame)
	_next()


func _vram_bytes() -> int:
	var file: FileAccess = FileAccess.open(SYSFS_VRAM, FileAccess.READ)
	return int(file.get_line().strip_edges()) if file != null else -1


func _next() -> void:
	_index += 1
	_frame = 0
	if _index >= SHOTS.size():
		await _compose()
		get_tree().quit()
		return
	var shot: Dictionary = SHOTS[_index]
	_front.frame().visible = bool(shot["menu"])
	_aim(shot)


func _aim(shot: Dictionary) -> void:
	_front.backdrop().show_view(StringName(shot["view"]), float(shot["time"]))


func _on_frame() -> void:
	if _index < 0 or _index >= SHOTS.size():
		return
	_frame += 1
	var settle: int = int(options["settle"])
	if _frame == settle - TIMED_FRAMES:
		_timed_us = Time.get_ticks_usec()
	if _frame == settle - 2:
		_aim(SHOTS[_index])  # back to the shot's moment, so the move's settling does not shift it
	if _frame < settle:
		return
	var steady_fps: float = TIMED_FRAMES / maxf((Time.get_ticks_usec() - _timed_us) / 1e6, 1e-6)
	var shot: Dictionary = SHOTS[_index]
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("%s/frame_%s.png" % [options["out"], shot["name"]])
	_frames.append(image)
	var stats: Array[String] = []
	for key: String in ["renderer", "fps", "draw_calls", "triangles", "vram_mb"]:
		stats.append("%s=%s" % [key, str(DebugConsole.registry.read("render.%s" % key).get("value", "?"))])
	var line: String = "%s: %s steady_fps=%.0f card_vram_mb=%.0f" % [shot["name"], " ".join(stats), steady_fps, _vram_bytes() / 1048576.0]
	_stats.append(line)
	print("[interior_sheet] ", line)
	_next()


# The sheet: the frames in two rows, the references and the swatches under them, drawn in a viewport of its own and saved.
func _compose() -> void:
	var viewport := SubViewport.new()
	viewport.size = SHEET_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	add_child(viewport)
	var page := ColorRect.new()
	page.color = Color(0.08, 0.08, 0.09)
	page.size = Vector2(SHEET_SIZE)
	viewport.add_child(page)
	_label(page, "M7-T09 Cobra-bay interior (b5_interior): look sheet, phase 1", Vector2(24, 12), 30)
	var frame_size := Vector2(768, 432)
	for i: int in _frames.size():
		var at := Vector2(24 + (i % 3) * (frame_size.x + 24), 64 + (i / 3) * (frame_size.y + 56))
		_picture(page, _frames[i], at, frame_size)
		_label(page, String(SHOTS[i]["label"]), at + Vector2(0, frame_size.y + 4), 18)
	var y: float = 64 + ceili(_frames.size() / 3.0) * (frame_size.y + 56) + 8
	_label(page, "References (gitignored; inspiration only):", Vector2(24, y), 20)
	var x: float = 24.0
	for ref: Dictionary in REFERENCES:
		var image := Image.load_from_file(ProjectSettings.globalize_path("res://" + String(ref["file"])))
		if image == null or image.is_empty():
			continue
		var h: float = 300.0
		var w: float = h * image.get_width() / image.get_height()
		_picture(page, image, Vector2(x, y + 30), Vector2(w, h))
		_label(page, String(ref["label"]), Vector2(x, y + 334), 16)
		x += w + 24
	_swatches(page, Vector2(x + 16, y), Vector2(SHEET_SIZE.x - x - 40, 360))
	var stats_y: float = SHEET_SIZE.y - 150.0
	_label(page, _load_line, Vector2(24, stats_y), 14)
	for i: int in _stats.size():
		_label(page, _stats[i], Vector2(24, stats_y + 20 + i * 19), 14)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var sheet: Image = viewport.get_texture().get_image()
	var path: String = "%s/M7-T09_interior_look_sheet.png" % options["out"]
	sheet.save_png(path)
	print("[interior_sheet] sheet -> ", path)


func _swatches(page: Control, at: Vector2, size: Vector2) -> void:
	var manifest: Dictionary = MeshAssets.read_manifest(HangarBackdrop.ASSET_ID)
	var materials: Dictionary = manifest.get("materials", {})
	_label(page, "Paints (capture colour, metallic, roughness) and glows (colour, strength):", at, 20)
	var cols: int = 3
	var cell := Vector2(size.x / cols, 62)
	var i: int = 0
	for role: String in materials:
		var m: Dictionary = materials[role]
		var pos: Vector2 = at + Vector2((i % cols) * cell.x, 34 + (i / cols) * cell.y)
		var chip := ColorRect.new()
		var text: String = ""
		if m.has("capture_srgb"):
			chip.color = Color.html(String(m["capture_srgb"]))
			text = "%s %s\nmetal %.2f rough %.2f" % [role, m["capture_srgb"], float(m["metallic"]), float(m["roughness"])]
		else:
			var c: Array = m["emissive_srgb"]
			chip.color = Color(float(c[0]), float(c[1]), float(c[2]))
			text = "%s (glow)\nstrength %.1f" % [role, float(m["strength"])]
		chip.position = pos
		chip.size = Vector2(48, 48)
		page.add_child(chip)
		_label(page, text, pos + Vector2(56, 0), 14)
		i += 1


func _picture(page: Control, image: Image, at: Vector2, size: Vector2) -> void:
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(image)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.position = at
	rect.size = size
	page.add_child(rect)


func _label(page: Control, text: String, at: Vector2, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", Color(0.9, 0.9, 0.88))
	page.add_child(label)
