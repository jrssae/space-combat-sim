extends GutTest
## ThrusterVisuals with the hardpoints fixture and a fake FlightOutput source (architecture §7.1, M1-T13): an exhaust
## plume for every pod nozzle and every RCS hardpoint, based at the hardpoint position and pointing along its exhaust
## axis, whose length, radius and alpha follow the levels with an 80 ms lag. Main passes `ship.get_flight_output` as
## the source, here it is a Callable returning whatever `output` holds. How the plumes look is (H).

const FIXTURE: String = "res://tests/fixtures/hardpoints_nominal.json"
const DT: float = 1.0 / 60.0
const SETTLE_S: float = 1.0  # about 12 time constants

var layout: ThrusterLayout
var visuals: ThrusterVisuals
var output: FlightOutput = null


func before_each() -> void:
	layout = ThrusterLayout.load_file(FIXTURE)
	assert_true(layout.valid, layout.error)
	output = null
	visuals = _make_visuals()


func _make_visuals() -> ThrusterVisuals:
	var made := ThrusterVisuals.new()
	made.name = "ThrusterVisuals"
	add_child_autofree(made)
	made.setup(layout, _source)
	return made


func _source() -> FlightOutput:
	return output


func _levels(mains: Array[float], retros: Array[float]) -> FlightOutput:
	var made := FlightOutput.new()
	made.main_levels = PackedFloat64Array(mains)
	made.retro_levels = PackedFloat64Array(retros)
	return made


func _settle() -> void:
	for i: int in roundi(SETTLE_S / DT):
		visuals.advance(DT)


func _pod_plume(nozzle_name: String) -> Node3D:
	return visuals.get_node_or_null(ThrusterVisuals.POD_PREFIX + nozzle_name) as Node3D


func _rcs_plume(nozzle_name: String) -> Node3D:
	return visuals.get_node_or_null(ThrusterVisuals.RCS_PREFIX + nozzle_name) as Node3D


func _cone_of(plume: Node3D) -> MeshInstance3D:
	return plume.get_node(ThrusterVisuals.CONE_NAME) as MeshInstance3D


func _core_of(plume: Node3D) -> MeshInstance3D:
	return plume.get_node(ThrusterVisuals.CORE_NAME) as MeshInstance3D


func _rcs_index(nozzle_name: String) -> int:
	for j: int in layout.rcs_nozzles.size():
		if layout.rcs_nozzles[j]["name"] == nozzle_name:
			return layout.nozzle_count() + j
	return -1


## Where the far end of the cone is, in the parent's frame: the unit cone's tip (y = 1) through the cone's own scale.
func _tip_of(plume: Node3D) -> Vector3:
	var cone_node: MeshInstance3D = _cone_of(plume)
	return plume.transform * (cone_node.transform * Vector3(0.0, cone_node.mesh.get_aabb().end.y, 0.0))


func _vec_tol(tol: float) -> Vector3:
	return Vector3(tol, tol, tol)


# --- one plume per nozzle, coming out of the nozzle ------------------------------------------------------------


func test_a_plume_exists_for_every_pod_nozzle_based_at_the_nozzle() -> void:
	assert_eq(layout.nozzle_count(), 8, "four pods, a main and a retro each")
	for i: int in layout.nozzle_count():
		var plume: Node3D = _pod_plume(layout.nozzle_names[i])
		assert_not_null(plume, "plume for %s" % layout.nozzle_names[i])
		if plume != null:
			assert_almost_eq(plume.position, layout.nozzle_positions[i], _vec_tol(1e-5), "%s at its hardpoint" % layout.nozzle_names[i])


func test_a_plume_exists_for_every_rcs_hardpoint_based_at_the_nozzle() -> void:
	assert_gt(layout.rcs_nozzles.size(), 0)
	for entry: Dictionary in layout.rcs_nozzles:
		var plume: Node3D = _rcs_plume(entry["name"])
		assert_not_null(plume, "plume for RCS %s" % entry["name"])
		if plume != null:
			assert_almost_eq(plume.position, entry["position"] as Vector3, _vec_tol(1e-5), "%s at its hardpoint" % entry["name"])


func test_every_pod_plume_axis_is_the_nozzle_exhaust_direction() -> void:
	for i: int in layout.nozzle_count():
		var plume: Node3D = _pod_plume(layout.nozzle_names[i])
		assert_almost_eq(plume.basis * Vector3.UP, layout.nozzle_exhausts[i], _vec_tol(1e-5),
				"%s points along its exhaust" % layout.nozzle_names[i])
		assert_true(plume.basis.is_conformal(), "%s is a pure rotation" % layout.nozzle_names[i])
		assert_almost_eq(plume.basis.determinant(), 1.0, 1e-5, "%s is right-handed" % layout.nozzle_names[i])


func test_every_rcs_plume_axis_is_the_nozzle_exhaust_direction() -> void:
	for entry: Dictionary in layout.rcs_nozzles:
		var plume: Node3D = _rcs_plume(entry["name"])
		assert_almost_eq(plume.basis * Vector3.UP, entry["exhaust"] as Vector3, _vec_tol(1e-5), "%s points along its exhaust" % entry["name"])


func test_the_mains_point_aft_and_the_retros_forward() -> void:
	# Mains thrust forward, so their gas goes out of the back (+Z); the retros' goes out of the front (-Z).
	for i: int in layout.nozzle_count():
		var plume: Node3D = _pod_plume(layout.nozzle_names[i])
		var expected: float = 1.0 if ThrusterLayout.is_main_group(layout.nozzle_groups[i]) else -1.0
		assert_almost_eq((plume.basis * Vector3.UP).z, expected, 1e-5, layout.nozzle_names[i])


func test_plume_basis_handles_every_axis_including_the_poles_and_diagonals() -> void:
	for axis: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK,
			Vector3(1.0, 1.0, 1.0), Vector3(-0.3, 0.9, -0.1), Vector3(0.0, 1e-5, 1.0)]:
		var basis: Basis = ThrusterVisuals.plume_basis(axis)
		assert_almost_eq(basis * Vector3.UP, axis.normalized(), _vec_tol(1e-5), "axis %s" % axis)
		assert_almost_eq(basis.determinant(), 1.0, 1e-5, "right-handed for %s" % axis)
		assert_true(basis.is_conformal() and basis.x.length() > 0.999, "orthonormal for %s" % axis)
	assert_almost_eq(ThrusterVisuals.plume_basis(Vector3.ZERO) * Vector3.UP, Vector3.BACK, _vec_tol(1e-5), "zero falls back")


func test_the_cone_starts_at_the_nozzle_and_extends_along_the_exhaust() -> void:
	output = _levels([1.0, 1.0, 1.0, 1.0], [1.0, 1.0, 1.0, 1.0])
	_settle()
	for i: int in layout.nozzle_count():
		var plume: Node3D = _pod_plume(layout.nozzle_names[i])
		var aabb: AABB = _cone_of(plume).mesh.get_aabb()
		assert_almost_eq(aabb.position.y, 0.0, 1e-5, "the cone's base is at the plume origin, i.e. the nozzle")
		var length: float = visuals.main_length_m if ThrusterLayout.is_main_group(layout.nozzle_groups[i]) else visuals.retro_length_m
		assert_almost_eq(_tip_of(plume), layout.nozzle_positions[i] + layout.nozzle_exhausts[i] * length, _vec_tol(1e-4),
				"%s: tip is one plume length down the exhaust" % layout.nozzle_names[i])


func test_the_core_disc_faces_along_the_exhaust_at_the_nozzle_exit() -> void:
	for i: int in layout.nozzle_count():
		var plume: Node3D = _pod_plume(layout.nozzle_names[i])
		var disc: MeshInstance3D = _core_of(plume)
		var normal: Vector3 = (plume.global_transform.basis * (disc.basis * Vector3.BACK)).normalized()  # a QuadMesh faces +Z
		assert_almost_eq(normal, layout.nozzle_exhausts[i], _vec_tol(1e-5), "%s: disc normal is the exhaust axis" % layout.nozzle_names[i])
		var offset: Vector3 = plume.global_transform * disc.position - layout.nozzle_positions[i]
		assert_almost_eq(offset, layout.nozzle_exhausts[i] * ThrusterVisuals.CORE_OFFSET_M, _vec_tol(1e-5),
				"%s: just outside the nozzle, on the axis" % layout.nozzle_names[i])


func test_there_are_no_other_plumes() -> void:
	assert_eq(visuals.glow_count(), layout.nozzle_count() + layout.rcs_nozzles.size())
	assert_eq(visuals.get_child_count(), visuals.glow_count())
	for i: int in visuals.glow_count():
		assert_eq(visuals.glow(i).get_child_count(), 2, "a cone and a core")


func test_plumes_are_unshaded_additive_meshes_that_do_not_billboard() -> void:
	for i: int in visuals.glow_count():
		var plume: Node3D = visuals.glow(i)
		var cone_node: MeshInstance3D = _cone_of(plume)
		assert_true(cone_node.mesh is ArrayMesh, "plume %d cone is a mesh, not a quad" % i)
		assert_false(cone_node.mesh is QuadMesh)
		var core_node: MeshInstance3D = _core_of(plume)
		assert_true(core_node.mesh is QuadMesh, "plume %d core is a disc quad" % i)
		for node: MeshInstance3D in [cone_node, core_node]:
			var material := node.mesh.surface_get_material(0) as StandardMaterial3D
			assert_not_null(material, "%s has a material" % node.name)
			assert_eq(material.blend_mode, BaseMaterial3D.BLEND_MODE_ADD)
			assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
			assert_eq(material.billboard_mode, BaseMaterial3D.BILLBOARD_DISABLED, "tied to the nozzle axis, not the camera")
			assert_eq(node.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var plume_material := visuals.cone(0).mesh.surface_get_material(0) as StandardMaterial3D
	assert_eq(plume_material.resource_path, "res://assets/materials/thruster_plume.tres")
	assert_true(plume_material.vertex_color_use_as_albedo, "the cone fades out along its length through vertex alpha")


func test_the_shared_cone_fades_from_the_nozzle_to_the_far_end() -> void:
	var arrays: Array = ThrusterVisuals.cone_mesh().surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_eq(vertices.size(), colors.size())
	for i: int in vertices.size():
		if is_zero_approx(vertices[i].y):
			assert_almost_eq(colors[i].a, 1.0, 1e-5, "opaque at the nozzle")
			assert_almost_eq(Vector2(vertices[i].x, vertices[i].z).length(), 1.0, 1e-5, "unit radius at the nozzle")
		if is_equal_approx(vertices[i].y, 1.0):
			assert_almost_eq(colors[i].a, 0.0, 1e-5, "gone at the far end")
			assert_almost_eq(Vector2(vertices[i].x, vertices[i].z).length(), ThrusterVisuals.CONE_TIP_RADIUS, 1e-5)
		assert_true(vertices[i].y >= -1e-6 and vertices[i].y <= 1.0 + 1e-6, "between the nozzle and the far end")


func test_plumes_start_dark_and_hidden() -> void:
	for i: int in visuals.glow_count():
		assert_eq(visuals.glow_level(i), 0.0)
		assert_false(visuals.glow(i).visible)


func test_plume_positions_are_ship_local_when_the_node_is_a_child_of_the_ship() -> void:
	var ship := Node3D.new()
	add_child_autofree(ship)
	ship.global_transform = Transform3D(Basis.from_euler(Vector3(0.2, 0.9, 0.0)), Vector3(40.0, 5.0, -8.0))
	var mounted := ThrusterVisuals.new()
	ship.add_child(mounted)
	mounted.setup(layout, _source)
	var plume := mounted.get_node(ThrusterVisuals.POD_PREFIX + "ur_main") as Node3D
	var index: int = layout.nozzle_names.find("ur_main")
	assert_almost_eq(plume.global_position, ship.global_transform * layout.nozzle_positions[index], _vec_tol(1e-4))
	assert_almost_eq(plume.global_basis * Vector3.UP, ship.global_basis * layout.nozzle_exhausts[index], _vec_tol(1e-5),
			"the axis turns with the ship")


# --- levels drive length, radius and alpha ---------------------------------------------------------------------


func test_pod_plumes_follow_the_main_and_retro_levels() -> void:
	output = _levels([1.0, 0.5, 0.0, 0.25], [0.0, 0.0, 0.75, 1.0])  # pods ur, lr, ul, ll
	_settle()
	var mains: Dictionary = {"ur_main": 1.0, "lr_main": 0.5, "ul_main": 0.0, "ll_main": 0.25}
	var retros: Dictionary = {"ur_retro": 0.0, "lr_retro": 0.0, "ul_retro": 0.75, "ll_retro": 1.0}
	for table: Dictionary in [mains, retros]:
		for nozzle_name: String in table:
			var index: int = layout.nozzle_names.find(nozzle_name)
			var expected: float = table[nozzle_name]
			assert_almost_eq(visuals.glow_level(index), expected, 0.002, nozzle_name)
			var plume: Node3D = _pod_plume(nozzle_name)
			assert_eq(plume.visible, expected > 0.0, "%s visible only when lit" % nozzle_name)
			if expected > 0.0:
				assert_almost_eq(_cone_of(plume).transparency, 1.0 - expected, 0.002, "%s cone alpha follows the level" % nozzle_name)
				assert_almost_eq(_core_of(plume).transparency, 1.0 - expected, 0.002, "%s core alpha follows the level" % nozzle_name)


func test_plume_length_is_proportional_to_the_level() -> void:
	output = _levels([1.0, 0.5, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0])
	_settle()
	var full: MeshInstance3D = _cone_of(_pod_plume("ur_main"))
	var half: MeshInstance3D = _cone_of(_pod_plume("lr_main"))
	assert_almost_eq(full.scale.y, visuals.main_length_m, 0.01 * visuals.main_length_m)
	assert_almost_eq(half.scale.y / full.scale.y, 0.5, 0.01)
	assert_almost_eq(full.scale.x, visuals.main_radius_m, 0.01 * visuals.main_radius_m, "full radius at full level")
	assert_lt(half.scale.x, full.scale.x, "a weaker plume is slimmer")
	assert_almost_eq(full.scale.x, full.scale.z, 1e-6, "round")


func test_retro_plumes_are_smaller_than_main_plumes() -> void:
	output = _levels([1.0, 1.0, 1.0, 1.0], [1.0, 1.0, 1.0, 1.0])
	_settle()
	var main_cone: MeshInstance3D = _cone_of(_pod_plume("ur_main"))
	var retro_cone: MeshInstance3D = _cone_of(_pod_plume("ur_retro"))
	assert_almost_eq(main_cone.scale.y, visuals.main_length_m, 0.02)
	assert_almost_eq(retro_cone.scale.y, visuals.retro_length_m, 0.02)
	assert_lt(retro_cone.scale.y, main_cone.scale.y)
	assert_lt(retro_cone.scale.x, main_cone.scale.x)


func test_a_dark_plume_never_has_a_singular_scale() -> void:
	output = _levels([0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0])
	_settle()
	for i: int in visuals.glow_count():
		for node: MeshInstance3D in [visuals.cone(i), visuals.core(i)]:
			assert_gt(node.scale.x, 0.0, "plume %d %s x" % [i, node.name])
			assert_gt(node.scale.y, 0.0, "plume %d %s y" % [i, node.name])
			assert_gt(node.scale.z, 0.0, "plume %d %s z" % [i, node.name])


func test_levels_respond_with_an_80_ms_lag() -> void:
	output = _levels([1.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0])
	var index: int = layout.nozzle_names.find("ur_main")
	assert_almost_eq(visuals.smoothing_s, 0.08, 1e-9)
	visuals.advance(0.08)
	assert_almost_eq(visuals.glow_level(index), 1.0 - exp(-1.0), 1e-6, "63% after one time constant")
	visuals.advance(0.08)
	assert_almost_eq(visuals.glow_level(index), 1.0 - exp(-2.0), 1e-6)
	_settle()
	assert_gt(visuals.glow_level(index), 0.999)


func test_plumes_fade_out_when_the_level_drops() -> void:
	output = _levels([1.0, 1.0, 1.0, 1.0], [1.0, 1.0, 1.0, 1.0])
	_settle()
	assert_true(_pod_plume("ur_main").visible)
	output = _levels([0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0])
	visuals.advance(0.08)
	var index: int = layout.nozzle_names.find("ur_main")
	assert_almost_eq(visuals.glow_level(index), exp(-1.0), 1e-3, "decays the same way")
	assert_true(_pod_plume("ur_main").visible, "not cut off instantly")
	_settle()
	assert_false(_pod_plume("ur_main").visible)


func test_no_output_fades_every_plume_out() -> void:
	output = _levels([1.0, 1.0, 1.0, 1.0], [1.0, 1.0, 1.0, 1.0])
	_settle()
	output = null
	_settle()
	for i: int in visuals.glow_count():
		assert_false(visuals.glow(i).visible, "plume %d" % i)


func test_process_drives_the_plumes_each_frame() -> void:
	output = _levels([1.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0])
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(visuals.glow_level(layout.nozzle_names.find("ur_main")), 0.0, "_process advanced the smoothing")


# --- RCS ------------------------------------------------------------------------------------------------------


func test_rcs_plume_takes_the_max_over_its_tags() -> void:
	# ur_px: thrust pushes the ship left, tags sway_left, yaw_right, roll_left.
	var tags: PackedStringArray = layout.rcs_nozzles[_rcs_index("ur_px") - layout.nozzle_count()]["tags"]
	assert_true(tags.has("sway_left") and tags.has("yaw_right") and tags.has("roll_left"), "fixture tags: %s" % [tags])
	output = _levels([0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0])
	output.rcs_force_level = Vector3(-0.3, 0.0, 0.0)  # sway left 0.3
	output.rcs_torque_level = Vector3(0.0, -0.8, 0.0)  # yaw right 0.8 (body -Y)
	_settle()
	assert_almost_eq(visuals.glow_level(_rcs_index("ur_px")), 0.8, 0.002, "the strongest tag wins")
	output.rcs_torque_level = Vector3.ZERO
	_settle()
	assert_almost_eq(visuals.glow_level(_rcs_index("ur_px")), 0.3, 0.002, "falls back to the remaining tag")


func test_rcs_plume_lights_only_for_its_own_directions() -> void:
	output = _levels([0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0])
	output.rcs_force_level = Vector3(1.0, 0.0, 0.0)  # full sway right
	_settle()
	var lit: int = 0
	for j: int in layout.rcs_nozzles.size():
		var tags: PackedStringArray = layout.rcs_nozzles[j]["tags"]
		var plume: Node3D = _rcs_plume(layout.rcs_nozzles[j]["name"])
		if tags.has("sway_right"):
			lit += 1
			assert_true(plume.visible, "%s pushes right" % layout.rcs_nozzles[j]["name"])
			assert_almost_eq(_cone_of(plume).scale.y, visuals.rcs_length_m, 0.01 * visuals.rcs_length_m)
		else:
			assert_false(plume.visible, "%s does not push right" % layout.rcs_nozzles[j]["name"])
	assert_gt(lit, 0)
	for i: int in layout.nozzle_count():
		assert_false(visuals.glow(i).visible, "pod plumes stay dark under pure RCS")


func test_rcs_plumes_are_smaller_than_pod_plumes() -> void:
	assert_lt(visuals.rcs_length_m, visuals.retro_length_m)
	assert_lt(visuals.retro_length_m, visuals.main_length_m)
	assert_lt(visuals.rcs_radius_m, visuals.retro_radius_m)
	assert_lt(visuals.retro_radius_m, visuals.main_radius_m)


# --- setup ----------------------------------------------------------------------------------------------------


func test_setup_again_rebuilds_without_duplicates() -> void:
	var count: int = visuals.glow_count()
	visuals.setup(layout, _source)
	assert_eq(visuals.glow_count(), count)
	assert_eq(visuals.get_child_count(), count, "the old plumes are gone")
	assert_not_null(_pod_plume("ur_main"), "and the names are free again")


func test_a_missing_source_leaves_the_plumes_dark_without_errors() -> void:
	visuals.setup(layout, Callable())
	for i: int in 10:
		visuals.advance(DT)
	for i: int in visuals.glow_count():
		assert_false(visuals.glow(i).visible)


func test_a_source_returning_null_means_no_output() -> void:
	visuals.setup(layout, func() -> Variant: return null)
	visuals.advance(DT)
	assert_eq(visuals.glow_level(0), 0.0)


func test_advance_before_setup_does_nothing() -> void:
	var bare := ThrusterVisuals.new()
	add_child_autofree(bare)
	bare.advance(DT)
	assert_eq(bare.glow_count(), 0)
