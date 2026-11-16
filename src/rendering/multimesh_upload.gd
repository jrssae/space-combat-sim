class_name MultiMeshUpload
extends RefCounted
## Buffer uploads for the batched draws that interpolate their own instances between ticks, so Godot's multimesh
## interpolation must stay off for them (it warns on any upload made outside the physics step).


## Uploads `buffer` to `multimesh` with Godot's own interpolation off. The node turns it back on whenever it enters the
## tree or resets, so it is cleared again before every upload.
static func set_buffer(multimesh: MultiMesh, buffer: PackedFloat32Array) -> void:
	RenderingServer.multimesh_set_physics_interpolated(multimesh.get_rid(), false)
	RenderingServer.multimesh_set_buffer(multimesh.get_rid(), buffer)


## Moves instance `index` of `multimesh` with Godot's own interpolation off, for the same reason as `set_buffer`.
static func set_instance_transform(multimesh: MultiMesh, index: int, transform: Transform3D) -> void:
	RenderingServer.multimesh_set_physics_interpolated(multimesh.get_rid(), false)
	multimesh.set_instance_transform(index, transform)
