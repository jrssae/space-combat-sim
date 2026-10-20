extends Node
## Settings autoload: schema-driven typed values (architecture §6.4).
## `set_value` applies immediately and marks the key unsaved; only `save()` writes `config_path`.
## Pad calibration (`[pads]`, trigger rest per GUID) is data owned by the input layer, not a schema key.

signal changed(key: StringName, value: Variant)

const DEFAULT_CONFIG_PATH := "user://settings.cfg"
const DEFAULT_JOY_MAPPINGS_PATH := "user://gamecontrollerdb.txt"
const _SECTION := "settings"
const _PADS_SECTION := "pads"

## Overridable before `_ready` (tests point these at scratch files).
var config_path: String = DEFAULT_CONFIG_PATH
var joy_mappings_path: String = DEFAULT_JOY_MAPPINGS_PATH

var schema := SettingsSchema.new()

var _values: Dictionary = {}
var _unsaved: Dictionary = {}
var _pad_trigger_rest: Dictionary = {}
var _last_error: String = ""


func _init() -> void:
	_load_defaults()


func _ready() -> void:
	revert()
	_apply_joy_mappings()


func get_value(key: StringName) -> Variant:
	return _values.get(key)


## Validated write. Applies now, marks the key unsaved, emits `changed`. Never touches the disk.
func set_value(key: StringName, value: Variant) -> Error:
	var result: Dictionary = schema.validate(key, value)
	if not result["ok"]:
		_last_error = result["error"]
		return ERR_INVALID_PARAMETER
	_last_error = ""
	_store(key, result["value"], true)
	return OK


## Like `set_value`, but from text (console, config files): "on", "0.2", "cockpit".
func set_from_text(key: StringName, text: String) -> Error:
	var result: Dictionary = schema.parse(key, text)
	if not result["ok"]:
		_last_error = result["error"]
		return ERR_INVALID_PARAMETER
	return set_value(key, result["value"])


## Back to the schema default for this session (unsaved until `save`).
func reset(key: StringName) -> Error:
	if not schema.has_key(key):
		_last_error = "unknown setting '%s'" % key
		return ERR_INVALID_PARAMETER
	_last_error = ""
	_store(key, schema.get_default(key), true)
	return OK


func is_unsaved(key: StringName) -> bool:
	return _unsaved.has(key)


func has_unsaved() -> bool:
	return not _unsaved.is_empty()


## Message for the last rejected write, empty after a successful one.
func get_last_error() -> String:
	return _last_error


func keys() -> Array[StringName]:
	return schema.keys()


func save() -> Error:
	var cfg := ConfigFile.new()
	for key: StringName in schema.keys():
		cfg.set_value(_SECTION, String(key), _to_config(key, _values[key]))
	for guid: String in _pad_trigger_rest.keys():
		cfg.set_value(_PADS_SECTION, guid, _pad_trigger_rest[guid])
	var err: Error = cfg.save(config_path)
	if err == OK:
		_unsaved.clear()
	else:
		_last_error = "could not write %s (%s)" % [config_path, error_string(err)]
	return err


## Reload from disk (defaults for anything missing or invalid). Drops unsaved changes.
func revert() -> Error:
	var loaded: Dictionary = {}
	for key: StringName in schema.keys():
		loaded[key] = schema.get_default(key)
	var pads: Dictionary = {}
	var cfg := ConfigFile.new()
	var err: Error = OK
	if FileAccess.file_exists(config_path):
		err = cfg.load(config_path)
		if err == OK:
			for key: StringName in schema.keys():
				var file_key: String = _file_key(cfg, key)
				if not file_key.is_empty():
					var result: Dictionary = schema.validate(key, _from_config(key, cfg.get_value(_SECTION, file_key)))
					if result["ok"]:
						loaded[key] = result["value"]
					else:
						push_warning("Settings: ignoring %s in %s: %s" % [file_key, config_path, result["error"]])
			if cfg.has_section(_PADS_SECTION):
				for guid: String in cfg.get_section_keys(_PADS_SECTION):
					pads[guid] = float(cfg.get_value(_PADS_SECTION, guid))
		else:
			push_warning("Settings: could not read %s (%s); using defaults" % [config_path, error_string(err)])
	_unsaved.clear()
	_pad_trigger_rest = pads
	for key: StringName in schema.keys():
		_store(key, loaded[key], false)
	return err


## Trigger rest value (0 or -1) last calibrated for a pad GUID, or `fallback` if unknown.
func get_trigger_rest(guid: String, fallback: float = 0.0) -> float:
	return float(_pad_trigger_rest.get(guid, fallback))


func set_trigger_rest(guid: String, rest: float) -> void:
	_pad_trigger_rest[guid] = rest


func get_pad_calibration() -> Dictionary:
	return _pad_trigger_rest.duplicate()


func _load_defaults() -> void:
	for key: StringName in schema.keys():
		_values[key] = schema.get_default(key)


func _store(key: StringName, value: Variant, mark_unsaved: bool) -> void:
	var previous: Variant = _values.get(key)
	_values[key] = value
	if mark_unsaved:
		_unsaved[key] = true
	if previous != value:
		changed.emit(key, value)


# The name `key` is stored under in a loaded file: its current name, else a former one (SettingsSchema.RENAMED),
# else "" when the file has neither.
func _file_key(cfg: ConfigFile, key: StringName) -> String:
	if cfg.has_section_key(_SECTION, String(key)):
		return String(key)
	for old: StringName in schema.old_names(key):
		if cfg.has_section_key(_SECTION, String(old)):
			return String(old)
	return ""


# Enums are stored as plain strings so the file stays readable and hand-editable.
func _to_config(key: StringName, value: Variant) -> Variant:
	if schema.get_type(key) == SettingsSchema.TYPE_ENUM:
		return String(value)
	return value


func _from_config(key: StringName, value: Variant) -> Variant:
	if schema.get_type(key) == SettingsSchema.TYPE_ENUM and typeof(value) == TYPE_STRING:
		return StringName(value)
	return value


# SDL mapping lines for pads that land on the wrong JOY_* indices (architecture §6.1).
func _apply_joy_mappings() -> void:
	if not FileAccess.file_exists(joy_mappings_path):
		return
	var text: String = FileAccess.get_file_as_string(joy_mappings_path)
	for raw_line: String in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		Input.add_joy_mapping(line, true)
