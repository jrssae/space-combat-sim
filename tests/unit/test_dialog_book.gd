extends GutTest
## DialogBook (architecture §18 D53, M5-T06): the speakers and dialog lines as data. A file that does not validate is refused
## whole, with an error that names the entry and the problem; a line's hold time is its `hold_s` or derived from its length.

const DIR: String = "user://test_dialog_book"

var book: DialogBook


func before_each() -> void:
	book = DialogBook.new()
	DirAccess.make_dir_recursive_absolute(DIR)


func after_each() -> void:
	for file_name: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(file_name))
	DirAccess.remove_absolute(DIR)
	Factions.reset()


func _speakers() -> Dictionary:
	return {"speakers": [
		{"id": "control", "name": "Babylon 5 Control", "callsign": "CONTROL", "faction": "earth_alliance"},
		{"id": "raider_lead", "name": "Raider leader", "callsign": "UNKNOWN", "faction": "raiders"},
	]}


func _line(overrides: Dictionary = {}) -> Dictionary:
	var line: Dictionary = {"id": "brief", "speaker": "control", "text": "Alpha wing, raiders are heading for the relay.",
			"voice": "control_01"}
	line.merge(overrides, true)
	return line


func _write(file_name: String, data: Variant) -> String:
	var path: String = DIR.path_join(file_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(data if data is String else JSON.stringify(data))
	file.close()
	return path


# --- hold time -------------------------------------------------------------------------------------------------------------


func test_hold_time_is_about_two_and_a_half_words_a_second_and_at_least_two_seconds() -> void:
	assert_eq(DialogBook.hold_for(""), 2.0)
	assert_eq(DialogBook.hold_for("Copy that."), 2.0, "short lines stay the minimum")
	assert_almost_eq(DialogBook.hold_for("one two three four five six seven eight nine ten"), 4.0, 1e-6)
	assert_almost_eq(DialogBook.hold_for("  spaces   and\nnewlines\tcount  once  each  word  here  now  "), 3.6, 1e-6,
			"nine words however they are separated")
	assert_almost_eq(DialogBook.hold_for("word" + " word".repeat(24)), 10.0, 1e-6, "25 words")


func test_a_line_without_hold_s_gets_the_derived_time_and_an_explicit_one_wins() -> void:
	assert_eq(book.add_speakers(_speakers(), "t"), "")
	assert_eq(book.add_lines({"lines": [_line(), _line({"id": "short", "text": "Copy.", "hold_s": 0.5})]}, "t"), "")
	assert_almost_eq(book.line(&"brief").hold_s, DialogBook.hold_for("Alpha wing, raiders are heading for the relay."), 1e-6)
	assert_eq(book.line(&"short").hold_s, 0.5, "an explicit hold_s is kept even under the minimum")


# --- what a valid book answers ---------------------------------------------------------------------------------------------


func test_a_valid_book_answers_by_id_in_file_order() -> void:
	assert_eq(book.add_speakers(_speakers(), "t"), "")
	assert_eq(book.add_lines({"lines": [_line(), _line({"id": "warn", "speaker": "raider_lead", "text": "Scatter!"})]}, "t"), "")
	assert_eq(book.line_ids(), [&"brief", &"warn"] as Array[StringName])
	assert_eq(book.line_count(), 2)
	assert_true(book.has_line(&"warn"))
	assert_false(book.has_line(&"nope"))
	assert_null(book.line(&"nope"))
	var line: DialogBook.Line = book.line(&"brief")
	assert_eq(line.id, &"brief")
	assert_eq(line.speaker, &"control")
	assert_eq(line.voice, &"control_01", "the M15 voice id is kept, unused for now")
	assert_eq(line.text, "Alpha wing, raiders are heading for the relay.")
	var speaker: DialogBook.Speaker = book.speaker_of(line)
	assert_eq(speaker.callsign, "CONTROL")
	assert_eq(speaker.name, "Babylon 5 Control")
	assert_eq(speaker.faction, Factions.EARTH_ALLIANCE)
	assert_eq(book.speaker_ids(), [&"control", &"raider_lead"] as Array[StringName])
	assert_null(book.speaker(&"nobody"))


# --- refusals --------------------------------------------------------------------------------------------------------------


func test_an_unknown_speaker_is_refused_and_named() -> void:
	book.add_speakers(_speakers(), "t")
	var error: String = book.add_lines({"lines": [_line({"speaker": "ghost"})]}, "dialog.json")
	assert_string_contains(error, "dialog.json")
	assert_string_contains(error, "brief")
	assert_string_contains(error, "unknown speaker")
	assert_string_contains(error, "ghost")
	assert_string_contains(error, "control", "the known speakers are listed")
	assert_eq(book.line_count(), 0, "a refused file adds nothing")


func test_a_duplicate_line_id_is_refused_even_across_files() -> void:
	book.add_speakers(_speakers(), "t")
	assert_string_contains(book.add_lines({"lines": [_line(), _line()]}, "a.json"), "duplicate")
	assert_eq(book.line_count(), 0)
	assert_eq(book.add_lines({"lines": [_line()]}, "a.json"), "")
	assert_string_contains(book.add_lines({"lines": [_line()]}, "b.json"), "duplicate")
	assert_eq(book.line_count(), 1)


func test_every_required_field_is_checked() -> void:
	book.add_speakers(_speakers(), "t")
	for field: String in ["id", "speaker", "text", "voice"]:
		var line: Dictionary = _line()
		line.erase(field)
		assert_string_contains(book.add_lines({"lines": [line]}, "t"), field, "missing %s" % field)
		assert_string_contains(book.add_lines({"lines": [_line({field: ""})]}, "t"), field, "empty %s" % field)
		assert_string_contains(book.add_lines({"lines": [_line({field: 7})]}, "t"), field, "%s must be a string" % field)
	assert_eq(book.line_count(), 0)


func test_hold_s_must_be_a_positive_number_when_given() -> void:
	book.add_speakers(_speakers(), "t")
	for bad: Variant in [0, -1.5, "3", true, null]:
		assert_string_contains(book.add_lines({"lines": [_line({"hold_s": bad})]}, "t"), "hold_s", "hold_s %s" % [bad])
	assert_eq(book.add_lines({"lines": [_line({"hold_s": 3})]}, "t"), "", "an integer is a number")


func test_line_ids_are_lower_case_words() -> void:
	book.add_speakers(_speakers(), "t")
	for bad: String in ["Brief", "two words", "wave.1", "-x"]:
		assert_string_contains(book.add_lines({"lines": [_line({"id": bad})]}, "t"), "id", "id '%s'" % bad)
	assert_eq(book.add_lines({"lines": [_line({"id": "wave_1_warning"})]}, "t"), "")


func test_an_unknown_field_is_refused_so_a_typo_does_not_pass() -> void:
	book.add_speakers(_speakers(), "t")
	var error: String = book.add_lines({"lines": [_line({"holds_s": 4.0})]}, "t")
	assert_string_contains(error, "holds_s")
	assert_string_contains(error, "unknown")


func test_the_file_shape_is_checked() -> void:
	book.add_speakers(_speakers(), "t")
	assert_string_contains(book.add_lines([], "t"), "object")
	assert_string_contains(book.add_lines({}, "t"), "lines")
	assert_string_contains(book.add_lines({"lines": {}}, "t"), "lines")
	assert_string_contains(book.add_lines({"lines": ["text"]}, "t"), "object")
	assert_eq(book.add_lines({"lines": []}, "t"), "", "no lines is a valid, if empty, file")


func test_speakers_are_validated_too() -> void:
	var speaker: Dictionary = _speakers()["speakers"][0]
	for field: String in ["id", "name", "callsign", "faction"]:
		var broken: Dictionary = speaker.duplicate()
		broken.erase(field)
		assert_string_contains(DialogBook.new().add_speakers({"speakers": [broken]}, "s.json"), field, "missing %s" % field)
	assert_string_contains(DialogBook.new().add_speakers({"speakers": [speaker, speaker]}, "s.json"), "duplicate")
	var unknown_faction: Dictionary = speaker.duplicate()
	unknown_faction["faction"] = "klingons"
	var error: String = DialogBook.new().add_speakers({"speakers": [unknown_faction]}, "s.json")
	assert_string_contains(error, "faction")
	assert_string_contains(error, "klingons")
	assert_string_contains(DialogBook.new().add_speakers({}, "s.json"), "speakers")


func test_a_refused_speakers_file_adds_nothing() -> void:
	var good: Dictionary = _speakers()["speakers"][0]
	var bad: Dictionary = good.duplicate()
	bad["id"] = "other"
	bad["callsign"] = ""
	assert_ne(book.add_speakers({"speakers": [good, bad]}, "t"), "")
	assert_eq(book.speaker_ids(), [] as Array[StringName])


# --- files -----------------------------------------------------------------------------------------------------------------


func test_load_file_reads_the_lines_and_the_speakers() -> void:
	var speakers_path: String = _write("speakers.json", _speakers())
	var lines_path: String = _write("lines.json", {"lines": [_line()]})
	var made: Dictionary = DialogBook.load_file(lines_path, speakers_path)
	assert_true(made["ok"], str(made["error"]))
	assert_eq(made["error"], "")
	var loaded: DialogBook = made["book"]
	assert_true(loaded.has_line(&"brief"))
	assert_eq(loaded.speaker_of(loaded.line(&"brief")).callsign, "CONTROL")


func test_load_file_says_which_file_failed_and_why() -> void:
	var speakers_path: String = _write("speakers.json", _speakers())
	var missing: Dictionary = DialogBook.load_file(DIR.path_join("none.json"), speakers_path)
	assert_false(missing["ok"])
	assert_string_contains(missing["error"], "none.json")
	var garbled: Dictionary = DialogBook.load_file(_write("garbled.json", "{not json"), speakers_path)
	assert_false(garbled["ok"])
	assert_string_contains(garbled["error"], "garbled.json")
	var no_speakers: Dictionary = DialogBook.load_file(_write("lines.json", {"lines": [_line()]}), DIR.path_join("nospeakers.json"))
	assert_false(no_speakers["ok"])
	assert_string_contains(no_speakers["error"], "nospeakers.json")
	var bad_line: Dictionary = DialogBook.load_file(_write("bad.json", {"lines": [_line({"speaker": "ghost"})]}), speakers_path)
	assert_false(bad_line["ok"])
	assert_string_contains(bad_line["error"], "bad.json")
	assert_string_contains(bad_line["error"], "ghost")
	assert_null(bad_line["book"])


func test_the_shipped_speakers_load_and_use_known_factions_and_distinct_callsigns() -> void:
	var made: Dictionary = DialogBook.load_file(_write("empty.json", {"lines": []}))
	assert_true(made["ok"], str(made["error"]))
	var shipped: DialogBook = made["book"]
	assert_true(shipped.speaker_ids().has(&"control"))
	var callsigns: Dictionary = {}
	for id: StringName in shipped.speaker_ids():
		var speaker: DialogBook.Speaker = shipped.speaker(id)
		assert_true(Factions.is_known(speaker.faction), "%s: %s is a known faction" % [id, speaker.faction])
		assert_false(callsigns.has(speaker.callsign), "callsign %s is used once" % speaker.callsign)
		callsigns[speaker.callsign] = true
