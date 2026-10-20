class_name ChaseCameraConfig
extends Resource
## Tunables for `ChaseCameraMath` (architecture §8). A Resource so the numbers are not literals in a node script;
## `CameraRig` owns one and overwrites `offset_local` with the hardpoints' `chase_anchor` in `setup`.

## Where the camera sits, in the ship's local frame. Godot forward is -Z, so +Z is behind and +Y above.
@export var offset_local: Vector3 = Vector3(0.0, 2.5, 9.0)
## The camera looks at the point this far ahead of the ship along its forward axis, so the ship sits low in frame.
@export_range(0.0, 1000.0, 0.1, "or_greater") var look_ahead_m: float = 40.0
## Seconds for the position error to halve. 0 snaps.
@export_range(0.0, 2.0, 0.001, "or_greater") var position_half_life_s: float = 0.08
## Seconds for the rotation error to halve. 0 snaps.
@export_range(0.0, 2.0, 0.001, "or_greater") var rotation_half_life_s: float = 0.12
