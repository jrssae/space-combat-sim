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
## Under TAA (`set_motion_vectors`, M4-T38) every bolt material draws opaque, so a bolt writes its own motion vector instead
## of the sky's behind it (an additive bolt keeps about 3 % of its light under TAA, an opaque one most of it), and a bolt new
## to its slot is drawn collapsed for its first frame (`BoltSlotQuarantine`), so no slot's last frame belongs to another bolt.
##
## Looks are registered once per weapon spec (`look_for`), shared by the cannon kernel and the stand-ins; a bolt a node
## draws (a beam, a missile) has `SimCore.LOOK_NONE`.

## The looks seen so far: `[length_m, radius_m, material]` by index.
static var _looks: Array[Array] = []
static var _look_index: Dictionary = {}
## Bolts write motion vectors (opaque materials, quarantined slots): on under TAA.
static var _motion_vectors: bool = false
## The bolt materials' own transparency and blend, kept while they are made opaque: `[transparency, blend_mode]` by material.
static var _additive_looks: Dictionary = {}
## Bolts drawn collapsed in the last frame because they were new to their slot (a readout, `aa.bolts_collapsed`).
static var collapsed_last_frame: int = 0

## Instances drawn in the last frame, over every look (a readout).
var instances_drawn: int = 0

var _sim: SimCore = null
var _instances: Array[MultiMeshInstance3D] = []
var _capacity: PackedInt32Array = PackedInt32Array()
var _child_basis: Basis = Basis.IDENTITY
var _child_known: bool = false
var _quarantine: BoltSlotQuarantine = null


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
	if _motion_vectors:
		_make_opaque(material)
	return index


## Whether bolts write motion vectors now.
static func motion_vectors() -> bool:
	return _motion_vectors


## Bolts write their motion vectors (`on`, for TAA) or draw as they were approved, additive. Covers every bolt material:
## the default, each registered look's and the node bolts' (`Projectile.bolt_materials`).
static func set_motion_vectors(on: bool) -> void:
	_motion_vectors = on
	var materials: Array[Material] = Projectile.bolt_materials()
	for look: Array in _looks:
		if not materials.has(look[2]):
			materials.append(look[2])
	for material: Material in materials:
		if on:
			_make_opaque(material)
		else:
			_restore(material)


static func _make_opaque(material: Material) -> void:
	var base := material as BaseMaterial3D
	if base == null or _additive_looks.has(base):
		return
	_additive_looks[base] = [base.transparency, base.blend_mode]
	base.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	base.blend_mode = BaseMaterial3D.BLEND_MODE_MIX


static func _restore(material: Material) -> void:
	var base := material as BaseMaterial3D
	if base == null or not _additive_looks.has(base):
		return
	var kept: Array = _additive_looks[base]
	base.transparency = kept[0]
	base.blend_mode = kept[1]
	_additive_looks.erase(base)


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
	if not _motion_vectors:
		_quarantine = null
	if _sim == null or _sim.core == null or not _sim.bolt_rows_on():
		_hide_all()
		return
	var fraction: float = Engine.get_physics_interpolation_fraction()
	var collapsed: int = 0
	for look: int in _looks.size():
		var count: int = int(_sim.core.bolt_instances(look))
		if count == 0:
			if look < _instances.size():
				_instances[look].multimesh.visible_instance_count = 0
			if _motion_vectors:
				_quarantined().filter(look, PackedFloat32Array())  # drawn empty: every slot starts afresh
			continue
		var grown: bool = look >= _capacity.size() or _capacity[look] < count
		var instance: MultiMeshInstance3D = _instance(look, count)
		if grown and _motion_vectors:
			_quarantined().filter(look, PackedFloat32Array())  # a new buffer has no last frame to pair with
		var buffer: PackedFloat32Array = _sim.core.bolt_transforms(look, fraction, Projectile.visual_scale, _child(),
				_capacity[look])
		if _motion_vectors:
			buffer = _quarantined().filter(look, buffer)
			collapsed += _quarantine.collapsed
		RenderingServer.multimesh_set_buffer(instance.multimesh.get_rid(), buffer)
		instance.multimesh.visible_instance_count = count
		instances_drawn += count
	collapsed_last_frame = collapsed


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


# The slot check for the frames bolts write motion vectors; forgotten while they do not, so a later switch starts afresh.
func _quarantined() -> BoltSlotQuarantine:
	if _quarantine == null:
		# The bolt flies along its node's -Z; in the instance's own frame that is the capsule's basis turned back.
		_quarantine = BoltSlotQuarantine.new(_child().inverse() * Vector3(0, 0, -1))
	return _quarantine


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
