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
# The native core's slot test (`bolt_quarantine`), a pure function of its arguments; the pass over the slots runs there.
var _kernel: Object = ClassDB.instantiate(SimCore.NATIVE_CLASS)


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
	var result: Array = _kernel.bolt_quarantine(buffer, last, _forward)
	collapsed = result[1]
	return result[0]
