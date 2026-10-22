class_name CameraLook
extends RefCounted
## Free look (architecture §6.1, §8), pure: where the pilot is looking relative to the ship's nose, as a yaw and a pitch in
## degrees (yaw right, pitch up). Held (L3 on a pad, the middle mouse button) it follows the right stick, which gives an
## absolute direction (stick right = look right, centre = look ahead), or the mouse, which turns the view by its travel;
## released, the view eases back to centre. The ship is not involved: the camera turns, the flight command does not.
##
## `step` is called once per physics tick with the tick's input and returns nothing; `yaw_deg` / `pitch_deg` are the goal the
## rig smooths toward every rendered frame.

enum Driver { NONE, STICK, MOUSE }

## Share of the way back to centre covered per second once released (exponential).
const RETURN_RATE_PER_S: float = 9.0
## Degrees per second the view swings toward a held stick direction.
const STICK_SWING_DEG_S: float = 540.0
const STICK_EPS: float = 0.001

var yaw_deg: float = 0.0
var pitch_deg: float = 0.0
## Largest look angles: the cockpit turns the head, the chase view orbits the whole ship.
var max_yaw_deg: float = 135.0
var max_pitch_deg: float = 80.0

var _driver: Driver = Driver.NONE


## Sets the limits for a camera mode (`cockpit` true = the pilot's head, false = orbit around the ship).
func set_mode(cockpit: bool) -> void:
	max_yaw_deg = 135.0 if cockpit else 180.0
	max_pitch_deg = 80.0
	yaw_deg = clampf(yaw_deg, -max_yaw_deg, max_yaw_deg)
	pitch_deg = clampf(pitch_deg, -max_pitch_deg, max_pitch_deg)


## One tick. `stick` is the look stick (x right, y up, -1..1), `mouse_px` the mouse travel this tick (x right, y up) and
## `deg_per_px` its gain.
func step(dt: float, active: bool, stick: Vector2, mouse_px: Vector2, deg_per_px: float) -> void:
	if not active:
		_driver = Driver.NONE
		_ease_to_centre(dt)
		return
	if stick.length() > STICK_EPS:
		_driver = Driver.STICK
		var goal := Vector2(stick.x * max_yaw_deg, stick.y * max_pitch_deg)
		var here := Vector2(yaw_deg, pitch_deg)
		var moved: Vector2 = here.move_toward(goal, STICK_SWING_DEG_S * maxf(dt, 0.0))
		yaw_deg = moved.x
		pitch_deg = moved.y
	elif mouse_px != Vector2.ZERO:
		_driver = Driver.MOUSE
		yaw_deg = clampf(yaw_deg + mouse_px.x * deg_per_px, -max_yaw_deg, max_yaw_deg)
		pitch_deg = clampf(pitch_deg + mouse_px.y * deg_per_px, -max_pitch_deg, max_pitch_deg)
	elif _driver == Driver.STICK:
		_ease_to_centre(dt)  # the stick went back to centre: so does the view (a mouse look holds where it is)


## The view rotation relative to the ship: yaw about the ship's up (right = clockwise from above), then pitch about the
## ship's right.
func look_basis() -> Basis:
	return Basis(Vector3.UP, -deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))


func is_centred() -> bool:
	return absf(yaw_deg) < 0.01 and absf(pitch_deg) < 0.01


func reset() -> void:
	yaw_deg = 0.0
	pitch_deg = 0.0
	_driver = Driver.NONE


func _ease_to_centre(dt: float) -> void:
	var k: float = 1.0 - exp(-RETURN_RATE_PER_S * maxf(dt, 0.0))
	yaw_deg = lerpf(yaw_deg, 0.0, k)
	pitch_deg = lerpf(pitch_deg, 0.0, k)
	if is_centred():
		yaw_deg = 0.0
		pitch_deg = 0.0
