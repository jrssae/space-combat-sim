class_name MeshMaterials
extends RefCounted
## Fixes the materials of the generated fallback meshes after import. The OBJ importer turns the generator's specular exponent
## into metallic 0.93-0.98 and roughness 1, and a nearly pure metal is lit only by reflections: against the black sky (or the
## dim panorama) every face the sun does not hit is black. A hull meant to read as painted plate gets a low metallic value instead.
##
## The cockpit interior's glow lives here too (`cockpit`, M3-T29): the OBJ importer reads no emission from the `.mtl`, and the faces must
## read red even when the cabin lamp has lost its light slot to explosions and nozzles.

const MAX_METALLIC: float = 0.15
const MIN_ROUGHNESS: float = 0.65
## A cockpit surface's own glow, by material name. What is not listed here is lit only by the cabin lamp and the sun.
const COCKPIT_GLOW: Dictionary = {
	"ef_cockpit_red": Color(0.42, 0.012, 0.008),
	"ef_cockpit_red_dim": Color(0.12, 0.004, 0.003),
	"ef_cockpit_dark": Color(0.008, 0.002, 0.002),
	"ef_cockpit_sill": Color(0.018, 0.003, 0.003),
	"ef_cockpit_metal": Color(0.016, 0.004, 0.004),
}
## Cockpit surfaces drawn as a flat colour, whatever lights the cabin: the round lamps and the screens' rims.
const COCKPIT_UNLIT: Array[String] = ["ef_cockpit_lamp", "ef_cockpit_rim"]


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


## Gives the cockpit interior's surfaces their glow (see `COCKPIT_GLOW`, `COCKPIT_UNLIT`). A null mesh is ignored.
static func cockpit(mesh: Mesh) -> void:
	if mesh == null:
		return
	for i: int in mesh.get_surface_count():
		var material := mesh.surface_get_material(i) as BaseMaterial3D
		if material == null:
			continue
		var surface_name: String = String(material.resource_name)
		# Hardly any sheen: from this close, the sun's highlight turns near-black panels grey.
		material.roughness = 1.0
		material.metallic_specular = 0.1
		if COCKPIT_UNLIT.has(surface_name):
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		elif COCKPIT_GLOW.has(surface_name):
			material.emission_enabled = true
			material.emission = COCKPIT_GLOW[surface_name]
