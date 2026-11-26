class_name BreakupPlan
extends RefCounted
## When and how each chunk of a dying hull leaves its wreck (M3-T28, architecture §15.7). A Starfury (`make`): the part hit
## last goes at the instant of death, the rest one at a time over the next second. A capital (`for_sections`, M10-T11, D12.8):
## its sections are its chunks; the one that blew goes first, the rest walk outward from it, nearest first, the reactors last,
## each blowing as it goes (`blast_kind`). Everything is drawn from the seed up front, so the same seed gives the same
## break-up and a test can read it. Pure; nothing here reads a clock.

## The others leave between `STAGE_START_S` and about `STAGE_START_S + STAGE_SPAN_S` (plus the jitter): all gone inside 1.2 s.
const STAGE_START_S: float = 0.2
const STAGE_SPAN_S: float = 0.75
const JITTER_S: float = 0.05
## Separation speed of a chunk (the old range) and of the one that leaves first.
## How fast a chunk may tumble.
const MAX_SPIN_DEG_S: float = 90.0
const KICK_MPS: Vector2 = Vector2(4.0, 15.0)
const FIRST_KICK_MPS: Vector2 = Vector2(11.0, 15.0)

var count: int = 0
## Chunk indices in the order they leave.
var order: PackedInt32Array = PackedInt32Array()
## Per chunk index: the time it leaves, its kick speed, its own tumble (rad/s), a unit direction used when it sits on the
## wreck's centre, and a 0-1 roll for how long it vents.
var release_s: PackedFloat64Array = PackedFloat64Array()
var kick_mps: PackedFloat64Array = PackedFloat64Array()
var spin: PackedVector3Array = PackedVector3Array()
var direction_hint: PackedVector3Array = PackedVector3Array()
var vent_roll: PackedFloat64Array = PackedFloat64Array()
## A capital's plan only (empty for a Starfury's): per chunk index, the blast it sets off as it leaves (a `BlastTable` section
## kind, `BlastTable.STRUCTURE`, or "" for none) and how long it burns once loose, s.
var blast_kind: PackedStringArray = PackedStringArray()
var fire_s: PackedFloat64Array = PackedFloat64Array()


## The plan for `p_count` chunks. `first` is the chunk that leaves first (the part the killing hit landed on), or -1 for an
## order drawn from the seed alone (a hit without a point).
static func make(p_count: int, first: int, seed_value: int) -> BreakupPlan:
	var plan := BreakupPlan.new()
	plan.count = maxi(p_count, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rest: Array[int] = []
	for i: int in plan.count:
		if i != first:
			rest.append(i)
	for i: int in range(rest.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: int = rest[i]
		rest[i] = rest[j]
		rest[j] = swap
	if first >= 0 and first < plan.count:
		plan.order.append(first)
	elif not rest.is_empty():
		plan.order.append(rest.pop_front())
	plan.order.append_array(PackedInt32Array(rest))
	plan.release_s.resize(plan.count)
	plan.kick_mps.resize(plan.count)
	plan.spin.resize(plan.count)
	plan.direction_hint.resize(plan.count)
	plan.vent_roll.resize(plan.count)
	var step: float = STAGE_SPAN_S / float(maxi(plan.count - 2, 1))
	for rank: int in plan.order.size():
		var chunk: int = plan.order[rank]
		plan.release_s[chunk] = 0.0 if rank == 0 else STAGE_START_S + float(rank - 1) * step + rng.randf_range(-JITTER_S, JITTER_S)
		var range_mps: Vector2 = FIRST_KICK_MPS if rank == 0 else KICK_MPS
		plan.kick_mps[chunk] = rng.randf_range(range_mps.x, range_mps.y)
		var hint := Vector3(rng.randfn(), rng.randfn(), rng.randfn())
		plan.direction_hint[chunk] = hint.normalized() if hint.length_squared() > 1e-9 else Vector3.UP
		var axis := Vector3(rng.randfn(), rng.randfn(), rng.randfn())
		axis = axis.normalized() if axis.length_squared() > 1e-9 else Vector3.UP
		plan.spin[chunk] = axis * deg_to_rad(rng.randf_range(0.0, MAX_SPIN_DEG_S))
		plan.vent_roll[chunk] = rng.randf()
	return plan


## A capital's plan (M10-T11): its sections' `centres` (body frame) and `kinds`, `first` the section that goes at once (the
## one that blew or was hit last), `spent` the sections that already blew (they come apart with no blast), `numbers` its
## class's `breakup` row (`step_s`, `reactor_after_s`, `kick_mps`, `spin_deg_s`, `fire_s`, `one_blast`).
static func for_sections(centres: PackedVector3Array, kinds: PackedStringArray, first: int, spent: PackedByteArray,
		numbers: Dictionary, seed_value: int) -> BreakupPlan:
	var plan := BreakupPlan.new()
	plan.count = centres.size()
	if plan.count == 0:
		return plan
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var start: int = clampi(first, 0, plan.count - 1)
	var from: Vector3 = centres[start]
	var rest: Array[int] = []
	var reactors: Array[int] = []
	for i: int in plan.count:
		if i == start:
			continue
		if kinds[i] == CapitalSection.REACTOR:
			reactors.append(i)
		else:
			rest.append(i)
	var nearest := func(a: int, b: int) -> bool:
		var da: float = centres[a].distance_squared_to(from)
		var db: float = centres[b].distance_squared_to(from)
		return da < db if da != db else a < b
	rest.sort_custom(nearest)
	reactors.sort_custom(nearest)
	plan.order.append(start)
	plan.order.append_array(PackedInt32Array(rest))
	plan.order.append_array(PackedInt32Array(reactors))
	plan.release_s.resize(plan.count)
	plan.kick_mps.resize(plan.count)
	plan.vent_roll.resize(plan.count)
	plan.fire_s.resize(plan.count)
	plan.spin.resize(plan.count)
	plan.direction_hint.resize(plan.count)
	plan.blast_kind.resize(plan.count)
	var step: Vector2 = _pair(numbers.get("step_s"), Vector2(0.5, 1.0))
	var kick: Vector2 = _pair(numbers.get("kick_mps"), KICK_MPS)
	var fire: Vector2 = _pair(numbers.get("fire_s"), Vector2.ZERO)
	var spin_max: float = deg_to_rad(float(numbers.get("spin_deg_s", 2.0)))
	var one_blast: bool = bool(numbers.get("one_blast", false))
	var t: float = 0.0
	for rank: int in plan.order.size():
		var chunk: int = plan.order[rank]
		if rank > 0:
			var first_reactor: bool = kinds[chunk] == CapitalSection.REACTOR and kinds[plan.order[rank - 1]] != CapitalSection.REACTOR
			t += float(numbers.get("reactor_after_s", step.y)) if first_reactor else rng.randf_range(step.x, step.y)
		plan.release_s[chunk] = t
		plan.kick_mps[chunk] = rng.randf_range(kick.x, kick.y)
		var hint := Vector3(rng.randfn(), rng.randfn(), rng.randfn())
		plan.direction_hint[chunk] = hint.normalized() if hint.length_squared() > 1e-9 else Vector3.UP
		var axis := Vector3(rng.randfn(), rng.randfn(), rng.randfn())
		axis = axis.normalized() if axis.length_squared() > 1e-9 else Vector3.UP
		plan.spin[chunk] = axis * rng.randf_range(0.0, spin_max)
		plan.vent_roll[chunk] = rng.randf()
		plan.fire_s[chunk] = rng.randf_range(fire.x, fire.y)
		var kind: String = kinds[chunk]
		if one_blast:
			plan.blast_kind[chunk] = (kind if BlastTable.KINDS.has(kind) else BlastTable.DEFAULT_KIND) if rank == 0 else ""
		elif rank > 0 and chunk < spent.size() and spent[chunk] != 0:
			plan.blast_kind[chunk] = ""
		else:
			plan.blast_kind[chunk] = kind if BlastTable.KINDS.has(kind) else BlastTable.STRUCTURE
	return plan


## When the last chunk leaves, s.
func span_s() -> float:
	var out: float = 0.0
	for t: float in release_s:
		out = maxf(out, t)
	return out


static func _pair(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback
