class_name BreakupPlan
extends RefCounted
## When and how each chunk of a Starfury leaves its wreck (M3-T28, architecture §15.7): the part hit last goes at the instant
## of death, the rest one at a time over the next second. Everything is drawn from the seed up front, so the same seed gives
## the same break-up and a test can read it. Pure; nothing here reads a clock.

## The others leave between `STAGE_START_S` and about `STAGE_START_S + STAGE_SPAN_S` (plus the jitter): all gone inside 1.2 s.
const STAGE_START_S: float = 0.2
const STAGE_SPAN_S: float = 0.75
const JITTER_S: float = 0.05
## Separation speed of a chunk (the old range) and of the one that leaves first.
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
		plan.spin[chunk] = axis * deg_to_rad(rng.randf_range(0.0, DebrisPool.MAX_SPIN_DEG_S))
		plan.vent_roll[chunk] = rng.randf()
	return plan
