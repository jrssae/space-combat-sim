class_name ControlProfileStore
extends RefCounted
## Where control profiles live (architecture §15.12). Built-in profiles are read-only: `default`, a snapshot of the
## project.godot map taken before any profile applies, and the `*.cfg` files under `data/controls/`. User profiles
## are `user://controls/<name>.cfg`, written by `save_profile`. A user file named like a built-in is ignored.
## Directories are injectable so tests run on scratch folders. Applying a profile to the InputMap is
## `ControlProfile.apply_to_input_map`; the ControlProfiles autoload decides when.

const DEFAULT_BUILTIN_DIR: String = "res://data/controls"
const DEFAULT_USER_DIR: String = "user://controls"
const EXTENSION: String = "cfg"
const DEFAULT_DESCRIPTION: String = "The project.godot map (architecture 6.1): right stick pitch and roll, D-pad yaw"

var builtin_dir: String = DEFAULT_BUILTIN_DIR
var user_dir: String = DEFAULT_USER_DIR

var _default: ControlProfile = null


func _init(p_builtin_dir: String = DEFAULT_BUILTIN_DIR, p_user_dir: String = DEFAULT_USER_DIR) -> void:
	builtin_dir = p_builtin_dir
	user_dir = p_user_dir


## Captures the InputMap as the `default` profile. Call once, before any profile is applied.
func snapshot_default() -> void:
	_default = ControlProfile.from_input_map(ControlProfile.DEFAULT_NAME)
	_default.description = DEFAULT_DESCRIPTION


func has_default() -> bool:
	return _default != null


## A copy of the default snapshot, or null before `snapshot_default`.
func default_profile() -> ControlProfile:
	return _default.duplicate_profile() if _default != null else null


# --- Listing -----------------------------------------------------------------------------------------------------


## `default`, then the data files, each sorted.
func builtin_names() -> PackedStringArray:
	var out := PackedStringArray([ControlProfile.DEFAULT_NAME])
	for file_name: String in _names_in(builtin_dir):
		if file_name != ControlProfile.DEFAULT_NAME:
			out.append(file_name)
	return out


## User profile names, sorted; files whose names are not valid profile names or shadow a built-in are left out.
func user_names() -> PackedStringArray:
	var builtin: PackedStringArray = builtin_names()
	var out := PackedStringArray()
	for file_name: String in _names_in(user_dir):
		if not builtin.has(file_name):
			out.append(file_name)
	return out


func names() -> PackedStringArray:
	var out: PackedStringArray = builtin_names()
	out.append_array(user_names())
	return out


func is_builtin(profile_name: String) -> bool:
	return builtin_names().has(profile_name)


func exists(profile_name: String) -> bool:
	return names().has(profile_name)


## One row per profile for listings: {"name", "builtin", "valid", "description", "errors"}.
func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for profile_name: String in names():
		var loaded: Dictionary = load_profile(profile_name)
		var profile: ControlProfile = loaded["profile"]
		out.append({"name": profile_name, "builtin": is_builtin(profile_name), "valid": loaded["ok"],
				"description": profile.description if profile != null else "", "errors": loaded["errors"]})
	return out


# --- Reading and writing -----------------------------------------------------------------------------------------


## Path of a profile's file ("" for `default`, which has none).
func path_for(profile_name: String) -> String:
	if profile_name == ControlProfile.DEFAULT_NAME:
		return ""
	if _names_in(builtin_dir).has(profile_name):
		return _path_in(builtin_dir, profile_name)
	return _path_in(user_dir, profile_name)


## Loads and validates a profile. Returns {"ok", "profile", "errors", "path", "filled"}; `errors` explains a failure (also an
## unknown name, with the names that exist), and `profile` is set whenever the file parsed. A user profile saved before an
## action existed gets the default profile's bindings for it (`filled` lists them; `ControlProfile.from_config_text`):
## saved layouts keep working when the game gains actions. The built-in data profiles must be complete.
func load_profile(profile_name: String) -> Dictionary:
	if not ControlProfile.is_valid_name(profile_name):
		return _load_failed("'%s' is not a profile name (lowercase letters, digits and _, 1-32 characters)" % profile_name)
	if profile_name == ControlProfile.DEFAULT_NAME:
		if _default == null:
			return _load_failed("the default profile has not been captured yet")
		return {"ok": true, "profile": default_profile(), "errors": PackedStringArray(), "path": "", "filled": PackedStringArray()}
	if not exists(profile_name):
		return _load_failed("no control profile '%s'%s; available: %s" % [profile_name,
				ConsoleFormat.did_you_mean(profile_name, names()), ", ".join(names())])
	var path: String = path_for(profile_name)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _load_failed("could not read %s (%s)" % [path, error_string(FileAccess.get_open_error())])
	var fill_from: ControlProfile = _default if not is_builtin(profile_name) else null
	var parsed: Dictionary = ControlProfile.from_config_text(file.get_as_text(), profile_name, fill_from)
	parsed["path"] = path
	return parsed


## Validates and writes `user://controls/<name>.cfg`. Returns the problems, empty when it was saved. Built-in names
## are refused, so `default` and the data profiles can never be overwritten.
func save_profile(profile: ControlProfile) -> PackedStringArray:
	if not ControlProfile.is_valid_name(profile.name):
		return PackedStringArray(["'%s' is not a profile name (lowercase letters, digits and _, 1-32 characters)"
				% profile.name])
	if is_builtin(profile.name):
		return PackedStringArray(["'%s' is a built-in profile and read-only; save under another name" % profile.name])
	var errors: PackedStringArray = profile.validate()
	if not errors.is_empty():
		return errors
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(user_dir))
	var path: String = _path_in(user_dir, profile.name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return PackedStringArray(["could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())]])
	file.store_string(profile.to_config_text())
	file.close()
	return PackedStringArray()


## Removes a user profile's file. Returns why not, or "" when it is gone.
func delete_profile(profile_name: String) -> String:
	if is_builtin(profile_name):
		return "'%s' is a built-in profile and cannot be deleted" % profile_name
	if not user_names().has(profile_name):
		return "no user profile '%s'%s" % [profile_name, ConsoleFormat.did_you_mean(profile_name, user_names())]
	var err: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(_path_in(user_dir, profile_name)))
	return "" if err == OK else "could not delete %s (%s)" % [profile_name, error_string(err)]


# --- Private -----------------------------------------------------------------------------------------------------


static func _path_in(dir: String, profile_name: String) -> String:
	return dir.path_join("%s.%s" % [profile_name, EXTENSION])


# Sorted base names of the valid-named `.cfg` files in a directory (none if it does not exist).
static func _names_in(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):  # get_files_at would print an engine error
		return out
	for file_name: String in DirAccess.get_files_at(dir):
		if file_name.get_extension() == EXTENSION and ControlProfile.is_valid_name(file_name.get_basename()):
			out.append(file_name.get_basename())
	out.sort()
	return out


static func _load_failed(message: String) -> Dictionary:
	return {"ok": false, "profile": null, "errors": PackedStringArray([message]), "path": "", "filled": PackedStringArray()}
