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
	assert_lte(material.metallic, MeshMaterials.MAX_METALLIC)
	assert_gte(material.roughness, MeshMaterials.MIN_ROUGHNESS)


func test_values_already_matte_are_left_alone_and_it_is_idempotent() -> void:
	var mesh: ArrayMesh = _mesh_with(0.05, 0.9)
	MeshMaterials.matte(mesh)
	MeshMaterials.matte(mesh)
	var material := mesh.surface_get_material(0) as StandardMaterial3D
	assert_eq(material.metallic, 0.05)
	assert_eq(material.roughness, 0.9)


func test_null_and_unmaterialled_meshes_are_ignored() -> void:
	MeshMaterials.matte(null)
	var bare := ArrayMesh.new()
	MeshMaterials.matte(bare)
	pass_test("no error")
