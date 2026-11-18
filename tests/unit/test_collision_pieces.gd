extends GutTest
## CollisionPieces and CollisionBodies (M7-T03, D73): a manifest's `collision` section parsed into shapes and hit volumes, and
## one physics body built per piece. The fixture is a small two-piece asset written by `tools/procgen/core/collision.py`
## (a deck box, a tank capsule along z and a wedge hull in `frame`; a turned box in `drum`); the last tests read a Saturn's.

const FIXTURE: String = "res://tests/fixtures/collision_demo_manifest.json"
const SATURN: String = "saturn_4_transport"
const GEN_ASSETS_HINT: String = "run scripts/gen_assets.sh (the Saturns' manifests carry collision pieces from M7-T03)"
const EPS: float = 1e-4


func _manifest() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_true(data is Dictionary, "the fixture parses")
	return data


func _pieces() -> CollisionPieces:
	return CollisionPieces.from_manifest(_manifest())


# The fixture with one edit made by `edit` to its collision section.
func _broken(edit: Callable) -> CollisionPieces:
	var manifest: Dictionary = _manifest()
	edit.call(manifest["collision"])
	return CollisionPieces.from_manifest(manifest)


# The box that holds every shape of a body, from the shapes' own debug meshes.
func _extent(body: PhysicsBody3D) -> AABB:
	var out := AABB()
	var first: bool = true
	for child: Node in body.get_children():
		var node: CollisionShape3D = child
		var box: AABB = node.transform * node.shape.get_debug_mesh().get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return get_tree().root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))


# --- parsing ------------------------------------------------------------------------------------------------------------
func test_the_section_gives_a_piece_per_body_with_its_bounds() -> void:
	var parsed: CollisionPieces = _pieces()
	assert_true(parsed.valid, parsed.error)
	assert_eq(parsed.pieces.size(), 2)
	var frame: Dictionary = parsed.piece("frame")
	assert_eq((parsed.pieces[0] as Dictionary)["name"], "frame")
	assert_eq((parsed.pieces[1] as Dictionary)["name"], "drum")
	assert_almost_eq((frame["aabb"] as AABB).position, Vector3(-2.0, -0.5, -4.5), Vector3.ONE * EPS)
	assert_almost_eq((frame["aabb"] as AABB).end, Vector3(2.0, 4.5, 7.0), Vector3.ONE * EPS)
	assert_almost_eq(frame["bound_center"] as Vector3, Vector3(0.0, 2.0, 1.25), Vector3.ONE * EPS)
	assert_almost_eq(float(frame["bound_radius"]), 6.14919, EPS)
	assert_true(parsed.piece("no_such_piece").is_empty())


func test_each_shape_becomes_its_godot_shape() -> void:
	var shapes: Array[Dictionary] = _pieces().piece("frame")["shapes"]
	assert_eq(shapes.size(), 3)
	var deck: Dictionary = shapes[0]
	assert_true(deck["shape"] is BoxShape3D)
	assert_eq((deck["shape"] as BoxShape3D).size, Vector3(4.0, 1.0, 8.0))
	var tank: Dictionary = shapes[1]
	assert_true(tank["shape"] is CapsuleShape3D)
	assert_almost_eq((tank["shape"] as CapsuleShape3D).radius, 1.5, EPS)
	assert_almost_eq((tank["shape"] as CapsuleShape3D).height, 9.0, EPS)
	assert_almost_eq((tank["transform"] as Transform3D).basis * Vector3.UP, Vector3.BACK, Vector3.ONE * EPS,
			"Godot's capsule stands on y; the piece's lies along z")
	assert_almost_eq((tank["transform"] as Transform3D).origin, Vector3(0.0, 3.0, 0.0), Vector3.ONE * EPS)
	var wedge: Dictionary = shapes[2]
	assert_eq(wedge["name"], "wedge")
	assert_true(wedge["shape"] is ConvexPolygonShape3D)
	assert_eq((wedge["shape"] as ConvexPolygonShape3D).points.size(), 6)
	assert_eq(wedge["transform"], Transform3D.IDENTITY, "a hull's points are in the piece's frame already")


func test_a_turned_box_keeps_its_basis() -> void:
	var arm: Dictionary = (_pieces().piece("drum")["shapes"] as Array[Dictionary])[0]
	var along: Vector3 = (arm["transform"] as Transform3D).basis * Vector3.BACK
	assert_almost_eq(absf(along.x), 1.0, EPS, "the 12 m side lies along x")


func test_hit_volumes_are_boxes_and_capsules_around_the_shapes() -> void:
	var frame: Dictionary = _pieces().piece("frame")
	var volumes: Array[HitShape] = frame["hit_volumes"]
	assert_eq(volumes.size(), 3)
	assert_eq(volumes[0].kind, HitShape.Kind.BOX)
	assert_eq(volumes[1].kind, HitShape.Kind.CAPSULE)
	assert_eq(volumes[2].kind, HitShape.Kind.BOX, "a hull is swept as the box fitted round it")
	assert_eq(volumes[2].shape_name, "wedge")
	var wedge: ConvexPolygonShape3D = (frame["shapes"] as Array[Dictionary])[2]["shape"]
	for point: Vector3 in wedge.points:
		assert_true(volumes[2].contains(point, EPS), "the wedge's corner %s is inside its hit volume" % point)
	assert_almost_eq(volumes[1].sweep(Vector3(0.0, 10.0, 0.0), Vector3(0.0, 0.0, 0.0)), 0.55, EPS, "a bolt from above meets the tank's top")


func test_a_manifest_without_the_section_is_not_valid() -> void:
	var parsed: CollisionPieces = CollisionPieces.from_manifest({"asset_id": "thing"})
	assert_false(parsed.valid)
	assert_string_contains(parsed.error, "no collision section")
	assert_eq(parsed.pieces.size(), 0)


func test_broken_sections_are_refused_whole() -> void:
	var edits: Dictionary = {
		"no budget": func(c: Dictionary) -> void: c.erase("max_shapes"),
		"over the shape budget": func(c: Dictionary) -> void: c["max_shapes"] = 2,
		"over the point budget": func(c: Dictionary) -> void: c["max_hull_points"] = 5,
		"no pieces": func(c: Dictionary) -> void: c["pieces"] = [],
		"a name twice": func(c: Dictionary) -> void: (c["pieces"][1] as Dictionary)["name"] = "frame",
		"a hull of three points": func(c: Dictionary) -> void: (c["pieces"][0]["shapes"][2]["points"] as Array).resize(3),
		"a point that is no vector": func(c: Dictionary) -> void: c["pieces"][0]["shapes"][2]["points"][0] = [1.0, "x", 0.0],
		"an unknown shape": func(c: Dictionary) -> void: c["pieces"][0]["shapes"][0]["type"] = "sphere",
		"a hull as a hit volume": func(c: Dictionary) -> void: c["pieces"][0]["hit_volumes"][2] = c["pieces"][0]["shapes"][2],
		"no bound": func(c: Dictionary) -> void: (c["pieces"][0] as Dictionary).erase("bound"),
		"no shapes": func(c: Dictionary) -> void: c["pieces"][1]["shapes"] = [],
	}
	for label: String in edits:
		var parsed: CollisionPieces = _broken(edits[label])
		assert_false(parsed.valid, label)
		assert_ne(parsed.error, "", label)
		assert_eq(parsed.pieces.size(), 0, "%s: no half-read pieces" % label)


# --- bodies -------------------------------------------------------------------------------------------------------------
func test_a_piece_builds_a_static_body_with_a_shape_node_each() -> void:
	var frame: Dictionary = _pieces().piece("frame")
	var body: PhysicsBody3D = CollisionBodies.build(frame)
	autofree(body)
	assert_true(body is StaticBody3D)
	assert_false(body is AnimatableBody3D)
	assert_eq(String(body.name), "Frame")
	assert_eq(body.get_child_count(), 3)
	var names: Array[String] = []
	for child: Node in body.get_children():
		assert_true(child is CollisionShape3D)
		names.append(String(child.name))
	assert_eq(names, ["Deck", "Tank", "Wedge"] as Array[String])
	var extent: AABB = _extent(body)
	var want: AABB = frame["aabb"]
	assert_almost_eq(extent.position, want.position, Vector3.ONE * 0.01)
	assert_almost_eq(extent.end, want.end, Vector3.ONE * 0.01)


func test_the_caller_can_ask_for_an_animatable_body() -> void:
	var body: PhysicsBody3D = CollisionBodies.build(_pieces().piece("drum"), true)
	autofree(body)
	assert_true(body is AnimatableBody3D)
	assert_eq(body.get_child_count(), 1)
	assert_almost_eq(_extent(body).size, Vector3(12.0, 2.0, 2.0), Vector3.ONE * 0.01)


func test_the_body_stops_rays_where_its_shapes_are_and_nowhere_else() -> void:
	var body: PhysicsBody3D = CollisionBodies.build(_pieces().piece("frame"))
	add_child_autofree(body)
	body.global_position = Vector3(500.0, 0.0, 0.0)
	await wait_physics_frames(2)
	var at: Vector3 = body.global_position
	var on_tank: Dictionary = _ray(at + Vector3(0.0, 10.0, -2.0), at + Vector3(0.0, -10.0, -2.0))
	assert_almost_eq((on_tank["position"] as Vector3).y, 4.5, 0.01, "the tank's top")
	var on_wedge: Dictionary = _ray(at + Vector3(0.0, 10.0, 5.5), at + Vector3(0.0, -10.0, 5.5))
	assert_almost_eq((on_wedge["position"] as Vector3).y, 1.0, 0.01, "half way down the wedge's slope, past the tank's end")
	var between: Dictionary = _ray(at + Vector3(10.0, 1.0, -2.0), at + Vector3(-10.0, 1.0, -2.0))
	assert_true(between.is_empty(), "the gap between the deck and the tank stays open")


# --- a generated hull -----------------------------------------------------------------------------------------------------
func test_a_saturns_manifest_builds_one_body_inside_the_budget() -> void:
	var parsed: CollisionPieces = CollisionPieces.for_asset(SATURN)
	assert_true(parsed.valid, "%s; %s" % [parsed.error, GEN_ASSETS_HINT])
	if not parsed.valid:
		return
	assert_eq(parsed.pieces.size(), 1)
	var hull: Dictionary = parsed.piece("hull")
	var shapes: Array[Dictionary] = hull["shapes"]
	assert_eq(shapes.size(), 76, "one shape a part")
	assert_eq((hull["hit_volumes"] as Array[HitShape]).size(), shapes.size())
	var capsules: int = 0
	for entry: Dictionary in shapes:
		if entry["shape"] is CapsuleShape3D:
			capsules += 1
			continue
		assert_true(entry["shape"] is ConvexPolygonShape3D, str(entry["name"]))
		assert_between((entry["shape"] as ConvexPolygonShape3D).points.size(), 4, 32, str(entry["name"]))
	assert_eq(capsules, 1, "the cargo cylinder")
	var body: PhysicsBody3D = CollisionBodies.build(hull)
	autofree(body)
	assert_eq(body.get_child_count(), shapes.size())
	# The body is as big as the drawn hull: its manifest box, within the capsule's rounding.
	var mesh: Dictionary = MeshAssets.read_manifest(SATURN)["mesh"]
	var extent: AABB = _extent(body)
	for axis: int in 3:
		assert_almost_eq(extent.position[axis], float(mesh["aabb_min"][axis]), 0.5, "axis %d, low" % axis)
		assert_almost_eq(extent.end[axis], float(mesh["aabb_max"][axis]), 0.5, "axis %d, high" % axis)
