class_name GateShotDirector
extends RefCounted
## Cuts the gate jump into short camera takes (M8-T29, maintainer 2026-11-19: every angle under 3 s, no two jumps alike). At the
## run-in's start it cuts the run-in into approach takes up to `GateShotPool.cut_s` and mouth takes on to the ring (the take
## holding the predicted entry is one made for it; a close take made for before it is kept there). The ring's 0.3 s flash ends
## the last mouth take with a hard cut to the arrival side, where it cuts the departure vortex's collapse and the blue one's
## opening, then the ship's burst back out, the same way. Takes come from `GateShotPool`, seeded per jump, never the same take
## twice in a row, never the last jump's opening take, and only takes whose camera stays clear of the gate, the station and the
## planets and can see the ship. `stop` ends everything in one call (a skip or an abort). Scene glue for `JumpgateHost`: the
## physics queries run on the main thread, a few hundred per stage.

## The least room the camera keeps from any collision surface, m.
const CLEAR_M: float = 40.0
## Above a planet's atmosphere by at least this, m.
const PLANET_MARGIN_M: float = 2000.0
## The clearance test samples a take this often, s.
const SAMPLE_S: float = 0.25
## From the mouth to the ring (the jump's swallow, `GateJump.SWALLOW_S`).
static var FUNNEL_S: float = GateJump.SWALLOW_S
## The ship bursts out about this long after the arrival is asked for: the arms' lead-in (the pylons' glow, from the cut), the
## blue flash and the start of the unfolding.
const OPEN_S: float = 3.8
## The way out until control returns: a second through the funnel, then 500 m on at 200 m/s (or 3 s).
const OUT_S: float = 3.5
## A take before the entry gives way this long before it; a cut this soon after it still counts as the entry's.
const ENTRY_LEAD_S: float = 0.2
const ENTRY_LATE_S: float = 0.5
## On the way back a take tagged `after` waits this long, until the blue vortex is opening.
const OPEN_LATE_S: float = 1.5
## A take may lose sight of the ship behind something for at most this share of its samples.
const MAX_BLOCKED_SHARE: float = 0.2
## What a camera keeps clear of and cannot see through: the gate's arms, the station, rocks and capital hulls.
const SOLID_MASK: int = CollisionLayers.ROCK | CollisionLayers.CAPITAL

var pool: GateShotPool = GateShotPool.load_file()
## Jumps begun so far (each jump's seed), and the opening takes of the last jump's run-in and way back out.
var picks: int = 0
var last_opening: String = ""
var last_arrival_opening: String = ""
## Takes every jump opens its run-in and its way out with instead of a pick (`gate shots`, for captures and look reviews).
var pinned: PackedStringArray = PackedStringArray()
var pinned_arrival: String = ""
## This jump's takes in order: `{slot, id, at_s}`, `at_s` on the stage's clock.
var played: Array[Dictionary] = []
## Seconds into the current stage (the run-in with its ring, or the way back).
var clock_s: float = 0.0

var _rng := RandomNumberGenerator.new()
var _ctx: Dictionary = {}
var _segments: Array[Dictionary] = []  # this stage's `{slot, end}` in order; the last runs on past its end if it must
var _arrival_s: float = INF  # the predicted entry, on the run-in's clock
var _next_cut: float = INF  # when the take on screen gives way
var _stage: StringName = &""  # the slot of the take on screen
var _take_at: float = 0.0
var _holding: bool = false  # the ring's flash: no more cuts until the arrival side
var _clear: Dictionary = {}  # "slot/id" -> bool, per stage


## Starts the run-in's takes. `ctx`: `gate` (Jumpgate), `ship` (Ship), `axis` (World, unit, the way in), `to_plane_m`,
## `speed_mps` (along the axis), `open_in_s`, `capability`, `arrival_s` (predicted), `gate_actor` (the gate's name in the takes),
## `space` (PhysicsDirectSpaceState3D or null), `planet` (ReferenceFrame.Candidate or null), `seed_extra` (an int that varies
## between sessions, so a session's first jump is not always cut alike). Returns the opening take's id.
func begin(ctx: Dictionary, play: Callable) -> String:
	_ctx = ctx
	_rng.seed = hash(["gate_shots", picks, String(ctx["gate_actor"]), int(ctx.get("seed_extra", 0))])
	picks += 1
	played.clear()
	_holding = false
	_clear.clear()
	var arrival: float = ctx["arrival_s"]
	_arrival_s = arrival
	_segments = [{"slot": GateShotPool.APPROACH, "end": pool.cut_s(arrival)},
			{"slot": GateShotPool.MOUTH, "end": arrival + FUNNEL_S}]
	clock_s = 0.0
	_cut(play)
	last_opening = String(played[0]["id"]) if not played.is_empty() else ""
	return last_opening


## Starts the way back out's takes while the blue vortex opens. `ctx`: `gate`, `ship`, `gate_actor`, `space`, `planet`,
## `seed_extra` as in `begin`, and `arrival_pose` (Transform3D, where the gate places the ship) and `arrival_velocity` (World, the
## speed it comes out at). Returns the opening take's id.
func begin_arrival(ctx: Dictionary, play: Callable) -> String:
	_ctx = ctx
	_clear.clear()
	_holding = false
	_stage_start(GateShotPool.ARRIVAL_OPEN, OPEN_S)
	_cut(play)
	var opening: String = String(played[played.size() - 1]["id"]) if not played.is_empty() else ""
	last_arrival_opening = opening
	return opening


## The departure vortex is held open for the player's following wingmen (M8-T17): takes outside on the gate, watching the one
## nearest the mouth, until `on_through` freezes the last into the cut to black. `ctx`: `gate`, `ship` (the watched wingman),
## `lead_pose` (its transform now), `gate_actor`, `space`, `planet`.
func begin_hold(ctx: Dictionary, play: Callable) -> String:
	_ctx = ctx
	_clear.clear()
	_holding = false
	_stage_start(GateShotPool.HOLD, INF)
	_cut(play)
	return String(played[played.size() - 1]["id"]) if not played.is_empty() else ""


## Whether the take on screen has not yet had its least hold (a second, a feature its 2.5 s).
func take_young() -> bool:
	return _stage != &"" and clock_s - _take_at < _least_hold_s()


## No more cuts: the take on screen plays on into what comes next (the hold is ending, the ring's flash).
func freeze() -> void:
	_holding = true


## The gate has placed the ship in the funnel: takes of it coming out.
func on_placed(play: Callable) -> void:
	if _stage != GateShotPool.ARRIVAL_OPEN or clock_s - _take_at < _least_hold_s():
		return  # the host asks every tick: the cut comes once the take on screen has had its second (a feature its 2.5 s)
	_stage_start(GateShotPool.ARRIVAL_OUT, OUT_S)
	_cut(play)


## The ship reached the ring: the take on screen holds its 0.3 s flash and the arrival side follows with a hard cut, so nothing
## more is cut on this side.
func on_through(_play: Callable) -> void:
	_holding = true


## One tick of a stage, `delta` seconds: the next take when the one on screen has had its time.
func tick(delta: float, play: Callable) -> void:
	if _stage == &"":
		return
	clock_s += delta
	if clock_s >= _next_cut and not _holding:
		_cut(play)


## Pins the run-in's opening takes (`approach` and `mouth`; "" for both: picked again). "" or why a name is unknown.
func pin(approach: String, mouth: String) -> String:
	if approach.is_empty() and mouth.is_empty():
		pinned = PackedStringArray()
		return ""
	if not pool.ids(GateShotPool.APPROACH).has(approach) or not pool.ids(GateShotPool.MOUTH).has(mouth):
		return "approach takes: %s; mouth takes: %s" % [", ".join(pool.ids(GateShotPool.APPROACH)),
				", ".join(pool.ids(GateShotPool.MOUTH))]
	pinned = PackedStringArray([approach, mouth])
	return ""


## Ends every take: the schedule is dropped and `stop_camera` ends the one on screen.
func stop(stop_camera: Callable) -> void:
	_segments.clear()
	_next_cut = INF
	_stage = &""
	stop_camera.call()


## This jump's takes as `slot/id`, in order.
func sequence() -> PackedStringArray:
	var out := PackedStringArray()
	for take: Dictionary in played:
		out.append("%s/%s" % [take["slot"], take["id"]])
	return out


## Whether a run-in take (approach or mouth) keeps clear wherever the stage may play it (`ctx` as in `begin`).
func is_clear(slot: StringName, id: String, ctx: Dictionary) -> bool:
	var arrival: float = ctx["arrival_s"]
	var cut: float = pool.cut_s(arrival)
	var starts: Array[float] = []
	match slot:
		GateShotPool.APPROACH:
			starts = [0.0, cut * 0.5, maxf(cut - GateShotPool.TAKE_MAX_S, 0.0)]
		_:
			starts = [cut, maxf(arrival - GateShotPool.TAKE_MAX_S * 0.5, cut), arrival + 1.0]
	var times := PackedFloat32Array()  # run-in seconds
	for start: float in starts:
		var t: float = 0.0
		while t <= pool.max_s(slot, id) + 1e-3:
			times.append(start + t)
			t += SAMPLE_S
	var order: Array = Array(times)
	order.sort()
	var sorted := PackedFloat32Array(order)
	var travel: PackedFloat32Array = GateAutopilot.run_in_travel_m(sorted, ctx["to_plane_m"], ctx["open_in_s"], ctx["speed_mps"],
			ctx["capability"])
	var ship: Ship = ctx["ship"]
	var axis: Vector3 = ctx["axis"]
	var at_time: Dictionary = {}
	for i: int in sorted.size():
		at_time[snappedf(sorted[i], 1e-3)] = Transform3D(ship.global_transform.basis, ship.global_transform.origin + axis * travel[i])
	var ok: bool = true
	for start: float in starts:
		var sample := PackedFloat32Array()
		var poses: Array[Transform3D] = []
		var watch := PackedByteArray()
		var t: float = 0.0
		while t <= pool.max_s(slot, id) + 1e-3:
			sample.append(t)
			poses.append(at_time.get(snappedf(start + t, 1e-3), ship.global_transform))
			watch.append(1 if start + t < arrival - 0.3 else 0)
			t += SAMPLE_S
		ok = ok and _take_clear(slot, id, ctx, sample, poses, watch)
	return ok


## Whether a way-back take keeps clear: the vortex opening (the ship not yet out) or the ship's way out along its exit path,
## seen once it is out in front of the mouth (`ctx` as in `begin_arrival`).
## Whether a hold take's camera keeps clear and sees the watched wingman, held where it is now.
func hold_clear(slot: StringName, id: String, ctx: Dictionary) -> bool:
	var sample := PackedFloat32Array()
	var poses: Array[Transform3D] = []
	var watch := PackedByteArray()
	var t: float = 0.0
	var pose: Transform3D = (ctx["lead_pose_now"] as Callable).call() if ctx.get("lead_pose_now") is Callable else ctx["lead_pose"]
	while t <= pool.max_s(slot, id) + 1e-3:
		sample.append(t)
		poses.append(pose)
		watch.append(1)
		t += SAMPLE_S
	return _take_clear(slot, id, ctx, sample, poses, watch)


func arrival_clear(slot: StringName, id: String, ctx: Dictionary) -> bool:
	var gate: Jumpgate = ctx["gate"]
	var placed: Transform3D = ctx["arrival_pose"]
	var velocity: Vector3 = ctx["arrival_velocity"]
	var starts: Array[float] = [0.0]
	if slot == GateShotPool.ARRIVAL_OUT:
		starts.append_array([3.0, 6.0])
	var ok: bool = true
	for start: float in starts:
		var sample := PackedFloat32Array()
		var poses: Array[Transform3D] = []
		var watch := PackedByteArray()
		var t: float = 0.0
		while t <= pool.max_s(slot, id) + 1e-3:
			var flown: float = start + t if slot == GateShotPool.ARRIVAL_OUT else 0.0
			var pose := Transform3D(placed.basis, placed.origin + velocity * flown)
			sample.append(t)
			poses.append(pose)
			watch.append(1 if slot == GateShotPool.ARRIVAL_OUT and gate.local_of(pose.origin).z < -CLEAR_M else 0)
			t += SAMPLE_S
		ok = ok and _take_clear(slot, id, ctx, sample, poses, watch)
	return ok


# Cuts to the next take: the stage's slot at this moment, a take picked for where it falls (before, at or after the entry), held
# as long as the take may be and the stage allows.
func _cut(play: Callable) -> void:
	if _segments.is_empty():
		return
	var index: int = 0
	while index < _segments.size() - 1 and clock_s >= float(_segments[index]["end"]) - 1e-3:
		index += 1
	var slot: StringName = _segments[index]["slot"]
	var stage_end: float = float(_segments[index]["end"])
	if index == _segments.size() - 1 and clock_s >= stage_end - 1e-3 and not played.is_empty():
		# Past the stage's predicted end (the ring or the burst out not yet come): the take on screen runs on to its longest, so
		# no stray short take is cut in just before the real end.
		var current: Dictionary = played[played.size() - 1]
		var longest: float = _take_at + pool.max_s(current["slot"], String(current["id"]))
		if clock_s < longest - 1e-3:
			_next_cut = longest
			return
	var kind: String = ""
	if slot == GateShotPool.MOUTH:
		if clock_s > _arrival_s + ENTRY_LATE_S:
			kind = GateShotPool.AFTER
		elif _arrival_s - clock_s <= GateShotPool.TAKE_MAX_S:
			kind = GateShotPool.ENTRY
		else:
			kind = GateShotPool.BEFORE
	elif slot == GateShotPool.ARRIVAL_OPEN:
		kind = GateShotPool.AFTER if clock_s >= OPEN_LATE_S else GateShotPool.BEFORE  # a take tagged `after` waits for the blue
	elif slot == GateShotPool.ARRIVAL_OUT:
		kind = GateShotPool.BEFORE if clock_s < 0.5 else GateShotPool.AFTER  # a take tagged `before` opens the burst, its core white
	var used := PackedStringArray()
	var previous: String = ""
	for take: Dictionary in played:
		if take["slot"] == slot:
			used.append(String(take["id"]))
		previous = String(take["id"])
	var opening: bool = used.is_empty() and (slot == GateShotPool.APPROACH or slot == GateShotPool.ARRIVAL_OPEN)
	var avoid: String = (last_opening if slot == GateShotPool.APPROACH else last_arrival_opening) if opening else ""
	var id: String = _pinned_for(slot, used)
	if id.is_empty() and slot == GateShotPool.HOLD and _ctx.get("hold_order") is Callable:
		id = _hold_pick(previous)
	if id.is_empty():
		id = pool.next(_rng, slot, used, previous, avoid, _usable, kind)
	if id.is_empty():
		return
	var length: float = GateShotPool.take_length(clock_s, stage_end if clock_s < stage_end - 1e-3 else INF, pool.max_s(slot, id))
	if kind == GateShotPool.BEFORE or pool.when(slot, id) == GateShotPool.BEFORE:
		# Off just before the entry, so the entry gets its own take and a close one never sees the core fill the view.
		length = minf(length, maxf(_arrival_s - clock_s - ENTRY_LEAD_S, GateShotPool.MIN_HOLD_S))
	var made: Dictionary = CinematicShot.from_dict(StringName("gate_%s_%s" % [slot, id]),
			{"keys": pool.keys(slot, id, String(_ctx["gate_actor"]))})
	if not bool(made["ok"]):
		push_warning("GateShotDirector: %s" % made["error"])
		return
	_stage = slot
	_take_at = clock_s
	_next_cut = clock_s + maxf(length, 0.05)
	played.append({"slot": slot, "id": id, "at_s": clock_s})
	play.call(made["shot"])


# The hold's take: the first of the host's order that is clear and not the one before (M8-T17).
func _hold_pick(previous: String) -> String:
	var order: PackedStringArray = (_ctx["hold_order"] as Callable).call()
	for id: String in order:
		if id != previous and pool.ids(GateShotPool.HOLD).has(id) and _usable(GateShotPool.HOLD, id):
			return id
	return order[0] if not order.is_empty() and order[0] != previous else ""


## The take on screen's id ("" before any).
func last_id() -> String:
	return String(played[played.size() - 1]["id"]) if not played.is_empty() else ""


## How many takes of `slot` this jump has played.
func played_in(slot: StringName) -> int:
	var n: int = 0
	for take: Dictionary in played:
		n += int(take["slot"] == slot)
	return n


# A pinned opening take for this stage, if one is pinned and the stage has not opened yet.
func _pinned_for(slot: StringName, used: PackedStringArray) -> String:
	if not used.is_empty():
		return ""
	if slot == GateShotPool.APPROACH and pinned.size() == 2:
		return pinned[0]
	if slot == GateShotPool.MOUTH and pinned.size() == 2:
		return pinned[1]
	if slot == GateShotPool.ARRIVAL_OPEN or slot == GateShotPool.ARRIVAL_OUT:
		return pinned_arrival if pool.ids(slot).has(pinned_arrival) else ""
	return ""


func _usable(slot: StringName, id: String) -> bool:
	var key: String = "%s/%s" % [slot, id]
	if slot == GateShotPool.HOLD:
		return hold_clear(slot, id, _ctx)  # the wingman moves on: judged afresh at each cut
	if not _clear.has(key):
		var arriving: bool = slot == GateShotPool.ARRIVAL_OPEN or slot == GateShotPool.ARRIVAL_OUT
		_clear[key] = arrival_clear(slot, id, _ctx) if arriving else is_clear(slot, id, _ctx)
	return _clear[key]


# The least the take on screen is held before a stage moves on: a second, or a feature take's `FEATURE_MIN_S`.
func _least_hold_s() -> float:
	if played.is_empty():
		return GateShotPool.MIN_HOLD_S
	var last: Dictionary = played[played.size() - 1]
	return GateShotPool.FEATURE_MIN_S if pool.is_feature(last["slot"], String(last["id"])) else GateShotPool.MIN_HOLD_S


func _stage_start(slot: StringName, length_s: float) -> void:
	clock_s = 0.0
	_arrival_s = INF
	_segments = [{"slot": slot, "end": length_s}]


# One take's camera, sampled at `sample` (s into it) with the ship at `poses`, kept clear of every solid and planet, and in sight
# of the ship at the samples `watch` marks.
func _take_clear(slot: StringName, id: String, ctx: Dictionary, sample: PackedFloat32Array, poses: Array[Transform3D],
		watch: PackedByteArray) -> bool:
	var gate: Jumpgate = ctx["gate"]
	var ship: Ship = ctx["ship"]
	var gate_actor: String = ctx["gate_actor"]
	var made: Dictionary = CinematicShot.from_dict(&"check", {"keys": pool.keys(slot, id, gate_actor)})
	if not bool(made["ok"]):
		return false
	var cameras: PackedVector3Array = GateShotPool.camera_path(made["shot"], sample,
			func(actor: String, i: int) -> Variant: return gate.global_transform if actor == gate_actor else poses[i])
	var space: PhysicsDirectSpaceState3D = ctx.get("space")
	var planet: ReferenceFrame.Candidate = ctx.get("planet")
	var blocked: int = 0
	var looked: int = 0
	for i: int in cameras.size():
		if planet != null and cameras[i].distance_to(planet.position) < planet.radius_m + planet.atmosphere_top_m + PLANET_MARGIN_M:
			return false
		if space == null:
			continue
		if _inside(space, cameras[i], ship):
			return false
		if watch[i] == 1:
			looked += 1
			if _view_blocked(space, cameras[i], poses[i].origin, ship):
				blocked += 1
	return looked == 0 or float(blocked) / float(looked) <= MAX_BLOCKED_SHARE


# The camera sits within `CLEAR_M` of something solid (the gate's arms, the station, a rock).
static func _inside(space: PhysicsDirectSpaceState3D, at: Vector3, ship: Ship) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = CLEAR_M
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = SOLID_MASK
	query.exclude = [ship.get_rid()]
	return not space.intersect_shape(query, 1).is_empty()


# Something solid stands between the camera and the ship.
static func _view_blocked(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, ship: Ship) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, SOLID_MASK, [ship.get_rid()])
	return not space.intersect_ray(query).is_empty()
