class_name Jumpgate
extends Node3D
## The Earth Alliance jumpgate (M6-T14, D69): the generated `jumpgate` mesh, one Jolt box per truss and fin, a `Targetable` that
## locks on like a nav beacon and broadcasts to 1 000 km (so the AI and missions see it), and its `JumpVortex`, fitted inside the
## arms from the markers (`VortexFit.for_gate`). Before each opening it runs its own activation (`GateActivation`): the fin
## stations' lamps flash in turn along all four arms from front to back, then the back ends glow into the vortex's centre flash.
##
## The four arms run parallel to the vortex's axis at its top, bottom and sides, the side arms further out, so they frame an
## elliptical mouth (T19's correction of T13). The origin is the centre of their front
## ends, where the vortex's mouth lies, and the gate faces -Z: arrivals come out along -Z from the arrival point, departures line
## up at the departure point in front and fly in along +Z (`hardpoints.json`). The gate is at rest and has no hull: bolts pass it,
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
const GLOW_SHADER: Shader = preload("res://src/props/jump_glow.gdshader")
## The activation's glows, metres across: a lamp's flash and a back end's.
const LAMP_GLOW_M: float = 70.0
const TIP_GLOW_M: float = 260.0
## A gate's beacon is heard 1 000 km out (D69; the wiki and the fan manual both say so), as the nav buoys are.
const BROADCAST_RANGE_M: float = 1.0e6
## Where the hardpoints are missing: the generator's values for 1 200 m arms, 800 m from the axis above and below, 1 080 m at the sides.
const DEFAULT_RADIUS_M: float = 755.5
const DEFAULT_ARRIVAL: Vector3 = Vector3(0.0, 0.0, -75.5)
const DEFAULT_DEPARTURE: Vector3 = Vector3(0.0, 0.0, -1511.0)
const DEFAULT_ARM_RADIUS_M: float = 800.0
const DEFAULT_SIDE_RADIUS_M: float = 1080.0
const DEFAULT_BACK_Z_M: float = 1210.0
const FALLBACK_REACH_M: float = 2200.0
## A departing ship this close to the mouth, in front, opens the vortex: from the departure point (1 500 m) a ship at the
## run-in speed reaches the mouth after the 3.5 s the vortex takes to open.
const DEPARTURE_OPEN_M: float = 1600.0
## While a departing ship is on its way in, the vortex is kept open at least this much longer each tick.
const DEPARTURE_KEEP_S: float = 1.5
## Crossing the plane this far out (a share of the mouth's ellipse) still counts as going through.
const THROUGH_RADIUS: float = 1.1
## Ships come out of an arrival at this speed along -Z: clear of the plane in well under the 4 s it stays open.
const ARRIVAL_SPEED_MPS: float = 200.0

## Shown in the target readout; the console and missions find it by it.
@export var display_name: String = "JUMPGATE":
	set(value):
		display_name = value
		_sync_targetable()

var vortex: JumpVortex = null
## The vortex's size and place, from the markers.
var fit: VortexFit = null
## The lamps' glows (one per fin-station lamp: steady, flashing in turn during the activation) and the back ends', one multimesh.
var activation_glows: MultiMeshInstance3D = null
var collision_body: StaticBody3D = null
## The mouth's half height: the largest circle inside its ellipse.
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
# Per activation glow: the lamp's station rank (0 the front), or -1 for a back end.
var _glow_ranks: PackedInt32Array = PackedInt32Array()
var _stations: int = 0
# The glows are at their steady levels (nothing to update until the next activation).
var _steady: bool = false
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
	add_to_group(WorldFrame.ANCHORED_GROUP)


func _ready() -> void:
	_load_shared()
	body.mesh = _shared_mesh
	_read_points(_shared_data)
	_build_collision(_shared_data)
	fit = VortexFit.for_gate(_shared_data)
	vortex = JumpVortex.create(_shared_data.get("vortex", {}) as Dictionary, false)
	vortex.name = "Vortex"
	vortex.fit = fit
	vortex.position = Vector3(0.0, 0.0, fit.mouth_z_m)
	add_child(vortex)
	_build_activation(_shared_data)
	_sync_targetable()


func _physics_process(_delta: float) -> void:
	_step_arrivals()
	_step_departures()


func _process(_delta: float) -> void:
	update_activation()


## Opens the vortex `direction` after the gate's activation (or keeps the one opening that way open); false while it runs the
## other way.
func open_vortex(direction: JumpVortex.Direction, hold_s: float = VortexTiming.DEFAULT_HOLD_S) -> bool:
	return vortex.open(direction, hold_s, GateActivation.DURATION_S)


## Puts the activation's lamps and tips on the vortex's age. Public for tests and captures.
func update_activation() -> void:
	if activation_glows == null:
		return
	# The lamps always burn (steadily between openings); only the activation changes them.
	var running: bool = vortex.is_active() and vortex.timing.lead_s > 0.0 and GateActivation.is_showing(vortex.age_s)
	if not running and _steady:
		return
	_steady = not running
	var age: float = vortex.age_s if running else INF
	var mm: MultiMesh = activation_glows.multimesh
	for i: int in _glow_ranks.size():
		var rank: int = _glow_ranks[i]
		var level: float
		if rank < 0:
			level = GateActivation.tip_level(age) if running else 0.0
		else:
			level = GateActivation.lamp_level(rank, _stations, age) if running else GateActivation.STEADY_LEVEL
		var c: Color = mm.get_instance_color(i)
		c.a = level
		mm.set_instance_color(i, c)


## The level of the lamps at station `rank` now (tests, captures).
func activation_level(rank: int) -> float:
	return GateActivation.lamp_level(rank, _stations, vortex.age_s) if vortex.is_active() else GateActivation.STEADY_LEVEL


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
		open_vortex(JumpVortex.Direction.ARRIVAL)  # refused while a departure runs: tried again next tick


func _step_departures() -> void:
	if _departures.is_empty() or vortex == null:
		return
	for i: int in range(_departures.size() - 1, -1, -1):
		var entry: Dictionary = _departures[i]
		var ship := entry["body"] as Node3D
		if not is_instance_valid(ship) or not ship.is_inside_tree() or not ship.is_visible_in_tree():
			_departures.remove_at(i)
			continue
		var local: Vector3 = to_local(ship.global_position)
		var was_z: float = entry["z"]
		entry["z"] = local.z
		var inside: bool = fit.contains(Vector2(local.x, local.y), THROUGH_RADIUS)
		if was_z < 0.0 and local.z >= 0.0 and inside and vortex.is_passable_for(JumpVortex.Direction.DEPARTURE):
			_departures.remove_at(i)
			departed += 1
			(entry["on_through"] as Callable).call(ship)
			continue
		if local.z < 0.0 and local.length() <= DEPARTURE_OPEN_M:
			if not open_vortex(JumpVortex.Direction.DEPARTURE):
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


# One glow per fin-station lamp (ranked by its place along the arm, the same on all four arms) and one per back end, in a single
# multimesh; the lamps' colour from the markers, the back ends' from the vortex's flash.
func _build_activation(data: Dictionary) -> void:
	var points: Array[Vector3] = []
	var colours: Array[Color] = []
	var along := PackedFloat32Array()
	var lights: Variant = data.get("lights")
	if lights is Array:
		for e: Variant in lights as Array:
			if e is Dictionary:
				var p: Vector3 = _vec((e as Dictionary).get("position"), Vector3.ZERO)
				points.append(p)
				colours.append(JumpVortex._colour((e as Dictionary).get("colour"), Color(1.0, 0.66, 0.26)))
				along.append(p.z)
	_glow_ranks = GateActivation.station_ranks(along)
	_stations = 0
	for r: int in _glow_ranks:
		_stations = maxi(_stations, r + 1)
	var tips: Array[Vector3] = _tips(data)
	for tip: Vector3 in tips:
		points.append(tip)
		colours.append(vortex.flash_colour)
		_glow_ranks.append(-1)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var material := ShaderMaterial.new()
	material.shader = GLOW_SHADER
	material.set_shader_parameter(&"tint", Vector3(3.0, 3.0, 3.0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = points.size()
	for i: int in points.size():
		var size: float = (TIP_GLOW_M if _glow_ranks[i] < 0 else LAMP_GLOW_M) * 0.5
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), points[i]))
		var c: Color = colours[i]
		c.a = 0.0
		mm.set_instance_color(i, c)
	activation_glows = MultiMeshInstance3D.new()
	activation_glows.name = "ActivationGlows"
	activation_glows.multimesh = mm
	activation_glows.material_override = material
	activation_glows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var reach: float = FALLBACK_REACH_M
	for p: Vector3 in points:
		reach = maxf(reach, p.length() + TIP_GLOW_M)
	activation_glows.custom_aabb = AABB(-Vector3.ONE * reach, Vector3.ONE * reach * 2.0)
	add_child(activation_glows)


func _tips(data: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var emitters: Variant = data.get("emitters")
	if emitters is Array:
		for e: Variant in emitters as Array:
			if e is Dictionary:
				out.append(_vec((e as Dictionary).get("position"), Vector3.ZERO))
	if out.is_empty():
		for axis: Vector3 in [Vector3.UP, Vector3.LEFT, Vector3.DOWN, Vector3.RIGHT]:
			var out_m: float = DEFAULT_ARM_RADIUS_M if is_zero_approx(axis.x) else DEFAULT_SIDE_RADIUS_M
			out.append(axis * out_m + Vector3(0.0, 0.0, DEFAULT_BACK_Z_M))
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
