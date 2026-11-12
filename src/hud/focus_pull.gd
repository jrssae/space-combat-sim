class_name FocusPull
extends RefCounted
## How far the play view is out of focus while a radial menu is open (architecture §18.21, M5-T44): 0 sharp, 1 full pull.
## Progress moves at a fixed rate toward open or closed, so a reversal mid-way starts from where it is and never jumps.

## Seconds from sharp to full pull, and back.
const DURATION_S: float = 0.2

var _t: float = 0.0
var _open: bool = false


func set_open(open: bool) -> void:
	_open = open


func is_open() -> bool:
	return _open


## Moves the pull by `dt` real seconds.
func advance(dt: float) -> void:
	var step: float = maxf(dt, 0.0) / DURATION_S
	_t = clampf(_t + (step if _open else -step), 0.0, 1.0)


## The eased amount, 0..1.
func amount() -> float:
	return _t * _t * (3.0 - 2.0 * _t)


## Closed and fully back in focus: nothing to draw.
func at_rest() -> bool:
	return not _open and _t <= 0.0
