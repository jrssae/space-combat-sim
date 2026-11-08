extends GutTest
## M4-T44 (F10): `info.md` lists every console command and state provider (CLAUDE.md asks for it). The main scene registers
## them; the test reads the file's tables and the registry and names any command or provider that one has and the other has
## not.

const INFO_PATH: String = "res://info.md"

var main: Main


func before_each() -> void:
	get_tree().paused = false
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.SANDBOX_PATH  # AI ships, so the AI and flight batch register theirs
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame


func test_every_registered_command_is_in_info_md_and_back() -> void:
	var listed: PackedStringArray = _first_column(false)
	var registered: PackedStringArray = _names(DebugConsole.registry.command_names())
	assert_gt(listed.size(), 40, "info.md's command tables were read")
	assert_eq(_missing(registered, listed), PackedStringArray(), "registered commands missing from info.md")
	assert_eq(_missing(listed, registered), PackedStringArray(), "info.md commands the game does not register")


func test_every_state_provider_is_in_info_md_and_back() -> void:
	var listed: PackedStringArray = _first_column(true)
	var registered: PackedStringArray = _names(DebugConsole.registry.provider_names())
	assert_gt(listed.size(), 20, "info.md's provider table was read")
	assert_eq(_missing(registered, listed), PackedStringArray(), "registered providers missing from info.md")
	assert_eq(_missing(listed, registered), PackedStringArray(), "info.md providers the game does not register")


# The names in the first column of info.md's tables: the provider table (under "State providers") or every command table
# before it.
func _first_column(providers: bool) -> PackedStringArray:
	var out := PackedStringArray()
	var in_providers: bool = false
	var cell := RegEx.create_from_string("^\\| `([^`]+)` \\|")
	for line: String in FileAccess.get_file_as_string(INFO_PATH).split("\n"):
		if line.begins_with("## "):
			in_providers = line == "## State providers"
		if in_providers != providers:
			continue
		var m: RegExMatch = cell.search(line)
		if m != null:
			out.append(m.get_string(1))
	return out


static func _names(names: Array[StringName]) -> PackedStringArray:
	var out := PackedStringArray()
	for n: StringName in names:
		out.append(String(n))
	return out


# Those of `a` not in `b`, sorted.
static func _missing(a: PackedStringArray, b: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for n: String in a:
		if not b.has(n):
			out.append(n)
	out.sort()
	return out
