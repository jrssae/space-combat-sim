class_name MenuScreens
extends RefCounted
## Where the front end and the pause menu get the pages they share (architecture §18, D57).

const SettingsScene: PackedScene = preload("res://src/frontend/settings_screen.tscn")
const ControlsScene: PackedScene = preload("res://src/frontend/controls_screen.tscn")


## The settings page (M5-T03): a new one each time, like the controls page.
static func settings() -> MenuScreen:
	return SettingsScene.instantiate() as MenuScreen


## The controls page (M5-T04): a new one each time, so a page left open elsewhere is never shared.
static func controls() -> MenuScreen:
	return ControlsScene.instantiate() as MenuScreen
