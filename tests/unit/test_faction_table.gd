extends GutTest
## FactionTable (M3-T02, AC2, architecture §16 D30): parsing and validating data/factions.json, the relation rule, and
## the session changes the console makes.

const FILE_PATH: String = "res://data/factions.json"

const EA: StringName = Factions.EARTH_ALLIANCE
const RA: StringName = Factions.RAIDERS
const NE: StringName = Factions.NEUTRAL


# A valid document the tests break one field at a time.
func _doc() -> Dictionary:
	return {
		"factions": [{"id": "earth_alliance", "name": "Earth Alliance"}, {"id": "raiders", "name": "Raiders"},
				{"id": "neutral", "name": "Neutral"}],
		"relations": [{"a": "earth_alliance", "b": "raiders", "relation": "hostile"}],
		"default": "neutral",
	}


func _table_from(doc: Dictionary) -> FactionTable:
	var result: Dictionary = FactionTable.from_dict(doc)
	assert_true(result["ok"], "valid document: %s" % result["error"])
	return result["table"]


func _assert_error(doc: Variant, expected: String) -> void:
	var result: Dictionary = FactionTable.from_dict(doc)
	assert_false(result["ok"], "should be rejected: " + expected)
	assert_null(result["table"], "no table from a broken document")
	assert_string_contains(String(result["error"]), expected)


# --- the shipped file ----------------------------------------------------------------------------------------


func test_the_shipped_file_validates() -> void:
	var result: Dictionary = FactionTable.load_file(FILE_PATH)
	assert_true(result["ok"], result["error"])
	assert_eq(result["error"], "")
	var table: FactionTable = result["table"]
	assert_eq(table.ids(), [EA, RA, NE] as Array[StringName])
	assert_eq(table.display_name(EA), "Earth Alliance")
	assert_eq(table.display_name(RA), "Raiders")
	assert_eq(table.display_name(NE), "Neutral")
	assert_eq(table.default_relation(), Factions.Relation.NEUTRAL)


func test_the_shipped_file_is_the_built_in_m2_rule() -> void:
	# AC0: with the file at its defaults, every relation is what M2 computed.
	var file_table: FactionTable = FactionTable.load_file(FILE_PATH)["table"]
	var built_in: FactionTable = FactionTable.builtin()
	assert_eq(file_table.ids(), built_in.ids())
	assert_eq(file_table.default_relation(), built_in.default_relation())
	var probes: Array[StringName] = [EA, RA, NE, &"pirates", &""]
	for a: StringName in probes:
		for b: StringName in probes:
			assert_eq(file_table.relation(a, b), built_in.relation(a, b), "%s vs %s" % [a, b])
			assert_eq(file_table.relation(a, b), _m2_rule(a, b), "%s vs %s against the M2 rule" % [a, b])


# The M2 rule as it was coded before the data file (Factions.relation in M2).
func _m2_rule(a: StringName, b: StringName) -> Factions.Relation:
	var known: Array[StringName] = [EA, RA, NE]
	if a == b:
		return Factions.Relation.FRIENDLY
	if not known.has(a) or not known.has(b) or a == NE or b == NE:
		return Factions.Relation.NEUTRAL
	return Factions.Relation.HOSTILE


func test_load_file_reports_a_missing_file_with_its_path() -> void:
	var result: Dictionary = FactionTable.load_file("res://data/no_such_factions.json")
	assert_false(result["ok"])
	assert_null(result["table"])
	assert_string_contains(String(result["error"]), "res://data/no_such_factions.json: cannot open")


# --- the rule --------------------------------------------------------------------------------------------------


func test_same_faction_is_friendly_even_when_unlisted() -> void:
	var table: FactionTable = _table_from(_doc())
	for id: StringName in [EA, RA, NE, &"pirates", &""]:
		assert_eq(table.relation(id, id), Factions.Relation.FRIENDLY, str(id))


func test_listed_pairs_are_symmetric() -> void:
	var table: FactionTable = _table_from(_doc())
	assert_eq(table.relation(EA, RA), Factions.Relation.HOSTILE)
	assert_eq(table.relation(RA, EA), Factions.Relation.HOSTILE)


func test_an_unlisted_pair_is_the_files_default() -> void:
	for default_name: String in ["friendly", "neutral", "hostile"]:
		var doc: Dictionary = _doc()
		doc["default"] = default_name
		var table: FactionTable = _table_from(doc)
		var expected: int = FactionTable.relation_from_name(default_name)
		assert_eq(int(table.relation(EA, NE)), expected, "earth_alliance vs neutral with default " + default_name)
		assert_eq(int(table.relation(NE, RA)), expected, "neutral vs raiders with default " + default_name)
		assert_eq(table.relation(EA, RA), Factions.Relation.HOSTILE, "a listed pair beats the default")
		assert_eq(int(table.default_relation()), expected)


func test_an_unknown_id_is_neutral_to_everything_but_itself_whatever_the_default() -> void:
	var doc: Dictionary = _doc()
	doc["default"] = "hostile"
	var table: FactionTable = _table_from(doc)
	for id: StringName in [EA, RA, NE]:
		assert_eq(table.relation(&"pirates", id), Factions.Relation.NEUTRAL, "pirates vs %s" % id)
		assert_eq(table.relation(id, &"pirates"), Factions.Relation.NEUTRAL, "%s vs pirates" % id)
		assert_eq(table.relation(&"", id), Factions.Relation.NEUTRAL)
	assert_eq(table.relation(&"pirates", &"smugglers"), Factions.Relation.NEUTRAL)
	assert_eq(table.relation(&"pirates", &"pirates"), Factions.Relation.FRIENDLY)


func test_a_pair_can_be_listed_in_either_order() -> void:
	var doc: Dictionary = _doc()
	doc["relations"] = [{"a": "raiders", "b": "earth_alliance", "relation": "friendly"}]
	var table: FactionTable = _table_from(doc)
	assert_eq(table.relation(EA, RA), Factions.Relation.FRIENDLY)
	assert_eq(table.relation(RA, EA), Factions.Relation.FRIENDLY)


func test_relation_names_are_case_insensitive() -> void:
	assert_eq(FactionTable.relation_from_name("Hostile"), Factions.Relation.HOSTILE)
	assert_eq(FactionTable.relation_from_name(&"FRIENDLY"), Factions.Relation.FRIENDLY)
	assert_eq(FactionTable.relation_from_name("enemy"), -1)
	assert_eq(FactionTable.relation_from_name(3), -1)
	assert_eq(FactionTable.relation_name(Factions.Relation.HOSTILE), &"hostile")
	assert_eq(FactionTable.relation_name(Factions.Relation.FRIENDLY), &"friendly")
	assert_eq(FactionTable.relation_name(Factions.Relation.NEUTRAL), &"neutral")


func test_a_new_faction_and_pair_are_just_data() -> void:
	var doc: Dictionary = _doc()
	(doc["factions"] as Array).append({"id": "pirates", "name": "Pirates"})
	(doc["relations"] as Array).append({"a": "pirates", "b": "raiders", "relation": "friendly"})
	(doc["relations"] as Array).append({"a": "pirates", "b": "earth_alliance", "relation": "hostile"})
	var table: FactionTable = _table_from(doc)
	assert_true(table.has(&"pirates"))
	assert_eq(table.display_name(&"pirates"), "Pirates")
	assert_eq(table.relation(&"pirates", RA), Factions.Relation.FRIENDLY)
	assert_eq(table.relation(EA, &"pirates"), Factions.Relation.HOSTILE)
	assert_eq(table.relation(&"pirates", NE), Factions.Relation.NEUTRAL)


func test_has_and_display_name() -> void:
	var table: FactionTable = _table_from(_doc())
	assert_true(table.has(EA))
	assert_false(table.has(&"pirates"))
	assert_false(table.has(&""))
	assert_eq(table.display_name(&"pirates"), "pirates", "an unlisted id is its own name")


# --- validation ------------------------------------------------------------------------------------------------


func test_a_non_object_root_is_rejected() -> void:
	_assert_error([], "the root must be an object")
	_assert_error("factions", "the root must be an object")
	_assert_error(null, "the root must be an object")


func test_factions_must_be_a_non_empty_array() -> void:
	var doc: Dictionary = _doc()
	doc.erase("factions")
	_assert_error(doc, "factions must be a non-empty array")
	doc["factions"] = []
	_assert_error(doc, "factions must be a non-empty array")
	doc["factions"] = {"id": "earth_alliance"}
	_assert_error(doc, "factions must be a non-empty array")


func test_a_faction_entry_must_be_an_object() -> void:
	var doc: Dictionary = _doc()
	(doc["factions"] as Array)[1] = "raiders"
	_assert_error(doc, "factions[1] must be an object")


func test_faction_ids_are_lower_snake() -> void:
	for bad: Variant in ["Raiders", "", "has space", "with-dash", "x".repeat(33), 7, null]:
		var doc: Dictionary = _doc()
		((doc["factions"] as Array)[1] as Dictionary)["id"] = bad
		_assert_error(doc, "factions[1].id must match")
	var doc: Dictionary = _doc()
	((doc["factions"] as Array)[2] as Dictionary).erase("id")
	_assert_error(doc, "factions[2].id must match")


func test_faction_names_must_be_non_empty_strings() -> void:
	for bad: Variant in ["", "   ", 7, null]:
		var doc: Dictionary = _doc()
		((doc["factions"] as Array)[0] as Dictionary)["name"] = bad
		_assert_error(doc, "factions[0].name must be a non-empty string")


func test_a_repeated_faction_id_names_both_entries() -> void:
	var doc: Dictionary = _doc()
	((doc["factions"] as Array)[2] as Dictionary)["id"] = "raiders"
	_assert_error(doc, "factions[2].id \"raiders\" repeats factions[1].id")


func test_the_default_must_be_a_relation_name() -> void:
	for bad: Variant in ["enemy", "", 1, null]:
		var doc: Dictionary = _doc()
		doc["default"] = bad
		_assert_error(doc, "default must be one of friendly|neutral|hostile")
	var doc: Dictionary = _doc()
	doc.erase("default")
	_assert_error(doc, "default must be one of friendly|neutral|hostile, got null")


func test_relations_must_be_an_array() -> void:
	var doc: Dictionary = _doc()
	doc.erase("relations")
	_assert_error(doc, "relations must be an array")
	doc["relations"] = {"a": "earth_alliance"}
	_assert_error(doc, "relations must be an array")


func test_a_relation_entry_must_be_an_object() -> void:
	var doc: Dictionary = _doc()
	(doc["relations"] as Array).append("earth_alliance raiders hostile")
	_assert_error(doc, "relations[1] must be an object")


func test_relation_sides_must_be_listed_faction_ids() -> void:
	for side: String in ["a", "b"]:
		for bad: Variant in ["pirates", "", 3, null]:
			var doc: Dictionary = _doc()
			((doc["relations"] as Array)[0] as Dictionary)[side] = bad
			_assert_error(doc, "relations[0].%s must be one of the listed faction ids (earth_alliance, raiders, neutral)" % side)


func test_a_pair_cannot_name_one_faction_twice() -> void:
	var doc: Dictionary = _doc()
	((doc["relations"] as Array)[0] as Dictionary)["b"] = "earth_alliance"
	_assert_error(doc, "relations[0] pairs \"earth_alliance\" with itself")


func test_the_relation_must_be_a_relation_name() -> void:
	for bad: Variant in ["enemy", "", 2, null]:
		var doc: Dictionary = _doc()
		((doc["relations"] as Array)[0] as Dictionary)["relation"] = bad
		_assert_error(doc, "relations[0].relation must be one of friendly|neutral|hostile")
	var doc: Dictionary = _doc()
	((doc["relations"] as Array)[0] as Dictionary)["relation"] = "enemy"
	_assert_error(doc, "relations[0].relation must be one of friendly|neutral|hostile, got \"enemy\"")


func test_a_pair_listed_twice_is_rejected_in_either_order() -> void:
	var doc: Dictionary = _doc()
	(doc["relations"] as Array).append({"a": "raiders", "b": "earth_alliance", "relation": "friendly"})
	_assert_error(doc, "relations[1] repeats the pair raiders/earth_alliance already set by relations[0]")


func test_the_first_problem_in_file_order_is_reported() -> void:
	var doc: Dictionary = _doc()
	((doc["relations"] as Array)[0] as Dictionary)["relation"] = "enemy"
	((doc["factions"] as Array)[2] as Dictionary)["name"] = ""
	_assert_error(doc, "factions[2].name")


# --- text ------------------------------------------------------------------------------------------------------


func test_parse_reads_json_text_and_names_the_source() -> void:
	var text: String = JSON.stringify(_doc())
	var good: Dictionary = FactionTable.parse(text, "mine.json")
	assert_true(good["ok"])
	assert_eq(good["error"], "")

	var broken: Dictionary = _doc()
	((broken["relations"] as Array)[0] as Dictionary)["relation"] = "enemy"
	var bad: Dictionary = FactionTable.parse(JSON.stringify(broken), "mine.json")
	assert_false(bad["ok"])
	assert_null(bad["table"])
	assert_string_starts_with(String(bad["error"]), "mine.json: relations[0].relation must be one of")


func test_parse_rejects_invalid_json() -> void:
	var result: Dictionary = FactionTable.parse("{\"factions\": [", "broken.json")
	assert_false(result["ok"])
	assert_null(result["table"])
	assert_string_contains(String(result["error"]), "broken.json: invalid JSON at line")


# --- session changes ---------------------------------------------------------------------------------------------


func test_set_relation_changes_a_listed_pair_in_both_directions() -> void:
	var table: FactionTable = _table_from(_doc())
	assert_eq(table.set_relation(EA, RA, Factions.Relation.NEUTRAL), "")
	assert_eq(table.relation(EA, RA), Factions.Relation.NEUTRAL)
	assert_eq(table.relation(RA, EA), Factions.Relation.NEUTRAL)
	assert_eq(table.listed_pairs().size(), 1, "the pair is changed, not added twice")
	assert_eq(table.set_relation(RA, EA, Factions.Relation.HOSTILE), "")
	assert_eq(table.relation(EA, RA), Factions.Relation.HOSTILE)
	assert_eq(table.listed_pairs().size(), 1)


func test_set_relation_can_add_a_pair_the_file_does_not_list() -> void:
	var table: FactionTable = _table_from(_doc())
	assert_eq(table.relation(EA, NE), Factions.Relation.NEUTRAL)
	assert_eq(table.set_relation(NE, EA, Factions.Relation.FRIENDLY), "")
	assert_eq(table.relation(EA, NE), Factions.Relation.FRIENDLY)
	assert_eq(table.relation(NE, EA), Factions.Relation.FRIENDLY)
	var pairs: Array[Dictionary] = table.listed_pairs()
	assert_eq(pairs.size(), 2)
	assert_eq(pairs[1]["relation"], Factions.Relation.FRIENDLY)


func test_set_relation_refuses_unknown_ids_and_self_pairs() -> void:
	var table: FactionTable = _table_from(_doc())
	assert_string_contains(table.set_relation(&"pirates", RA, Factions.Relation.HOSTILE), "unknown faction 'pirates'")
	assert_string_contains(table.set_relation(EA, &"pirates", Factions.Relation.HOSTILE), "unknown faction 'pirates'")
	assert_string_contains(table.set_relation(EA, EA, Factions.Relation.HOSTILE), "always friendly to itself")
	assert_eq(table.relation(EA, EA), Factions.Relation.FRIENDLY)
	assert_eq(table.relation(EA, RA), Factions.Relation.HOSTILE, "the failed calls changed nothing")


func test_listed_pairs_returns_copies() -> void:
	var table: FactionTable = _table_from(_doc())
	var pairs: Array[Dictionary] = table.listed_pairs()
	pairs[0]["relation"] = Factions.Relation.FRIENDLY
	pairs.clear()
	assert_eq(table.listed_pairs().size(), 1)
	assert_eq(table.listed_pairs()[0]["relation"], Factions.Relation.HOSTILE)
	assert_eq(table.listed_pairs()[0]["a"], EA)
	assert_eq(table.listed_pairs()[0]["b"], RA)


func test_tables_do_not_share_state() -> void:
	var one: FactionTable = _table_from(_doc())
	var two: FactionTable = _table_from(_doc())
	one.set_relation(EA, RA, Factions.Relation.FRIENDLY)
	assert_eq(two.relation(EA, RA), Factions.Relation.HOSTILE)
