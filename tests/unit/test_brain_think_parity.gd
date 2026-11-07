extends GutTest
## The native brains against the GDScript `AiPilot`, bit for bit (M4-T17b, architecture §17.13): on hand-built rows (ships of
## four sides, props, rocks and mines, bolts) walking a seeded path, a native brain slot and a GDScript twin think side by
## side every tick for several scenarios (a plain crowd, a wing under each order, an objective, a guard post, a patrol route
## with its demos, a passive and a reckless pilot, a hit) and must give the same flight and combat command, the same
## wanted target, the same dodge, the same behaviour in control and the same scores. The twin's perception is picked as
## `AiPilotDriver.perceive` picks it (nearest k with the keeps, the nearest statics, incoming fire, broadcasts), from a scan
## built by hand on the same rows. Skips, saying why, when the library is not built.

const BRAINS_CLASS: StringName = &"ScsBrains"
const SIDES: Array[StringName] = [Factions.EARTH_ALLIANCE, Factions.RAIDERS, &"bench_c", &"bench_d"]
const TICKS: int = 240
const DT: float = 1.0 / 60.0
const NEAREST_K: int = 12
const STATIC_K: int = 4


func before_each() -> void:
	Factions.use_table(BenchLayout.faction_table(BenchLayout.BATTLE))


func after_each() -> void:
	Factions.reset()


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there are no brains to test")
	return true


static func _bytes(value: Variant) -> String:
	return var_to_bytes(value).hex_encode()


static func _v3(rng: RandomNumberGenerator, scale: float) -> Vector3:
	return Vector3(rng.randf_range(-scale, scale), rng.randf_range(-scale, scale), rng.randf_range(-scale, scale))


# --- the world as rows -------------------------------------------------------------------------------------------------


## A seeded crowd as rows: ships of four sides (some capitals and props), rocks and mines, bolts, walking every tick.
class Rows:
	var ids := PackedInt64Array()
	var positions := PackedVector3Array()
	var velocities := PackedVector3Array()
	var bases: Array[Basis] = []
	var radii := PackedFloat64Array()
	var kinds := PackedByteArray()
	var factions := PackedInt32Array()
	var is_ship := PackedByteArray()
	var hulls := PackedFloat64Array()
	var target_ids := PackedInt64Array()
	var reaches := PackedFloat64Array()
	var names := PackedStringArray()
	var bolt_positions := PackedVector3Array()
	var bolt_velocities := PackedVector3Array()
	var bolt_factions := PackedInt32Array()
	var bolt_shooters := PackedInt64Array()
	var _spin: Array[Vector3] = []

	func _init(rng: RandomNumberGenerator, ships: int, statics: int, bolts: int, spread_m: float) -> void:
		for i: int in ships:
			var at: Vector3 = Vector3(rng.randf_range(-spread_m, spread_m), rng.randf_range(-spread_m * 0.3, spread_m * 0.3),
					rng.randf_range(-spread_m, spread_m))
			var side: int = i % 4 if i >= 4 else i
			var roll: float = rng.randf()
			var prop: bool = roll < 0.08
			var capital: bool = not prop and roll < 0.16
			ids.append(1000 + i)
			positions.append(at)
			velocities.append(Vector3.ZERO if prop else _random(rng, 150.0))
			bases.append(Basis.from_euler(Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI))))
			radii.append(3.0 if prop else (rng.randf_range(100.0, 400.0) if capital else rng.randf_range(5.0, 30.0)))
			kinds.append(BodyKind.PROP if prop else (BodyKind.CAPITAL if capital else BodyKind.SHIP))
			factions.append(side)
			is_ship.append(0 if prop else 1)
			hulls.append(-1.0 if prop and rng.randf() < 0.5 else rng.randf())
			target_ids.append(-1)
			reaches.append(100000.0 if side == 0 or (prop and rng.randf() < 0.5) else 0.0)
			names.append("%s %d" % ["BUOY" if prop else ("CAPITAL" if capital else "SHIP"), i])
			_spin.append(_random(rng, 0.3))
		for s: int in statics:
			var mine: bool = rng.randf() < 0.3
			ids.append(5000 + s)
			positions.append(Vector3(rng.randf_range(-spread_m, spread_m), rng.randf_range(-400.0, 400.0), rng.randf_range(-spread_m, spread_m)))
			velocities.append(Vector3.ZERO)
			bases.append(Basis.IDENTITY)
			radii.append(50.0 if mine else rng.randf_range(20.0, 200.0))
			kinds.append(BodyKind.MINE if mine else BodyKind.STATIC)
			factions.append(rng.randi_range(0, 3) if mine else 2)
			is_ship.append(0)
			hulls.append(-1.0)
			target_ids.append(-1)
			reaches.append(0.0)
			names.append("")
			_spin.append(Vector3.ZERO)
		for b: int in bolts:
			var near: int = rng.randi_range(0, ships - 1)
			var at: Vector3 = positions[near] + _random(rng, 400.0)
			bolt_positions.append(at)
			bolt_velocities.append((positions[near] - at).normalized() * rng.randf_range(300.0, 900.0) + _random(rng, 20.0))
			bolt_factions.append(rng.randi_range(0, 3))
			bolt_shooters.append(ids[rng.randi_range(0, ships - 1)])

	static func _random(rng: RandomNumberGenerator, scale: float) -> Vector3:
		return Vector3(rng.randf_range(-scale, scale), rng.randf_range(-scale, scale), rng.randf_range(-scale, scale))

	## One tick of the walk: ships drift and turn, hulls wear, selections change now and then, bolts fly on.
	func walk(rng: RandomNumberGenerator, dt: float) -> void:
		for i: int in ids.size():
			if kinds[i] == BodyKind.STATIC or kinds[i] == BodyKind.MINE:
				continue
			positions[i] += velocities[i] * dt
			if is_ship[i] == 1:
				velocities[i] += _random(rng, 2.0)
				bases[i] = (bases[i] * Basis.from_euler(_spin[i] * dt)).orthonormalized()
				if rng.randf() < 0.01:
					hulls[i] = maxf(hulls[i] - rng.randf_range(0.0, 0.3), 0.0)
				if rng.randf() < 0.02:
					target_ids[i] = ids[rng.randi_range(0, ids.size() - 1)] if rng.randf() < 0.8 else -1
		for b: int in bolt_positions.size():
			bolt_positions[b] += bolt_velocities[b] * dt
			if positions[0].distance_to(bolt_positions[b]) > 6000.0:
				bolt_positions[b] = positions[rng.randi_range(0, 3)] + _random(rng, 300.0)

	func load_into(brains: Object) -> void:
		var packed_bases := PackedVector3Array()
		for b: Basis in bases:
			packed_bases.append_array([b.x, b.y, b.z])
		assert(brains.load_rows(ids, positions, velocities, packed_bases, radii, kinds, factions, is_ship, hulls, target_ids,
				reaches, names), "the rows load")
		assert(brains.load_bolts(bolt_positions, bolt_velocities, bolt_factions, bolt_shooters), "the bolts load")

	## The scan the GDScript twin perceives from: the same rows, on the GDScript path.
	func scan() -> ContactScan:
		var s := ContactScan.new()
		s.use_native = false
		s._body_ids = ids
		s._ids = ids
		s._names = names
		for f: int in factions:
			s._factions.append(SIDES[f])
		s._positions = positions
		s._velocities = velocities
		for b: Basis in bases:
			s._forwards.append(-b.z.normalized())
			s._ups.append(b.y.normalized())
		s._radii = radii
		s._is_ship = is_ship
		s._hulls = hulls
		s._target_ids = target_ids
		s._kinds = kinds
		s._node_count = ids.size()
		s._bolt_positions = bolt_positions
		s._bolt_velocities = bolt_velocities
		for f: int in bolt_factions:
			s._bolt_factions.append(SIDES[f])
		s._bolt_shooters = bolt_shooters
		return s

	## The broadcast scan: the broadcasters only, with their reach.
	func broadcast_scan() -> ContactScan:
		var s := ContactScan.new()
		s.use_native = false
		for i: int in ids.size():
			if reaches[i] <= 0.0:
				continue
			s._body_ids.append(ids[i])
			s._ids.append(ids[i])
			s._names.append(names[i])
			s._factions.append(SIDES[factions[i]])
			s._positions.append(positions[i])
			s._velocities.append(velocities[i])
			s._forwards.append(-bases[i].z.normalized())
			s._ups.append(bases[i].y.normalized())
			s._radii.append(radii[i])
			s._is_ship.append(is_ship[i])
			s._hulls.append(hulls[i])
			s._target_ids.append(target_ids[i])
			s._kinds.append(kinds[i])
			s._reach.append(reaches[i])
		s._node_count = s._ids.size()
		return s


# --- the twins ---------------------------------------------------------------------------------------------------------


## One asking ship: its GDScript pilot and its native slot, with everything the driver would give them.
class Twin:
	var row: int = 0
	var pilot: AiPilot = null
	var slot: int = -1
	var cap: ShipCapability = null
	var muzzle_local: Vector3 = Vector3(0.0, -1.4, -2.0)
	var radius: float = 10.0
	var tie_hash: int = 0
	var last_hit_s: float = -INF
	var last_bolt_hit_s: float = -INF
	var last_attacker_id: int = 0
	var selected_id: int = 0
	var friendly_fire: bool = false
	var now_s: float = 0.0
	var origin: UniversePos = UniversePos.new(12000.5, -300.25, 777.0)


static func _capability(rng: RandomNumberGenerator) -> ShipCapability:
	var cap := ShipCapability.new()
	cap.a_main = rng.randf_range(15.0, 40.0)
	cap.a_retro = rng.randf_range(5.0, 20.0)
	cap.a_rcs = Vector2(rng.randf_range(3.0, 12.0), rng.randf_range(3.0, 12.0))
	cap.rate_max_rad = Vector3(rng.randf_range(0.8, 2.0), rng.randf_range(0.8, 2.0), rng.randf_range(1.0, 3.0))
	cap.alpha_max_rad = Vector3(rng.randf_range(1.0, 4.0), rng.randf_range(1.0, 4.0), rng.randf_range(1.0, 6.0))
	return cap


static func _profile(name: StringName) -> AiProfile:
	return AiProfile.load_named(name)


## The twin's GDScript perception this tick, picked as the driver picks it.
static func _perceive(t: Twin, rows: Rows, scan: ContactScan, broadcasts: ContactScan) -> Perception:
	var p := Perception.new()
	p.now_s = t.now_s
	p.position = rows.positions[t.row]
	p.basis = rows.bases[t.row]
	p.velocity = rows.velocities[t.row]
	p.angular_velocity = Vector3.ZERO
	p.self_id = rows.ids[t.row]
	p.hull_fraction = rows.hulls[t.row]
	p.faction = SIDES[rows.factions[t.row]]
	p.capability = t.cap
	p.muzzle_offset = p.basis * t.muzzle_local
	p.muzzle_speed_mps = 650.0
	p.weapon_lifetime_s = 3.0
	p.frame_origin = t.origin
	var own_id: int = rows.ids[t.row]
	var keeper: Callable = func() -> Array:
		var ids: PackedInt64Array = t.pilot.keep_ids().duplicate()
		if t.selected_id != 0:
			ids.append(t.selected_id)
		if t.last_attacker_id != 0 and t.now_s - t.last_hit_s <= AiPilotDriver.KEEP_ATTACKER_S:
			ids.append(t.last_attacker_id)
		return [ids, t.pilot.keep_names()]
	p.contacts = scan.nearest_for(own_id, p.position, p.faction, NEAREST_K, keeper)
	p.contact_rows = scan.picked_rows
	p.statics = scan.statics_for(own_id, p.position, p.faction, STATIC_K)
	p.static_rows = scan.picked_rows
	p.incoming_fire = scan.incoming_fire(own_id, p.position, p.velocity, p.faction)
	p.broadcasts = broadcasts.broadcasts_for(own_id, p.position, p.faction)
	p.last_hit_s = t.last_hit_s
	p.last_bolt_hit_s = t.last_bolt_hit_s
	p.last_attacker_id = t.last_attacker_id
	p.friendly_fire = t.friendly_fire
	return p


## The GDScript think with the driver's avoidance, as `[flight fields..., fire, wanted, avoiding, urgent, has_desired, all_axes,
## desired, current id, raw scores, weighted scores]` strings of bytes.
static func _think_gdscript(t: Twin, p: Perception) -> PackedStringArray:
	t.pilot.has_desired_velocity = false
	var pc: PilotCommand = t.pilot.think(p, DT)
	var avoiding: bool = false
	var urgent: bool = false
	if not pc.flight.brake and not (p.contacts.is_empty() and p.statics.is_empty()):
		var wish: Vector3 = t.pilot.desired_velocity if t.pilot.has_desired_velocity else p.velocity
		var result: Dictionary = AvoidanceMath.filter_seen(p, t.radius, wish, t.pilot.avoid_exempt_id, t.tie_hash)
		var filtered: Vector3 = result["v_des"]
		if filtered != wish:
			avoiding = true
			urgent = bool(result["urgent"])
			var horizon: float = AiPilotDriver.URGENT_SEEK_HORIZON_S if urgent else PilotSteering.HORIZON_S
			PilotSteering.apply_seek(pc.flight, PilotSteering.seek(p.velocity, filtered, p.basis, p.capability, horizon,
					t.pilot.has_desired_velocity and t.pilot.desired_all_axes))
	return _digest(pc.flight, pc.combat.fire, t.pilot.wanted_target_id, avoiding, urgent, t.pilot.has_desired_velocity,
			t.pilot.desired_all_axes, t.pilot.desired_velocity, String(t.pilot.current.id) if t.pilot.current != null else "none",
			_scores(t.pilot, false), _scores(t.pilot, true))


static func _scores(pilot: AiPilot, weighted: bool) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for id: StringName in AiPilot.TIE_ORDER:
		out.append(pilot.score_of(id) if weighted else pilot.raw_score_of(id))
	return out


static func _digest(flight: FlightCommand, fire: bool, wanted: int, avoiding: bool, urgent: bool, has_desired: bool,
		all_axes: bool, desired: Vector3, current: String, raw: PackedFloat64Array, weighted: PackedFloat64Array) -> PackedStringArray:
	return PackedStringArray(["levels %s %s %s %s" % [_bytes(flight.main_left), _bytes(flight.main_right), _bytes(flight.retro_left),
			_bytes(flight.retro_right)], "strafe %s" % _bytes(flight.strafe), "rot %s" % _bytes(flight.rot), "brake %s" % flight.brake,
			"fire %s" % fire, "wanted %d" % wanted, "avoiding %s %s" % [avoiding, urgent], "desired %s %s %s" % [has_desired, all_axes,
			_bytes(desired) if has_desired else ""], "current %s" % current, "raw %s" % _bytes(raw), "weighted %s" % _bytes(weighted)])


## The native think as the same digest (`AiPilot.NATIVE_*` give the output's layout).
static func _think_native(brains: Object, t: Twin, rows: Rows, relations: PackedByteArray) -> PackedStringArray:
	var out: PackedFloat64Array = brains.think(t.slot, relations, t.now_s, DT, rows.hulls[t.row], t.selected_id,
			t.last_hit_s, t.last_bolt_hit_s, t.last_attacker_id, t.friendly_fire, t.origin.x, t.origin.y, t.origin.z)
	assert(not out.is_empty(), "the native think answered")
	var flight := FlightCommand.new()
	flight.main_left = out[AiPilot.NATIVE_MAIN_LEFT]
	flight.main_right = out[AiPilot.NATIVE_MAIN_LEFT + 1]
	flight.retro_left = out[AiPilot.NATIVE_MAIN_LEFT + 2]
	flight.retro_right = out[AiPilot.NATIVE_MAIN_LEFT + 3]
	flight.strafe = Vector2(out[AiPilot.NATIVE_STRAFE], out[AiPilot.NATIVE_STRAFE + 1])
	flight.rot = Vector3(out[AiPilot.NATIVE_ROT], out[AiPilot.NATIVE_ROT + 1], out[AiPilot.NATIVE_ROT + 2])
	flight.brake = out[AiPilot.NATIVE_BRAKE] != 0.0
	var wanted: int = AiPilot.native_target_id(out)
	var kind: int = int(out[AiPilot.NATIVE_CURRENT])
	var raw := PackedFloat64Array()
	var weighted := PackedFloat64Array()
	for i: int in AiPilot.TIE_ORDER.size():
		raw.append(out[AiPilot.NATIVE_RAW + i])
		weighted.append(out[AiPilot.NATIVE_WEIGHTED + i])
	return _digest(flight, out[AiPilot.NATIVE_FIRE] != 0.0, wanted, out[AiPilot.NATIVE_AVOIDING] != 0.0,
			out[AiPilot.NATIVE_AVOIDING + 1] != 0.0, out[AiPilot.NATIVE_HAS_DESIRED] != 0.0, out[AiPilot.NATIVE_ALL_AXES] != 0.0,
			Vector3(out[AiPilot.NATIVE_DESIRED], out[AiPilot.NATIVE_DESIRED + 1], out[AiPilot.NATIVE_DESIRED + 2]),
			String(AiPilot.TIE_ORDER[kind]) if kind >= 0 else "none", raw, weighted)


## Makes the twin's native slot as the facade does, from its GDScript pilot.
static func _make_slot(brains: Object, t: Twin, rows: Rows) -> void:
	var pilot: AiPilot = t.pilot
	t.slot = brains.create(pilot.seed_value, AiPilot.native_profile(pilot.base_profile), AiPilot.native_tactics(pilot.base_profile.tactics),
			AiPilot.native_kinds(pilot.behaviours), pilot.temperament.skill, pilot.temperament.aggression)
	assert(t.slot >= 0, "a slot was made")
	brains.set_settings(NEAREST_K, STATIC_K)
	brains.bind_ship(t.slot, AiPilot.native_capability(t.cap), t.muzzle_local, 650.0, 3.0, t.radius, t.tie_hash, rows.ids[t.row],
			rows.ids[t.row])


## Pushes the GDScript context's wing, objective, guard and route to the slot, as the facade does.
static func _push_context(brains: Object, t: Twin) -> void:
	AiPilot.native_push_context(brains, t.slot, t.pilot.context)


func _relations(own: int) -> PackedByteArray:
	var row := PackedByteArray()
	for other: StringName in SIDES:
		row.append(Factions.relation(SIDES[own], other))
	return row


## Runs `twins` beside their slots for `ticks`, with a seeded walk of the rows and the scripted events `hit_at` (tick ->
## twin index hit by a bolt), and lists the first differences.
func _run(brains: Object, rows: Rows, twins: Array[Twin], rng: RandomNumberGenerator, ticks: int, hit_at: Dictionary,
		label: String, events: Dictionary = {}) -> PackedStringArray:
	var differences := PackedStringArray()
	var scan: ContactScan = rows.scan()
	var broadcasts: ContactScan = rows.broadcast_scan()
	rows.load_into(brains)
	for tick: int in ticks:
		if events.has(tick):
			(events[tick] as Callable).call()
			scan = rows.scan()
			broadcasts = rows.broadcast_scan()
			rows.load_into(brains)
		for i: int in twins.size():
			var t: Twin = twins[i]
			t.now_s += DT
			if hit_at.has(tick) and int(hit_at[tick]) == i:
				t.last_hit_s = t.now_s
				t.last_bolt_hit_s = t.now_s
				t.last_attacker_id = rows.ids[(t.row + 1) % rows.ids.size()]
			if tick % 37 == 0:
				t.selected_id = rows.ids[rng.randi_range(0, rows.ids.size() - 1)] if rng.randf() < 0.5 else 0
			var p: Perception = _perceive(t, rows, scan, broadcasts)
			var a: PackedStringArray = _think_gdscript(t, p)
			var b: PackedStringArray = _think_native(brains, t, rows, _relations(rows.factions[t.row]))
			if a != b:
				var lists: Array = brains.last_lists()
				var wish: Vector3 = t.pilot.desired_velocity if t.pilot.has_desired_velocity else p.velocity
				var filtered: Dictionary = AvoidanceMath.filter_seen(p, t.radius, wish, t.pilot.avoid_exempt_id, t.tie_hash)
				var kernels: Object = NativeLib.instantiate(ContactScan.PILOT_CLASS)
				kernels.load(rows.ids, rows.positions, rows.velocities, rows.radii, rows.kinds, rows.factions, rows.is_ship)
				var avoided: Vector4 = kernels.avoid(p.contact_rows, p.static_rows, t.pilot.avoid_exempt_id, p.position, p.velocity,
						t.radius, wish, t.cap.a_retro, t.cap.rate_max_rad, t.cap.a_rcs, hash(t.tie_hash))
				differences.append("%s: twin %d tick %d (%d contacts, %d statics, incoming %d): native %s | gdscript %s | rows native %s %s gdscript %s %s | wish %s gd filtered %s %s kernel %s" % [
						label, i, tick, p.contacts.size(), p.statics.size(), p.incoming_fire, _differing(b, a), _differing(a, b),
						lists[0], lists[1], p.contact_rows, p.static_rows, _bytes(wish), _bytes(filtered["v_des"]), filtered["urgent"],
						_bytes(Vector3(avoided.x, avoided.y, avoided.z))])
			if differences.size() > 2:
				return differences
		rows.walk(rng, DT)
		scan = rows.scan()
		broadcasts = rows.broadcast_scan()
		rows.load_into(brains)
	return differences


## The fields of `a` that differ from `b`, for the message.
static func _differing(a: PackedStringArray, b: PackedStringArray) -> String:
	var out := PackedStringArray()
	for k: int in a.size():
		if a[k] != b[k]:
			out.append(a[k])
	return " ; ".join(out)


func _twin(rows: Rows, row: int, profile: StringName, seed_value: int, rng: RandomNumberGenerator, skill: float = -1.0,
		aggression: float = -1.0) -> Twin:
	var t := Twin.new()
	t.row = row
	var base: AiProfile = _profile(profile)
	var temperament: AiTemperament = null
	if skill >= 0.0:
		temperament = AiTemperament.new(skill, aggression)
	t.pilot = AiPilot.new(base, seed_value, [] as Array[AiBehaviour], temperament)
	t.cap = _capability(rng)
	t.radius = rows.radii[row]
	t.tie_hash = hash("SHIP %d" % row)
	return t


func test_a_plain_crowd_thinks_the_same_natively_tick_by_tick() -> void:
	if _skipped():
		return
	var brains: Object = NativeLib.instantiate(BRAINS_CLASS)
	assert_not_null(brains)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1707
	var rows := Rows.new(rng, 30, 12, 20, 2500.0)
	var twins: Array[Twin] = []
	for i: int in 6:
		var t: Twin = _twin(rows, i, [&"ally_starfury", &"raider"][i % 2], 100 + i, rng)
		t.friendly_fire = i % 3 == 0
		_make_slot(brains, t, rows)
		t.pilot.reset()
		brains.reset(t.slot)
		twins.append(t)
	var differences: PackedStringArray = _run(brains, rows, twins, rng, TICKS, {40: 0, 41: 0, 90: 2, 150: 4}, "crowd")
	assert_eq(differences.size(), 0, "the native brains think the same bits as the GDScript twins: %s" % differences.slice(0, 4))


func test_wings_under_each_order_and_a_leaderless_wing_think_the_same() -> void:
	if _skipped():
		return
	var brains: Object = NativeLib.instantiate(BRAINS_CLASS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1708
	var rows := Rows.new(rng, 24, 6, 10, 1800.0)
	var twins: Array[Twin] = []
	var formation := Formation.new()
	for i: int in 8:
		var t: Twin = _twin(rows, i, &"ally_starfury", 200 + i, rng)
		_make_slot(brains, t, rows)
		var ctx: AiContext = t.pilot.context
		var leader_row: int = (i + 4) % rows.ids.size()
		ctx.order = [AiContext.Order.COVER_ME, AiContext.Order.FORM_ON_ME, AiContext.Order.ATTACK_MY_TARGET,
				AiContext.Order.ENGAGE_AT_WILL][i % 4] as AiContext.Order
		ctx.leader_id = rows.ids[leader_row] if i < 6 else 0
		ctx.leader_target_id = rows.target_ids[leader_row] if i % 2 == 0 else rows.ids[(i + 9) % rows.ids.size()]
		ctx.has_slot = i < 7
		ctx.slot_offset = formation.offset(1 + i % 3)
		ctx.wing_ids = PackedInt64Array([rows.ids[leader_row], rows.ids[(i + 5) % rows.ids.size()], rows.ids[(i + 6) % rows.ids.size()]])
		if i % 3 == 1:
			ctx.leader_link_position = t.origin.plus_local(rows.positions[leader_row] + Vector3(9000.0, 0.0, 0.0))
			ctx.leader_link_velocity = Vector3(30.0, 0.0, -20.0)
		t.pilot.add_behaviour(BehaviourFormation.new(t.pilot.profile))
		t.pilot.add_behaviour(BehaviourRally.new(t.pilot.profile))
		brains.add_behaviour(t.slot, AiPilot.TIE_ORDER.find(&"formation"))
		brains.add_behaviour(t.slot, AiPilot.TIE_ORDER.find(&"rally"))
		t.pilot.reset()
		brains.reset(t.slot)
		_push_context(brains, t)
		twins.append(t)
	var differences: PackedStringArray = _run(brains, rows, twins, rng, TICKS, {60: 1, 120: 3}, "wings")
	assert_eq(differences.size(), 0, "wing pilots think the same bits natively: %s" % differences.slice(0, 4))


func test_objectives_guards_temperaments_and_live_retunes_think_the_same() -> void:
	if _skipped():
		return
	var brains: Object = NativeLib.instantiate(BRAINS_CLASS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1709
	var rows := Rows.new(rng, 28, 10, 16, 3000.0)
	var twins: Array[Twin] = []
	for i: int in 8:
		var skill: float = [0.2, 0.45, 0.7, 0.95][i % 4]
		var aggression: float = [0.0, 0.25, 0.75, 1.0][i % 4]
		var t: Twin = _twin(rows, i, [&"raider", &"civilian", &"ally_starfury", &"instructor"][i % 4], 300 + i, rng, skill, aggression)
		_make_slot(brains, t, rows)
		match i % 4:
			0:
				t.pilot.context.objective_name = rows.names[(i + 7) % 28].to_lower()
			1:
				BehaviourGuard.attach(t.pilot, t.origin.plus_local(rows.positions[i] + Vector3(300.0, 0.0, 0.0)), "", Vector3.ZERO, 1200.0)
				brains.add_behaviour(t.slot, AiPilot.TIE_ORDER.find(&"guard"))
			2:
				BehaviourGuard.attach(t.pilot, null, rows.names[(i + 3) % 28], Vector3(40.0, 0.0, 60.0), 900.0)
				brains.add_behaviour(t.slot, AiPilot.TIE_ORDER.find(&"guard"))
		t.pilot.reset()
		brains.reset(t.slot)
		_push_context(brains, t)
		twins.append(t)
	# At tick 40 the objective's name moves to another body and the guarded ship is renamed: both twins must follow the
	# names, as the GDScript matches them every tick.
	var swap: Callable = func() -> void:
		var a: int = (0 + 7) % 28
		var b: int = (a + 11) % 28
		var name_a: String = rows.names[a]
		rows.names[a] = rows.names[b]
		rows.names[b] = name_a
		rows.names[(2 + 3) % 28] = "ELSEWHERE"
	var differences: PackedStringArray = _run(brains, rows, twins, rng, TICKS / 2, {20: 1, 70: 5}, "objectives", {40: swap})
	# A live retune, as the console does it: both sides change together.
	for i: int in twins.size():
		var t: Twin = twins[i]
		var again := AiTemperament.new([0.95, 0.2][i % 2], [1.0, 0.5][i % 2])
		t.pilot.set_temperament(again)
		brains.set_temperament(t.slot, again.skill, again.aggression)
	differences.append_array(_run(brains, rows, twins, rng, TICKS / 2, {30: 0}, "retuned"))
	assert_eq(differences.size(), 0, "objectives, guards, temperaments and retunes think the same bits: %s" % differences.slice(0, 4))


func test_a_patrol_route_with_demos_flies_the_same() -> void:
	if _skipped():
		return
	var brains: Object = NativeLib.instantiate(BRAINS_CLASS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1710
	var rows := Rows.new(rng, 10, 0, 0, 900.0)
	var twins: Array[Twin] = []
	for i: int in 3:
		var t: Twin = _twin(rows, i, &"instructor", 400 + i, rng)
		_make_slot(brains, t, rows)
		var route := Route.new()
		route.name = "LESSON"
		route.cruise_mps = 60.0
		route.loop = i == 2
		route.yield_to_attack = i == 1
		route.pace = Route.PACE_PLAYER if i == 0 else Route.PACE_NONE
		route.pace_id = rows.ids[5] if i == 0 else 0
		for w: int in 4:
			route.add(t.origin.plus_local(rows.positions[i] + Vector3(200.0 * float(w + 1), 0.0, -100.0 * float(w))),
					Manoeuvres.NAMES[(w + i) % Manoeuvres.NAMES.size()] if w % 2 == 0 else &"", 1.0 if w == 1 else 0.0)
		BehaviourFollowPath.attach(t.pilot, route)
		brains.add_behaviour(t.slot, AiPilot.TIE_ORDER.find(&"follow_path"))
		t.pilot.reset()
		brains.reset(t.slot)
		_push_context(brains, t)
		twins.append(t)
	# The leaders fly their routes: rows 0 to 2 move as the twins' commands would roughly take them, so waypoints are reached.
	var differences := PackedStringArray()
	var scan: ContactScan = rows.scan()
	var broadcasts: ContactScan = rows.broadcast_scan()
	rows.load_into(brains)
	for tick: int in TICKS * 2:
		for i: int in twins.size():
			var t: Twin = twins[i]
			t.now_s += DT
			var p: Perception = _perceive(t, rows, scan, broadcasts)
			var a: PackedStringArray = _think_gdscript(t, p)
			var b: PackedStringArray = _think_native(brains, t, rows, _relations(rows.factions[t.row]))
			for k: int in a.size():
				if a[k] != b[k]:
					differences.append("route: twin %d tick %d: %s | %s" % [i, tick, b[k], a[k]])
					break
			# Fly toward the wish: the route's waypoints come within reach, so arrivals, demos and holds happen.
			if t.pilot.has_desired_velocity:
				rows.velocities[t.row] = rows.velocities[t.row].lerp(t.pilot.desired_velocity, 0.2)
			var to_nose: Vector3 = PilotSteering.face(rows.bases[t.row], rows.velocities[t.row], t.cap.rate_max_rad)
			rows.bases[t.row] = (rows.bases[t.row] * Basis.from_euler(Vector3(to_nose.x, -to_nose.y, 0.0) * 0.05)).orthonormalized()
		if differences.size() > 6:
			break
		rows.walk(rng, DT)
		scan = rows.scan()
		broadcasts = rows.broadcast_scan()
		rows.load_into(brains)
	var path := twins[2].pilot.behaviour(&"follow_path") as BehaviourFollowPath
	assert_gt(path.visited.size(), 0, "the looping route reached a waypoint in the run")
	assert_eq(differences.size(), 0, "the routes and demos fly the same bits natively: %s" % differences.slice(0, 4))


func test_a_duplicate_name_follows_the_first_listed_row_as_the_gdscript_does() -> void:
	# M4-T18: a row earlier in the row order (out of sensor range: a parked or far body) carries the same name as a live ship
	# in range. The GDScript matches the name among the contacts every tick, so the objective and the guarded ship are the
	# live one; the native brains must not stick to the first row with the name.
	if _skipped():
		return
	var brains: Object = NativeLib.instantiate(BRAINS_CLASS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1711
	var rows := Rows.new(rng, 28, 6, 10, 2000.0)
	var live: int = 15
	var stale: int = 9
	rows.names[stale] = rows.names[live]
	rows.positions[stale] = Vector3(40000.0, 0.0, 0.0)
	rows.velocities[stale] = Vector3.ZERO
	var twins: Array[Twin] = []
	for i: int in 6:
		var t: Twin = _twin(rows, i, [&"raider", &"ally_starfury", &"civilian"][i % 3], 500 + i, rng)
		_make_slot(brains, t, rows)
		if i % 2 == 0:
			t.pilot.context.objective_name = rows.names[live].to_lower()
		else:
			BehaviourGuard.attach(t.pilot, null, rows.names[live], Vector3(30.0, 0.0, 50.0), 900.0)
			brains.add_behaviour(t.slot, AiPilot.TIE_ORDER.find(&"guard"))
		t.pilot.reset()
		brains.reset(t.slot)
		_push_context(brains, t)
		twins.append(t)
	var differences: PackedStringArray = _run(brains, rows, twins, rng, TICKS / 2, {25: 1}, "duplicate name")
	assert_eq(differences.size(), 0, "a duplicate name follows the listed row, bit for bit: %s" % differences.slice(0, 4))
