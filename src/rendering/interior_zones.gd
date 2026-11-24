class_name InteriorZones
extends Node3D
## The station's open bays as trigger volumes (M7): a ship flying into the main docking bay's tunnel or the cargo bay goes into
## the interior light (`InteriorLight`), and back out as it leaves or is taken from the world. The physics engine reports the
## crossings, so nothing here runs per tick. A child of the station, in its frame: the tunnel lies on the drum's axis, so its
## volume need not turn with the drum. The launch halls are closed; their fighters are `LaunchDirector`'s.
##
## A capital's bays (M10-T72, Q68) are one volume of its own, `bays`, a box per bay's hall from its `bays` hardpoints, a child of the
## ship so it flies and turns with it: a fighter or the player in a hall is lit by the hall's lamps alone, as the walls are.

## How far inside the tunnel's mouth its volume starts, m: a ship is in the interior light once it is in past the mouth's frames.
const MOUTH_INSET_M: float = 8.0
## Room round the clear passage, m.
const MARGIN_M: float = 12.0

## A capital's volume: every bay's hall.
const BAYS: String = "bays"

## How many ships are inside each volume now, by name (for the tests and the console).
var inside: Dictionary = {}


## The volumes of a station's `manifest`, in the asset's frame: `name`, `kind` (`cylinder` along z or `box`), `centre`, and
## `radius` with `length`, or `size`. Empty when the manifest has no bays.
static func volumes(manifest: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var hardpoints: Dictionary = manifest.get("hardpoints", {})
	var bay: Dictionary = hardpoints.get("main_docking_bay", {})
	var pivot: Array = ((manifest.get("pieces", {}) as Dictionary).get("drum", {}) as Dictionary).get("pivot", [0.0, 0.0, 0.0])
	if bay.has("main_docking_bay_mouth") and bay.has("main_docking_bay_airlock"):
		var mouth: float = float((bay["main_docking_bay_mouth"] as Array)[2]) + float(pivot[2]) + MOUTH_INSET_M
		var airlock: float = float((bay["main_docking_bay_airlock"] as Array)[2]) + float(pivot[2])
		var half: Array = bay.get("main_docking_bay_clear_half_m", [40.0, 20.0])
		out.append({"name": "main_docking_bay", "kind": "cylinder", "centre": Vector3(0.0, 0.0, 0.5 * (mouth + airlock)),
				"radius": Vector2(float(half[0]), float(half[1])).length() + MARGIN_M, "length": absf(airlock - mouth)})
	var cargo: Dictionary = hardpoints.get("cargo_bay", {})
	if cargo.has("cargo_bay_clear_min") and cargo.has("cargo_bay_clear_max"):
		var lo: Array = cargo["cargo_bay_clear_min"]
		var hi: Array = cargo["cargo_bay_clear_max"]
		var a := Vector3(float(lo[0]), float(lo[1]), float(lo[2]))
		var b := Vector3(float(hi[0]), float(hi[1]), float(hi[2]))
		out.append({"name": "cargo_bay", "kind": "box", "centre": 0.5 * (a + b) + Vector3(0.0, 0.0, 0.5 * MOUTH_INSET_M),
				"size": (b - a) + Vector3(2.0 * MARGIN_M, 2.0 * MARGIN_M, -MOUTH_INSET_M)})
	return out


## The zones of a station's `manifest`, to add under the station; null when it has no bays.
static func for_manifest(manifest: Dictionary) -> InteriorZones:
	var listed: Array[Dictionary] = volumes(manifest)
	if listed.is_empty():
		return null
	var made := InteriorZones.new()
	made.name = "InteriorZones"
	for volume: Dictionary in listed:
		made._add(volume)
	return made


## A capital's bay halls in its `hardpoints` (body frame), each a `box` with its `basis` (x across, y up, z into the mouth): from
## `MOUTH_INSET_M` inside the mouth (half the hall's depth for a short hall) to its back wall. Empty when it has no bays.
static func bay_volumes(hardpoints: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Variant in hardpoints.get("bays", []) if hardpoints.get("bays") is Array else []:
		var bay: Dictionary = raw if raw is Dictionary else {}
		if str(bay.get("kind", "")) != "bay" or not bay.has("mouth_m") or not bay.has("exit"):
			continue
		var mouth: Array = bay["mouth_m"]
		var depth: float = float(bay.get("depth_m", 0.0))
		var w: float = float(mouth[0])
		var h: float = float(mouth[1])
		var out_dir: Vector3 = _vec(bay.get("forward")).normalized()
		var up: Vector3 = _vec(bay.get("up")).normalized()
		var inset: float = minf(MOUTH_INSET_M, 0.5 * depth)
		var basis := Basis(out_dir.cross(up), up, -out_dir)  # right-handed: z into the hall
		var centre: Vector3 = _vec(bay["exit"]) + up * (h / 6.0) - out_dir * (0.5 * (depth + inset))
		out.append({"name": str(bay.get("name", "")), "kind": "box", "centre": centre, "basis": basis,
				"size": Vector3(w, h, depth - inset)})
	return out


## The zone of a capital's bays (its `hardpoints`), to add under the ship; null when it has none.
static func for_bays(hardpoints: Dictionary) -> InteriorZones:
	var listed: Array[Dictionary] = bay_volumes(hardpoints)
	if listed.is_empty():
		return null
	var made := InteriorZones.new()
	made.name = "BayZones"
	made._add_group(BAYS, Vector3.ZERO, listed)
	return made


## The trigger volume named `zone`, or null.
func area(zone: String) -> Area3D:
	return get_node_or_null(NodePath(zone.to_pascal_case())) as Area3D


func _add(volume: Dictionary) -> void:
	var at: Vector3 = volume["centre"]
	_add_group(String(volume["name"]), at, [volume.merged({"centre": Vector3.ZERO}, true)])


# One trigger volume of one or more shapes (each placed about `at`).
func _add_group(zone_name: String, at: Vector3, shapes: Array[Dictionary]) -> void:
	var zone := Area3D.new()
	zone.name = zone_name.to_pascal_case()
	zone.position = at
	zone.collision_layer = 0
	zone.collision_mask = CollisionLayers.PLAYER | CollisionLayers.FIGHTER | CollisionLayers.CAPITAL
	if zone_name == BAYS:
		zone.collision_mask = CollisionLayers.PLAYER | CollisionLayers.FIGHTER  # not its own hull, nor another capital
	zone.monitorable = false
	for volume: Dictionary in shapes:
		var shape := CollisionShape3D.new()
		if volume["kind"] == "cylinder":
			var cylinder := CylinderShape3D.new()
			cylinder.radius = float(volume["radius"])
			cylinder.height = float(volume["length"])
			shape.shape = cylinder
			shape.rotation = Vector3(0.5 * PI, 0.0, 0.0)  # the cylinder's axis along z
		else:
			var box := BoxShape3D.new()
			box.size = volume["size"]
			shape.shape = box
			shape.basis = volume.get("basis", Basis.IDENTITY)
		shape.position = volume["centre"]
		zone.add_child(shape)
	add_child(zone)
	inside[zone_name] = 0
	zone.body_entered.connect(_crossed.bind(zone_name, true))
	zone.body_exited.connect(_crossed.bind(zone_name, false))


static func _vec(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	var a: Array = v if v is Array else [0.0, 0.0, 0.0]
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


# A ship came into a volume or left it (also when it is taken from the world inside).
func _crossed(body: Node3D, zone: String, entered: bool) -> void:
	if not body is Ship:
		return
	inside[zone] = maxi(int(inside[zone]) + (1 if entered else -1), 0)
	if is_instance_valid(body):
		InteriorLight.set_inside(body, entered)
