extends GutTest
## The native seam (M4-T05a, architecture §17.5): `NativeProbe` answers through the native library (required since
## M4-T37), and the boundary bench (console `native bench`) times it against a GDScript distance check that finds the same
## points. M6-T18 dropped the M4-T05a experiment's own distance-check tests: only the bench calls `in_range`.


func test_the_probe_takes_the_native_path() -> void:
	assert_eq(NativeProbe.new().path(), &"native")
	assert_true(NativeLib.has_class(NativeProbe.NATIVE_CLASS))
	assert_ne(NativeLib.version(NativeProbe.NATIVE_CLASS), "", "the loaded library gives its version")
	var probe := NativeProbe.new()
	assert_eq(probe.echo(42), 42)
	assert_eq(probe.echo(-7_000_000_000), -7_000_000_000, "64-bit ints cross unchanged")


func test_an_unknown_class_gives_null_not_an_error() -> void:
	assert_false(NativeLib.has_class(&"ScsNoSuchClass"))
	assert_null(NativeLib.instantiate(&"ScsNoSuchClass"))


func test_the_boundary_bench_reports_every_size_and_the_yardstick_agrees() -> void:
	var rows := NativeBoundaryBench.run(50, PackedInt32Array([100, 300]))
	assert_eq(rows.size(), 3, "echo plus one row per size")
	for row: Dictionary in rows:
		assert_gte(float(row["gdscript_us"]), 0.0)
		assert_gte(float(row["native_us"]), 0.0, "native timed")
		assert_eq(row["native_found"], row["gdscript_found"], "%s %d" % [row["name"], row["n"]])
	for line: String in NativeBoundaryBench.format(rows):
		gut.p(line)
