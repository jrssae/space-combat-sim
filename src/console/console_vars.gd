class_name ConsoleVars
extends ConsoleStateProvider
## ConsoleStateProvider built from a Dictionary, the usual way a subsystem exposes state (architecture §6.4):
##
##     DebugConsole.registry.register_provider(&"ship", ConsoleVars.new({
##         &"speed":     {"get": func() -> float: return linear_velocity.length(), "type": TYPE_FLOAT, "unit": "m/s"},
##         &"assist_on": {"get": func() -> bool: return assist_on, "set": set_assist, "type": TYPE_BOOL},
##     }), self)
##
## Entry fields: "get" (Callable() -> value, required); "set" (Callable(value), makes the key writable; may return
## nothing, an Error, a bool, or a String that is empty on success and the reason otherwise); "type" (a Variant.Type:
## TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR3; required for writable keys);
## "min"/"max" (numbers); "choices" (Array or Callable() -> Array, makes a string key an enum); "unit"; "doc";
## "reset" (Callable() restoring the default, same return convention as "set"); "modified" (Callable() -> bool).
## Keys keep the Dictionary's order.

var _entries: Dictionary = {}
var _args: Dictionary = {}  # key -> ConsoleArg, built lazily for writable keys


func _init(entries: Dictionary = {}) -> void:
	for key: Variant in entries.keys():
		var entry: Dictionary = entries[key]
		assert(entry.has("get") and entry["get"] is Callable, "ConsoleVars: '%s' needs a \"get\" Callable" % key)
		_entries[StringName(key)] = entry


func keys() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: StringName in _entries.keys():
		out.append(key)
	return out


func has_key(key: StringName) -> bool:
	return _entries.has(key)


func read(key: StringName) -> Variant:
	if not _entries.has(key):
		return null
	var getter: Callable = _entries[key]["get"]
	return getter.call() if getter.is_valid() else null


func unit(key: StringName) -> String:
	return str(_entry(key).get("unit", ""))


func doc(key: StringName) -> String:
	return str(_entry(key).get("doc", ""))


func is_writable(key: StringName) -> bool:
	var setter: Variant = _entry(key).get("set")
	return setter is Callable and (setter as Callable).is_valid()


func value_arg(key: StringName) -> ConsoleArg:
	if not is_writable(key):
		return null
	if not _args.has(key):
		_args[key] = _make_arg(key, _entry(key))
	return _args[key]


func write(key: StringName, value: Variant) -> String:
	if not is_writable(key):
		return "%s is read-only" % key
	var setter: Callable = _entry(key)["set"]
	return _outcome(setter.call(value))


func can_reset(key: StringName) -> bool:
	var resetter: Variant = _entry(key).get("reset")
	return resetter is Callable and (resetter as Callable).is_valid()


func reset(key: StringName) -> String:
	if not can_reset(key):
		return "%s has no default" % key
	var resetter: Callable = _entry(key)["reset"]
	return _outcome(resetter.call())


func is_modified(key: StringName) -> bool:
	var probe: Variant = _entry(key).get("modified")
	if probe is Callable and (probe as Callable).is_valid():
		return bool((probe as Callable).call())
	return false


func _entry(key: StringName) -> Dictionary:
	return _entries.get(key, {})


static func _make_arg(key: StringName, entry: Dictionary) -> ConsoleArg:
	var value_type: int = int(entry.get("type", TYPE_STRING))
	var low: float = float(entry.get("min", -INF))
	var high: float = float(entry.get("max", INF))
	if entry.has("choices"):
		return ConsoleArg.enum_required(key, entry["choices"])
	match value_type:
		TYPE_BOOL:
			return ConsoleArg.bool_required(key)
		TYPE_INT:
			return ConsoleArg.int_required(key, low, high)
		TYPE_FLOAT:
			return ConsoleArg.float_required(key, low, high)
		TYPE_VECTOR3:
			return ConsoleArg.vec3_required(key)
	return ConsoleArg.string_required(key)


# Setters and resetters may return nothing, an Error, a bool or a message; "" means it worked.
static func _outcome(returned: Variant) -> String:
	match typeof(returned):
		TYPE_NIL:
			return ""
		TYPE_INT:
			return "" if int(returned) == OK else error_string(int(returned))
		TYPE_BOOL:
			return "" if bool(returned) else "rejected"
		TYPE_STRING, TYPE_STRING_NAME:
			return String(returned)
	return ""
