extends GutTest
## AC5 in Jolt (M3-T05, architecture §16 D33): the avoidance filter in `AiPilotDriver`, closed loop through the real
## flight model. Two AI ships set on a head-on course at 150 m/s closing pass without contact in 20 of 20 seeded runs; an
## AI ship aimed at a buoy at 100 m/s misses it. Real ships from `ShipAssembly`, real drivers and brains (patrol through
## the other ship, or coast), the game's own 60 Hz physics step.
##
## Every seeded run of a test flies in the same world at once, each in its own lane 6 km from the next: beyond the 5 km
## sensor range, so no run sees another (each ship's contacts are only its own run's). "Without contact" is measured
## swept, tick to tick, between the body origins, and must stay above the sum of the two bounding radii: the bounding
## spheres never touch, so no hull can. Nor may the loop oscillate: one engagement per encounter, at most one strafe
## reversal.

const RAIDER_SPEC: String = "res://assets/ships/raider_delta_v.tres"
const STARFURY_SPEC: String = "res://assets/ships/starfury_aurora.tres"
const RUNS: int = 20
const LANE_SPACING_M: float = 6000.0
const HEAD_ON_SPEED_MPS: float = 75.0
const HEAD_ON_START_M: float = 1500.0
const BUOY_SPEED_MPS: float = 100.0
const BUOY_START_M: float = 1500.0
## Seconds after the meeting the runs keep going, so a late swerve back into the other ship would be seen.
const AFTER_PASS_S: float = 3.0

var world: WorldFrame
var projectiles: Node3D
var monitor: PassMonitor


## Swept closest distance between two bodies, tick by tick (priority 500: after every script, before Jolt steps).
class PassMonitor extends Node:
	var a: Array[Node3D] = []
	var b: Array[Node3D] = []
	var drivers: Array[AiPilotDriver] = []
	var min_m: Array[float] = []
	var avoided: Array[bool] = []
	## Times the driver's avoidance switched on, and times the commanded strafe reversed (a weave), per pair.
	var engagements: Array[int] = []
	var reversals: Array[int] = []
	var _prev: Array[Vector3] = []
	var _was_avoiding: Array[bool] = []
	var _last_strafe: Array[Vector2] = []

	func _init() -> void:
		process_physics_priority = 500

	func watch(p_a: Node3D, p_b: Node3D, driver: AiPilotDriver) -> void:
		a.append(p_a)
		b.append(p_b)
		drivers.append(driver)
		min_m.append(INF)
		avoided.append(false)
		engagements.append(0)
		reversals.append(0)
		_prev.append(p_a.global_position - p_b.global_position)
		_was_avoiding.append(false)
		_last_strafe.append(Vector2.ZERO)

	func _physics_process(_delta: float) -> void:
		for i: int in a.size():
			var rel: Vector3 = a[i].global_position - b[i].global_position
			min_m[i] = minf(min_m[i], _segment_distance(_prev[i], rel))
			_prev[i] = rel
			var on: bool = drivers[i].avoiding
			avoided[i] = avoided[i] or on
			if on and not _was_avoiding[i]:
				engagements[i] += 1
			_was_avoiding[i] = on
			var strafe: Vector2 = (a[i] as Ship)._flight.strafe
			if strafe.length() > 0.05:
				if _last_strafe[i] != Vector2.ZERO and strafe.dot(_last_strafe[i]) < 0.0:
					reversals[i] += 1
				_last_strafe[i] = strafe

	# Distance from the origin to the segment p -> q.
	static func _segment_distance(p: Vector3, q: Vector3) -> float:
		var d: Vector3 = q - p
		var len_sq: float = d.length_squared()
		var t: float = 0.0 if len_sq < 1e-12 else clampf(-p.dot(d) / len_sq, 0.0, 1.0)
		return (p + d * t).length()


func before_each() -> void:
	ContactScan.invalidate()
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	monitor = PassMonitor.new()
	add_child_autofree(monitor)


func after_each() -> void:
	ContactScan.invalidate()


# The centre of lane `i`: a 5 x 4 grid across the course, 6 km apart.
func _lane(i: int) -> Vector3:
	return Vector3((float(i % 5) - 2.0) * LANE_SPACING_M, (floorf(float(i) / 5.0) - 1.5) * LANE_SPACING_M, 0.0)


func _ai_ship(spec_path: String, display_name: String, faction: StringName, at: Vector3, velocity: Vector3) -> Combatant:
	var c: Combatant = ShipAssembly.build(load(spec_path) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: faction,
		ShipAssembly.OPT_DISPLAY_NAME: display_name,
		ShipAssembly.OPT_FORCE_ASSIST: true,
		ShipAssembly.OPT_AI: true,
	})
	world.spawn(c.ship, world.to_universe(at), Basis.looking_at(velocity.normalized(), Vector3.UP))
	c.ship.linear_velocity = velocity
	return c


# Patrol on through whatever is ahead (waypoints 3 and 6 km along the course), or coast.
func _brain(patrol: bool, c: Combatant, direction: Vector3, cruise_mps: float, seed_value: int) -> PilotBrain:
	if not patrol:
		return IdleBrain.new()
	var ahead: Vector3 = direction * 3000.0
	var made: Dictionary = BrainFactory.from_behaviour({"type": "patrol", "cruise_mps": cruise_mps,
			"waypoints": [[ahead.x, ahead.y, ahead.z], [2.0 * ahead.x, 2.0 * ahead.y, 2.0 * ahead.z]]},
			world.to_universe(c.ship.global_position), seed_value)
	assert_true(made["ok"], made["error"])
	return made["brain"]


func _fly(seconds: float) -> void:
	var ticks: int = roundi(seconds * float(Engine.physics_ticks_per_second))
	for i: int in ticks:
		await get_tree().physics_frame


func test_two_ai_ships_head_on_at_150_mps_closing_pass_without_contact_in_20_of_20_seeded_runs() -> void:
	var specs: Array[String] = [STARFURY_SPEC, RAIDER_SPEC]
	var radii: Array[float] = []
	var labels: Array[String] = []
	for run: int in RUNS:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + run
		# Ship types by run: Starfury vs Starfury, raider vs raider, Starfury vs raider. Patrol on even runs, coast on odd.
		var spec_a: String = specs[0] if run % 3 != 1 else specs[1]
		var spec_b: String = specs[1] if run % 3 != 0 else specs[0]
		var patrol: bool = run % 2 == 0
		# Dead centre on run 0; otherwise up to 4 m off, any direction across the course: a collision course every time.
		var offset: Vector3 = Vector3.ZERO if run == 0 else Vector3.RIGHT.rotated(Vector3.BACK, rng.randf() * TAU) * rng.randf_range(0.0, 4.0)
		var centre: Vector3 = _lane(run)
		var a: Combatant = _ai_ship(spec_a, "A%d" % run, Factions.EARTH_ALLIANCE,
				centre + Vector3(0.0, 0.0, 0.5 * HEAD_ON_START_M), Vector3(0.0, 0.0, -HEAD_ON_SPEED_MPS))
		var b: Combatant = _ai_ship(spec_b, "B%d" % run, Factions.RAIDERS,
				centre + offset + Vector3(0.0, 0.0, -0.5 * HEAD_ON_START_M), Vector3(0.0, 0.0, HEAD_ON_SPEED_MPS))
		a.driver.brain = _brain(patrol, a, Vector3.FORWARD, HEAD_ON_SPEED_MPS, run)
		b.driver.brain = _brain(patrol, b, Vector3.BACK, HEAD_ON_SPEED_MPS, run + 500)
		monitor.watch(a.ship, b.ship, a.driver)
		radii.append(a.damageable.bounding_radius + b.damageable.bounding_radius)
		labels.append("run %d (%s vs %s, %s, offset %.1f m)" % [run, spec_a.get_file().get_basename(),
				spec_b.get_file().get_basename(), "patrol" if patrol else "coast", offset.length()])
	await _fly(HEAD_ON_START_M / (2.0 * HEAD_ON_SPEED_MPS) + AFTER_PASS_S)
	var clean: int = 0
	var report: PackedStringArray = []
	for run: int in RUNS:
		var ok: bool = monitor.min_m[run] > radii[run]
		clean += 1 if ok else 0
		report.append("%s: closest %.1f m, radii %.1f m, avoidance on %d time(s), strafe reversed %d time(s)%s" % [labels[run],
				monitor.min_m[run], radii[run], monitor.engagements[run], monitor.reversals[run], "" if ok else "  CONTACT"])
		assert_true(monitor.avoided[run], "%s: the filter acted" % labels[run])
		_assert_no_weave(run, labels[run])
	gut.p("head-on:\n  " + "\n  ".join(report))
	assert_eq(clean, RUNS, "every run passes without contact")


func test_an_ai_ship_aimed_at_a_buoy_at_100_mps_misses_it() -> void:
	var cases: Array[Dictionary] = [
		{"spec": RAIDER_SPEC, "patrol": false}, {"spec": RAIDER_SPEC, "patrol": true},
		{"spec": STARFURY_SPEC, "patrol": false}, {"spec": STARFURY_SPEC, "patrol": true},
	]
	var radii: Array[float] = []
	for i: int in cases.size():
		var centre: Vector3 = _lane(i)
		var buoy: NavBuoy = NavBuoy.create("NAV %d" % i)
		world.spawn(buoy, world.to_universe(centre))
		var ship: Combatant = _ai_ship(cases[i]["spec"], "RUNNER %d" % i, Factions.RAIDERS,
				centre + Vector3(0.0, 0.0, BUOY_START_M), Vector3(0.0, 0.0, -BUOY_SPEED_MPS))
		ship.driver.brain = _brain(cases[i]["patrol"], ship, Vector3.FORWARD, BUOY_SPEED_MPS, i)
		monitor.watch(ship.ship, buoy, ship.driver)
		radii.append(ship.damageable.bounding_radius + buoy.damageable.bounding_radius)
	await _fly(BUOY_START_M / BUOY_SPEED_MPS + AFTER_PASS_S)
	for i: int in cases.size():
		var label: String = "%s %s" % [(cases[i]["spec"] as String).get_file().get_basename(), "patrol" if cases[i]["patrol"] else "coast"]
		gut.p("buoy, %s: closest %.1f m (radii %.1f m), avoidance on %d time(s), strafe reversed %d time(s)" % [label,
				monitor.min_m[i], radii[i], monitor.engagements[i], monitor.reversals[i]])
		assert_gt(monitor.min_m[i], radii[i], "%s misses the buoy" % label)
		assert_true(monitor.avoided[i], "%s: the filter acted" % label)
		_assert_no_weave(i, label)


# Closed loop through Newtonian steering without oscillating: the dodge engages once per encounter, and the strafe
# reverses at most once (out, then a patrol steering back onto its course after the pass; a coasting ship never).
func _assert_no_weave(i: int, label: String) -> void:
	assert_eq(monitor.engagements[i], 1, "%s: avoidance engaged once" % label)
	assert_lte(monitor.reversals[i], 1, "%s: no weaving" % label)
