class_name ConsoleHistory
extends RefCounted
## Typed console lines, newest last, capped at MAX_ENTRIES and persisted one per line (architecture §6.4).
## Up/Down browsing keeps the line being typed as a draft and returns it when browsing past the newest entry.
## Only lines the user typed belong here; startup scripts and `exec` files are not history.

const MAX_ENTRIES: int = 100
const DEFAULT_PATH: String = "user://console_history.txt"

var path: String = DEFAULT_PATH

var _entries: PackedStringArray = PackedStringArray()
var _cursor: int = -1  # index into _entries while browsing, -1 when not
var _draft: String = ""


func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path


## Appends a line (stripped). Blank lines and repeats of the newest entry are ignored. Ends any browsing.
func add(line: String) -> void:
	reset_cursor()
	var text: String = line.strip_edges()
	if text.is_empty() or text.contains("\n"):
		return
	if not _entries.is_empty() and _entries[_entries.size() - 1] == text:
		return
	_entries.append(text)
	if _entries.size() > MAX_ENTRIES:
		_entries = _entries.slice(_entries.size() - MAX_ENTRIES)


func entries() -> PackedStringArray:
	return _entries.duplicate()


func size() -> int:
	return _entries.size()


## Up: the next older entry. `current` is what is typed now; it is kept as the draft on the first step.
func older(current: String) -> String:
	if _entries.is_empty():
		return current
	if _cursor == -1:
		_draft = current
		_cursor = _entries.size() - 1
	elif _cursor > 0:
		_cursor -= 1
	return _entries[_cursor]


## Down: the next newer entry, or the draft after the newest one.
func newer(current: String) -> String:
	if _cursor == -1:
		return current
	_cursor += 1
	if _cursor >= _entries.size():
		_cursor = -1
		return _draft
	return _entries[_cursor]


func reset_cursor() -> void:
	_cursor = -1
	_draft = ""


func clear() -> void:
	_entries = PackedStringArray()
	reset_cursor()


## Replaces the entries with the file's (keeping the newest MAX_ENTRIES). A missing file is an empty history.
func load_file() -> Error:
	clear()
	if not FileAccess.file_exists(path):
		return OK
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	while not file.eof_reached():
		var text: String = file.get_line().strip_edges()
		if not text.is_empty():
			_entries.append(text)
	if _entries.size() > MAX_ENTRIES:
		_entries = _entries.slice(_entries.size() - MAX_ENTRIES)
	return OK


func save_file() -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	for text: String in _entries:
		file.store_line(text)
	return OK
