class_name BlastResolver
extends RefCounted
## Lands every blast (M10-T09, D12.6): a death, a section blowing, a missile's warhead. The native core names the hulls a
## blast reaches and how far each one's nearest hit volume is (`ScsSimCore.blast_reach`, over the rows of this tick's sync,
## near hulls then tier rows); this lands the damage and the push on each, per event, on the main thread in the tick.
##
## - **Damage** `d0 x f(d)` through the hull's `Damageable.apply_hit` (cause `blast`), at the hull's nearest point: a capital's
##   lands on the section of the surface volume nearest the blast (`HitInfo.volume`, `CapitalDamage` through its router), a
##   station's on the volume's place, a fighter's measured to its own hit volumes. A capital and its rotors share one hull: the
##   nearest piece takes the blast, once. Friend or foe alike; god mode as for any hit.
## - **Push** `dv = impulse x f(d) x A / m` (capped) away from the centre, on the body (a rotor's on its capital), or on its tier
##   row. A kinematic or frozen body is not pushed.
## - **Chains.** A blast that kills sets off the dead hull's own blast through the destruction director; it waits until this one
##   is landed, then lands in the same tick, in the order set off.
##
## Without a core nothing is reached (the core is required; there is no other path). `stats` holds the readouts the console's
## `blasts` provider shows.

## Readouts since the last `reset_stats`: blasts landed, hulls hurt and pushed, the cost (wall clock, readouts only).
static var blasts: int = 0
static var hulls_hurt: int = 0
static var pushed: int = 0
static var total_us: int = 0
static var max_us: int = 0
## Of that, the native core's reach (the walk over the hulls).
static var reach_us: int = 0
## The last blast landed: its source, centre, the hulls it reached and hurt, its cost.
static var last_source: StringName = &""
static var last_centre: Vector3 = Vector3.ZERO
static var last_reached: int = 0
static var last_hurt: int = 0
static var last_us: int = 0

static var _queue: Array[Array] = []  # [spec, centre, faction, shooter_id] waiting behind the blast being landed
static var _landing: bool = false


## Sets off blast `spec` at `centre` (World frame): lands it now, or after the blast being landed when one is (a chain).
## `faction` and `shooter_id` go on its hits (0: no shooter, so no kill credit and no one to answer).
static func set_off(spec: BlastSpec, centre: Vector3, faction: StringName = &"", shooter_id: int = 0) -> void:
	if spec == null or not (spec.radius_m > 0.0):
		return
	_queue.append([spec, centre, faction, shooter_id])
	if _landing:
		return
	_landing = true
	var n: int = 0
	while n < _queue.size():
		var e: Array = _queue[n]
		n += 1
		_land(e[0], e[1], e[2], e[3])
	_queue.clear()
	_landing = false


## Clears the readouts.
static func reset_stats() -> void:
	blasts = 0
	hulls_hurt = 0
	pushed = 0
	total_us = 0
	max_us = 0
	reach_us = 0
	last_source = &""
	last_centre = Vector3.ZERO
	last_reached = 0
	last_hurt = 0
	last_us = 0


## The readouts as one dictionary (the console's provider).
static func stats() -> Dictionary:
	return {"blasts": blasts, "hulls_hurt": hulls_hurt, "pushed": pushed, "last_source": String(last_source),
			"last_reached": last_reached, "last_hurt": last_hurt, "last_us": last_us, "max_us": max_us,
			"mean_us": float(total_us) / float(blasts) if blasts > 0 else 0.0,
			"reach_mean_us": float(reach_us) / float(blasts) if blasts > 0 else 0.0}


## Hull `damageable`'s nearest point to World point `at` and how far it is, `[distance, point]`, measured to its hit volumes
## with its body at `xform` (World); `fallback` (`[distance, point]`) for a hull with none.
static func nearest_on(damageable: Damageable, xform: Transform3D, at: Vector3, fallback: Array) -> Array:
	if damageable.shapes.is_empty():
		return fallback
	var local: Vector3 = xform.affine_inverse() * at
	var best_d: float = INF
	var best: Vector3 = local
	for shape: HitShape in damageable.shapes:
		var p: Vector3 = shape.nearest_point(local)
		var d: float = p.distance_to(local)
		if d < best_d:
			best_d = d
			best = p
	return [best_d, xform * best]


# One blast: the hulls the core names, the nearest piece of each, then the damage and the push on each in the core's order.
static func _land(spec: BlastSpec, centre: Vector3, faction: StringName, shooter_id: int) -> void:
	var started: int = Time.get_ticks_usec()  # a readout, never gameplay time
	var sim: SimCore = SimCore.current()
	var reached: int = 0
	var hurt: int = 0
	if sim != null and sim.ensure_synced():
		var asked: int = Time.get_ticks_usec()
		var found: Array = sim.core.blast_reach(centre, spec.radius_m)
		reach_us += Time.get_ticks_usec() - asked
		var hull_ids: PackedInt64Array = found[0]
		var distances: PackedFloat64Array = found[2]
		var points: PackedVector3Array = found[3]
		var volumes: PackedInt32Array = found[4]
		var places: PackedVector3Array = found[5]
		var axes: PackedVector3Array = found[6]
		var picks: Dictionary = {}  # the hull that answers for a piece -> [distance, point, volume, place, damageable]
		var order: Array[int] = []
		for k: int in hull_ids.size():
			var damageable: Damageable = _hurtable(hull_ids[k])
			if damageable == null:
				continue
			var near: Array = [distances[k], points[k]]
			if volumes[k] < 0:
				var xform := Transform3D(Basis(axes[3 * k], axes[3 * k + 1], axes[3 * k + 2]), places[k])
				near = nearest_on(damageable, xform, centre, near)
				if not (float(near[0]) < spec.radius_m):
					continue
			var owner: int = _owner_of(damageable)
			if picks.has(owner):
				if float(near[0]) < float((picks[owner] as Array)[0]):
					picks[owner] = [near[0], near[1], volumes[k], places[k], damageable]
				continue
			picks[owner] = [near[0], near[1], volumes[k], places[k], damageable]
			order.append(owner)
		reached = order.size()
		for owner: int in order:
			var pick: Array = picks[owner]
			if _hit(spec, centre, faction, shooter_id, pick):
				hurt += 1
			_push(sim, spec, centre, pick)
	blasts += 1
	hulls_hurt += hurt
	last_source = spec.source
	last_centre = centre
	last_reached = reached
	last_hurt = hurt
	last_us = Time.get_ticks_usec() - started
	total_us += last_us
	max_us = maxi(max_us, last_us)


# The hull of instance `hull_id` when a blast can still hurt it: in play, or flying in the tier; null otherwise.
static func _hurtable(hull_id: int) -> Damageable:
	var damageable := instance_from_id(hull_id) as Damageable if is_instance_id_valid(hull_id) else null
	if damageable == null or damageable.hull.destroyed:
		return null
	var body: Node3D = damageable.body()
	if body == null or not (damageable.is_active() or body.has_meta(TierDirector.TIER_META)):
		return null
	return damageable


# Which hull answers for a piece: a rotor's capital (one hull for the whole ship), else the piece itself.
static func _owner_of(damageable: Damageable) -> int:
	var rotor := damageable.body() as CapitalRotor
	return rotor.capital.get_instance_id() if rotor != null and is_instance_valid(rotor.capital) else damageable.get_instance_id()


# The blast's damage on one hull; true when it took any.
static func _hit(spec: BlastSpec, centre: Vector3, faction: StringName, shooter_id: int, pick: Array) -> bool:
	var damage: float = spec.damage_at(float(pick[0]))
	if not (damage > 0.0):
		return false
	var damageable: Damageable = pick[4]
	var point: Vector3 = pick[1]
	var target_id: int = damageable.body().get_instance_id()
	var facing: Vector3 = centre - point
	if facing.length_squared() < 1e-12:
		facing = centre - (pick[3] as Vector3)
	var info := HitInfo.new(target_id, shooter_id if shooter_id != target_id else 0, faction, damage, point,
			facing.normalized() if facing.length_squared() > 1e-12 else Vector3.ZERO, 0.0, HitInfo.CAUSE_BLAST)
	info.volume = int(pick[2])
	damageable.apply_hit(info)
	return true


# The blast's push on one hull, away from the centre: on its body, or on its tier row.
static func _push(sim: SimCore, spec: BlastSpec, centre: Vector3, pick: Array) -> void:
	var damageable: Damageable = pick[4]
	var body: Node3D = damageable.body()
	var rotor := body as CapitalRotor
	if rotor != null:
		body = rotor.capital
	if body == null or not is_instance_valid(body):
		return
	var away: Vector3 = (pick[3] as Vector3) - centre
	if away.length_squared() < 1e-12:
		return
	var dv: float = spec.push_at(float(pick[0]), BlastSpec.mean_face_area(_box_size(damageable, body)), damageable.ram_mass())
	if not (dv > 0.0):
		return
	var kick: Vector3 = away.normalized() * dv
	if body.has_meta(TierDirector.TIER_META):
		if bool(sim.core.tier_add_velocity(body.get_instance_id(), kick)):
			pushed += 1
		return
	var rigid := body as RigidBody3D
	if rigid != null and not rigid.freeze:
		rigid.linear_velocity += kick
		pushed += 1


# The hull's box, full extents: a capital's hull box, else its ram volumes' bounds, else its bounding sphere's cube.
static func _box_size(damageable: Damageable, body: Node3D) -> Vector3:
	var cap := body as CapitalBody
	if cap != null:
		return cap.half_extents() * 2.0
	if damageable.ram_bounds.size.length_squared() > 0.0:
		return damageable.ram_bounds.size
	return Vector3.ONE * 2.0 * damageable.bounding_radius
