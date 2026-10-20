class_name FlightCommand
extends RefCounted
## What a pilot (player or AI) asks of the ship for one physics tick (architecture §6.2).
## Pilot terms throughout; the flight model converts them to body-frame forces.

var main_left: float = 0.0  ## 0..1, LT: both left main nozzles
var main_right: float = 0.0  ## 0..1, RT: both right main nozzles
var retro_left: float = 0.0  ## 0..1, LB (0 or 1 from a button; float keeps AI/HOTAS analog-ready)
var retro_right: float = 0.0  ## 0..1, RB
var strafe: Vector2 = Vector2.ZERO  ## x sway right, y heave up, -1..1 (radial)
var rot: Vector3 = Vector3.ZERO  ## x pitch up, y yaw right, z roll right, -1..1
var brake: bool = false  ## held: all stop (velocity and rotation), see architecture §5.5
var toggle_assist: bool = false  ## edge: true for one tick
## Body frame (+X right, +Y up, -Z forward): the direction the brake turns the nose onto; any length, zero = none.
## Not from the sticks: the Ship writes it every tick from its TargetingController (the line of sight to the selected
## target), so any pilot, player or AI, gets brake-to-face by selecting a target. Ignored unless `brake` is held.
var face_dir_b: Vector3 = Vector3.ZERO


func to_dict() -> Dictionary:
	return {
		"main_left": main_left, "main_right": main_right,
		"retro_left": retro_left, "retro_right": retro_right,
		"strafe": strafe, "rot": rot, "brake": brake, "toggle_assist": toggle_assist, "face_dir_b": face_dir_b,
	}
