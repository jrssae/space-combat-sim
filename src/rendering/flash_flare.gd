class_name FlashFlare
extends RefCounted
## The one lens flare the jump flashes share (M7-T23): every flash showing offers itself each frame, and `PostEffects` gives the
## brightest to a second pass of the lens flare. One flare however many jump points flash, so a battle's hundred points cost one
## pass at most. Offers last a frame (the offering and the reading nodes may run in either order).

## Below this weight no flare is drawn.
const MIN_WEIGHT: float = 0.02

static var _frame: int = -1
static var _now: Array = [0.0, Vector3.ZERO, Color.WHITE]
static var _before: Array = [0.0, Vector3.ZERO, Color.WHITE]


## Offers a flash at `position` (World frame) of `colour` (linear); `weight` is its flare's strength, 0 to about 1.
static func offer(position: Vector3, colour: Color, weight: float, frame: int = Engine.get_process_frames()) -> void:
	_roll(frame)
	if weight > float(_now[0]):
		_now = [weight, position, colour]


## The brightest flash offered this frame or the last: its weight (0 for none), position and colour.
static func brightest(frame: int = Engine.get_process_frames()) -> Array:
	_roll(frame)
	return _now if float(_now[0]) >= float(_before[0]) else _before


## How far a flash's size on screen lets its flare through: nothing under `from_px`, whole from `full_px`.
static func by_size(radius_px: float, from_px: float, full_px: float) -> float:
	return smoothstep(from_px, maxf(full_px, from_px + 1e-3), radius_px)


static func clear() -> void:
	_frame = -1
	_now = [0.0, Vector3.ZERO, Color.WHITE]
	_before = [0.0, Vector3.ZERO, Color.WHITE]


# Ages the offers: this frame's become the last frame's, older ones go.
static func _roll(frame: int) -> void:
	if frame == _frame:
		return
	_before = _now if frame == _frame + 1 else [0.0, Vector3.ZERO, Color.WHITE]
	_now = [0.0, Vector3.ZERO, Color.WHITE]
	_frame = frame
