class_name CargoPodRig
extends Node3D
## The cargo pod's model with movable arms (M7-T33, for T34): the skinned `cargo_pod_craft` glb under this node, posed from three
## numbers by `CargoPodPose`. A visual only: call `set_pose` from `_process`; the craft's motion is its owner's.

const ASSET_ID: String = "cargo_pod_craft"

var pose: CargoPodPose = null
var extend: float = 0.0
var wrist_deg: float = 0.0
var jaw_open: float = 1.0

var _skeleton: Skeleton3D = null
var _grips: Dictionary = {}  # side -> [bone, rest point]


## Builds the model from the generated asset under `asset_root`; false when it is missing or not imported.
func build(asset_root: String = ShipSpec.ASSET_ROOT) -> bool:
	var manifest: Dictionary = MeshAssets.read_manifest(ASSET_ID, asset_root)
	if MeshAssets.for_asset(ASSET_ID, asset_root) == null:  # puts the textured materials on the imported mesh
		return false
	var path: String = asset_root.path_join(ASSET_ID).path_join(String((manifest.get("mesh", {}) as Dictionary).get("file", "")))
	var scene := load(path) as PackedScene
	if scene == null:
		return false
	var model: Node = scene.instantiate()
	add_child(model)
	_skeleton = _find_skeleton(model)
	pose = CargoPodPose.from_rig(manifest.get("rig", {}))
	_grips.clear()
	var hardpoints: Dictionary = _read_json(asset_root.path_join(ASSET_ID).path_join("hardpoints.json"))
	for grip: Dictionary in hardpoints.get("grips", []):
		var p: Array = grip.get("position", [0.0, 0.0, 0.0])
		_grips[String(grip["name"]).trim_prefix("grip_")] = [String(grip.get("bone", "")), Vector3(float(p[0]), float(p[1]), float(p[2]))]
	set_pose(0.0, 0.0, 1.0)
	return _skeleton != null


## Poses both arms: `p_extend` 0..1 of the barrels' reach, `p_wrist_deg` the hands' pitch (up positive), `p_jaw_open` 1 open to 0 shut.
func set_pose(p_extend: float, p_wrist_deg: float, p_jaw_open: float) -> void:
	extend = p_extend
	wrist_deg = p_wrist_deg
	jaw_open = p_jaw_open
	if _skeleton == null or pose == null:
		return
	var deltas: Dictionary = pose.bone_deltas(extend, wrist_deg, jaw_open)
	for bone: String in deltas:
		var index: int = _skeleton.find_bone(bone)
		if index >= 0:
			_skeleton.set_bone_pose(index, _skeleton.get_bone_rest(index) * (deltas[bone] as Transform3D))


## Where a hand's grip point is now (`side` "r" or "l"), in this node's frame; the origin when the hand is unknown.
func grip_point(side: String) -> Vector3:
	if pose == null or not _grips.has(side):
		return Vector3.ZERO
	var grip: Array = _grips[side]
	return pose.point_on(String(grip[0]), grip[1] as Vector3, pose.bone_deltas(extend, wrist_deg, jaw_open))


func skeleton() -> Skeleton3D:
	return _skeleton


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


static func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	return data if data is Dictionary else {}
