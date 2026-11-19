class_name SquadronLaunch
extends RefCounted
## The squadron-launch cinematic (M8-T03, D81, AC2), run by `LaunchDirector`: the squadron's Starfuries (its AI flights and the
## player's own wingmen) launch from the wing's Cobra arm in M7-T08's sequence, and each one, once let go, flies a scripted way
## (`FormUpPath`: out, the flip, mains then retros) to its slot in a formation hanging off the drum; the player waits stowed in the
## station meanwhile, then launches alone from its door with the exterior shots, and its hand-off ends the cinematic: everyone
## formed up is let go at rest on its slot to its own pilot.
##
## Skipping (`skip_now`) lands in the end state the full run reaches: every squadron ship on its slot, the doors shut, and the
## player's launch skipped to its hand-off (M7-T08's skip). The slots are fixed in the station's frame when the launch starts, so
## the two runs agree whatever the drum's angle.

const DEFAULT_PATH: String = "res://data/launch/squadron_launch.json"

## The squadron ships launching, then the player's own launch, then over.
enum Stage { WINGS, PLAYER, DONE }

var director: LaunchDirector = null
var stage: Stage = Stage.WINGS
var wing: String = ""
var door: int = 1
## Read from the data file (`load_settings`).
var settings: Dictionary = {}
## The formation's anchor in the station's frame: x right, y away from the station, z aft (-z its heading).
var anchor: Transform3D = Transform3D.IDENTITY
## Each squadron ship's slot in the station's frame, by callsign.
var slots: Dictionary = {}
## The squadron's own launch (a `LaunchDirector.launches` entry) and its ships, by callsign.
var launch: Dictionary = {}
var ships: Dictionary = {}
## Seconds since the cinematic began.
var time_s: float = 0.0
## The skip came (`LaunchDirector.skip`): handled on the director's next tick.
var skip_asked: bool = false

var _forming: Dictionary = {}  # callsign -> {path: FormUpPath or null (on its slot), since: float, burn: Vector2}
var _avoid_deg: float = 90.0
var _player_stowed: Combatant = null


## The cinematic's settings from `path`: `{ok, flights, player_door, form_up: Dictionary, profile: LaunchProfile (its camera
## phases)}` or `{ok: false, error}`.
static func load_settings(path: String = DEFAULT_PATH) -> Dictionary:
	var made: Dictionary = LaunchProfile.load_file(path)
	if not bool(made["ok"]):
		return made
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var raw: Dictionary = data if data is Dictionary else {}
	var form: Dictionary = raw.get("form_up", {}) if raw.get("form_up") is Dictionary else {}
	var out: Dictionary = {"ok": true, "profile": made["profile"],
			"flights": clampi(int(raw.get("flights", 4)), 1, 4), "player_door": maxi(int(raw.get("player_door", 1)), 1), "form_up": {}}
	for key: String in ["angle_deg", "radius_m", "duration_s", "flip_s", "main_s", "retro_s"]:
		var defaults: Dictionary = {"angle_deg": 270.0, "radius_m": 650.0, "duration_s": 7.0, "flip_s": 2.5, "main_s": 3.0, "retro_s": 2.0}
		out["form_up"][key] = float(form.get(key, defaults[key]))
	return out


func _init(p_director: LaunchDirector, p_wing: String, p_door: int, p_settings: Dictionary) -> void:
	director = p_director
	wing = p_wing.to_lower()
	door = p_door
	settings = p_settings


## Starts the cinematic on the squadron's launch `p_launch` (already running): the formation and its slots, and the player stowed.
func begin(p_launch: Dictionary, s: Station) -> void:
	launch = p_launch
	ships = launch["ships"]
	var form: Dictionary = settings["form_up"]
	var seq: LaunchSequence = launch["seq"]
	var z: float = 0.0
	for bay: Dictionary in seq.bays:
		z += (bay["door"] as Vector3).z
	z = s.drum_origin.z + z / float(seq.bays.size())
	var a: float = deg_to_rad(float(form["angle_deg"]))
	var up := Vector3(cos(a), sin(a), 0.0)
	var back := Vector3.BACK
	anchor = Transform3D(Basis(up.cross(back), up, back),
			Vector3(s.drum_origin.x, s.drum_origin.y, z) + up * float(form["radius_m"]))
	var sectors: Array = s.hardpoints.launch_clearance.get("blocked_sectors_deg", [])
	if not sectors.is_empty():
		var a0: float = float(sectors[0][0])
		_avoid_deg = a0 + fposmod(float(sectors[0][1]) - a0, 360.0) * 0.5
	var ids: Array = ships.keys()
	for i: int in ids.size():
		slots[ids[i]] = Transform3D(anchor.basis, anchor * _slot_offset(ships[ids[i]], i))
	_player_stowed = director.main.combatant


## Whether the cinematic still has the player (stowed, or in its launch until the hand-off).
func running() -> bool:
	return stage != Stage.DONE


## The fighter `id` of the squadron's launch was let go with the station-frame `handoff` state: its way to its slot starts.
func take(id: String, handoff: Dictionary, s: Station) -> void:
	if not slots.has(id):
		return
	var form: Dictionary = settings["form_up"]
	_forming[id] = {"path": FormUpPath.create(handoff, slots[id], s.drum_origin, _avoid_deg, float(form["duration_s"]),
			float(form["flip_s"]), float(form["main_s"]), float(form["retro_s"])), "since": time_s, "burn": Vector2(-1.0, -1.0)}


## Moves the cinematic's clock on (before the launches step).
func advance(delta: float) -> void:
	time_s += delta


## Places every ship the cinematic holds this tick: the stowed player, and each squadron ship on its way or on its slot. Starts
## the player's launch once the squadron's own is over. After the launches step.
func place(s: Station) -> void:
	if stage == Stage.DONE:
		return
	if not director.main.player_alive:
		finish()
		return
	if _player_stowed != null:
		director.hold(_player_stowed.ship, {"transform": Transform3D(Basis.IDENTITY, s.drum_origin), "velocity": Vector3.ZERO,
				"angular": Vector3.ZERO}, s)
	for id: String in _forming:
		var c: Combatant = ships.get(id)
		if not director.is_flying(c):
			continue
		var entry: Dictionary = _forming[id]
		var path: FormUpPath = entry["path"]
		var state: Dictionary = path.state_at(time_s - float(entry["since"])) if path != null else _on_slot(id)
		director.hold(c.ship, state, s)
		var burn := Vector2(float(state.get("main", 0.0)), float(state.get("retro", 0.0)))
		if burn != entry["burn"]:
			entry["burn"] = burn
			var command := FlightCommand.new()
			command.main_left = burn.x
			command.main_right = burn.x
			command.retro_left = burn.y
			command.retro_right = burn.y
			c.ship.set_clamped_command(command)
	if stage == Stage.WINGS and not _launch_running():
		_start_player(false)


## The skip: every squadron ship on its slot, the squadron's launch over with its doors shut, the player's launch skipped to its
## hand-off. On the director's tick.
func skip_now(s: Station) -> void:
	skip_asked = false
	if stage != Stage.WINGS:
		return
	for id: String in ships:
		if director.is_flying(ships[id]):
			_forming[id] = {"path": null, "since": time_s, "burn": Vector2(-1.0, -1.0)}
	if _launch_running():
		director.end_launch(launch)
	_start_player(true)
	place(s)


## The player's hand-off: every squadron ship is let go on its slot, at rest against the station, to its own pilot.
func finish() -> void:
	if stage == Stage.DONE:
		return
	stage = Stage.DONE
	var s: Station = director.station()
	if _player_stowed != null and director.is_flying(_player_stowed):
		director.let_go(_player_stowed.ship)
	_player_stowed = null
	for id: String in ships:
		var c: Combatant = ships[id]
		if not director.is_flying(c) or not slots.has(id):
			continue
		if not _forming.has(id) and _launch_running():
			continue  # still on its rack: its own launch goes on
		if s != null:
			director.hold(c.ship, _on_slot(id), s)
		c.ship.set_clamped_command(null)
		director.let_go(c.ship)
	_forming.clear()


## One line for the console.
func describe() -> String:
	var formed: int = 0
	for id: String in _forming:
		var path: FormUpPath = _forming[id]["path"]
		if path == null or path.done(time_s - float(_forming[id]["since"])):
			formed += 1
	return "wing %s, %s, %.1f s: %d of %d on their slots" % [wing, ["squadron launching", "player launching", "done"][stage], time_s,
			formed, ships.size()]


func _on_slot(id: String) -> Dictionary:
	return {"transform": slots[id], "velocity": Vector3.ZERO, "angular": Vector3.ZERO}


func _launch_running() -> bool:
	for running_launch: Dictionary in director.launches:
		if is_same(running_launch, launch):
			return true
	return false


# The player goes alone from its door, filmed from outside; a skip jumps it to the hand-off.
func _start_player(skipped: bool) -> void:
	var stowed: Combatant = _player_stowed
	if stowed != null and director.is_flying(stowed):
		director.let_go(stowed.ship)
	_player_stowed = null
	var why: String = director.launch_player(wing, door, false, true)
	if not why.is_empty():
		_player_stowed = stowed  # back inside until the next tick's try
		return
	stage = Stage.PLAYER
	if skipped:
		director.skip()


# A ship's place in the formation, in the anchor's frame: the AI flights as their pilots keep them (each flight's lead on the
# squadron's lead, M8-T19), the player's own wingmen on the player's place, which is the next flight's.
func _slot_offset(c: Combatant, index: int) -> Vector3:
	var wd: WingDirector = director.main.wings
	var fallback := Vector3((float(index % 4) - 1.5) * 90.0, 0.0, floorf(float(index) / 4.0) * 90.0)
	if wd == null:
		return fallback
	var prefix: String = wing.to_upper()
	var lead: Combatant = wd.squadron_lead(prefix)
	var flights: Array[Wing] = wd.flights_of(prefix)
	var first: int = 0
	var last: int = 0
	for w: Wing in flights:
		if w.leader == lead and lead != null:
			first = w.flight
		if w.leader != null and not w.leader.is_player:
			last = maxi(last, w.flight)
	for w: Wing in wd.wings:
		var in_wing: bool = w.leader == c or w.members().has(c)
		if not in_wing:
			continue
		var spread := Formation.new(w.formation.shape, w.formation.spacing_m * wd.flight_rules.lead_spacing)
		var place: Vector3
		if w.leader != null and w.leader.is_player:
			place = spread.offset(last - first + 1) if lead != null else Vector3.ZERO
		elif w.flight > 0 and lead != null:
			place = spread.offset(w.flight - first)
		else:
			return fallback
		return place if w.leader == c else place + w.slot_offset(w.slot_of(c))
	return fallback
