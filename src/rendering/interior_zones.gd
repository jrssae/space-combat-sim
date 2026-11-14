class_name InteriorZones
extends Node3D
## The station's open bays as trigger volumes (M7): a ship flying into the main docking bay's tunnel or the cargo bay goes into
## the interior light (`InteriorLight`), and back out as it leaves or is taken from the world. The physics engine reports the
## crossings, so nothing here runs per tick. A child of the station, in its frame: the tunnel lies on the drum's axis, so its
## volume need not turn with the drum. The launch halls are closed; their fighters are `LaunchDirector`'s.

## How far inside the tunnel's mouth its volume starts, m: a ship is in the interior light once it is in past the mouth's frames.
const MOUTH_INSET_M: float = 8.0
## Room round the clear passage, m.
const MARGIN_M: float = 12.0

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


## The trigger volume named `zone`, or null.
func area(zone: String) -> Area3D:
	return get_node_or_null(NodePath(zone.to_pascal_case())) as Area3D


func _add(volume: Dictionary) -> void:
	var zone := Area3D.new()
	zone.name = String(volume["name"]).to_pascal_case()
	zone.position = volume["centre"]
	zone.collision_layer = 0
	zone.collision_mask = CollisionLayers.PLAYER | CollisionLayers.FIGHTER | CollisionLayers.CAPITAL
	zone.monitorable = false
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
	zone.add_child(shape)
	add_child(zone)
	inside[String(volume["name"])] = 0
	zone.body_entered.connect(_crossed.bind(String(volume["name"]), true))
	zone.body_exited.connect(_crossed.bind(String(volume["name"]), false))


# A ship came into a volume or left it (also when it is taken from the world inside).
func _crossed(body: Node3D, zone: String, entered: bool) -> void:
	if not body is Ship:
		return
	inside[zone] = maxi(int(inside[zone]) + (1 if entered else -1), 0)
	if is_instance_valid(body):
		InteriorLight.set_inside(body, entered)
