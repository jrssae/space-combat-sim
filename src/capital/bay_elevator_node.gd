class_name BayElevatorNode
extends Node3D
## Draws a bay's hidden lift (M10-T17, Q73; the rules are `BayElevator`): a deck plate flush with the hall's floor that sinks out
## of sight and comes back up. While it is down a dark well shows in the floor where it was; the hall's floor hides the plate
## and any craft below it, so a craft on the lift rises out of the well.

## Past this the lift is not drawn (the hall's mouth is a few pixels from that far).
const DRAW_RANGE_M: float = 6000.0
## The plate stands this proud of the floor at the top, and the well's cover this far, m (no fighting with the floor's faces).
const PLATE_PROUD_M: float = 0.08
const WELL_PROUD_M: float = 0.03
const PLATE_THICK_M: float = 0.6

var lift: BayElevator = null
var travel_m: float = 30.0
var _plate: MeshInstance3D = null
var _well: MeshInstance3D = null

static var _plate_material: StandardMaterial3D = null
static var _well_material: StandardMaterial3D = null


## A lift whose floor point is `at` (the carrier's frame, its basis `basis`: x across, y up), `size_m` across and along the hall.
static func create(p_lift: BayElevator, at: Vector3, basis: Basis, size_m: Vector2, p_travel_m: float) -> BayElevatorNode:
	var node := BayElevatorNode.new()
	node.name = "Elevator"
	node.lift = p_lift
	node.travel_m = p_travel_m
	node.transform = Transform3D(basis, at)
	var plate := BoxMesh.new()
	plate.size = Vector3(size_m.x, PLATE_THICK_M, size_m.y)
	plate.material = _shared(false)
	node._plate = node._part("Plate", plate)
	var well := PlaneMesh.new()
	well.size = size_m
	well.material = _shared(true)
	node._well = node._part("Well", well)
	node._well.position = Vector3(0.0, WELL_PROUD_M, 0.0)
	node._draw()
	return node


func _process(_delta: float) -> void:
	_draw()


# Puts the plate at the lift's height and shows the well while it is not flush.
func _draw() -> void:
	var h: float = lift.height() if lift != null else 1.0
	_plate.position = Vector3(0.0, PLATE_PROUD_M - 0.5 * PLATE_THICK_M - (1.0 - h) * travel_m, 0.0)
	_well.visible = h < 0.999


func _part(part_name: String, mesh: Mesh) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.visibility_range_end = DRAW_RANGE_M
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	return part


static func _shared(dark: bool) -> StandardMaterial3D:
	if dark and _well_material == null:
		_well_material = StandardMaterial3D.new()
		_well_material.albedo_color = Color(0.02, 0.02, 0.025)
		_well_material.roughness = 1.0
	if not dark and _plate_material == null:
		_plate_material = StandardMaterial3D.new()
		_plate_material.albedo_color = Color(0.42, 0.43, 0.45)
		_plate_material.roughness = 0.7
		_plate_material.metallic = 0.3
	return _well_material if dark else _plate_material
