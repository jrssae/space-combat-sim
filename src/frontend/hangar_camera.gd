class_name HangarCamera
extends RefCounted
## The front end's camera in the Cobra-bay hangar (M7-T09, D77): a slow dolly up and down the rail beside the racks, looking
## ahead and across at the held fighters, with a gentle sway. `wide`, `close` and `rack` (a whole door's rack from in front)
## are fixed views for the look sheets. Pure, so the move is tested without the hangar.

enum View { MOVE, WIDE, CLOSE, RACK }

## One trip down the rail and back.
const PERIOD_S: float = 240.0
## Where the camera looks: this far ahead along the hall, this far in from the rail toward the racks (so the racks run from the
## frame's right side, clear of the menu, to the middle), and this high above the racks' line.
const LOOK_AHEAD_M: float = 30.0
const LOOK_IN_M: float = 7.0
const LOOK_RISE_M: float = 1.5
## The sway on top of the dolly: height and yaw, each a slow sine.
const BOB_M: float = 0.6
const BOB_RATE: float = 0.05
const SWAY_DEG: float = 3.0
const SWAY_RATE: float = 0.031

var rail_x: float = 31.0
var rail_y: float = 7.5
var z_from: float = -112.0
var z_to: float = 112.0
## The height of the racks' line: where the held fighters sit.
var rack_y: float = 9.0
## The racks' positions along the hall, for the close view.
var rack_z: PackedFloat64Array = PackedFloat64Array()
## The hall's size, for the wide view.
var half_width: float = 42.0
var height: float = 30.0
var end_z: float = 135.0


## A camera for the manifest's `camera.rail` and `racks` (`b5_interior`).
static func from_manifest(manifest: Dictionary) -> HangarCamera:
	var out := HangarCamera.new()
	var rail: Dictionary = (manifest.get("camera", {}) as Dictionary).get("rail", {})
	out.rail_x = float(rail.get("x", out.rail_x))
	out.rail_y = float(rail.get("y", out.rail_y))
	out.z_from = float(rail.get("z_from", out.z_from))
	out.z_to = float(rail.get("z_to", out.z_to))
	for rack: Dictionary in manifest.get("racks", []):
		var p: Array = rack.get("position", [0.0, 9.0, 0.0])
		out.rack_y = float(p[1])
		out.rack_z.append(float(p[2]))
	var hall: Dictionary = manifest.get("hall", {})
	out.half_width = float(hall.get("half_width_m", out.half_width))
	out.height = float(hall.get("height_m", out.height))
	out.end_z = float(hall.get("end_z_m", out.end_z))
	return out


## Where the camera is and where it looks, `elapsed_s` into the move, or in one of the fixed views.
func pose(elapsed_s: float, view: View = View.MOVE) -> Transform3D:
	match view:
		View.WIDE:
			return _looking(Vector3(-12.0, height - 9.0, -end_z + 6.0), Vector3(6.0, rack_y - 1.0, 0.0))
		View.CLOSE:
			var z: float = rack_z[rack_z.size() / 2] if not rack_z.is_empty() else 0.0
			return _looking(Vector3(-14.0, rack_y + 1.0, z - 16.0), Vector3(0.0, rack_y + 0.5, z))
		View.RACK:
			var z: float = rack_z[rack_z.size() / 2] if not rack_z.is_empty() else 0.0
			return _looking(Vector3(3.0, rack_y + 2.0, z - 24.0), Vector3(0.0, rack_y, z))
	var mid: float = 0.5 * (z_from + z_to)
	var half: float = 0.5 * (z_to - z_from)
	var z: float = mid - half * cos(TAU * elapsed_s / PERIOD_S)  # starts at the head end, eases in and out at both ends
	var at := Vector3(rail_x, rail_y + BOB_M * sin(elapsed_s * BOB_RATE), z)
	var target := Vector3(rail_x + signf(-rail_x) * LOOK_IN_M, rack_y + LOOK_RISE_M, z + LOOK_AHEAD_M)
	var look: Transform3D = _looking(at, target)
	return Transform3D(look.basis.rotated(Vector3.UP, deg_to_rad(SWAY_DEG) * sin(elapsed_s * SWAY_RATE)), at)


func _looking(at: Vector3, target: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(target - at, Vector3.UP), at)
