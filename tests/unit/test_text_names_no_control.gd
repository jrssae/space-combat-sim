extends GutTest
## The guard on mission text (M8-T33, the maintainer: a line always shows the control an action is mapped to now, never the
## default): no dialog line, mission script string or scenario text may name a control itself. A control is written as an
## action placeholder, `{action:<name>}` (`ControlText`), and every placeholder must name an action of the input map.
##
## A new mission is covered by being in `data/dialog/`, `data/missions/` or `data/scenarios/`. A new way to name a control goes
## into `CONTROL_NAMES`; a new false alarm is prose to rewrite, not an exception to add.

const DIALOG_DIR: String = "res://data/dialog/"
const MISSION_DIR: String = "res://data/missions/"
const SCENARIO_DIR: String = "res://data/scenarios/"
## Scenario keys whose values are shown to the player.
const SCENARIO_TEXT_KEYS: Array[String] = ["title", "briefing", "text", "description"]
## What names a control, each a regular expression over a text's prose (its placeholders cut out) and what it catches.
const CONTROL_NAMES: Array[Dictionary] = [
	{"what": "a face button by its letter (X, Y, B)", "pattern": "\\b[XYB]\\b"},
	{"what": "the A button", "pattern": "(?i:\\b(press|tap|hold|hit|push|use))\\s+(?i:the\\s+)?A\\b"},
	{"what": "a button", "pattern": "(?i)\\bbuttons?\\b"},
	{"what": "a key by its letter", "pattern": "(?i)\\b[a-z0-9]\\s+key\\b"},
	{"what": "a shoulder button or trigger", "pattern": "\\b(LT|RT|LB|RB|L1|L2|R1|R2)\\b|(?i:\\b(left|right)\\s+(trigger|bumper|shoulder)\\b)"},
	{"what": "a stick or the D-pad", "pattern": "(?i)\\b((left|right|l|r)\\s+stick|thumbstick|d-?pad)\\b"},
	{"what": "Start, Select or Back on the pad", "pattern": "(?i:\\b(press|tap|hold|hit))\\s+(Start|Select|Back)\\b"},
	{"what": "a keyboard key after a verb", "pattern": "(?i)\\b(press|tap|hold|hit|push|use)\\s+(the\\s+)?(shift|ctrl|alt|tab|enter|return|escape|esc|space|backspace)\\b"},
	{"what": "a keyboard key by name", "pattern": "\\b(Shift|SHIFT|CTRL|Ctrl|ALT|TAB|ENTER|ESC|Esc|SPACE)\\b|(?i:\\b(space ?bar|backspace|caps ?lock|(shift|tab|enter|return|escape|control|alt) key)\\b)"},
	{"what": "a function key", "pattern": "\\bF([1-9]|1[0-2])\\b"},
	{"what": "the mouse", "pattern": "(?i)\\b(mouse|LMB|RMB|MMB|(left|right|middle)[- ]click|scroll wheel)\\b"},
	{"what": "the keyboard's movement keys", "pattern": "\\bWASD\\b"},
]
## Texts the table must catch, and prose it must leave alone (the guard's own check).
const CAUGHT: Array[String] = ["Tap X. Auto-track the buoy.", "Your X control.", "Hold B and pick NAV ONE.", "Press A to fire.",
		"Hold the A button.", "Press the fire button.", "Pull the left trigger.", "Squeeze RT.", "Push the left stick.",
		"Use the D-pad.", "Press Start.", "Hold Shift.", "Tap the space bar.", "Press F5.", "Mouse 4 tracks.", "Click RMB.",
		"Fly with WASD.", "Hit the Tab key.", "The W key strafes.", "Shift tracks your target.", "Hold space to brake."]
const LEFT_ALONE: Array[String] = ["A tap tracks your target.", "A jumpgate offers a jump.", "Babylon 5, B5 for short.",
		"Tap {action:autotrack}. Auto-track the buoy.", "Hold {action:target_cycle,target_next} and pick NAV ONE.",
		"Start your run when ready.", "NAV ONE is your start.", "Control did not plan that.", "Alpha One, {instructor}.",
		"Take a position off the bow.", "Hold here and brake.", "Fire both main pods.", "The key is your braking point.",
		"Enter the bay on Control's word.", "The carrier may escape through the gate.", "Babylon Control has the squadron.",
		"Hold a steady course.", "Use a slow approach."]


# Every `{what, pattern}` of the table that `text`'s prose matches: the "what" of each.
func _named(text: String) -> PackedStringArray:
	var prose: String = ControlText.prose(text)
	var found := PackedStringArray()
	for entry: Dictionary in CONTROL_NAMES:
		var regex := RegEx.new()
		assert_eq(regex.compile(String(entry["pattern"])), OK, "the pattern for %s compiles" % entry["what"])
		if regex.search(prose) != null:
			found.append(String(entry["what"]))
	return found


func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _files(dir: String, extension: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() == extension:
			out.append(dir + file)
	return out


# Every player-facing text of the game's missions: `{where, text}`.
func _texts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for path: String in _files(DIALOG_DIR, "json"):
		var data: Variant = _json(path)
		for line: Variant in (data as Dictionary).get("lines", []) if data is Dictionary else []:
			out.append({"where": "%s line %s" % [path.get_file(), line["id"]], "text": String(line["text"])})
	for path: String in _files(SCENARIO_DIR, "json"):
		_collect(_json(path), path.get_file(), out)
	for path: String in _files(MISSION_DIR, "gd"):
		var source: String = FileAccess.get_file_as_string(path)
		var literal := RegEx.new()
		literal.compile("\"((?:[^\"\\\\\\n]|\\\\.)*)\"")
		for line: String in source.split("\n"):
			if line.strip_edges().begins_with("#"):
				continue  # a comment talks to the maintainer, not to the player
			for found: RegExMatch in literal.search_all(line):
				out.append({"where": "%s string" % path.get_file(), "text": found.get_string(1)})
	return out


func _collect(node: Variant, where: String, out: Array[Dictionary]) -> void:
	if node is Dictionary:
		for key: Variant in node:
			if node[key] is String and SCENARIO_TEXT_KEYS.has(String(key)):
				out.append({"where": "%s %s" % [where, key], "text": String(node[key])})
			else:
				_collect(node[key], where, out)
	elif node is Array:
		for item: Variant in node:
			_collect(item, where, out)


func test_the_table_catches_a_named_control_and_leaves_prose_alone() -> void:
	for text: String in CAUGHT:
		assert_false(_named(text).is_empty(), "caught: %s" % text)
	for text: String in LEFT_ALONE:
		assert_eq(_named(text), PackedStringArray(), "left alone: %s" % text)


func test_no_mission_text_names_a_control_outside_a_placeholder() -> void:
	var texts: Array[Dictionary] = _texts()
	assert_gt(texts.size(), 100, "the dialog files, the scenarios and the mission scripts were read")
	for entry: Dictionary in texts:
		var named: PackedStringArray = _named(String(entry["text"]))
		assert_eq(named, PackedStringArray(), "%s names %s: write {action:<name>} instead (%s)" % [entry["where"],
				", ".join(named), entry["text"]])


func test_every_placeholder_names_an_action_of_the_input_map() -> void:
	ControlProfiles.store.default_profile().apply_to_input_map()
	var seen: int = 0
	for entry: Dictionary in _texts():
		for actions: PackedStringArray in ControlText.placeholders(String(entry["text"])):
			seen += 1
			assert_false(actions.is_empty(), "%s: an empty placeholder" % entry["where"])
			for action: String in actions:
				assert_true(InputMap.has_action(action), "%s: no action '%s'" % [entry["where"], action])
			assert_ne(ControlText.name_of(actions, InputSource.Device.PAD), ControlText.UNBOUND, "%s: bound by default" % entry["where"])
	assert_gt(seen, 5, "the tutorial's lines use placeholders")
