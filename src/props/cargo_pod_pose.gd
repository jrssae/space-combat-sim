class_name CargoPodPose
extends RefCounted
## The cargo pod's arm pose (M7-T33, for T34): from three numbers (how far the barrels reach, the wrist's angle and how open the
## jaws are) to each joint's turn and slide, and to where a hand's grip point ends up. Pure maths on the manifest's `rig`, so
## `CargoPodRig` only hands the results to the skeleton.
##
## Joints rest without turning (the generator writes them so), the left arm mirrors the right across x, and a turn about x reads
## the same on both sides, so one set of numbers poses both arms alike.

## Each bone by name: its parent's name ("" for the root) and its rest position in the craft's frame.
var parents: Dictionary = {}
var rest_positions: Dictionary = {}
var extend_m: float = 1.0
var wrist_limit_deg: float = 45.0
var jaw_close_deg: float = 15.5


## The pose maths for a manifest's `rig` section; empty (no bones) when the section is missing.
static func from_rig(rig: Dictionary) -> CargoPodPose:
	var pose := CargoPodPose.new()
	var bones: Array = rig.get("bones", [])
	var names: Array[String] = []
	for bone: Dictionary in bones:
		names.append(String(bone.get("name", "")))
	for bone: Dictionary in bones:
		var parent: int = int(bone.get("parent", -1))
		var p: Array = bone.get("position", [0.0, 0.0, 0.0])
		pose.parents[String(bone["name"])] = names[parent] if parent >= 0 else ""
		pose.rest_positions[String(bone["name"])] = Vector3(float(p[0]), float(p[1]), float(p[2]))
	pose.extend_m = float(rig.get("extend_m", pose.extend_m))
	pose.wrist_limit_deg = float(rig.get("wrist_limit_deg", pose.wrist_limit_deg))
	pose.jaw_close_deg = float(rig.get("jaw_close_deg", pose.jaw_close_deg))
	return pose


## Each moving bone's change from rest, as a transform in its own frame: the reach slides forward (-z) by `extend` (0..1) of its
## travel, the wrist turns about x by `wrist_deg` (up is positive, within the limit), and the jaws turn toward each other as
## `jaw_open` goes from 1 (rest, as the reference model holds them) to 0 (tips together).
func bone_deltas(extend: float, wrist_deg: float, jaw_open: float) -> Dictionary:
	var slide := Vector3(0.0, 0.0, -clampf(extend, 0.0, 1.0) * extend_m)
	var wrist := Basis(Vector3.RIGHT, deg_to_rad(clampf(wrist_deg, -wrist_limit_deg, wrist_limit_deg)))
	var close: float = deg_to_rad((1.0 - clampf(jaw_open, 0.0, 1.0)) * jaw_close_deg)
	var out: Dictionary = {}
	for side: String in ["r", "l"]:
		if not rest_positions.has("reach_" + side):
			continue
		out["reach_" + side] = Transform3D(Basis.IDENTITY, slide)
		out["wrist_" + side] = Transform3D(wrist, Vector3.ZERO)
		out["jaw_up_" + side] = Transform3D(Basis(Vector3.RIGHT, -close), Vector3.ZERO)  # the upper jaw's tip comes down
		out["jaw_lo_" + side] = Transform3D(Basis(Vector3.RIGHT, close), Vector3.ZERO)
	return out


## A bone's frame in the craft's frame under the pose (`deltas` from `bone_deltas`).
func bone_global(bone: String, deltas: Dictionary) -> Transform3D:
	var local := Transform3D(Basis.IDENTITY, rest_positions.get(bone, Vector3.ZERO))
	var parent: String = String(parents.get(bone, ""))
	if parent != "":
		local.origin -= rest_positions.get(parent, Vector3.ZERO)
		local = bone_global(parent, deltas) * local
	return local * (deltas.get(bone, Transform3D.IDENTITY) as Transform3D)


## Where a point that rides `bone` (given at rest, in the craft's frame) is under the pose: a hand's grip point on its wrist.
func point_on(bone: String, rest_point: Vector3, deltas: Dictionary) -> Vector3:
	return bone_global(bone, deltas) * (rest_point - (rest_positions.get(bone, Vector3.ZERO) as Vector3))
