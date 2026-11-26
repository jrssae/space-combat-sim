class_name BlastResolver
extends RefCounted
## Lands every blast (M10-T09, D12.6): a death, a section blowing, a missile's warhead, a mine. Since M10-T76 (Q70) a blast and
## its chain land in one native batch (`ScsBlastBatch`) on the damage store, in the order they were set off; this queues them,
## drives the batch and answers what it hands back, once each.
##
## - **Reach.** The core names the hulls a blast reaches from the rows of this tick's sync (near hulls, then tier rows), each
##   measured to its nearest hit volume (a big hull's surface, a fighter's own hit volumes); a capital's rotors share their
##   ship's place in the order, the nearest piece taking the blast, once.
## - **Damage** `d0 x f(d)`, cause `blast`, friend or foe alike, through the damage store: a capital's on the section of the
##   surface volume nearest the blast, the station's by section and grid mount, a fighter's on its hull (god mode as for any
##   hit). Each damaged ship hears of a batch's blast hits once, as a `HitSummary` (`Damageable.hits_landed`, cause `blast`),
##   not a `hit_taken` and a `damaged` a hit (Q94).
## - **Push** `dv = impulse x f(d) x A / m` (capped) away from the centre, on the body (a rotor's on its capital) or on its tier
##   row. A kinematic or frozen body is not pushed.
## - **Chains.** A blast sets off the mines it reaches (in their field's next landing, `MineField`); a field's landing runs in the
##   batch too, one blast a mine, so a field goes off as a chain. A hit that kills ends a batch: the kill's `destroyed` is
##   announced here, the destruction director sets off the dead hull's own blast, and it lands after this one, in the same tick.
##
## Without a core no hull is reached (the core is required; there is no other path). `stats` holds the readouts the console's
## `blasts` provider shows.

const NATIVE_CLASS: StringName = &"ScsBlastBatch"

## Readouts since the last `reset_stats`: blasts landed, hulls hurt and pushed, the cost (wall clock, readouts only).
static var blasts: int = 0
static var hulls_hurt: int = 0
static var pushed: int = 0
## Wall clock of every landing (a blast set off and the chain it starts, the answers to its events included), us.
static var total_us: int = 0
static var max_us: int = 0
## Of that, the native core's reach (the walk over the hulls), and the native batch's whole share.
static var reach_us: int = 0
static var native_us: int = 0
## The last blast landed: its source, centre, the hulls it reached and hurt; the last landing's cost.
static var last_source: StringName = &""
static var last_centre: Vector3 = Vector3.ZERO
static var last_reached: int = 0
static var last_hurt: int = 0
static var last_us: int = 0
## Batches the last landing took (each kill or event to answer ends one).
static var last_batches: int = 0

static var _batch: Object = null
static var _landing: bool = false


## The native batch, made the first time it is asked for.
static func batch() -> Object:
	if _batch == null:
		_batch = NativeLib.instantiate(NATIVE_CLASS)
		if _batch != null:
			_batch.attach_store(DamageStore.store)
			for k: int in MineKinds.NAMES.size():
				var spec: BlastSpec = MineKinds.blast(k)
				if spec != null:
					_batch.set_mine_blast(k, _numbers(spec), spec.source)
	return _batch


## Sets off blast `spec` at `centre` (World frame): lands it now, or after the blast being landed when one is (a chain).
## `faction` and `shooter_id` go on its hits (0: no shooter, so no kill credit and no one to answer).
static func set_off(spec: BlastSpec, centre: Vector3, faction: StringName = &"", shooter_id: int = 0) -> void:
	if spec == null or not (spec.radius_m > 0.0) or batch() == null:
		return
	_batch.set_off(_numbers(spec), spec.source, centre, faction, shooter_id)
	if not _landing:
		_drive()


## Lands `field`'s mines waiting to go off (its step's), its node at `origin`, one blast each with every chain they start.
static func land_field(field: MineField, origin: Vector3) -> void:
	if batch() != null and bool(_batch.begin_field(field.number, origin)) and not _landing:
		_drive()


## Mine field `field` can be set off by blasts from now on (its rows made, in the tree), or no longer.
static func add_field(field: MineField) -> void:
	if batch() != null and field.rows != null:
		_batch.add_field(field.number, field.get_instance_id(), field.rows)


static func remove_field(field: MineField) -> void:
	if _batch != null:
		_batch.remove_field(field.number)


## Clears the readouts.
static func reset_stats() -> void:
	if batch() != null:
		_batch.reset_stats()
	blasts = 0
	hulls_hurt = 0
	pushed = 0
	total_us = 0
	max_us = 0
	reach_us = 0
	native_us = 0
	last_source = &""
	last_centre = Vector3.ZERO
	last_reached = 0
	last_hurt = 0
	last_us = 0
	last_batches = 0


## The readouts as one dictionary (the console's provider).
static func stats() -> Dictionary:
	return {"blasts": blasts, "hulls_hurt": hulls_hurt, "pushed": pushed, "last_source": String(last_source),
			"last_reached": last_reached, "last_hurt": last_hurt, "last_us": last_us, "max_us": max_us,
			"mean_us": float(total_us) / float(blasts) if blasts > 0 else 0.0,
			"reach_mean_us": float(reach_us) / float(blasts) if blasts > 0 else 0.0,
			"native_mean_us": float(native_us) / float(blasts) if blasts > 0 else 0.0}


## Keeps every blast hit landed from now on (true) or stops and forgets them: the tests' native hit log.
static func set_hit_log(on: bool) -> void:
	if batch() != null:
		_batch.set_hit_log(on)


## The blast hits landed since `set_hit_log(true)`, in order, each as a `HitInfo` (target the body hit, the shooter, damage,
## points removed, point, cause `blast`), for the tests.
static func hit_log() -> Array[HitInfo]:
	var out: Array[HitInfo] = []
	if _batch == null:
		return out
	var log: Array = _batch.hit_log()
	var bodies: PackedInt64Array = log[1]
	for k: int in bodies.size():
		var info := HitInfo.new(bodies[k], (log[2] as PackedInt64Array)[k], &"", (log[3] as PackedFloat64Array)[k],
				(log[5] as PackedVector3Array)[k], Vector3.ZERO, 0.0, HitInfo.CAUSE_BLAST)
		info.applied = (log[4] as PackedFloat64Array)[k]
		out.append(info)
	return out


## Hull `damageable`'s nearest point to World point `at` and how far it is, `[distance, point]`, measured to its hit volumes
## with its body at `xform` (World); `fallback` (`[distance, point]`) for a hull with none. The native batch measures the
## same (`damage_store::blasts`); this is the tests' reference.
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


## The hull of instance `hull_id` when a blast (or a beam, M10-T12) can still hurt it: in play, or flying in the tier; null
## otherwise.
static func hurtable(hull_id: int) -> Damageable:
	var damageable := instance_from_id(hull_id) as Damageable if is_instance_id_valid(hull_id) else null
	if damageable == null or damageable.hull.destroyed:
		return null
	var body: Node3D = damageable.body()
	if body == null or not (damageable.is_active() or body.has_meta(TierDirector.TIER_META)):
		return null
	return damageable


## Which hull answers for a piece in a blast: a rotor's capital (the whole ship's), else the piece itself.
static func owner_of(damageable: Damageable) -> int:
	var rotor := damageable.body() as CapitalRotor
	return rotor.capital.get_instance_id() if rotor != null and is_instance_valid(rotor.capital) else damageable.get_instance_id()


## The body a blast pushes for a piece: a rotor's capital, else the piece's own body (null for none).
static func push_body_of(damageable: Damageable) -> Node3D:
	var body: Node3D = damageable.body()
	var rotor := body as CapitalRotor
	return rotor.capital if rotor != null and is_instance_valid(rotor.capital) else body


## The box a push acts on, full extents: a capital's hull box, else its ram volumes' bounds, else its bounding sphere's cube.
static func box_size(damageable: Damageable, body: Node3D) -> Vector3:
	var cap := body as CapitalBody
	if cap != null:
		return cap.half_extents() * 2.0
	if damageable.ram_bounds.size.length_squared() > 0.0:
		return damageable.ram_bounds.size
	return Vector3.ONE * 2.0 * damageable.bounding_radius


static func _numbers(spec: BlastSpec) -> PackedFloat64Array:
	return PackedFloat64Array([spec.d0, spec.radius_m, spec.impulse, spec.push_cap_mps])


# Runs the batch until every blast queued (and the chains they start) has landed, answering each batch's events in order.
static func _drive() -> void:
	_landing = true
	var started: int = Time.get_ticks_usec()  # a readout, never gameplay time
	var sim: SimCore = SimCore.current()
	var names: Array = []  # the core's factions, read once when a summary needs them
	var batches: int = 0
	while true:
		var core: Object = sim.core if sim != null and sim.ensure_synced() else null
		var got: Array = _batch.run(core, DebugConsole.flags.invulnerable)
		batches += 1
		_take_mines(got)
		DamageStore.take_writes(got[1])
		DamageStore.apply(got[2])
		var cols: Array = got[3]
		var targets: PackedInt64Array = cols[0]
		if not targets.is_empty() and names.is_empty() and core != null:
			names = core.factions()
		for k: int in targets.size():
			var hull: Damageable = instance_from_id(targets[k]) as Damageable if is_instance_id_valid(targets[k]) else null
			if hull != null:
				var summary: HitSummary = HitSummary.from_columns(cols, k, names)
				summary.cause = HitInfo.CAUSE_BLAST
				hull.land_summary(summary)
		var kill: Dictionary = got[4]
		if not kill.is_empty():
			_announce_kill(kill)
		var left: Dictionary = got[5]
		if not left.is_empty():
			_land_one(left)
		if bool(got[0]):
			break
	_landing = false
	var stat: PackedFloat64Array = _batch.stats()
	blasts = int(stat[0])
	hulls_hurt = int(stat[1])
	pushed = int(stat[2])
	reach_us = int(stat[3])
	native_us = int(stat[4])
	var last: Array = _batch.last()
	last_source = last[0]
	last_centre = last[1]
	last_reached = int(last[2])
	last_hurt = int(last[3])
	last_batches = batches
	last_us = Time.get_ticks_usec() - started
	total_us += last_us
	max_us = maxi(max_us, last_us)


# The mines that went off in a batch, each answered by its field (drawn, out of the rows, its signal).
static func _take_mines(got: Array) -> void:
	var numbers: PackedInt64Array = got[6]
	if numbers.is_empty():
		return
	var by_number: Dictionary = {}
	for f: MineField in MineField.fields:
		if is_instance_valid(f):
			by_number[f.number] = f
	var slots: PackedInt32Array = got[7]
	var causes: PackedInt32Array = got[8]
	var kinds: PackedInt32Array = got[9]
	var places: PackedVector3Array = got[10]
	for k: int in numbers.size():
		var field: MineField = by_number.get(numbers[k])
		if field != null:
			field.went_off(slots[k], causes[k], kinds[k], places[k])


# A blast hit as a `HitInfo` (cause `blast`, facing the blast's centre) from the batch's dictionary.
static func _info(hit: Dictionary) -> HitInfo:
	var point: Vector3 = hit["point"]
	var centre: Vector3 = hit["centre"]
	var facing: Vector3 = centre - point
	if facing.length_squared() < 1e-12:
		facing = centre - (hit["place"] as Vector3)
	var info := HitInfo.new(int(hit["body"]), int(hit["shooter"]), StringName(hit["faction"]), float(hit["damage"]), point,
			facing.normalized() if facing.length_squared() > 1e-12 else Vector3.ZERO, 0.0, HitInfo.CAUSE_BLAST)
	info.volume = int(hit["volume"])
	return info


# The blast hit that destroyed its hull: its `destroyed` (the destruction director sets off the dead hull's blast).
static func _announce_kill(kill: Dictionary) -> void:
	var hull: Damageable = instance_from_id(int(kill["target"])) as Damageable if is_instance_id_valid(int(kill["target"])) else null
	if hull == null:
		return
	var info: HitInfo = _info(kill)
	info.applied = float(kill["applied"])
	hull.destroyed.emit(info)


# A hit the batch left to GDScript (a hull it holds no landing for, a capital volume it cannot name): through its
# `Damageable`, as every blast hit landed before the batch.
static func _land_one(hit: Dictionary) -> void:
	var hull: Damageable = instance_from_id(int(hit["target"])) as Damageable if is_instance_id_valid(int(hit["target"])) else null
	if hull == null:
		return
	hull.push_landing()  # the batch lands on it from now on
	hull.apply_hit(_info(hit))
