extends GutTest
## FeatureEdges, pure (architecture §18.20, M5-T43): a hull's creases and open borders as line pairs, with no flat-panel
## diagonal, whatever way the mesh splits its vertices.

const UNIT_CUBE: Array[Vector3] = [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0), Vector3(0, 0, 1),
		Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)]
# The cube's six faces, each a quad of corner numbers wound outward.
const CUBE_FACES: Array[Array] = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [2, 3, 7, 6], [0, 4, 7, 3], [1, 2, 6, 5]]


# A cube whose every face has its own four vertices (hard normals, as an imported hull has): 24 vertices, 12 triangles.
func _split_cube() -> Array:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for face: Array in CUBE_FACES:
		var base: int = vertices.size()
		for corner: int in face:
			vertices.append(UNIT_CUBE[corner])
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	return [vertices, indices]


# Two unit quads sharing the edge on the Z axis, the second folded up by `fold_deg` from flat.
func _hinge(fold_deg: float) -> Array:
	var up: Vector3 = Vector3(cos(deg_to_rad(fold_deg)), sin(deg_to_rad(fold_deg)), 0.0)
	var vertices := PackedVector3Array([Vector3(-1, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 1), up,
			up + Vector3(0, 0, 1)])
	return [vertices, PackedInt32Array([0, 1, 2, 0, 2, 3, 1, 4, 5, 1, 5, 2])]


func _has_edge(lines: PackedVector3Array, a: Vector3, b: Vector3) -> bool:
	for i: int in range(0, lines.size(), 2):
		if (lines[i].is_equal_approx(a) and lines[i + 1].is_equal_approx(b)) \
				or (lines[i].is_equal_approx(b) and lines[i + 1].is_equal_approx(a)):
			return true
	return false


func test_a_cube_keeps_its_twelve_edges() -> void:
	var cube: Array = _split_cube()
	var lines: PackedVector3Array = FeatureEdges.build(cube[0], cube[1])
	assert_eq(lines.size(), 24, "12 edges as 12 pairs of points")
	assert_true(_has_edge(lines, Vector3(0, 0, 0), Vector3(1, 0, 0)))
	assert_true(_has_edge(lines, Vector3(1, 1, 1), Vector3(1, 1, 0)))
	assert_false(_has_edge(lines, Vector3(0, 0, 0), Vector3(1, 1, 0)), "no face diagonal")


func test_a_flat_panel_drops_its_diagonal_and_keeps_its_borders() -> void:
	var vertices := PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(2, 0, 1), Vector3(0, 0, 1)])
	var lines: PackedVector3Array = FeatureEdges.build(vertices, PackedInt32Array([0, 1, 2, 0, 2, 3]))
	assert_eq(lines.size(), 8, "the four open borders")
	assert_false(_has_edge(lines, Vector3(0, 0, 0), Vector3(2, 0, 1)), "the diagonal is not an edge of the panel")
	for i: int in 4:
		assert_true(_has_edge(lines, vertices[i], vertices[(i + 1) % 4]), "border %d" % i)


func test_a_fold_is_an_edge_only_past_the_crease_angle() -> void:
	var soft: Array = _hinge(FeatureEdges.CREASE_DEG - 5.0)
	var hard: Array = _hinge(FeatureEdges.CREASE_DEG + 5.0)
	assert_eq(FeatureEdges.build(soft[0], soft[1]).size(), 12, "six borders, the gentle fold is not drawn")
	var lines: PackedVector3Array = FeatureEdges.build(hard[0], hard[1])
	assert_eq(lines.size(), 14, "six borders and the fold")
	assert_true(_has_edge(lines, Vector3(0, 0, 0), Vector3(0, 0, 1)))
	assert_eq(FeatureEdges.build(soft[0], soft[1], 10.0).size(), 14, "the angle is the caller's to set")


func test_a_seam_of_doubled_vertices_is_no_border() -> void:
	# The flat panel again, its two triangles sharing no vertex (a UV seam down the diagonal).
	var vertices := PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(2, 0, 1), Vector3(0, 0, 0), Vector3(2, 0, 1),
			Vector3(0, 0, 1)])
	var lines: PackedVector3Array = FeatureEdges.build(vertices, PackedInt32Array([0, 1, 2, 3, 4, 5]))
	assert_eq(lines.size(), 8)
	assert_false(_has_edge(lines, Vector3(0, 0, 0), Vector3(2, 0, 1)))
	# Vertices a hair apart weld too; ones further apart than the weld do not.
	vertices[3] = Vector3(0, 0, FeatureEdges.WELD_M * 0.2)
	assert_eq(FeatureEdges.build(vertices, PackedInt32Array([0, 1, 2, 3, 4, 5])).size(), 8)
	vertices[3] = Vector3(0, 0, 0.05)
	assert_gt(FeatureEdges.build(vertices, PackedInt32Array([0, 1, 2, 3, 4, 5])).size(), 8)


func test_the_order_is_the_same_every_time() -> void:
	var cube: Array = _split_cube()
	var first: PackedVector3Array = FeatureEdges.build(cube[0], cube[1])
	assert_eq(FeatureEdges.build(cube[0], cube[1]), first)
	assert_eq(first[0], Vector3(0, 0, 0), "edges come in the order the triangles first name them")


func test_slivers_and_an_unindexed_list_are_handled() -> void:
	# A triangle with no area adds nothing; without indices every three vertices are a triangle.
	var vertices := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(5, 5, 5), Vector3(5, 5, 5),
			Vector3(6, 5, 5)])
	assert_eq(FeatureEdges.build(vertices, PackedInt32Array()).size(), 6)
	assert_eq(FeatureEdges.build(PackedVector3Array(), PackedInt32Array()).size(), 0)


func test_an_edge_three_faces_share_is_kept() -> void:
	# A flat panel with a fin standing on its diagonal: the diagonal is now a real edge.
	var vertices := PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(2, 0, 1), Vector3(0, 0, 1), Vector3(1, 1, 0.5)])
	var lines: PackedVector3Array = FeatureEdges.build(vertices, PackedInt32Array([0, 1, 2, 0, 2, 3, 0, 2, 4]))
	assert_true(_has_edge(lines, Vector3(0, 0, 0), Vector3(2, 0, 1)))
	assert_eq(lines.size(), 14, "four borders, the fin's two free edges and its root")


func test_a_mesh_gives_its_edges_and_a_line_mesh() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(2, 1, 4)
	var lines: PackedVector3Array = FeatureEdges.from_mesh(box)
	assert_eq(lines.size(), 24, "a box mesh is a cube")
	var mesh: ArrayMesh = FeatureEdges.line_mesh(lines)
	assert_eq(mesh.get_surface_count(), 1)
	assert_eq(mesh.surface_get_primitive_type(0), Mesh.PRIMITIVE_LINES)
	assert_eq((mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 24)
	assert_eq(FeatureEdges.line_mesh(PackedVector3Array()).get_surface_count(), 0, "nothing to draw, no surface")
	assert_eq(FeatureEdges.from_mesh(null).size(), 0)


func test_a_job_worked_in_slices_gives_the_same_lines() -> void:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 8
	sphere.rings = 4
	var whole: PackedVector3Array = FeatureEdges.from_mesh(sphere)
	assert_gt(whole.size(), 0, "a coarse ball is all creases")
	var job: FeatureEdgeJob = FeatureEdgeJob.for_mesh(sphere)
	assert_false(job.done)
	assert_eq(job.lines().size(), 0, "no lines before it is done")
	var guard: int = 0
	while not job.step(0) and guard < 10000:
		guard += 1
	assert_true(job.done)
	assert_gt(job.steps, 1, "a budget of nothing still moves it on, a chunk at a time")
	assert_eq(job.lines(), whole)
	assert_eq(job.progress(), 1.0)
	assert_true(job.step(0), "a done job stays done")
	var empty: FeatureEdgeJob = FeatureEdgeJob.for_mesh(null)
	assert_true(empty.step(0))
	assert_eq(empty.lines().size(), 0)
