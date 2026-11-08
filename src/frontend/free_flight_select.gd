class_name FreeFlightSelect
extends MenuScreen
## The front end's Free flight page (architecture §18, D57): encounters on or off, then Start. Encounters are mixed traffic
## (raiders, allied patrols and neutral ships); the page starts from `Settings.encounters` (on by default) and keeps the
## player's choice there for the session (M5-T17).

signal start_requested(encounters: bool)

var encounters: bool = true

var _toggle: Button = null


func setup_free_flight() -> void:
	title = "Free flight"
	encounters = bool(Settings.get_value(&"encounters"))
	_toggle = add_option("", _on_toggle)
	_refresh_toggle()
	add_option("Start", func() -> void: start_requested.emit(encounters))
	add_back_option()


## The right panel says what the choice means.
func info() -> Dictionary:
	return ObjectivesModel.briefing("Free flight",
			"Fly the nav buoys at your own pace.\nEncounters add raiders, allied patrols and neutral traffic.")


func _on_toggle() -> void:
	encounters = not encounters
	Settings.set_value(&"encounters", encounters)
	_refresh_toggle()


func _refresh_toggle() -> void:
	_toggle.text = "Encounters: %s" % ("on" if encounters else "off")
