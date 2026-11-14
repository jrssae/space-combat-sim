class_name NewGameSelect
extends ChoiceListScreen
## The New game list (M5-T45): the missions of the `MissionCatalog` first, then the sandbox scenes. Until a campaign exists this
## is the one place a run with a goal or a test arena is picked. The highlighted entry's briefing (a mission) or one-line
## description (a scene, the `description` of its scenario file) shows under the list.

const SCENES: Array[Dictionary] = [
	{"id": &"combat_sandbox", "text": "Combat sandbox"},
	{"id": &"dogfight", "text": "Dogfight"},
	{"id": &"instructor_route", "text": "Instructor route"},
	{"id": &"civilian_showcase", "text": "Civilian ships"},
	{"id": &"station_showcase", "text": "Babylon 5 station"},
]

var _missions: Dictionary = {}  # id -> true, for `is_mission`


## `missions` are `MissionCatalog.entries`; `describe` turns a scene id into its description (`scene_description` by default).
func setup_new_game(missions: Array[Dictionary], describe: Callable = Callable()) -> void:
	var entries: Array[Dictionary] = []
	for mission: Dictionary in missions:
		_missions[mission["id"]] = true
		entries.append({"id": mission["id"], "text": mission["title"],
				"info": ObjectivesModel.briefing(String(mission["title"]), String(mission["briefing"]))})
	for scene: Dictionary in SCENES:
		var text: String = String(describe.call(scene["id"])) if describe.is_valid() else scene_description(scene["id"])
		entries.append({"id": scene["id"], "text": scene["text"], "info": ObjectivesModel.briefing(String(scene["text"]), text)})
	setup("New game", entries)
	add_back_option()
	show_pad = false
	show_right = false


func is_mission(id: StringName) -> bool:
	return _missions.has(id)


## The `description` line a scenario file carries, or "" when it has none.
static func scene_description(scenario_id: StringName) -> String:
	var file := FileAccess.open(GameFlow.scenario_path(scenario_id), FileAccess.READ)
	if file == null:
		return ""
	var data: Variant = JSON.parse_string(file.get_as_text())
	return String((data as Dictionary).get("description", "")) if data is Dictionary else ""
