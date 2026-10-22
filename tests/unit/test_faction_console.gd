extends GutTest
## FactionConsole (M3-T02, AC2, architecture §16.4): provider `factions` and the `relation` command, on a registry of their
## own so no node or autoload is involved. The registration through `HitResolver` is in test_friendly_fire.

var registry: ConsoleRegistry
var settings_backup: bool = false


func before_each() -> void:
	Factions.reset()
	settings_backup = bool(Settings.get_value(&"friendly_fire"))
	registry = ConsoleRegistry.new()
	registry.register_provider(&"factions", FactionConsole.provider())
	registry.register_command(FactionConsole.command(), FactionConsole.run)


func after_each() -> void:
	Factions.reset()
	Settings.set_value(&"friendly_fire", settings_backup)


func _run(line: String) -> ConsoleResult:
	var results: Array[ConsoleResult] = registry.execute(line)
	assert_eq(results.size(), 1, "one statement: " + line)
	return results[0]


# --- the provider ------------------------------------------------------------------------------------------------


func test_the_provider_lists_ids_and_listed_pairs() -> void:
	assert_eq(registry.format_path("factions.ids"), "factions.ids = [earth_alliance, raiders, neutral]")
	assert_eq(registry.format_path("factions.relations"), "factions.relations = [earth_alliance raiders hostile]")


func test_the_provider_follows_session_changes() -> void:
	Factions.table().set_relation(&"neutral", &"raiders", Factions.Relation.FRIENDLY)
	assert_eq(registry.format_path("factions.relations"),
			"factions.relations = [earth_alliance raiders hostile, neutral raiders friendly]")


func test_the_provider_mirrors_the_friendly_fire_setting() -> void:
	Settings.set_value(&"friendly_fire", false)
	assert_eq(registry.format_path("factions.friendly_fire"), "factions.friendly_fire = false")
	Settings.set_value(&"friendly_fire", true)
	assert_eq(registry.format_path("factions.friendly_fire"), "factions.friendly_fire = true")


func test_the_provider_is_read_only() -> void:
	var provider: ConsoleStateProvider = registry.get_provider(&"factions")
	for key: StringName in [&"ids", &"relations", &"friendly_fire"]:
		assert_true(provider.has_key(key), str(key))
		assert_false(provider.is_writable(key), "%s is read-only; settings.friendly_fire is the writable one" % key)
	assert_false(provider.has_key(&"table"))


# --- relation ----------------------------------------------------------------------------------------------------


func test_relation_prints_a_pair() -> void:
	var result: ConsoleResult = _run("relation earth_alliance raiders")
	assert_true(result.ok, result.error)
	assert_eq(result.lines, PackedStringArray(["earth_alliance vs raiders: hostile"]))
	assert_eq(_run("relation raiders earth_alliance").lines, PackedStringArray(["raiders vs earth_alliance: hostile"]))
	assert_eq(_run("relation earth_alliance neutral").lines, PackedStringArray(["earth_alliance vs neutral: neutral"]))
	assert_eq(_run("relation raiders raiders").lines, PackedStringArray(["raiders vs raiders: friendly"]))


func test_relation_sets_a_pair_for_the_session() -> void:
	var result: ConsoleResult = _run("relation earth_alliance raiders neutral")
	assert_true(result.ok, result.error)
	assert_eq(result.lines, PackedStringArray(["earth_alliance vs raiders: hostile -> neutral (this session)"]))
	assert_eq(Factions.relation(Factions.EARTH_ALLIANCE, Factions.RAIDERS), Factions.Relation.NEUTRAL)
	assert_eq(Factions.relation(Factions.RAIDERS, Factions.EARTH_ALLIANCE), Factions.Relation.NEUTRAL)
	assert_eq(registry.format_path("factions.relations"), "factions.relations = [earth_alliance raiders neutral]")
	assert_eq(_run("relation raiders earth_alliance").lines, PackedStringArray(["raiders vs earth_alliance: neutral"]))


func test_relation_can_make_new_friends_and_enemies() -> void:
	assert_true(_run("relation neutral raiders hostile").ok)
	assert_true(Factions.is_hostile(Factions.NEUTRAL, Factions.RAIDERS))
	assert_true(_run("relation earth_alliance raiders friendly").ok)
	assert_eq(Factions.relation(Factions.EARTH_ALLIANCE, Factions.RAIDERS), Factions.Relation.FRIENDLY)
	assert_eq(Factions.hud_color(Factions.relation(Factions.EARTH_ALLIANCE, Factions.RAIDERS)), Factions.FRIENDLY_COLOR)


func test_relation_is_case_insensitive() -> void:
	assert_true(_run("relation Earth_Alliance RAIDERS Neutral").ok)
	assert_eq(Factions.relation(Factions.EARTH_ALLIANCE, Factions.RAIDERS), Factions.Relation.NEUTRAL)


func test_relation_reset_reloads_the_file() -> void:
	_run("relation earth_alliance raiders friendly")
	var result: ConsoleResult = _run("relation reset")
	assert_true(result.ok, result.error)
	assert_string_contains(result.lines[0], "res://data/factions.json")
	assert_true(Factions.is_hostile(Factions.EARTH_ALLIANCE, Factions.RAIDERS))
	assert_eq(registry.format_path("factions.relations"), "factions.relations = [earth_alliance raiders hostile]")


func test_relation_never_writes_the_data_file() -> void:
	var before: String = FileAccess.get_file_as_string(Factions.TABLE_PATH)
	_run("relation earth_alliance raiders friendly")
	_run("relation reset")
	assert_eq(FileAccess.get_file_as_string(Factions.TABLE_PATH), before)


func test_relation_rejects_bad_arguments() -> void:
	var cases: Dictionary = {
		"relation": "missing <a>",
		"relation earth_alliance": "relation needs a second faction",
		"relation pirates raiders": "unknown faction 'pirates'",
		"relation earth_alliance pirates": "unknown faction 'pirates'",
		"relation earth_alliance raiders enemy": "enemy",
		"relation earth_alliance raiders hostile extra": "too many arguments",
		"relation earth_alliance earth_alliance hostile": "always friendly to itself",
	}
	for line: String in cases:
		var result: ConsoleResult = _run(line)
		assert_false(result.ok, "should fail: " + line)
		assert_string_contains(result.error, cases[line])
	assert_true(Factions.is_hostile(Factions.EARTH_ALLIANCE, Factions.RAIDERS), "nothing was changed")
	assert_eq(Factions.relation(Factions.EARTH_ALLIANCE, Factions.EARTH_ALLIANCE), Factions.Relation.FRIENDLY)


func test_an_unknown_faction_gets_a_suggestion() -> void:
	var result: ConsoleResult = _run("relation raiderz earth_alliance")
	assert_false(result.ok)
	assert_string_contains(result.error, "known: earth_alliance, raiders, neutral")
	assert_string_contains(result.error, "did you mean raiders?")


func test_reset_is_not_a_faction() -> void:
	var result: ConsoleResult = _run("relation reset raiders")
	assert_false(result.ok)
	assert_string_contains(result.error, "unknown faction 'reset'")


func test_the_command_is_documented_and_completes_faction_ids() -> void:
	var command: ConsoleCommand = registry.get_command(&"relation")
	assert_eq(command.usage(), "relation <a> [b] [friendly|neutral|hostile]")
	var completer := ConsoleCompleter.new(registry)
	var offered: PackedStringArray = completer.complete("relation ra")
	assert_eq(offered, PackedStringArray(["relation raiders "]))
	assert_eq(completer.complete("relation re"), PackedStringArray(["relation reset "]))
	assert_eq(completer.complete("relation raiders earth_alliance h"),
			PackedStringArray(["relation raiders earth_alliance hostile "]))
