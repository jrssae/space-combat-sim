extends GutTest
## `PieceSections` (M7-T19): a piece's sections and near-only props read from its manifest entries.


func _entry() -> Dictionary:
	return {"sections": [
		{"name": "fore", "file": "x_sec_fore.glb", "origin": [0.0, 0.0, -150.0], "z0": null, "z1": -100.0,
				"aabb_min": [-10.0, -10.0, -50.0], "aabb_max": [10.0, 10.0, 50.0], "triangles": 12},
		{"name": "mid", "file": "x_sec_mid.glb", "origin": [0.0, 0.0, 0.0], "z0": -100.0, "z1": 100.0,
				"aabb_min": [-20.0, -20.0, -100.0], "aabb_max": [20.0, 30.0, 100.0], "triangles": 40},
		{"name": "aft", "file": "x_sec_aft.glb", "origin": [0.0, 0.0, 150.0], "z0": 100.0, "z1": null,
				"aabb_min": [-10.0, -10.0, -50.0], "aabb_max": [10.0, 10.0, 50.0], "triangles": 12},
	]}


func _props() -> Dictionary:
	return {"near_m": 1500.0, "margin_m": 400.0, "surface": {"name": "prop", "albedo": "x_props_albedo.png"},
		"kinds": {"clamp": {"file": "x_prop_clamp.glb"}},
		"groups": [
			{"kind": "clamp", "section": "mid", "transforms": [[1, 0, 0, 0, 1, 0, 0, 0, 1, 5, 6, 7], [0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0]],
					"aabb_min": [-1.0, -1.0, -1.0], "aabb_max": [6.0, 7.0, 8.0]},
			{"kind": "antenna", "section": "mid", "transforms": [[1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]]},
			{"kind": "clamp", "section": "nowhere", "transforms": [[1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]]},
		]}


func test_reads_the_sections_bow_to_stern_with_their_slabs() -> void:
	var made: PieceSections = PieceSections.from_entry(_entry())
	assert_not_null(made)
	assert_eq(made.names(), PackedStringArray(["fore", "mid", "aft"]))
	assert_true(made.is_contiguous())
	assert_eq(made.find("mid")["origin"], Vector3.ZERO)
	assert_eq(made.find("fore")["z0"], -INF, "open at the bow")
	assert_eq(made.find("aft")["z1"], INF, "open at the stern")
	assert_eq(made.section_at(-500.0), "fore")
	assert_eq(made.section_at(-100.0), "mid", "a point on a cut belongs aft of it")
	assert_eq(made.section_at(99.0), "mid")
	assert_eq(made.section_at(5000.0), "aft")
	assert_eq(made.bounds(), AABB(Vector3(-20.0, -20.0, -200.0), Vector3(40.0, 50.0, 400.0)))


func test_a_piece_without_sections_or_with_a_gap_is_drawn_whole() -> void:
	assert_null(PieceSections.from_entry({}), "no sections")
	var gap: Dictionary = _entry()
	gap["sections"][2]["z0"] = 120.0
	assert_null(PieceSections.from_entry(gap), "a gap between mid and aft")
	var closed: Dictionary = _entry()
	closed["sections"][0]["z0"] = -300.0
	assert_null(PieceSections.from_entry(closed), "the bow end must be open")
	var nameless: Dictionary = _entry()
	nameless["sections"][1]["file"] = ""
	assert_null(PieceSections.from_entry(nameless), "a section without a file")
	assert_push_warning_count(2)


func test_reads_the_props_and_skips_a_group_that_names_nothing() -> void:
	var made: PieceSections = PieceSections.from_entry(_entry(), _props())
	assert_eq(made.prop_groups.size(), 1, "the unknown kind and the unknown section are skipped")
	assert_push_warning_count(2)
	var group: Dictionary = made.prop_groups[0]
	assert_eq(group["section"], "mid")
	assert_eq(made.groups_in("mid").size(), 1)
	assert_eq(made.groups_in("fore").size(), 0)
	var transforms: Array[Transform3D] = group["transforms"]
	assert_eq(transforms[0], Transform3D(Basis.IDENTITY, Vector3(5.0, 6.0, 7.0)))
	assert_almost_eq(transforms[1].basis.x, Vector3(0.0, 1.0, 0.0), Vector3.ONE * 1e-6, "the basis' columns, x first")
	assert_eq(made.prop_files["clamp"], "x_prop_clamp.glb")


func test_props_are_shown_near_and_fade_out_and_nothing_casts_a_shadow() -> void:
	var made: PieceSections = PieceSections.from_entry(_entry(), _props())
	var range_: Dictionary = made.prop_range()
	assert_eq(range_["end"], 1500.0)
	assert_eq(range_["end_margin"], 400.0)
	assert_eq(range_["fade"], GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF)
	assert_eq(PieceSections.CAST_SHADOW, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no light in the game casts shadows")


func test_a_malformed_transform_is_the_identity() -> void:
	assert_eq(PieceSections.transform_of([1, 2, 3]), Transform3D.IDENTITY)
