extends GutTest
## The pilot kernels (M4-T16, architecture §17.13): avoidance, the fire lane and the context lists in native code, one call
## per thinking ship over the core's rows. `AvoidanceMath`, `FireLane` and `AiContext.refresh` stay the reference: on seeded
## contacts (head-on, dead-centre ties, contacts inside the margin, matched velocities, rocks and mines, lanes grazed at
## their edge) the native kernels give the same filtered velocity, lane verdict and lists bit for bit. The kernels live in
## the engine-free module (`native/src/kernels.rs`, `pub mod pilot`), so T18 can run them on worker threads. Here the
## kernels read rows loaded from arrays (`ScsPilotKernels.load`); `test_pilot_kernels_in_play` reads them from the core.
## Skips, saying why, when the native library is not built at all.

const PILOT_CLASS: StringName = &"ScsPilotKernels"
const KERNEL_FILE: String = "res://native/src/kernels.rs"
const SHELL_FILE: String = "res://native/src/pilot_kernels.rs"
const CASES: int = 600

var _saved_native: bool = true


func before_each() -> void:
	_saved_native = bool(Settings.get_value(&"perf_native"))
	Settings.set_value(&"perf_native", true)


func after_each() -> void:
	Settings.set_value(&"perf_native", _saved_native)


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there are no kernels to test")
	return true


func _kernels() -> Object:
	var kernels: Object = NativeLib.instantiate(PILOT_CLASS)
	assert_not_null(kernels, "the library provides %s (%s)" % [PILOT_CLASS, NativeLib.version(NativeProbe.NATIVE_CLASS)])
	return kernels


# --- seeded worlds -----------------------------------------------------------------------------------------------------


## A table of rows in a shuffled order, the contacts and statics at those rows, and the asking ship's relation to each of
## four factions (one relation row per case, as `ContactScan.relation_row` builds it).
class Table:
	var contacts: Array[Contact] = []
	var statics: Array[Contact] = []
	var contact_rows := PackedInt32Array()
	var static_rows := PackedInt32Array()
	var relations := PackedByteArray()
	var ids := PackedInt64Array()
	var positions := PackedVector3Array()
	var velocities := PackedVector3Array()
	var radii := PackedFloat64Array()
	var kinds := PackedByteArray()
	var factions := PackedInt32Array()
	var is_ship := PackedByteArray()

	func _init(rng: RandomNumberGenerator) -> void:
		for f: int in 4:
			relations.append(rng.randi_range(0, 2))

	## Lays the contacts and statics out as rows in a seeded order and notes each one's row.
	func lay_out(rng: RandomNumberGenerator, faction_of: Dictionary) -> void:
		var all: Array[Contact] = contacts + statics
		var order: Array[int] = []
		for i: int in all.size():
			order.append(i)
		for i: int in range(order.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var t: int = order[i]
			order[i] = order[j]
			order[j] = t
		var row_of: Dictionary = {}
		for row: int in order.size():
			var c: Contact = all[order[row]]
			row_of[c] = row
			ids.append(c.id)
			positions.append(c.position)
			velocities.append(c.velocity)
			radii.append(c.bounding_radius)
			kinds.append(c.kind)
			factions.append(faction_of[c])
			is_ship.append(1 if c.is_ship else 0)
		for c: Contact in contacts:
			contact_rows.append(row_of[c])
		for c: Contact in statics:
			static_rows.append(row_of[c])

	func load_into(kernels: Object) -> bool:
		return kernels.load(ids, positions, velocities, radii, kinds, factions, is_ship)


static func _unit(rng: RandomNumberGenerator) -> Vector3:
	var v := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	return v.normalized() if v.length_squared() > 1e-6 else Vector3.UP


static func _vec(rng: RandomNumberGenerator, scale: float) -> Vector3:
	return _unit(rng) * rng.randf_range(0.0, scale)


static func _cap(rng: RandomNumberGenerator) -> ShipCapability:
	var cap := ShipCapability.new()
	cap.a_retro = rng.randf_range(0.0, 30.0) if rng.randf() > 0.05 else 0.0
	cap.a_rcs = Vector2(rng.randf_range(0.0, 15.0), rng.randf_range(0.0, 15.0))
	cap.rate_max_rad = Vector3(rng.randf_range(0.0, 3.0), rng.randf_range(0.0, 3.0), rng.randf_range(0.0, 3.0))
	return cap


# A contact of the faction `f` (its relation from the table's row), made for one of the seeded situations.
static func _contact(rng: RandomNumberGenerator, table: Table, faction_of: Dictionary, id: int, own_pos: Vector3,
		v_des: Vector3, own_radius: float) -> Contact:
	var c := Contact.new()
	c.id = id
	var f: int = rng.randi_range(0, 3)
	faction_of[c] = f
	c.relation = table.relations[f] as Factions.Relation
	c.is_ship = rng.randf() < 0.8
	c.kind = [BodyKind.SHIP, BodyKind.CAPITAL, BodyKind.PROP, BodyKind.TURRET][rng.randi_range(0, 3)]
	c.bounding_radius = rng.randf_range(0.0, 60.0) if rng.randf() > 0.05 else 0.0
	var reach: float = own_radius + c.bounding_radius + AvoidanceMath.MARGIN_M
	match rng.randi_range(0, 6):
		0:  # anywhere in the sensor range, any motion
			c.position = own_pos + _vec(rng, 3000.0)
			c.velocity = _vec(rng, 300.0)
		1:  # a dead-centre course: the relative velocity points straight at the contact
			var dir: Vector3 = _unit(rng)
			c.position = own_pos + dir * rng.randf_range(reach, 2000.0)
			c.velocity = v_des - dir * rng.randf_range(5.0, 200.0)
		2:  # on top of the ship: a tie inside the margin (sometimes with no relative velocity at all)
			c.position = own_pos + (_vec(rng, 0.09) if rng.randf() < 0.5 else Vector3.ZERO)
			c.velocity = v_des if rng.randf() < 0.3 else _vec(rng, 100.0)
		3:  # inside the margin
			c.position = own_pos + _unit(rng) * rng.randf_range(0.0, reach)
			c.velocity = _vec(rng, 50.0)
		4:  # flying together: matched velocities, near or just outside the margin
			c.position = own_pos + _unit(rng) * rng.randf_range(0.5 * reach, 3.0 * reach)
			c.velocity = v_des + _vec(rng, 3.5)
		5:  # a near miss: the closest approach about the reach
			var dir: Vector3 = _unit(rng)
			var side: Vector3 = dir.cross(_unit(rng)).normalized()
			c.position = own_pos + dir * rng.randf_range(100.0, 1500.0) + side * reach * rng.randf_range(0.5, 1.5)
			c.velocity = v_des - dir * rng.randf_range(10.0, 250.0)
		_:  # crossing at speed
			c.position = own_pos + _vec(rng, 1500.0)
			c.velocity = (own_pos - c.position).normalized().cross(_unit(rng)) * rng.randf_range(0.0, 250.0)
	return c


static func _static(rng: RandomNumberGenerator, table: Table, faction_of: Dictionary, id: int, own_pos: Vector3) -> Contact:
	var c := Contact.new()
	c.id = id
	var f: int = rng.randi_range(0, 3)
	faction_of[c] = f
	c.relation = table.relations[f] as Factions.Relation
	c.is_ship = false
	c.kind = BodyKind.MINE if rng.randf() < 0.3 else BodyKind.STATIC
	c.bounding_radius = rng.randf_range(20.0, 300.0)
	c.position = own_pos + _unit(rng) * (c.bounding_radius + rng.randf_range(-20.0, 1500.0))
	return c


# --- the engine seam ---------------------------------------------------------------------------------------------------


func test_the_pilot_kernels_live_in_the_engine_free_module() -> void:
	var kernels: String = FileAccess.get_file_as_string(KERNEL_FILE)
	assert_true(kernels.contains("pub mod pilot"), "the pilot kernels are a module of kernels.rs, which test_sim_core keeps engine-free")
	for name: String in ["pub fn avoid(", "pub fn fire_lane(", "pub fn context_lists("]:
		assert_true(kernels.contains(name), "kernels.rs holds %s" % name)
	var shell: String = FileAccess.get_file_as_string(SHELL_FILE)
	assert_true(shell.contains("use crate::kernels::pilot"), "the shell takes its maths from the kernels")
	for maths: String in ["fn tie_direction", "fn sideways_speed", ".sqrt()", ".cos()"]:
		assert_false(shell.contains(maths), "the shell holds no maths of its own (%s)" % maths)


# --- avoidance ---------------------------------------------------------------------------------------------------------


func test_avoidance_matches_the_gdscript_filter_bit_for_bit_on_seeded_contacts() -> void:
	if _skipped():
		return
	var kernels: Object = _kernels()
	if kernels == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1600
	var differences: PackedStringArray = []
	var dodged: int = 0
	var urgent: int = 0
	var exempted: int = 0
	for case: int in CASES:
		var table := Table.new(rng)
		var faction_of: Dictionary = {}
		var own_pos: Vector3 = _vec(rng, 20000.0)
		var v_des: Vector3 = _vec(rng, 250.0) if rng.randf() > 0.05 else Vector3.ZERO
		var own_vel: Vector3 = v_des + _vec(rng, 80.0) if rng.randf() > 0.1 else v_des
		var own_radius: float = rng.randf_range(0.0, 40.0)
		var cap: ShipCapability = _cap(rng)
		var seed_value: int = hash("SHIP %d" % rng.randi()) if rng.randf() < 0.5 else rng.randi() - (1 << 31)
		for i: int in rng.randi_range(0, 16):
			table.contacts.append(_contact(rng, table, faction_of, 1000 + i, own_pos, v_des, own_radius))
		for s: int in rng.randi_range(0, 4) if rng.randf() < 0.5 else 0:
			table.statics.append(_static(rng, table, faction_of, 900000 + s, own_pos))
		table.lay_out(rng, faction_of)
		assert_true(table.load_into(kernels), "case %d: the rows load" % case)
		var exempt_id: int = 0
		if not table.contacts.is_empty() and rng.randf() < 0.3:
			exempt_id = table.contacts[rng.randi_range(0, table.contacts.size() - 1)].id
			exempted += 1
		var reference: Dictionary = _reference_filter(table, exempt_id, own_pos, own_vel, own_radius, v_des, cap, seed_value)
		var native: Vector4 = kernels.avoid(table.contact_rows, table.static_rows, exempt_id, own_pos, own_vel, own_radius,
				v_des, cap.a_retro, cap.rate_max_rad, cap.a_rcs, hash(seed_value))
		var filtered := Vector3(native.x, native.y, native.z)
		if var_to_bytes(filtered) != var_to_bytes(reference["v_des"]) or (native.w > 0.5) != bool(reference["urgent"]):
			differences.append("case %d: native %s urgent %s, GDScript %s urgent %s" % [case, filtered, native.w > 0.5,
					reference["v_des"], reference["urgent"]])
		dodged += 1 if reference["v_des"] != v_des else 0
		urgent += 1 if reference["urgent"] else 0
	assert_eq(differences.size(), 0, "the native filter is the GDScript filter bit for bit: %s" % differences.slice(0, 4))
	assert_gt(dodged, CASES / 3, "the seeded cases dodge often (%d of %d)" % [dodged, CASES])
	assert_gt(urgent, CASES / 10, "and are often urgent (%d)" % urgent)
	assert_gt(exempted, CASES / 5, "a rammer's exempt target is left out in many cases (%d)" % exempted)


# The driver's avoidance before M4-T16: the contacts but the exempt one, then the statics, through `AvoidanceMath.filter`.
static func _reference_filter(table: Table, exempt_id: int, own_pos: Vector3, own_vel: Vector3, own_radius: float,
		v_des: Vector3, cap: ShipCapability, seed_value: int) -> Dictionary:
	var contacts: Array[Contact] = []
	for c: Contact in table.contacts:
		if exempt_id == 0 or c.id != exempt_id:
			contacts.append(c)
	contacts.append_array(table.statics)
	return AvoidanceMath.filter(own_pos, own_vel, own_radius, contacts, v_des, cap, seed_value)


func test_dead_centre_ties_break_the_same_way_natively_for_every_seed() -> void:
	if _skipped():
		return
	var kernels: Object = _kernels()
	if kernels == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1601
	var differences: PackedStringArray = []
	var sides: Dictionary = {}
	for case: int in 400:
		var table := Table.new(rng)
		var faction_of: Dictionary = {}
		var c := Contact.new()
		c.id = 7
		faction_of[c] = 0
		c.is_ship = true
		c.bounding_radius = 10.0
		# Half on top of the ship (a tie inside the margin), half on a dead-centre course from far off; some with the
		# relative velocity straight up or down (the "right" falls back to world right) or zero (the axis is forward).
		var v_des: Vector3 = [_vec(rng, 200.0), Vector3(0.0, rng.randf_range(10.0, 90.0), 0.0), Vector3.ZERO][case % 3]
		if case % 2 == 0:
			c.position = Vector3(3.0, -2.0, 1.0)
			c.velocity = _vec(rng, 50.0) if case % 3 != 2 else v_des
		else:
			var dir: Vector3 = v_des.normalized() if v_des != Vector3.ZERO else Vector3.FORWARD
			c.position = Vector3(3.0, -2.0, 1.0) + dir * 600.0
			c.velocity = -dir * 40.0
		table.contacts.append(c)
		table.lay_out(rng, faction_of)
		table.load_into(kernels)
		var cap := ShipCapability.new()
		var seed_value: int = case * 7919 - 1000000
		var reference: Dictionary = AvoidanceMath.filter(Vector3(3.0, -2.0, 1.0), v_des, 10.0, table.contacts, v_des, cap,
				seed_value)
		var native: Vector4 = kernels.avoid(table.contact_rows, table.static_rows, 0, Vector3(3.0, -2.0, 1.0), v_des, 10.0,
				v_des, cap.a_retro, cap.rate_max_rad, cap.a_rcs, hash(seed_value))
		var filtered := Vector3(native.x, native.y, native.z)
		if var_to_bytes(filtered) != var_to_bytes(reference["v_des"]):
			differences.append("case %d (seed %d): native %s, GDScript %s" % [case, seed_value, filtered, reference["v_des"]])
		sides[reference["v_des"]] = true
	assert_eq(differences.size(), 0, "every tie breaks the same way natively: %s" % differences.slice(0, 4))
	assert_gt(sides.size(), 300, "the seeds spread the ties' sides (%d different)" % sides.size())


# --- the fire lane -----------------------------------------------------------------------------------------------------


func test_the_fire_lane_matches_the_gdscript_verdict_on_seeded_lanes() -> void:
	if _skipped():
		return
	var kernels: Object = _kernels()
	if kernels == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1602
	var differences: PackedStringArray = []
	var closed: int = 0
	for case: int in CASES * 2:
		var table := Table.new(rng)
		var faction_of: Dictionary = {}
		var own_pos: Vector3 = _vec(rng, 20000.0)
		var aim: Vector3 = _unit(rng) * (rng.randf_range(0.2, 3.0) if rng.randf() > 0.05 else 0.0)
		var range_m: float = rng.randf_range(0.0, 1500.0) if rng.randf() > 0.05 else -10.0
		var friendly_fire: bool = rng.randf() < 0.5
		var dir: Vector3 = aim.normalized() if aim != Vector3.ZERO else Vector3.FORWARD
		for i: int in rng.randi_range(0, 14):
			var c := Contact.new()
			c.id = 2000 + i
			var f: int = rng.randi_range(0, 3)
			faction_of[c] = f
			c.relation = table.relations[f] as Factions.Relation
			c.is_ship = rng.randf() < 0.75
			c.bounding_radius = rng.randf_range(0.0, 40.0)
			var side: Vector3 = dir.cross(_unit(rng)).normalized()
			var width: float = c.bounding_radius + FireLane.CLEARANCE_M
			# Along the lane (some behind, some past the range), off it by about the lane's width, some right at its edge.
			var along: float = rng.randf_range(-100.0, absf(range_m) + 100.0)
			var off: float = width * (rng.randf_range(0.0, 1.6) if rng.randf() > 0.2 else 1.0)
			c.position = own_pos + dir * along + side * off
			table.contacts.append(c)
		table.lay_out(rng, faction_of)
		table.load_into(kernels)
		var target_id: int = 0
		if not table.contacts.is_empty() and rng.randf() < 0.5:
			target_id = table.contacts[rng.randi_range(0, table.contacts.size() - 1)].id
		var reference: bool = FireLane.clear(own_pos, aim, range_m, table.contacts, target_id, friendly_fire)
		var native: bool = kernels.fire_lane(table.contact_rows, table.relations, own_pos, aim, range_m, target_id, friendly_fire)
		if native != reference:
			differences.append("case %d: native %s, GDScript %s" % [case, native, reference])
		closed += 0 if reference else 1
	assert_eq(differences.size(), 0, "the native lane is the GDScript lane: %s" % differences.slice(0, 4))
	assert_gt(closed, CASES / 4, "many lanes are closed (%d)" % closed)


# --- the context lists -------------------------------------------------------------------------------------------------


func test_the_context_lists_match_the_gdscript_refresh_on_seeded_contacts() -> void:
	if _skipped():
		return
	var kernels: Object = _kernels()
	if kernels == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1603
	var differences: PackedStringArray = []
	var led: int = 0
	for case: int in CASES:
		var table := Table.new(rng)
		var faction_of: Dictionary = {}
		var own_pos: Vector3 = _vec(rng, 20000.0)
		for i: int in rng.randi_range(0, 20):
			table.contacts.append(_contact(rng, table, faction_of, 3000 + i, own_pos, Vector3.ZERO, 10.0))
		table.lay_out(rng, faction_of)
		table.load_into(kernels)
		var p := Perception.new()
		p.position = own_pos
		p.self_id = 0 if rng.randf() < 0.2 else 77
		p.contacts = table.contacts
		var ctx := AiContext.new()
		ctx.leader_id = 0
		if not table.contacts.is_empty() and rng.randf() < 0.7:
			ctx.leader_id = table.contacts[rng.randi_range(0, table.contacts.size() - 1)].id
		ctx.refresh(p)
		var lists: Array = kernels.context_lists(table.contact_rows, table.relations, own_pos, p.self_id, ctx.leader_id)
		var hostiles: Array[Contact] = []
		for i: int in lists[0] as PackedInt32Array:
			hostiles.append(table.contacts[i])
		var leader: Contact = table.contacts[lists[4]] if int(lists[4]) >= 0 else null
		var same: bool = hostiles == ctx.hostiles and var_to_bytes(lists[1]) == var_to_bytes(ctx.hostile_offsets) \
				and var_to_bytes(lists[2]) == var_to_bytes(ctx.hostile_ranges) and lists[3] == ctx.friendly_ids \
				and leader == ctx.leader
		if not same:
			differences.append("case %d: native %s, GDScript %s %s %s %s %s" % [case, lists, ctx.hostiles, ctx.hostile_offsets,
					ctx.hostile_ranges, ctx.friendly_ids, ctx.leader])
		led += 1 if ctx.leader != null else 0
	assert_eq(differences.size(), 0, "the native lists are the GDScript lists: %s" % differences.slice(0, 3))
	assert_gt(led, CASES / 10, "a leader is in sight in many cases (%d)" % led)


# --- bad input ---------------------------------------------------------------------------------------------------------


func test_rows_that_do_not_line_up_or_out_of_range_never_panic() -> void:
	if _skipped():
		return
	var kernels: Object = _kernels()
	if kernels == null:
		return
	var ok: bool = kernels.load(PackedInt64Array([1, 2]), PackedVector3Array([Vector3.ZERO]), PackedVector3Array(),
			PackedFloat64Array(), PackedByteArray(), PackedInt32Array(), PackedByteArray())
	assert_false(ok, "arrays that do not line up are refused")
	assert_push_error("array lengths differ")
	var v := Vector3(10.0, 0.0, 0.0)
	var out: Vector4 = kernels.avoid(PackedInt32Array([0, 5, -1]), PackedInt32Array([9]), 0, Vector3.ZERO, v, 5.0, v, 5.0,
			Vector3.ONE, Vector2.ONE, 0)
	assert_eq(Vector3(out.x, out.y, out.z), v, "rows it does not hold are no threat")
	assert_true(kernels.fire_lane(PackedInt32Array([3]), PackedByteArray(), Vector3.ZERO, Vector3.FORWARD, 100.0, 0, true),
			"nor do they close a lane")
	var lists: Array = kernels.context_lists(PackedInt32Array([4]), PackedByteArray(), Vector3.ZERO, 5, 0)
	assert_eq(lists[3], PackedInt64Array([5]), "nor are they listed: only the ship itself is a friend")
