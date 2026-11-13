class_name HangarCamera
extends RefCounted
## The front end's camera in the Cobra-bay hangar (M7-T09, M7-T20; D77): a slow dolly up and down a rail beside the racked
## fighters, looking ahead along the hall and across at the racks, with a gentle sway. `wide`, `close`, `rack` (the six racks) and
## `second` (the second row) are fixed views for the look sheets, as the manifest gives them. Pure, so the move is tested without
## the hangar.

enum View { MOVE, WIDE, CLOSE, RACK, SECOND }

const VIEW_KEYS: Array[String] = ["move", "wide", "close", "rack", "second"]
## One trip down the rail and back.
const PERIOD_S: float = 240.0
## Where the camera looks: this far ahead along the hall (toward the rail's `look_dir`), toward its `look_x` across it (so the
## racks run from the frame's right side, clear of the menu, to the middle), and this high above the racks' line.
const LOOK_AHEAD_M: float = 30.0
const LOOK_RISE_M: float = 1.5
## The sway on top of the dolly: height and yaw, each a slow sine.
const BOB_M: float = 0.6
const BOB_RATE: float = 0.05
const SWAY_DEG: float = 3.0
const SWAY_RATE: float = 0.031

var rail_x: float = -12.0
var rail_y: float = 7.5
var z_from: float = -43.5
var z_to: float = 69.0
var look_x: float = -6.0
## -1: the camera looks toward the arm's head (-z) and starts at the root end; +1 the other way.
var look_dir: float = -1.0
## The racked fighters' height (the line the camera looks along).
var rack_y: float = 9.0
## The fixed views by key: {"at": [x, y, z], "look": [x, y, z]}.
var views: Dictionary = {}


## A camera for the manifest's `camera` and `fighters` (`b5_interior`).
static func from_manifest(manifest: Dictionary) -> HangarCamera:
	var out := HangarCamera.new()
	var camera: Dictionary = manifest.get("camera", {})
	var rail: Dictionary = camera.get("rail", {})
	out.rail_x = float(rail.get("x", out.rail_x))
	out.rail_y = float(rail.get("y", out.rail_y))
	out.z_from = float(rail.get("z_from", out.z_from))
	out.z_to = float(rail.get("z_to", out.z_to))
	out.look_x = float(rail.get("look_x", out.look_x))
	out.look_dir = signf(float(rail.get("look_dir", out.look_dir)))
	out.views = camera.get("views", {})
	for fighter: Dictionary in manifest.get("fighters", []):
		if int(fighter.get("wave", 1)) == 1:
			out.rack_y = float((fighter.get("position", [0.0, 9.0, 0.0]) as Array)[1])
	return out


## Where the camera is and where it looks, `elapsed_s` into the move, or in one of the fixed views.
func pose(elapsed_s: float, view: View = View.MOVE) -> Transform3D:
	var fixed: Dictionary = views.get(VIEW_KEYS[view], {})
	if view != View.MOVE and not fixed.is_empty():
		return _looking(_vec(fixed["at"]), _vec(fixed["look"]))
	var mid: float = 0.5 * (z_from + z_to)
	var half: float = 0.5 * (z_to - z_from)
	# Starts at the end it looks away from, so it begins with the whole row ahead; eases in and out at both ends.
	var z: float = mid - look_dir * half * cos(TAU * elapsed_s / PERIOD_S)
	var at := Vector3(rail_x, rail_y + BOB_M * sin(elapsed_s * BOB_RATE), z)
	var target := Vector3(look_x, rack_y + LOOK_RISE_M, z + look_dir * LOOK_AHEAD_M)
	var look: Transform3D = _looking(at, target)
	return Transform3D(look.basis.rotated(Vector3.UP, deg_to_rad(SWAY_DEG) * sin(elapsed_s * SWAY_RATE)), at)


func _looking(at: Vector3, target: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(target - at, Vector3.UP), at)


static func _vec(values: Variant) -> Vector3:
	var a: Array = values if values is Array else []
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a.size() >= 3 else Vector3.ZERO
