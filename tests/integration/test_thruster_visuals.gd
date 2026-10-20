extends GutTest
## ThrusterVisuals with the hardpoints fixture and a fake FlightOutput source (architecture §7.1, M1-T13): a glow node
## for every pod nozzle and every RCS hardpoint at the hardpoint position, whose scale and alpha follow the levels
## with an 80 ms lag. The Ship scene does not exist yet; Main will pass `ship.get_flight_output` as the source, here
## it is a Callable returning whatever `output` holds. How the glow looks is (H).

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


func _pod_glow(nozzle_name: String) -> MeshInstance3D:
	return visuals.get_node_or_null(ThrusterVisuals.POD_PREFIX + nozzle_name) as MeshInstance3D


func _rcs_glow(nozzle_name: String) -> MeshInstance3D:
	return visuals.get_node_or_null(ThrusterVisuals.RCS_PREFIX + nozzle_name) as MeshInstance3D


func _rcs_index(nozzle_name: String) -> int:
	for j: int in layout.rcs_nozzles.size():
		if layout.rcs_nozzles[j]["name"] == nozzle_name:
			return layout.nozzle_count() + j
	return -1


func _vec_tol(tol: float) -> Vector3:
	return Vector3(tol, tol, tol)


# --- one glow per nozzle --------------------------------------------------------------------------------------


func test_a_glow_node_exists_for_every_pod_nozzle() -> void:
	assert_eq(layout.nozzle_count(), 8, "four pods, a main and a retro each")
	for i: int in layout.nozzle_count():
		var glow: MeshInstance3D = _pod_glow(layout.nozzle_names[i])
		assert_not_null(glow, "glow for %s" % layout.nozzle_names[i])
		if glow != null:
			assert_almost_eq(glow.position, layout.nozzle_positions[i], _vec_tol(1e-5), "%s at its hardpoint" % layout.nozzle_names[i])


func test_a_glow_node_exists_for_every_rcs_hardpoint() -> void:
	assert_gt(layout.rcs_nozzles.size(), 0)
	for entry: Dictionary in layout.rcs_nozzles:
		var glow: MeshInstance3D = _rcs_glow(entry["name"])
		assert_not_null(glow, "glow for RCS %s" % entry["name"])
		if glow != null:
			assert_almost_eq(glow.position, entry["position"] as Vector3, _vec_tol(1e-5), "%s at its hardpoint" % entry["name"])


func test_there_are_no_other_glows() -> void:
	assert_eq(visuals.glow_count(), layout.nozzle_count() + layout.rcs_nozzles.size())
	assert_eq(visuals.get_child_count(), visuals.glow_count())


func test_glows_are_quads_with_the_shared_additive_material() -> void:
	for i: int in visuals.glow_count():
		var glow: MeshInstance3D = visuals.glow(i)
		assert_true(glow.mesh is QuadMesh, "glow %d is a quad" % i)
		var material := glow.mesh.surface_get_material(0) as StandardMaterial3D
		assert_not_null(material)
		assert_eq(material.resource_path, "res://assets/materials/thruster_glow.tres")
		assert_eq(material.blend_mode, BaseMaterial3D.BLEND_MODE_ADD)
		assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
		assert_eq(glow.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func test_glows_start_dark_and_hidden() -> void:
	for i: int in visuals.glow_count():
		assert_eq(visuals.glow_level(i), 0.0)
		assert_false(visuals.glow(i).visible)


func test_glow_positions_are_ship_local_when_the_node_is_a_child_of_the_ship() -> void:
	var ship := Node3D.new()
	add_child_autofree(ship)
	ship.global_transform = Transform3D(Basis.from_euler(Vector3(0.2, 0.9, 0.0)), Vector3(40.0, 5.0, -8.0))
	var mounted := ThrusterVisuals.new()
	ship.add_child(mounted)
	mounted.setup(layout, _source)
	var glow := mounted.get_node(ThrusterVisuals.POD_PREFIX + "ur_main") as MeshInstance3D
	var index: int = layout.nozzle_names.find("ur_main")
	assert_almost_eq(glow.global_position, ship.global_transform * layout.nozzle_positions[index], _vec_tol(1e-4))


# --- levels drive scale and alpha -----------------------------------------------------------------------------


func test_pod_glows_follow_the_main_and_retro_levels() -> void:
	output = _levels([1.0, 0.5, 0.0, 0.25], [0.0, 0.0, 0.75, 1.0])  # pods ur, lr, ul, ll
	_settle()
	var mains: Dictionary = {"ur_main": 1.0, "lr_main": 0.5, "ul_main": 0.0, "ll_main": 0.25}
	var retros: Dictionary = {"ur_retro": 0.0, "lr_retro": 0.0, "ul_retro": 0.75, "ll_retro": 1.0}
	for table: Dictionary in [mains, retros]:
		for nozzle_name: String in table:
			var index: int = layout.nozzle_names.find(nozzle_name)
			var expected: float = table[nozzle_name]
			assert_almost_eq(visuals.glow_level(index), expected, 0.002, nozzle_name)
			var glow: MeshInstance3D = _pod_glow(nozzle_name)
			assert_eq(glow.visible, expected > 0.0, "%s visible only when lit" % nozzle_name)
			if expected > 0.0:
				assert_almost_eq(glow.transparency, 1.0 - expected, 0.002, "%s alpha follows the level" % nozzle_name)


func test_glow_scale_is_proportional_to_the_level() -> void:
	output = _levels([1.0, 0.5, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0])
	_settle()
	var full: MeshInstance3D = _pod_glow("ur_main")
	var half: MeshInstance3D = _pod_glow("lr_main")
	assert_almost_eq(full.scale.x, visuals.main_size_m, 0.01 * visuals.main_size_m)
	assert_almost_eq(half.scale.x / full.scale.x, 0.5, 0.01)
	assert_almost_eq(full.scale.y, full.scale.x, 1e-6, "uniform scale")


func test_retro_glows_are_smaller_than_main_glows() -> void:
	output = _levels([1.0, 1.0, 1.0, 1.0], [1.0, 1.0, 1.0, 1.0])
	_settle()
	var main_glow: MeshInstance3D = _pod_glow("ur_main")
	var retro_glow: MeshInstance3D = _pod_glow("ur_retro")
	assert_almost_eq(main_glow.scale.x, visuals.main_size_m, 0.02)
	assert_almost_eq(retro_glow.scale.x, visuals.retro_size_m, 0.02)
	assert_lt(retro_glow.scale.x, main_glow.scale.x)


func test_a_dark_glow_never_has_a_singular_scale() -> void:
	output = _levels([0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0])
	_settle()
	for i: int in visuals.glow_count():
		assert_gt(visuals.glow(i).scale.x, 0.0, "glow %d" % i)


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


func test_glows_fade_out_when_the_level_drops() -> void:
	output = _levels([1.0, 1.0, 1.0, 1.0], [1.0, 1.0, 1.0, 1.0])
	_settle()
	assert_true(_pod_glow("ur_main").visible)
	output = _levels([0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0])
	visuals.advance(0.08)
	var index: int = layout.nozzle_names.find("ur_main")
	assert_almost_eq(visuals.glow_level(index), exp(-1.0), 1e-3, "decays the same way")
	assert_true(_pod_glow("ur_main").visible, "not cut off instantly")
	_settle()
	assert_false(_pod_glow("ur_main").visible)


func test_no_output_fades_every_glow_out() -> void:
	output = _levels([1.0, 1.0, 1.0, 1.0], [1.0, 1.0, 1.0, 1.0])
	_settle()
	output = null
	_settle()
	for i: int in visuals.glow_count():
		assert_false(visuals.glow(i).visible, "glow %d" % i)


func test_process_drives_the_glows_each_frame() -> void:
	output = _levels([1.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0])
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(visuals.glow_level(layout.nozzle_names.find("ur_main")), 0.0, "_process advanced the smoothing")


# --- RCS ------------------------------------------------------------------------------------------------------


func test_rcs_glow_takes_the_max_over_its_tags() -> void:
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


func test_rcs_glow_lights_only_for_its_own_directions() -> void:
	output = _levels([0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0])
	output.rcs_force_level = Vector3(1.0, 0.0, 0.0)  # full sway right
	_settle()
	var lit: int = 0
	for j: int in layout.rcs_nozzles.size():
		var tags: PackedStringArray = layout.rcs_nozzles[j]["tags"]
		var glow: MeshInstance3D = _rcs_glow(layout.rcs_nozzles[j]["name"])
		if tags.has("sway_right"):
			lit += 1
			assert_true(glow.visible, "%s pushes right" % layout.rcs_nozzles[j]["name"])
			assert_almost_eq(glow.scale.x, visuals.rcs_size_m, 0.01 * visuals.rcs_size_m)
		else:
			assert_false(glow.visible, "%s does not push right" % layout.rcs_nozzles[j]["name"])
	assert_gt(lit, 0)
	for i: int in layout.nozzle_count():
		assert_false(visuals.glow(i).visible, "pod glows stay dark under pure RCS")


func test_rcs_glows_are_smaller_than_pod_glows() -> void:
	assert_lt(visuals.rcs_size_m, visuals.retro_size_m)
	assert_lt(visuals.retro_size_m, visuals.main_size_m)


# --- setup ----------------------------------------------------------------------------------------------------


func test_setup_again_rebuilds_without_duplicates() -> void:
	var count: int = visuals.glow_count()
	visuals.setup(layout, _source)
	assert_eq(visuals.glow_count(), count)
	assert_eq(visuals.get_child_count(), count, "the old glows are gone")
	assert_not_null(_pod_glow("ur_main"), "and the names are free again")


func test_a_missing_source_leaves_the_glows_dark_without_errors() -> void:
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
