extends GutTest
## The console key opens the debug console on the real main scene, in free flight and in the station showcase, for the key as
## Wayland reports it on an ISO keyboard (physical 167, the section sign, typing a backtick) as well as the ANSI backquote
## (M7-T39: the console had stopped opening on the maintainer's keyboard).

const SHOWCASE: String = "res://data/scenarios/station_showcase.json"
const FREE_FLIGHT: String = "res://data/scenarios/free_flight.json"

var main: Main


func before_each() -> void:
	get_tree().paused = false
	if DebugConsole.is_open():
		DebugConsole.close()


func after_each() -> void:
	if DebugConsole.is_open():
		DebugConsole.close()
	get_tree().paused = false


func _start(scenario: String) -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = scenario
	main.raider_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame


# One tap of the key as a real keyboard sends it.
func _tap(physical: Key) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = physical
	down.keycode = KEY_QUOTELEFT
	down.key_label = KEY_QUOTELEFT
	down.unicode = 96
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	var up := down.duplicate() as InputEventKey
	up.pressed = false
	up.unicode = 0
	Input.parse_input_event(up)
	Input.flush_buffered_events()


func _opens_and_closes(physical: Key) -> void:
	_tap(physical)
	assert_true(DebugConsole.is_open(), "the key opens the console")
	_tap(physical)
	assert_false(DebugConsole.is_open(), "the key closes it again")


func test_ansi_backquote_in_free_flight() -> void:
	await _start(FREE_FLIGHT)
	_opens_and_closes(KEY_QUOTELEFT)


func test_iso_section_key_in_free_flight() -> void:
	await _start(FREE_FLIGHT)
	_opens_and_closes(KEY_SECTION)


func test_ansi_backquote_in_the_station_showcase() -> void:
	await _start(SHOWCASE)
	_opens_and_closes(KEY_QUOTELEFT)


func test_iso_section_key_in_the_station_showcase() -> void:
	await _start(SHOWCASE)
	_opens_and_closes(KEY_SECTION)

