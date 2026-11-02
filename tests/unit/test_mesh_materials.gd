extends GutTest
## MeshMaterials.matte: generated hull meshes import as near-pure metal (black where the sun does not hit); it makes them plate.


func _mesh_with(metallic: float, roughness: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.metallic = metallic
	material.roughness = roughness
	mesh.surface_set_material(0, material)
	return mesh


func test_a_metal_hull_becomes_matte() -> void:
	var mesh: ArrayMesh = _mesh_with(0.98, 1.0)
	MeshMaterials.matte(mesh)
	var material := mesh.surface_get_material(0) as StandardMaterial3D
	assert_lte(material.metallic, MeshMaterials.MAX_METALLIC + 1e-6)
	assert_gte(material.roughness, MeshMaterials.MIN_ROUGHNESS)


func test_values_already_matte_are_left_alone_and_it_is_idempotent() -> void:
	var mesh: ArrayMesh = _mesh_with(0.05, 0.9)
	MeshMaterials.matte(mesh)
	MeshMaterials.matte(mesh)
	var material := mesh.surface_get_material(0) as StandardMaterial3D
	assert_almost_eq(material.metallic, 0.05, 1e-6)
	assert_almost_eq(material.roughness, 0.9, 1e-6)


func test_null_and_unmaterialled_meshes_are_ignored() -> void:
	MeshMaterials.matte(null)
	var bare := ArrayMesh.new()
	MeshMaterials.matte(bare)
	pass_test("no error")


# --- the cockpit interior (M3-T29) --------------------------------------------------------------------------------------


func _named_mesh(names: Array[String]) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for surface_name: String in names:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.resource_name = surface_name
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh


func _material(mesh: ArrayMesh, index: int) -> StandardMaterial3D:
	return mesh.surface_get_material(index) as StandardMaterial3D


func test_the_struts_glow_red_of_their_own() -> void:
	var mesh: ArrayMesh = _named_mesh(["ef_cockpit_red", "ef_cockpit_dark"])
	MeshMaterials.cockpit(mesh)
	assert_true(_material(mesh, 0).emission_enabled, "whether or not the cabin lamp has a light slot")
	assert_gt(_material(mesh, 0).emission.r, _material(mesh, 0).emission.g * 10.0, "saturated red")
	assert_gt(_material(mesh, 0).emission.r, _material(mesh, 1).emission.r * 10.0, "the rest stays near black")
	assert_lt(_material(mesh, 0).emission.r, 1.0, "dim enough that the view outside still reads")


func test_lamps_and_rims_are_unlit_and_lamp_states_are_left_alone() -> void:
	var mesh: ArrayMesh = _named_mesh(["ef_cockpit_lamp", "ef_cockpit_rim", "ef_cockpit_ind_assist"])
	MeshMaterials.cockpit(mesh)
	assert_eq(_material(mesh, 0).shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_eq(_material(mesh, 1).shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_false(_material(mesh, 2).emission_enabled, "a state lamp is lit by CockpitScreens")


func test_cockpit_ignores_a_null_mesh() -> void:
	MeshMaterials.cockpit(null)
	pass_test("no error")
