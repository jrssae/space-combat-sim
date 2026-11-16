extends GutTest
## M7-T45: the radar's dots stay drawn after motion vectors come on mid-run. Godot 4.7.2 moves a multimesh's buffer the first
## time it is written with motion vectors on and leaves the 2D renderer bound to the freed one, so the radar showed only its
## stalks once its dot multimeshes had stopped growing. Contacts come and go (the multimeshes grow to their size) with the ship
## rolled through 0-360 degrees, then a motion-vector effect comes on and the run goes on; every frame's dots are read back from
## the GPU at the places the radar puts them.
## Needs the real renderer: headless runs have no RenderingDevice and mark it pending. Run with a window:
## `.tools/godot/godot --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_radar_dots_gpu.gd -gexit`

const SIZE: int = 512
const RADIUS_PX: float = 230.0
const MAX_CONTACTS: int = 300
## A dot's pixel is lit when a channel passes this (the background is black).
const LIT: float = 0.15

var viewport: SubViewport
var canvas: Node2D
var painter: HudPainter
var frame := HudFrame.new()
var surface := HudSurface.new()
var effect: CompositorEffect


func before_each() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	add_child_autofree(viewport)
	canvas = Node2D.new()
	viewport.add_child(canvas)
	painter = HudPainter.new(canvas)
	canvas.draw.connect(_paint)
	surface.items = [HudSurface.RADAR]
	surface.radar_centre = Vector2(SIZE, SIZE) * 0.5
	surface.radar_radius_px = RADIUS_PX


func after_each() -> void:
	if effect != null:
		effect.enabled = false
		effect = null


func _paint() -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), Color.BLACK)
	painter.paint(frame, surface)


func _gpu() -> bool:
	if RenderingServer.get_rendering_device() == null:
		pending("needs the real renderer (no RenderingDevice headless)")
		return false
	return true


# `n` contacts out to the sensors' range, half friends and half raiders; `seed_value` picks where.
func _contacts(n: int, seed_value: int) -> RadarContacts:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var c := RadarContacts.new()
	c.faction_names = [Factions.EARTH_ALLIANCE, Factions.RAIDERS]
	for i: int in n:
		c.ids.append(i + 1)
		var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.4, 0.4), rng.randf_range(-1.0, 1.0)).normalized()
		c.positions.append(dir * rng.randf_range(300.0, RadarModel.MAX_RANGE_M * 0.95))
		c.faction_ix.append(i % 2)
		c.reach.append(0.0)
	return c


# Plots `contacts` for the ship rolled `roll_deg` and holds it two frames, so both halves of a motion-vector multimesh carry
# it; returns the share of the plain dots whose pixels read back lit.
func _show(contacts: RadarContacts, roll_deg: float) -> float:
	frame.radar_plot = RadarModel.plot(contacts, -1, Vector3.ZERO, Basis(Vector3.FORWARD, deg_to_rad(roll_deg)),
			Factions.EARTH_ALLIANCE)
	for i: int in 2:
		canvas.queue_redraw()
		await RenderingServer.frame_post_draw
	var k: float = RADIUS_PX / HudLayout.RADAR_RADIUS_UNITS
	var dots: RadarDotBuffers = RadarModel.dot_buffers(frame.radar_plot, surface.radar_centre, RADIUS_PX, 5.5 * k, 3.0 * k,
			Color.BLACK, false, PackedInt32Array([0, 0, 0]))
	if dots.plain_count == 0:
		return 1.0
	var image: Image = viewport.get_texture().get_image()
	var lit: int = 0
	for d: int in dots.plain_count:
		var o: int = d * RadarDotBuffers.STRIDE
		# Beside the centre, clear of the dot's own stalk.
		var at := Vector2(dots.plain[o + 3] + 0.5 * dots.plain[o], dots.plain[o + 7])
		var p := Vector2i(clampi(roundi(at.x), 0, SIZE - 1), clampi(roundi(at.y), 0, SIZE - 1))
		var px: Color = image.get_pixelv(p)
		if maxf(px.r, maxf(px.g, px.b)) > LIT:
			lit += 1
	return float(lit) / float(dots.plain_count)


# The size of the GPU buffer behind the radar's plain dots, in floats (twice the instances' once motion vectors are on).
func _buffer_floats() -> int:
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	var buffer: RID = RenderingServer.multimesh_get_buffer_rd_rid(painter._dots.multimesh.get_rid())
	return rd.buffer_get_data(buffer).size() / 4


func test_the_dots_stay_drawn_when_motion_vectors_come_on_after_many_contacts() -> void:
	if not _gpu():
		return
	# Contacts come and go with the ship rolling: the multimeshes grow to their size.
	var worst_before: float = 1.0
	for step: int in 24:
		var n: int = 4 + int(float(MAX_CONTACTS - 4) * float(step % 12) / 11.0) if step < 12 else MAX_CONTACTS - step * 7
		worst_before = minf(worst_before, await _show(_contacts(n, step), float(step) * 15.0))
	var instances: int = painter._dots.instances()
	if _buffer_floats() != instances * RadarDotBuffers.STRIDE:
		pending("motion vectors were already on; this needs them off at the start")
		return
	assert_gt(worst_before, 0.9, "the dots draw before motion vectors are on")
	effect = CompositorEffect.new()
	effect.needs_motion_vectors = true  # enabled: motion vectors on, as motion blur, TAA or FSR 2.2 turn them on
	var worst_after: float = 1.0
	for step: int in 24:
		var n: int = MAX_CONTACTS - (step * 37) % (MAX_CONTACTS - 10)
		worst_after = minf(worst_after, await _show(_contacts(n, 100 + step), float(step) * 15.0))
	assert_eq(painter._dots.instances(), instances, "the run after it needs no more room, so nothing resizes the multimesh")
	assert_eq(_buffer_floats(), 2 * instances * RadarDotBuffers.STRIDE, "motion vectors are on for the radar's multimesh")
	assert_gt(worst_after, 0.9, "every frame's dots still draw after motion vectors came on (worst %.2f)" % worst_after)
