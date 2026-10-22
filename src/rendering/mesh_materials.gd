class_name MeshMaterials
extends RefCounted
## Fixes the materials of the generated fallback meshes after import. The OBJ importer turns the generator's specular exponent
## into metallic 0.93-0.98 and roughness 1, and a nearly pure metal is lit only by reflections: against the black sky (or the
## dim panorama) every face the sun does not hit is black. A hull meant to read as painted plate gets a low metallic value instead.

const MAX_METALLIC: float = 0.15
const MIN_ROUGHNESS: float = 0.65


## Lowers `metallic` and raises `roughness` on every surface material of `mesh` (idempotent; the materials are shared by
## every user of the mesh, which is the point). A null mesh is ignored.
static func matte(mesh: Mesh) -> void:
	if mesh == null:
		return
	for i: int in mesh.get_surface_count():
		var material := mesh.surface_get_material(i) as BaseMaterial3D
		if material == null:
			continue
		material.metallic = minf(material.metallic, MAX_METALLIC)
		material.roughness = maxf(material.roughness, MIN_ROUGHNESS)
