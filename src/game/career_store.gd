class_name CareerStore
extends RefCounted
## Keeps the `Career` on disk beside the settings (M8 D79), so a rank survives a restart.

const DEFAULT_PATH: String = "user://career.json"


## The saved career, or a fresh one when there is no readable file.
static func load_file(path: String = DEFAULT_PATH) -> Career:
	if not FileAccess.file_exists(path):
		return Career.new()
	return Career.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))


## Returns "" or why it could not be written.
static func save_file(career: Career, path: String = DEFAULT_PATH) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())]
	file.store_string(JSON.stringify(career.to_dict(), " "))
	return ""
