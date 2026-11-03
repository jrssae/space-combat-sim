class_name MenuScreens
extends RefCounted
## Where the front end and the pause menu get the pages they share (architecture §18, D57). Settings and Controls are
## placeholders until M5-T03 and M5-T04 return their real pages from here; neither host changes.


static func settings() -> MenuScreen:
	var page := PlaceholderScreen.new()
	page.setup_placeholder("Settings", "The settings page arrives with M5-T03.")
	return page


static func controls() -> MenuScreen:
	var page := PlaceholderScreen.new()
	page.setup_placeholder("Controls", "The controls page arrives with M5-T04.")
	return page
