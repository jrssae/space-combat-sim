extends Node
## Photographs a capital hull for its look sheet and its surface option sheet (M12-T19): the game's main scene, the player alone
## and hidden, the `sheet` command parking the hull ahead of the chase camera for each shot, held a few frames and saved. The
## sheets are put together from the shots afterwards (`scripts/hull_sheet.sh`).
##
## Arguments after `--`: out=<dir> settle=<frames> shots=<name>|<asset[:option]>|<distance_m>|<view>|<low or high>,...
## An asset of `-` clears the sheet: a shot of the empty scene, whose video memory is the baseline.

var main: Main
var options: Dictionary = {"out": "", "settle": "50", "shots": ""}
var shots: Array[PackedStringArray] = []
var _index: int = -1
var _frame: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = arg.split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	for shot: String in String(options["shots"]).split(",", false):
		if shot.split("|").size() == 5:
			shots.append(shot.split("|"))
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.waves_auto_start = false
	main.input_source = FakeInputSource.new()
	var tree: SceneTree = get_tree()
	tree.root.add_child.call_deferred(main)
	tree.set_deferred(&"current_scene", main)
	main.ready.connect(_start.call_deferred, CONNECT_ONE_SHOT)


func _start() -> void:
	for line: String in ["god on", "wave stop", "despawn all", "camera chase", "flare off", "fps off", "scaled hide"]:
		_run(line)
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false  # the pictures are of the hull, not the HUD
	if main.overlay != null:
		main.overlay.visible = false
	for child: Node in main.world.get_children():
		if child is Node3D:
			(child as Node3D).visible = false  # the scenario's own ships and props stay out of the picture
	get_tree().process_frame.connect(_on_frame)
	_next()


func _run(line: String) -> void:
	for result: ConsoleResult in DebugConsole.registry.execute(line):
		print("[hull sheet] %s%s: %s" % ["" if result.ok else "console error on ", line, "; ".join(result.lines)])


func _next() -> void:
	_index += 1
	_frame = 0
	if _index >= shots.size():
		print("[hull sheet] renderer %s, gpu %s" % [DebugConsole.registry.read("render.renderer")["value"],
				DebugConsole.registry.read("render.gpu")["value"]])
		get_tree().quit()
		return
	var shot: PackedStringArray = shots[_index]
	Settings.set_value(&"texture_detail", StringName(shot[4]))
	if shot[1] == "-":
		_run("sheet off")  # an empty shot: the scene's video memory without a hull
	else:
		_run("sheet %s %d lit - %s" % [shot[1], int(shot[2]), shot[3]])


func _on_frame() -> void:
	if _index < 0 or _index >= shots.size():
		return
	_frame += 1
	if _frame < int(options["settle"]):
		return
	var shot: PackedStringArray = shots[_index]
	var path: String = "%s/%s.png" % [options["out"], shot[0]]
	get_viewport().get_texture().get_image().save_png(path)
	print("[hull sheet] %s: video memory %.0f MB -> %s" % [shot[0], Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, path])
	_next()
