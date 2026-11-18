extends GutTest
## `LaunchCut` (M7-T08, maintainer: several camera options a phase, shuffled so they never feel stale): a pool's variants all play
## before any repeats, the same variant never plays twice in a row, a pinned seed gives the same cut, optional phases are left out
## now and then, required ones never. Runs on the shipped profile's pools.

var profile: LaunchProfile


func before_each() -> void:
	var made: Dictionary = LaunchProfile.load_file()
	assert_true(bool(made["ok"]), str(made.get("error", "")))
	profile = made["profile"]


# The variant each cut gave `phase` ("" where it was left out).
func _played(cut: LaunchCut, phase: String) -> PackedStringArray:
	var out := PackedStringArray()
	for record: Array in cut.history:
		var got: String = ""
		for entry: Dictionary in record:
			if entry["phase"] == phase:
				got = entry["variant"]
		out.append(got)
	return out


func test_every_phase_has_a_pool() -> void:
	for name: String in ["rack", "rotate", "hold", "drop", "exit", "chase"]:
		var phase: Dictionary = profile.phase(name)
		assert_false(phase.is_empty(), "a %s phase" % name)
		assert_gte((phase["variants"] as Array).size(), 2, "%s has several variants" % name)
	assert_gt(float(profile.phase("exit")["optional"]), 0.0, "the exit is optional")
	assert_eq(float(profile.phase("rack")["optional"]), 0.0, "the rack is always shown")


func test_a_pool_plays_all_its_variants_before_any_repeats() -> void:
	var cut := LaunchCut.new(profile)
	for i: int in 40:
		cut.pick(hash(["bag", i]))
	for name: String in ["rack", "rotate", "drop", "chase", "hold"]:
		var size: int = (profile.phase(name)["variants"] as Array).size()
		var seen: PackedStringArray = _played(cut, name)
		for start: int in range(0, seen.size() - size + 1, size):
			var round_ := PackedStringArray()
			for j: int in size:
				assert_false(round_.has(seen[start + j]), "%s repeats %s inside a round: %s" % [name, seen[start + j], seen])
				round_.append(seen[start + j])


func test_the_same_variant_never_plays_twice_in_a_row() -> void:
	var cut := LaunchCut.new(profile)
	for i: int in 60:
		cut.pick(hash(["row", i]))
	for name: String in ["rack", "rotate", "drop", "exit", "chase", "hold"]:
		var last: String = ""
		for got: String in _played(cut, name):
			if got.is_empty():
				continue
			assert_ne(got, last, "%s played %s twice running" % [name, got])
			last = got


func test_a_pinned_seed_gives_the_same_cut() -> void:
	var a := LaunchCut.new(profile)
	var b := LaunchCut.new(profile)
	for i: int in 8:
		var seed_value: int = 1234 + i
		var ca: Array[Dictionary] = a.pick(seed_value)
		var cb: Array[Dictionary] = b.pick(seed_value)
		assert_eq(ca.size(), cb.size())
		for j: int in ca.size():
			assert_eq(ca[j]["variant"], cb[j]["variant"], "launch %d, %s" % [i, ca[j]["phase"]])
	var other := LaunchCut.new(profile)
	var differs: bool = false
	for i: int in 8:
		var c1: Array[Dictionary] = other.pick(99000 + i)
		differs = differs or str(c1.map(func(e: Dictionary) -> String: return e["variant"])) \
				!= str(a.history[i].map(func(e: Dictionary) -> String: return e["variant"]))
	assert_true(differs, "other seeds give other cuts")


func test_optional_phases_are_left_out_sometimes_and_required_ones_never() -> void:
	var cut := LaunchCut.new(profile)
	var missing: Dictionary = {}
	for i: int in 200:
		cut.pick(hash(["optional", i]))
	for name: String in ["rack", "rotate", "hold", "drop", "exit", "chase"]:
		missing[name] = _played(cut, name).count("")
	assert_eq(int(missing["rack"]) + int(missing["rotate"]) + int(missing["drop"]) + int(missing["chase"]), 0, "required: always")
	var chance: float = float(profile.phase("exit")["optional"])
	assert_almost_eq(float(missing["exit"]) / 200.0, chance, 0.1, "the exit left out about %.0f%% of the time" % (chance * 100.0))


func test_weights_favour_a_variant_within_a_round() -> void:
	var cut := LaunchCut.new(profile)
	var first: Dictionary = {}
	var size: int = (profile.phase("rack")["variants"] as Array).size()
	for i: int in 400:
		var fresh := LaunchCut.new(profile)
		var got: String = fresh.pick(hash(["weight", i]))[0]["variant"]
		first[got] = int(first.get(got, 0)) + 1
	assert_gt(int(first.get("rack_pilot", 0)), int(first.get("rack_wingman", 0)), "a weight-2 variant opens a round more often")
	assert_eq(first.size(), size, "every variant can open a round")
	assert_not_null(cut)


func test_a_wave_draws_row_shots_for_its_drop_and_leaves_the_exit_out() -> void:
	var cut := LaunchCut.new(profile)
	var rows := PackedStringArray()
	for variant: Dictionary in profile.phase("drop")["variants"]:
		if bool(variant["row"]):
			rows.append(String(variant["id"]))
	assert_gte(rows.size(), 2, "several row shots")
	var drops := PackedStringArray()
	for i: int in rows.size() * 2:
		var picked: Array[Dictionary] = cut.pick(hash(["wave", i]), 4)
		assert_false(picked.any(func(e: Dictionary) -> bool: return e["phase"] == "exit"), "no exit in a wave")
		for e: Dictionary in picked:
			if e["phase"] == "drop":
				assert_true(rows.has(String(e["variant"])), "%s films the row" % e["variant"])
				drops.append(String(e["variant"]))
	for k: int in rows.size():
		assert_true(drops.slice(0, rows.size()).has(rows[k]), "every row shot before any repeats")
	for k: int in range(1, drops.size()):
		assert_ne(drops[k], drops[k - 1], "never the same row shot twice running")
