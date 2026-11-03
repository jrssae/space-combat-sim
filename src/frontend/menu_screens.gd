class_name MenuScreens
extends RefCounted
## Where the front end and the pause menu get the pages they share (architecture §18, D57). Settings is a placeholder until
## M5-T03 returns its real page from here; neither host changes.

const ControlsScene: PackedScene = preload("res://src/frontend/controls_screen.tscn")


static func settings() -> MenuScreen:
	var page := PlaceholderScreen.new()
	page.setup_placeholder("Settings", "The settings page arrives with M5-T03.")
	return page


## The controls page (M5-T04): a new one each time, so a page left open elsewhere is never shared.
static func controls() -> MenuScreen:
	return ControlsScene.instantiate() as MenuScreen
