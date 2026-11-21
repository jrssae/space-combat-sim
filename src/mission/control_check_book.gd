class_name ControlCheckBook
extends RefCounted
## The control checks a mission can run (M8 D80): `data/checks/controls.json`, `{defaults: {...}, checks: [{id, label, actions,
## kind, ...}]}` (`ControlCheck` documents an entry). `make` hands out a fresh check each time, so one can be run again. A
## file that does not validate is refused whole, with an error naming the file, the entry and the problem.

## The checks every mission shares.
const PATH: String = "res://data/checks/controls.json"

var _entries: Dictionary = {}  # StringName -> Dictionary, its defaults filled in
var _order: Array[StringName] = []


## Reads a checks file. Returns {"ok", "book", "error"}.
static func load_file(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "book": null, "error": "%s: no such file" % path}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {"ok": false, "book": null, "error": "%s: line %d: %s" % [path, json.get_error_line(), json.get_error_message()]}
	var made := ControlCheckBook.new()
	var problem: String = made.add(json.data, path)
	if not problem.is_empty():
		return {"ok": false, "book": null, "error": problem}
	return {"ok": true, "book": made, "error": ""}


## Adds one file's checks. Returns "" or why nothing was added.
func add(data: Variant, source: String) -> String:
	if not (data is Dictionary) or not ((data as Dictionary).get("checks") is Array):
		return "%s: expected {\"checks\": [...]}" % source
	var defaults: Variant = (data as Dictionary).get("defaults", {})
	if not (defaults is Dictionary):
		return "%s: defaults must be an object" % source
	var added: Dictionary = {}
	var order: Array[StringName] = []
	var entries: Array = (data as Dictionary)["checks"]
	for i: int in entries.size():
		var made: Dictionary = ControlCheck.from_dict(entries[i], defaults)
		if not bool(made["ok"]):
			return "%s: checks[%d]: %s" % [source, i, made["error"]]
		var check: ControlCheck = made["check"]
		if _entries.has(check.id) or added.has(check.id):
			return "%s: checks[%d]: check '%s' is defined twice" % [source, i, check.id]
		var entry: Dictionary = (defaults as Dictionary).duplicate()
		entry.merge(entries[i] as Dictionary, true)
		added[check.id] = entry
		order.append(check.id)
	_entries.merge(added)
	_order.append_array(order)
	return ""


func has(id: StringName) -> bool:
	return _entries.has(id)


## Every check's id, in the file's order (the order the tutorial teaches them).
func ids() -> Array[StringName]:
	return _order.duplicate()


## A fresh check `id`, nothing measured yet; null when the book has none.
func make(id: StringName) -> ControlCheck:
	if not _entries.has(id):
		return null
	return ControlCheck.from_dict(_entries[id])["check"] as ControlCheck
