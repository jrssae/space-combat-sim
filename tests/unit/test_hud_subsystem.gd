extends GutTest
## The target box's subsystem line, its marker on the hull and the lead on the subsystem's point (M10-T18, Q17; by kind since
## M10-T65, Q60), on hand-built cameras: a picked kind names its count standing and the part aimed at and moves the lead (not
## the box); a kind with none left shows destroyed with no marker; the whole ship and an unidentified contact show none.

const VIEW := Vector2(1920.0, 1080.0)


func _hud_input() -> HudInput:
	var input := HudInput.new()
	input.camera_transform = Transform3D.IDENTITY
	input.projection = Projection.create_perspective(75.0, VIEW.x / VIEW.y, 0.05, 100000.0)
	input.viewport_size = VIEW
	input.weapon_speed_mps = 1000.0
	input.weapon_lifetime_s = 8.0
	return input


# A capital 1.5 km ahead whose turrets' nearest standing one sits 100 m to the right of its centre.
func _target(picked: bool = true) -> TargetReadout:
	var t := TargetReadout.new()
	t.id = 7
	t.display_name = "EAS AGAMEMNON"
	t.faction = Factions.EARTH_ALLIANCE
	t.position = Vector3(0.0, 0.0, -1500.0)
	t.range_m = 1500.0
	t.hull_fraction = 0.9
	t.bounding_radius = 200.0
	if picked:
		t.subsystem = {"key": "turrets", "label": "TURRETS 5/6", "part": "mount:turret_1", "state": "damaged", "fraction": 0.4,
				"works": true, "group": "turrets", "point": Vector3.ZERO, "live": 5, "total": 6}
		t.aim_offset = Vector3(100.0, 0.0, 0.0)
	return t


func test_a_picked_kind_gets_a_line_a_state_colour_and_a_marker() -> void:
	var input: HudInput = _hud_input()
	input.target = _target()
	var f: HudFrame = HudLayout.compute(input)
	assert_eq(f.subsystem_line, "TURRETS 5/6  TURRET 1  DAMAGED 40%", "the kind, how many stand, the part aimed at, its state")
	assert_almost_eq(f.subsystem_fraction, 0.4, 1e-6)
	assert_eq(f.subsystem_color, HudLayout.hull_color(0.4))
	assert_true(f.subsystem_marker_visible)
	var centre: Vector2 = HudLayout.project(input, Vector3(0.0, 0.0, -1500.0))["pos"]
	assert_gt(f.subsystem_marker_pos.x, centre.x, "the marker is on the hull where the turret is, right of its centre")
	assert_almost_eq(f.target_box.get_center().x, centre.x, 0.5, "the box stays on the whole hull")


func test_the_lead_aims_at_the_subsystem_not_the_centre() -> void:
	var input: HudInput = _hud_input()
	input.target = _target(false)
	var whole: Vector2 = HudLayout.compute(input).lead_pos
	input.target = _target(true)
	var picked: Vector2 = HudLayout.compute(input).lead_pos
	assert_gt(picked.x, whole.x + 20.0, "the lead moved toward the turret")


func test_a_kind_of_one_part_names_no_part() -> void:
	var input: HudInput = _hud_input()
	var t: TargetReadout = _target()
	t.subsystem.merge({"key": "bridge", "label": "BRIDGE", "part": "bridge", "live": 1, "total": 1}, true)
	input.target = t
	assert_eq(HudLayout.compute(input).subsystem_line, "BRIDGE  DAMAGED 40%")


func test_a_kind_with_none_left_shows_destroyed_dim_with_no_marker() -> void:
	var input: HudInput = _hud_input()
	var t: TargetReadout = _target()
	t.subsystem.merge({"label": "TURRETS 0/6", "part": "", "works": false, "state": "destroyed", "fraction": 0.0, "live": 0}, true)
	t.aim_offset = Vector3.ZERO  # the controller gives the aim back to the whole ship
	input.target = t
	var f: HudFrame = HudLayout.compute(input)
	assert_eq(f.subsystem_line, "TURRETS 0/6  DESTROYED 0%")
	assert_eq(f.subsystem_color, Factions.UNIDENTIFIED_COLOR)
	assert_false(f.subsystem_marker_visible, "nothing left to mark: the guns lead the whole ship")


func test_the_whole_ship_shows_no_subsystem() -> void:
	var input: HudInput = _hud_input()
	input.target = _target(false)
	var f: HudFrame = HudLayout.compute(input)
	assert_eq(f.subsystem_line, "")
	assert_false(f.subsystem_marker_visible)


func test_an_unidentified_contact_shows_no_subsystem() -> void:
	var input: HudInput = _hud_input()
	input.target = _target()
	input.target_unknown = true
	var f: HudFrame = HudLayout.compute(input)
	assert_eq(f.subsystem_line, "")
	assert_false(f.subsystem_marker_visible)
