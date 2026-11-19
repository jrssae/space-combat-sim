extends GutTest
## GateShotPool (M8-T29, maintainer 2026-11-19): the gate jump's camera takes come from pools in data, every take under 3 s; a
## stage is sliced into takes no longer than `TAKE_MAX_S`, and the next take is picked at random (seeded) from the clear ones,
## never the one just before, never the last jump's opening, not one the sequence already used while others are left, and the
## entry's slice gets a take made for the entry.

var pool: GateShotPool


func before_each() -> void:
	pool = GateShotPool.load_file()


func _all(_slot: StringName, _id: String) -> bool:
	return true


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_the_pools_hold_the_reviewed_takes_each_under_three_seconds() -> void:
	assert_eq(pool.error, "")
	var expected: Dictionary = {
		GateShotPool.APPROACH: ["beside_behind", "trail_wide", "gate_side"],
		GateShotPool.MOUTH: ["close_behind", "trail_mid", "pull_out", "over_shoulder"],
		GateShotPool.ARRIVAL_OPEN: ["pylons_wide", "centre_close", "wide_burst", "reverse_exit"],
		GateShotPool.ARRIVAL_OUT: ["centre_close", "wide_burst", "arm_side", "head_on"],
	}
	for slot: StringName in expected:
		for id: String in expected[slot]:
			assert_true(pool.ids(slot).has(id), "%s take %s" % [slot, id])
	for slot: StringName in GateShotPool.SLOTS:
		for id: String in pool.ids(slot):
			var keys: Array = pool.keys(slot, id, "gate:G")
			var length: float = float(keys[keys.size() - 1]["t"]) - float(keys[0]["t"])
			assert_lt(length, 5.0 if pool.is_feature(slot, id) else 3.0, "%s %s lasts %.1f s" % [slot, id, length])
			assert_gt(length, pool.max_s(slot, id), "%s %s outlasts its longest cut, so it never ends early" % [slot, id])
			assert_true(bool(CinematicShot.from_dict(&"t", {"keys": keys})["ok"]), "%s %s is a valid shot" % [slot, id])
	assert_eq(pool.keys(GateShotPool.APPROACH, "gate_side", "gate:G")[0]["position"]["actor"], "gate:G")
	for id: String in ["pull_out", "trail_mid"]:
		assert_eq(pool.when(GateShotPool.MOUTH, id), GateShotPool.ENTRY, "%s is made for the entry" % id)
	for id: String in ["close_behind", "over_shoulder"]:
		assert_eq(pool.when(GateShotPool.MOUTH, id), GateShotPool.BEFORE, "%s stays before the core fills" % id)


func test_a_take_is_held_no_longer_than_it_may_be_and_leaves_the_next_a_second() -> void:
	assert_eq(GateShotPool.take_length(0.0, 2.0, GateShotPool.TAKE_MAX_S), 2.0, "all that is left when it fits")
	assert_almost_eq(GateShotPool.take_length(0.0, 10.0, GateShotPool.TAKE_MAX_S), 2.5, 1e-6, "10 s: four even takes")
	assert_eq(GateShotPool.take_length(0.0, 3.0, GateShotPool.TAKE_MAX_S), 1.5, "an even share: the next take keeps its second")
	assert_eq(GateShotPool.take_length(0.0, INF, GateShotPool.FEATURE_MAX_S), GateShotPool.FEATURE_MAX_S)
	for case: Array in [[0.0, 3.3], [0.0, 3.59], [1.0, 6.2], [0.0, 5.0], [2.0, 9.9]]:
		for longest: float in [GateShotPool.TAKE_MAX_S, GateShotPool.FEATURE_MAX_S]:
			var held: float = GateShotPool.take_length(case[0], case[1], longest)
			assert_gte(held, GateShotPool.MIN_HOLD_S, "no take under 1 s")
			var left: float = case[1] - case[0] - held
			assert_true(left <= 0.0 or left >= GateShotPool.MIN_HOLD_S - 1e-4, "%.1f to %.1f: the next take keeps its second" % case)
	assert_lt(GateShotPool.TAKE_MAX_S + GateJump.RING_HOLD_S, 3.0, "an ordinary take with the ring's flash on its end")
	assert_lt(GateShotPool.FEATURE_MAX_S + GateJump.RING_HOLD_S, 5.0, "a feature take with it")
	var features := PackedStringArray()
	for slot: StringName in GateShotPool.SLOTS:
		for id: String in pool.ids(slot):
			if pool.is_feature(slot, id):
				features.append("%s/%s" % [slot, id])
	assert_eq(Array(features), ["arrival_open/wide_burst", "arrival_out/wide_burst"], "the takes that earn the longer hold")
	assert_eq(pool.when(GateShotPool.ARRIVAL_OPEN, "wide_burst"), GateShotPool.AFTER, "it waits for the blue vortex to open")


func test_the_next_take_never_repeats_the_one_before_or_the_last_jumps_opening() -> void:
	for seed_value: int in 200:
		var rng: RandomNumberGenerator = _rng(seed_value)
		var used := PackedStringArray()
		var previous: String = ""
		for take: int in 9:
			var id: String = pool.next(rng, GateShotPool.APPROACH, used, previous, "trail_wide", _all)
			assert_ne(id, previous, "seed %d take %d repeats" % [seed_value, take])
			if take == 0:
				assert_ne(id, "trail_wide", "never the last jump's opening")
			if take < pool.ids(GateShotPool.APPROACH).size() - 1:
				assert_false(used.has(id), "seed %d: %s used twice while others were left" % [seed_value, id])
			used.append(id)
			previous = id


func test_the_entry_slice_gets_an_entry_take_and_blocked_takes_never_play() -> void:
	for seed_value: int in 50:
		var entry: String = pool.next(_rng(seed_value), GateShotPool.MOUTH, PackedStringArray(), "", "", _all, GateShotPool.ENTRY)
		assert_eq(pool.when(GateShotPool.MOUTH, entry), GateShotPool.ENTRY, "seed %d: %s at the entry" % [seed_value, entry])
		var before: String = pool.next(_rng(seed_value), GateShotPool.MOUTH, PackedStringArray(), "", "", _all, GateShotPool.BEFORE)
		assert_ne(pool.when(GateShotPool.MOUTH, before), GateShotPool.ENTRY, "before the entry an entry take waits")
		for slice: String in [GateShotPool.ENTRY, GateShotPool.AFTER]:
			var used := PackedStringArray(["trail_mid", "pull_out"])
			var late: String = pool.next(_rng(seed_value), GateShotPool.MOUTH, used, "trail_mid", "", _all, slice)
			assert_false(pool.when(GateShotPool.MOUTH, late) == GateShotPool.BEFORE, "seed %d: %s at or after the entry" % [seed_value, late])
	var no_side: Callable = func(slot: StringName, id: String) -> bool: return not (slot == GateShotPool.APPROACH and id == "gate_side")
	for seed_value: int in 100:
		assert_ne(pool.next(_rng(seed_value), GateShotPool.APPROACH, PackedStringArray(), "", "", no_side), "gate_side")
	var only_one: Callable = func(_slot: StringName, id: String) -> bool: return id == "wide_burst"
	assert_eq(pool.next(_rng(1), GateShotPool.ARRIVAL_OPEN, PackedStringArray(), "wide_burst", "", only_one), "wide_burst",
			"the only clear take is played again rather than a blocked one")


func test_the_picks_are_seeded() -> void:
	var a: String = pool.next(_rng(42), GateShotPool.ARRIVAL_OUT, PackedStringArray(), "", "", _all)
	assert_eq(pool.next(_rng(42), GateShotPool.ARRIVAL_OUT, PackedStringArray(), "", "", _all), a)
	var seen: Dictionary = {}
	for seed_value: int in 100:
		var slice: String = GateShotPool.BEFORE if seed_value % 2 == 0 else GateShotPool.AFTER
		seen[pool.next(_rng(seed_value), GateShotPool.ARRIVAL_OPEN, PackedStringArray(), "", "", _all, slice)] = true
	assert_eq(seen.size(), pool.ids(GateShotPool.ARRIVAL_OPEN).size(), "every opening take comes up")


func test_the_camera_path_follows_the_predicted_poses() -> void:
	var shot: CinematicShot = CinematicShot.from_dict(&"m", {"keys": pool.keys(GateShotPool.MOUTH, "close_behind", "gate:G")})["shot"]
	var poses: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3.ZERO), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -500.0))]
	var path: PackedVector3Array = GateShotPool.camera_path(shot, PackedFloat32Array([0.0, 1.0]),
			func(_actor: String, i: int) -> Variant: return poses[i])
	assert_almost_eq(path[0].z, 26.0, 1e-3, "behind the ship")
	assert_almost_eq(path[1].z - path[0].z, -500.0, 1e-3, "and moving with it")
