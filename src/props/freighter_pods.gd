class_name FreighterPods
extends Node3D
## A freighter's cargo pods leaving it for the station's cargo bay (M7-T10, the maintainer: no loaders, the pods fly in by
## themselves). The Saturn's hull is one mesh, so while it is unloaded its hull is hidden and its break-up chunks stand in:
## the ones that are not pods ride the ship, and each pod flies from its place on the hull along the bay's path and leaves
## the world at the bay's entry. `restore` puts the hull back (the ship goes back to its pool whole).
##
## Ambient: the pods in flight have no body, target or row, and the freighter's mass and hit volumes stay as they were. A
## handful of nodes for a minute, so their motion is GDScript (`CLAUDE.md`'s split).

const POD_PREFIX: String = "pod"
## The pods leave this far apart, and fly this fast, s and m/s.
const STAGGER_S: float = 7.0
const SPEED_MPS: float = 22.0
const ACCEL_MPS2: float = 3.0

signal pod_entered(pod_name: String)

var ship: Ship = null
## The pods still on their way, and how many have gone into the bay.
var flying: Array[Dictionary] = []
var entered: int = 0
var _riding: Array[MeshInstance3D] = []
var _frame: Node3D = null
var _path: PackedVector3Array = PackedVector3Array()


## Unloads `freighter`: its pods fly along `path` (in `frame`'s space, the station) from where they sit now. Null for a
## hull without pod chunks.
static func unload(freighter: Ship, frame: Node3D, path: PackedVector3Array) -> FreighterPods:
	var hardpoints: Hardpoints = freighter.get_hardpoints()
	if hardpoints == null or path.size() < 2:
		return null
	var dir: String = ShipSpec.ASSET_ROOT.path_join(freighter.spec.asset_id)
	var pods := FreighterPods.new()
	pods.name = "FreighterPods"
	pods.ship = freighter
	pods._frame = frame
	pods._path = path
	var found: int = 0
	for entry: Dictionary in hardpoints.chunks:
		var chunk_name: String = String(entry.get("name", ""))
		var mesh: Mesh = MeshAssets.chunk_mesh(dir, String(entry.get("mesh", ""))) if entry.has("mesh") else null
		if mesh == null:
			continue
		var instance := MeshInstance3D.new()
		instance.name = chunk_name.to_pascal_case()
		instance.mesh = mesh
		var offset: Vector3 = entry.get("offset", Vector3.ZERO)
		if chunk_name.begins_with(POD_PREFIX):
			frame.add_child(instance)
			instance.global_transform = freighter.global_transform * Transform3D(Basis.IDENTITY, offset)
			pods.flying.append({"node": instance, "name": chunk_name, "wait_s": STAGGER_S * float(found), "leg": 0, "speed": 0.0})
			found += 1
		else:
			instance.position = offset
			pods.add_child(instance)
			pods._riding.append(instance)
	if found == 0:
		pods.free()
		return null
	freighter.add_child(pods)
	freighter.hull.visible = false
	return pods


func _physics_process(delta: float) -> void:
	for i: int in range(flying.size() - 1, -1, -1):
		var pod: Dictionary = flying[i]
		pod["wait_s"] = float(pod["wait_s"]) - delta
		if float(pod["wait_s"]) > 0.0:
			continue
		var node: MeshInstance3D = pod["node"]
		var speed: float = minf(float(pod["speed"]) + ACCEL_MPS2 * delta, SPEED_MPS)
		pod["speed"] = speed
		var step: float = speed * delta
		while step > 0.0 and int(pod["leg"]) < _path.size():
			var to: Vector3 = _path[int(pod["leg"])] - node.position
			if to.length() <= step:
				node.position = _path[int(pod["leg"])]
				step -= to.length()
				pod["leg"] = int(pod["leg"]) + 1
			else:
				node.position += to.normalized() * step
				step = 0.0
		if int(pod["leg"]) >= _path.size():
			node.queue_free()
			flying.remove_at(i)
			entered += 1
			pod_entered.emit(String(pod["name"]))


func _process(_delta: float) -> void:
	# The ship's own LOD switch shows the hull again when it comes back from a far dot: the stand-ins follow it.
	var far: bool = ship.is_far_dot()
	ship.hull.visible = false
	for part: MeshInstance3D in _riding:
		part.visible = not far


## Puts the hull back and removes the stand-ins and any pod still flying.
func restore() -> void:
	for pod: Dictionary in flying:
		(pod["node"] as Node).queue_free()
	flying.clear()
	if is_instance_valid(ship):
		ship.hull.visible = not ship.is_far_dot()
	queue_free()
