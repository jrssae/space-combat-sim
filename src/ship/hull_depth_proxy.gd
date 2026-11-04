class_name HullDepthProxy
extends MeshInstance3D
## Depth-only stand-in for a splat body (architecture §7.2). GDGS composites splats before the transparent pass and
## splats write no depth, so effects drawn with depth testing (thruster plumes, muzzle flash, projectiles, the buoy
## beacon) behind a hull would show through it. This node draws the body's fallback mesh in opaque black with every
## vertex pulled `inset_m` inward along its normal (`hull_depth_proxy.gdshader`): it writes depth just inside the splat
## surface, so it hides what is behind the hull and never covers the splats.
##
## M4-T11: a ship hands it the fallback mesh with `use_mesh`, and it draws that mesh merged into one surface, so the proxy is one
## draw call per pass however many materials the hull has; on a lean AI ship the same node also draws the fallback mesh itself.
##
## The owner (`Ship`, `NavBuoy`) gives it the mesh the fallback uses (`use_mesh`, or `mesh = fallback.mesh`, whatever is loaded) and
## shows it exactly when the splats are shown, i.e. opposite to the fallback mesh (`SplatStatus`). Shadows and GI
## ignore it. What it looks like is (H); an unlit black hull with splats on top is the intended picture.

const SHADER: Shader = preload("res://assets/shaders/hull_depth_proxy.gdshader")
const INSET_PARAMETER: StringName = &"inset_m"
## Default inset, m: beyond the splat sampling jitter, small enough that the silhouette stays inside the splats.
const DEFAULT_INSET_M: float = 0.04

## How far inside the surface the proxy sits, m.
@export_range(0.0, 0.5, 0.005, "suffix:m") var inset_m: float = DEFAULT_INSET_M:
	set(value):
		inset_m = value
		_sync_inset()

var _material: ShaderMaterial = null
var _source: Mesh = null
var _as_fallback: bool = false
# Each fallback mesh merged into one surface, made once.
static var _merged: Dictionary = {}


func _init() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_sync_inset()


func _sync_inset() -> void:
	if _material != null:
		_material.set_shader_parameter(INSET_PARAMETER, inset_m)


## Draws `source` (the body's fallback mesh): as the black inset proxy, merged into one surface (M4-T11: one draw call per pass
## instead of one per material), or, with `as_fallback`, as the mesh itself with its own materials (a lean AI ship has no
## separate fallback node, §17.10).
func use_mesh(source: Mesh, as_fallback: bool = false) -> void:
	_source = source
	_as_fallback = as_fallback
	mesh = source if as_fallback else merged(source)
	material_override = null if as_fallback else _material


## The fallback mesh this proxy was given (`use_mesh`).
func source_mesh() -> Mesh:
	return _source


## Whether it draws the fallback mesh itself rather than the proxy.
func is_drawing_fallback() -> bool:
	return _as_fallback


## `source` as one surface of positions and normals (all the proxy shader reads), made once per mesh. Null for null.
static func merged(source: Mesh) -> Mesh:
	if source == null:
		return null
	if source.get_surface_count() <= 1:
		return source
	if _merged.has(source):
		return _merged[source]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for s: int in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(s)
		var base: int = vertices.size()
		var surface_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		vertices.append_array(surface_vertices)
		normals.append_array(arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)
		if (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() != surface_vertices.size():
			return source  # no normals to inset along: draw it as it is
		var surface_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if surface_indices.is_empty():
			for i: int in surface_vertices.size():
				indices.append(base + i)
		else:
			for i: int in surface_indices:
				indices.append(base + i)
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = vertices
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_INDEX] = indices
	var mesh_out := ArrayMesh.new()
	mesh_out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	_merged[source] = mesh_out
	return mesh_out
