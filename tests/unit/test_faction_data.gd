extends GutTest
## The fourteen factions as data (M10-T02, D12.3, Q8, Q12): the shipped relations, the profiles hulls read, a scenario's
## overrides and the renegades' marking.

const EA: StringName = &"earth_alliance"
const RENEGADES: StringName = &"renegades"
const RAIDERS: StringName = &"raiders"
const SHADOWS: StringName = &"shadows"
const DRAKH: StringName = &"drakh"
const VORLONS: StringName = &"vorlons"

var _table: FactionTable


func before_each() -> void:
	Factions.reset()
	_table = FactionTable.load_file(Factions.TABLE_PATH)["table"]


func after_each() -> void:
	Factions.reset()


func _rel(a: StringName, b: StringName) -> Factions.Relation:
	return _table.relation(a, b)


func test_every_faction_is_hostile_to_the_raiders_but_the_neutral_one() -> void:
	for id: StringName in _table.ids():
		if id == RAIDERS or id == &"neutral":
			continue
		assert_eq(_rel(id, RAIDERS), Factions.Relation.HOSTILE, String(id))


func test_the_renegades_are_hostile_to_the_alliance_and_to_nobody_else_but_the_raiders() -> void:
	assert_eq(_rel(RENEGADES, EA), Factions.Relation.HOSTILE)
	for id: StringName in [&"narn", &"centauri", &"minbari", &"drazi", &"brakiri", &"vree", &"isa", &"neutral"]:
		assert_eq(_rel(RENEGADES, id), Factions.Relation.NEUTRAL, String(id))


func test_the_shadows_and_the_drakh_are_hostile_to_every_people_but_each_other() -> void:
	assert_eq(_rel(SHADOWS, DRAKH), Factions.Relation.FRIENDLY)
	for ancient: StringName in [SHADOWS, DRAKH]:
		for id: StringName in _table.ids():
			if id == SHADOWS or id == DRAKH or id == &"neutral":
				continue
			assert_eq(_rel(ancient, id), Factions.Relation.HOSTILE, "%s against %s" % [ancient, id])


func test_the_vorlons_are_hostile_to_the_shadows_and_the_drakh_only() -> void:
	assert_eq(_rel(VORLONS, SHADOWS), Factions.Relation.HOSTILE)
	assert_eq(_rel(VORLONS, DRAKH), Factions.Relation.HOSTILE)
	for id: StringName in [EA, &"narn", &"centauri", &"minbari", &"drazi", &"brakiri", &"vree", &"isa", RENEGADES]:
		assert_eq(_rel(VORLONS, id), Factions.Relation.NEUTRAL, String(id))


func test_the_other_pairs_are_neutral() -> void:
	assert_eq(_rel(&"narn", &"centauri"), Factions.Relation.NEUTRAL)
	assert_eq(_rel(EA, &"minbari"), Factions.Relation.NEUTRAL)
	assert_eq(_rel(EA, &"neutral"), Factions.Relation.NEUTRAL)


func test_the_profiles_name_style_fighters_weapons_and_mine() -> void:
	assert_eq(_table.style(EA), "earthforce")
	assert_eq(_table.style(SHADOWS), "shadow")
	assert_eq(_table.fighters(&"narn"), [&"narn_frazi"] as Array[StringName])
	assert_true(_table.weapons(&"narn").has(&"narn_heavy_laser"))
	assert_eq(_table.mine(&"narn"), "narn_mine")
	assert_eq(_table.battle_mine(&"narn"), "narn_energy_mine")
	assert_eq(_table.battle_mine(&"centauri"), "centauri_guided_mine")
	assert_eq(_table.mine(RAIDERS), "")


func test_the_renegades_fly_the_alliance_hulls_with_their_own_marking() -> void:
	assert_eq(_table.fighters(RENEGADES), _table.fighters(EA))
	assert_eq(_table.weapons(RENEGADES), _table.weapons(EA))
	assert_eq(_table.marking(RENEGADES), "renegades")
	assert_eq(_table.marking(EA), "")


func test_an_unlisted_faction_has_an_empty_profile() -> void:
	assert_eq(_table.style(&"pirates"), "")
	assert_true(_table.fighters(&"pirates").is_empty())
	assert_eq(_table.marking(&"pirates"), "")


func test_a_bad_profile_key_is_refused_with_its_path() -> void:
	var doc: Dictionary = {"factions": [{"id": "a", "name": "A", "fighters": "no"}], "relations": [], "default": "neutral"}
	var result: Dictionary = FactionTable.from_dict(doc)
	assert_false(result["ok"])
	assert_string_contains(String(result["error"]), "factions[0].fighters must be an array")
	doc["factions"] = [{"id": "a", "name": "A", "style": "Bad Style"}]
	assert_string_contains(String(FactionTable.from_dict(doc)["error"]), "factions[0].style")


func test_overrides_are_checked_against_the_listed_factions() -> void:
	var good: Variant = _table.overrides_from([{"a": "narn", "b": "centauri", "relation": "hostile"}])
	assert_true(good is Array)
	assert_eq((good as Array[Dictionary])[0]["relation"], Factions.Relation.HOSTILE)
	assert_string_contains(String(_table.overrides_from([{"a": "narn", "b": "nobody", "relation": "hostile"}])), "relations[0].b")
	assert_string_contains(String(_table.overrides_from([{"a": "narn", "b": "narn", "relation": "hostile"}])), "itself")
	assert_string_contains(String(_table.overrides_from([{"a": "narn", "b": "drazi", "relation": "war"}])), "relation must be one of")
	assert_string_contains(String(_table.overrides_from("x")), "must be an array")


func test_a_scenario_override_lasts_until_the_next_scenario() -> void:
	var pairs: Array[Dictionary] = [{"a": &"narn", "b": &"centauri", "relation": Factions.Relation.HOSTILE}]
	Factions.apply_overrides(pairs)
	assert_true(Factions.is_hostile(&"narn", &"centauri"))
	Factions.apply_overrides([] as Array[Dictionary])
	assert_false(Factions.is_hostile(&"narn", &"centauri"), "the next scenario starts from the file")


func test_an_empty_override_leaves_a_session_edit_alone() -> void:
	Factions.table().set_relation(&"narn", &"centauri", Factions.Relation.FRIENDLY)
	Factions.apply_overrides([] as Array[Dictionary])
	assert_eq(Factions.relation(&"narn", &"centauri"), Factions.Relation.FRIENDLY)


func test_a_scenario_file_may_carry_relations() -> void:
	var text: String = JSON.stringify({"scenario_id": "t", "player": {"position": [0, 0, 0]},
			"relations": [{"a": "narn", "b": "centauri", "relation": "hostile"}]})
	var scenario: Dictionary = ScenarioLoader.parse(text)
	assert_true(scenario["ok"], String(scenario["error"]))
	assert_eq((scenario["relations"] as Array[Dictionary]).size(), 1)
	var bad: Dictionary = ScenarioLoader.parse(text.replace("centauri", "nobody"))
	assert_false(bad["ok"])
	assert_string_contains(String(bad["error"]), "relations[0].b")


func test_a_marking_is_the_named_row_or_nothing() -> void:
	var section: Dictionary = {"liveries": {"renegades": {"primary": [0.5, 0.0, 0.0], "secondary": [0.1, 0.1, 0.1],
			"number_colour": [1, 1, 1], "pattern": "plain", "numbers": []}}, "patterns": {"plain": []}, "number_fields": {}}
	assert_null(Livery.for_marking("", section))
	assert_null(Livery.for_marking("renegades", {"liveries": {}}), "a hull without the row keeps its own paint")
	var marked: Livery = Livery.for_marking("renegades", section)
	assert_not_null(marked)
	assert_eq(marked.number, 0)
	assert_eq(marked.primary.r, 0.5)
