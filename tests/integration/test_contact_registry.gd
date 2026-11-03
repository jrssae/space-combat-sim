extends GutTest
## The native body registry in play (M4-T09, architecture §17.8): with the library and `perf_native` on, the AI's shared
## scan comes from one native refresh a tick, never from a GDScript gather of the tree, and holds exactly what that gather
## would. Rocks and mines are kept out of a fighter's nearest contacts; its nearest `ai_nearest_static_k` statics come
## beside them and avoidance steers round them. Real ships from `ShipAssembly`, real drivers and brains, the game's 60 Hz.

const RAIDER_SPEC: String = "res://assets/ships/raider_delta_v.tres"
const STARFURY_SPEC: String = "res://assets/ships/starfury_aurora.tres"
const ROWS_COMPARED: Array[String] = ["_body_ids", "_ids", "_names", "_factions", "_positions", "_velocities", "_forwards",
		"_ups", "_radii", "_is_ship", "_kinds"]
const ROCK_RADIUS_M: float = 150.0
const ROCK_START_M: float = 1500.0
const ROCK_SPEED_MPS: float = 100.0
const LANE_SPACING_M: float = 8000.0
const SETTINGS: Array[StringName] = [&"perf_native", &"ai_nearest_k", &"ai_nearest_static_k"]

var world: WorldFrame
var projectiles: Node3D
var _saved: Dictionary = {}


## Before the drivers each tick (priority -20): compares the registry's scan with the tree gather, and parks a ship on cue.
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
		var native: ContactScan = ContactScan.from_registry(get_tree())
		var script: ContactScan = ContactScan.from_tree(get_tree())
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


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there is no registry to compare")
	return true


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


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


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


func test_in_a_live_fight_the_scan_never_gathers_from_the_tree_and_equals_that_gather() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var ships: Array[Combatant] = _fight(rng)
	var checker := Checker.new()
	checker.parked = ships[3].ship
	checker.park_at_tick = 40
	add_child_autofree(checker)
	var gathers: int = ContactScan.gathers
	await _ticks(120)
	# The checker's own `from_tree` calls are the only gathers.
	assert_eq(ContactScan.gathers - gathers, checker.compared, "no gather from the tree but the checker's")
	assert_gt(checker.compared, 10, "the scans were compared")
	assert_eq(checker.differences, PackedStringArray(), "the registry's scan equals the tree gather every time")
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
	Settings.set_value(&"perf_native", false)
	gathers = ContactScan.gathers
	var compared: int = checker.compared
	await _ticks(10)
	assert_gt(ContactScan.gathers - gathers - (checker.compared - compared), 0, "perf_native off: the GDScript gather")


func test_a_fighter_flying_at_a_rock_steers_round_it_on_both_paths() -> void:
	if _skipped():
		return
	var cases: Array[Dictionary] = [
		{"spec": RAIDER_SPEC, "native": true}, {"spec": STARFURY_SPEC, "native": true},
		{"spec": RAIDER_SPEC, "native": false}, {"spec": STARFURY_SPEC, "native": false},
	]
	for i: int in cases.size():
		Settings.set_value(&"perf_native", cases[i]["native"])
		ContactScan.invalidate()
		ContactScan.clear_statics()
		var monitor := RockMonitor.new()
		add_child_autofree(monitor)
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
		ship.ship.queue_free()
		await _ticks(1)
