extends GutTest
## ControlProfiles node on scratch folders, a scratch Settings and its own console registry (architecture §15.12,
## AC13): switching profiles changes what GodotInputSource reads, with no phantom edges; invalid profiles are refused
## and change nothing; `default` cannot be overwritten; bind is session-only until `controls save`; a saved
## selection is applied before the first frame of the next start. The real autoload is only checked for its wiring.

const ControlProfilesScript := preload("res://src/autoload/control_profiles.gd")
const SettingsScript := preload("res://src/autoload/settings.gd")
const DebugConsoleScript := preload("res://src/autoload/debug_console.gd")

const USER_DIR := "user://test_control_profiles"
const CONFIG_PATH := "user://test_control_profiles_settings.cfg"
const HISTORY_PATH := "user://test_control_profiles_history.txt"
const DT := 1.0 / 60.0


## GodotInputSource with one fake pad (id 0), driven with parse_input_event.
class OnePadSource:
	extends GodotInputSource

	func _pad_ids() -> Array[int]:
		var pads: Array[int] = [0]
		return pads

	func _pad_guid(_pad: int) -> String:
		return "fakepad0"

	func _pad_name(_pad: int) -> String:
		return "Fake Pad"


var default_profile: ControlProfile
var settings: SettingsScript
var console: DebugConsoleScript
var registry: ConsoleRegistry
var node: ControlProfilesScript
var source: OnePadSource
var adapter: InputAdapter
var resyncs: int = 0


func before_all() -> void:
	default_profile = ControlProfiles.store.default_profile()


func before_each() -> void:
	_clean()
	default_profile.apply_to_input_map()
	source = OnePadSource.new()
	adapter = InputAdapter.new()
	_boot()


func after_each() -> void:
	_release_everything()
	_shutdown()
	default_profile.apply_to_input_map()
	_clean()


func after_all() -> void:
	_clean()


# --- Wiring ---------------------------------------------------------------------------------------------------


func test_commands_and_provider_are_registered() -> void:
	for command: StringName in [&"controls", &"bind", &"unbind"]:
		assert_true(registry.has_command(command), String(command))
	assert_true(registry.has_provider(&"controls"))
	assert_eq(registry.read("controls.profile")["value"], "default")
	assert_eq(registry.read("controls.profiles")["value"], ["default", "m1_classic"])
	assert_eq(registry.read("controls.unsaved")["value"], false)


func test_the_real_autoload_is_wired_into_the_real_console() -> void:
	assert_true(DebugConsole.registry.has_command(&"controls"))
	assert_true(DebugConsole.registry.has_command(&"bind"))
	assert_true(DebugConsole.registry.has_command(&"unbind"))
	assert_true(DebugConsole.registry.has_provider(&"controls"))
	assert_true(Settings.validators.has(&"control_profile"), "set settings.control_profile is checked")
	assert_true(ControlProfiles.store.has_default())


func test_removing_the_node_removes_its_console_entries_and_validator() -> void:
	_free_node()
	assert_false(registry.has_command(&"controls"))
	assert_false(registry.has_provider(&"controls"))
	assert_false(settings.validators.has(&"control_profile"))
	node = _make_node()  # for after_each


func test_list_marks_the_profile_in_use() -> void:
	var text: String = _run("controls list").text()
	assert_string_contains(text, "control profiles (* = in use):")
	assert_string_contains(text, "* default")
	assert_string_contains(text, "  m1_classic  built-in  Original M1 layout")
	assert_eq(_run("controls").text(), text, "list is the default")
	_run("controls save mine")
	text = _run("controls list").text()
	assert_string_contains(text, "  default")
	assert_string_contains(text, "* mine")
	assert_string_contains(text, "user")


# --- Switching (AC13) -----------------------------------------------------------------------------------------


func test_use_changes_what_godot_input_source_reads() -> void:
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	_button(JOY_BUTTON_DPAD_RIGHT, true)
	var v: Vector2 = source.get_vector(&"roll_left", &"roll_right", &"pitch_down", &"pitch_up", 0.15)
	assert_almost_eq(v.x, 1.0, 1e-5, "default: the stick X is roll")
	assert_true(source.is_pressed(&"yaw_right"), "default: the D-pad is yaw")

	var result: ConsoleResult = _run("controls use m1_classic")
	assert_true(result.ok, result.text())
	assert_eq(registry.read("controls.profile")["value"], "m1_classic")
	v = source.get_vector(&"roll_left", &"roll_right", &"pitch_down", &"pitch_up", 0.15)
	assert_almost_eq(v.x, 1.0, 1e-5, "m1_classic: the D-pad is roll (a button reads 1)")
	assert_true(source.is_pressed(&"yaw_right"), "m1_classic: the stick X is yaw")
	assert_true(source.is_pressed(&"roll_right"), "m1_classic: the D-pad Right is roll")

	_button(JOY_BUTTON_DPAD_RIGHT, false)
	assert_false(source.is_pressed(&"roll_right"))
	assert_true(source.is_pressed(&"yaw_right"), "the stick is still held")
	v = source.get_vector(&"roll_left", &"roll_right", &"pitch_down", &"pitch_up", 0.15)
	assert_eq(v, Vector2.ZERO, "and no longer rolls")

	_axis(JOY_AXIS_RIGHT_X, 0.1)
	assert_false(source.is_pressed(&"yaw_right"), "inside the yaw deadzone the profile brought (0.15)")
	assert_almost_eq(InputMap.action_get_deadzone(&"yaw_right"), 0.15, 1e-6)
	assert_almost_eq(InputMap.action_get_deadzone(&"roll_right"), 0.5, 1e-6)

	assert_true(_run("controls use default").ok)
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	assert_false(source.is_pressed(&"yaw_right"), "back to the default: the stick does not yaw")


func test_use_produces_no_phantom_edges() -> void:
	var without_resync := InputAdapter.new()
	_button(JOY_BUTTON_B, true)  # held across the switch
	assert_true(adapter.sample(source, DT).flight.toggle_assist, "B is flight assist: its own edge")
	assert_true(without_resync.sample(source, DT).flight.toggle_assist)
	assert_false(adapter.sample(source, DT).flight.toggle_assist, "once")

	resyncs = 0
	var result: ConsoleResult = _run("bind toggle_camera pad:button:1")
	assert_true(result.ok, result.text())
	assert_eq(resyncs, 1, "the input adapter was told")
	assert_true(source.is_pressed(&"toggle_camera"), "B now means camera as well")
	var after: PilotCommand = adapter.sample(source, DT)
	assert_false(after.ui.toggle_camera, "no phantom camera toggle from a button that was already down")
	assert_false(after.flight.toggle_assist)
	assert_true(without_resync.sample(source, DT).ui.toggle_camera, "(without the resync the edge would have fired)")

	_button(JOY_BUTTON_B, false)
	adapter.sample(source, DT)
	_button(JOY_BUTTON_B, true)
	assert_true(adapter.sample(source, DT).ui.toggle_camera, "a real press still toggles")


func test_a_tap_or_hold_in_progress_is_dropped_by_a_switch() -> void:
	_button(JOY_BUTTON_DPAD_UP, true)
	assert_false(adapter.sample(source, DT).combat.target_next)
	assert_true(_run("controls use m1_classic").ok)
	_button(JOY_BUTTON_DPAD_UP, false)
	assert_false(adapter.sample(source, DT).combat.target_next, "the press began under the old profile")


func test_applied_signal() -> void:
	watch_signals(node)
	assert_true(_run("controls use m1_classic").ok)
	assert_signal_emitted_with_parameters(node, "applied", ["m1_classic"])
	assert_true(_run("bind fire key:K").ok)
	assert_signal_emit_count(node, "applied", 2)


func test_use_is_case_insensitive_and_needs_a_name() -> void:
	assert_true(_run("controls use M1_Classic").ok)
	assert_eq(node.active_name, "m1_classic")
	var missing: ConsoleResult = _run("controls use")
	assert_false(missing.ok)
	assert_string_contains(missing.error, "needs a profile name")
	var extra: ConsoleResult = _run("controls list now")
	assert_false(extra.ok)
	assert_string_contains(extra.error, "takes no argument")
	var typo: ConsoleResult = _run("controls usee m1_classic")
	assert_false(typo.ok)
	assert_string_contains(typo.error, "did you mean use?")


func test_use_hints_that_save_keeps_the_choice() -> void:
	var text: String = _run("controls use m1_classic").text()
	assert_string_contains(text, "control profile: m1_classic")
	assert_string_contains(text, "type save to start with it next time")
	assert_true(settings.is_unsaved(&"control_profile"))
	assert_false(FileAccess.file_exists(CONFIG_PATH), "never written by use")


# --- Refusals (AC13) ------------------------------------------------------------------------------------------


func test_an_unknown_profile_is_refused_with_the_names_that_exist() -> void:
	var before: String = _snapshot()
	var result: ConsoleResult = _run("controls use m1_clasic")
	assert_false(result.ok)
	assert_string_contains(result.error, "no control profile 'm1_clasic' (did you mean m1_classic?)")
	assert_string_contains(result.error, "available: default, m1_classic")
	assert_eq(_snapshot(), before)
	assert_eq(node.active_name, "default")
	assert_eq(settings.get_value(&"control_profile"), "default")
	assert_false(_run("controls use ../evil").ok)
	assert_eq(_snapshot(), before)


func test_an_invalid_profile_file_is_refused_and_the_map_is_unchanged() -> void:
	var broken: ControlProfile = default_profile.duplicate_profile()
	broken.bindings.erase(&"pause")
	broken.bindings[&"fire"] = ["pad:button:0", "pad:button:15"]
	broken.bindings[&"brake"] = ["pad:button:2", "key:QuoteLeft"]
	_write_user_profile("broken", broken)
	var before: String = _snapshot()
	var result: ConsoleResult = _run("controls use broken")
	assert_false(result.ok)
	assert_string_contains(result.error, "controls use broken: 3 problems, nothing changed")
	var details: String = "\n".join(result.lines)
	assert_string_contains(details, "bindings.pause: missing")
	assert_string_contains(details, "bindings.fire[1]: pad button 15 is outside the standard layout (0-14)")
	assert_string_contains(details, "bindings.brake[1]: key:QuoteLeft is the console key")
	assert_eq(_snapshot(), before, "InputMap unchanged")
	assert_eq(node.active_name, "default")
	assert_eq(settings.get_value(&"control_profile"), "default")
	assert_eq(resyncs, 0, "nothing applied, nobody told")
	assert_string_contains(_run("controls list").text(), "INVALID")


func test_a_profile_saved_before_new_actions_existed_is_used_with_a_notice() -> void:
	var old: ControlProfile = default_profile.duplicate_profile()
	for action: StringName in [InputAdapter.WING_ATTACK, InputAdapter.WING_FORM, InputAdapter.WING_ENGAGE,
			InputAdapter.WING_COVER]:
		old.bindings.erase(action)
		old.deadzones.erase(action)
	_write_user_profile("old", old)
	var result: ConsoleResult = _run("controls use old")
	assert_true(result.ok, result.error)
	assert_string_contains(result.text(),
			"control profile 'old' was saved before wing_attack, wing_form, wing_engage, wing_cover existed")
	assert_eq(node.active_name, "old")
	assert_false(node.is_unsaved(), "the filled bindings are the profile's until it is saved")
	assert_eq(ControlProfile.from_input_map().descriptors_for(InputAdapter.WING_FORM), PackedStringArray(["key:2"]))


func test_set_setting_to_an_unknown_profile_is_refused() -> void:
	var before: String = _snapshot()
	var refused: String = _setting_write("ghost")
	assert_string_contains(refused, "no control profile 'ghost'")
	assert_eq(settings.get_value(&"control_profile"), "default")
	assert_eq(_snapshot(), before)
	var result: ConsoleResult = _run("set settings.control_profile Bad_Name")
	assert_false(result.ok)
	assert_string_contains(result.error, "control_profile must match")


func test_default_cannot_be_overwritten() -> void:
	_run("bind fire key:K")
	for line: String in ["controls save default", "controls save m1_classic", "controls save"]:
		var result: ConsoleResult = _run(line)
		assert_false(result.ok, line)
		assert_string_contains(result.error, "built-in profile and read-only", line)
	assert_eq(_stored_user_profiles(), PackedStringArray(), "nothing was written")
	assert_true(_run("controls use m1_classic").ok)
	var again: ConsoleResult = _run("controls save")
	assert_false(again.ok, "also while a built-in is in use")
	assert_string_contains(again.error, "give a name")
	assert_eq(ControlProfiles.store.load_profile("m1_classic")["path"], "res://data/controls/m1_classic.cfg")


func test_save_rejects_bad_names_and_lower_cases_the_rest() -> void:
	_run("bind fire key:K")
	for line: String in ["controls save ../evil", "controls save a-b", "controls save has.dot"]:
		var result: ConsoleResult = _run(line)
		assert_false(result.ok, line)
		assert_string_contains(result.error, "is not a profile name", line)
	assert_eq(_stored_user_profiles(), PackedStringArray(), "nothing was written")
	assert_true(_run("controls save MixedCase").ok)
	assert_eq(_stored_user_profiles(), PackedStringArray(["mixedcase"]))


func test_bind_and_unbind_errors_leave_the_map_alone() -> void:
	var before: String = _snapshot()
	var cases: Dictionary = {
		"bind fier key:K": "unknown action 'fier' (did you mean fire?)",
		"bind fire key:NoSuchKey": "unknown key name",
		"bind fire key:QuoteLeft": "console key",
		"bind fire pad:button:15": "outside the standard layout",
		"bind fire pad:axis:5-": "trigger",
		"bind fire joystick:1": "unknown binding",
		"unbind fire key:K": "fire has no key:K binding (it has: pad:button:0 key:Space mouse:1)",
		"unbind fire pad:button:0": "needs a pad binding",
		"unbind pitch_up pad:axis:3+": "needs a pad binding",
	}
	for line: String in cases.keys():
		var result: ConsoleResult = _run(line)
		assert_false(result.ok, line)
		assert_string_contains(result.error + "\n".join(result.lines), cases[line], line)
		assert_eq(_snapshot(), before, line)
	assert_eq(resyncs, 0)
	assert_false(node.is_unsaved())


# --- bind / unbind (AC13) -------------------------------------------------------------------------------------


func test_bind_is_session_only_until_controls_save() -> void:
	var result: ConsoleResult = _run("bind fire key:k")
	assert_true(result.ok, result.text())
	assert_string_contains(result.text(), "fire: pad:button:0 key:Space mouse:1 key:K (deadzone 0.50)")
	assert_false(result.text().contains("is also bound"), "K is free in layout B: no note")
	assert_string_contains(result.text(), "session only")
	assert_true(registry.read("controls.unsaved")["value"])
	_key(KEY_K, true)
	assert_true(source.is_pressed(&"fire"), "the new binding is live")
	_key(KEY_K, false)
	assert_eq(settings.get_value(&"control_profile"), "default", "no selection changed")
	assert_eq(_stored_user_profiles(), PackedStringArray(), "no profile file exists")

	var discarded: ConsoleResult = _run("controls use default")
	assert_string_contains(discarded.text(), "discarded unsaved bind/unbind changes")
	assert_eq(_descriptors(&"fire"), PackedStringArray(["pad:button:0", "key:Space", "mouse:1"]))
	assert_false(registry.read("controls.unsaved")["value"])

	_run("bind fire key:K")
	var saved: ConsoleResult = _run("controls save mine")
	assert_true(saved.ok, saved.text())
	assert_string_contains(saved.text(), "saved user://test_control_profiles/mine.cfg")
	assert_true(FileAccess.file_exists(USER_DIR.path_join("mine.cfg")))
	assert_eq(registry.read("controls.profile")["value"], "mine")
	assert_false(registry.read("controls.unsaved")["value"])
	assert_eq(settings.get_value(&"control_profile"), "mine", "selected")
	assert_true(settings.is_unsaved(&"control_profile"), "but only `save` makes the selection stick")
	assert_false(FileAccess.file_exists(CONFIG_PATH))

	assert_true(_run("controls use default").ok)
	assert_false(_descriptors(&"fire").has("key:K"))
	assert_true(_run("controls use mine").ok)
	assert_true(_descriptors(&"fire").has("key:K"), "the saved bind is back")


func test_controls_save_with_no_name_updates_the_active_user_profile() -> void:
	_run("bind fire key:K")
	assert_true(_run("controls save mine").ok)
	_run("bind weapon_next key:Y")
	assert_true(registry.read("controls.unsaved")["value"])
	var result: ConsoleResult = _run("controls save")
	assert_true(result.ok, result.text())
	assert_string_contains(result.text(), "saved user://test_control_profiles/mine.cfg")
	assert_false(registry.read("controls.unsaved")["value"])
	var loaded: Dictionary = node.store.load_profile("mine")
	assert_true(loaded["ok"], str(loaded["errors"]))
	assert_true((loaded["profile"] as ControlProfile).descriptors_for(&"weapon_next").has("key:Y"))


func test_unbind_then_bind_moves_a_pad_button() -> void:
	assert_true(_run("bind fire pad:button:7").ok)
	var refused: ConsoleResult = _run("unbind fire pad:button:99")
	assert_false(refused.ok)
	assert_true(_run("unbind fire pad:button:0").ok)
	_button(JOY_BUTTON_A, true)
	assert_false(source.is_pressed(&"fire"), "A no longer fires")
	_button(JOY_BUTTON_LEFT_STICK, true)
	assert_true(source.is_pressed(&"fire"), "L3 does")
	assert_true(source.is_pressed(&"camera_look"), "(and still holds the free look)")


func test_binding_a_key_another_action_uses_says_so() -> void:
	var result: ConsoleResult = _run("bind fire key:b")
	assert_true(result.ok, result.text())
	assert_string_contains(result.text(), "note: key:B is also bound to target_next")
	assert_true(_run("controls use default").ok, "discard the session bind")


func test_binding_something_twice_says_so() -> void:
	var result: ConsoleResult = _run("bind fire KEY:space")
	assert_true(result.ok)
	assert_string_contains(result.text(), "key:Space was already bound to fire")
	assert_eq(resyncs, 0, "nothing changed")
	assert_false(node.is_unsaved())


func test_a_bind_undone_is_not_unsaved() -> void:
	_run("bind fire key:K")
	assert_true(node.is_unsaved())
	_run("unbind fire key:K")
	assert_false(node.is_unsaved(), "back to what the profile holds")


func test_show() -> void:
	assert_eq(_run("controls show fire").text(), "fire: pad:button:0 key:Space mouse:1 (deadzone 0.50)")
	var all: ConsoleResult = _run("controls show")
	assert_eq(all.lines.size(), InputAdapter.ACTIONS.size() + 1)
	assert_eq(all.lines[0], "control profile: default")
	var typo: ConsoleResult = _run("controls show fier")
	assert_false(typo.ok)
	assert_string_contains(typo.error, "unknown action 'fier' (did you mean fire?)")
	_run("bind fire key:K")
	assert_string_contains(_run("controls show").lines[0], "(unsaved changes)")


func test_delete() -> void:
	_run("controls save mine")
	assert_string_contains(_run("controls delete mine").error, "the active profile")
	assert_true(_run("controls use default").ok)
	assert_true(_run("controls delete mine").ok)
	assert_false(FileAccess.file_exists(USER_DIR.path_join("mine.cfg")))
	assert_string_contains(_run("controls delete default").error, "built-in")
	assert_string_contains(_run("controls delete mien").error, "no user profile 'mien'")
	assert_false(_run("controls delete").ok)


# --- The setting ----------------------------------------------------------------------------------------------


func test_setting_the_setting_applies_the_profile() -> void:
	var result: ConsoleResult = _run("set settings.control_profile m1_classic")
	assert_true(result.ok, result.text())
	assert_eq(node.active_name, "m1_classic")
	assert_eq(_descriptors(&"yaw_left"), PackedStringArray(["pad:axis:2-"]))
	assert_eq(resyncs, 1)
	assert_true(_run("default settings.control_profile").ok)
	assert_eq(node.active_name, "default")
	assert_eq(_descriptors(&"yaw_left"), PackedStringArray(["pad:button:13"]))
	settings.set_value(&"control_profile", "m1_classic")
	settings.revert()  # nothing was saved: back to the default selection
	assert_eq(node.active_name, "default", "revert re-applies the saved selection")


# --- Start-up and restarts (AC13, AC20) -----------------------------------------------------------------------


func test_the_saved_selection_is_applied_when_the_node_enters_the_tree() -> void:
	var mine: ControlProfile = default_profile.duplicate_profile()
	mine.bindings[&"fire"] = ["pad:button:0", "key:Space", "mouse:1", "key:K"]
	_write_user_profile("mine", mine)
	_free_node()
	settings.set_value(&"control_profile", "mine")
	resyncs = 0
	node = _make_node()  # _ready is "before the first frame"
	assert_eq(node.active_name, "mine")
	assert_eq(_descriptors(&"fire"), PackedStringArray(["pad:button:0", "key:Space", "mouse:1", "key:K"]))
	assert_eq(resyncs, 1)
	assert_false(node.is_unsaved())
	assert_eq(registry.read("controls.profile")["value"], "mine")


func test_the_built_in_default_snapshot_is_taken_before_the_selection_applies() -> void:
	_free_node()
	settings.set_value(&"control_profile", "m1_classic")
	node = _make_node()
	assert_eq(node.active_name, "m1_classic")
	assert_true(node.store.default_profile().same_bindings(default_profile), "default is still the project map")
	assert_true(_run("controls use default").ok)
	assert_eq(_descriptors(&"yaw_left"), PackedStringArray(["pad:button:13"]))


func test_a_missing_profile_falls_back_to_the_default_controls() -> void:
	var before: String = _snapshot()
	_free_node()
	settings.set_value(&"control_profile", "ghost")
	node = _make_node()
	assert_eq(node.active_name, "default")
	assert_eq(_snapshot(), before)
	assert_eq(settings.get_value(&"control_profile"), "ghost", "the choice is kept, not overwritten, until you change it")
	assert_true(_run("controls use default").ok)
	assert_eq(settings.get_value(&"control_profile"), "default")


func test_an_invalid_profile_falls_back_to_the_default_controls() -> void:
	var broken: ControlProfile = default_profile.duplicate_profile()
	broken.bindings[&"fire"] = ["pad:button:15"]
	_write_user_profile("broken", broken)
	var before: String = _snapshot()
	_free_node()
	settings.set_value(&"control_profile", "broken")
	node = _make_node()
	assert_eq(node.active_name, "default")
	assert_eq(_snapshot(), before, "nothing half-applied")


func test_a_saved_profile_and_selection_survive_a_restart() -> void:
	_run("bind fire key:K")
	_run("bind yaw_left pad:axis:2-")
	_run("unbind yaw_left pad:button:13")
	assert_true(_run("controls save mine").ok)
	assert_eq(settings.save(), OK, "what the console's `save` does")
	var expected: String = _snapshot()

	# "Restart": the process starts over with the project.godot map, new Settings reading the file, new node.
	_shutdown()
	default_profile.apply_to_input_map()
	assert_ne(_snapshot(), expected, "the fresh process starts from the project map")
	_boot()
	assert_eq(settings.get_value(&"control_profile"), "mine", "the selection was saved")
	assert_eq(node.active_name, "mine")
	assert_eq(_snapshot(), expected, "the map is exactly what was saved, applied before anything else ran")
	assert_eq(_descriptors(&"yaw_left"), PackedStringArray(["pad:axis:2-"]))
	assert_true(_descriptors(&"fire").has("key:K"))
	assert_eq(registry.read("controls.profile")["value"], "mine")
	assert_false(registry.read("controls.unsaved")["value"])


func test_without_save_the_selection_does_not_survive() -> void:
	assert_true(_run("controls use m1_classic").ok)
	_shutdown()
	default_profile.apply_to_input_map()
	_boot()
	assert_eq(node.active_name, "default")


# --- Helpers --------------------------------------------------------------------------------------------------


# A fresh "process": Settings reading the scratch file, a console (its registry and `set`/`default`/`save`
# commands), and the node under test.
func _boot() -> void:
	resyncs = 0
	settings = _make_settings()
	console = DebugConsoleScript.new()
	console.settings = settings
	console.history = ConsoleHistory.new(HISTORY_PATH)
	console.autoexec_path = "user://test_no_such_autoexec.cfg"
	console.user_args = PackedStringArray()
	console.run_startup = false
	console.mirror_stdout = false
	add_child_autofree(console)
	registry = console.registry
	node = _make_node()


func _shutdown() -> void:
	_free_node()
	for freed: Node in [console, settings]:
		if is_instance_valid(freed):
			if freed.get_parent() != null:
				freed.get_parent().remove_child(freed)
			freed.free()


func _make_settings() -> SettingsScript:
	var made: SettingsScript = SettingsScript.new()
	made.config_path = CONFIG_PATH
	made.joy_mappings_path = "user://test_no_such_gamecontrollerdb.txt"
	add_child_autofree(made)
	return made


func _make_node() -> ControlProfilesScript:
	var made: ControlProfilesScript = ControlProfilesScript.new()
	made.store = ControlProfileStore.new(ControlProfileStore.DEFAULT_BUILTIN_DIR, USER_DIR)
	made.settings = settings
	made.registry = registry
	made.resync_input = func() -> void:
		resyncs += 1
		adapter.resync_edges(source)
	add_child_autofree(made)
	return made


func _free_node() -> void:
	if is_instance_valid(node):
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()


func _run(line: String) -> ConsoleResult:
	var results: Array[ConsoleResult] = registry.execute(line)
	return results[0]


# `set settings.control_profile <value>` through the settings provider; the refusal text, or "" when it worked.
func _setting_write(value: String) -> String:
	var result: ConsoleResult = _run("set settings.control_profile " + value)
	return "" if result.ok else result.error


func _stored_user_profiles() -> PackedStringArray:
	return ControlProfileStore.new(ControlProfileStore.DEFAULT_BUILTIN_DIR, USER_DIR).user_names()


func _descriptors(action: StringName) -> PackedStringArray:
	return ControlProfile.from_input_map().descriptors_for(action)


# The whole game part of the InputMap as text (descriptors and deadzones, in order).
func _snapshot() -> String:
	return ControlProfile.from_input_map("snapshot").to_config_text()


func _write_user_profile(profile_name: String, profile: ControlProfile) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_DIR))
	var file := FileAccess.open(USER_DIR.path_join(profile_name + ".cfg"), FileAccess.WRITE)
	file.store_string(profile.to_config_text())
	file.close()


func _clean() -> void:
	if FileAccess.file_exists(CONFIG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG_PATH))
	if not DirAccess.dir_exists_absolute(USER_DIR):
		return
	for file_name: String in DirAccess.get_files_at(USER_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_DIR.path_join(file_name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_DIR))


func _axis(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _button(button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _key(key: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = key
	e.keycode = key
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _release_everything() -> void:
	for axis: int in 6:
		_axis(axis as JoyAxis, 0.0)
	for button: int in 15:
		_button(button as JoyButton, false)
	for key: Key in [KEY_K, KEY_Y]:
		_key(key, false)
	Input.flush_buffered_events()
