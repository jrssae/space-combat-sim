class_name SettingsGroupsScreen
extends ChoiceListScreen
## The Settings list (M5-T45): the five groups of `SettingsSchema.GROUPS`, each opening its page. Controls opens the controls
## page (profiles and rebinding, with the controls settings inside it); the others open a `SettingsScreen` for their categories.
## Both the start screen and the pause menu push this page, so they offer the same five.


func _init() -> void:
	var entries: Array[Dictionary] = []
	for group: Dictionary in SettingsSchema.GROUPS:
		entries.append({"id": group["id"], "text": group["title"],
				"info": ObjectivesModel.briefing(String(group["title"]), String(group["help"]))})
	setup("Settings", entries)
	add_back_option()
	chosen.connect(_on_chosen)


func _on_chosen(id: StringName) -> void:
	push_requested.emit(MenuScreens.controls() if id == &"controls" else MenuScreens.settings_screen(id))
