extends GutTest
## AudioBuses (M5-T03, D57): which bus a sound plays on, which setting sets which bus, and the gain in dB.


func test_the_four_buses_and_their_settings() -> void:
	assert_eq(AudioBuses.NAMES, [&"Master", &"SFX", &"UI", &"Comms"] as Array[StringName])
	assert_eq(AudioBuses.setting_of(&"Master"), &"master_volume")
	assert_eq(AudioBuses.setting_of(&"SFX"), &"sfx_volume")
	assert_eq(AudioBuses.setting_of(&"UI"), &"ui_volume")
	assert_eq(AudioBuses.setting_of(&"Comms"), &"comms_volume")
	var schema := SettingsSchema.new()
	for bus: StringName in AudioBuses.NAMES:
		assert_true(schema.has_key(AudioBuses.setting_of(bus)), "%s has a setting in the schema" % bus)


func test_a_setting_names_its_bus() -> void:
	assert_eq(AudioBuses.bus_of_setting(&"ui_volume"), &"UI")
	assert_eq(AudioBuses.bus_of_setting(&"comms_volume"), &"Comms")
	assert_eq(AudioBuses.bus_of_setting(&"master_volume"), &"Master")
	assert_eq(AudioBuses.bus_of_setting(&"invert_y"), &"", "a setting that is not a volume names no bus")


func test_menu_sounds_go_to_the_ui_bus_radio_to_comms_and_the_rest_to_sfx() -> void:
	for sound: StringName in [&"ui_move", &"ui_accept", &"ui_back"]:
		assert_eq(AudioBuses.bus_of_sound(sound), &"UI", String(sound))
	for sound: StringName in [&"radio_open", &"radio_close"]:
		assert_eq(AudioBuses.bus_of_sound(sound), &"Comms", String(sound))
	for sound: StringName in [&"pulse_fire", &"explosion", &"warning_beep", &"target_blip", &"main_burst"]:
		assert_eq(AudioBuses.bus_of_sound(sound), &"SFX", String(sound))


func test_volume_db_is_silent_at_zero_and_unity_at_one() -> void:
	assert_eq(AudioBuses.volume_db(0.0), AudioBuses.SILENT_DB)
	assert_almost_eq(AudioBuses.volume_db(1.0), 0.0, 1e-6)
	assert_almost_eq(AudioBuses.volume_db(0.5), linear_to_db(0.5), 1e-6)
	assert_eq(AudioBuses.volume_db(-3.0), AudioBuses.SILENT_DB, "below zero is silent")
	assert_almost_eq(AudioBuses.volume_db(7.0), 0.0, 1e-6, "above one is full")
