class_name ComputeUniform
extends RefCounted
## The one `RDUniform` builder the compositor compute effects share (motion blur, sky velocity, velocity probe).


## A uniform of `type` at `binding` holding `ids` (RIDs).
static func make(type: RenderingDevice.UniformType, binding: int, ids: Array) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = type
	uniform.binding = binding
	for id: RID in ids:
		uniform.add_id(id)
	return uniform
