class_name NativeLib
extends RefCounted
## The only way GDScript reaches the optional native library (M4-T05a, architecture §17.5). Callers never name a
## native class in code, so a missing or stale library never breaks parsing: they ask here, get null when the
## library lacks the class or `perf_native` is off, and run their GDScript path instead.

# `perf_native` as last read (-1: read it on the next ask), kept current through `Settings.changed`.
static var _enabled: int = -1


## Whether the native library registered `native_class` in this process.
static func has_class(native_class: StringName) -> bool:
	return ClassDB.class_exists(native_class) and ClassDB.can_instantiate(native_class)


## Whether the `perf_native` setting asks for native code. Cheap enough to ask on every call, and follows the setting at
## once, so long-lived facades can ask per call instead of deciding once.
static func enabled() -> bool:
	if _enabled < 0:
		_enabled = 1 if bool(Settings.get_value(&"perf_native")) else 0
		if not Settings.changed.is_connected(_on_setting_changed):
			Settings.changed.connect(_on_setting_changed)
	return _enabled == 1


static func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key == &"perf_native":
		_enabled = -1


## A new `native_class`, or null when `perf_native` is off or the library does not provide it.
static func instantiate(native_class: StringName) -> Object:
	if not enabled() or not has_class(native_class):
		return null
	return ClassDB.instantiate(native_class)


## The library's version as `native_class` reports it, or "" when the library does not provide that class.
static func version(native_class: StringName) -> String:
	if not has_class(native_class) or not ClassDB.class_has_method(native_class, &"version"):
		return ""
	return String(ClassDB.class_call_static(native_class, &"version"))
