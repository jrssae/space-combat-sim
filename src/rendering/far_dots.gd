class_name FarDots
extends MultiMeshInstance3D
## Every far AI ship as a point (M4-T11, architecture §17.10 and §14.4's last level). A ship past `settings.far_ship_dot_m` from
## the camera hides its hull, plumes and markers (its `LodSwitcher` decides, `Ship.set_far_dot`) and is drawn here instead: one
## instance of the world's one multimesh, so every far ship together is one draw call. A dot is the hull's mean paint at the hull's
## angular size, never under a pixel, and dims below that like a running light (`far_ship_dot.gdshader`). The paint is the textured
## mesh's mean albedo from the manifest (M4-T30d).
##
## A child of `World` (`attach`) at the World's origin, its dots in World-local metres. Each frame it writes each shown ship's
## drawn pose. It is shiftable, so a rebase moves the written dots with everything else at once (no frame draws one at its old
## place); it then goes back to the origin and moves the dots instead, so its own offset never grows. A parked or freed ship draws
## none. Visual only.

const NODE_NAME: String = "FarDots"
const SHADER: Shader = preload("res://assets/shaders/far_ship_dot.gdshader")
## The paint of a ship whose manifest names none.
const DEFAULT_PAINT: Color = Color(0.5, 0.5, 0.5)
## The light a far hull's lit side gets (§7.3: about 1.2 facing the key star), applied to the sRGB paint: what the eye picks out
## of a far hull is its lit side.
const LIGHT_LEVEL: float = 1.2
## Floats per instance: a 3x4 transform, then the custom data (paint, radius).
const STRIDE: int = 16

# Each asset's lit paint, read once.
static var _asset_paint: Dictionary = {}

var _ships: Array[Ship] = []
var _buffer: PackedFloat32Array = PackedFloat32Array()
var _shown: int = 0


## The world's dots, or null before any ship went far.
static func of(world: Node) -> FarDots:
	if world == null or not is_instance_valid(world):
		return null
	return world.get_node_or_null(NodePath(NODE_NAME)) as FarDots


## The world's dots, made on first use.
static func attach(world: Node) -> FarDots:
	var found: FarDots = of(world)
	if found != null or world == null or not is_instance_valid(world):
		return found
	var made := FarDots.new()
	world.add_child(made)
	return made


## The dot colour of `asset_id` in linear light: its manifest's `mesh.mean_albedo` (linear) lit as a hull's lit side, else
## `DEFAULT_PAINT`; read once per asset.
static func asset_paint(asset_id: String) -> Color:
	if _asset_paint.has(asset_id):
		return _asset_paint[asset_id]
	var mean: Array = (MeshAssets.read_manifest(asset_id).get("mesh", {}) as Dictionary).get("mean_albedo", [])
	var paint: Color = Color(float(mean[0]), float(mean[1]), float(mean[2])).linear_to_srgb() if mean.size() == 3 \
			else DEFAULT_PAINT
	var lit := Color(paint.r * LIGHT_LEVEL, paint.g * LIGHT_LEVEL, paint.b * LIGHT_LEVEL).srgb_to_linear()
	_asset_paint[asset_id] = lit
	return lit


func _init() -> void:
	name = NODE_NAME
	add_to_group(WorldFrame.SHIFTABLE_GROUP)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	custom_aabb = AABB(Vector3.ONE * -1.0e6, Vector3.ONE * 2.0e6)  # spread over the whole world: never culled as one
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material_override = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.visible_instance_count = 0


func _ready() -> void:
	var world := get_parent() as WorldFrame
	if world != null and not world.rebased.is_connected(_on_rebased):
		world.rebased.connect(_on_rebased)


func _process(_delta: float) -> void:
	refresh()


## Draws `ship` as a dot from the next refresh on.
func add(ship: Ship) -> void:
	if ship != null and not _ships.has(ship):
		_ships.append(ship)
		refresh()


## Stops drawing `ship` as a dot.
func remove(ship: Ship) -> void:
	if _ships.has(ship):
		_ships.erase(ship)
		refresh()


## Dots drawn since the last refresh.
func dot_count() -> int:
	return _shown


## The global position of dot `index`.
func dot_position(index: int) -> Vector3:
	var base: int = index * STRIDE
	return global_transform * Vector3(_buffer[base + 3], _buffer[base + 7], _buffer[base + 11])


## The hull radius dot `index` is sized by, m.
func dot_radius(index: int) -> float:
	return _buffer[index * STRIDE + 15]


## Writes every shown far ship at its drawn pose. `_process` calls it each frame; public for the tests.
func refresh() -> void:
	var n: int = 0
	for i: int in range(_ships.size() - 1, -1, -1):
		if not is_instance_valid(_ships[i]) or not _ships[i].is_inside_tree():
			_ships.remove_at(i)
	if _ships.size() > multimesh.instance_count:
		multimesh.instance_count = maxi(_ships.size(), multimesh.instance_count * 2)  # grows rarely, never shrinks
		_buffer.resize(multimesh.instance_count * STRIDE)
	var to_local: Transform3D = global_transform.affine_inverse()
	for ship: Ship in _ships:
		if not ship.is_visible_in_tree():
			continue  # parked
		var at: Vector3 = to_local * ship.get_global_transform_interpolated().origin
		var paint: Color = _paint_of(ship)
		var base: int = n * STRIDE
		_buffer[base + 0] = 1.0
		_buffer[base + 1] = 0.0
		_buffer[base + 2] = 0.0
		_buffer[base + 3] = at.x
		_buffer[base + 4] = 0.0
		_buffer[base + 5] = 1.0
		_buffer[base + 6] = 0.0
		_buffer[base + 7] = at.y
		_buffer[base + 8] = 0.0
		_buffer[base + 9] = 0.0
		_buffer[base + 10] = 1.0
		_buffer[base + 11] = at.z
		_buffer[base + 12] = paint.r
		_buffer[base + 13] = paint.g
		_buffer[base + 14] = paint.b
		_buffer[base + 15] = ship.bounding_radius()
		n += 1
	_shown = n
	_upload()


func _upload() -> void:
	if multimesh.instance_count > 0:
		RenderingServer.multimesh_set_buffer(multimesh.get_rid(), _buffer)
	multimesh.visible_instance_count = _shown


# The rebase moved this node with the world; back to the origin, with the dots moved instead.
func _on_rebased(offset: Vector3) -> void:
	position += offset
	for i: int in _shown:
		var base: int = i * STRIDE
		_buffer[base + 3] -= offset.x
		_buffer[base + 7] -= offset.y
		_buffer[base + 11] -= offset.z
	_upload()


# The ship's hull paint (its asset's manifest), lit as a hull's lit side, in linear light.
func _paint_of(ship: Ship) -> Color:
	return asset_paint(ship.spec.asset_id if ship.spec != null else "")
