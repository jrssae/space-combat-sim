extends SceneTree
## Compiles every project GDScript outside addons/ and exits 1 if any fails to parse.
## Needed because `--import` does not compile scripts, and GUT skips (rather than fails) a test file that
## does not parse, so a type error could otherwise pass CI silently.
## Usage: godot --headless --path . -s res://scripts/check_scripts.gd

const ROOTS: PackedStringArray = ["res://src", "res://tests", "res://scripts"]


func _initialize() -> void:
	var self_path: String = (get_script() as Script).resource_path
	var paths: PackedStringArray = []
	for root: String in ROOTS:
		_collect(root, paths)
	var failed: PackedStringArray = []
	for path: String in paths:
		if path == self_path:
			continue
		var res: Resource = ResourceLoader.load(path)
		if not (res is Script and (res as Script).can_instantiate()):
			failed.append(path)
	if failed.is_empty():
		print("check_scripts: %d scripts compiled cleanly" % paths.size())
		quit(0)
	else:
		printerr("check_scripts: %d of %d scripts failed to compile:" % [failed.size(), paths.size()])
		for path: String in failed:
			printerr("  " + path)
		quit(1)


func _collect(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		if not sub.begins_with("."):
			_collect(dir_path.path_join(sub), out)
	for file: String in dir.get_files():
		if file.get_extension() == "gd":
			out.append(dir_path.path_join(file))
