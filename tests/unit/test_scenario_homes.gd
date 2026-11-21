extends GutTest
## Home docks in scenario data (M8-T06; maintainer, 2026-11-18): `home` on the player, a wing and a spawn names the dock a
## fighter belongs to; a spawn's own word goes before its wing's, and "none" assigns it to nothing on purpose.


func _data(player_home: Variant, wing_home: Variant, member_home: Variant) -> Dictionary:
	var player: Dictionary = {"position": [0, 0, 0], "forward": [0, 0, -1]}
	if player_home != null:
		player["home"] = player_home
	var member: Dictionary = {"type": "starfury_ally", "name": "ALPHA 2", "anchor": "player", "offset": [-60, 0, 40],
			"behaviour": {"type": "ai", "profile": "ally_starfury"}}
	if member_home != null:
		member["home"] = member_home
	var wing: Dictionary = {"name": "ALPHA", "leader": "player", "members": [member]}
	if wing_home != null:
		wing["home"] = wing_home
	return {"scenario_id": "case", "player": player, "pools": {"starfury_ally": 1}, "wings": [wing]}


func test_homes_are_read_from_the_player_the_wing_and_the_spawn() -> void:
	var result: Dictionary = ScenarioLoader.from_data(_data("Babylon5", "babylon5", "Hyperion"), "case")
	assert_true(result["ok"], str(result["error"]))
	assert_eq(result["player"]["home"], &"babylon5", "ids are lower case")
	assert_eq(result["wings"][0]["home"], &"babylon5")
	var spawn: Dictionary = result["spawns"][0]
	assert_eq(spawn["home"], &"hyperion")
	assert_true(spawn["home_set"], "the spawn said so itself")


func test_without_a_word_nobody_has_a_home() -> void:
	var result: Dictionary = ScenarioLoader.from_data(_data(null, null, null), "case")
	assert_true(result["ok"], str(result["error"]))
	assert_eq(result["player"]["home"], &"")
	assert_eq(result["wings"][0]["home"], &"")
	assert_eq(result["spawns"][0]["home"], &"")
	assert_false(result["spawns"][0]["home_set"], "left to its wing or its launch")


func test_none_assigns_a_spawn_to_nothing_on_purpose() -> void:
	var result: Dictionary = ScenarioLoader.from_data(_data("babylon5", "babylon5", "none"), "case")
	assert_true(result["ok"], str(result["error"]))
	assert_eq(result["spawns"][0]["home"], &"")
	assert_true(result["spawns"][0]["home_set"], "so its wing's home does not reach it")


func test_a_home_that_is_not_a_word_is_refused() -> void:
	for bad: Array in [[7, "babylon5", "babylon5", "player.home"], ["babylon5", 7, "babylon5", "wings[0].home"],
			["babylon5", "babylon5", 7, "home must be"]]:
		var result: Dictionary = ScenarioLoader.from_data(_data(bad[0], bad[1], bad[2]), "case")
		assert_false(result["ok"])
		assert_string_contains(result["error"], bad[3])


func test_a_ship_takes_its_wings_home_unless_the_scenario_gave_it_one() -> void:
	var wing := Wing.new()
	wing.home = &"babylon5"
	var plain := Combatant.new()
	WingDirector.give_home(wing, plain)
	assert_eq(plain.home, &"babylon5")
	var assigned := Combatant.new()
	assigned.home = &"hyperion"
	assigned.home_assigned = true
	WingDirector.give_home(wing, assigned)
	assert_eq(assigned.home, &"hyperion", "the scenario's word stands")
	var nothing := Combatant.new()
	nothing.home_assigned = true
	WingDirector.give_home(wing, nothing)
	assert_eq(nothing.home, &"", "assigned to nothing, it stays so")
	var homeless := Wing.new()
	var kept := Combatant.new()
	kept.home = &"babylon5"
	WingDirector.give_home(homeless, kept)
	assert_eq(kept.home, &"babylon5", "a wing without a home takes none away")


func test_the_shipped_station_scenarios_give_the_player_a_home() -> void:
	for path: String in [ScenarioLoader.FREE_FLIGHT_PATH, "res://data/scenarios/station_dock.json"]:
		var result: Dictionary = ScenarioLoader.load(path)
		assert_true(result["ok"], str(result["error"]))
		assert_eq(result["player"]["home"], Station.HOME_ID, path)
