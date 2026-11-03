extends GutTest
## The console command list (CLAUDE.md, M5-T24): `info.md` names every command and state provider the game registers, and
## nothing the game does not. The scenes that register different things are booted one after another (free flight, a mission,
## the instructor's route, the front end) and the console's registry is read after each; the autoloads' own entries are
## there throughout. A task that adds a command or a provider without listing it fails here.

const INFO_PATH: String = "res://info.md"
## The provider table follows this heading; everything before it holds the commands.
const PROVIDERS_HEADING: String = "## State providers"
## A row whose "Where" cell starts with this exists only in a benchmark run, which this test cannot boot: it need not be
## registered here. Everything else listed must be.
const UNBOOTABLE_WHERE_PREFIX: String = "benchmark"
const MISSION_PATH: String = "res://tests/fixtures/missions/test_mission.json"
const ROUTE_PATH: String = "res://data/scenarios/instructor_route.json"
const SETTLE_TICKS: int = 4

var _collected: bool = false
var _commands: Dictionary = {}  # StringName -> the context that registered it first
var _providers: Dictionary = {}


func before_each() -> void:
	get_tree().paused = false


func after_each() -> void:
	get_tree().paused = false


# --- Collecting what the game registers -------------------------------------------------------------------------


# Boots each scene once and keeps what the registry held while it was up; runs once for the whole script.
func _collect() -> void:
	if _collected:
		return
	_collected = true
	_note("autoloads")
	await _in_flight("free flight", ScenarioLoader.FREE_FLIGHT_PATH)
	await _in_flight("mission", MISSION_PATH)
	await _in_flight("instructor route", ROUTE_PATH)
	await _in_front_end()


func _in_flight(context: String, scenario: String) -> void:
	var main := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = scenario
	add_child(main)
	await wait_physics_frames(SETTLE_TICKS)
	_note(context)
	await _free(main)


func _in_front_end() -> void:
	var game := RecordingGame.new()  # takes the menu's requests; never in the tree, so it registers nothing
	autofree(game)
	var front := (load("res://src/frontend/front_end.tscn") as PackedScene).instantiate() as FrontEnd
	front.game = game
	add_child(front)
	await wait_process_frames(2)
	_note("front end")
	await _free(front)


func _free(scene: Node) -> void:
	remove_child(scene)
	scene.queue_free()
	await wait_process_frames(2)


func _note(context: String) -> void:
	for command_name: StringName in DebugConsole.registry.command_names():
		if not _commands.has(command_name):
			_commands[command_name] = context
	for provider_name: StringName in DebugConsole.registry.provider_names():
		if not _providers.has(provider_name):
			_providers[provider_name] = context


# --- Reading info.md ----------------------------------------------------------------------------------------------


# The table rows of `text` whose first cell is `code`: {"name": the code, "where": the last cell}.
static func _rows(text: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for line: String in text.split("\n"):
		var row: String = line.strip_edges()
		if not row.begins_with("|"):
			continue
		var cells: PackedStringArray = row.replace("\\|", "\u0001").split("|")  # an escaped bar stays inside its cell
		if cells.size() < 4:
			continue
		var first: String = cells[1].strip_edges()
		if first.length() < 3 or not first.begins_with("`") or not first.ends_with("`"):
			continue
		rows.append({"name": first.substr(1, first.length() - 2), "where": cells[cells.size() - 2].strip_edges()})
	return rows


func _info_text() -> String:
	var file: FileAccess = FileAccess.open(INFO_PATH, FileAccess.READ)
	assert_not_null(file, "info.md is at the repository root")
	return file.get_as_text() if file != null else ""


func _listed_commands() -> Array[Dictionary]:
	var text: String = _info_text()
	var split_at: int = text.find(PROVIDERS_HEADING)
	assert_true(split_at >= 0, "info.md has a '%s' section" % PROVIDERS_HEADING)
	return _rows(text.substr(0, split_at if split_at >= 0 else text.length()))


func _listed_providers() -> Array[Dictionary]:
	var text: String = _info_text()
	var split_at: int = text.find(PROVIDERS_HEADING)
	return _rows(text.substr(split_at)) if split_at >= 0 else []


static func _names_of(rows: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in rows:
		out.append(String(row["name"]))
	return out


# Registered names that no row lists.
func _unlisted(registered: Dictionary, rows: Array[Dictionary]) -> PackedStringArray:
	var listed: Array[String] = _names_of(rows)
	var out := PackedStringArray()
	for registered_name: StringName in registered.keys():
		if not listed.has(String(registered_name)):
			out.append("%s (%s)" % [registered_name, registered[registered_name]])
	out.sort()
	return out


# Listed names that no booted scene registers, leaving out the rows marked as unbootable.
func _unregistered(registered: Dictionary, rows: Array[Dictionary]) -> PackedStringArray:
	var out := PackedStringArray()
	for row: Dictionary in rows:
		if String(row["where"]).begins_with(UNBOOTABLE_WHERE_PREFIX):
			continue
		if not registered.has(StringName(row["name"])):
			out.append(String(row["name"]))
	out.sort()
	return out


# --- Tests --------------------------------------------------------------------------------------------------------


func test_the_scenes_register_commands_and_providers() -> void:
	await _collect()
	assert_has(_commands, &"help", "the console's own commands")
	assert_has(_commands, &"mission", "the mission fixture booted and started its runner")
	assert_has(_commands, &"menu", "the Game autoload")
	assert_has(_providers, &"route", "the instructor route booted")
	assert_has(_providers, &"ship", "flight booted")
	assert_gt(_commands.size(), 40, "every scene's commands were read")


func test_every_registered_command_is_listed() -> void:
	await _collect()
	var missing: PackedStringArray = _unlisted(_commands, _listed_commands())
	assert_true(missing.is_empty(), "add to info.md (Commands): %s" % ", ".join(missing))


func test_every_listed_command_is_registered() -> void:
	await _collect()
	var gone: PackedStringArray = _unregistered(_commands, _listed_commands())
	assert_true(gone.is_empty(), "in info.md but not registered by any booted scene: %s" % ", ".join(gone))


func test_every_registered_provider_is_listed() -> void:
	await _collect()
	var missing: PackedStringArray = _unlisted(_providers, _listed_providers())
	assert_true(missing.is_empty(), "add to info.md (State providers): %s" % ", ".join(missing))


func test_every_listed_provider_is_registered() -> void:
	await _collect()
	var gone: PackedStringArray = _unregistered(_providers, _listed_providers())
	assert_true(gone.is_empty(), "in info.md but not registered by any booted scene: %s" % ", ".join(gone))


func test_no_name_is_listed_twice() -> void:
	for rows: Array[Dictionary] in [_listed_commands(), _listed_providers()]:
		var seen: Array[String] = []
		for listed: String in _names_of(rows):
			assert_false(seen.has(listed), "'%s' is listed once" % listed)
			seen.append(listed)
		assert_gt(seen.size(), 0, "the table is not empty")


func test_the_row_parser_keeps_escaped_bars_inside_their_cell() -> void:
	var rows: Array[Dictionary] = _rows("| Command | Args | Where |\n|---|---|---|\n| `assist` | `[on\\|off]` | in flight |\n| plain | x | y |")
	assert_eq(rows.size(), 1, "the header and the plain row are not commands")
	assert_eq(rows[0]["name"], "assist")
	assert_eq(rows[0]["where"], "in flight")
