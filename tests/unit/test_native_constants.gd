extends GutTest
## M5-T36 (L13): every constant the native code mirrors from GDScript equals its GDScript twin, so changing one side alone
## fails here. The table is `ScsSimCore.constants()` (native/src/constants.rs): `Class.CONST`, with `@module` for a second
## Rust copy and `#size` for the size of a twin array.

var _core: Object


func before_each() -> void:
	_core = ClassDB.instantiate(SimCore.NATIVE_CLASS)


# The script of the global class `name`.
func _script_of(class_name_: String) -> Script:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if String(entry["class"]) == class_name_:
			return load(String(entry["path"])) as Script
	return null


func test_the_table_is_not_empty() -> void:
	assert_gt((_core.constants() as Dictionary).size(), 30)


func test_every_mirrored_constant_equals_its_gdscript_twin() -> void:
	var table: Dictionary = _core.constants()
	var drifted := PackedStringArray()
	for key: String in table:
		var twin: String = key.split("@")[0].split("#")[0]
		var parts: PackedStringArray = twin.split(".")
		var script: Script = _script_of(parts[0])
		if script == null or not script.get_script_constant_map().has(parts[1]):
			drifted.append("%s: no twin" % key)
			continue
		var theirs: Variant = script.get_script_constant_map()[parts[1]]
		if key.contains("#size"):
			theirs = (theirs as Array).size()
		if typeof(theirs) == TYPE_INT:
			theirs = float(theirs)
		if theirs != table[key]:
			drifted.append("%s: native %s, GDScript %s" % [key, table[key], theirs])
	assert_eq(drifted.size(), 0, "native constants drifted from GDScript: %s" % [drifted])
