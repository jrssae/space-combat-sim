extends GutTest
## Painted hull lettering (M10-T21): the letter a ship wears, where it sits in the atlas and how its quad faces.

const ATLAS: Dictionary = {"chars": "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", "columns": 6, "glyph_height_share": 0.65625}


func test_the_initial_skips_the_factions_prefix() -> void:
	assert_eq(HullMarks.initial_of("EAS Agamemnon"), "A")
	assert_eq(HullMarks.initial_of("EAS Agamemnon 2"), "A")
	assert_eq(HullMarks.initial_of("Zeus"), "Z", "a bare name's own first letter")
	assert_eq(HullMarks.initial_of(""), "")


func test_a_mark_shows_the_initial_or_its_own_text() -> void:
	assert_eq(HullMarks.text_for({"text": "initial"}, "EAS Hector", ATLAS["chars"]), "H")
	assert_eq(HullMarks.text_for({"text": "bc-7"}, "EAS Hector", ATLAS["chars"]), "BC7", "uppercased, unprintable characters dropped")
	assert_eq(HullMarks.text_for({"text": "initial"}, "  ", ATLAS["chars"]), "")


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
