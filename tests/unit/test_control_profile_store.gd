extends GutTest
## ControlProfileStore: built-in and user profiles, listing, loading, saving, deleting (architecture §15.12, AC13).
## Runs on a scratch user folder and the real data/controls folder.

const USER_DIR := "user://test_control_store"

var store: ControlProfileStore
var default_profile: ControlProfile


func before_all() -> void:
	default_profile = ControlProfiles.store.default_profile()


func before_each() -> void:
	_remove_scratch()
	store = ControlProfileStore.new(ControlProfileStore.DEFAULT_BUILTIN_DIR, USER_DIR)
	store.snapshot_default()  # the live map is the project map or the profile a player saved; both are valid


func after_each() -> void:
	default_profile.apply_to_input_map()


func after_all() -> void:
	_remove_scratch()


func test_the_default_is_a_snapshot_of_the_input_map() -> void:
	assert_true(store.has_default())
	var snapshot: ControlProfile = store.default_profile()
	assert_eq(snapshot.name, "default")
	assert_true(snapshot.same_bindings(ControlProfile.from_input_map()))
	assert_eq(snapshot.validate(), PackedStringArray())
	assert_false(ControlProfileStore.new().has_default(), "nothing before snapshot_default")
	assert_null(ControlProfileStore.new().default_profile())


func test_the_default_snapshot_does_not_follow_later_map_changes() -> void:
	var before: ControlProfile = store.default_profile()
	InputMap.action_add_event(&"fire", ControlProfile.event_from("key:K"))
	var after: ControlProfile = store.default_profile()
	InputMap.action_erase_event(&"fire", ControlProfile.event_from("key:K"))
	assert_true(after.same_bindings(before), "default stays what it was when captured")
	assert_eq(after.descriptors_for(&"fire"), before.descriptors_for(&"fire"))


func test_default_profile_returns_copies() -> void:
	var one: ControlProfile = store.default_profile()
	one.bindings[&"fire"] = ["key:Y"]
	assert_ne(store.default_profile().descriptors_for(&"fire"), PackedStringArray(["key:Y"]))


func test_listing_has_default_then_data_profiles_then_user_profiles() -> void:
	assert_eq(store.builtin_names(), PackedStringArray(["default", "m1_classic"]))
	assert_eq(store.user_names(), PackedStringArray(), "no user folder yet, and no engine error for it")
	_save_user("zeta")
	_save_user("alpha")
	assert_eq(store.user_names(), PackedStringArray(["alpha", "zeta"]))
	assert_eq(store.names(), PackedStringArray(["default", "m1_classic", "alpha", "zeta"]))
	assert_true(store.is_builtin("default"))
	assert_true(store.is_builtin("m1_classic"))
	assert_false(store.is_builtin("alpha"))
	assert_true(store.exists("alpha"))
	assert_false(store.exists("nope"))


func test_user_files_with_bad_names_or_built_in_names_are_ignored() -> void:
	_save_user("good")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_DIR))
	var text: String = default_profile.to_config_text()
	for file_name: String in ["Bad Name.cfg", "UPPER.cfg", "default.cfg", "m1_classic.cfg", "notes.txt"]:
		var file := FileAccess.open(USER_DIR.path_join(file_name), FileAccess.WRITE)
		file.store_string(text)
		file.close()
	assert_eq(store.user_names(), PackedStringArray(["good"]))
	var shadow: Dictionary = store.load_profile("m1_classic")
	assert_eq(store.path_for("m1_classic"), "res://data/controls/m1_classic.cfg", "the built-in wins")
	assert_true(shadow["ok"])


func test_load_default_and_the_data_profile() -> void:
	var loaded: Dictionary = store.load_profile("default")
	assert_true(loaded["ok"])
	assert_eq(loaded["path"], "")
	var classic: Dictionary = store.load_profile("m1_classic")
	assert_true(classic["ok"], str(classic["errors"]))
	assert_eq((classic["profile"] as ControlProfile).name, "m1_classic")
	assert_eq(classic["path"], "res://data/controls/m1_classic.cfg")


func test_load_before_the_snapshot_says_so() -> void:
	var fresh := ControlProfileStore.new(ControlProfileStore.DEFAULT_BUILTIN_DIR, USER_DIR)
	var loaded: Dictionary = fresh.load_profile("default")
	assert_false(loaded["ok"])
	assert_string_contains(loaded["errors"][0], "not been captured")


func test_unknown_and_malformed_names_say_what_exists() -> void:
	_save_user("mine")
	var typo: Dictionary = store.load_profile("m1_clasic")
	assert_false(typo["ok"])
	assert_string_contains(typo["errors"][0], "no control profile 'm1_clasic' (did you mean m1_classic?)")
	assert_string_contains(typo["errors"][0], "available: default, m1_classic, mine")
	var bad_name: Dictionary = store.load_profile("../evil")
	assert_false(bad_name["ok"])
	assert_string_contains(bad_name["errors"][0], "is not a profile name")


func test_save_load_round_trip() -> void:
	var edited: Dictionary = default_profile.with_bound(&"fire", "key:K")
	var profile: ControlProfile = edited["profile"]
	profile.name = "mine"
	profile.description = "test layout"
	assert_eq(store.save_profile(profile), PackedStringArray())
	assert_true(FileAccess.file_exists(USER_DIR.path_join("mine.cfg")))
	var loaded: Dictionary = store.load_profile("mine")
	assert_true(loaded["ok"], str(loaded["errors"]))
	var reread: ControlProfile = loaded["profile"]
	assert_true(reread.same_bindings(profile))
	assert_eq(reread.name, "mine")
	assert_eq(reread.description, "test layout")
	assert_eq(loaded["path"], USER_DIR.path_join("mine.cfg"))


func test_built_in_profiles_cannot_be_overwritten() -> void:
	for built_in: String in ["default", "m1_classic"]:
		var profile: ControlProfile = default_profile.duplicate_profile()
		profile.name = built_in
		var errors: PackedStringArray = store.save_profile(profile)
		assert_eq(errors.size(), 1, built_in)
		assert_string_contains(errors[0], "built-in profile and read-only")
	assert_false(FileAccess.file_exists(USER_DIR.path_join("default.cfg")))
	assert_false(FileAccess.file_exists(USER_DIR.path_join("m1_classic.cfg")))
	assert_eq(store.load_profile("m1_classic")["path"], "res://data/controls/m1_classic.cfg")


func test_save_refuses_bad_names_and_invalid_profiles_and_writes_nothing() -> void:
	for bad: String in ["", "Mine", "two words", "../evil"]:
		var profile: ControlProfile = default_profile.duplicate_profile()
		profile.name = bad
		var errors: PackedStringArray = store.save_profile(profile)
		assert_eq(errors.size(), 1, "'%s'" % bad)
		assert_string_contains(errors[0], "is not a profile name")
	var invalid: ControlProfile = default_profile.duplicate_profile()
	invalid.name = "broken"
	invalid.bindings[&"fire"] = ["key:QuoteLeft"]
	var problems: PackedStringArray = store.save_profile(invalid)
	assert_gt(problems.size(), 0)
	assert_string_contains("\n".join(problems), "console key")
	assert_eq(store.user_names(), PackedStringArray(), "nothing was written")


func test_a_broken_file_loads_with_its_errors_and_is_flagged_in_the_listing() -> void:
	_write_user_file("broken", "[profile]\nformat=1\n[bindings]\nfire=[\"pad:button:15\"]\n[deadzones]\nfire=0.5\n")
	var loaded: Dictionary = store.load_profile("broken")
	assert_false(loaded["ok"])
	for error: String in loaded["errors"]:
		assert_string_starts_with(error, "bindings.fire", "only fire is wrong: the actions the file never mentions take the default's (M3-T07)")
	assert_string_contains("\n".join(loaded["errors"]), "bindings.fire[0]: pad button 15 is outside the standard layout")
	assert_eq((loaded["filled"] as PackedStringArray).size(), InputAdapter.ACTIONS.size() - 1)
	assert_not_null(loaded["profile"], "the parsed part is still available")
	var rows: Array[Dictionary] = store.entries()
	var broken_rows: Array = rows.filter(func(row: Dictionary) -> bool: return row["name"] == "broken")
	assert_eq(broken_rows.size(), 1)
	assert_false(broken_rows[0]["valid"])
	assert_true(rows.filter(func(row: Dictionary) -> bool: return row["name"] == "default")[0]["valid"])


func test_a_profile_saved_before_the_wing_orders_keeps_its_bindings_and_gains_keys_1_to_4() -> void:
	var old: ControlProfile = default_profile.duplicate_profile()
	old.name = "pre_t07"
	old.bindings[&"fire"] = (old.bindings[&"fire"] as Array) + ["key:K"]
	var wing_actions: Array[StringName] = [InputAdapter.WING_ATTACK, InputAdapter.WING_FORM, InputAdapter.WING_ENGAGE,
			InputAdapter.WING_COVER]
	for action: StringName in wing_actions:
		old.bindings.erase(action)
		old.deadzones.erase(action)
	_write_user_file("pre_t07", old.to_config_text())
	var loaded: Dictionary = store.load_profile("pre_t07")
	assert_true(loaded["ok"], "\n".join(loaded["errors"]))
	assert_eq(loaded["filled"], PackedStringArray(["wing_attack", "wing_form", "wing_engage", "wing_cover"]))
	var profile: ControlProfile = loaded["profile"]
	assert_eq(profile.descriptors_for(&"fire"), PackedStringArray(["pad:button:0", "key:Space", "mouse:1", "key:K"]),
			"its own bindings are kept")
	assert_eq(profile.descriptors_for(InputAdapter.WING_ATTACK), PackedStringArray(["key:1"]))
	assert_eq(profile.descriptors_for(InputAdapter.WING_COVER), PackedStringArray(["key:4"]))
	assert_eq(float(profile.deadzones[InputAdapter.WING_FORM]), float(default_profile.deadzones[InputAdapter.WING_FORM]))
	# Only actions the file never mentions are filled: one with a deadzone but no bindings is still broken.
	var half: ControlProfile = old.duplicate_profile()
	half.deadzones[InputAdapter.WING_ATTACK] = 0.5
	_write_user_file("half", half.to_config_text())
	var broken: Dictionary = store.load_profile("half")
	assert_false(broken["ok"])
	assert_string_contains("\n".join(broken["errors"]), "bindings.wing_attack: missing")


func test_entries_describe_every_profile() -> void:
	_save_user("mine")
	var rows: Array[Dictionary] = store.entries()
	assert_eq(rows.size(), 3)
	assert_eq(rows[0]["name"], "default")
	assert_true(rows[0]["builtin"])
	assert_string_contains(rows[0]["description"], "project.godot")
	assert_eq(rows[1]["name"], "m1_classic")
	assert_true(rows[1]["valid"])
	assert_eq(rows[2]["name"], "mine")
	assert_false(rows[2]["builtin"])


func test_delete() -> void:
	_save_user("mine")
	assert_string_contains(store.delete_profile("default"), "built-in")
	assert_string_contains(store.delete_profile("m1_classic"), "built-in")
	assert_string_contains(store.delete_profile("mien"), "no user profile 'mien' (did you mean mine?)")
	assert_eq(store.delete_profile("mine"), "")
	assert_false(FileAccess.file_exists(USER_DIR.path_join("mine.cfg")))
	assert_eq(store.user_names(), PackedStringArray())


# --- Helpers --------------------------------------------------------------------------------------------------


func _save_user(profile_name: String) -> void:
	var profile: ControlProfile = default_profile.duplicate_profile()
	profile.name = profile_name
	assert_eq(store.save_profile(profile), PackedStringArray(), "saved " + profile_name)


func _write_user_file(profile_name: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_DIR))
	var file := FileAccess.open(USER_DIR.path_join(profile_name + ".cfg"), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _remove_scratch() -> void:
	if not DirAccess.dir_exists_absolute(USER_DIR):
		return
	for file_name: String in DirAccess.get_files_at(USER_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_DIR.path_join(file_name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_DIR))
