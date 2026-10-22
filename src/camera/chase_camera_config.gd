class_name ChaseCameraConfig
extends Resource
## Tunables for `ChaseCameraMath` (architecture §8). A Resource so the numbers are not literals in a node script;
## `CameraRig` owns one, overwrites `offset_local` with the hardpoints' `chase_anchor` in `setup` and keeps
## `smoothing_s` in step with the `camera_chase_smoothing_s` setting.

## Where the camera sits, in the ship's local frame. Godot forward is -Z, so +Z is behind and +Y above.
@export var offset_local: Vector3 = Vector3(0.0, 2.5, 9.0)
## The camera looks at the point this far ahead of the ship along its forward axis, so the ship sits low in frame.
@export_range(0.0, 1000.0, 0.1, "or_greater") var look_ahead_m: float = 40.0
## Time constant, s, with which the camera's orientation trails the ship's. 0 (the default) is a rigid mount: the
## camera is exactly the ship's pose times the fixed chase pose, with no lag at all. The position never lags, whatever
## this is: the camera always sits `offset_local` from the ship, only the direction of that offset may swing.
@export_range(0.0, 0.5, 0.001) var smoothing_s: float = 0.0
