class_name FarDots
extends MultiMeshInstance3D
## Every far AI ship as a point (M4-T11, architecture §17.10 and §14.4's last level). A ship past `settings.far_ship_dot_m` from
## the camera hides its hull, plumes and markers (its `LodSwitcher` decides, `Ship.set_far_dot`) and is drawn here instead: one
## instance of the world's one multimesh, so every far ship together is one draw call. A dot is the hull's mean paint at the hull's
## angular size, never under a pixel, and dims below that like a running light (`far_ship_dot.gdshader`). The paint is the textured
## mesh's mean albedo from the manifest (M4-T30d).
##
## A child of `World` (`attach`) at the World's origin, its dots in World-local metres. Each frame it writes each shown ship's
## drawn pose; a ship's paint and size are read once, when it turns into a dot, and the dots' identity rotations once per slot,
## so a frame writes a dot's place, paint and size only, and ships turning together cost one refresh (M4-T36). It is shiftable, so a rebase moves the written dots with everything else at once (no frame draws one at its old
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
# Per ship in `_ships`: its paint and its hull's radius, read when it turned into a dot.
var _paints: Array[Color] = []
var _radii: PackedFloat64Array = PackedFloat64Array()
var _buffer: PackedFloat32Array = PackedFloat32Array()
var _shown: int = 0
## Refreshes so far (tests: ships that turn together cost one).
var refresh_count: int = 0


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


## Draws `ship` as a dot from the next refresh on (this frame's: the dots refresh after the LOD pass).
func add(ship: Ship) -> void:
	if ship != null and not _ships.has(ship):
		_ships.append(ship)
		_paints.append(_paint_of(ship))
		_radii.append(ship.bounding_radius())


## Stops drawing `ship` as a dot from the next refresh on.
func remove(ship: Ship) -> void:
	var at: int = _ships.find(ship)
	if at >= 0:
		_forget(at)


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


## The paint dot `index` is drawn in.
func dot_paint(index: int) -> Color:
	var base: int = index * STRIDE
	return Color(_buffer[base + 12], _buffer[base + 13], _buffer[base + 14])


## The pose instance `index` is drawn with, in this node's frame.
func instance_transform(index: int) -> Transform3D:
	var b: int = index * STRIDE
	return Transform3D(Vector3(_buffer[b], _buffer[b + 4], _buffer[b + 8]), Vector3(_buffer[b + 1], _buffer[b + 5], _buffer[b + 9]),
			Vector3(_buffer[b + 2], _buffer[b + 6], _buffer[b + 10]), Vector3(_buffer[b + 3], _buffer[b + 7], _buffer[b + 11]))


## Writes every shown far ship at its drawn pose. `_process` calls it each frame; public for the tests.
func refresh() -> void:
	refresh_count += 1
	var n: int = 0
	for i: int in range(_ships.size() - 1, -1, -1):
		if not is_instance_valid(_ships[i]) or not _ships[i].is_inside_tree():
			_forget(i)
	if _ships.size() > multimesh.instance_count:
		var first_new: int = multimesh.instance_count
		multimesh.instance_count = maxi(_ships.size(), multimesh.instance_count * 2)  # grows rarely, never shrinks
		_buffer.resize(multimesh.instance_count * STRIDE)
		for slot: int in range(first_new, multimesh.instance_count):
			var b: int = slot * STRIDE  # the dots never turn: each slot's rotation is the identity, written once
			_buffer[b] = 1.0
			_buffer[b + 5] = 1.0
			_buffer[b + 10] = 1.0
	var to_local: Transform3D = global_transform.affine_inverse()
	for i: int in _ships.size():
		var ship: Ship = _ships[i]
		if not ship.is_visible_in_tree():
			continue  # parked
		var at: Vector3 = to_local * ship.get_global_transform_interpolated().origin
		var paint: Color = _paints[i]
		var base: int = n * STRIDE
		_buffer[base + 3] = at.x
		_buffer[base + 7] = at.y
		_buffer[base + 11] = at.z
		_buffer[base + 12] = paint.r
		_buffer[base + 13] = paint.g
		_buffer[base + 14] = paint.b
		_buffer[base + 15] = _radii[i]
		n += 1
	_shown = n
	_upload()


func _forget(at: int) -> void:
	_ships.remove_at(at)
	_paints.remove_at(at)
	_radii.remove_at(at)


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
