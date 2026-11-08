class_name NativeBoundaryBench
extends RefCounted
## Measures what crossing from GDScript into the native library costs (M4-T05a), at the sizes the contact kernel
## will use: one call per AI ship per query, with a packed array of every body in and the indices in range out.
## The GDScript columns time the same work written in GDScript, as the yardstick. Wall-clock numbers for the Cycle log and
## the console (`native bench`), never for assertions.

const SIZES: PackedInt32Array = [100, 200, 300]
const RANGE_M: float = 5000.0
const SEED: int = 5
const WARMUP_CALLS: int = 20


## One row per measurement: `name`, `n` (points per call, 0 for echo), `calls`, `native_us` and `gdscript_us`
## (per call; -1 when the library is not loaded) and the indices found over all calls, which must match.
static func run(calls: int = 300, sizes: PackedInt32Array = SIZES) -> Array[Dictionary]:
	var native := NativeProbe.new()
	var has_native: bool = native.path() == &"native"
	var rows: Array[Dictionary] = []
	rows.append({"name": "echo", "n": 0, "calls": calls,
			"native_us": _time_echo(native.echo, calls) if has_native else -1.0,
			"gdscript_us": _time_echo(_script_echo, calls), "native_found": 0, "gdscript_found": 0})
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for n: int in sizes:
		var points := PackedVector3Array()
		for i: int in n:
			points.append(Vector3(rng.randf_range(-RANGE_M, RANGE_M), rng.randf_range(-RANGE_M, RANGE_M),
					rng.randf_range(-RANGE_M, RANGE_M)))
		var row: Dictionary = {"name": "in_range", "n": n, "calls": calls, "native_us": -1.0, "native_found": 0}
		if has_native:
			var timed: Array = _time_in_range(native.in_range, points, calls)
			row["native_us"] = timed[0]
			row["native_found"] = timed[1]
		var timed_script: Array = _time_in_range(_script_in_range, points, calls)
		row["gdscript_us"] = timed_script[0]
		row["gdscript_found"] = timed_script[1]
		rows.append(row)
	return rows


## The rows as console lines: per call, per point and per tick of `calls` calls.
static func format(rows: Array[Dictionary]) -> PackedStringArray:
	var out := PackedStringArray()
	for row: Dictionary in rows:
		var native_us: float = row["native_us"]
		var script_us: float = row["gdscript_us"]
		if row["n"] == 0:
			if native_us < 0.0:
				out.append("echo: GDScript %.2f us per call; the native library is not loaded" % script_us)
			else:
				out.append("echo: native %.2f us per call, GDScript %.2f us" % [native_us, script_us])
			continue
		var n: int = row["n"]
		var line: String = "in_range %d points: GDScript %.2f us per call (%.1f ns per point, %.2f ms per %d calls)" % [
				n, script_us, script_us * 1000.0 / n, script_us * row["calls"] / 1000.0, row["calls"]]
		if native_us >= 0.0:
			line += "; native %.2f us (%.1f ns per point, %.2f ms per %d calls), %.0fx" % [native_us,
					native_us * 1000.0 / n, native_us * row["calls"] / 1000.0, row["calls"], script_us / native_us]
		out.append(line)
	return out


# The yardsticks: the probe's two calls written in GDScript, at the library's precision.
static func _script_echo(value: int) -> int:
	return value


static func _script_in_range(positions: PackedVector3Array, origin: Vector3, range_m: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var range_sq: float = range_m * range_m
	for i: int in positions.size():
		if positions[i].distance_squared_to(origin) <= range_sq:
			out.append(i)
	return out


# Mean cost of one echo, in microseconds.
static func _time_echo(echo: Callable, calls: int) -> float:
	var total: int = 0
	for i: int in WARMUP_CALLS:
		total += int(echo.call(i))
	var start: int = Time.get_ticks_usec()
	for i: int in calls:
		total += int(echo.call(i))
	var elapsed: int = Time.get_ticks_usec() - start
	return float(elapsed) / calls


# Mean cost of one query in microseconds, and how many indices all queries found.
static func _time_in_range(in_range: Callable, points: PackedVector3Array, calls: int) -> Array:
	for i: int in WARMUP_CALLS:
		in_range.call(points, points[i % points.size()], RANGE_M)
	var found: int = 0
	var start: int = Time.get_ticks_usec()
	for i: int in calls:
		found += (in_range.call(points, points[i % points.size()], RANGE_M) as PackedInt32Array).size()
	var elapsed: int = Time.get_ticks_usec() - start
	return [float(elapsed) / calls, found]
