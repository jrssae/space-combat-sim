extends GutTest
## A civilian hull's HUD colour (M7-T56, maintainer's m5-056: "A Saturn 3 freighter showed up as an ally rather than as a civilian"):
## the role, not the faction, says what it is, so an Earth Alliance freighter is drawn in the civilian colour on the radar, the
## target box and the target preview, as the target menu files it; a hostile civilian still reads hostile.

const VIEW := Vector2(1920.0, 1080.0)
const EA: StringName = Factions.EARTH_ALLIANCE


func after_each() -> void:
	Factions.reset()


func _info(id: int, faction: StringName, at: Vector3, role: Targetable.Role) -> TargetInfo:
	var info := TargetInfo.new(id, "SATURN 1", faction, at)
	info.role = role
	return info


func test_a_civilian_is_never_drawn_as_an_ally() -> void:
	assert_eq(Factions.contact_color(Factions.Relation.FRIENDLY, true), Factions.CIVILIAN_COLOR, "own people's freighter")
	assert_eq(Factions.contact_color(Factions.Relation.NEUTRAL, true), Factions.CIVILIAN_COLOR, "another people's")
	assert_eq(Factions.contact_color(Factions.Relation.HOSTILE, true), Factions.HOSTILE_COLOR, "a hostile one stays hostile")
	assert_eq(Factions.contact_color(Factions.Relation.FRIENDLY, false), Factions.FRIENDLY_COLOR, "a warship by its relation")
	assert_eq(TargetCategories.COLORS[TargetCategories.Category.CIVILIAN], Factions.CIVILIAN_COLOR, "the menu's colour too")


func test_the_radar_draws_civilians_in_their_colour_and_warships_by_relation() -> void:
	var infos: Array[TargetInfo] = [
		_info(1, EA, Vector3(0.0, 0.0, -300.0), Targetable.Role.CIVILIAN),
		_info(2, EA, Vector3(0.0, 0.0, -600.0), Targetable.Role.SHIP),
		_info(3, &"narn", Vector3(0.0, 0.0, -900.0), Targetable.Role.CIVILIAN),
		_info(4, Factions.RAIDERS, Vector3(0.0, 0.0, -1200.0), Targetable.Role.SHIP),
	]
	var contacts: RadarContacts = RadarContacts.from_infos(infos)
	assert_eq(contacts.civilian, PackedByteArray([1, 0, 1, 0]))
	var plot: RadarPlot = RadarModel.plot(contacts, 0, Vector3.ZERO, Basis.IDENTITY, EA)
	var colour_of: Dictionary = {}
	for dot: RadarModel.Dot in plot.to_dots():
		colour_of[dot.id] = dot.color
	assert_eq(colour_of[1], Factions.CIVILIAN_COLOR, "an Earth Alliance Saturn is a civilian, not an ally")
	assert_eq(colour_of[2], Factions.FRIENDLY_COLOR, "an Earth Alliance Starfury is an ally")
	assert_eq(colour_of[3], Factions.CIVILIAN_COLOR, "a Narn transport is a civilian")
	assert_eq(colour_of[4], Factions.HOSTILE_COLOR)
	assert_eq(plot.to_dots().size(), 4)


func test_the_target_box_and_preview_show_a_civilian_target_in_its_colour() -> void:
	var input := HudInput.new()
	input.camera_transform = Transform3D.IDENTITY
	input.projection = Projection.create_perspective(75.0, VIEW.x / VIEW.y, 0.05, 100000.0)
	input.viewport_size = VIEW
	input.faction = EA
	var t := TargetReadout.new()
	t.id = 7
	t.display_name = "SATURN 1"
	t.faction = EA
	t.role = Targetable.Role.CIVILIAN
	t.position = Vector3(0.0, 0.0, -500.0)
	t.range_m = 500.0
	t.hull_fraction = 1.0
	input.target = t
	assert_eq(HudLayout.compute(input).target_color, Factions.CIVILIAN_COLOR, "the target box")
	var info: TargetInfo = _info(7, EA, Vector3(0.0, 0.0, -500.0), Targetable.Role.CIVILIAN)
	var model: TargetPreviewModel = TargetPreviewModel.contact(info, Vector3.ZERO, Vector3.ZERO, EA, {"asset_id": "saturn_3_freighter"})
	assert_eq(model.title_color, Factions.CIVILIAN_COLOR, "the preview's title")
