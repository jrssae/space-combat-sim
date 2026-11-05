class_name BoltMesh
extends Node3D
## Draws the core's owned bolts (M4-T35, architecture §17.13): one `MultiMeshInstance3D` per look (a weapon's capsule
## length, radius and material, `Projectile.bolt_mesh`), its buffer filled once a frame from the core (`bolt_transforms`:
## every live owned bolt of that look, drawn between its last two ticks as an interpolated node would be, enlarged by
## `Projectile.visual_scale`). An internal child of `SimCore`, so it comes and goes with the core. Positions are World
## local as the rows hold them, so a rebase moves the rows and the next frame draws them there; the node itself stays at
## the identity and is not shiftable. The frame's passes (`FramePasses`, M4-T36) call `update` once a frame. Each bolt keeps
## its instance slot for life (a freed slot is drawn empty until a new bolt takes it), so instance k follows one bolt tick to
## tick, as T38's motion vectors need.
##
## Looks are registered once per weapon spec (`look_for`), shared by the cannon kernel and the stand-ins; a bolt a node
## draws (a beam, a missile) has `SimCore.LOOK_NONE`.

## The looks seen so far: `[length_m, radius_m, material]` by index.
static var _looks: Array[Array] = []
static var _look_index: Dictionary = {}

## Instances drawn in the last frame, over every look (a readout).
var instances_drawn: int = 0

var _sim: SimCore = null
var _instances: Array[MultiMeshInstance3D] = []
var _capacity: PackedInt32Array = PackedInt32Array()
var _child_basis: Basis = Basis.IDENTITY
var _child_known: bool = false


func _init(p_sim: SimCore = null) -> void:
	name = "BoltMesh"
	_sim = p_sim


## The look index for bolts of `weapon` (made on first sight), what the kernel stamps on each bolt row.
static func look_for(weapon: WeaponSpec) -> int:
	var material: Material = weapon.bolt_material if weapon.bolt_material != null else Projectile.DEFAULT_MATERIAL
	var key := "%s|%s|%d" % [weapon.bolt_length_m, weapon.bolt_radius_m, material.get_instance_id()]
	var found: Variant = _look_index.get(key)
	if found != null:
		return found
	var index: int = _looks.size()
	if index >= SimCore.LOOK_NONE:
		return SimCore.LOOK_NONE  # more looks than a byte holds: drawn by nothing
	_looks.append([weapon.bolt_length_m, weapon.bolt_radius_m, material])
	_look_index[key] = index
	return index


## Looks registered so far.
static func look_count() -> int:
	return _looks.size()


func _enter_tree() -> void:
	var passes: FramePasses = FramePasses.of(self)
	if passes != null:
		passes.add_bolt_mesh(self)


func _exit_tree() -> void:
	var passes: FramePasses = FramePasses.current()
	if passes != null:
		passes.remove_bolt_mesh(self)


## Fills the multimeshes for this frame (the frame's bolt pass, `FramePasses.update_bolts`; M4-T36's rule: no `_process`).
func update() -> void:
	instances_drawn = 0
	if _sim == null or _sim.core == null or not _sim.bolt_rows_on():
		_hide_all()
		return
	var fraction: float = Engine.get_physics_interpolation_fraction()
	for look: int in _looks.size():
		var count: int = int(_sim.core.bolt_instances(look))
		if count == 0:
			if look < _instances.size():
				_instances[look].multimesh.visible_instance_count = 0
			continue
		var instance: MultiMeshInstance3D = _instance(look, count)
		var buffer: PackedFloat32Array = _sim.core.bolt_transforms(look, fraction, Projectile.visual_scale, _child(),
				_capacity[look])
		RenderingServer.multimesh_set_buffer(instance.multimesh.get_rid(), buffer)
		instance.multimesh.visible_instance_count = count
		instances_drawn += count


# The multimesh of `look`, made on first need and grown to hold `count` instances.
func _instance(look: int, count: int) -> MultiMeshInstance3D:
	while _instances.size() <= look:
		var spec: Array = _looks[_instances.size()]
		var mesh := MultiMesh.new()
		mesh.transform_format = MultiMesh.TRANSFORM_3D
		mesh.mesh = Projectile.bolt_mesh(spec[0], spec[1], spec[2])
		# Never culled by a stale bound: the bolts are everywhere the battle is.
		mesh.custom_aabb = AABB(Vector3.ONE * -1.0e6, Vector3.ONE * 2.0e6)
		var instance := MultiMeshInstance3D.new()
		instance.name = "Look%d" % _instances.size()
		instance.multimesh = mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance, false, Node.INTERNAL_MODE_BACK)
		_instances.append(instance)
		_capacity.append(0)
	var instance: MultiMeshInstance3D = _instances[look]
	if _capacity[look] < count:
		var capacity: int = maxi(64, _capacity[look])
		while capacity < count:
			capacity *= 2
		instance.multimesh.instance_count = capacity
		_capacity[look] = capacity
	return instance


func _hide_all() -> void:
	for instance: MultiMeshInstance3D in _instances:
		instance.multimesh.visible_instance_count = 0


# The bolt capsule's basis under its node in `projectile.tscn` (the capsule's axis turned down the node's -Z), read once.
func _child() -> Basis:
	if not _child_known:
		_child_known = true
		var sample := PulseCannon.PROJECTILE_SCENE.instantiate() as Node3D
		var bolt := sample.get_node_or_null(^"Bolt") as Node3D
		if bolt != null:
			_child_basis = bolt.transform.basis
		sample.free()
	return _child_basis
