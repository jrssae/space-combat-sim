extends GutTest
## The transponder rules (M10-T02): what a disguised ship shows and what gives it away.


func test_a_disguised_ship_shows_its_broadcast_to_everyone_but_its_own_side() -> void:
	assert_eq(Transponder.seen_faction(&"renegades", &"earth_alliance", &"earth_alliance"), &"earth_alliance")
	assert_eq(Transponder.seen_faction(&"renegades", &"earth_alliance", &"raiders"), &"earth_alliance")
	assert_eq(Transponder.seen_faction(&"renegades", &"earth_alliance", &"renegades"), &"renegades", "its own side knows it")
	assert_eq(Transponder.seen_faction(&"renegades", &"", &"earth_alliance"), &"renegades", "revealed, or never disguised")


func test_firing_on_the_player_or_the_broadcast_side_or_its_friends_gives_it_away() -> void:
	assert_true(Transponder.is_hostile_act(&"earth_alliance", &"earth_alliance", false))
	assert_true(Transponder.is_hostile_act(&"earth_alliance", &"neutral", true), "the player, whatever its faction")
	assert_false(Transponder.is_hostile_act(&"earth_alliance", &"raiders", false), "raiders are no friend of the Earth Alliance")
	assert_false(Transponder.is_hostile_act(&"earth_alliance", &"renegades", false), "its own side is not a victim")


func test_the_shipped_renegades_broadcast_earth_alliance_and_nobody_else_does() -> void:
	var table: FactionTable = Factions.table()
	assert_eq(table.transponder(&"renegades"), &"earth_alliance")
	assert_eq(table.transponder(&"earth_alliance"), &"")
	assert_eq(table.transponder(&"raiders"), &"")
	assert_eq(table.transponder(&"nobody"), &"", "an unlisted faction broadcasts its own")


func test_a_transponder_must_name_another_listed_faction() -> void:
	var good: Dictionary = {"factions": [{"id": "a", "name": "A", "transponder": "b"}, {"id": "b", "name": "B"}],
			"relations": [], "default": "neutral"}
	assert_true(bool(FactionTable.from_dict(good)["ok"]))
	good["factions"][0]["transponder"] = "a"
	assert_false(bool(FactionTable.from_dict(good)["ok"]), "itself")
	good["factions"][0]["transponder"] = "zzz"
	assert_false(bool(FactionTable.from_dict(good)["ok"]), "an unlisted id")


func test_the_command_reveals_and_hides_only_ships_that_broadcast() -> void:
	var renegade := Targetable.new()
	add_child_autofree(renegade)
	renegade.faction = &"renegades"
	renegade.disguise_as(&"earth_alliance")
	var ally := Targetable.new()
	add_child_autofree(ally)
	ally.faction = &"earth_alliance"
	var shown: Array[Targetable] = [renegade, ally, null]
	assert_string_contains(TransponderConsole.apply(&"reveal", shown).text(), "1 ship changed")
	assert_false(renegade.is_disguised())
	assert_eq(renegade.to_target_info().faction, &"renegades", "revealed it shows its true faction")
	assert_string_contains(TransponderConsole.apply(&"hide", shown).text(), "1 ship changed")
	assert_eq(renegade.to_target_info().faction, &"earth_alliance", "disguised it shows the Earth Alliance's")
	assert_eq(renegade.faction_seen_by(&"renegades"), &"renegades")
	assert_eq(ally.to_target_info().faction, &"earth_alliance")
