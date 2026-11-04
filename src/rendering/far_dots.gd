class_name FarDots
extends MultiMeshInstance3D
## Every far AI ship as a point (M4-T11, architecture §17.10 and §14.4's last level). A ship past `settings.far_ship_dot_m` from
## the camera hides its splats, proxy, plumes and markers (its `LodSwitcher` decides, `Ship.set_far_dot`) and is drawn here
## instead: one instance of the world's one multimesh, so every far ship together is one draw call. A dot is the hull's mean paint
## at the hull's angular size, never under a pixel, and dims below that like a running light (`far_ship_dot.gdshader`).
##
## A child of `World` (`attach`), drawn in global space (`top_level`). Each frame it writes each shown ship's drawn pose; a
## rebase moves the written dots at once, so no frame draws one at its old place. A parked or freed ship draws none. Visual only.

const NODE_NAME: String = "FarDots"
const SHADER: Shader = preload("res://assets/shaders/far_ship_dot.gdshader")
## The paint of a ship with no splats to read.
const DEFAULT_PAINT: Color = Color(0.5, 0.5, 0.5)
## How much of its paint a far hull shows on average, between its lit side and its dark side (§7.3: about 1.2 and 0.3).
const LIGHT_LEVEL: float = 0.75
## Floats per instance: a 3x4 transform, then the custom data (paint, radius).
const STRIDE: int = 16
const SPLAT_FLOATS: int = 60
const SH_C0: float = 0.28209479177387814

# The mean paint of each splat resource, read once.
static var _paint_cache: Dictionary = {}

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


## The opacity-weighted mean paint of a splat resource (sRGB, as the generators wrote it), or `DEFAULT_PAINT`.
static func paint_color(gaussian: GaussianResource) -> Color:
	if gaussian == null or gaussian.point_count <= 0 or gaussian.point_data_float.size() < gaussian.point_count * SPLAT_FLOATS:
		return DEFAULT_PAINT
	var data: PackedFloat32Array = gaussian.point_data_float
	var sum := Vector3.ZERO
	var weight: float = 0.0
	for i: int in gaussian.point_count:
		var base: int = i * SPLAT_FLOATS
		var alpha: float = data[base + 10]
		sum += alpha * Vector3(data[base + 12], data[base + 13], data[base + 14])
		weight += alpha
	if weight <= 0.0:
		return DEFAULT_PAINT
	var dc: Vector3 = sum / weight
	return Color(clampf(0.5 + SH_C0 * dc.x, 0.0, 1.0), clampf(0.5 + SH_C0 * dc.y, 0.0, 1.0), clampf(0.5 + SH_C0 * dc.z, 0.0, 1.0))


func _init() -> void:
	name = NODE_NAME
	top_level = true
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
	return Vector3(_buffer[base + 3], _buffer[base + 7], _buffer[base + 11])


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
	for ship: Ship in _ships:
		if not ship.is_visible_in_tree():
			continue  # parked
		var at: Vector3 = ship.get_global_transform_interpolated().origin
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


# The world moved under every dot: they move with it now, not at the next frame.
func _on_rebased(offset: Vector3) -> void:
	for i: int in _shown:
		var base: int = i * STRIDE
		_buffer[base + 3] -= offset.x
		_buffer[base + 7] -= offset.y
		_buffer[base + 11] -= offset.z
	_upload()


# The ship's coarsest level's mean paint, lit to a far hull's average and in linear light.
func _paint_of(ship: Ship) -> Color:
	var nodes: Array[GaussianSplatNode] = ship.splat_nodes()
	var gaussian: GaussianResource = nodes.back().gaussian if not nodes.is_empty() else null
	if not _paint_cache.has(gaussian):
		var paint: Color = paint_color(gaussian).srgb_to_linear()
		_paint_cache[gaussian] = Color(paint.r * LIGHT_LEVEL, paint.g * LIGHT_LEVEL, paint.b * LIGHT_LEVEL)
	return _paint_cache[gaussian]
