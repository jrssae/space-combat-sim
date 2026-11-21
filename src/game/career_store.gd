class_name CareerStore
extends RefCounted
## Keeps the `Career` on disk beside the settings (M8 D79), so a rank survives a restart. A save goes to a file beside it
## first and then takes its place, so a crash in the middle of a write cannot leave the rank half written. If the move
## fails after the old save had to go first, the new one stays in that file beside it and a load reads it from there.

const DEFAULT_PATH: String = "user://career.json"
const TMP_SUFFIX: String = ".tmp"


## The saved career: from `path`, or when that is missing or unreadable from the file a save left beside it; a fresh one
## when neither reads.
static func load_file(path: String = DEFAULT_PATH) -> Career:
	var saved: Variant = _read(path)
	if saved == null:
		saved = _read(path + TMP_SUFFIX)
	return Career.from_dict(saved)


## Returns "" or why it could not be written.
static func save_file(career: Career, path: String = DEFAULT_PATH) -> String:
	var tmp: String = path + TMP_SUFFIX
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return "cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())]
	file.store_string(JSON.stringify(career.to_dict(), " "))
	file.close()
	var moved: Error = DirAccess.rename_absolute(tmp, path)
	if moved != OK and FileAccess.file_exists(path):
		# Where a rename will not replace a file (Windows), the old one goes first.
		DirAccess.remove_absolute(path)
		moved = DirAccess.rename_absolute(tmp, path)
	if moved != OK:
		# The temporary file goes only while the save it could not replace still stands: with that gone it is the one copy.
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(tmp)
		return "cannot move %s to %s (%s)" % [tmp, path, error_string(moved)]
	return ""


# The saved data in `file_path`, or null when there is no such file or it does not hold a JSON object.
static func _read(file_path: String) -> Variant:
	if not FileAccess.file_exists(file_path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(file_path)) != OK or not (json.data is Dictionary):
		return null
	return json.data
