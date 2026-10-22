extends GutTest
## Factions (architecture §15.1 D25, AC1; §16 D30, M3 AC2): the relation table, the hostility query and the HUD colours,
## and the active table behind them (loaded from data/factions.json, swappable, resettable).

const ALL_KNOWN: Array[StringName] = [Factions.EARTH_ALLIANCE, Factions.RAIDERS, Factions.NEUTRAL]


func after_each() -> void:
	Factions.reset()  # the table is process-wide: no test may leak a swapped or edited one


func test_faction_ids() -> void:
	assert_eq(Factions.EARTH_ALLIANCE, &"earth_alliance")
	assert_eq(Factions.RAIDERS, &"raiders")
	assert_eq(Factions.NEUTRAL, &"neutral")


func test_relation_table() -> void:
	var friendly: int = Factions.Relation.FRIENDLY
	var neutral: int = Factions.Relation.NEUTRAL
	var hostile: int = Factions.Relation.HOSTILE
	# Rows: self faction; columns: other faction, in ALL_KNOWN order (earth_alliance, raiders, neutral).
	var table: Array = [
		[friendly, hostile, neutral],
		[hostile, friendly, neutral],
		[neutral, neutral, friendly],
	]
	for row: int in ALL_KNOWN.size():
		for column: int in ALL_KNOWN.size():
			assert_eq(int(Factions.relation(ALL_KNOWN[row], ALL_KNOWN[column])), (table[row] as Array)[column],
					"%s vs %s" % [ALL_KNOWN[row], ALL_KNOWN[column]])


func test_relation_is_symmetric() -> void:
	var ids: Array[StringName] = [Factions.EARTH_ALLIANCE, Factions.RAIDERS, Factions.NEUTRAL, &"pirates", &""]
	for a: StringName in ids:
		for b: StringName in ids:
			assert_eq(Factions.relation(a, b), Factions.relation(b, a), "%s vs %s" % [a, b])


func test_same_faction_is_friendly() -> void:
	assert_eq(Factions.relation(Factions.EARTH_ALLIANCE, Factions.EARTH_ALLIANCE), Factions.Relation.FRIENDLY)
	assert_eq(Factions.relation(Factions.RAIDERS, Factions.RAIDERS), Factions.Relation.FRIENDLY)
	assert_eq(Factions.relation(&"pirates", &"pirates"), Factions.Relation.FRIENDLY)


func test_unknown_faction_is_neutral_against_everyone_else() -> void:
	for other: StringName in ALL_KNOWN:
		assert_eq(Factions.relation(&"pirates", other), Factions.Relation.NEUTRAL, "pirates vs %s" % other)
		assert_eq(Factions.relation(&"", other), Factions.Relation.NEUTRAL, "empty vs %s" % other)
	assert_eq(Factions.relation(&"pirates", &"smugglers"), Factions.Relation.NEUTRAL)


func test_is_hostile_only_for_earth_alliance_against_raiders() -> void:
	assert_true(Factions.is_hostile(Factions.EARTH_ALLIANCE, Factions.RAIDERS))
	assert_true(Factions.is_hostile(Factions.RAIDERS, Factions.EARTH_ALLIANCE))
	var others: Array[StringName] = [Factions.NEUTRAL, &"pirates", &""]
	for faction: StringName in [Factions.EARTH_ALLIANCE, Factions.RAIDERS]:
		assert_false(Factions.is_hostile(faction, faction), "%s vs itself" % faction)
		for other: StringName in others:
			assert_false(Factions.is_hostile(faction, other), "%s vs %s" % [faction, other])
			assert_false(Factions.is_hostile(other, faction), "%s vs %s" % [other, faction])
	assert_false(Factions.is_hostile(Factions.NEUTRAL, Factions.NEUTRAL))


func test_string_ids_work_like_string_names() -> void:
	assert_true(Factions.is_hostile("earth_alliance", "raiders"))
	assert_eq(Factions.relation("neutral", "raiders"), Factions.Relation.NEUTRAL)


func test_is_known() -> void:
	for faction: StringName in ALL_KNOWN:
		assert_true(Factions.is_known(faction), str(faction))
	assert_false(Factions.is_known(&"pirates"))
	assert_false(Factions.is_known(&""))


func test_hud_colors_follow_the_maintainer_answer() -> void:
	assert_eq(Factions.hud_color(Factions.Relation.HOSTILE), Color(1.0, 0.35, 0.25), "hostile red")
	assert_eq(Factions.hud_color(Factions.Relation.NEUTRAL), Color(1.0, 0.85, 0.25), "neutral/unknown yellow")
	assert_eq(Factions.hud_color(Factions.Relation.FRIENDLY), Color(0.45, 0.7, 1.0), "friendly blue")


func test_hud_colors_are_distinct_and_line_work_stays_green() -> void:
	var colors: Array[Color] = []
	for rel: Factions.Relation in Factions.Relation.values():
		colors.append(Factions.hud_color(rel))
	assert_eq(colors.size(), 3)
	assert_ne(colors[0], colors[1])
	assert_ne(colors[0], colors[2])
	assert_ne(colors[1], colors[2])
	assert_eq(Factions.HUD_LINE_COLOR, Color(0.55, 1.0, 0.6))
	for color: Color in colors:
		assert_ne(color, Factions.HUD_LINE_COLOR, "faction colours never reuse the HUD line green")


func test_hud_color_of_an_unlisted_relation_is_the_neutral_yellow() -> void:
	assert_eq(Factions.hud_color((-1) as Factions.Relation), Factions.NEUTRAL_COLOR)
	assert_eq(Factions.hud_color(99 as Factions.Relation), Factions.NEUTRAL_COLOR)


func test_hud_color_through_the_relation_query() -> void:
	# What the HUD does for a raider seen from a Starfury, a buoy and an unknown contact.
	var own: StringName = Factions.EARTH_ALLIANCE
	assert_eq(Factions.hud_color(Factions.relation(own, Factions.RAIDERS)), Factions.HOSTILE_COLOR)
	assert_eq(Factions.hud_color(Factions.relation(own, Factions.NEUTRAL)), Factions.NEUTRAL_COLOR)
	assert_eq(Factions.hud_color(Factions.relation(own, &"pirates")), Factions.NEUTRAL_COLOR)
	assert_eq(Factions.hud_color(Factions.relation(own, own)), Factions.FRIENDLY_COLOR)


# --- the active table (M3-T02, D30) ----------------------------------------------------------------------------


func _doc_with(relation: String) -> Dictionary:
	return {
		"factions": [{"id": "earth_alliance", "name": "Earth Alliance"}, {"id": "raiders", "name": "Raiders"},
				{"id": "neutral", "name": "Neutral"}],
		"relations": [{"a": "earth_alliance", "b": "raiders", "relation": relation}],
		"default": "neutral",
	}


func test_the_active_table_is_loaded_lazily_from_the_data_file() -> void:
	Factions.reset()
	var table: FactionTable = Factions.table()
	assert_eq(table.ids(), ALL_KNOWN as Array[StringName])
	assert_eq(table.display_name(Factions.EARTH_ALLIANCE), "Earth Alliance")
	assert_same(Factions.table(), table, "loaded once, then reused")
	assert_true(Factions.is_hostile(Factions.EARTH_ALLIANCE, Factions.RAIDERS))


func test_use_table_swaps_the_rule_for_every_caller() -> void:
	var friendly_doc: Dictionary = _doc_with("friendly")
	Factions.use_table(FactionTable.from_dict(friendly_doc)["table"])
	assert_eq(Factions.relation(Factions.EARTH_ALLIANCE, Factions.RAIDERS), Factions.Relation.FRIENDLY)
	assert_false(Factions.is_hostile(Factions.EARTH_ALLIANCE, Factions.RAIDERS))
	assert_false(Factions.is_hostile(Factions.RAIDERS, Factions.EARTH_ALLIANCE))
	Factions.use_table(FactionTable.from_dict(_doc_with("hostile"))["table"])
	assert_true(Factions.is_hostile(Factions.RAIDERS, Factions.EARTH_ALLIANCE))


func test_a_table_with_another_faction_changes_what_is_known() -> void:
	var doc: Dictionary = _doc_with("hostile")
	(doc["factions"] as Array).append({"id": "pirates", "name": "Pirates"})
	(doc["relations"] as Array).append({"a": "pirates", "b": "raiders", "relation": "hostile"})
	Factions.use_table(FactionTable.from_dict(doc)["table"])
	assert_true(Factions.is_known(&"pirates"))
	assert_true(Factions.is_hostile(&"pirates", Factions.RAIDERS))
	assert_false(Factions.is_hostile(&"pirates", Factions.EARTH_ALLIANCE), "unlisted pair: the default")
	Factions.reset()
	assert_false(Factions.is_known(&"pirates"), "reset forgets the swapped table")
	assert_eq(Factions.relation(&"pirates", Factions.RAIDERS), Factions.Relation.NEUTRAL)


func test_reset_drops_session_changes_and_reloads_the_file() -> void:
	assert_eq(Factions.table().set_relation(Factions.EARTH_ALLIANCE, Factions.RAIDERS, Factions.Relation.NEUTRAL), "")
	assert_false(Factions.is_hostile(Factions.EARTH_ALLIANCE, Factions.RAIDERS))
	Factions.reset()
	assert_true(Factions.is_hostile(Factions.EARTH_ALLIANCE, Factions.RAIDERS), "the file says hostile")


func test_use_table_null_is_a_reset() -> void:
	Factions.use_table(FactionTable.from_dict(_doc_with("friendly"))["table"])
	Factions.use_table(null)
	assert_true(Factions.is_hostile(Factions.EARTH_ALLIANCE, Factions.RAIDERS))


func test_load_table_installs_a_valid_file() -> void:
	var path: String = "user://test_factions_valid.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(_doc_with("friendly")))
	file.close()
	assert_eq(Factions.load_table(path), "")
	assert_eq(Factions.relation(Factions.EARTH_ALLIANCE, Factions.RAIDERS), Factions.Relation.FRIENDLY)
	DirAccess.remove_absolute(path)


func test_a_broken_file_leaves_the_active_table_unchanged() -> void:
	Factions.use_table(FactionTable.from_dict(_doc_with("friendly"))["table"])
	var broken: Dictionary = _doc_with("hostile")
	((broken["relations"] as Array)[0] as Dictionary)["relation"] = "enemy"
	var path: String = "user://test_factions_broken.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(broken))
	file.close()
	var error: String = Factions.load_table(path)
	assert_string_contains(error, "relations[0].relation must be one of friendly|neutral|hostile")
	assert_string_starts_with(error, path)
	assert_eq(Factions.relation(Factions.EARTH_ALLIANCE, Factions.RAIDERS), Factions.Relation.FRIENDLY, "still the table in use")
	assert_ne(Factions.load_table("user://no_such_factions.json"), "")
	assert_eq(Factions.relation(Factions.EARTH_ALLIANCE, Factions.RAIDERS), Factions.Relation.FRIENDLY)
	DirAccess.remove_absolute(path)


func test_the_built_in_rule_matches_the_shipped_file_for_every_query() -> void:
	# What a broken file falls back to must read the same as the file at its defaults.
	var from_file: Array[int] = []
	var probes: Array[StringName] = [Factions.EARTH_ALLIANCE, Factions.RAIDERS, Factions.NEUTRAL, &"pirates", &""]
	for a: StringName in probes:
		for b: StringName in probes:
			from_file.append(Factions.relation(a, b))
	Factions.use_table(FactionTable.builtin())
	var index: int = 0
	for a: StringName in probes:
		for b: StringName in probes:
			assert_eq(Factions.relation(a, b), from_file[index], "%s vs %s" % [a, b])
			index += 1


func test_hud_colours_follow_a_changed_pair() -> void:
	# AC2: `relation earth_alliance raiders neutral` recolours the raiders yellow, `friendly` blue.
	var own: StringName = Factions.EARTH_ALLIANCE
	assert_eq(Factions.hud_color(Factions.relation(own, Factions.RAIDERS)), Factions.HOSTILE_COLOR)
	Factions.table().set_relation(own, Factions.RAIDERS, Factions.Relation.NEUTRAL)
	assert_eq(Factions.hud_color(Factions.relation(own, Factions.RAIDERS)), Factions.NEUTRAL_COLOR)
	Factions.table().set_relation(own, Factions.RAIDERS, Factions.Relation.FRIENDLY)
	assert_eq(Factions.hud_color(Factions.relation(own, Factions.RAIDERS)), Factions.FRIENDLY_COLOR)
