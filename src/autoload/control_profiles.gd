extends Node
## ControlProfiles autoload: saved, selectable control layouts (architecture §15.12, M2-T11). Thin adapter over the
## pure ControlProfile and ControlProfileStore: it applies the profile named by `settings.control_profile` before
## the first frame (an invalid or missing one warns and leaves the default), keeps the choice in step with that
## setting, and exposes the console's `controls`, `bind` and `unbind` commands and the `controls` provider.
##
## Every change goes through ControlProfile.validate first and replaces the InputMap's game actions all at once, so
## a bad profile can never leave the map half-changed. `GodotInputSource` reads the InputMap on every poll, so
## nothing else needs to know; `resync_input` (the console's input adapter) re-seeds its edge state so a button
## that now means something else cannot fire a phantom edge.
##
## Session vs saved, as for settings: `controls use`, `bind` and `unbind` last until the game quits; `controls save
## <name>` writes `user://controls/<name>.cfg`; the console's `save` persists `settings.control_profile`, which is what
## selects the profile at the next start. `default` and the data profiles are read-only.

## A profile (or a tweak of one) is now in the InputMap.
signal applied(profile_name: String)

const SettingsScript := preload("res://src/autoload/settings.gd")
const DebugConsoleScript := preload("res://src/autoload/debug_console.gd")

const SETTING_KEY: StringName = &"control_profile"
const SUBCOMMANDS: Array[StringName] = [&"list", &"use", &"save", &"show", &"delete"]

# Injection points, read when the node enters the tree. The defaults are what the autoload uses; tests point them
# at scratch folders, a scratch Settings and a registry of their own.
var store: ControlProfileStore = ControlProfileStore.new()
var settings: SettingsScript = null  ## null: /root/Settings
var registry: ConsoleRegistry = null  ## null: the registry of /root/DebugConsole
## Called after every apply. Default: the console's `resync_input_edges`.
var resync_input: Callable = Callable()

## The profile the InputMap was last loaded from or saved as (`default` until one is used).
var active_name: String = ControlProfile.DEFAULT_NAME

var _base: ControlProfile = null  # what `active_name` holds on disk (or in the project), to detect unsaved binds


func _ready() -> void:
	if settings == null:
		settings = get_node_or_null(^"/root/Settings") as SettingsScript
	var console: DebugConsoleScript = get_node_or_null(^"/root/DebugConsole") as DebugConsoleScript
	if console != null:
		if registry == null:
			registry = console.registry
		if not resync_input.is_valid():
			resync_input = console.resync_input_edges
	if not store.has_default():
		store.snapshot_default()  # before any profile applies
	_base = store.default_profile()
	var problems: PackedStringArray = _base.validate()
	if not problems.is_empty():
		push_warning("ControlProfiles: the project.godot input map breaks the profile rules: %s" % problems[0])
	if settings != null:
		settings.validators[SETTING_KEY] = _check_selection
		settings.changed.connect(_on_setting_changed)
		_apply_startup_selection()
	_register_console()


func _exit_tree() -> void:
	if registry != null:
		registry.unregister_owner(self)
	if settings != null:
		if settings.changed.is_connected(_on_setting_changed):
			settings.changed.disconnect(_on_setting_changed)
		if settings.validators.get(SETTING_KEY) == Callable(self, &"_check_selection"):
			settings.validators.erase(SETTING_KEY)


# --- Profiles ----------------------------------------------------------------------------------------------------


## True when the InputMap differs from what the active profile holds (`bind`/`unbind` since the last use or save).
func is_unsaved() -> bool:
	if _base == null:
		return false
	return not ControlProfile.from_input_map().same_bindings(_base)


## Applies a profile for this session and selects it in `settings.control_profile` (unsaved until the console's
## `save`). Returns {"ok", "errors", "discarded"}; `discarded` is true when unsaved binds were thrown away. On failure
## the InputMap and the setting are unchanged.
func use(profile_name: String) -> Dictionary:
	var discarded: bool = is_unsaved()
	var errors: PackedStringArray = _activate(profile_name)
	if errors.is_empty() and settings != null:
		if settings.set_value(SETTING_KEY, profile_name) != OK:
			errors.append(settings.get_last_error())
	return {"ok": errors.is_empty(), "errors": errors, "discarded": discarded and errors.is_empty()}


## Writes the InputMap as `user://controls/<name>.cfg` and selects it. Refuses `default` and the data profiles.
## Returns the problems, empty on success.
func save_as(profile_name: String) -> PackedStringArray:
	var profile: ControlProfile = ControlProfile.from_input_map(profile_name)
	if profile_name == active_name and _base != null:
		profile.description = _base.description
	var errors: PackedStringArray = store.save_profile(profile)
	if not errors.is_empty():
		return errors
	active_name = profile_name
	_base = profile
	if settings != null and settings.set_value(SETTING_KEY, profile_name) != OK:
		errors.append(settings.get_last_error())
	return errors


## `save_as` over the active profile, which must be a user profile.
func save_active() -> PackedStringArray:
	return save_as(active_name)


## Removes a user profile. The active one cannot go: its bindings are in the InputMap.
func delete_profile(profile_name: String) -> String:
	if profile_name == active_name and not store.is_builtin(profile_name):
		return "'%s' is the active profile; switch to another first (controls use <name>)" % profile_name
	return store.delete_profile(profile_name)


## Adds a binding to an action for this session. Returns {"ok", "errors", "changed", "descriptor", "also"}:
## `changed` is false when it was already bound, `also` lists the other actions with the same binding.
func bind(action: StringName, descriptor: String) -> Dictionary:
	return _edit(action, descriptor, true)


## Removes a binding from an action for this session; an action keeps at least one pad binding.
func unbind(action: StringName, descriptor: String) -> Dictionary:
	return _edit(action, descriptor, false)


func profile_names() -> PackedStringArray:
	return store.names()


# Loads, validates and applies a stored profile. Returns the problems, empty = applied.
func _activate(profile_name: String) -> PackedStringArray:
	var loaded: Dictionary = store.load_profile(profile_name)
	if not loaded["ok"]:
		return loaded["errors"]
	var profile: ControlProfile = loaded["profile"]
	var errors: PackedStringArray = profile.apply_to_input_map()
	if not errors.is_empty():
		return errors
	active_name = profile_name
	_base = profile
	_notify_applied()
	return errors


func _edit(action: StringName, descriptor: String, add: bool) -> Dictionary:
	var live: ControlProfile = ControlProfile.from_input_map(active_name)
	var result: Dictionary = live.with_bound(action, descriptor) if add else live.with_unbound(action, descriptor)
	result["also"] = PackedStringArray()
	if not result["ok"]:
		return result
	if add:
		var also := PackedStringArray()
		for other: StringName in InputAdapter.ACTIONS:
			if other != action and live.descriptors_for(other).has(result["descriptor"]):
				also.append(String(other))
		result["also"] = also
	if bool(result["changed"]):
		var edited: ControlProfile = result["profile"]
		var errors: PackedStringArray = edited.apply_to_input_map()
		if not errors.is_empty():
			result["ok"] = false
			result["errors"] = errors
			return result
		_notify_applied()
	return result


func _notify_applied() -> void:
	if resync_input.is_valid():
		resync_input.call()
	applied.emit(active_name)


func _apply_startup_selection() -> void:
	var wanted: String = String(settings.get_value(SETTING_KEY))
	if wanted == active_name:
		return
	var errors: PackedStringArray = _activate(wanted)
	if not errors.is_empty():
		push_warning("ControlProfiles: could not apply control profile '%s' (%s); using the default controls" % [
				wanted, errors[0]])


func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key != SETTING_KEY or String(value) == active_name:
		return
	var errors: PackedStringArray = _activate(String(value))
	if not errors.is_empty():
		push_warning("ControlProfiles: could not apply control profile '%s' (%s)" % [value, errors[0]])


# `Settings.validators`: `set settings.control_profile x` only takes names of valid profiles.
func _check_selection(value: Variant) -> String:
	var loaded: Dictionary = store.load_profile(String(value))
	if loaded["ok"]:
		return ""
	var errors: PackedStringArray = loaded["errors"]
	if errors.size() == 1:
		return errors[0]
	return "profile '%s' is invalid (%d problems; controls use %s lists them)" % [value, errors.size(), value]


# --- Console -----------------------------------------------------------------------------------------------------


func _register_console() -> void:
	if registry == null:
		return
	var controls_args: Array[ConsoleArg] = [
		ConsoleArg.enum_optional(&"sub", SUBCOMMANDS, &"list"),
		ConsoleArg.string_optional(&"name").with_hint("name|action").with_suggestions(_suggest_names),
	]
	registry.register_command(ConsoleCommand.new(&"controls",
			"Control profiles: list them, use or save one, show bindings, delete a user profile", controls_args),
			_cmd_controls, self)
	var bind_args: Array[ConsoleArg] = [
		ConsoleArg.string_required(&"action").with_suggestions(ControlProfile.action_names),
		ConsoleArg.string_required(&"binding").with_suggestions(_suggest_bindings),
	]
	registry.register_command(ConsoleCommand.new(&"bind",
			"Add a binding to an action (session only until controls save); " + ControlProfile.DESCRIPTOR_HELP,
			bind_args), _cmd_bind, self)
	registry.register_command(ConsoleCommand.new(&"unbind",
			"Remove a binding from an action (session only until controls save)", bind_args), _cmd_unbind, self)
	registry.register_provider(&"controls", ConsoleVars.new({
		&"profile": {"get": func() -> String: return active_name,
				"doc": "The profile the input map was loaded from (controls use <name>)"},
		&"profiles": {"get": func() -> Array: return Array(store.names()),
				"doc": "Built-in and saved profiles"},
		&"unsaved": {"get": is_unsaved, "doc": "bind/unbind changes since the profile was used or saved"},
	}), self)


func _suggest_names() -> PackedStringArray:
	var out: PackedStringArray = store.names()
	out.append_array(ControlProfile.action_names())
	return out


func _suggest_bindings() -> PackedStringArray:
	return PackedStringArray(["pad:button:", "pad:axis:", "key:", "mouse:"])


func _cmd_controls(args: Dictionary) -> ConsoleResult:
	var sub: StringName = args[&"sub"]
	var target: String = "" if args[&"name"] == null else String(args[&"name"]).to_lower()
	match sub:
		&"list":
			if not target.is_empty():
				return ConsoleResult.failure("controls list takes no argument (usage: controls list)")
			return ConsoleResult.success(_list_lines())
		&"use":
			if target.is_empty():
				return ConsoleResult.failure("controls use needs a profile name (controls list shows them)")
			return _use(target)
		&"save":
			return _save(target)
		&"show":
			return _show(target)
		&"delete":
			if target.is_empty():
				return ConsoleResult.failure("controls delete needs a profile name (controls list shows them)")
			var refused: String = delete_profile(target)
			if not refused.is_empty():
				return ConsoleResult.failure("controls delete: " + refused)
			return ConsoleResult.line("deleted control profile '%s'" % target)
	return ConsoleResult.failure("unknown controls command '%s'" % sub)


func _cmd_bind(args: Dictionary) -> ConsoleResult:
	return _edit_result(args, true)


func _cmd_unbind(args: Dictionary) -> ConsoleResult:
	return _edit_result(args, false)


func _list_lines() -> PackedStringArray:
	var entries: Array[Dictionary] = store.entries()
	var width: int = 0
	for entry: Dictionary in entries:
		width = maxi(width, String(entry["name"]).length())
	var lines := PackedStringArray(["control profiles (* = in use):"])
	for entry: Dictionary in entries:
		var profile_name: String = entry["name"]
		var is_active: bool = profile_name == active_name
		var kind: String = "built-in" if entry["builtin"] else "user"
		var detail: String = String(entry["description"])
		if not entry["valid"]:
			var problems: PackedStringArray = entry["errors"]
			detail = "INVALID: %s" % problems[0]
		if is_active and is_unsaved():
			detail += " (unsaved changes)"
		lines.append("%s %s  %s  %s" % ["*" if is_active else " ", profile_name.rpad(width), kind.rpad(8), detail])
	return lines


func _use(profile_name: String) -> ConsoleResult:
	var outcome: Dictionary = use(profile_name)
	if not outcome["ok"]:
		return _failure("controls use %s" % profile_name, outcome["errors"])
	var lines := PackedStringArray()
	if outcome["discarded"]:
		lines.append("discarded unsaved bind/unbind changes")
	lines.append("control profile: %s" % profile_name)
	lines.append_array(_keep_hint())
	return ConsoleResult.success(lines)


func _save(requested: String) -> ConsoleResult:
	var errors: PackedStringArray
	var profile_name: String = requested
	if requested.is_empty():
		profile_name = active_name
		if store.is_builtin(active_name):
			return ConsoleResult.failure(("controls save: '%s' is a built-in profile and read-only; give a name: "
					+ "controls save <name>") % active_name)
	errors = save_as(profile_name)
	if not errors.is_empty():
		return _failure("controls save %s" % profile_name, errors)
	var lines := PackedStringArray(["saved %s" % store.path_for(profile_name), "control profile: %s" % profile_name])
	lines.append_array(_keep_hint())
	return ConsoleResult.success(lines)


func _show(requested: String) -> ConsoleResult:
	var live: ControlProfile = ControlProfile.from_input_map(active_name)
	if not requested.is_empty():
		var action := StringName(requested)
		if not InputAdapter.ACTIONS.has(action):
			return ConsoleResult.failure("unknown action '%s'%s" % [requested,
					ConsoleFormat.did_you_mean(requested, ControlProfile.action_names())])
		return ConsoleResult.line(live.describe_action(action))
	var lines := PackedStringArray(["control profile: %s%s" % [active_name, " (unsaved changes)" if is_unsaved() else ""]])
	for action: StringName in InputAdapter.ACTIONS:
		lines.append("  " + live.describe_action(action))
	return ConsoleResult.success(lines)


func _edit_result(args: Dictionary, add: bool) -> ConsoleResult:
	var action := StringName(String(args[&"action"]).to_lower())
	var descriptor: String = args[&"binding"]
	var outcome: Dictionary = bind(action, descriptor) if add else unbind(action, descriptor)
	var verb: String = "bind" if add else "unbind"
	if not outcome["ok"]:
		return _failure("%s %s" % [verb, action], outcome["errors"])
	var lines := PackedStringArray()
	var canonical: String = outcome["descriptor"]
	if not outcome["changed"]:
		lines.append("%s was already bound to %s" % [canonical, action])
	var also: PackedStringArray = outcome["also"]
	if not also.is_empty():
		lines.append("note: %s is also bound to %s" % [canonical, ", ".join(also)])
	lines.append(ControlProfile.from_input_map(active_name).describe_action(action))
	if bool(outcome["changed"]):
		lines.append("session only; controls save <name> keeps it")
	return ConsoleResult.success(lines)


# What to tell the player after a profile was chosen: the choice itself is a setting and survives restarts only
# once `save` has written it.
func _keep_hint() -> PackedStringArray:
	if settings != null and settings.is_unsaved(SETTING_KEY):
		return PackedStringArray(["the choice is session only; type save to start with it next time"])
	return PackedStringArray()


static func _failure(summary: String, errors: PackedStringArray) -> ConsoleResult:
	if errors.size() == 1:
		return ConsoleResult.failure("%s: %s" % [summary, errors[0]])
	var lines := PackedStringArray()
	for problem: String in errors:
		lines.append("  " + problem)
	return ConsoleResult.failure("%s: %d problems, nothing changed" % [summary, errors.size()], lines)
