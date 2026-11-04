extends GutTest
## `Livery` (M4-T30b, Q35): a wing's livery from the Starfury manifest's table, the fallback for any other wing name (the same FNV-1a
## and the same picks as procgen's `livery_for`), the plain livery for no wing, the player as Alpha 01, and the pool's names parsed.

const STARFURY: String = "starfury_aurora"


func _section() -> Dictionary:
	return MeshAssets.livery_section(STARFURY)


func test_fnv1a_is_procgens() -> void:
	assert_eq(Livery.fnv1a(""), 0x811C9DC5)
	assert_eq(Livery.fnv1a("a"), 0xE40C292C)
	assert_eq(Livery.fnv1a("foobar"), 0xBF9CF968)
	assert_eq(Livery.fnv1a("kilo"), 0xC20F40E0, "tools/procgen/core/livery.py fnv1a32('kilo')")


func test_a_named_wing_gets_its_own_livery_and_number() -> void:
	var section: Dictionary = _section()
	assert_false(section.is_empty(), "run scripts/gen_assets.sh first")
	var alpha: Livery = Livery.for_wing("ALPHA", 2, section)
	assert_eq(alpha.wing, "alpha")
	assert_eq(alpha.pattern, "bands")
	assert_eq(alpha.pattern_index, (section["patterns"] as Dictionary).keys().find("bands"))
	assert_eq(alpha.number, 2)
	assert_eq(alpha.number_text(), "02")
	var row: Array = section["liveries"]["alpha"]["primary"]
	assert_true(alpha.primary.is_equal_approx(Color(row[0], row[1], row[2])), str(alpha.primary))
	var dorsal: int = (section["number_fields"] as Dictionary).keys().find("dorsal")
	assert_true(alpha.field_bits & (1 << dorsal) != 0, "the dorsal number")
	var wing_field: int = (section["number_fields"] as Dictionary).keys().find("wing")
	assert_eq(alpha.field_bits, (1 << dorsal) | (1 << wing_field), "Q37: the deck and the upper left wing, no pods")
	for wing: String in ["beta", "delta", "zeta"]:
		var other: Livery = Livery.for_wing(wing, 3, section)
		assert_ne(other.pattern, alpha.pattern, wing)
		assert_ne(other.primary, alpha.primary, wing)


func test_another_wing_gets_procgens_fallback() -> void:
	var section: Dictionary = _section()
	var kilo: Livery = Livery.for_wing("Kilo", 4, section)
	# procgen: livery_for("kilo") is palette 2 (maroon and sand) with the pinstripe pattern.
	var palette: Array = section["fallback"]["palettes"][2]["primary"]
	assert_true(kilo.primary.is_equal_approx(Color(palette[0], palette[1], palette[2])), str(kilo.primary))
	assert_eq(kilo.pattern, "pinstripe")
	assert_eq(kilo.number, 4)
	var again: Livery = Livery.for_wing("KILO", 4, section)
	assert_eq(again.primary, kilo.primary, "stable for a name in any case")
	var lima: Livery = Livery.for_wing("lima", 4, section)
	assert_ne(lima.primary, kilo.primary)


func test_no_wing_is_the_plain_livery_without_a_number() -> void:
	var plain: Livery = Livery.for_wing("", 5, _section())
	assert_eq(plain.pattern, "plain")
	assert_eq(plain.pattern_index, 0)
	assert_eq(plain.number, 0)
	assert_eq(plain.field_bits, 0)
	assert_eq(plain.number_text(), "")


func test_the_player_flies_alpha_01() -> void:
	var player: Livery = Livery.player(_section())
	assert_eq(player.wing, "alpha")
	assert_eq(player.number, 1)
	assert_eq(player.number_text(), "01")


func test_the_pools_names_parse_into_wing_and_number() -> void:
	assert_eq(Livery.parse_name("ALPHA 2"), ["ALPHA", 2])
	assert_eq(Livery.parse_name("DELTA 12"), ["DELTA", 12])
	assert_eq(Livery.parse_name("SHEET"), ["", 0])
	assert_eq(Livery.parse_name("PLAYER"), ["", 0])
	assert_eq(Livery.parse_name(""), ["", 0])
