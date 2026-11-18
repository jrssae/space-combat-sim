extends GutTest
## M7-T45: a radar dot batch resizes itself only when Godot moved the buffer it last drew with (the GPU half is
## `tests/integration/test_radar_dots_gpu.gd`).

const STRIDE: int = RadarDotBuffers.STRIDE


func _buffer(instances: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(instances * STRIDE)
	for i: int in instances:
		out[i * STRIDE] = 3.0
		out[i * STRIDE + 5] = 3.0
		out[i * STRIDE + 11] = 1.0
	return out


func test_only_a_drawn_buffer_that_changed_counts_as_moved() -> void:
	var a: RID = RenderingServer.multimesh_create()
	var b: RID = RenderingServer.multimesh_create()
	assert_false(RadarDotBatch.moved(RID(), a), "nothing drawn yet, or just resized: a new buffer is expected")
	assert_false(RadarDotBatch.moved(a, a), "the same buffer")
	assert_true(RadarDotBatch.moved(a, b), "the buffer changed under a drawn multimesh")
	RenderingServer.free_rid(a)
	RenderingServer.free_rid(b)


# Submits on `canvas` inside its draw, as the painter does, and waits for the frame.
func _submit(canvas: Node2D, batch: RadarDotBatch, buffer: PackedFloat32Array, count: int, mesh: Mesh) -> void:
	var paint := func() -> void: batch.submit(canvas, buffer, count, mesh)
	canvas.draw.connect(paint)
	canvas.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	canvas.draw.disconnect(paint)


func test_a_batch_sizes_its_multimesh_for_the_buffer_and_keeps_it() -> void:
	var canvas := Node2D.new()
	add_child_autofree(canvas)
	var batch := RadarDotBatch.new()
	assert_eq(batch.instances(), 0, "no multimesh before the first dots")
	var mesh := QuadMesh.new()
	await _submit(canvas, batch, _buffer(8), 5, mesh)
	assert_eq(batch.instances(), 8, "sized for the buffer")
	assert_eq(batch.multimesh.visible_instance_count, 5, "draws only the dots there are")
	await _submit(canvas, batch, _buffer(8), 7, mesh)
	assert_eq(batch.instances(), 8)
	assert_eq(batch.rebuilds, 0, "no buffer moved")
	await _submit(canvas, batch, PackedFloat32Array(), 0, mesh)
	assert_eq(batch.multimesh.visible_instance_count, 0, "no dots, nothing drawn")
