extends GutTest
## Factions (architecture §15.1 D25, AC1): the relation table, the hostility query and the HUD colours.

const ALL_KNOWN: Array[StringName] = [Factions.EARTH_ALLIANCE, Factions.RAIDERS, Factions.NEUTRAL]


func test_faction_ids() -> void:
	assert_eq(Factions.EARTH_ALLIANCE, &"earth_alliance")
	assert_eq(Factions.RAIDERS, &"raiders")
	assert_eq(Factions.NEUTRAL, &"neutral")


func test_relation_table() -> void:
	var friendly: int = Factions.Relation.FRIENDLY
	var neutral: int = Factions.Relation.NEUTRAL
	var hostile: int = Factions.Relation.HOSTILE
	# Rows: self faction; columns: other faction, in ALL_KNOWN order (earth_alliance, raiders, neutral).
	var table: Array = [
		[friendly, hostile, neutral],
		[hostile, friendly, neutral],
		[neutral, neutral, friendly],
	]
	for row: int in ALL_KNOWN.size():
		for column: int in ALL_KNOWN.size():
			assert_eq(int(Factions.relation(ALL_KNOWN[row], ALL_KNOWN[column])), (table[row] as Array)[column],
					"%s vs %s" % [ALL_KNOWN[row], ALL_KNOWN[column]])


func test_relation_is_symmetric() -> void:
	var ids: Array[StringName] = [Factions.EARTH_ALLIANCE, Factions.RAIDERS, Factions.NEUTRAL, &"pirates", &""]
	for a: StringName in ids:
		for b: StringName in ids:
			assert_eq(Factions.relation(a, b), Factions.relation(b, a), "%s vs %s" % [a, b])


func test_same_faction_is_friendly() -> void:
	assert_eq(Factions.relation(Factions.EARTH_ALLIANCE, Factions.EARTH_ALLIANCE), Factions.Relation.FRIENDLY)
	assert_eq(Factions.relation(Factions.RAIDERS, Factions.RAIDERS), Factions.Relation.FRIENDLY)
	assert_eq(Factions.relation(&"pirates", &"pirates"), Factions.Relation.FRIENDLY)


func test_unknown_faction_is_neutral_against_everyone_else() -> void:
	for other: StringName in ALL_KNOWN:
		assert_eq(Factions.relation(&"pirates", other), Factions.Relation.NEUTRAL, "pirates vs %s" % other)
		assert_eq(Factions.relation(&"", other), Factions.Relation.NEUTRAL, "empty vs %s" % other)
	assert_eq(Factions.relation(&"pirates", &"smugglers"), Factions.Relation.NEUTRAL)


func test_is_hostile_only_for_earth_alliance_against_raiders() -> void:
	assert_true(Factions.is_hostile(Factions.EARTH_ALLIANCE, Factions.RAIDERS))
	assert_true(Factions.is_hostile(Factions.RAIDERS, Factions.EARTH_ALLIANCE))
	var others: Array[StringName] = [Factions.NEUTRAL, &"pirates", &""]
	for faction: StringName in [Factions.EARTH_ALLIANCE, Factions.RAIDERS]:
		assert_false(Factions.is_hostile(faction, faction), "%s vs itself" % faction)
		for other: StringName in others:
			assert_false(Factions.is_hostile(faction, other), "%s vs %s" % [faction, other])
			assert_false(Factions.is_hostile(other, faction), "%s vs %s" % [other, faction])
	assert_false(Factions.is_hostile(Factions.NEUTRAL, Factions.NEUTRAL))


func test_string_ids_work_like_string_names() -> void:
	assert_true(Factions.is_hostile("earth_alliance", "raiders"))
	assert_eq(Factions.relation("neutral", "raiders"), Factions.Relation.NEUTRAL)


func test_is_known() -> void:
	for faction: StringName in ALL_KNOWN:
		assert_true(Factions.is_known(faction), str(faction))
	assert_false(Factions.is_known(&"pirates"))
	assert_false(Factions.is_known(&""))


func test_hud_colors_follow_the_maintainer_answer() -> void:
	assert_eq(Factions.hud_color(Factions.Relation.HOSTILE), Color(1.0, 0.35, 0.25), "hostile red")
	assert_eq(Factions.hud_color(Factions.Relation.NEUTRAL), Color(1.0, 0.85, 0.25), "neutral/unknown yellow")
	assert_eq(Factions.hud_color(Factions.Relation.FRIENDLY), Color(0.45, 0.7, 1.0), "friendly blue")


func test_hud_colors_are_distinct_and_line_work_stays_green() -> void:
	var colors: Array[Color] = []
	for rel: Factions.Relation in Factions.Relation.values():
		colors.append(Factions.hud_color(rel))
	assert_eq(colors.size(), 3)
	assert_ne(colors[0], colors[1])
	assert_ne(colors[0], colors[2])
	assert_ne(colors[1], colors[2])
	assert_eq(Factions.HUD_LINE_COLOR, Color(0.55, 1.0, 0.6))
	for color: Color in colors:
		assert_ne(color, Factions.HUD_LINE_COLOR, "faction colours never reuse the HUD line green")


func test_hud_color_of_an_unlisted_relation_is_the_neutral_yellow() -> void:
	assert_eq(Factions.hud_color((-1) as Factions.Relation), Factions.NEUTRAL_COLOR)
	assert_eq(Factions.hud_color(99 as Factions.Relation), Factions.NEUTRAL_COLOR)


func test_hud_color_through_the_relation_query() -> void:
	# What the HUD does for a raider seen from a Starfury, a buoy and an unknown contact.
	var own: StringName = Factions.EARTH_ALLIANCE
	assert_eq(Factions.hud_color(Factions.relation(own, Factions.RAIDERS)), Factions.HOSTILE_COLOR)
	assert_eq(Factions.hud_color(Factions.relation(own, Factions.NEUTRAL)), Factions.NEUTRAL_COLOR)
	assert_eq(Factions.hud_color(Factions.relation(own, &"pirates")), Factions.NEUTRAL_COLOR)
	assert_eq(Factions.hud_color(Factions.relation(own, own)), Factions.FRIENDLY_COLOR)
