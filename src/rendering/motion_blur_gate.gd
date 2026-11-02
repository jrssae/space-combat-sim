class_name MotionBlurGate
extends RefCounted
## The blur strength the effect gets each rendered frame. A rebase moves the camera and every hull by kilometres in one tick, so
## the velocity the renderer reports for the frames around it is nonsense; the gate blanks those frames and lets the rest through.

## Frames left unblurred after a rebase: the one that draws the shifted world, and one more for the previous-frame transforms
## the renderer still holds.
const SKIP_FRAMES_AFTER_REBASE: int = 2

var _skip: int = 0


## A rebase happened: blank the next frames.
func note_rebase() -> void:
	_skip = SKIP_FRAMES_AFTER_REBASE


## Frames still to blank.
func skipping() -> int:
	return _skip


## The strength for this rendered frame (0-1), 0 while a rebase's frames run out. Call once per frame, blur on or off.
func take(strength: float) -> float:
	if _skip > 0:
		_skip -= 1
		return 0.0
	return clampf(strength, 0.0, 1.0)
