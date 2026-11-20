class_name CareerStore
extends RefCounted
## Keeps the `Career` on disk beside the settings (M8 D79), so a rank survives a restart. A save goes to a file beside it
## first and then takes its place, so a crash in the middle of a write cannot leave the rank half written.

const DEFAULT_PATH: String = "user://career.json"
const TMP_SUFFIX: String = ".tmp"


## The saved career, or a fresh one when there is no readable file.
static func load_file(path: String = DEFAULT_PATH) -> Career:
	if not FileAccess.file_exists(path):
		return Career.new()
	return Career.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))


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
		DirAccess.remove_absolute(tmp)
		return "cannot move %s to %s (%s)" % [tmp, path, error_string(moved)]
	return ""
