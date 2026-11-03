class_name NativeLib
extends RefCounted
## The only way GDScript reaches the optional native library (M4-T05a, architecture §17.5). Callers never name a
## native class in code, so a missing or stale library never breaks parsing: they ask here, get null when the
## library lacks the class or `perf_native` is off, and run their GDScript path instead.


## Whether the native library registered `native_class` in this process.
static func has_class(native_class: StringName) -> bool:
	return ClassDB.class_exists(native_class) and ClassDB.can_instantiate(native_class)


## Whether the `perf_native` setting asks for native code.
static func enabled() -> bool:
	return bool(Settings.get_value(&"perf_native"))


## A new `native_class`, or null when `perf_native` is off or the library does not provide it.
static func instantiate(native_class: StringName) -> Object:
	if not enabled() or not has_class(native_class):
		return null
	return ClassDB.instantiate(native_class)


## The library's version, or "" when it is not loaded.
static func version() -> String:
	if not has_class(NativeProbe.NATIVE_CLASS):
		return ""
	return String(ClassDB.class_call_static(NativeProbe.NATIVE_CLASS, &"version"))
