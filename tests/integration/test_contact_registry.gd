extends TestSteps
## The core's body rows in play (M4-T09's registry, the core's since M4-T15 and every world's since M4-T42): the AI's
## shared scan comes from the core's sync, never from a GDScript gather of the tree, and holds exactly what a node-by-node
## read of the tree (`TreeRows`) gives. Rocks and mines are kept out of a fighter's nearest contacts; its nearest `ai_nearest_static_k` statics come
## beside them and avoidance steers round them. Real ships from `ShipAssembly`, real drivers and brains, the game's 60 Hz.

const RAIDER_SPEC: String = "res://assets/ships/raider_delta_v.tres"
const STARFURY_SPEC: String = "res://assets/ships/starfury_aurora.tres"
const ROWS_COMPARED: Array[String] = ["_body_ids", "_ids", "_names", "_factions", "_positions", "_velocities", "_forwards",
		"_ups", "_radii", "_is_ship", "_kinds"]
const ROCK_RADIUS_M: float = 150.0
const ROCK_START_M: float = 1500.0
const ROCK_SPEED_MPS: float = 100.0
const LANE_SPACING_M: float = 8000.0
const SETTINGS: Array[StringName] = [&"ai_nearest_k", &"ai_nearest_static_k"]

var world: WorldFrame
var projectiles: Node3D
var _saved: Dictionary = {}


## Before the drivers each tick (priority -20): compares the core's scan with the tree read, and parks a ship on cue.
class Checker extends Node:
	var compared: int = 0
	var differences: PackedStringArray = PackedStringArray()
	var park_at_tick: int = -1
	var parked: Node3D = null
	var parked_seen_after: int = -1
	var _tick: int = 0

	func _init() -> void:
		process_physics_priority = -20

	func _physics_process(_delta: float) -> void:
		_tick += 1
		if parked != null and _tick == park_at_tick + 1:
			var scan: ContactScan = ContactScan.shared(get_tree())
			parked_seen_after = 1 if scan._body_ids.has(parked.get_instance_id()) else 0
		if parked != null and _tick == park_at_tick:
			parked.visible = false
			parked.process_mode = Node.PROCESS_MODE_DISABLED
		if _tick % 7 != 0:
			return
		# The core's sync runs here (-20), before its own at -11: nothing moves between, so the fight is unchanged.
		var native: ContactScan = TreeRows.core_scan(get_tree())
		var script: ContactScan = TreeRows.scan(get_tree())
		compared += 1
		for field: String in ROWS_COMPARED:
			if native.get(field) != script.get(field):
				differences.append("tick %d: %s" % [_tick, field])


## Swept closest distance from a ship to a fixed point, tick by tick (after every script).
class RockMonitor extends Node:
	var ships: Array[Node3D] = []
	var rocks: Array[Vector3] = []
	var min_m: Array[float] = []
	var _prev: Array[Vector3] = []

	func _init() -> void:
		process_physics_priority = 500

	func watch(ship: Node3D, rock: Vector3) -> void:
		ships.append(ship)
		rocks.append(rock)
		min_m.append(INF)
		_prev.append(ship.global_position - rock)

	func _physics_process(_delta: float) -> void:
		for i: int in ships.size():
			var rel: Vector3 = ships[i].global_position - rocks[i]
			var d: Vector3 = rel - _prev[i]
			var len_sq: float = d.length_squared()
			var t: float = 0.0 if len_sq < 1e-12 else clampf(-_prev[i].dot(d) / len_sq, 0.0, 1.0)
			min_m[i] = minf(min_m[i], (_prev[i] + d * t).length())
			_prev[i] = rel


func before_each() -> void:
	for key: StringName in SETTINGS:
		_saved[key] = Settings.get_value(key)
		Settings.reset(key)
	ContactScan.invalidate()
	ContactScan.clear_statics()
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)


func after_each() -> void:
	for key: StringName in SETTINGS:
		Settings.set_value(key, _saved[key])
	ContactScan.clear_statics()
	ContactScan.invalidate()


func _ai_ship(spec_path: String, display_name: String, faction: StringName, at: Vector3, velocity: Vector3) -> Combatant:
	var c: Combatant = ShipAssembly.build(load(spec_path) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: faction,
		ShipAssembly.OPT_DISPLAY_NAME: display_name,
		ShipAssembly.OPT_FORCE_ASSIST: true,
		ShipAssembly.OPT_AI: true,
	})
	var facing: Vector3 = velocity.normalized() if velocity.length_squared() > 0.0 else Vector3.FORWARD
	world.spawn(c.ship, world.to_universe(at), Basis.looking_at(facing, Vector3.UP))
	c.ship.linear_velocity = velocity
	return c


# Eight against eight within 2 km, flown by the game's own pilots, and a rock field of 1 000 statics around them.
func _fight(rng: RandomNumberGenerator) -> Array[Combatant]:
	var ships: Array[Combatant] = []
	for i: int in 16:
		var raider: bool = i % 2 == 0
		var at := Vector3(rng.randf_range(-1000.0, 1000.0), rng.randf_range(-300.0, 300.0), rng.randf_range(-1000.0, 1000.0))
		var c: Combatant = _ai_ship(RAIDER_SPEC if raider else STARFURY_SPEC, ("RAIDER %d" if raider else "ALPHA %d") % i,
				Factions.RAIDERS if raider else Factions.EARTH_ALLIANCE, at, Vector3(0.0, 0.0, -40.0))
		var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": "raider" if raider else "ally_starfury",
				"orders": "engage"}, world.to_universe(at), 100 + i)
		assert_true(made["ok"], made["error"])
		c.driver.brain = made["brain"]
		ships.append(c)
	for s: int in 1000:
		ContactScan.register_static(700000 + s, Vector3(rng.randf_range(-8000.0, 8000.0), rng.randf_range(-2000.0, 2000.0),
				rng.randf_range(-8000.0, 8000.0)), rng.randf_range(20.0, 200.0), BodyKind.MINE if s % 5 == 0 else BodyKind.STATIC)
	return ships


func test_in_a_live_fight_the_scan_is_the_cores_and_equals_the_tree() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var ships: Array[Combatant] = _fight(rng)
	var checker := Checker.new()
	checker.parked = ships[3].ship
	checker.park_at_tick = 40
	add_child_autofree(checker)
	await _ticks(120)
	assert_eq(ContactScan.shared(get_tree()).source(), &"core", "the drivers read the core's rows")
	assert_gt(checker.compared, 10, "the scans were compared")
	assert_eq(checker.differences, PackedStringArray(), "the core's scan equals the tree every time")
	assert_eq(checker.parked_seen_after, 0, "a ship parked as the pool parks it is gone from the next tick's scan")
	var static_contacts: int = 0
	var statics_handed: int = 0
	for c: Combatant in ships:
		if c.ship == checker.parked:
			continue
		var p: Perception = c.driver.perceive()
		for contact: Contact in p.contacts:
			if BodyKind.is_static(contact.kind):
				static_contacts += 1
		statics_handed = maxi(statics_handed, p.statics.size())
		for rock: Contact in p.statics:
			assert_true(BodyKind.is_static(rock.kind), "only rocks and mines among the statics")
	assert_eq(static_contacts, 0, "no rock or mine among any fighter's contacts")
	assert_eq(statics_handed, 4, "a fighter in the field gets its nearest ai_nearest_static_k (4) statics")


func test_a_fighter_flying_at_a_rock_steers_round_it() -> void:
	var cases: Array[Dictionary] = [
		{"spec": RAIDER_SPEC, "native": true}, {"spec": STARFURY_SPEC, "native": true},
	]
	for i: int in cases.size():
		ContactScan.invalidate()
		ContactScan.clear_statics()
		var monitor := RockMonitor.new()
		add_child(monitor)
		var rock := Vector3(float(i) * LANE_SPACING_M, 0.0, 0.0)
		ContactScan.register_static(800000 + i, rock, ROCK_RADIUS_M)
		var ship: Combatant = _ai_ship(cases[i]["spec"], "RUNNER %d" % i, Factions.RAIDERS,
				rock + Vector3(0.0, 0.0, ROCK_START_M), Vector3(0.0, 0.0, -ROCK_SPEED_MPS))
		var ahead := Vector3(0.0, 0.0, -3000.0)
		var made: Dictionary = BrainFactory.from_behaviour({"type": "patrol", "cruise_mps": ROCK_SPEED_MPS,
				"waypoints": [[ahead.x, ahead.y, ahead.z], [2.0 * ahead.x, 2.0 * ahead.y, 2.0 * ahead.z]]},
				world.to_universe(ship.ship.global_position), i)
		assert_true(made["ok"], made["error"])
		ship.driver.brain = made["brain"]
		monitor.watch(ship.ship, rock)
		await _ticks(roundi((ROCK_START_M / ROCK_SPEED_MPS + 3.0) * float(Engine.physics_ticks_per_second)))
		var clearance: float = ROCK_RADIUS_M + ship.damageable.bounding_radius
		var label: String = "%s on the %s path" % [(cases[i]["spec"] as String).get_file().get_basename(),
				"native" if cases[i]["native"] else "GDScript"]
		gut.p("rock, %s: closest %.1f m (rock and hull %.1f m)" % [label, monitor.min_m[0], clearance])
		assert_gt(monitor.min_m[0], clearance, "%s: no ram into the rock" % label)
		monitor.free()
		ship.ship.queue_free()
		await _ticks(1)


# The contact `scan` hands a ship of `faction` at `at` for the body with contact id `id`, or null.
static func _contact_of(scan: ContactScan, at: Vector3, faction: StringName, id: int) -> Contact:
	for c: Contact in scan.contacts_for(-1, at, faction):
		if c.id == id:
			return c
	return null


func test_a_selection_and_a_hull_changed_after_the_build_reach_the_scan() -> void:
	var own: Combatant = _ai_ship(RAIDER_SPEC, "RAIDER 1", Factions.RAIDERS, Vector3.ZERO, Vector3.ZERO)
	var mate: Combatant = _ai_ship(RAIDER_SPEC, "RAIDER 2", Factions.RAIDERS, Vector3(200.0, 0.0, 0.0), Vector3.ZERO)
	var enemy: Combatant = _ai_ship(STARFURY_SPEC, "ALPHA 1", Factions.EARTH_ALLIANCE, Vector3(0.0, 0.0, -900.0),
			Vector3.ZERO)
	var mate_id: int = mate.targetable.get_instance_id()
	assert_true(mate.ship.targeting.select_nearest_hostile(), "the mate has the enemy selected")
	# Built first, changed after (a console `set targeting.selected`, the player, a stand-in, a hit), queried last.
	var native: ContactScan = TreeRows.core_scan(get_tree())
	var script: ContactScan = TreeRows.scan(get_tree())
	mate.ship.targeting.clear_selection()
	mate.damageable.hull.apply(0.25 * mate.damageable.hull.max_hp)
	var a: Contact = _contact_of(native, own.ship.global_position, Factions.RAIDERS, mate_id)
	var b: Contact = _contact_of(script, own.ship.global_position, Factions.RAIDERS, mate_id)
	assert_not_null(a, "the core scan has the mate")
	assert_not_null(b, "the tree read has the mate")
	assert_eq(a.target_id, b.target_id, "the same selection as the tree's")
	assert_eq(a.hull_fraction, b.hull_fraction, "the same hull as the tree's")
	assert_eq(a.target_id, -1, "the selection is read when the contact is handed out")
	assert_almost_eq(a.hull_fraction, 0.75, 1e-6, "and the hull")
	# A driver's own change after the build is noted, so both paths hand out the selection the scan was built with.
	for on: bool in [true, false]:
		mate.ship.targeting.select_nearest_hostile()
		ContactScan.invalidate()
		var shared: ContactScan = ContactScan.shared(get_tree())
		ContactScan.note_selection(mate.ship)
		mate.ship.targeting.clear_selection()
		var c: Contact = _contact_of(shared, own.ship.global_position, Factions.RAIDERS, mate_id)
		assert_eq(c.target_id, enemy.targetable.get_instance_id(), "%s: the noted selection" % shared.path())
