class_name LightPicker
extends RefCounted
## Chooses which emitters fill the `LightRig`'s 7 omni light slots (the 8th light, the key star, is always on; architecture §7.3).
## Ranking by energy x range now and then would miss a short muzzle flash and let a far explosion push out the player's nozzles;
## this ranks every frame by what the camera will notice, and holds on to a pick so slots do not flicker. Pure.

const SLOT_COUNT: int = 7
## An incumbent's score counts this much more, so a light only swaps out for one clearly better.
const INCUMBENT_BONUS: float = 1.2
## Closer than this counts as this far: an emitter at the camera must not dwarf everything by a division by nearly nothing.
const MIN_DISTANCE_M: float = 1.0

# One entry per slot (null = free). An emitter stays in its slot while it is picked.
var _slots: Array[LightEmitter] = []


func _init() -> void:
	_slots.resize(SLOT_COUNT)


## How much the camera will notice an emitter.
static func score(emitter: LightEmitter, camera_position: Vector3) -> float:
	var distance_sq: float = maxf(emitter.position.distance_squared_to(camera_position), MIN_DISTANCE_M * MIN_DISTANCE_M)
	return emitter.priority * emitter.energy * emitter.omni_range / distance_sq


## This frame's slots, one entry per slot (null = dark): the highest-scoring lit emitters, each one that stays keeping its slot.
## The returned array is the picker's own; read it, do not keep it.
func pick(candidates: Array[LightEmitter], camera_position: Vector3) -> Array[LightEmitter]:
	var best: Array[LightEmitter] = _highest(candidates, camera_position)
	for i: int in SLOT_COUNT:
		if _slots[i] != null and not best.has(_slots[i]):
			_slots[i] = null
	for emitter: LightEmitter in best:
		if not _slots.has(emitter):
			_slots[_slots.find(null)] = emitter
	return _slots


# The top `SLOT_COUNT` lit candidates, best first; the order of equal scores is the candidates' own. A short insertion list, so the
# cost per candidate stays small when there are hundreds of them.
func _highest(candidates: Array[LightEmitter], camera_position: Vector3) -> Array[LightEmitter]:
	var best: Array[LightEmitter] = []
	var scores: PackedFloat64Array = PackedFloat64Array()
	for emitter: LightEmitter in candidates:
		if emitter.energy <= 0.0:
			continue
		var value: float = score(emitter, camera_position)
		if _slots.has(emitter):
			value *= INCUMBENT_BONUS
		if best.size() == SLOT_COUNT and value <= scores[SLOT_COUNT - 1]:
			continue
		var at: int = best.size()
		while at > 0 and value > scores[at - 1]:
			at -= 1
		best.insert(at, emitter)
		scores.insert(at, value)
		if best.size() > SLOT_COUNT:
			best.resize(SLOT_COUNT)
			scores.resize(SLOT_COUNT)
	return best
