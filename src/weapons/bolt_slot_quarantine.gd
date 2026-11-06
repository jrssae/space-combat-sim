class_name BoltSlotQuarantine
extends RefCounted
## Keeps the bolts' motion vectors honest (M4-T38, from T35's re-review). The renderer pairs a multimesh instance with what
## the same instance held in the last drawn frame. The core reuses a freed draw slot at once, so a new bolt could inherit
## another bolt's last place (a smear across the screen) or an empty slot's zeros (a vector from the world origin, NaN at
## the camera). This draws a bolt that is new to its slot collapsed at its own place for one frame, so the slot is drawn
## empty before its new occupant shows and the occupant's first vector starts where it is. Used only while the bolts write
## motion vectors (under TAA); it costs a pass over the slots each frame.
##
## A slot keeps its occupant from one frame to the next when its basis's first row is unchanged (a bolt flies straight, so its
## basis never changes) and the move runs forward along its flight, no further than `MAX_STEP_M` and with almost nothing to the
## side. The same cannon's next shot (same basis, starting behind) and a wingman's bolt flying the same way (beside it) are new.

## The furthest a bolt flies between two drawn frames: 1 000 m/s through a quarter-second frame.
const MAX_STEP_M: float = 250.0
## How far off its line of flight a kept bolt may be drawn, m, plus this share of its move (float rounding of the rows).
const SIDE_SLACK_M: float = 0.05
const SIDE_SLACK_SHARE: float = 0.01

## Slots drawn collapsed in the last `filter` call, over every look since the last reset.
var collapsed: int = 0

var _forward: Vector3
var _last: Dictionary[int, PackedFloat32Array] = {}


## `forward` is the bolts' flight direction in an instance's own frame.
func _init(forward: Vector3 = Vector3(0, 0, -1)) -> void:
	_forward = forward


func reset() -> void:
	_last.clear()
	collapsed = 0


## The buffer to draw for `look` this frame: `buffer` (12 floats a slot, as the core writes it, left untouched) with every
## slot whose occupant is new since the last call collapsed to a point at its place.
func filter(look: int, buffer: PackedFloat32Array) -> PackedFloat32Array:
	var last: PackedFloat32Array = _last.get(look, PackedFloat32Array())
	_last[look] = buffer
	var out: PackedFloat32Array = buffer.duplicate()
	var fx: float = _forward.x
	var fy: float = _forward.y
	var fz: float = _forward.z
	var known: int = last.size()
	var end: int = buffer.size()
	var count: int = 0
	var b: int = 0
	while b < end:
		var r0x: float = buffer[b]
		var r0y: float = buffer[b + 1]
		var r0z: float = buffer[b + 2]
		if r0x != 0.0 or r0y != 0.0 or r0z != 0.0:
			var kept: bool = b < known and r0x == last[b] and r0y == last[b + 1] and r0z == last[b + 2]
			if kept:
				# The flight direction in the world (scaled like the basis) and the move since the last frame.
				var wx: float = r0x * fx + r0y * fy + r0z * fz
				var wy: float = buffer[b + 4] * fx + buffer[b + 5] * fy + buffer[b + 6] * fz
				var wz: float = buffer[b + 8] * fx + buffer[b + 9] * fy + buffer[b + 10] * fz
				var dx: float = buffer[b + 3] - last[b + 3]
				var dy: float = buffer[b + 7] - last[b + 7]
				var dz: float = buffer[b + 11] - last[b + 11]
				var w2: float = wx * wx + wy * wy + wz * wz
				var d2: float = dx * dx + dy * dy + dz * dz
				var along: float = dx * wx + dy * wy + dz * wz
				var side2: float = d2 - along * along / maxf(w2, 1e-12)
				var slack: float = SIDE_SLACK_M + SIDE_SLACK_SHARE * sqrt(d2)
				kept = along >= 0.0 and d2 <= MAX_STEP_M * MAX_STEP_M and side2 <= slack * slack
			if not kept:
				count += 1
				out[b] = 0.0
				out[b + 1] = 0.0
				out[b + 2] = 0.0
				out[b + 4] = 0.0
				out[b + 5] = 0.0
				out[b + 6] = 0.0
				out[b + 8] = 0.0
				out[b + 9] = 0.0
				out[b + 10] = 0.0
		b += 12
	collapsed = count
	return out
