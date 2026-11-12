extends GutTest
## RadarModel.plot and RadarPlot (M4-T36): the radar's packed plot's unit points and stalks land where `RadarModel.to_screen`
## puts them, and the contacts gathered from `TargetInfo`s keep what the plot reads. The dots themselves are
## `test_radar_model`'s (M6-T18 removed the GDScript `dots` they were compared with).

const TOL: float = 1e-6


# A seeded field of contacts around a turned ship: near, far, beyond the sensors, broadcasting, of every relation.
func _field(count: int, seed_value: int) -> Array[TargetInfo]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var factions: Array[StringName] = [Factions.RAIDERS, Factions.EARTH_ALLIANCE, Factions.NEUTRAL, &"who_knows"]
	var infos: Array[TargetInfo] = []
	for i: int in count:
		var direction := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var range_m: float = [rng.randf_range(10.0, 5000.0), rng.randf_range(5000.0, 26000.0), rng.randf_range(2.0e4, 4.0e5)][i % 3]
		var info := TargetInfo.new(1000 + i * 7, "C%d" % i, factions[i % factions.size()], Vector3(120.0, -40.0, 300.0) + direction * range_m)
		info.broadcast_range_m = [0.0, 0.0, 1.0e5, INF][i % 4]
		infos.append(info)
	return infos


func _own_basis() -> Basis:
	return Basis(Vector3(0.3, 1.0, -0.2).normalized(), 0.8)


func test_with_no_selection_and_no_contacts() -> void:
	var plot: RadarPlot = RadarModel.plot(RadarContacts.new(), 0, Vector3.ZERO, Basis.IDENTITY, Factions.EARTH_ALLIANCE)
	assert_eq(plot.size(), 0)
	assert_eq(plot.selected_index, -1)
	var infos: Array[TargetInfo] = _field(30, 5)
	plot = RadarModel.plot(RadarContacts.from_infos(infos), TargetingSystem.NO_TARGET, Vector3(120.0, -40.0, 300.0), _own_basis(),
			Factions.EARTH_ALLIANCE)
	assert_eq(plot.selected_index, -1)


func test_the_unit_points_and_stalks_land_where_to_screen_puts_them() -> void:
	var infos: Array[TargetInfo] = _field(60, 9)
	var plot: RadarPlot = RadarModel.plot(RadarContacts.from_infos(infos), infos[3].id, Vector3(120.0, -40.0, 300.0), _own_basis(),
			Factions.RAIDERS)
	var centre := Vector2(1700.5, 880.25)
	var radius: float = 131.0
	var placed: PackedVector2Array = RadarPlot.screen_transform(centre, radius) * plot.point_units
	var stalks: PackedVector2Array = RadarPlot.screen_transform(centre, radius) * plot.stalk_units
	assert_eq(stalks.size(), 2 * plot.size())
	assert_eq(plot.stalk_colors.size(), plot.size())
	var off: int = 0
	for i: int in plot.size():
		var point: Vector3 = plot.points[i]
		var at: Vector2 = RadarModel.to_screen(point, centre, radius)
		var foot: Vector2 = RadarModel.to_screen(Vector3(point.x, point.y, 0.0), centre, radius)
		if not placed[i].is_equal_approx(at) or not stalks[2 * i + 1].is_equal_approx(at) or not stalks[2 * i].is_equal_approx(foot):
			off += 1
		var c: Color = plot.colors[i]
		if plot.stalk_colors[i] != Color(c.r, c.g, c.b, 0.5):
			off += 1
	assert_eq(off, 0, "every dot and stalk where the per-dot painter drew it")


func test_gathered_contacts_from_infos_keep_ids_positions_factions_and_reach() -> void:
	var infos: Array[TargetInfo] = _field(8, 2)
	var contacts: RadarContacts = RadarContacts.from_infos(infos)
	assert_eq(contacts.size(), 8)
	for i: int in 8:
		assert_eq(contacts.ids[i], infos[i].id)
		assert_eq(contacts.positions[i], infos[i].position)
		assert_eq(contacts.factions[i], infos[i].faction)
		assert_eq(contacts.reach[i], infos[i].broadcast_range_m)


# The per-contact loop the painter ran before M5-T34, as the reference for the native buffers: [plain, rim, backing] as
# float lists, each instance 12 floats.
func _reference_dots(plot: RadarPlot, centre: Vector2, radius_px: float, backing_radius: float, dot_radius: float,
		backings: bool) -> Array:
	var at: PackedVector2Array = RadarPlot.screen_transform(centre, radius_px) * plot.point_units
	var out: Array = [[], [], []]
	for i: int in at.size():
		var p: Vector2 = at[i]
		if backings:
			out[2].append_array([backing_radius, 0.0, 0.0, p.x, 0.0, backing_radius, 0.0, p.y, 0.0, 0.0, 0.0, 0.8])
		if i == plot.selected_index:
			continue
		var c: Color = plot.colors[i]
		out[1 if plot.rims[i] == 1 else 0].append_array([dot_radius, 0.0, 0.0, p.x, 0.0, dot_radius, 0.0, p.y, c.r, c.g, c.b, c.a])
	return out


func _same(buffer: PackedFloat32Array, count: int, expected: Array) -> bool:
	if count * RadarDotBuffers.STRIDE != expected.size() or buffer.size() < expected.size():
		return false
	for k: int in expected.size():
		if not is_equal_approx(buffer[k], expected[k]):
			return false
	return true


func test_the_native_dot_buffers_match_the_per_contact_loop() -> void:
	var infos: Array[TargetInfo] = _field(80, 4)
	var plot: RadarPlot = RadarModel.plot(RadarContacts.from_infos(infos), infos[3].id, Vector3(120.0, -40.0, 300.0), _own_basis(),
			Factions.RAIDERS)
	assert_gt(plot.rims.count(1), 0, "the field has rim contacts")
	assert_gte(plot.selected_index, 0, "the selection is drawn")
	var centre := Vector2(1700.5, 880.25)
	for backings: bool in [true, false]:
		var held := PackedInt32Array([0, 0, 0])
		var got: RadarDotBuffers = RadarModel.dot_buffers(plot, centre, 131.0, 5.5, 3.0, Color(0.0, 0.0, 0.0, 0.8), backings, held)
		var want: Array = _reference_dots(plot, centre, 131.0, 5.5, 3.0, backings)
		assert_true(_same(got.plain, got.plain_count, want[0]), "plain dots (backings %s)" % backings)
		assert_true(_same(got.rim, got.rim_count, want[1]), "rim dots (backings %s)" % backings)
		assert_true(_same(got.backing, got.backing_count, want[2]), "backings (backings %s)" % backings)
		assert_eq(got.backing_count, plot.size() if backings else 0)
		assert_eq(got.plain_count + got.rim_count, plot.size() - 1, "all but the selection")


func test_a_dot_buffer_is_sized_for_its_multimesh() -> void:
	var infos: Array[TargetInfo] = _field(30, 6)
	var plot: RadarPlot = RadarModel.plot(RadarContacts.from_infos(infos), TargetingSystem.NO_TARGET, Vector3(120.0, -40.0, 300.0),
			_own_basis(), Factions.RAIDERS)
	var first: RadarDotBuffers = RadarModel.dot_buffers(plot, Vector2.ZERO, 100.0, 5.5, 3.0, Color.BLACK, false, PackedInt32Array([0, 0, 0]))
	assert_eq(RadarDotBuffers.instances(first.plain), first.plain_count, "a new multimesh is the count")
	assert_eq(first.backing.size(), 0, "no backings, no buffer")
	var roomy: RadarDotBuffers = RadarModel.dot_buffers(plot, Vector2.ZERO, 100.0, 5.5, 3.0, Color.BLACK, false,
			PackedInt32Array([500, 500, 500]))
	assert_eq(RadarDotBuffers.instances(roomy.plain), 500, "a multimesh that is big enough keeps its size")
	var grown: RadarDotBuffers = RadarModel.dot_buffers(plot, Vector2.ZERO, 100.0, 5.5, 3.0, Color.BLACK, false,
			PackedInt32Array([first.plain_count - 1, 0, 0]))
	assert_eq(RadarDotBuffers.instances(grown.plain), 2 * (first.plain_count - 1), "it doubles when it must grow")
	var empty: RadarDotBuffers = RadarModel.dot_buffers(RadarPlot.new(), Vector2.ZERO, 100.0, 5.5, 3.0, Color.BLACK, true,
			PackedInt32Array([8, 8, 8]))
	assert_eq(empty.plain.size() + empty.rim.size() + empty.backing.size(), 0, "nothing to draw, nothing sized")


func test_the_factions_are_named_when_read() -> void:
	var infos: Array[TargetInfo] = _field(40, 8)
	var plot: RadarPlot = RadarModel.plot(RadarContacts.from_infos(infos), infos[2].id, Vector3(120.0, -40.0, 300.0), _own_basis(),
			Factions.RAIDERS)
	var by_id: Dictionary = {}
	for info: TargetInfo in infos:
		by_id[info.id] = info.faction
	var names: Array[StringName] = plot.factions
	assert_eq(names.size(), plot.size())
	for i: int in plot.size():
		assert_eq(names[i], by_id[plot.ids[i]], "contact %d" % i)
	assert_eq(plot.to_dots()[0].faction, names[0])


# Code review (M5-T47): columns of different lengths, or a colour index outside the palette, are refused with an error
# and an empty plot, never truncated or painted a stand-in colour.
func test_mismatched_columns_are_refused_not_truncated() -> void:
	var native: Object = NativeLib.instantiate(RadarModel.NATIVE_CLASS)
	var ids := PackedInt64Array([1, 2, 3])
	var positions := PackedVector3Array([Vector3(0, 0, -100), Vector3(0, 0, -200)])
	var reach := PackedFloat64Array([0.0, 0.0, 0.0])
	var palette := PackedColorArray([Color.RED])
	var r: Array = native.plot(ids, positions, reach, PackedInt32Array([0, 0, 0]), palette, Vector3.ZERO, Basis.IDENTITY,
			0, 5000.0, Color.GRAY, 0)
	assert_engine_error("columns do not line up")
	assert_eq((r[0] as PackedInt32Array).size(), 0, "nothing plotted")
	assert_eq(int(r[9]), -1)
	positions.append(Vector3(0, 0, -300))
	r = native.plot(ids, positions, reach, PackedInt32Array([0, 1, 0]), palette, Vector3.ZERO, Basis.IDENTITY, 0, 5000.0,
			Color.GRAY, 0)
	assert_engine_error("colour index")
	assert_eq((r[0] as PackedInt32Array).size(), 0, "a colour outside the palette is refused too")
	r = native.plot(ids, positions, reach, PackedInt32Array([0, 0, 0]), palette, Vector3.ZERO, Basis.IDENTITY, 0, 5000.0,
			Color.GRAY, 0)
	assert_eq((r[0] as PackedInt32Array).size(), 3, "matching columns plot every contact")
