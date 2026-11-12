extends GutTest
## The four audio buses (M5-T03, D57; AC3): Master, SFX, UI and Comms exist; the menu's sounds play on UI, the radio on Comms
## and everything else on SFX; each bus follows its volume setting the moment it changes.

var audio: AudioDirector
var _backup: Dictionary = {}


func before_each() -> void:
	for key: StringName in [&"master_volume", &"sfx_volume", &"ui_volume", &"comms_volume"]:
		_backup[key] = Settings.get_value(key)
	audio = AudioDirector.new()
	add_child_autofree(audio)
	await wait_process_frames(1)


func after_each() -> void:
	for key: StringName in _backup:
		Settings.set_value(key, _backup[key])


func _db(bus: StringName) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus))


func test_the_layout_has_the_four_buses_sending_to_master() -> void:
	for bus: StringName in AudioBuses.NAMES:
		assert_gte(AudioServer.get_bus_index(bus), 0, "%s exists" % bus)
	assert_eq(AudioServer.get_bus_index(&"Master"), 0)
	for bus: StringName in [&"SFX", &"UI", &"Comms"]:
		assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index(bus)), &"Master", "%s plays through Master" % bus)


func test_the_layout_file_defines_all_four() -> void:
	var layout := load("res://default_bus_layout.tres") as AudioBusLayout
	assert_not_null(layout)
	assert_eq(layout.get("bus/1/name"), &"SFX")
	assert_eq(layout.get("bus/2/name"), &"UI")
	assert_eq(layout.get("bus/3/name"), &"Comms")


func test_the_buses_start_at_their_settings() -> void:
	Settings.set_value(&"master_volume", 0.5)
	Settings.set_value(&"ui_volume", 0.25)
	audio.apply_all_volumes()
	assert_almost_eq(_db(&"Master"), linear_to_db(0.5), 1e-4)
	assert_almost_eq(_db(&"UI"), linear_to_db(0.25), 1e-4)


func test_a_volume_change_applies_live_to_its_own_bus() -> void:
	Settings.set_value(&"master_volume", 1.0)
	Settings.set_value(&"sfx_volume", 1.0)
	Settings.set_value(&"ui_volume", 1.0)
	Settings.set_value(&"comms_volume", 1.0)
	Settings.set_value(&"ui_volume", 0.5)
	assert_almost_eq(_db(&"UI"), linear_to_db(0.5), 1e-4)
	assert_almost_eq(_db(&"SFX"), 0.0, 1e-4, "the other buses stay put")
	assert_almost_eq(_db(&"Comms"), 0.0, 1e-4)
	Settings.set_value(&"comms_volume", 0.1)
	assert_almost_eq(_db(&"Comms"), linear_to_db(0.1), 1e-4)
	Settings.set_value(&"sfx_volume", 0.2)
	assert_almost_eq(_db(&"SFX"), linear_to_db(0.2), 1e-4)
	Settings.set_value(&"master_volume", 0.0)
	assert_eq(_db(&"Master"), AudioBuses.SILENT_DB, "zero is silent")
	assert_almost_eq(_db(&"UI"), linear_to_db(0.5), 1e-4, "Master is a bus of its own: the others keep their gain")


func test_menu_sounds_play_on_the_ui_bus() -> void:
	for sound: StringName in [&"ui_move", &"ui_accept", &"ui_back"]:
		var voice: AudioStreamPlayer = audio.play_ui(sound)
		assert_not_null(voice, String(sound))
		assert_eq(voice.bus, &"UI", String(sound))


func test_other_two_d_sounds_stay_on_sfx() -> void:
	var blip: AudioStreamPlayer = audio.play_ui(&"target_blip")
	assert_not_null(blip)
	assert_eq(blip.bus, &"SFX", "the cockpit's blip is not a menu sound")


func test_play_comms_plays_on_the_comms_bus() -> void:
	var voice: AudioStreamPlayer = audio.play_comms(&"ui_accept")
	assert_not_null(voice)
	assert_eq(voice.bus, &"Comms")
	assert_true(voice.playing)
	assert_null(audio.play_comms(&"no_such_sound"), "an unknown sound is ignored")


func test_a_radio_sound_through_play_ui_still_lands_on_comms() -> void:
	if not audio.has_sound(&"radio_open"):
		pending("radio_open arrives with M5-T06's sfx_ui")
		return
	assert_eq(audio.play_ui(&"radio_open").bus, &"Comms")
	assert_eq(audio.play_ui(&"radio_close").bus, &"Comms")


func test_a_reused_voice_takes_the_bus_of_its_new_sound() -> void:
	for i: int in AudioDirector.UI_VOICES:
		audio.play_comms(&"ui_move")
	var voice: AudioStreamPlayer = audio.play_ui(&"ui_accept")
	assert_eq(voice.bus, &"UI", "a voice that carried radio last time now carries a menu sound")


func test_three_d_voices_stay_on_sfx() -> void:
	var voice: AudioStreamPlayer3D = audio.play(&"pulse_fire", Vector3.ZERO)
	assert_not_null(voice)
	assert_eq(voice.bus, &"SFX")
