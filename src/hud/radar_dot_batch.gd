class_name RadarDotBatch
extends RefCounted
## One kind of radar dot drawn as one multimesh (M4-T36), kept drawable when Godot moves its buffer (M7-T45).
##
## Godot 4.7.2 swaps a multimesh's GPU buffer for one twice the size the first time it is written with motion vectors on
## (motion blur, TAA, FSR 2.2), frees the old one, and forgets the 2D renderer's binding to it: a multimesh drawn in 2D before
## that draws nothing until it is resized. The radar kept its stalks and lost its dots once the dot multimeshes had stopped
## growing. A batch that finds its buffer moved resizes itself once, so the next draw binds the new buffer.

## The multimesh; null until the first dots.
var multimesh: MultiMesh = null
## How many times the batch resized itself after Godot moved its buffer (tests read it).
var rebuilds: int = 0

# The GPU buffer the last draw used; empty when the multimesh is new or was just resized.
var _drawn_buffer: RID = RID()


## The multimesh's instance count, 0 before it is made.
func instances() -> int:
	return multimesh.instance_count if multimesh != null else 0


## Draws the first `count` dots of `buffer` with `mesh` on `canvas` in one call. The buffer comes sized for the multimesh
## (`RadarModel.dot_buffers`), so it goes to the server whole.
func submit(canvas: CanvasItem, buffer: PackedFloat32Array, count: int, mesh: Mesh) -> void:
	if multimesh == null:
		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_2D
		multimesh.use_colors = true
	if multimesh.mesh != mesh:
		multimesh.mesh = mesh
	if count == 0:
		multimesh.visible_instance_count = 0
		return
	var capacity: int = RadarDotBuffers.instances(buffer)
	if multimesh.instance_count != capacity:
		multimesh.instance_count = capacity  # grows rarely, never shrinks
		_drawn_buffer = RID()
	var rid: RID = multimesh.get_rid()
	RenderingServer.multimesh_set_buffer(rid, buffer)
	var now: RID = RenderingServer.multimesh_get_buffer_rd_rid(rid)
	if moved(_drawn_buffer, now):
		# Resizing drops the stale binding; the buffer written after it is the one the draw binds.
		multimesh.instance_count = 0
		multimesh.instance_count = capacity
		RenderingServer.multimesh_set_buffer(rid, buffer)
		now = RenderingServer.multimesh_get_buffer_rd_rid(rid)
		rebuilds += 1
	_drawn_buffer = now
	multimesh.visible_instance_count = count
	canvas.draw_multimesh(multimesh, null)


## Whether the GPU buffer changed under a multimesh that was drawn with `drawn` and not resized since.
static func moved(drawn: RID, now: RID) -> bool:
	return drawn.is_valid() and now != drawn
