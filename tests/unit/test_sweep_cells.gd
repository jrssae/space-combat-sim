extends GutTest
## The hit broad phase's grid with hashed cells (M4-T34): `native/src/sweep_cells.rs` places the hulls in the same cells as
## the sorted grid and finds each projectile's candidates by one lookup a cell, so with `perf_native_sweep_cells` on and off
## (and on the GDScript reference) the pairs and the work count are the same, per tick and against kept hulls, on seeded
## mixes of fighters, capitals, rocks, hulls too odd to place and beams kilometres long. The kernel holds no engine type
## (T15's guard). Skips, saying why, when the native library is not built.

const KERNEL: String = "res://native/src/sweep_cells.rs"
const KERNEL_USE_ALLOWED: Array[String] = ["use std::", "use godot::builtin::Vector3;", "use crate::v3::"]
const ROUNDS: int = 12

var _saved: Dictionary = {}


func before_each() -> void:
	for key: StringName in [&"perf_native", &"perf_native_sweep_cells"]:
		_saved[key] = Settings.get_value(key)
	Settings.set_value(&"perf_native", true)


func after_each() -> void:
	for key: StringName in _saved:
		Settings.set_value(key, _saved[key])


func test_the_kernel_holds_no_engine_type() -> void:
	var guard: GDScript = load("res://tests/unit/test_sim_core.gd")
	var forbidden: Array[String] = guard.get("KERNEL_FORBIDDEN")
	var violations: PackedStringArray = guard.call("_engine_free_violations", KERNEL, forbidden, KERNEL_USE_ALLOWED)
	assert_eq(violations.size(), 0, "no engine type, call, crate path or stray import in the cell grid: %s" % violations)
	var source: String = FileAccess.get_file_as_string(KERNEL)
	assert_false(source.contains("static mut") or source.contains("thread_local") or source.contains("Cell<"),
			"no shared mutable state")


# Seeded spheres: [mids, reach] for `n` hulls of every size, a few too odd to place.
func _hulls(rng: RandomNumberGenerator, n: int) -> Array:
	var mids := PackedVector3Array()
	var reach := PackedFloat64Array()
	for j: int in n:
		mids.append(Vector3(rng.randf_range(-20000.0, 20000.0), rng.randf_range(-4000.0, 4000.0), rng.randf_range(-20000.0, 20000.0)))
		var roll: float = rng.randf()
		reach.append(rng.randf_range(4.0, 30.0) if roll < 0.6 else (rng.randf_range(100.0, 900.0) if roll < 0.85
				else (rng.randf_range(20.0, 250.0) if roll < 0.98 else 40000.0)))
	mids[n / 2] = Vector3(NAN, 0.0, 0.0)
	return [mids, reach]


# Seeded bolts, most near a hull, some beams kilometres long.
func _bolts(rng: RandomNumberGenerator, n: int, hull_mids: PackedVector3Array) -> Array:
	var mids := PackedVector3Array()
	var reach := PackedFloat64Array()
	for i: int in n:
		var near: Vector3 = hull_mids[rng.randi_range(0, hull_mids.size() - 1)]
		if not near.is_finite():
			near = Vector3.ZERO
		mids.append(near + Vector3(rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0), rng.randf_range(-300.0, 300.0)))
		reach.append(rng.randf_range(3.0, 12.0) if rng.randf() < 0.95 else rng.randf_range(500.0, 3000.0))
	return [mids, reach]


func test_the_pairs_and_the_work_are_the_same_with_hashed_cells() -> void:
	if not NativeLib.has_class(HitBroadPhase.NATIVE_CLASS):
		pending("the native library is not built (scripts/build_native.sh)")
		return
	assert_true(Settings.get_value(&"perf_native_sweep_cells") is bool, "the setting exists")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3403
	var reference := HitBroadPhase.new()
	reference.use_native = false
	var paired: int = 0
	for round: int in ROUNDS:
		var hulls: Array = _hulls(rng, rng.randi_range(20, 400))
		var bolts: Array = _bolts(rng, rng.randi_range(50, 1500), hulls[0])
		var answers: Array = []
		for cells: bool in [false, true]:
			Settings.set_value(&"perf_native_sweep_cells", cells)
			var phase := HitBroadPhase.new()
			var keys: PackedInt64Array = phase.pairs(bolts[0], bolts[1], hulls[0], hulls[1])
			var visited: int = phase.visited
			phase.keep(hulls[0], hulls[1])
			var kept: PackedInt64Array = phase.kept_pairs(bolts[0], bolts[1])
			answers.append([keys, visited, kept, phase.visited, phase._native().cells()])
		assert_false(answers[0][4], "round %d: off keeps the sorted cells" % round)
		assert_true(answers[1][4], "round %d: on hashes them" % round)
		var gd_keys: PackedInt64Array = reference.pairs(bolts[0], bolts[1], hulls[0], hulls[1])
		assert_eq(answers[1][0], answers[0][0], "round %d: the same pairs" % round)
		assert_eq(answers[1][1], answers[0][1], "round %d: the same work" % round)
		assert_eq(answers[1][2], answers[0][2], "round %d: the same pairs against kept hulls" % round)
		assert_eq(answers[1][3], answers[0][3], "round %d: the same work against kept hulls" % round)
		assert_eq(answers[1][0], gd_keys, "round %d: the GDScript reference's pairs" % round)
		assert_eq(answers[1][1], reference.visited, "round %d: and its work" % round)
		paired += answers[1][0].size()
	assert_gt(paired, 100, "the rounds paired enough to compare")
