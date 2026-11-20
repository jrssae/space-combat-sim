class_name VortexKeepOuts
extends Node
## AI ships keep clear of jump vortices (M8-T17, maintainer 2026-11-20: "most ships avoid the vortex area when one is detected,
## for their own safety"). From the moment a vortex is announced until it folds, its funnel and `MARGIN_M` round it are a
## no-go volume for every AI pilot but the ship that opened it and the ships it carries (`JumpVortex.spares`). The avoidance
## itself is per think in the native brains (`keep_out.rs`); this node only tells them, once per change: a vortex opening or
## folding, a ship spared, the frame moving the volume.

const NODE_NAME: StringName = &"VortexKeepOuts"
## How far round the funnel a pilot keeps.
const MARGIN_M: float = 300.0
## The volumes are sent again when a vortex has drifted this far from where they were sent.
const DRIFT_M: float = 25.0
const DRIFT_MPS: float = 1.0

## Volumes sent the last time, and how many times they were sent (readouts).
var volumes: int = 0
var sends: int = 0

var _world: WorldFrame = null
var _sent_key: Array = []
var _sent_at: PackedVector3Array = PackedVector3Array()
var _sent_rest: Vector3 = Vector3.ZERO
var _host: Object = null


## The keep-outs of the World `node` is in, made on first use and woken (null outside a World).
static func wake(node: Node) -> VortexKeepOuts:
	var at: Node = node
	while at != null and not (at is WorldFrame):
		at = at.get_parent()
	if at == null:
		return null
	var found := at.get_node_or_null(NodePath(NODE_NAME)) as VortexKeepOuts
	if found == null:
		found = VortexKeepOuts.new()
		found.name = NODE_NAME
		at.add_child(found)
	found.set_physics_process(true)
	return found


## The volume a pilot keeps out of for `vortex`: the capsule round its axis, mouth to base, radius and margin.
static func volume(vortex: JumpVortex) -> Dictionary:
	var frame: Transform3D = vortex.true_frame()
	var axes: Vector2 = vortex.fit.semi_axes()
	return {"a": frame.origin, "b": frame * Vector3(0.0, 0.0, vortex.fit.depth_m), "radius": maxf(axes.x, axes.y) + MARGIN_M}


func _ready() -> void:
	_world = get_parent() as WorldFrame
	process_physics_priority = -100  # before the brains' launch, so a vortex announced this tick is avoided this tick
	DebugConsole.registry.register_provider(&"keep_out", ConsoleVars.new({
		&"volumes": {"get": func() -> int: return volumes, "doc": "Jump vortices AI pilots keep clear of now (M8-T17)"},
		&"sends": {"get": func() -> int: return sends, "doc": "Times the volumes were sent to the native brains"},
	}), self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if _host != null and is_instance_valid(_host) and volumes > 0:
		_host.set_keep_outs(PackedFloat64Array(), PackedInt64Array())


func _physics_process(_delta: float) -> void:
	var active: Array[JumpVortex] = []
	for node: Node in get_tree().get_nodes_in_group(JumpVortex.GROUP):
		var vortex := node as JumpVortex
		if vortex != null and vortex.is_active() and vortex.is_inside_tree() and vortex.fit != null:
			active.append(vortex)
	var host: Object = NativeBrains.host(get_tree())
	var key: Array = [host]
	for vortex: JumpVortex in active:
		key.append_array([vortex.get_instance_id(), vortex.openings, vortex.spared_version,
				vortex.opener.get_instance_id() if is_instance_valid(vortex.opener) else 0])
	var rest: Vector3 = _world.rest_velocity() if _world != null else Vector3.ZERO
	if key != _sent_key or rest.distance_to(_sent_rest) > DRIFT_MPS or _drifted(active):
		_send(host, active, rest)
		_sent_key = key
	if active.is_empty():
		set_physics_process(false)  # asleep until the next vortex opens


func _drifted(active: Array[JumpVortex]) -> bool:
	if active.size() != _sent_at.size():
		return true
	for i: int in active.size():
		if active[i].true_frame().origin.distance_to(_sent_at[i]) > DRIFT_M:
			return true
	return false


func _send(host: Object, active: Array[JumpVortex], rest: Vector3) -> void:
	var floats := PackedFloat64Array()
	var ids := PackedInt64Array()
	_sent_at.clear()
	for vortex: JumpVortex in active:
		var v: Dictionary = volume(vortex)
		var a: UniversePos = _world.to_universe(v["a"]) if _world != null else UniversePos.new()
		var b: UniversePos = _world.to_universe(v["b"]) if _world != null else UniversePos.new()
		var exempt: PackedInt64Array = vortex.spared_ids()
		floats.append_array([a.x, a.y, a.z, b.x, b.y, b.z, rest.x, rest.y, rest.z, float(v["radius"]), float(exempt.size())])
		ids.append_array(exempt)
		_sent_at.append(v["a"])
	_sent_rest = rest
	volumes = active.size()
	sends += 1
	_host = host
	if host != null:
		host.set_keep_outs(floats, ids)
