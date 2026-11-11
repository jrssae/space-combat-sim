class_name Jumpgate
extends Node3D
## The Earth Alliance jumpgate (M6-T14, D69): the generated `jumpgate` mesh, one Jolt box per truss and fin, a `Targetable` that
## locks on like a nav beacon and broadcasts to 1 000 km (so the AI and missions see it), and its `JumpVortex`.
##
## Its origin is the vortex's centre and it faces -Z: arrivals come out along -Z from the arrival point, departures line up at
## the departure point in front and fly in along +Z (`hardpoints.json`). The gate is at rest and has no hull: bolts pass it,
## ships bounce off its arms.
##
## Traffic: `request_arrival` opens the blue vortex and places the waiting ships once it is fully open (a group comes through
## one opening); `send_departure` watches a ship flying in, opens the orange vortex as it nears and hands it back through
## `on_through` once it crosses the vortex. The rules for who flies where are the callers' (missions, encounters, the player's
## jump); the gate only keeps the vortex in step with them. Spawned through `World` from a scenario's `jumpgate` prop.

const SCENE_PATH: String = "res://src/props/jumpgate.tscn"
const ASSET_ID: String = "jumpgate"
const ASSET_DIR: String = "res://assets/generated/jumpgate"
const HARDPOINTS_PATH: String = ASSET_DIR + "/hardpoints.json"
## A gate's beacon is heard 1 000 km out (D69; the wiki and the fan manual both say so), as the nav buoys are.
const BROADCAST_RANGE_M: float = 1.0e6
## Where the hardpoints are missing: the generator's values for 1 200 m arms.
const DEFAULT_RADIUS_M: float = 720.0
const DEFAULT_ARRIVAL: Vector3 = Vector3(0.0, 0.0, -72.0)
const DEFAULT_DEPARTURE: Vector3 = Vector3(0.0, 0.0, -1440.0)
const DEFAULT_TIP_M: float = 790.0
## A departing ship this close to the centre, in front, opens the vortex: from the departure point (1 440 m) a ship at the
## run-in speed reaches the plane after the 3.5 s the vortex takes to open.
const DEPARTURE_OPEN_M: float = 1600.0
## While a departing ship is on its way in, the vortex is kept open at least this much longer each tick.
const DEPARTURE_KEEP_S: float = 1.5
## Crossing the plane this far from the centre (a share of the vortex radius) still counts as going through.
const THROUGH_RADIUS: float = 1.1
## Ships come out of an arrival at this speed along -Z: clear of the plane in well under the 4 s it stays open.
const ARRIVAL_SPEED_MPS: float = 200.0

## Shown in the target readout; the console and missions find it by it.
@export var display_name: String = "JUMPGATE":
	set(value):
		display_name = value
		_sync_targetable()

var vortex: JumpVortex = null
var collision_body: StaticBody3D = null
var radius_m: float = DEFAULT_RADIUS_M
## Gate-local points and directions from the hardpoints.
var arrival_point: Vector3 = DEFAULT_ARRIVAL
var arrival_forward: Vector3 = Vector3.FORWARD
var departure_point: Vector3 = DEFAULT_DEPARTURE
var departure_forward: Vector3 = Vector3.BACK
## Ships placed through an arrival and handed back through a departure (tests, console).
var arrived: int = 0
var departed: int = 0

var _pending_arrivals: Array[Callable] = []
# One entry per departing ship: {body: Node3D, on_through: Callable, z: float (gate-local z last tick)}.
var _departures: Array[Dictionary] = []

static var _shared_loaded: bool = false
static var _shared_mesh: Mesh = null
static var _shared_data: Dictionary = {}

@onready var body: MeshInstance3D = $Body
@onready var targetable: Targetable = $Targetable


## A gate ready for `World.spawn()`.
static func create(p_display_name: String) -> Jumpgate:
	var gate := (load(SCENE_PATH) as PackedScene).instantiate() as Jumpgate
	gate.display_name = p_display_name
	gate.name = p_display_name.to_pascal_case().validate_node_name()
	return gate


func _init() -> void:
	add_to_group(WorldFrame.SHIFTABLE_GROUP)


func _ready() -> void:
	_load_shared()
	body.mesh = _shared_mesh
	_read_points(_shared_data)
	_build_collision(_shared_data)
	vortex = JumpVortex.new()
	vortex.name = "Vortex"
	vortex.setup(radius_m, _shared_data.get("vortex", {}) as Dictionary, _tips(_shared_data))
	add_child(vortex)
	_sync_targetable()


func _physics_process(_delta: float) -> void:
	_step_arrivals()
	_step_departures()


## Opens the arrival vortex (or joins the one opening) and calls `place` once it is fully open; `place` puts the ship at
## `arrival_transform` itself. An opening the other way is let finish first.
func request_arrival(place: Callable) -> void:
	_pending_arrivals.append(place)
	_step_arrivals()


## Watches `ship` flying in: the departure vortex opens as it nears and `on_through(ship)` runs once it crosses the vortex.
func send_departure(ship: Node3D, on_through: Callable) -> void:
	cancel_departure(ship)
	_departures.append({"body": ship, "on_through": on_through, "z": to_local(ship.global_position).z})


## Stops watching `ship` (it was destroyed, or its mission changed its mind).
func cancel_departure(ship: Node3D) -> void:
	for i: int in range(_departures.size() - 1, -1, -1):
		if _departures[i]["body"] == ship:
			_departures.remove_at(i)


func pending_arrivals() -> int:
	return _pending_arrivals.size()


func departing() -> int:
	return _departures.size()


## Where the `k`-th ship of an arrival comes out, World-local: the arrival point plus `offset` in the gate's frame (x right, y up,
## so a group comes out side by side), nose along the arrival direction.
func arrival_transform(offset: Vector3 = Vector3.ZERO) -> Transform3D:
	var forward: Vector3 = global_basis * arrival_forward
	return Transform3D(Basis.looking_at(forward, global_basis.y), global_transform * (arrival_point + offset))


## The arrival velocity, World frame.
func arrival_velocity() -> Vector3:
	return (global_basis * arrival_forward).normalized() * ARRIVAL_SPEED_MPS


## A ship's place in the gate's frame.
func local_of(world_point: Vector3) -> Vector3:
	return to_local(world_point)


## The way through for a departing AI ship, in universe positions: the departure point, the centre, then well past the plane.
func departure_route(world: WorldFrame, cruise_mps: float) -> Route:
	var route := Route.new()
	route.name = "%s DEPARTURE" % display_name
	route.pace = Route.PACE_NONE
	route.loop = false
	route.cruise_mps = cruise_mps
	for point: Vector3 in [departure_point, Vector3.ZERO, departure_forward.normalized() * radius_m * 2.0]:
		route.add(world.to_universe(global_transform * point))
	return route


func _step_arrivals() -> void:
	if _pending_arrivals.is_empty() or vortex == null:
		return
	if vortex.is_open_for(JumpVortex.Direction.ARRIVAL):
		var waiting: Array[Callable] = _pending_arrivals.duplicate()
		_pending_arrivals.clear()
		for place: Callable in waiting:
			if place.is_valid():
				place.call()
				arrived += 1
		return
	if vortex.open_in_s(JumpVortex.Direction.ARRIVAL) == INF:
		vortex.open(JumpVortex.Direction.ARRIVAL)  # refused while a departure runs: tried again next tick


func _step_departures() -> void:
	if _departures.is_empty() or vortex == null:
		return
	var limit: float = radius_m * THROUGH_RADIUS
	for i: int in range(_departures.size() - 1, -1, -1):
		var entry: Dictionary = _departures[i]
		var ship := entry["body"] as Node3D
		if not is_instance_valid(ship) or not ship.is_inside_tree() or not ship.is_visible_in_tree():
			_departures.remove_at(i)
			continue
		var local: Vector3 = to_local(ship.global_position)
		var was_z: float = entry["z"]
		entry["z"] = local.z
		var radial: float = Vector2(local.x, local.y).length()
		if was_z < 0.0 and local.z >= 0.0 and radial <= limit and vortex.is_passable_for(JumpVortex.Direction.DEPARTURE):
			_departures.remove_at(i)
			departed += 1
			(entry["on_through"] as Callable).call(ship)
			continue
		if local.z < 0.0 and local.length() <= DEPARTURE_OPEN_M:
			if not vortex.open(JumpVortex.Direction.DEPARTURE):
				continue  # an arrival is running: it opens once that one has closed
			vortex.extend(DEPARTURE_KEEP_S)
	if _departures.is_empty() and vortex.direction == JumpVortex.Direction.DEPARTURE:
		vortex.close()


func _sync_targetable() -> void:
	var marker := get_node_or_null(^"Targetable") as Targetable
	if marker == null:
		return
	marker.display_name = display_name
	marker.kind = Targetable.Kind.PROP
	marker.velocity = Vector3.ZERO
	marker.broadcast_range_m = BROADCAST_RANGE_M


func _read_points(data: Dictionary) -> void:
	var v: Variant = data.get("vortex")
	if v is Dictionary:
		radius_m = float((v as Dictionary).get("radius_m", DEFAULT_RADIUS_M))
	var a: Variant = data.get("arrival")
	if a is Dictionary:
		arrival_point = _vec((a as Dictionary).get("position"), DEFAULT_ARRIVAL)
		arrival_forward = _vec((a as Dictionary).get("forward"), Vector3.FORWARD).normalized()
	var d: Variant = data.get("departure")
	if d is Dictionary:
		departure_point = _vec((d as Dictionary).get("position"), DEFAULT_DEPARTURE)
		departure_forward = _vec((d as Dictionary).get("forward"), Vector3.BACK).normalized()


func _tips(data: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var emitters: Variant = data.get("emitters")
	if emitters is Array:
		for e: Variant in emitters as Array:
			if e is Dictionary:
				out.append(_vec((e as Dictionary).get("position"), Vector3.ZERO))
	if out.is_empty():
		for axis: Vector3 in [Vector3.UP, Vector3.LEFT, Vector3.DOWN, Vector3.RIGHT]:
			out.append(axis * DEFAULT_TIP_M)
	return out


# One Jolt box per truss and fin, on the rock layer: ships bounce off the arms; nothing else in the world touches them.
func _build_collision(data: Dictionary) -> void:
	collision_body = StaticBody3D.new()
	collision_body.name = "Collision"
	collision_body.collision_layer = CollisionLayers.layer_of(&"rock")
	collision_body.collision_mask = CollisionLayers.mask_of(&"rock")
	add_child(collision_body)
	var raw: Variant = data.get("collision")
	if not (raw is Array):
		return
	for value: Variant in raw as Array:
		var entry: Dictionary = Hardpoints.collision_entry(value)
		if entry.is_empty():
			continue
		var shape := CollisionShape3D.new()
		shape.name = String(entry["name"])
		shape.shape = entry["shape"]
		shape.transform = entry["transform"]
		collision_body.add_child(shape)


static func _load_shared() -> void:
	if _shared_loaded:
		return
	_shared_loaded = true
	_shared_mesh = MeshAssets.for_asset(ASSET_ID)
	if _shared_mesh == null:
		push_warning("Jumpgate: %s has no textured mesh (run scripts/gen_assets.sh, then import); the gate has no body" % ASSET_ID)
	var file := FileAccess.open(HARDPOINTS_PATH, FileAccess.READ)
	if file == null:
		push_warning("Jumpgate: no %s; the vortex and its points take the generator's defaults" % HARDPOINTS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_shared_data = parsed


static func _vec(raw: Variant, fallback: Vector3) -> Vector3:
	if raw is Array and (raw as Array).size() == 3:
		var a: Array = raw
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback
