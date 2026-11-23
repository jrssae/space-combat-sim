class_name BayDoorNode
extends MultiMeshInstance3D
## One bay's roll-up door (M10-T22, Q58): its shutter's slats over the mouth, shut by default and wound up into the hull's roll
## housing when told to open. A thin adapter; the rules are in `BayDoors`.

## Past this the shutter is not drawn: the bay's mouth is under a pixel from that far, so its red cannot show either.
const DRAW_RANGE_M: float = 20000.0

## The bay this door closes.
var bay: String = ""
## 0 shut, 1 open: what is drawn now.
var amount: float = 0.0
var _door: Dictionary = {}
var _target: float = 0.0
var _backing: MeshInstance3D = null

static var _material: StandardMaterial3D = null
static var _dark: StandardMaterial3D = null


## A shut door built from one `doors` entry of `hardpoints.json`.
static func create(door: Dictionary) -> BayDoorNode:
	var node := BayDoorNode.new()
	node.bay = BayDoors.bay_of(str(door.get("name", "")))
	node.name = "Door%s" % node.bay.to_pascal_case().validate_node_name()
	node._door = door
	var size: Array = door.get("size_m", [1.0, 1.0, 0.2]) as Array
	var slat := BoxMesh.new()
	slat.size = Vector3(float(size[0]), 1.0, float(size[2]))
	slat.material = _shared_material()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = slat
	mm.instance_count = maxi(int(door.get("slats", 1)), 1)
	node.multimesh = mm
	node.transform = BayDoors.frame(door)
	node.visibility_range_end = DRAW_RANGE_M
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node._add_backing(size)
	node._draw()
	node.set_process(false)
	return node


func is_open() -> bool:
	return _target > 0.5


## Rolls toward open (true) or shut (false).
func set_open(open: bool) -> void:
	_target = 1.0 if open else 0.0
	set_process(not is_equal_approx(amount, _target))


## Jumps to open or shut at once (a test, or a freshly spawned hull).
func snap(open: bool) -> void:
	_target = 1.0 if open else 0.0
	amount = _target
	_draw()
	set_process(false)


## Holds the shutter part-way (0 shut, 1 open), for a look sheet.
func hold(at: float) -> void:
	amount = clampf(at, 0.0, 1.0)
	_target = amount
	_draw()
	set_process(false)


func _process(delta: float) -> void:
	amount = BayDoors.advance(amount, _target, delta)
	_draw()
	if is_equal_approx(amount, _target):
		set_process(false)


# A shut door shows no light: a dark plate behind the slats blocks the lit hall seen through their grooves.
func _add_backing(size: Array) -> void:
	var plate := BoxMesh.new()
	plate.size = Vector3(float(size[0]), 1.0, 0.05)
	plate.material = _dark_material()
	_backing = MeshInstance3D.new()
	_backing.name = "Backing"
	_backing.mesh = plate
	_backing.visibility_range_end = DRAW_RANGE_M
	_backing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_backing)


# Lays out the slats still out of the housing, and the dark plate behind them.
func _draw() -> void:
	var shown: Array[Vector2] = BayDoors.slats(_door, amount)
	for i: int in shown.size():
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1.0, shown[i].y, 1.0)), Vector3(0.0, shown[i].x, 0.0)))
	multimesh.visible_instance_count = shown.size()
	visible = not shown.is_empty()
	var back: Vector2 = BayDoors.backing(_door, amount)
	var depth: float = float((_door.get("size_m", [1.0, 1.0, 0.2]) as Array)[2])
	_backing.transform = Transform3D(Basis.from_scale(Vector3(1.0, maxf(back.y, 1e-3), 1.0)), Vector3(0.0, back.x, -0.5 * depth - 0.03))


static func _dark_material() -> StandardMaterial3D:
	if _dark == null:
		_dark = StandardMaterial3D.new()
		_dark.albedo_color = Color(0.03, 0.03, 0.035)
		_dark.roughness = 1.0
	return _dark


static func _shared_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_color = Color(0.52, 0.53, 0.55)
		_material.roughness = 0.5
		_material.metallic = 0.45
	return _material
