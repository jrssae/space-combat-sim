class_name ConsoleFormat
extends RefCounted
## How the console prints values and finds "did you mean" suggestions (architecture §6.4), pure.
## One formatter for every provider, so values look the same everywhere: floats and vector components to 2
## decimals, bools as true/false, units appended after a space.

const DECIMALS: int = 2


## Formats a value for display, with an optional unit ("42.10 m/s"). A missing value is just "none", without the unit
## (`targeting.range_m = none` when nothing is selected).
static func value(v: Variant, unit: String = "") -> String:
	var text: String = _value(v)
	return text if unit.is_empty() or typeof(v) == TYPE_NIL else "%s %s" % [text, unit]


## "path = value unit", with " *" when the value is modified (unsaved settings).
static func key_value(path: String, v: Variant, unit: String = "", modified: bool = false) -> String:
	var text: String = "%s = %s" % [path, value(v, unit)]
	return text + " *" if modified else text


static func number(x: float) -> String:
	if is_nan(x):
		return "nan"
	if is_inf(x):
		return "inf" if x > 0.0 else "-inf"
	if x == 0.0:
		return "0.00"  # also -0.0
	# Fixed 2 decimals would print tiny non-zero values as 0.00; show their magnitude instead.
	if absf(x) < 0.005:
		return String.num_scientific(x)
	return String.num(x, DECIMALS).pad_decimals(DECIMALS)


## A token as it must be typed to round-trip through ConsoleTokenizer.
static func quote_token(token: String) -> String:
	var needs_quotes: bool = token.is_empty()
	for c: String in [" ", "\t", "\"", ";", "#", "\\", "\n"]:
		if token.contains(c):
			needs_quotes = true
			break
	if not needs_quotes:
		return token
	return "\"%s\"" % token.replace("\\", "\\\\").replace("\"", "\\\"")


static func join_tokens(tokens: PackedStringArray) -> String:
	var parts := PackedStringArray()
	for token: String in tokens:
		parts.append(quote_token(token))
	return " ".join(parts)


## The candidate closest to `word`, or "" if none is plausibly a typo of it. Case-insensitive; a candidate that
## starts with `word` counts as close.
static func suggest(word: String, candidates: PackedStringArray) -> String:
	var needle: String = word.to_lower()
	if needle.is_empty():
		return ""
	var best: String = ""
	var best_distance: int = 1 << 30
	for candidate: String in candidates:
		var hay: String = candidate.to_lower()
		var distance: int = edit_distance(needle, hay)
		if hay.begins_with(needle) and needle.length() >= 2:
			distance = mini(distance, 1)
		if distance < best_distance or (distance == best_distance and candidate < best):
			best = candidate
			best_distance = distance
	if best_distance <= _typo_budget(needle.length()):
		return best
	return ""


## Optimal string alignment distance: Levenshtein plus adjacent transpositions ("hepl" -> "help" is 1).
static func edit_distance(a: String, b: String) -> int:
	var n: int = a.length()
	var m: int = b.length()
	if n == 0:
		return m
	if m == 0:
		return n
	var width: int = m + 1
	var d := PackedInt32Array()
	d.resize((n + 1) * width)
	for i: int in n + 1:
		d[i * width] = i
	for j: int in m + 1:
		d[j] = j
	for i: int in range(1, n + 1):
		for j: int in range(1, m + 1):
			var cost: int = 0 if a[i - 1] == b[j - 1] else 1
			var best: int = mini(mini(d[(i - 1) * width + j] + 1, d[i * width + j - 1] + 1),
					d[(i - 1) * width + j - 1] + cost)
			if i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]:
				best = mini(best, d[(i - 2) * width + j - 2] + 1)
			d[i * width + j] = best
	return d[n * width + m]


## " (did you mean x?)" or "".
static func did_you_mean(word: String, candidates: PackedStringArray) -> String:
	var guess: String = suggest(word, candidates)
	return "" if guess.is_empty() else " (did you mean %s?)" % guess


static func _typo_budget(length: int) -> int:
	if length <= 3:
		return 1
	if length <= 7:
		return 2
	return 3


static func _value(v: Variant) -> String:
	match typeof(v):
		TYPE_NIL:
			return "none"
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT:
			return str(v)
		TYPE_FLOAT:
			return number(float(v))
		TYPE_STRING, TYPE_STRING_NAME:
			return String(v)
		TYPE_VECTOR2:
			var v2: Vector2 = v
			return "(%s, %s)" % [number(v2.x), number(v2.y)]
		TYPE_VECTOR3:
			var v3: Vector3 = v
			return "(%s, %s, %s)" % [number(v3.x), number(v3.y), number(v3.z)]
		TYPE_VECTOR4:
			var v4: Vector4 = v
			return "(%s, %s, %s, %s)" % [number(v4.x), number(v4.y), number(v4.z), number(v4.w)]
		TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I:
			return str(v)
		TYPE_DICTIONARY:
			var parts := PackedStringArray()
			var dict: Dictionary = v
			for key: Variant in dict.keys():
				parts.append("%s: %s" % [_value(key), _value(dict[key])])
			return "{%s}" % ", ".join(parts)
		TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
				TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, \
				TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, \
				TYPE_PACKED_COLOR_ARRAY:
			var items := PackedStringArray()
			for item: Variant in v:
				items.append(_value(item))
			return "[%s]" % ", ".join(items)
		TYPE_OBJECT:
			if v == null or not is_instance_valid(v):
				return "none"
			return str(v)
	return str(v)
