class_name FreeFlightSelect
extends MenuScreen
## The front end's Free flight page (architecture §18, D57): three switches (civilian traffic, allied patrols, enemy encounters),
## then Start. Each starts from its setting (on by default) and keeps the player's choice there; any combination works and all
## off is an empty sky (M8-T28).

signal start_requested(encounters: bool)

const SWITCHES: Array[Dictionary] = [
	{"key": &"encounters_civilian", "label": "Civilian traffic"},
	{"key": &"encounters_allied", "label": "Allied patrols"},
	{"key": &"encounters_enemy", "label": "Enemy encounters"},
]

var _buttons: Dictionary = {}


func setup_free_flight() -> void:
	title = "Free flight"
	compact = true
	wide_right = true
	for entry: Dictionary in SWITCHES:
		var key: StringName = entry["key"]
		_buttons[key] = add_option("", func() -> void: _toggle(key))
		_refresh(key)
	add_option("Start", func() -> void: start_requested.emit(any_on()))
	add_back_option()


## Whether any switch is on: the request's `encounters` flag, which tells the scene to start its director.
func any_on() -> bool:
	for entry: Dictionary in SWITCHES:
		if bool(Settings.get_value(entry["key"])):
			return true
	return false


## The right panel says what the switches mean.
func info() -> Dictionary:
	return ObjectivesModel.briefing("Free flight",
			"Fly the nav buoys at your own pace.\nCivilian traffic: neutral ships, and the station's docking queues and gate runs.\nAllied patrols: Starfuries passing through.\nEnemy encounters: raiders and their carriers.\nAll off is an empty sky.")


func _toggle(key: StringName) -> void:
	Settings.set_value(key, not bool(Settings.get_value(key)))
	_refresh(key)


func _refresh(key: StringName) -> void:
	for entry: Dictionary in SWITCHES:
		if entry["key"] == key:
			(_buttons[key] as Button).text = "%s: %s" % [entry["label"], "on" if bool(Settings.get_value(key)) else "off"]
