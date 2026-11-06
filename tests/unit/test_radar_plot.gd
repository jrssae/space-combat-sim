extends GutTest
## RadarModel.plot and RadarPlot (M4-T36): the radar's packed plot gives the same dots, in the same order, as the per-contact
## `RadarModel.dots`, and its unit points land where `RadarModel.to_screen` puts them.

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


func test_the_plot_holds_the_same_dots_in_the_same_order_as_the_dots() -> void:
	var infos: Array[TargetInfo] = _field(400, 36)
	var own := Vector3(120.0, -40.0, 300.0)
	var selected: int = infos[18].id  # a near one (every third is within 5 km)
	var expected: Array[RadarModel.Dot] = RadarModel.dots(infos, selected, own, _own_basis(), Factions.EARTH_ALLIANCE)
	var plot: RadarPlot = RadarModel.plot(RadarContacts.from_infos(infos), selected, own, _own_basis(), Factions.EARTH_ALLIANCE)
	var got: Array[RadarModel.Dot] = plot.to_dots()
	assert_gt(expected.size(), 200, "most are on the radar")
	assert_lt(expected.size(), infos.size(), "some are beyond reach")
	assert_eq(got.size(), expected.size())
	var same: int = 0
	for i: int in mini(got.size(), expected.size()):
		var a: RadarModel.Dot = got[i]
		var b: RadarModel.Dot = expected[i]
		if a.id == b.id and a.point == b.point and a.foot == b.foot and a.range_m == b.range_m and a.color == b.color \
				and a.faction == b.faction and a.selected == b.selected and a.above == b.above and a.rim == b.rim:
			same += 1
	assert_eq(same, expected.size(), "every dot equal, bit for bit, in drawing order")
	assert_eq(plot.selected_index, plot.size() - 1, "the selected one last")


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
