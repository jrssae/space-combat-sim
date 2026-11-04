extends GutTest
## Every line a mission script says exists in its dialog file, and every speaker exists (architecture §18 D53, AC6, M5-T06).
## Generic on purpose: it walks the mission scenarios in `data/scenarios/` and `tests/fixtures/missions/`, reads each one's
## script for `say(...)` and `dialog_finished(...)` ids, and checks them against the scenario's dialog file, so a new mission
## (T10's Buoy defence) is covered the moment it exists. Ids a script builds at run time cannot be read; scripts use literals.

## Folders whose `*.json` scenarios may carry a `mission` block, and the folder of dialog files.
const SCENARIO_DIRS: Array[String] = ["res://data/scenarios", "res://tests/fixtures/missions"]
const SCRIPT_DIRS: Array[String] = ["res://data/missions", "res://tests/fixtures/missions"]
const DIALOG_DIR: String = "res://data/dialog"

var _say_pattern: RegEx = RegEx.create_from_string("\\.say\\(\\s*&?[\"']([^\"']+)[\"']")
var _finished_pattern: RegEx = RegEx.create_from_string("dialog_finished\\(\\s*&?[\"']([^\"']+)[\"']")


# --- the scan --------------------------------------------------------------------------------------------------------------


# The ids a script's source says or waits for, once each.
func _line_ids(source: String) -> Array[String]:
	var ids: Array[String] = []
	for pattern: RegEx in [_say_pattern, _finished_pattern]:
		for found: RegExMatch in pattern.search_all(source):
			var id: String = found.get_string(1)
			if not ids.has(id):
				ids.append(id)
	return ids


# The ids a scenario's own objectives wait for (`{"kind": "dialog_finished", "line": id}`), anywhere in its mission block, and
# its closing lines (T10).
func _scenario_ids(node: Variant) -> Array[String]:
	var ids: Array[String] = []
	if node is Dictionary:
		var d: Dictionary = node
		if d.get("kind") == "dialog_finished" and d.get("line") is String:
			ids.append(d["line"])
		if d.get("closing_lines") is Dictionary:
			for line_id: Variant in (d["closing_lines"] as Dictionary).values():
				ids.append(str(line_id))
		for value: Variant in d.values():
			ids.append_array(_scenario_ids(value))
	elif node is Array:
		for value: Variant in node as Array:
			ids.append_array(_scenario_ids(value))
	return ids


func _files(dir: String, extension: String) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out  # a folder no mission has needed yet
	for file_name: String in DirAccess.get_files_at(dir):
		if file_name.ends_with(extension):
			out.append(dir.path_join(file_name))
	out.sort()
	return out


func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


# Every problem found: a script that says an id its dialog lacks, a dialog that does not validate, a script no mission names.
func _problems() -> Array[String]:
	var problems: Array[String] = []
	var named_scripts: Dictionary = {}
	for dir: String in SCENARIO_DIRS:
		for path: String in _files(dir, ".json"):
			var data: Variant = _json(path)
			if not (data is Dictionary) or not (data as Dictionary).get("mission") is Dictionary:
				continue
			var block: Dictionary = (data as Dictionary)["mission"]
			var script_path: String = String(block.get("script", ""))
			var dialog_path: String = String(block.get("dialog", ""))
			var ids: Array[String] = _scenario_ids(block)
			if not script_path.is_empty():
				named_scripts[script_path] = true
				if FileAccess.file_exists(script_path):
					for id: String in _line_ids(FileAccess.get_file_as_string(script_path)):
						if not ids.has(id):
							ids.append(id)
			if dialog_path.is_empty():
				if not ids.is_empty():
					problems.append("%s: says %s but names no dialog file" % [path, ids])
				continue
			var made: Dictionary = DialogBook.load_file(dialog_path)
			if not bool(made["ok"]):
				problems.append("%s: %s" % [path, made["error"]])
				continue
			var book: DialogBook = made["book"]
			for id: String in ids:
				if not book.has_line(StringName(id)):
					problems.append("%s: line '%s' is not in %s" % [path, id, dialog_path])
	for dir: String in SCRIPT_DIRS:
		for path: String in _files(dir, ".gd"):
			if not named_scripts.has(path) and not _line_ids(FileAccess.get_file_as_string(path)).is_empty():
				problems.append("%s: says lines, but no mission scenario names it as its script" % path)
	for path: String in _files(DIALOG_DIR, ".json"):
		if path.get_file() != "speakers.json":
			var made: Dictionary = DialogBook.load_file(path)
			if not bool(made["ok"]):
				problems.append(String(made["error"]))
	return problems


# --- the checks ------------------------------------------------------------------------------------------------------------


func test_every_line_a_mission_script_uses_exists_in_its_dialog_file() -> void:
	var problems: Array[String] = _problems()
	assert_eq(problems, [] as Array[String], "\n".join(PackedStringArray(problems)))


func test_the_scan_covers_the_test_missions() -> void:
	var seen: Array[String] = []
	for path: String in _files("res://tests/fixtures/missions", ".json"):
		var data: Variant = _json(path)
		if data is Dictionary and (data as Dictionary).get("mission") is Dictionary:
			seen.append(path.get_file())
	for expected: String in ["test_mission.json", "test_mission_scout.json", "test_comms.json"]:
		assert_has(seen, expected)
	var ids: Array[String] = _line_ids(FileAccess.get_file_as_string("res://tests/fixtures/missions/test_mission.gd"))
	assert_has(ids, "control_brief")
	assert_has(ids, "control_raiders")


func test_the_scan_covers_buoy_defence_and_its_closing_lines() -> void:
	var data: Variant = _json("res://data/scenarios/buoy_defence.json")
	assert_true(data is Dictionary and (data as Dictionary).get("mission") is Dictionary, "Buoy defence is a mission")
	var block: Dictionary = (data as Dictionary)["mission"]
	var closing: Array[String] = _scenario_ids(block)
	assert_has(closing, "control_relay_lost")
	assert_has(closing, "alpha_2_leader_down")
	var said: Array[String] = _line_ids(FileAccess.get_file_as_string(String(block["script"])))
	assert_gt(said.size(), 5, "the script's lines are read")
	assert_has(said, "control_brief")


# --- the scanner itself (a check that cannot find a missing id would pass for nothing) -----------------------------------


func test_the_scanner_reads_every_way_a_script_names_a_line() -> void:
	var source: String = """
		await m.say(&"one")
		await m.say("two", true)
		m.say( &'three' )
		await m.until(TriggerSpec.dialog_finished(&"four"))
		var say_later: String = "not a call"
		# a comment that mentions m.say(&"five") is read too, and harmlessly
	"""
	var ids: Array[String] = _line_ids(source)
	ids.sort()
	assert_eq(ids, ["five", "four", "one", "three", "two"] as Array[String])


func test_a_missing_line_and_an_unknown_speaker_are_both_found() -> void:
	var speakers := {"speakers": [{"id": "control", "name": "C", "callsign": "CONTROL", "faction": "earth_alliance"}]}
	var book := DialogBook.new()
	assert_eq(book.add_speakers(speakers, "t"), "")
	assert_eq(book.add_lines({"lines": [{"id": "here", "speaker": "control", "text": "Hi", "voice": "v"}]}, "t"), "")
	var ids: Array[String] = _line_ids("await m.say(&\"here\")\nawait m.say(&\"ghost\")")
	var missing: Array[String] = []
	for id: String in ids:
		if not book.has_line(StringName(id)):
			missing.append(id)
	assert_eq(missing, ["ghost"] as Array[String])
	assert_ne(DialogBook.new().add_lines({"lines": [{"id": "x", "speaker": "nobody", "text": "Hi", "voice": "v"}]}, "t"), "",
			"an unknown speaker is refused when the file loads, which the scan reports")
