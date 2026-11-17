class_name StationAirlock
extends Node
## The main docking bay's inner doors in play (M7-T25): a docking ship asks them open on its way in, flies through into the black
## void behind them and lets go once it lies wholly past their plane; they shut and the traffic takes the ship from the world.
## Undocking is the same backwards. Steps `AirlockDoors` each tick (the traffic reads it) and slides the leaves each frame. Timing
## from `data/station/airlock.json`. Console: command and provider `airlock`.

const NODE_NAME: StringName = &"StationAirlock"
const DATA_PATH: String = "res://data/station/airlock.json"
const PROVIDER: StringName = &"airlock"
const ACTIONS: Array[StringName] = [&"status", &"open", &"shut", &"auto"]

var doors := AirlockDoors.new()
var leaves: AirlockLeaves = null
## How far each leaf slides to open, metres (the manifest's).
var open_m: float = 21.0
## A docking ship asks once its nose is this near the doors' plane, metres.
var ask_ahead_m: float = 400.0
## A hull counts as past the doors' plane once its near end is this far beyond it, metres.
var clear_m: float = 3.0
## The doors' plane on the bay's axis, and the axis pointing into the bay, in the station's frame.
var doors_at: Vector3 = Vector3.ZERO
var axis: Vector3 = Vector3.BACK
## The black void behind the doors (M7-T62): how deep it runs past their plane to its back wall, and the radius about the axis
## that holds its cross-section (the drum turns it, so a circle, not its box), metres.
var void_depth_m: float = 0.0
var void_radius_m: float = 0.0


## The doors of `station`'s main docking bay, or null when its hardpoints have none.
static func make(station: Station) -> StationAirlock:
	var bay: Dictionary = station.hardpoints.main_docking_bay if station.hardpoints != null else {}
	if not bay.has("main_docking_bay_doors") or not bay.has("main_docking_bay_mouth"):
		return null
	var made := StationAirlock.new()
	made.name = String(NODE_NAME)
	made.doors_at = (bay["main_docking_bay_doors"] as Vector3) + station.drum_origin
	var mouth: Vector3 = (bay["main_docking_bay_mouth"] as Vector3) + station.drum_origin
	made.axis = (made.doors_at - mouth).normalized()
	made.open_m = float(bay.get("main_docking_bay_doors_open_m", made.open_m))
	if bay.has("main_docking_bay_airlock"):
		made.void_depth_m = made.depth_of((bay["main_docking_bay_airlock"] as Vector3) + station.drum_origin)
	made.void_radius_m = (bay.get("main_docking_bay_void_half_m", Vector2.ZERO) as Vector2).length()
	made.leaves = AirlockLeaves.find(station.drum_piece)
	return made


## How far a point in the station's frame lies past the doors' plane, into the bay (negative ahead of it).
func depth_of(point: Vector3) -> float:
	return (point - doors_at).dot(axis)


## Whether a point in the station's frame lies in the black void behind the doors (M7-T62): a ship whose origin is there is inside
## the station, unavailable to everyone outside. The one test of that boundary.
func holds(point: Vector3) -> bool:
	var depth: float = depth_of(point)
	if depth <= 0.0 or depth > void_depth_m:
		return false
	return (point - doors_at - axis * depth).length() <= void_radius_m


## A hull's reach ahead of its origin (`x`) and behind it (`y`) along its nose, metres: from its collision shapes (nodes or, on a
## lean ship, shape owners: both are the body's shape owners).
static func hull_reach(body: CollisionObject3D) -> Vector2:
	var fore: float = 0.0
	var aft: float = 0.0
	for owner_id: int in body.get_shape_owners():
		var t: Transform3D = body.shape_owner_get_transform(owner_id)
		for k: int in body.shape_owner_get_shape_count(owner_id):
			var shape: Shape3D = body.shape_owner_get_shape(owner_id, k)
			var half := Vector3.ZERO
			if shape is BoxShape3D:
				half = 0.5 * (shape as BoxShape3D).size
			elif shape is CapsuleShape3D:
				half = Vector3((shape as CapsuleShape3D).radius, 0.5 * (shape as CapsuleShape3D).height, (shape as CapsuleShape3D).radius)
			elif shape is SphereShape3D:
				half = Vector3.ONE * (shape as SphereShape3D).radius
			else:
				continue
			var reach: float = absf(t.basis.x.z) * half.x + absf(t.basis.y.z) * half.y + absf(t.basis.z.z) * half.z
			fore = maxf(fore, -(t.origin.z - reach))  # the nose is -Z
			aft = maxf(aft, t.origin.z + reach)
	return Vector2(fore, aft)


func _ready() -> void:
	_load_data()
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _physics_process(delta: float) -> void:
	doors.step(delta)


func _process(_delta: float) -> void:
	if leaves != null:
		leaves.set_offset(smoothstep(0.0, 1.0, doors.fraction) * open_m)


func _load_data() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
	if not (parsed is Dictionary):
		push_warning("StationAirlock: %s is missing or not a JSON object; default timing" % DATA_PATH)
		return
	var data: Dictionary = parsed
	doors.open_s = maxf(float(data.get("open_s", doors.open_s)), 0.0)
	doors.close_s = maxf(float(data.get("close_s", doors.close_s)), 0.0)
	ask_ahead_m = maxf(float(data.get("ask_ahead_m", ask_ahead_m)), 0.0)
	clear_m = maxf(float(data.get("clear_m", clear_m)), 0.0)


# --- console ----------------------------------------------------------------------------------------------------


func _register_console() -> void:
	var registry: ConsoleRegistry = DebugConsole.registry
	registry.register_provider(PROVIDER, ConsoleVars.new({
		&"state": {"get": doors.state_name, "doc": "The main docking bay's inner doors: open, shut, opening or closing"},
		&"open": {"get": func() -> float: return doors.fraction, "doc": "How far open they stand, 0 to 1"},
		&"asking": {"get": doors.asking, "doc": "Ships asking them open"},
		&"mode": {"get": func() -> String: return String(AirlockDoors.Mode.find_key(doors.mode)).to_lower(),
				"doc": "auto (the traffic opens them), or held open or shut from the console"},
		&"leaves": {"get": func() -> int: return leaves.count() if leaves != null else 0, "doc": "Door leaves found on the drum"},
	}), self)
	registry.register_command(ConsoleCommand.new(&"airlock",
			"The main docking bay's inner doors: status, open (hold them open), shut (hold them shut), auto (the traffic opens them)",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"status")] as Array[ConsoleArg]), _cmd_airlock, self)


func _cmd_airlock(args: Dictionary) -> ConsoleResult:
	match StringName(args[&"action"]):
		&"open":
			doors.mode = AirlockDoors.Mode.OPEN
		&"shut":
			doors.mode = AirlockDoors.Mode.SHUT
		&"auto":
			doors.mode = AirlockDoors.Mode.AUTO
	return ConsoleResult.line("doors %s (%.0f%% open), %d asking, mode %s" % [doors.state_name(), 100.0 * doors.fraction, doors.asking(),
			String(AirlockDoors.Mode.find_key(doors.mode)).to_lower()])
