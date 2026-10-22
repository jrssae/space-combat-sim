class_name ConsoleArg
extends RefCounted
## One typed console argument (architecture §6.4): its kind, optional default, range or choices, how it reads in
## usage strings, and how text becomes a validated value. Also used by ConsoleVars to parse `set` values, so a
## command argument and a writable key share one parser and one set of error messages.
##
## Build them with the static constructors, e.g. `ConsoleArg.bool_optional(&"state")`,
## `ConsoleArg.float_required(&"scale", 0.05, 1.0)`, `ConsoleArg.path_required(&"path", ConsoleArg.PathFilter.WRITABLE)`.

enum Kind { BOOL, INT, FLOAT, STRING, ENUM, PATH, VEC3 }

## Which provider keys a PATH argument accepts (checked by the registry; also narrows Tab completion).
enum PathFilter { ANY, WRITABLE, WRITABLE_BOOL, RESETTABLE }

const TRUE_WORDS: PackedStringArray = ["true", "on", "1", "yes"]
const FALSE_WORDS: PackedStringArray = ["false", "off", "0", "no"]

var name: StringName
var kind: Kind = Kind.STRING
var optional: bool = false
## Value handed to the command when an optional argument is omitted (null = "not given").
var fallback: Variant = null
var min_value: float = -INF
var max_value: float = INF
## ENUM choices: an Array of StringName/String, or a Callable returning one (choices that change at runtime).
var choices: Variant = []
## STRING only: swallow every remaining token, joined by single spaces (`set <path> <value>`).
var rest: bool = false
## Overrides the usage label, e.g. "0.05..1" for `timescale <0.05..1>`.
var hint: String = ""
var path_filter: PathFilter = PathFilter.ANY
## Optional Callable() -> PackedStringArray of Tab-completion candidates (e.g. command names for `help`).
var suggest: Callable = Callable()
## Completion only: this argument is a value for the PATH argument at this index (`set <path> <value>`).
var value_of: int = -1
## VEC3 usage labels, e.g. ["dx", "dy", "dz"].
var components: PackedStringArray = PackedStringArray()


func _init(p_name: StringName = &"", p_kind: Kind = Kind.STRING) -> void:
	name = p_name
	kind = p_kind


static func bool_required(p_name: StringName) -> ConsoleArg:
	return ConsoleArg.new(p_name, Kind.BOOL)


static func bool_optional(p_name: StringName, p_fallback: Variant = null) -> ConsoleArg:
	return ConsoleArg.new(p_name, Kind.BOOL).make_optional(p_fallback)


static func int_required(p_name: StringName, p_min: float = -INF, p_max: float = INF) -> ConsoleArg:
	return ConsoleArg.new(p_name, Kind.INT).with_range(p_min, p_max)


static func int_optional(p_name: StringName, p_fallback: Variant = null, p_min: float = -INF,
		p_max: float = INF) -> ConsoleArg:
	return ConsoleArg.new(p_name, Kind.INT).with_range(p_min, p_max).make_optional(p_fallback)


static func float_required(p_name: StringName, p_min: float = -INF, p_max: float = INF) -> ConsoleArg:
	return ConsoleArg.new(p_name, Kind.FLOAT).with_range(p_min, p_max)


static func float_optional(p_name: StringName, p_fallback: Variant = null, p_min: float = -INF,
		p_max: float = INF) -> ConsoleArg:
	return ConsoleArg.new(p_name, Kind.FLOAT).with_range(p_min, p_max).make_optional(p_fallback)


static func string_required(p_name: StringName) -> ConsoleArg:
	return ConsoleArg.new(p_name, Kind.STRING)


static func string_optional(p_name: StringName, p_fallback: Variant = null) -> ConsoleArg:
	return ConsoleArg.new(p_name, Kind.STRING).make_optional(p_fallback)


## A required STRING that takes the rest of the line.
static func string_rest(p_name: StringName) -> ConsoleArg:
	var arg := ConsoleArg.new(p_name, Kind.STRING)
	arg.rest = true
	return arg


static func enum_required(p_name: StringName, p_choices: Variant) -> ConsoleArg:
	var arg := ConsoleArg.new(p_name, Kind.ENUM)
	arg.choices = p_choices
	return arg


static func enum_optional(p_name: StringName, p_choices: Variant, p_fallback: Variant = null) -> ConsoleArg:
	return ConsoleArg.enum_required(p_name, p_choices).make_optional(p_fallback)


static func path_required(p_name: StringName, p_filter: PathFilter = PathFilter.ANY) -> ConsoleArg:
	var arg := ConsoleArg.new(p_name, Kind.PATH)
	arg.path_filter = p_filter
	return arg


static func path_optional(p_name: StringName, p_filter: PathFilter = PathFilter.ANY,
		p_fallback: Variant = null) -> ConsoleArg:
	return ConsoleArg.path_required(p_name, p_filter).make_optional(p_fallback)


## Three numbers, typed as three tokens (`1 2 3`) or one (`1,2,3`).
static func vec3_required(p_name: StringName, p_components: PackedStringArray = PackedStringArray()) -> ConsoleArg:
	var arg := ConsoleArg.new(p_name, Kind.VEC3)
	arg.components = p_components
	return arg


func make_optional(p_fallback: Variant = null) -> ConsoleArg:
	optional = true
	fallback = p_fallback
	return self


func with_range(p_min: float, p_max: float) -> ConsoleArg:
	min_value = p_min
	max_value = p_max
	return self


func with_hint(p_hint: String) -> ConsoleArg:
	hint = p_hint
	return self


func with_suggestions(p_suggest: Callable) -> ConsoleArg:
	suggest = p_suggest
	return self


func choice_list() -> PackedStringArray:
	var raw: Variant = choices.call() if choices is Callable else choices
	var out := PackedStringArray()
	if raw is Array or raw is PackedStringArray:
		for choice: Variant in raw:
			out.append(String(choice))
	return out


## How the argument reads in usage strings: `<path>`, `[on|off]`, `<0.05..1>`, `<dx> <dy> <dz>`.
func usage() -> String:
	if kind == Kind.VEC3:
		var labels: PackedStringArray = components
		if labels.size() != 3:
			labels = PackedStringArray(["%s_x" % name, "%s_y" % name, "%s_z" % name])
		var parts := PackedStringArray()
		for label: String in labels:
			parts.append(("[%s]" if optional else "<%s>") % label)
		return " ".join(parts)
	var label: String = hint
	if label.is_empty():
		match kind:
			Kind.BOOL:
				label = "on|off"
			Kind.ENUM:
				label = "|".join(choice_list())
			_:
				label = String(name)
	return ("[%s]" if optional else "<%s>") % label


## Label used in error messages for command arguments.
func subject() -> String:
	return "<%s>" % name


## Parses console text into a validated value. Returns {"ok": bool, "value": Variant, "error": String}.
## `what` names the thing in error messages (default: the argument, e.g. "<frames>"; ConsoleVars passes the path).
func parse_text(text: String, what: String = "") -> Dictionary:
	var who: String = what if not what.is_empty() else subject()
	var t: String = text.strip_edges()
	match kind:
		Kind.BOOL:
			var lower: String = t.to_lower()
			if TRUE_WORDS.has(lower):
				return _ok(true)
			if FALSE_WORDS.has(lower):
				return _ok(false)
			return _fail("%s expects on/off (or true/false, 1/0), got '%s'" % [who, t])
		Kind.INT:
			if not t.is_valid_int():
				return _fail("%s expects an integer, got '%s'" % [who, t])
			return validate(t.to_int(), what)
		Kind.FLOAT:
			if not t.is_valid_float():
				return _fail("%s expects a number, got '%s'" % [who, t])
			return validate(t.to_float(), what)
		Kind.ENUM:
			for choice: String in choice_list():
				if choice.to_lower() == t.to_lower():
					return _ok(StringName(choice))
			return _fail("%s expects one of %s, got '%s'%s" % [who, "|".join(choice_list()), t,
					ConsoleFormat.did_you_mean(t, choice_list())])
		Kind.PATH:
			# Only the shape is checked here; the registry resolves it and explains what is wrong with it.
			if t.is_empty():
				return _fail("%s expects provider.key" % who)
			return _ok(t)
		Kind.VEC3:
			var parts := PackedStringArray()
			for piece: String in t.replace("(", " ").replace(")", " ").replace(",", " ").split(" ", false):
				parts.append(piece)
			if parts.size() != 3:
				return _fail("%s expects three numbers (x y z), got '%s'" % [who, t])
			var comps: Array[float] = []
			for piece: String in parts:
				if not piece.is_valid_float():
					return _fail("%s expects three numbers (x y z), got '%s'" % [who, t])
				comps.append(piece.to_float())
			return validate(Vector3(comps[0], comps[1], comps[2]), what)
	return _ok(t)  # STRING


## Validates (and losslessly coerces) an already typed value. Same result shape as `parse_text`.
func validate(value: Variant, what: String = "") -> Dictionary:
	var who: String = what if not what.is_empty() else subject()
	match kind:
		Kind.BOOL:
			if typeof(value) != TYPE_BOOL:
				return _fail("%s expects a bool, got %s" % [who, type_string(typeof(value))])
			return _ok(value)
		Kind.INT:
			if typeof(value) == TYPE_FLOAT and float(value) == floorf(float(value)):
				value = int(value)
			if typeof(value) != TYPE_INT:
				return _fail("%s expects an integer, got %s" % [who, type_string(typeof(value))])
			return _check_range(who, int(value), float(value))
		Kind.FLOAT:
			if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
				return _fail("%s expects a number, got %s" % [who, type_string(typeof(value))])
			var f: float = float(value)
			if is_nan(f) or is_inf(f):
				return _fail("%s expects a finite number, got %s" % [who, f])
			return _check_range(who, f, f)
		Kind.ENUM:
			if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
				return _fail("%s expects one of %s" % [who, "|".join(choice_list())])
			return parse_text(String(value), what)
		Kind.VEC3:
			if typeof(value) != TYPE_VECTOR3:
				return _fail("%s expects a Vector3, got %s" % [who, type_string(typeof(value))])
			var v: Vector3 = value
			if not v.is_finite():
				return _fail("%s expects finite numbers" % who)
			return _ok(v)
		Kind.PATH, Kind.STRING:
			if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
				return _fail("%s expects text, got %s" % [who, type_string(typeof(value))])
			return parse_text(String(value), what) if kind == Kind.PATH else _ok(String(value))
	return _fail("%s has an unknown kind" % who)


## Tokens this argument consumes from a statement (VEC3 takes three unless typed as one "x,y,z" token).
func token_span(tokens: PackedStringArray, start: int) -> int:
	if rest:
		return maxi(0, tokens.size() - start)
	if kind == Kind.VEC3 and start < tokens.size() and not tokens[start].contains(","):
		return mini(3, tokens.size() - start)
	return 1 if start < tokens.size() else 0


func _check_range(who: String, value: Variant, as_float: float) -> Dictionary:
	if as_float < min_value or as_float > max_value:
		if is_inf(max_value):
			return _fail("%s must be >= %s, got %s" % [who, _bound(min_value), value])
		if is_inf(min_value):
			return _fail("%s must be <= %s, got %s" % [who, _bound(max_value), value])
		return _fail("%s must be in %s..%s, got %s" % [who, _bound(min_value), _bound(max_value), value])
	return _ok(value)


func _bound(x: float) -> String:
	if kind == Kind.INT:
		return str(int(x))
	return str(x)


static func _ok(value: Variant) -> Dictionary:
	return {"ok": true, "value": value, "error": ""}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
