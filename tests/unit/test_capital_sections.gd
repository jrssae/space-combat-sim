extends GutTest
## A capital's sections as its collision knows them (M10-T07): each collision piece is a section on the body its `piece`
## names; the volumes and shapes come out per body in order; a point is named by the section it lies in or nearest.


func _box(name: String, at: Array, size: Array) -> Dictionary:
	return {"name": name, "type": "box", "position": at, "size": size,
			"basis": {"x": [1.0, 0.0, 0.0], "y": [0.0, 1.0, 0.0], "z": [0.0, 0.0, 1.0]}}


func _piece(name: String, body: String, at: Array, size: Array) -> Dictionary:
	return {"name": name, "piece": body, "aabb_min": [-50.0, -50.0, -50.0], "aabb_max": [50.0, 50.0, 50.0],
			"bound": {"center": at, "radius": 60.0}, "shapes": [_box(name + "_00", at, size)],
			"hit_volumes": [_box(name + "_00", at, size)]}


func _manifest() -> Dictionary:
	return {"collision": {"max_shapes": 64, "max_hull_points": 64, "pieces": [
		_piece("bow", "hull", [0.0, 0.0, -100.0], [20.0, 10.0, 40.0]),
		_piece("habitat", "rotor", [0.0, 0.0, 0.0], [10.0, 10.0, 10.0]),
		_piece("engine", "hull", [0.0, 0.0, 100.0], [20.0, 10.0, 40.0]),
	]}, "sections": [{"name": "bow", "kind": "structure"}, {"name": "engine", "kind": "engine"}, {"name": "habitat", "kind": "habitat"}]}


func test_each_collision_piece_is_a_section_on_its_body() -> void:
	var sections: CapitalSections = CapitalSections.from_manifest(_manifest())
	assert_true(sections.valid, sections.error)
	assert_eq(sections.bodies(), PackedStringArray(["hull", "rotor"]), "the hull first, then each rotating piece")
	assert_eq(sections.on("hull").size(), 2)
	assert_eq(sections.volumes_of("hull").size(), 2)
	assert_eq(sections.shapes_of("rotor").size(), 1)
	assert_eq(sections.volume_sections("hull"), PackedStringArray(["bow", "engine"]))
	assert_eq(str((sections.by_name["engine"] as Dictionary)["kind"]), "engine", "the manifest's section facts by name")


func test_a_point_is_named_by_the_section_it_lies_in_or_nearest() -> void:
	var sections: CapitalSections = CapitalSections.from_manifest(_manifest())
	assert_eq(sections.section_at("hull", Vector3(0.0, 0.0, -100.0)), "bow", "inside the bow")
	assert_eq(sections.section_at("hull", Vector3(0.0, 8.0, 95.0)), "engine", "just above the engine")
	assert_eq(sections.section_at("rotor", Vector3(3.0, 0.0, 0.0)), "habitat")
	assert_eq(sections.section_at("nothing", Vector3.ZERO), "", "a body with no sections names none")


func test_a_broken_collision_section_gives_none() -> void:
	var sections: CapitalSections = CapitalSections.from_manifest({"collision": {}})
	assert_false(sections.valid)
	assert_true(sections.pieces.is_empty())


func test_distance_to_boxes_and_capsules() -> void:
	var box: HitShape = HitShape.make_box(Transform3D.IDENTITY, Vector3(2.0, 2.0, 2.0))
	assert_eq(CapitalSections.distance(box, Vector3(0.5, 0.0, 0.0)), 0.0, "inside")
	assert_almost_eq(CapitalSections.distance(box, Vector3(4.0, 0.0, 0.0)), 3.0, 1e-5)
	var capsule: HitShape = HitShape.make_capsule(Transform3D.IDENTITY, 1.0, 6.0)
	assert_almost_eq(CapitalSections.distance(capsule, Vector3(0.0, 5.0, 0.0)), 2.0, 1e-5, "past its end cap (axis to 2, radius 1)")
	assert_almost_eq(CapitalSections.distance(capsule, Vector3(3.0, 0.0, 0.0)), 2.0, 1e-5, "beside its axis")
