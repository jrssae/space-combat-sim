class_name MissionSelect
extends ChoiceListScreen
## The front end's Missions page (architecture §18, D57): one entry per mission the `MissionCatalog` found, the focused one's
## briefing on the right. With no missions it says so rather than showing an empty page.

const NONE_ID: StringName = &"none"


## `missions` are `MissionCatalog.entries`.
func setup_missions(missions: Array[Dictionary]) -> void:
	var entries: Array[Dictionary] = []
	for mission: Dictionary in missions:
		entries.append({"id": mission["id"], "text": mission["title"],
				"info": ObjectivesModel.briefing(String(mission["title"]), String(mission["briefing"]))})
	if entries.is_empty():
		entries.append({"id": NONE_ID, "text": "No missions yet", "enabled": false})
	setup("Missions", entries)
	add_back_option()
