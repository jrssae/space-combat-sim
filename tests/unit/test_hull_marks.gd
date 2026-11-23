extends GutTest
## Painted hull lettering (M10-T21): the letter a ship wears, where it sits in the atlas and how its quad faces.

const ATLAS: Dictionary = {"chars": "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", "columns": 6, "glyph_height_share": 0.65625}


func test_the_initial_skips_the_factions_prefix() -> void:
	assert_eq(HullMarks.initial_of("EAS Agamemnon"), "A")
	assert_eq(HullMarks.initial_of("EAS Agamemnon 2"), "A")
	assert_eq(HullMarks.initial_of("Zeus"), "Z", "a bare name's own first letter")
	assert_eq(HullMarks.initial_of(""), "")


func test_a_number_mark_shows_the_hull_number() -> void:
	assert_eq(HullMarks.text_for({"text": "number"}, "EAS Hyperion", ATLAS["chars"], "21"), "21")
	assert_eq(HullMarks.text_for({"text": "number"}, "EAS Hyperion", ATLAS["chars"]), "", "no number, nothing printed")


func test_a_mark_shows_the_initial_or_its_own_text() -> void:
	assert_eq(HullMarks.text_for({"text": "initial"}, "EAS Hector", ATLAS["chars"]), "H")
	assert_eq(HullMarks.text_for({"text": "bc-7"}, "EAS Hector", ATLAS["chars"]), "BC7", "uppercased, unprintable characters dropped")
	assert_eq(HullMarks.text_for({"text": "initial"}, "  ", ATLAS["chars"]), "")


func test_a_name_mark_shows_the_whole_name_without_the_prefix() -> void:
	assert_eq(HullMarks.name_of("EAS Lexington 2"), "Lexington 2")
	assert_eq(HullMarks.text_for({"text": "name"}, "EAS Hyperion", ATLAS["chars"]), "HYPERION")
	assert_eq(HullMarks.text_for({"text": "name"}, "EAS Yi Sun-sin 2", ATLAS["chars"]), "YI SUNSIN 2", "a space stays a gap between words")
	assert_eq(HullMarks.text_for({"text": "name"}, "", ATLAS["chars"]), "")


func test_the_atlas_cell_follows_the_character_order() -> void:
	assert_eq(HullMarks.cell_of("A", ATLAS), Vector2i(0, 0))
	assert_eq(HullMarks.cell_of("G", ATLAS), Vector2i(0, 1))
	assert_eq(HullMarks.cell_of("Z", ATLAS), Vector2i(1, 4))
	assert_eq(HullMarks.cell_of("9", ATLAS), Vector2i(5, 5))
	assert_eq(HullMarks.cell_of("?", ATLAS), Vector2i(-1, -1))


func test_the_quad_reads_upright_from_outside_the_face() -> void:
	var basis: Basis = HullMarks.quad_basis(Vector3(0.958, -0.287, 0.0), Vector3(0.287, 0.958, 0.0))
	assert_true(basis.z.is_equal_approx(Vector3(0.958, -0.287, 0.0).normalized()), "the quad faces out")
	assert_almost_eq(basis.determinant(), 1.0, 0.001, "a proper rotation")
	assert_gt(basis.y.y, 0.9, "the letters stand upright")
	assert_lt(basis.x.z, -0.9, "and read toward the bow from the starboard side (the bow is -Z)")


func test_the_quad_holds_the_letters_height() -> void:
	assert_almost_eq(HullMarks.quad_side_m(40.0, ATLAS), 40.0 / 0.65625, 0.001)


func test_a_faction_only_mark_shows_on_that_faction() -> void:
	assert_true(HullMarks.shown_for({"text": "initial"}, &"earth_alliance"), "no restriction: every ship")
	assert_true(HullMarks.shown_for({"only_faction": "renegades"}, &"renegades"))
	assert_false(HullMarks.shown_for({"only_faction": "renegades"}, &"earth_alliance"))


func test_letters_are_spaced_by_their_own_widths_and_centred() -> void:
	var widths: Array = []
	for c: String in ATLAS["chars"]:
		widths.append(0.17 if c == "I" else 0.6)
	var atlas: Dictionary = ATLAS.merged({"widths": widths, "tracking": 0.1, "space": 0.3})
	var at: PackedFloat32Array = HullMarks.offsets("HI", atlas)
	assert_almost_eq(at[0], -0.5 * (0.6 + 0.1 + 0.17) + 0.3, 1e-5, "H's centre")
	assert_almost_eq(at[1] - at[0], 0.3 + 0.1 + 0.085, 1e-5, "a narrow I sits close")
	assert_almost_eq(at[0] + at[1], (0.3 - 0.435) + (0.785 - 0.435), 1e-5)
	var wide: PackedFloat32Array = HullMarks.offsets("HI", atlas, 1.5)
	assert_almost_eq(wide[1] - wide[0], 1.5 * (at[1] - at[0]), 1e-5, "stretched print spreads out")
	var even: PackedFloat32Array = HullMarks.offsets("AB", ATLAS)
	assert_almost_eq(even[1] - even[0], 0.8, 1e-5, "an atlas without widths keeps an even pitch")
	assert_almost_eq(even[0] + even[1], 0.0, 1e-5)


func test_an_outlined_mark_prints_from_the_outlined_atlas() -> void:
	var atlas: Dictionary = ATLAS.merged({"file": "x_marks.png", "outlined_file": "x_marks_outlined.png"})
	assert_eq(HullMarks.atlas_file({"text": "name", "outline": true}, atlas), "x_marks_outlined.png", "the bow name and hull number")
	assert_eq(HullMarks.atlas_file({"text": "name"}, atlas), "x_marks.png", "every other mark prints plain")
	assert_eq(HullMarks.atlas_file({"outline": true}, ATLAS.merged({"file": "x_marks.png"})), "x_marks.png", "no outlined print: the plain one")


func test_a_picture_mark_is_told_from_lettering() -> void:
	assert_true(HullMarks.is_image({"image": "ea_hyperion_ea_emblem.png", "width_m": 42.0}), "the emblem")
	assert_false(HullMarks.is_image({"text": "name"}))
	assert_false(HullMarks.is_image({"image": ""}))
