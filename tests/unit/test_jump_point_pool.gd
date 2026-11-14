extends GutTest
## Mass arrivals (M6-T20, AC13): a pool holds up to a hundred jump points that share their mesh and materials, opens all hundred
## at once with nothing made, reuses them once they close, lights only the nearest few and sounds only a few a second. A far
## point draws less detail but flashes on the same timing as a near one.

var pool: JumpPointPool


func before_each() -> void:
	JumpVortex.forced_level = -1
	pool = JumpPointPool.new()
	add_child_autofree(pool)
	pool.prepare(JumpPointPool.MAX_POINTS)


func after_each() -> void:
	JumpVortex.forced_level = -1


# Points `spacing_m` apart along -Z, facing the origin, each `radius_m` across.
func _xforms(count: int, spacing_m: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for i: int in count:
		out.append(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -spacing_m * float(i + 1))))
	return out


func test_the_pool_holds_a_hundred_points_at_most() -> void:
	assert_eq(pool.size(), JumpPointPool.MAX_POINTS)
	pool.prepare(JumpPointPool.MAX_POINTS + 20)
	assert_eq(pool.size(), JumpPointPool.MAX_POINTS, "never more than a hundred")
	assert_eq(pool.get_child_count(), JumpPointPool.MAX_POINTS)


func test_every_point_shares_the_mesh_and_its_directions_materials() -> void:
	var first: JumpVortex = pool.points()[0]
	for point: JumpVortex in pool.points():
		assert_same(point.funnel.mesh, first.funnel.mesh)
		assert_same(point.funnel.material_override, first.funnel.material_override)
		assert_same(point.flash_quad.material_override, first.flash_quad.material_override)
		assert_same(point.flash_quad.mesh, first.flash_quad.mesh)
	var xforms: Array[Transform3D] = _xforms(2, 500.0)
	var fit := VortexFit.new(60.0, 96.0)
	var arrival: JumpVortex = pool.open_with(xforms[0], fit, JumpVortex.Direction.ARRIVAL)
	var departure: JumpVortex = pool.open_with(xforms[1], fit, JumpVortex.Direction.DEPARTURE)
	assert_same(arrival.funnel.material_override, JumpVortex.funnel_material(JumpVortex.DEFAULT_COLOURS, JumpVortex.Direction.ARRIVAL))
	assert_same(departure.funnel.material_override,
			JumpVortex.funnel_material(JumpVortex.DEFAULT_COLOURS, JumpVortex.Direction.DEPARTURE))
	assert_ne(arrival.funnel.material_override, departure.funnel.material_override, "one material per direction")


func test_a_hundred_points_open_at_once_with_nothing_made() -> void:
	var xforms: Array[Transform3D] = _xforms(JumpPointPool.MAX_POINTS, 300.0)
	var fit := VortexFit.new(60.0, 96.0)
	# One opening first, near and far: what is made once for every vortex (the coarse mesh, the engine's first-use caches).
	var once: JumpVortex = pool.open_with(xforms[-1], fit, JumpVortex.Direction.ARRIVAL)
	once.advance(1.5)
	once.update_visuals_for(Vector3.ZERO, VortexLod.px_per_unit(60.0, 1080.0))
	once.update_visuals_for(xforms[-1].origin, VortexLod.px_per_unit(60.0, 1080.0))
	once.advance(VortexTiming.for_point().done_at_s())
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	var nodes: float = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var opened: Array[JumpVortex] = []
	for xform: Transform3D in xforms:
		opened.append(pool.open_with(xform, fit, JumpVortex.Direction.ARRIVAL))
	for point: JumpVortex in opened:
		point.advance(VortexTiming.point_forming_s() - VortexTiming.GROW_S * 0.5)
		point.update_visuals_for(Vector3.ZERO, VortexLod.px_per_unit(60.0, 1080.0))
	var made: float = Performance.get_monitor(Performance.OBJECT_COUNT) - objects
	var made_nodes: float = Performance.get_monitor(Performance.OBJECT_NODE_COUNT) - nodes
	assert_lte(made, float(JumpPointPool.SOUND_VOICES), "nothing made opening and drawing a hundred points but the few sounds' playbacks (%d)" % made)
	assert_eq(made_nodes, 0.0, "no node either")
	assert_eq(pool.open_count(), JumpPointPool.MAX_POINTS, "all a hundred open together")
	var distinct: Dictionary = {}
	for point: JumpVortex in opened:
		distinct[point] = true
		assert_eq(point.phase_name(), "grow", "each one forming")
	assert_eq(distinct.size(), JumpPointPool.MAX_POINTS, "a hundred different points")
	assert_almost_eq(opened[-1].position.z, xforms[-1].origin.z, 0.01, "each where it was asked")


func test_closed_points_are_reused_and_with_all_open_the_oldest_goes() -> void:
	var xforms: Array[Transform3D] = _xforms(JumpPointPool.MAX_POINTS, 300.0)
	var fit := VortexFit.new(60.0, 96.0)
	var first: Array[JumpVortex] = []
	for xform: Transform3D in xforms:
		first.append(pool.open_with(xform, fit, JumpVortex.Direction.ARRIVAL))
	first[0].advance(0.5)  # the oldest
	var extra: JumpVortex = pool.open_with(xforms[0], fit, JumpVortex.Direction.ARRIVAL)
	assert_same(extra, first[0], "with every point open the oldest is taken back")
	assert_eq(extra.age_s, 0.0, "and opens anew")
	for point: JumpVortex in first:
		point.advance(VortexTiming.for_point().done_at_s() + 0.1)
	assert_eq(pool.open_count(), 0, "all closed after a point's life")
	var again: Dictionary = {}
	for xform: Transform3D in xforms:
		again[pool.open_with(xform, fit, JumpVortex.Direction.ARRIVAL)] = true
	for point: JumpVortex in first:
		assert_true(again.has(point), "the next wave reuses the same points")
	assert_eq(pool.opened, 2 * JumpPointPool.MAX_POINTS + 1)


func test_closed_points_do_not_process() -> void:
	var point: JumpVortex = pool.points()[0]
	assert_false(point.is_physics_processing(), "closed: no tick")
	assert_false(point.is_processing())
	pool.open_with(Transform3D.IDENTITY, VortexFit.new(), JumpVortex.Direction.ARRIVAL)
	assert_true(point.is_physics_processing(), "open: it ages each tick")
	assert_false(point.is_processing(), "its pool draws it")
	point.advance(VortexTiming.for_point().done_at_s() + 0.1)
	assert_false(point.is_physics_processing(), "closed again")


func test_only_the_nearest_points_carry_a_light_and_a_few_sound() -> void:
	var xforms: Array[Transform3D] = _xforms(20, 400.0)
	xforms.reverse()  # the nearest open last
	var opened: Array[JumpVortex] = []
	for xform: Transform3D in xforms:
		opened.append(pool.open_with(xform, VortexFit.new(), JumpVortex.Direction.ARRIVAL))
	pool._process(0.0)
	var lit: Array[float] = []
	for point: JumpVortex in opened:
		if point.lit:
			lit.append(-point.position.z)
	lit.sort()
	assert_eq(lit, [400.0, 800.0, 1200.0] as Array[float], "the three nearest to the camera (here the origin) are lit")
	var sounding: int = 0
	for point: JumpVortex in opened:
		sounding += 0 if point.muted else 1
	assert_eq(sounding, JumpPointPool.SOUND_VOICES, "twenty opening in one second: only a few sound")


func test_a_group_widens_its_point_instead_of_opening_another() -> void:
	var world := WorldFrame.new()
	add_child_autofree(world)
	pool.world = world
	var lead: JumpVortex = pool.open_for(world.to_universe(Vector3(0.0, 0.0, -1000.0)), Vector3.FORWARD, 10.0,
			JumpVortex.Direction.ARRIVAL, false)
	var before: float = lead.fit.mouth_radius_m
	pool.join(lead, world.to_universe(Vector3(200.0, 0.0, -1000.0)), 10.0)
	assert_eq(pool.open_count(), 1, "one point for the group")
	assert_almost_eq(lead.fit.mouth_radius_m, 200.0 + before, 0.01, "wide enough for the wingman's own point")
	var own: JumpVortex = pool.open_for(world.to_universe(Vector3(100.0, 0.0, -1000.0)), Vector3.FORWARD, 10.0,
			JumpVortex.Direction.ARRIVAL, false)
	assert_ne(own, lead, "not sharing: a point of its own even close by")


func test_a_far_point_draws_less_but_flashes_on_the_same_timing() -> void:
	var near: JumpVortex = pool.open_with(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -200.0)), VortexFit.new(60.0, 96.0),
			JumpVortex.Direction.ARRIVAL)
	var far: JumpVortex = pool.open_with(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -50000.0)), VortexFit.new(60.0, 96.0),
			JumpVortex.Direction.ARRIVAL)
	var px: float = VortexLod.px_per_unit(60.0, 1080.0)
	for age: float in [0.2, 0.33, 0.9, 2.0]:
		near.age_s = age
		far.age_s = age
		near.update_visuals_for(Vector3.ZERO, px)
		far.update_visuals_for(Vector3.ZERO, px)
		assert_eq(far.flash_quad.get_instance_shader_parameter(&"level"), near.flash_quad.get_instance_shader_parameter(&"level"),
				"the same flash at %.2f s" % age)
		assert_eq(far.flash_quad.visible, near.flash_quad.visible)
	assert_eq(near.lod_level, 0, "200 m off: every layer (%.0f px)" % near.radius_px)
	assert_eq(far.lod_level, VortexLod.LAYER_COUNT, "50 km off: the soft disc (%.2f px)" % far.radius_px)
	assert_true(far.is_coarse(), "and the coarse mesh")
	assert_same(far.funnel.mesh, JumpVortex.coarse_funnel_mesh())
	assert_eq(far.funnel.get_instance_shader_parameter(&"vortex_lod_a"), Vector4.ZERO, "no hairs, no patches")
	JumpVortex.forced_level = 2
	near.update_visuals_for(Vector3.ZERO, px)
	assert_eq(near.funnel.get_instance_shader_parameter(&"vortex_lod_a"), Vector4(0.0, 0.0, 1.0, 1.0),
			"a forced level drops its layers at any size")
