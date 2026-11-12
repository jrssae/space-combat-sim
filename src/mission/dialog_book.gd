class_name DialogBook
extends RefCounted
## The dialog data a mission speaks from (architecture §18 D53): the speakers (`data/dialog/speakers.json`, `{speakers: [{id,
## name, callsign, faction}]}`) and a dialog file's lines (`{lines: [{id, speaker, text, voice, hold_s?}]}`). Pure: files are read
## by `load_file`, and `add_speakers` / `add_lines` validate plain data, so tests build books without a disk.
##
## A file that does not validate is refused whole, with an error naming the file, the entry and the problem, and adds nothing.
## `voice` is the M15 voice id: required, unused until voiced dialog exists. A line's hold time is its `hold_s`, or derived from
## its length (`hold_for`).

## The speakers every mission shares.
const SPEAKERS_PATH: String = "res://data/dialog/speakers.json"
## Reading speed that sets how long an unmarked line stays up, and the shortest it ever does.
const WORDS_PER_SECOND: float = 2.5
const MIN_HOLD_S: float = 2.0

const _ID_PATTERN: String = "^[a-z0-9_]+$"
const _SPEAKER_KEYS: Array[String] = ["id", "name", "callsign", "faction"]
const _LINE_KEYS: Array[String] = ["id", "speaker", "text", "voice", "hold_s"]


## Who talks: the name for the log, the callsign the comms panel shows, and the faction that colours it.
class Speaker extends RefCounted:
	var id: StringName = &""
	var name: String = ""
	var callsign: String = ""
	var faction: StringName = &""

	func _init(p_id: StringName = &"", p_name: String = "", p_callsign: String = "", p_faction: StringName = &"") -> void:
		id = p_id
		name = p_name
		callsign = p_callsign
		faction = p_faction


## One comms line. `hold_s` is how long it stays up (already derived when the file gave none).
class Line extends RefCounted:
	var id: StringName = &""
	var speaker: StringName = &""
	var text: String = ""
	var voice: StringName = &""
	var hold_s: float = DialogBook.MIN_HOLD_S

	func _init(p_id: StringName = &"", p_speaker: StringName = &"", p_text: String = "", p_voice: StringName = &"",
			p_hold_s: float = -1.0) -> void:
		id = p_id
		speaker = p_speaker
		text = p_text
		voice = p_voice
		hold_s = p_hold_s if p_hold_s > 0.0 else DialogBook.hold_for(p_text)


var _speakers: Dictionary = {}  # StringName -> Speaker
var _speaker_order: Array[StringName] = []
var _lines: Dictionary = {}  # StringName -> Line
var _line_order: Array[StringName] = []


## How long a line of `text` stays up when its file gives no `hold_s`: about 2.5 words a second, never under 2 s.
static func hold_for(text: String) -> float:
	var words: int = text.replace("\n", " ").replace("\t", " ").split(" ", false).size()
	return maxf(MIN_HOLD_S, float(words) / WORDS_PER_SECOND)


## `{"ok": bool, "book": DialogBook or null, "error": String}` for the dialog file at `lines_path` over the speakers file.
static func load_file(lines_path: String, speakers_path: String = SPEAKERS_PATH) -> Dictionary:
	var made := DialogBook.new()
	var speakers: Dictionary = _read_json(speakers_path)
	var problem: String = String(speakers["error"])
	if problem.is_empty():
		problem = made.add_speakers(speakers["data"], speakers_path)
	if problem.is_empty():
		var lines: Dictionary = _read_json(lines_path)
		problem = String(lines["error"])
		if problem.is_empty():
			problem = made.add_lines(lines["data"], lines_path)
	if not problem.is_empty():
		return {"ok": false, "book": null, "error": problem}
	return {"ok": true, "book": made, "error": ""}


## Adds the speakers of one file's data. Returns "" or why nothing was added.
func add_speakers(data: Variant, source: String) -> String:
	var entries: Variant = _list(data, "speakers", source)
	if entries is String:
		return entries
	var added: Dictionary = {}
	var order: Array[StringName] = []
	for i: int in (entries as Array).size():
		var where: String = "%s: speakers[%d]" % [source, i]
		var entry: Variant = (entries as Array)[i]
		if not (entry is Dictionary):
			return "%s must be an object" % where
		var d: Dictionary = entry
		var problem: String = _unknown_key(d, _SPEAKER_KEYS, where)
		for key: String in _SPEAKER_KEYS:
			if problem.is_empty():
				problem = _text_problem(d, key, where)
		if not problem.is_empty():
			return problem
		var id := StringName(String(d["id"]))
		where = "%s: speaker '%s'" % [source, id]
		if _speakers.has(id) or added.has(id):
			return "%s is declared twice (duplicate id)" % where
		var faction := StringName(String(d["faction"]))
		if not Factions.is_known(faction):
			return "%s: faction must be a known faction, got '%s'" % [where, faction]
		added[id] = Speaker.new(id, String(d["name"]), String(d["callsign"]), faction)
		order.append(id)
	_speakers.merge(added)
	_speaker_order.append_array(order)
	return ""


## Adds the lines of one file's data; every speaker must be known already. Returns "" or why nothing was added.
func add_lines(data: Variant, source: String) -> String:
	var entries: Variant = _list(data, "lines", source)
	if entries is String:
		return entries
	var added: Dictionary = {}
	var order: Array[StringName] = []
	var regex := RegEx.create_from_string(_ID_PATTERN)
	for i: int in (entries as Array).size():
		var where: String = "%s: lines[%d]" % [source, i]
		var entry: Variant = (entries as Array)[i]
		if not (entry is Dictionary):
			return "%s must be an object" % where
		var d: Dictionary = entry
		var problem: String = _unknown_key(d, _LINE_KEYS, where)
		for key: String in ["id", "speaker", "text", "voice"]:
			if problem.is_empty():
				problem = _text_problem(d, key, where)
		if not problem.is_empty():
			return problem
		var id := StringName(String(d["id"]))
		where = "%s: line '%s'" % [source, id]
		if regex.search(String(id)) == null:
			return "%s: id must be lower case letters, digits and underscores" % where
		if _lines.has(id) or added.has(id):
			return "%s is declared twice (duplicate id)" % where
		var speaker := StringName(String(d["speaker"]))
		if not _speakers.has(speaker):
			return "%s: unknown speaker '%s' (known: %s)" % [where, speaker, ", ".join(PackedStringArray(_speaker_order))]
		var hold_s: float = -1.0
		if d.has("hold_s"):
			var raw: Variant = d["hold_s"]
			if not (typeof(raw) == TYPE_FLOAT or typeof(raw) == TYPE_INT) or float(raw) <= 0.0:
				return "%s: hold_s must be a number above 0, got %s" % [where, JSON.stringify(raw)]
			hold_s = float(raw)
		added[id] = Line.new(id, speaker, String(d["text"]), StringName(String(d["voice"])), hold_s)
		order.append(id)
	_lines.merge(added)
	_line_order.append_array(order)
	return ""


## Fills placeholders in every line's text (`ScenarioLoader.CIVILIAN_PLACEHOLDER` -> the drawn civilian's name, M5-T30), so
## one dialog file serves whichever ship the seed drew.
func fill(placeholders: Dictionary) -> void:
	if placeholders.is_empty():
		return
	for id: StringName in _lines:
		var l: Line = _lines[id]
		l.text = String(ScenarioLoader.fill_placeholders(l.text, placeholders))


func has_line(id: StringName) -> bool:
	return _lines.has(id)


## The line `id`, or null.
func line(id: StringName) -> Line:
	return _lines.get(id) as Line


## Every line id, in the order the files gave them.
func line_ids() -> Array[StringName]:
	return _line_order.duplicate()


func line_count() -> int:
	return _line_order.size()


## The speaker `id`, or null.
func speaker(id: StringName) -> Speaker:
	return _speakers.get(id) as Speaker


## Who says `spoken` (null only for a line built by hand).
func speaker_of(spoken: Line) -> Speaker:
	return speaker(spoken.speaker)


func speaker_ids() -> Array[StringName]:
	return _speaker_order.duplicate()


# --- internals -------------------------------------------------------------------------------------------------------------


# `{"data": parsed JSON, "error": ""}` or an error naming the file.
static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"data": null, "error": "%s: no such file" % path}
	var parser := JSON.new()
	var problem: Error = parser.parse(FileAccess.get_file_as_string(path))
	if problem != OK:
		return {"data": null, "error": "%s: not valid JSON (line %d: %s)" % [path, parser.get_error_line(), parser.get_error_message()]}
	return {"data": parser.data, "error": ""}


# The array under `key` of a file's object, or an error string.
static func _list(data: Variant, key: String, source: String) -> Variant:
	if not (data is Dictionary):
		return "%s: the file must be an object with a '%s' array" % [source, key]
	var entries: Variant = (data as Dictionary).get(key)
	if not (entries is Array):
		return "%s: '%s' must be an array" % [source, key]
	return entries


static func _unknown_key(d: Dictionary, allowed: Array[String], where: String) -> String:
	for key: Variant in d:
		if not allowed.has(String(key)):
			return "%s: unknown field '%s' (expected %s)" % [where, key, ", ".join(PackedStringArray(allowed))]
	return ""


# "" when `d[key]` is a non-empty string.
static func _text_problem(d: Dictionary, key: String, where: String) -> String:
	var value: Variant = d.get(key)
	if not (value is String) or (value as String).strip_edges().is_empty():
		return "%s: %s must be a non-empty string, got %s" % [where, key, JSON.stringify(value)]
	return ""
