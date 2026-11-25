class_name ShotTails
extends RefCounted
## One voice per gun-firing ship (M10-T87, Q82): a shot rings for its full length, but when the same ship fires again the
## previous shot's tail fades out in `FADE_S`, so a ship holds at most two voices and rapid fire stays crisp. Pure
## bookkeeping over the `AudioDirector`'s voice slots; the director applies the gains and stops a voice whose fade ended.

## How long a cut-off tail takes to fade out, s (an eighth of a second between shots at 8 a second).
const FADE_S: float = 0.04
const SILENT_DB: float = -60.0

var _owner: PackedInt64Array  # per voice: the ship whose shot it plays, 0 for any other sound
var _left: PackedFloat32Array  # per voice: fade time left, 0 when not fading


func _init(voices: int) -> void:
	_owner.resize(voices)
	_left.resize(voices)


## A voice starts a new sound for `owner` (0: no ship). Returns the voice now fading as that ship's old tail, or -1.
func claim(voice: int, owner: int) -> int:
	_left[voice] = 0.0
	_owner[voice] = owner
	if owner == 0:
		return -1
	for i: int in _owner.size():
		if i != voice and _owner[i] == owner:
			_owner[i] = 0
			_left[i] = FADE_S
			return i
	return -1


func is_fading(voice: int) -> bool:
	return _left[voice] > 0.0


## The fading voice's gain against its own level, dB (0 when not fading).
func gain_db(voice: int) -> float:
	if _left[voice] <= 0.0:
		return 0.0
	return maxf(linear_to_db(_left[voice] / FADE_S), SILENT_DB)


## Advances the fades. Returns the voices whose fade ended this step (to stop).
func step(delta: float) -> PackedInt32Array:
	var ended := PackedInt32Array()
	for i: int in _left.size():
		if _left[i] > 0.0:
			_left[i] = maxf(_left[i] - delta, 0.0)
			if _left[i] == 0.0:
				ended.append(i)
	return ended


## Voices fading now (tests, console).
func fading_count() -> int:
	var n: int = 0
	for left: float in _left:
		n += 1 if left > 0.0 else 0
	return n
