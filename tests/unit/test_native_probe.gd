extends GutTest
## The native seam (M4-T05a, architecture §17.5): `NativeProbe` answers through the native library when it is
## loaded and `perf_native` is on, through GDScript otherwise, with the same results either way. Passes with and
## without bin/libscs_native.so, and says which path it took.

var _native_backup: bool


func before_each() -> void:
	_native_backup = bool(Settings.get_value(&"perf_native"))
	Settings.set_value(&"perf_native", true)


func after_each() -> void:
	Settings.set_value(&"perf_native", _native_backup)


func _loaded() -> bool:
	return ClassDB.class_exists(NativeProbe.NATIVE_CLASS)


func _points(count: int, seed_value: int) -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := PackedVector3Array()
	for i: int in count:
		out.append(Vector3(rng.randf_range(-6000.0, 6000.0), rng.randf_range(-6000.0, 6000.0),
				rng.randf_range(-6000.0, 6000.0)))
	return out


func test_the_probe_takes_the_native_path_exactly_when_the_library_is_loaded() -> void:
	var probe := NativeProbe.new()
	var expected: StringName = &"native" if _loaded() else &"gdscript"
	gut.p("native library %s: probe path %s" % ["loaded" if _loaded() else "absent", probe.path()])
	assert_eq(probe.path(), expected)
	assert_eq(NativeLib.has_class(NativeProbe.NATIVE_CLASS), _loaded())
	assert_eq(NativeLib.version(NativeProbe.NATIVE_CLASS) != "", _loaded(), "a version only from a loaded library")


func test_perf_native_off_selects_gdscript() -> void:
	Settings.set_value(&"perf_native", false)
	assert_eq(NativeProbe.new().path(), &"gdscript")
	assert_null(NativeLib.instantiate(NativeProbe.NATIVE_CLASS))


func test_an_existing_probe_follows_a_live_flip() -> void:
	var probe := NativeProbe.new()
	var loaded: StringName = &"native" if _loaded() else &"gdscript"
	assert_eq(probe.path(), loaded)
	Settings.set_value(&"perf_native", false)
	assert_eq(probe.path(), &"gdscript", "off: the same probe answers from GDScript at once")
	assert_eq(probe.echo(9), 9)
	Settings.set_value(&"perf_native", true)
	assert_eq(probe.path(), loaded, "and back")


func test_use_native_false_forces_gdscript() -> void:
	assert_eq(NativeProbe.new(false).path(), &"gdscript")


func test_an_unknown_class_gives_null_not_an_error() -> void:
	assert_false(NativeLib.has_class(&"ScsNoSuchClass"))
	assert_null(NativeLib.instantiate(&"ScsNoSuchClass"))


func test_both_paths_give_the_same_answers() -> void:
	var probe := NativeProbe.new()
	var fallback := NativeProbe.new(false)
	assert_eq(probe.echo(42), 42)
	assert_eq(probe.echo(-7_000_000_000), -7_000_000_000, "64-bit ints cross unchanged")
	for count: int in [0, 1, 7, 100, 300]:
		var points := _points(count, count + 11)
		for origin: Vector3 in [Vector3.ZERO, Vector3(3000.0, -2000.0, 500.0)]:
			for range_m: float in [0.0, 1500.0, 5000.0, 20000.0]:
				assert_eq(probe.in_range(points, origin, range_m), fallback.in_range(points, origin, range_m),
						"%d points, range %.0f, %s path" % [count, range_m, probe.path()])


func test_the_range_edge_matches_gdscript_precision() -> void:
	# A point exactly on the range, one just past it, and the origin: both paths split them the same way.
	var origin := Vector3(0.5, 0.25, 0.125)
	var points := PackedVector3Array([origin + Vector3(1000.0, 0.0, 0.0), origin + Vector3(1000.001, 0.0, 0.0), origin])
	var expected := NativeProbe.new(false).in_range(points, origin, 1000.0)
	assert_eq(expected, PackedInt32Array([0, 2]), "on the edge is in range, past it is not")
	assert_eq(NativeProbe.new().in_range(points, origin, 1000.0), expected)


func test_the_boundary_bench_reports_every_size_and_both_paths_agree() -> void:
	var rows := NativeBoundaryBench.run(50, PackedInt32Array([100, 300]))
	assert_eq(rows.size(), 3, "echo plus one row per size")
	for row: Dictionary in rows:
		assert_gte(float(row["gdscript_us"]), 0.0)
		assert_eq(float(row["native_us"]) >= 0.0, _loaded(), "native timed only with the library")
		if _loaded():
			assert_eq(row["native_found"], row["gdscript_found"], "%s %d" % [row["name"], row["n"]])
	for line: String in NativeBoundaryBench.format(rows):
		gut.p(line)
