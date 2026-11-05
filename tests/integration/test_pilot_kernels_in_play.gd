extends GutTest
## The pilot kernels on the core's rows (M4-T16, architecture §17.13): with the core on, a ship's perception carries the
## native kernels, the core rows of its contacts and statics (in the lists' order) and its relation to every faction of the
## core's table, and `AvoidanceMath.filter_seen`, `FireLane.clear_seen` and `AiContext.refresh` answer through the kernels
## exactly as the GDScript reference answers from the same contacts. Seeded crowds of ships, props, drones, rocks and mines
## of four sides; real AI ships for the driver. Skips, saying why, when the native library is not built at all.

const SIDES: Array[StringName] = [Factions.RAIDERS, Factions.EARTH_ALLIANCE, Factions.NEUTRAL, &"drifters"]
const RAIDER_SPEC: String = "res://assets/ships/raider_delta_v.tres"
const SETTINGS: Array[StringName] = [&"perf_native", &"perf_native_core"]

var world: WorldFrame
var projectiles: Node3D
var _saved: Dictionary = {}


func before_each() -> void:
	for key: StringName in SETTINGS:
		_saved[key] = Settings.get_value(key)
		Settings.set_value(key, true)
	Factions.reset()
	ContactScan.invalidate()
	ContactScan.clear_statics()
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)


func after_each() -> void:
	ContactScan.clear_statics()
	ContactScan.invalidate()
	for key: StringName in SETTINGS:
		Settings.set_value(key, _saved[key])
	Factions.reset()


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there are no kernels to test")
	return true


# A rigid body with a marker and a hull, as `ShipAssembly` builds them (without the rest of a ship).
func _body(at: Vector3, velocity: Vector3, faction: StringName, label: String, radius: float, kind: int) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.freeze = true
	world.add_child(body)
	body.add_to_group(WorldFrame.SHIFTABLE_GROUP)
	body.global_position = at
	body.linear_velocity = velocity
	var hull := Damageable.new()
	hull.faction = faction
	hull.bounding_radius = radius
	body.add_child(hull)
	var t := Targetable.new()
	t.name = "Targetable"
	t.display_name = label
	t.faction = faction
	t.kind = kind
	body.add_child(t)
	return body


# A drifting prop (a buoy): a plain node with a marker and a hull.
func _prop(at: Vector3, faction: StringName, label: String) -> Node3D:
	var prop := Node3D.new()
	world.add_child(prop)
	prop.add_to_group(WorldFrame.SHIFTABLE_GROUP)
	prop.global_position = at
	var hull := Damageable.new()
	hull.bounding_radius = 3.0
	hull.faction = faction
	prop.add_child(hull)
	var t := Targetable.new()
	t.display_name = label
	t.faction = faction
	t.velocity = Vector3(0.5, 0.0, -0.25)
	prop.add_child(t)
	return prop


# A seeded crowd within a few km: ships of four sides (some capitals), props, rocks and mines; returns the bodies.
func _crowd(rng: RandomNumberGenerator, n: int, statics: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for i: int in n:
		var at := Vector3(rng.randf_range(-1500.0, 1500.0), rng.randf_range(-500.0, 500.0), rng.randf_range(-1500.0, 1500.0))
		var side: StringName = SIDES[rng.randi_range(0, 3)]
		if rng.randf() < 0.1:
			out.append(_prop(at, side, "BUOY %d" % i))
			continue
		var kind: int = Targetable.Kind.CAPITAL if rng.randf() < 0.1 else Targetable.Kind.SHIP
		var velocity := Vector3(rng.randf_range(-150.0, 150.0), rng.randf_range(-50.0, 50.0), rng.randf_range(-150.0, 150.0))
		out.append(_body(at, velocity, side, "SHIP %d" % i, rng.randf_range(5.0, 30.0) if kind == Targetable.Kind.SHIP
				else rng.randf_range(100.0, 400.0), kind))
	for s: int in statics:
		var at := Vector3(rng.randf_range(-2000.0, 2000.0), rng.randf_range(-500.0, 500.0), rng.randf_range(-2000.0, 2000.0))
		var mine: bool = rng.randf() < 0.3
		ContactScan.register_static(800000 + s, at, 50.0 if mine else rng.randf_range(20.0, 200.0),
				BodyKind.MINE if mine else BodyKind.STATIC, SIDES[rng.randi_range(0, 3)] if mine else Factions.NEUTRAL, world)
	return out


func test_the_facades_answer_from_the_core_as_the_gdscript_reference_does() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1610
	var differences: PackedStringArray = []
	var on_rows: int = 0
	var queries: int = 0
	for round: int in 4:
		for node: Node in world.get_children():
			if node != projectiles:
				node.free()
		ContactScan.clear_statics()
		ContactScan.invalidate()
		var bodies: Array[Node3D] = _crowd(rng, [8, 30, 60, 120][round], [0, 6, 20, 40][round])
		var sim: SimCore = SimCore.attach(world)
		assert_not_null(sim, "a core attaches to the world")
		if sim == null:
			return
		sim.sync_now()
		var scan: ContactScan = ContactScan.shared(get_tree())
		assert_eq(scan.source(), &"core", "round %d: the shared scan comes from the core" % round)
		for q: int in 40:
			var own: Node3D = bodies[rng.randi_range(0, bodies.size() - 1)]
			var p := Perception.new()
			p.faction = SIDES[rng.randi_range(0, 3)]
			p.position = own.global_position
			p.velocity = Vector3(rng.randf_range(-150.0, 150.0), 0.0, rng.randf_range(-150.0, 150.0))
			p.self_id = q % 2 * 99
			p.friendly_fire = q % 3 == 0
			var cap := ShipCapability.new()
			cap.a_retro = rng.randf_range(2.0, 20.0)
			cap.a_rcs = Vector2(rng.randf_range(2.0, 10.0), rng.randf_range(2.0, 10.0))
			p.capability = cap
			var own_id: int = own.get_instance_id()
			p.contacts = scan.nearest_for(own_id, p.position, p.faction, [0, 4, 12][q % 3])
			var contact_rows: PackedInt32Array = scan.picked_rows
			p.statics = scan.statics_for(own_id, p.position, p.faction, 4)
			p.static_rows = scan.picked_rows
			p.contact_rows = contact_rows
			p.kernels = scan.pilot_kernels()
			p.relation_row = scan.relation_row(p.faction)
			queries += 1
			if p.kernels == null:
				differences.append("round %d query %d: no kernels on a core scan" % [round, q])
				continue
			on_rows += 1 if p.on_rows() else 0
			# Each listed contact sits at its row of the core.
			for i: int in p.contacts.size():
				if sim.core.row_position(p.contact_rows[i]) != p.contacts[i].position:
					differences.append("round %d query %d: contact %d is not at its row" % [round, q, i])
			for i: int in p.statics.size():
				if sim.core.row_position(p.static_rows[i]) != p.statics[i].position:
					differences.append("round %d query %d: static %d is not at its row" % [round, q, i])
			_ask_both(p, rng, "round %d query %d" % [round, q], differences)
	assert_eq(differences.size(), 0, "the kernels on the core answer as the GDScript does: %s" % differences.slice(0, 4))
	assert_eq(on_rows, queries, "every perception of a core scan is on the rows")


# Asks each facade through the kernels and the GDScript reference on the same perception.
func _ask_both(p: Perception, rng: RandomNumberGenerator, label: String, differences: PackedStringArray) -> void:
	var radius: float = rng.randf_range(5.0, 20.0)
	var v_des: Vector3 = p.velocity + Vector3(rng.randf_range(-80.0, 80.0), rng.randf_range(-30.0, 30.0), rng.randf_range(-80.0, 80.0))
	var exempt_id: int = p.contacts[rng.randi_range(0, p.contacts.size() - 1)].id if not p.contacts.is_empty() \
			and rng.randf() < 0.3 else 0
	var seed_value: int = hash("SHIP %d" % rng.randi())
	var native: Dictionary = AvoidanceMath.filter_seen(p, radius, v_des, exempt_id, seed_value)
	var listed: Array[Contact] = []
	for c: Contact in p.contacts:
		if exempt_id == 0 or c.id != exempt_id:
			listed.append(c)
	listed.append_array(p.statics)
	var reference: Dictionary = AvoidanceMath.filter(p.position, p.velocity, radius, listed, v_des, p.capability, seed_value)
	if var_to_bytes(native["v_des"]) != var_to_bytes(reference["v_des"]) or native["urgent"] != reference["urgent"]:
		differences.append("%s: avoidance %s against %s" % [label, native, reference])
	for shot: int in 4:
		var aim: Vector3 = (p.contacts[rng.randi_range(0, p.contacts.size() - 1)].position - p.position).normalized() \
				if not p.contacts.is_empty() and shot < 3 else Vector3.FORWARD
		var target_id: int = p.contacts[rng.randi_range(0, p.contacts.size() - 1)].id if not p.contacts.is_empty() else 0
		var range_m: float = rng.randf_range(200.0, 3000.0)
		var lane: bool = FireLane.clear_seen(p, aim, range_m, target_id)
		if lane != FireLane.clear(p.position, aim, range_m, p.contacts, target_id, p.friendly_fire):
			differences.append("%s: the lane differs (shot %d)" % [label, shot])
	var leader_id: int = p.contacts[rng.randi_range(0, p.contacts.size() - 1)].id if not p.contacts.is_empty() else 0
	var a := AiContext.new()
	a.leader_id = leader_id
	a.refresh(p)
	var bare := Perception.new()
	bare.position = p.position
	bare.self_id = p.self_id
	bare.contacts = p.contacts
	var b := AiContext.new()
	b.leader_id = leader_id
	b.refresh(bare)
	if a.hostiles != b.hostiles or a.hostile_offsets != b.hostile_offsets or a.hostile_ranges != b.hostile_ranges \
			or a.friendly_ids != b.friendly_ids or a.leader != b.leader:
		differences.append("%s: the context lists differ" % label)


func _ai_ship(display_name: String, faction: StringName, at: Vector3) -> Combatant:
	var c: Combatant = ShipAssembly.build(load(RAIDER_SPEC) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: faction,
		ShipAssembly.OPT_DISPLAY_NAME: display_name,
		ShipAssembly.OPT_FORCE_ASSIST: true,
		ShipAssembly.OPT_AI: true,
	})
	world.spawn(c.ship, world.to_universe(at))
	c.driver.brain = IdleBrain.new()
	return c


func test_the_driver_perceives_on_the_rows_with_the_core_and_without_them_off_it() -> void:
	if _skipped():
		return
	var a: Combatant = _ai_ship("ALPHA 1", Factions.EARTH_ALLIANCE, Vector3.ZERO)
	_ai_ship("RAIDER 1", Factions.RAIDERS, Vector3(0.0, 0.0, -400.0))
	_ai_ship("ALPHA 2", Factions.EARTH_ALLIANCE, Vector3(60.0, 0.0, 0.0))
	ContactScan.register_static(810000, Vector3(0.0, 0.0, 600.0), 120.0, BodyKind.STATIC, Factions.NEUTRAL, world)
	for i: int in 3:
		await get_tree().physics_frame
	var p: Perception = a.driver.perceive()
	assert_not_null(p.kernels, "with the core on, the perception carries the kernels")
	assert_true(p.on_rows(), "and its rows line up with its contacts and statics")
	assert_eq(p.contacts.size(), 2, "it sees the other two ships")
	assert_eq(p.statics.size(), 1, "and the rock")
	assert_eq(p.relation_row.size(), SimCore.for_tree(get_tree()).core.factions().size(), "a relation for every faction of the core")
	Settings.set_value(&"perf_native", false)
	ContactScan.invalidate()
	await get_tree().physics_frame
	var off: Perception = a.driver.perceive()
	assert_null(off.kernels, "with native code off, the GDScript reference answers")
	assert_false(off.on_rows(), "and the perception is not on the rows")
	assert_eq(off.contacts.size(), 2, "it still sees the other two ships")
