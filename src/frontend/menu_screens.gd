class_name MenuScreens
extends RefCounted
## Where the front end and the pause menu get the pages they share (architecture §18, D57).

const SettingsScene: PackedScene = preload("res://src/frontend/settings_screen.tscn")
const ControlsScene: PackedScene = preload("res://src/frontend/controls_screen.tscn")


## The Settings list (M5-T45): the five groups, each opening its page. A new one each time.
static func settings() -> MenuScreen:
	return SettingsGroupsScreen.new()


## One settings page (M5-T03): a new one each time. `group` is an id of `SettingsSchema.GROUPS`; empty lists every setting.
static func settings_screen(group: StringName = &"") -> MenuScreen:
	var page: SettingsScreen = SettingsScene.instantiate() as SettingsScreen
	page.group = group
	return page


## The controls page (M5-T04): a new one each time, so a page left open elsewhere is never shared.
static func controls() -> MenuScreen:
	return ControlsScene.instantiate() as MenuScreen
