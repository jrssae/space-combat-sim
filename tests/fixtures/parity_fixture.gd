class_name ParityFixture
extends RefCounted
## Recorded reference outputs for the parity tests (M4-T37, Q67). Before T37 removed the GDScript paths, each parity test
## recorded what its GDScript reference gave on the test's seeds into `tests/fixtures/parity/<file>.json`; the test now
## compares the native path with the recording, so it still fails when the native result moves.
##
## Recording: run the test with `SCS_RECORD_FIXTURES=1` and the recorder (`expected`'s callable) writes its case instead of
## reading it. The recordings were taken at `0586e3e`, whose game code is the tag `m4-gdscript-reference`'s (see the
## README in `tests/fixtures/parity/`); a recording taken after T37 records the native path, so re-record only on purpose
## and say so in the commit.
##
## Values are stored as JSON: vectors as `[x, y, z]`, packed arrays as lists, integers past 2^53 as strings, floats at full
## precision, so a recording compares bit for bit. Bulky outputs are stored as a `digest` (SHA-256 of their text) beside the
## counts a reviewer can read.

const DIR: String = "res://tests/fixtures/parity/"
const ENV: String = "SCS_RECORD_FIXTURES"
const _MAX_EXACT_INT: int = 9007199254740992  # 2^53: integers past it lose bits as JSON numbers

static var _cache: Dictionary = {}


## Whether this run records the references instead of reading them. Never on CI (`CI=true`): a recording there would
## rewrite the references from whatever code runs, unreviewed.
static func recording() -> bool:
	if OS.get_environment(ENV) != "1":
		return false
	if OS.get_environment("CI") == "true":
		push_error("ParityFixture: %s=1 on CI; recording refuses there, the stored references are read" % ENV)
		return false
	return true


## The recorded case `case` of `file`; when recording, `recorder` (which may await) is run and its value written first.
## The value comes back in its stored form (see `encode`); await it.
static func expected(file: String, case: String, recorder: Callable = Callable()) -> Variant:
	if recording() and recorder.is_valid():
		var value: Variant = await recorder.call()
		record(file, case, value)
	return stored(file, case)


## Writes case `case` of `file` (merged into the file's other cases).
static func record(file: String, case: String, value: Variant) -> void:
	var data: Dictionary = _read(file)
	data[case] = encode(value)
	var keys: Array = data.keys()
	keys.sort()
	var ordered: Dictionary = {}
	for key: Variant in keys:
		ordered[key] = data[key]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var f := FileAccess.open(_path(file), FileAccess.WRITE)
	f.store_string(JSON.stringify(ordered, "  ", false, true) + "\n")
	f.close()
	_cache[file] = ordered


## Case `case` of `file` as stored, or null when it was never recorded.
static func stored(file: String, case: String) -> Variant:
	return _read(file).get(case)


## `value` in its stored form: what `stored` gives back for it, so `encode(native) == stored(...)` compares exactly.
static func encode(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(_plain(value), "", false, true))


## A short, stable digest of `value` (SHA-256 of its stored text), for outputs too bulky to keep whole.
static func digest(value: Variant) -> String:
	return JSON.stringify(_plain(value), "", true, true).sha256_text()


static func _path(file: String) -> String:
	return DIR + file + ".json"


static func _read(file: String) -> Dictionary:
	if _cache.has(file):
		return _cache[file]
	var data: Dictionary = {}
	if FileAccess.file_exists(_path(file)):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path(file)))
		if parsed is Dictionary:
			data = parsed
	_cache[file] = data
	return data


# `value` as JSON-ready lists, dictionaries, strings, booleans and numbers.
static func _plain(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [value.x, value.y, value.z]
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_BASIS:
			var b: Basis = value
			return [_plain(b.x), _plain(b.y), _plain(b.z)]
		TYPE_COLOR:
			var c: Color = value
			return [c.r, c.g, c.b, c.a]
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return String(value)
		TYPE_INT:
			return str(value) if absi(value) > _MAX_EXACT_INT else value
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			for key: Variant in (value as Dictionary).keys():
				out[str(key)] = _plain(value[key])
			return out
		TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, \
				TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, \
				TYPE_PACKED_COLOR_ARRAY:
			var out: Array = []
			for item: Variant in value:
				out.append(_plain(item))
			return out
	return value
