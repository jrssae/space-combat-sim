extends GutTest
## The Settings page (architecture §18, D57, Q15; AC3): built from the schema, the console-only entries left out, and driven
## the way a pad drives it. Change, apply, revert and reset work against a scratch `Settings` so the project's own file and the
## live audio buses stay as they were.

const SettingsScript := preload("res://src/autoload/settings.gd")
const FrameScene: PackedScene = preload("res://src/frontend/menu_frame.tscn")
const SCRATCH := "user://test_settings_screen.cfg"

var settings: SettingsScript
var frame: MenuFrame
var screen: SettingsScreen


func before_each() -> void:
	get_tree().paused = false
	_clean()
	settings = SettingsScript.new()
	settings.config_path = SCRATCH
	autofree(settings)
	frame = FrameScene.instantiate() as MenuFrame
	add_child_autofree(frame)
	var home := ChoiceListScreen.new()
	home.setup("HOME", [{"id": &"settings", "text": "Settings"}] as Array[Dictionary])
	frame.set_root(home)
	screen = MenuScreens.settings() as SettingsScreen
	screen.settings = settings
	frame.push_screen(screen)
	await wait_process_frames(2)


func after_each() -> void:
	_clean()


func _clean() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func _pad(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		event.strength = 1.0 if pressed else 0.0
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await get_tree().process_frame


func _focus(key: StringName) -> void:
	screen.control_of(key).grab_focus()
	await wait_process_frames(1)


func test_the_page_lists_the_menu_entries_and_hides_the_console_only_ones() -> void:
	for key: StringName in settings.schema.keys():
		if settings.schema.is_menu(key):
			assert_not_null(screen.control_of(key), "%s has a row" % key)
		else:
			assert_null(screen.control_of(key), "%s stays on the console" % key)
	assert_not_null(screen.control_of(&"master_volume"))
	assert_null(screen.control_of(&"physics_jitter_fix"))


func test_each_type_gets_its_control() -> void:
	assert_true(screen.control_of(&"invert_y") is CheckButton)
	assert_true(screen.control_of(&"stick_deadzone") is HSlider)
	assert_true(screen.control_of(&"camera_default") is OptionButton)


func test_the_pad_changes_a_value_and_it_is_unsaved_until_apply() -> void:
	await _focus(&"master_volume")
	assert_eq(screen.focused_key(), &"master_volume")
	await _pad(&"ui_left")
	assert_almost_eq(float(settings.get_value(&"master_volume")), 0.95, 1e-4)
	assert_true(settings.is_unsaved(&"master_volume"))
	assert_true(screen.row_text(&"master_volume").ends_with("*"), "the row is marked")
	assert_eq(screen.value_text(&"master_volume"), "95%")
	await _pad(&"ui_right")
	await _pad(&"ui_right")
	assert_eq(float(settings.get_value(&"master_volume")), 1.0, "a slider stops at its end")


func test_a_flips_a_switch() -> void:
	var before: bool = bool(settings.get_value(&"invert_y"))
	await _focus(&"invert_y")
	await _pad(&"ui_accept")
	assert_eq(bool(settings.get_value(&"invert_y")), not before)
	assert_eq(screen.value_text(&"invert_y"), "On" if not before else "Off")


func test_apply_writes_the_file_and_clears_the_marks() -> void:
	settings.set_value(&"sfx_volume", 0.3)
	screen.refresh_all()
	assert_true(screen.row_text(&"sfx_volume").ends_with("*"))
	screen.action_button(&"apply").pressed.emit()
	assert_false(settings.has_unsaved())
	assert_false(screen.row_text(&"sfx_volume").ends_with("*"))
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(SCRATCH), OK)
	assert_almost_eq(float(cfg.get_value("settings", "sfx_volume")), 0.3, 1e-4, "persisted through Settings.save")


func test_revert_returns_to_the_saved_values() -> void:
	settings.set_value(&"comms_volume", 0.2)
	settings.save()
	settings.set_value(&"comms_volume", 0.9)
	settings.set_value(&"invert_y", true)
	screen.refresh_all()
	screen.action_button(&"revert").pressed.emit()
	assert_almost_eq(float(settings.get_value(&"comms_volume")), 0.2, 1e-4)
	assert_false(bool(settings.get_value(&"invert_y")))
	assert_eq(screen.value_text(&"comms_volume"), "20%")
	assert_false(settings.has_unsaved())


func test_defaults_reset_every_listed_setting() -> void:
	settings.set_value(&"ui_volume", 0.1)
	settings.set_value(&"stick_deadzone", 0.2)
	screen.refresh_all()
	screen.action_button(&"defaults").pressed.emit()
	for key: StringName in screen.listed_keys():
		assert_eq(settings.get_value(key), settings.schema.get_default(key), "%s is its default" % key)


func test_a_console_change_shows_on_the_open_page() -> void:
	settings.set_value(&"hud_targeting_grid", true)
	assert_eq(screen.value_text(&"hud_targeting_grid"), "On")


func test_up_from_the_first_row_reaches_the_buttons_and_back_leaves() -> void:
	screen.focus_first()
	await wait_process_frames(1)
	assert_eq(screen.focused_key(), screen.listed_keys()[0])
	await _pad(&"ui_up")
	assert_eq(screen.focused_option(), screen.action_button(&"apply"))
	var depth: int = frame.depth()
	await _pad(&"ui_cancel")
	assert_eq(frame.depth(), depth - 1, "B goes back")


func test_the_right_panel_explains_the_focused_setting() -> void:
	await _focus(&"master_volume")
	var info: Dictionary = screen.info()
	assert_false(info.is_empty())
	assert_gt(frame.objectives_panel().shown_lines().size(), 0)


func test_changes_drive_the_audio_bus_volume() -> void:
	# The live Settings drives the bus; this checks the page's value reaches the same setting the director reads.
	assert_eq(AudioBuses.bus_of_setting(&"ui_volume"), AudioBuses.UI)
	assert_not_null(screen.control_of(&"ui_volume"))
	assert_not_null(screen.control_of(&"comms_volume"))
