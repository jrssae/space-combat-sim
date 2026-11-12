extends GutTest
## MissionCatalog (architecture §18, D57): the missions the front end lists are the scenarios that carry a `mission` block,
## read through `ScenarioLoader`, never a hard-coded list. A scenario that does not load, or has no block, is not a mission.

const FIXTURES := "res://tests/fixtures/scenarios/"


## Stands in for the `mission` block that M5-T05 makes the loader pass through: the loader's own result plus the block
## read from the file, so the fixtures are listed exactly as the real data will be.
func _read(path: String) -> Dictionary:
	var result: Dictionary = ScenarioLoader.load(path)
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if bool(result.get("ok", false)) and raw is Dictionary and (raw as Dictionary).has("mission"):
		result["mission"] = (raw as Dictionary)["mission"]
	return result


func test_only_scenarios_with_a_mission_block_are_missions() -> void:
	var entries: Array[Dictionary] = MissionCatalog.entries(FIXTURES, _read)
	var ids: Array[StringName] = []
	for entry: Dictionary in entries:
		ids.append(entry["id"])
	assert_eq(ids, [&"mission_demo", &"mission_second"] as Array[StringName], "the plain and the broken scenario are left out, by id")


func test_an_entry_carries_the_title_and_the_briefing() -> void:
	var demo: Dictionary = MissionCatalog.entries(FIXTURES, _read)[0]
	assert_eq(demo["title"], "Demo Run")
	assert_eq(demo["briefing"], "Escort the freighter to the buoy.\nDo not let a raider through.")


func test_a_mission_with_no_title_is_named_from_its_id() -> void:
	var second: Dictionary = MissionCatalog.entries(FIXTURES, _read)[1]
	assert_eq(second["title"], "Mission Second")
	assert_eq(second["briefing"], "No title here.")


func test_an_empty_block_is_no_mission() -> void:
	var reads_empty: Callable = func(_path: String) -> Dictionary: return {"ok": true, "mission": {}}
	assert_eq(MissionCatalog.entries(FIXTURES, reads_empty).size(), 0, "the loader's way of saying a scenario has none")


func test_the_real_loader_feeds_the_default_reader() -> void:
	if not ScenarioLoader.load(FIXTURES + "mission_demo.json").has("mission"):
		pending("ScenarioLoader passes no `mission` block yet (M5-T05)")
		return
	var ids: Array[StringName] = []
	for entry: Dictionary in MissionCatalog.entries(FIXTURES):
		ids.append(entry["id"])
	assert_has(ids, &"mission_demo")
	assert_does_not_have(ids, &"mission_plain")


func test_no_missions_is_an_empty_list_not_an_error() -> void:
	assert_eq(MissionCatalog.entries("res://tests/fixtures/no_such_folder/", _read).size(), 0)
	var reads_nothing: Callable = func(_path: String) -> Dictionary: return {"ok": false, "error": "x"}
	assert_eq(MissionCatalog.entries(FIXTURES, reads_nothing).size(), 0)


func test_every_json_in_the_folder_is_offered_to_the_reader() -> void:
	var calls: Array[String] = []
	var spy: Callable = func(path: String) -> Dictionary:
		calls.append(path)
		return {"ok": true, "mission": {"title": "Spy"}}
	var entries: Array[Dictionary] = MissionCatalog.entries(FIXTURES, spy)
	assert_eq(calls.size(), 4, "every .json in the folder is offered to the reader")
	assert_eq(entries.size(), 4)
	# The shipped scenarios load through the real loader whatever they hold.
	for entry: Dictionary in MissionCatalog.entries():
		assert_true(entry.has("id") and entry.has("title") and entry.has("briefing"))
