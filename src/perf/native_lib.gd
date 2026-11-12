class_name NativeLib
extends RefCounted
## The only way GDScript reaches the native library (M4-T05a, architecture §17.5). Callers never name a native class in
## code, so a missing or stale library never breaks parsing. The library is required (M4-T37): `Main` refuses to start
## when `refusal` names a missing class.

## Every class the game needs from the native library (M4-T37: the library is required, Q57 and Q67).
const REQUIRED: Array[StringName] = [&"ScsSimCore", &"ScsBrains", &"ScsFlightStep", &"ScsCannons", &"ScsBoltSync",
		&"ScsContactField", &"ScsPilotKernels", &"ScsHitSweep", &"ScsRamPhase", &"ScsRamTracker", &"ScsWeaponRows", &"ScsNativeProbe",
		&"ScsEphemeris", &"ScsStaticRows"]
## The user argument that adds a class to the required list: the refusal's test seam (`test_native_required`).
const REQUIRE_ARG: String = "--native-require="

## The classes of `classes` this process lacks; by default the required ones plus any named by `--native-require=`.
static func missing(classes: Array[StringName] = []) -> PackedStringArray:
	var wanted: Array[StringName] = classes
	if wanted.is_empty():
		wanted = REQUIRED.duplicate()
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with(REQUIRE_ARG):
				wanted.append(StringName(arg.trim_prefix(REQUIRE_ARG)))
	var out := PackedStringArray()
	for native_class: StringName in wanted:
		if not has_class(native_class):
			out.append(String(native_class))
	return out


## Why the game cannot start (the missing classes and how to build the library), or "" when nothing is missing.
static func refusal(classes: Array[StringName] = []) -> String:
	var lacking: PackedStringArray = missing(classes)
	if lacking.is_empty():
		return ""
	return ("The native library bin/libscs_native.so is missing or out of date (it lacks %s). The game needs it: build it "
			+ "with scripts/build_native.sh (it needs Rust's cargo; install it with rustup, https://rustup.rs), run "
			+ "godot --headless --path . --import once so Godot registers it, then start again.") % ", ".join(lacking)


## Whether `native_class` is registered in this process.
static func has_class(native_class: StringName) -> bool:
	return ClassDB.class_exists(native_class) and ClassDB.can_instantiate(native_class)


## A new `native_class`, or null when the library does not provide it.
static func instantiate(native_class: StringName) -> Object:
	if not has_class(native_class):
		return null
	return ClassDB.instantiate(native_class)


## The library's version as `native_class` reports it, or "" when the library does not provide that class.
static func version(native_class: StringName) -> String:
	if not has_class(native_class) or not ClassDB.class_has_method(native_class, &"version"):
		return ""
	return String(ClassDB.class_call_static(native_class, &"version"))
