class_name StationCommands
extends Node
## Babylon 5's commands (M8-T34, maintainer 2026-11-19): with the station selected as the target (an ally), the comms menu shows
## these instead of the wing orders. They go to the station, any pilot may give them, and Control answers each on the comms
## panel. Main's child; the work itself is the station's own systems':
##
## - **Launch wing** (a ring of Alpha, Beta, Delta, Zeta, All): `LaunchDirector.launch_wing`; a wing still out or in the bay says so.
## - **Recall fighters**: `DockingDirector.recall_all`, every fighter of the station's, the player's wingmen too, docks and stays.
## - **Defense grid** on/off: `StationGrid.set_on` (a core flag: off, no gun or interceptor fires).
## - **Fire support** on/off: covering fire round the player's ship, `StationGrid.set_cover` (the core's pick takes hostiles within
##   `cover_radius_m` of the player first, nearest the player first, latched or not). A toggle; it follows the player's ship.
## - **Shelter civilians** on/off: `StationTraffic.set_shelter`.
## - **Sitrep**: the station's damaged sections, the wings out, raiders near it and the grid's state.
##
## Console: command `stationcmd`, provider `station_cmd`.

const DATA_PATH: String = "res://data/station/commands.json"
const PROVIDER: StringName = &"station_cmd"
const SPEAKER: StringName = &"control"
## What a comms entry's payload starts with when it is a station command; the rest is `command[:arg]`.
const PAYLOAD_PREFIX: String = "station:"
const COMMANDS: Array[StringName] = [&"launch", &"recall", &"grid", &"support", &"shelter", &"sitrep"]
const LAUNCH_ALL: String = "all"

var main: Main = null
var cover_radius_m: float = 2000.0
var raider_scan_km: float = 30.0
## Control's answers by key (`data/station/commands.json`).
var lines: Dictionary = {}
## Covering fire asked for and not yet ended.
var support_on: bool = false
## Commands carried out, and Control's last answer (for the console and tests).
var given: int = 0
var last_line: String = ""
## Control's answers when no mission runs: its own queue, shown by its own panel.
var queue: DialogQueue = DialogQueue.new()

var _book: DialogBook = DialogBook.new()
var _panel: CommsPanel = null


## The comms menu's page of station commands, given the grid's, covering fire's and the shelter's state now.
static func page(grid_on: bool, covering: bool, sheltering: bool) -> Array[Dictionary]:
	var wings: Array[Dictionary] = []
	for wing: String in LaunchDirector.WINGS:
		wings.append({"label": wing.to_upper(), "payload": "%slaunch:%s" % [PAYLOAD_PREFIX, wing]})
	wings.append({"label": LAUNCH_ALL.to_upper(), "sub": "every wing", "payload": "%slaunch:%s" % [PAYLOAD_PREFIX, LAUNCH_ALL]})
	return [
		{"label": "LAUNCH WING", "sub": "", "page": {"title": "LAUNCH WING", "entries": wings}},
		{"label": "RECALL", "sub": "all fighters", "payload": PAYLOAD_PREFIX + "recall"},
		{"label": "DEFENSE GRID", "sub": "turn off" if grid_on else "turn on", "payload": PAYLOAD_PREFIX + "grid"},
		{"label": "FIRE SUPPORT", "sub": "end" if covering else "cover me", "payload": PAYLOAD_PREFIX + "support"},
		{"label": "SHELTER", "sub": "release civilians" if sheltering else "civilians", "payload": PAYLOAD_PREFIX + "shelter"},
		{"label": "SITREP", "sub": "", "payload": PAYLOAD_PREFIX + "sitrep"},
	]


## Whether `payload` (a comms entry's) is a station command.
static func is_payload(payload: Variant) -> bool:
	return payload is String and (payload as String).begins_with(PAYLOAD_PREFIX)


func _ready() -> void:
	name = "StationCommands"
	_load_data()
	var speakers: Dictionary = DialogBook._read_json(DialogBook.SPEAKERS_PATH)
	if String(speakers["error"]).is_empty():
		_book.add_speakers(speakers["data"], DialogBook.SPEAKERS_PATH)
	_panel = CommsPanel.new()
	add_child(_panel)
	_panel.bind(queue, _book, main.audio if main != null else null)
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _physics_process(delta: float) -> void:
	queue.tick(delta)
	# Covering fire follows the player's ship (a respawn is a new body); it ends with the pilot.
	if support_on and _grid() != null:
		var ship: Ship = main.ship if main.player_alive else null
		var body: int = ship.get_instance_id() if ship != null else 0
		if body != _grid().cover_body():
			_grid().set_cover(ship, cover_radius_m if ship != null else 0.0)


func station() -> Station:
	var s: Station = main.far_props.station if main != null and main.far_props != null else null
	return s if s != null and is_instance_valid(s) and s.targetable != null else null


## Whether the player has the station selected and it is an ally: the comms menu then shows `page`.
func targeted() -> bool:
	var s: Station = station()
	if s == null or main.ship == null or main.combatant == null or not main.ship.targeting.system.has_selection():
		return false
	return main.ship.targeting.system.selected_id() == s.targetable.get_instance_id() \
			and Factions.relation(main.combatant.faction, s.targetable.faction) == Factions.Relation.FRIENDLY


## The station commands page as things stand.
func current_page() -> Array[Dictionary]:
	var grid: StationGrid = _grid()
	return page(grid == null or grid.is_on(), support_on, main.traffic != null and main.traffic.sheltering)


## Carries out a comms entry's payload (`station:command[:arg]`). Returns `{ok, lines}`.
func run_payload(payload: String) -> Dictionary:
	var parts: PackedStringArray = payload.trim_prefix(PAYLOAD_PREFIX).split(":")
	return run(StringName(parts[0]), parts[1] if parts.size() > 1 else "")


## Carries out `command` (`COMMANDS`) with `arg` (a wing or `all` for launch; `on`/`off` for the toggles, else it flips) and has
## Control answer. Returns `{ok, lines}`: what Control said.
func run(command: StringName, arg: String = "") -> Dictionary:
	if station() == null:
		return {"ok": false, "lines": PackedStringArray(["no station in this scenario"])}
	var said := PackedStringArray()
	var ok: bool = true
	match command:
		&"launch":
			ok = _launch(arg.to_lower(), said)
		&"recall":
			var n: int = main.docking.recall_all() if main.docking != null else 0
			ok = n > 0
			said.append(_text("recall" if ok else "recall_none"))
		&"grid":
			var grid: StationGrid = _grid()
			ok = grid != null
			if ok:
				var on: bool = _flip(arg, grid.is_on())
				grid.set_on(on)
				said.append(_text("grid_on" if on else "grid_off"))
		&"support":
			ok = _support(_flip(arg, support_on), said)
		&"shelter":
			ok = main.traffic != null
			if ok:
				var on: bool = _flip(arg, main.traffic.sheltering)
				main.traffic.set_shelter(on)
				said.append(_text("shelter_on" if on else "shelter_off"))
		&"sitrep":
			_sitrep(said)
		_:
			return {"ok": false, "lines": PackedStringArray(["no station command '%s' (%s)" % [command, ", ".join(COMMANDS)]])}
	for text: String in said:
		_say(text)
	given += 1
	return {"ok": ok, "lines": said}


# Launch one wing, or every wing that is home; Control says which went or why not.
func _launch(wing: String, said: PackedStringArray) -> bool:
	var launches: LaunchDirector = main.launches
	if launches == null:
		said.append(_text("launch_refused", {"WING": wing.to_upper()}))
		return false
	if wing == LAUNCH_ALL:
		var went := PackedStringArray()
		for w: String in LaunchDirector.WINGS:
			if not launches.is_launching(w) and launches.wing_strength(w) == 0 and launches.launch_wing(w).is_empty():
				went.append(w.to_upper())
		if went.is_empty():
			said.append(_text("launch_none"))
			return false
		said.append(_text("launch_all", {"WINGS": ", ".join(went) + (" WINGS" if went.size() > 1 else " WING")}))
		return true
	if not LaunchDirector.WINGS.has(wing):
		said.append(_text("launch_refused", {"WING": wing.to_upper()}))
		return false
	if launches.is_launching(wing):
		said.append(_text("launch_bay", {"WING": wing.to_upper()}))
		return false
	if launches.wing_strength(wing) > 0:
		said.append(_text("launch_flying", {"WING": wing.to_upper()}))
		return false
	if not launches.launch_wing(wing).is_empty():
		said.append(_text("launch_refused", {"WING": wing.to_upper()}))
		return false
	said.append(_text("launch", {"WING": wing.to_upper()}))
	return true


func _support(on: bool, said: PackedStringArray) -> bool:
	var grid: StationGrid = _grid()
	if grid == null:
		return false
	if on and not grid.is_on():
		said.append(_text("support_grid_off"))
		return false
	support_on = on
	grid.set_cover(main.ship if on and main.player_alive else null, cover_radius_m if on else 0.0)
	said.append(_text("support_on" if on else "support_off"))
	return true


func _sitrep(said: PackedStringArray) -> void:
	var s: Station = station()
	var hurt := PackedStringArray()
	if s.sections != null:
		for i: int in s.sections.count():
			if not s.sections.is_whole(i):
				hurt.append("%s %d%%" % [str(s.sections.sections[i].get("name", "?")).to_upper(), roundi(s.sections.fraction(i) * 100.0)])
	said.append(_text("sitrep_sections", {"SECTIONS": ", ".join(hurt) if not hurt.is_empty() else "ALL SECTIONS INTACT"}))
	var out := PackedStringArray()
	if main.launches != null:
		for w: String in LaunchDirector.WINGS:
			var n: int = main.launches.wing_strength(w)
			if n > 0:
				out.append("%s %d" % [w.to_upper(), n])
	said.append(_text("sitrep_wings", {"WINGS": ", ".join(out) if not out.is_empty() else "NONE"}))
	said.append(_text("sitrep_raiders", {"RAIDERS": raiders_near(), "KM": roundi(raider_scan_km)}))
	var grid: StationGrid = _grid()
	var state: String = "OFFLINE"
	if grid != null and grid.is_on():
		state = "ONLINE, " + ("WEAPONS FREE" if not grid.free_sides().is_empty() else "HOLDING FIRE")
		if grid.health != null and grid.health.out_count() > 0:
			state += ", %d MOUNTS DOWN" % grid.health.out_count()
		if support_on:
			state += ", COVERING YOU"
	said.append(_text("sitrep_grid", {"GRID": state}))


## Hostile ships within `raider_scan_km` of the station.
func raiders_near() -> int:
	var s: Station = station()
	if s == null or main.ships == null:
		return 0
	var reach: float = raider_scan_km * 1000.0
	var n: int = 0
	for c: Combatant in main.ships.alive():
		if is_instance_valid(c.ship) and Factions.is_hostile(s.targetable.faction, c.targetable.faction_seen_by(s.targetable.faction)) \
				and c.ship.global_position.distance_to(s.global_position) <= reach:
			n += 1
	return n


func _grid() -> StationGrid:
	var s: Station = station()
	return s.grid if s != null and s.grid != null and is_instance_valid(s.grid) else null


# `on`/`off` set a toggle; anything else flips it from `now`.
static func _flip(arg: String, now: bool) -> bool:
	match arg.to_lower():
		"on":
			return true
		"off":
			return false
	return not now


func _text(key: String, fill: Dictionary = {}) -> String:
	return str(lines.get(key, key.to_upper())).format(fill)


# Control's line on the comms panel: the mission's when one runs (one panel, one queue), else this node's own.
func _say(text: String) -> void:
	last_line = text
	var line := DialogBook.Line.new(&"station_cmd", SPEAKER, text)
	var api: MissionApi = main.mission.api if main.mission != null else null
	if api != null:
		api.dialog.say(line)
	else:
		queue.say(line)


func _load_data() -> void:
	var read: Dictionary = DialogBook._read_json(DATA_PATH)
	if not String(read["error"]).is_empty() or not read["data"] is Dictionary:
		push_error("StationCommands: %s" % read["error"])
		return
	var data: Dictionary = read["data"]
	cover_radius_m = float(data.get("cover_radius_m", cover_radius_m))
	raider_scan_km = float(data.get("raider_scan_km", raider_scan_km))
	lines = data.get("lines", {})


# --- console -----------------------------------------------------------------------------------------------------


func _register_console() -> void:
	DebugConsole.registry.register_provider(PROVIDER, ConsoleVars.new({
		&"targeted": {"get": func() -> bool: return targeted(), "doc": "Babylon 5 is the selected target: the comms menu shows its commands"},
		&"support": {"get": func() -> bool: return support_on, "doc": "Covering fire round the player is on"},
		&"cover_radius_m": {"get": func() -> float: return cover_radius_m, "unit": "m", "doc": "How near the player covering fire reaches"},
		&"given": {"get": func() -> int: return given, "doc": "Station commands carried out"},
		&"last_line": {"get": func() -> String: return last_line if not last_line.is_empty() else "none", "doc": "Control's last answer"},
		&"raiders_near": {"get": func() -> int: return raiders_near(), "doc": "Hostile ships within the sitrep's reach of the station"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"stationcmd",
			"Babylon 5's commands (M8-T34), as the comms menu gives them with the station targeted: launch <alpha|beta|delta|zeta|all>, "
			+ "recall, grid [on|off], support [on|off], shelter [on|off], sitrep (a toggle without on/off flips)",
			[ConsoleArg.enum_required(&"command", COMMANDS), ConsoleArg.string_optional(&"arg", "")]), _cmd, self)


func _cmd(args: Dictionary) -> ConsoleResult:
	var command := StringName(args[&"command"])
	var arg: String = String(args[&"arg"]).strip_edges()
	if command == &"launch" and arg.is_empty():
		return ConsoleResult.failure("stationcmd launch <%s|all>" % "|".join(LaunchDirector.WINGS))
	var result: Dictionary = run(command, arg)
	var text: String = "; ".join(result["lines"] as PackedStringArray)
	return ConsoleResult.line("CONTROL: " + text) if bool(result["ok"]) else ConsoleResult.failure("CONTROL: " + text)
