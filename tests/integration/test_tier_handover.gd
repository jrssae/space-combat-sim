extends GutTest
## The low-attention tier's handover (M4-T21, architecture §17.14): a fighter beyond `tier_radius_m` of the player leaves
## Jolt and the processing and flies as a core row; coming back within the radius it is promoted onto its body with its
## position, velocity, attitude, command and assist state carried over exactly, and the reverse demotes it, so nothing pops.
## A capital goes with its turrets and emitters and fires again when it is back; Jolt holds only the near bodies; the
## player flying into a far fight finds it promoted at 10 km, long before 5 km; a tier ship does not think (the tier
## replaces the far rate for it) and thinks again when promoted; a hulk comes back as a hulk; a release while tiered takes
## the row away; the radius at 0 or the core off promotes everything. Every test runs on both of T24's step schedules
## (Q54), each pass reading the live schedule back. Real pooled ships, real physics frames. Skips, saying why, when the
## library is not built.

const POOL: int = 14
const DT: float = 1.0 / 60.0
const SETTINGS: Array[StringName] = [&"perf_native", &"perf_native_core", &"perf_native_brains", &"perf_native_flight",
		&"perf_native_commands", &"perf_native_driver_step", &"perf_native_weapons", &"perf_native_bolt_rows", &"sim_step",
		&"tier_radius_m", &"tier_hz", &"ai_think_rate", &"perf_threads"]
const SCHEDULES: Array[StringName] = [&"threaded", &"inline"]
const RADIUS_M: float = 10000.0

var world: WorldFrame
var projectiles: Node3D
var pool: ShipPool
var player: Combatant
var standins: StandinDirector
var sim: SimCore
var tier: TierDirector
var _saved: Dictionary = {}


## Holds one command, so the ship flies the same way on its body and in the tier.
class ThrustBrain extends PilotBrain:
	var thinks: int = 0

	func think(_p: Perception, _dt: float) -> PilotCommand:
		thinks += 1
		var cmd := PilotCommand.new()
		cmd.flight.main_left = 0.4
		cmd.flight.main_right = 0.4
		cmd.flight.rot = Vector3(0.0, 0.2, 0.0)
		return cmd


func before_each() -> void:
	for key: StringName in SETTINGS:
		_saved[key] = Settings.get_value(key)
	for key: StringName in [&"perf_native", &"perf_native_core", &"perf_native_brains", &"perf_native_flight",
			&"perf_native_commands", &"perf_native_driver_step", &"perf_native_weapons", &"perf_native_bolt_rows", &"ai_think_rate"]:
		Settings.set_value(key, true)
	Settings.set_value(&"tier_radius_m", RADIUS_M)
	Settings.set_value(&"tier_hz", 20.0)
	Factions.reset()
	ContactScan.invalidate()
	_build()


func after_each() -> void:
	for key: StringName in SETTINGS:
		Settings.set_value(key, _saved[key])
	Factions.reset()
	ContactScan.invalidate()


# A world with the pool, the player at the origin, the stand-ins, the core and the director.
func _build() -> void:
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	pool = ShipPool.new()
	pool.name = "Ships"
	world.add_child(pool)
	pool.world = world
	pool.projectiles = projectiles
	player = ShipAssembly.build(load("res://assets/ships/starfury_aurora.tres") as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: "PLAYER",
		ShipAssembly.OPT_CONSOLE_OWNER: true,
	})
	world.spawn(player.ship, world.to_universe(Vector3.ZERO))
	pool.player = player.ship
	pool.prepare(ShipPool.DEFAULT_TYPE, POOL)
	standins = StandinDirector.new()
	standins.name = "Standins"
	standins.world = world
	standins.projectiles = projectiles
	standins.ships = pool
	standins.player = player.ship
	world.add_child(standins)
	FlightBatch.attach(world)
	sim = SimCore.attach(world)
	tier = TierDirector.attach(world, pool, standins)


# The world torn down and built again (a seeded run from the same start).
func _rebuild() -> void:
	world.get_parent().remove_child(world)
	world.free()
	await get_tree().physics_frame
	ContactScan.invalidate()
	_build()
	await get_tree().physics_frame


# Far ships no director can demote (built outside the pool), 20 km out, first in the tree and so in the core's rows.
func _strays(n: int) -> Array[Combatant]:
	var holder := Node3D.new()
	holder.name = "Strays"
	world.add_child(holder)
	world.move_child(holder, 0)
	var out: Array[Combatant] = []
	for i: int in n:
		var stray: Combatant = ShipAssembly.build(load("res://assets/ships/starfury_aurora.tres") as ShipSpec, world, projectiles, {
			ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
			ShipAssembly.OPT_DISPLAY_NAME: "STRAY %d" % i,
		})
		world.spawn(stray.ship, world.to_universe(Vector3(float(i) * 100.0, 0.0, -20000.0)), Basis.IDENTITY, holder)
		out.append(stray)
	return out


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there is no tier to hand over to")
	return true


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _raider(display_name: String, at: Vector3, brain: PilotBrain, velocity: Vector3 = Vector3.ZERO) -> Combatant:
	var c: Combatant = pool.acquire(display_name, world.to_universe(at), Basis.IDENTITY, velocity, brain)
	assert_not_null(c, "a raider from the pool")
	return c


func _ai_brain(at: Vector3, seed_value: int) -> PilotBrain:
	return BrainFactory.from_behaviour({"type": "ai", "profile": "raider"}, world.to_universe(at), seed_value)["brain"] as PilotBrain


static func _in_jolt(body: RigidBody3D) -> bool:
	return PhysicsServer3D.body_get_space(body.get_rid()).is_valid()


static func _parked(ship: Ship) -> bool:
	return ship.is_tier_parked() and not ship.visible and not ship.can_process()


# Switches T24's step schedule and proves the live step took it (the batch's cached mode and the core's readout).
func _use_schedule(schedule: StringName) -> void:
	Settings.set_value(&"sim_step", schedule)
	assert_eq(BrainBatch.step_mode(), BrainBatch.step_mode_of(schedule), "the batch steps on %s" % schedule)
	var read: Dictionary = DebugConsole.registry.read("core.step_mode")
	assert_eq(str(read.get("value", "")), String(schedule), "core.step_mode reads %s back" % schedule)


# Proves the native thinks of the last ticks ran where the schedule says: off the main thread only when threaded.
func _assert_step_ran(schedule: StringName) -> void:
	var host: Object = NativeBrains.host(get_tree())
	assert_not_null(host, "%s: a brain host ran" % schedule)
	if host != null:
		assert_eq(bool(host.step_off_main()), schedule == &"threaded", "%s: the last job ran %s the main thread" % [
				schedule, "off" if schedule == &"threaded" else "on"])


# Ticks `n` times, recording each tick the ship's row in the core (its scan position) and its velocity then.
func _scan_ticks(n: int, c: Combatant, scan: Array) -> void:
	var id: int = c.ship.get_instance_id()
	for i: int in n:
		await get_tree().physics_frame
		var row: int = int(sim.core.row_of_id(id))
		var vel: Vector3 = (sim.core.tier_state(id)["velocity"] as Vector3) if c.ship.is_tier_parked() else c.ship.linear_velocity
		scan.append([sim.core.row_position(row) if row >= 0 else Vector3.INF, vel])


# The scan never jumps at a handover: each tick's step is the ship's motion over a tick, give or take one tick's motion
# (a tier row is integrated one tick ahead of the body rows), and never backwards.
func _assert_scan_continuous(scan: Array, why: String) -> void:
	var worst: float = 0.0
	var gaps: int = 0
	var backwards: int = 0
	for i: int in range(1, scan.size()):
		var p0: Vector3 = scan[i - 1][0]
		var p1: Vector3 = scan[i][0]
		if not p0.is_finite() or not p1.is_finite():
			gaps += 1
			continue
		var tick_m: float = maxf((scan[i - 1][1] as Vector3).length(), (scan[i][1] as Vector3).length()) * DT
		var step: Vector3 = p1 - p0
		worst = maxf(worst, absf(step.length() - tick_m) / maxf(tick_m, 1e-6))
		if step.dot(scan[i][1] as Vector3) < -0.001:
			backwards += 1
	assert_eq(gaps, 0, "%s: the ship had a row in the scan every tick" % why)
	assert_lte(worst, 1.02, "%s: no scan step strayed from a tick's motion by more than one tick's motion (worst %.3f ticks)" % [why, worst])
	assert_eq(backwards, 0, "%s: and the scan never stepped backwards" % why)
	gut.p("%s: %d scan steps, worst %.3f ticks off a tick's motion" % [why, scan.size() - 1, worst])


# --- the handover ----------------------------------------------------------------------------------------------------------


func test_a_fighter_demoted_and_promoted_a_hundred_times_never_pops_on_either_schedule() -> void:
	if _skipped():
		return
	tier.set_physics_process(false)  # the handovers by hand, at a fixed beat
	for schedule: StringName in SCHEDULES:
		_use_schedule(schedule)
		var brain := ThrustBrain.new()
		var c: Combatant = _raider("R %s" % schedule, Vector3(0.0, 0.0, -12000.0), brain, Vector3(0.0, 0.0, -80.0))
		var id: int = c.ship.get_instance_id()
		var hull_before: float = c.damageable.hull.hp
		await _ticks(6)
		var worst_pos: float = 0.0
		var worst_vel: float = 0.0
		var scan: Array = []
		for cycle: int in 50:
			await _scan_ticks(12, c, scan)
			var pos: Vector3 = c.ship.global_position
			var vel: Vector3 = c.ship.linear_velocity
			var basis: Basis = c.ship.global_basis
			var spin: Vector3 = c.ship.angular_velocity
			var command: Dictionary = c.ship.flight_command().to_dict()
			var pod_yaw: float = c.ship.assist_state()
			assert_true(tier.demote_body(id), "cycle %d: demoted" % cycle)
			var row: Dictionary = sim.core.tier_state(id)
			assert_false(row.is_empty(), "cycle %d: a row" % cycle)
			worst_pos = maxf(worst_pos, (row["position"] as Vector3).distance_to(pos))
			worst_vel = maxf(worst_vel, (row["velocity"] as Vector3).distance_to(vel))
			assert_eq(row["basis"], basis, "cycle %d: the attitude goes over exactly" % cycle)
			assert_eq(row["angular"], spin, "cycle %d: and the spin" % cycle)
			assert_eq(float(row["pod_yaw"]), pod_yaw, "cycle %d: and the assist's state" % cycle)
			assert_eq(row["command"], TierDirector.held_command(sim, c), "cycle %d: the command the ship held" % cycle)
			assert_true(_parked(c.ship), "cycle %d: the body is parked" % cycle)
			assert_false(_in_jolt(c.ship), "cycle %d: and out of Jolt" % cycle)
			await _scan_ticks(12, c, scan)
			row = sim.core.tier_state(id)
			var row_vel: Vector3 = row["velocity"]
			assert_ne(row_vel, vel, "cycle %d: the tier flew the held command (%s from %s)" % [cycle, row_vel, vel])
			assert_true(tier.promote_body(id), "cycle %d: promoted" % cycle)
			worst_pos = maxf(worst_pos, c.ship.global_position.distance_to(row["position"]))
			worst_vel = maxf(worst_vel, c.ship.linear_velocity.distance_to(row_vel))
			assert_eq(c.ship.global_basis, row["basis"], "cycle %d: the attitude comes back exactly" % cycle)
			assert_eq(c.ship.angular_velocity, row["angular"], "cycle %d: and the spin" % cycle)
			assert_eq(c.ship.assist_state(), float(row["pod_yaw"]), "cycle %d: and the assist's state" % cycle)
			assert_eq(c.ship.flight_command().to_dict(), command, "cycle %d: the command is the one it left with" % cycle)
			assert_true(c.ship.visible and c.ship.can_process() and not c.ship.is_tier_parked(), "cycle %d: back in play" % cycle)
			assert_true(_in_jolt(c.ship), "cycle %d: and in Jolt" % cycle)
			assert_true(sim.core.tier_state(id).is_empty(), "cycle %d: no row left" % cycle)
		await _scan_ticks(3, c, scan)
		_assert_scan_continuous(scan, "%s, 100 handovers" % schedule)
		assert_lt(worst_pos, 0.01, "%s: the position never moved by a centimetre at a handover (%.5f m)" % [schedule, worst_pos])
		assert_lt(worst_vel, 0.01, "%s: nor the velocity by a centimetre a second (%.5f m/s)" % [schedule, worst_vel])
		assert_same(c.driver.brain, brain, "the pilot stayed")
		assert_eq(c.display_name, "R %s" % schedule, "and the name")
		assert_eq(c.damageable.hull.hp, hull_before, "and the hull")
		assert_lt(c.ship.global_position.z, -12000.0 - 80.0 * 20.0 * 0.9, "over 20 s it flew on (%.0f m)" % c.ship.global_position.z)
		gut.p("%s: 100 handovers, worst handover error %.6f m, %.6f m/s" % [schedule, worst_pos, worst_vel])
		pool.release(c)


func test_jolt_holds_only_the_near_bodies_and_the_counts_say_so() -> void:
	if _skipped():
		return
	for schedule: StringName in SCHEDULES:
		_use_schedule(schedule)
		var near: Array[Combatant] = []
		var far: Array[Combatant] = []
		for i: int in 6:
			near.append(_raider("N%d" % i, Vector3(float(i) * 100.0, 0.0, -3000.0), IdleBrain.new()))
			far.append(_raider("F%d" % i, Vector3(float(i) * 100.0, 0.0, -15000.0), IdleBrain.new()))
		var near_cap: CapitalStandin = standins.add_capital(&"cruiser", Factions.EARTH_ALLIANCE, "NEAR CAP",
				world.to_universe(Vector3(2000.0, 0.0, -2000.0)), Basis.IDENTITY, Vector3.ZERO)
		var far_cap: CapitalStandin = standins.add_capital(&"cruiser", Factions.EARTH_ALLIANCE, "FAR CAP",
				world.to_universe(Vector3(2000.0, 0.0, -20000.0)), Basis.IDENTITY, Vector3.ZERO)
		standins.active = true
		await _ticks(4)
		assert_eq(int(sim.core.tier_count()), 7, "%s: six far fighters and the far capital are tier rows" % schedule)
		assert_eq(tier.tier_fighters(), 6)
		assert_eq(tier.tier_capitals(), 1)
		for c: Combatant in near:
			assert_true(_in_jolt(c.ship) and c.ship.visible, "%s is near: in Jolt" % c.display_name)
		for c: Combatant in far:
			assert_true(_parked(c.ship) and not _in_jolt(c.ship), "%s is far: a row, not a body" % c.display_name)
		assert_true(_in_jolt(near_cap) and not near_cap.is_tier_parked(), "the near capital is in Jolt")
		assert_true(far_cap.is_tier_parked() and not _in_jolt(far_cap), "the far capital is a row")
		assert_true(_in_jolt(player.ship), "the player is never tiered")
		var in_jolt: int = 0
		for c: Combatant in pool.alive():
			in_jolt += 1 if _in_jolt(c.ship) else 0
		assert_eq(in_jolt, 6, "the bodies in Jolt are the near fighters")
		assert_eq(standins.counts[StandinDirector.Count.FIGHTERS_NEAR], 6)
		assert_eq(standins.counts[StandinDirector.Count.FIGHTERS_FAR], 6)
		assert_eq(standins.counts[StandinDirector.Count.TIER_FIGHTERS], 6)
		assert_eq(standins.counts[StandinDirector.Count.TIER_CAPITALS], 1)
		var rows: int = int(sim.core.row_count())
		assert_eq(rows, 1 + 6 + 1 + 7, "the player, six near fighters, the near capital, and seven tier rows")
		gut.p("%s: %d active 3D objects by the engine's monitor" % [schedule, int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))])
		standins.clear()
		for c: Combatant in pool.alive():
			pool.release(c)
		await _ticks(2)
		assert_eq(int(sim.core.tier_count()), 0, "%s: a cleared battle leaves no row behind" % schedule)


func test_the_player_flying_into_a_far_fight_sees_it_promoted_at_ten_km_long_before_five() -> void:
	if _skipped():
		return
	for schedule: StringName in SCHEDULES:
		if schedule != SCHEDULES[0]:
			await _rebuild()
		_use_schedule(schedule)
		var fight: Array[Combatant] = []
		for i: int in 8:
			fight.append(_raider("FIGHT %d" % i, Vector3(float(i % 4) * 150.0 - 225.0, float(i / 4) * 150.0, -14000.0), IdleBrain.new()))
		await _ticks(3)
		assert_eq(int(sim.core.tier_count()), 8, "%s: the fight starts in the tier, 14 km out" % schedule)
		player.ship.linear_velocity = Vector3(0.0, 0.0, -1000.0)
		var promoted_at: float = -1.0
		for t: int in 12 * 60:
			await _ticks(1)
			var distance: float = player.ship.global_position.distance_to(Vector3(0.0, 0.0, -14000.0))
			if promoted_at < 0.0 and int(sim.core.tier_count()) == 0:
				promoted_at = distance
			if distance < 5000.0:
				break
		assert_gte(promoted_at, 5000.0, "%s: the fight was promoted before the player was within 5 km (at %.0f m)" % [schedule, promoted_at])
		assert_between(promoted_at, RADIUS_M - 150.0, RADIUS_M + 50.0, "%s: and right at the radius (%.0f m)" % [schedule, promoted_at])
		assert_eq(int(sim.core.tier_count()), 0, "%s: every ship of the fight is on its body within 5 km" % schedule)
		for c: Combatant in fight:
			assert_true(_in_jolt(c.ship) and c.ship.visible and not c.ship.is_tier_parked(), "%s flies in Jolt" % c.display_name)
			assert_lt(c.ship.global_position.distance_to(Vector3(c.ship.global_position.x, c.ship.global_position.y, -14000.0)), 50.0,
					"%s came back where it was (an idle ship at rest; %s)" % [c.display_name, c.ship.global_position])


func test_a_tier_ship_does_not_think_and_thinks_again_when_promoted() -> void:
	if _skipped():
		return
	for schedule: StringName in SCHEDULES:
		_use_schedule(schedule)
		Settings.set_value(&"tier_radius_m", RADIUS_M)
		var at := Vector3(0.0, 0.0, -15000.0)
		var c: Combatant = _raider("THINKER", at, _ai_brain(at, 7))
		var near_c: Combatant = _raider("NEAR THINKER", Vector3(0.0, 0.0, -3000.0), _ai_brain(Vector3(0.0, 0.0, -3000.0), 8))
		tier.set_physics_process(false)  # both think on their bodies first
		await _ticks(8)
		var host: Object = NativeBrains.host(get_tree())
		var pilot := c.driver.brain as AiPilot
		var near_pilot := near_c.driver.brain as AiPilot
		var slot: int = pilot.native_slot_index()
		var near_slot: int = near_pilot.native_slot_index()
		assert_gte(slot, 0, "%s: the far pilot has a native slot" % schedule)
		assert_gt(int(host.slot_think_count(slot)), 0, "%s: and thought on its body" % schedule)
		_assert_step_ran(schedule)
		tier.set_physics_process(true)
		await _ticks(4)
		assert_true(_parked(c.ship), "%s: the far ship is a tier row" % schedule)
		var thinks_at_demotion: int = int(host.slot_think_count(slot))
		var near_thinks: int = int(host.slot_think_count(near_slot))
		var command_at_demotion: PackedFloat64Array = sim.core.row_command(c.ship.get_instance_id())
		await _ticks(60)
		assert_eq(int(host.slot_think_count(slot)), thinks_at_demotion, "%s: a tier ship does not think in a second" % schedule)
		assert_gt(int(host.slot_think_count(near_slot)), near_thinks, "%s: the near one keeps thinking" % schedule)
		assert_eq(sim.core.row_command(c.ship.get_instance_id()), command_at_demotion, "%s: its row command is held" % schedule)
		Settings.set_value(&"tier_radius_m", 0.0)  # the tier off: promoted
		await _ticks(12)
		assert_true(c.ship.visible and _in_jolt(c.ship), "%s: promoted when the tier is off" % schedule)
		assert_gt(int(host.slot_think_count(slot)), thinks_at_demotion, "%s: and it thinks again" % schedule)
		for each: Combatant in pool.alive():
			pool.release(each)
		await _ticks(2)


func test_a_capital_leaves_with_its_turrets_and_fires_again_when_it_is_back() -> void:
	if _skipped():
		return
	for schedule: StringName in SCHEDULES:
		if schedule != SCHEDULES[0]:
			await _rebuild()
		_use_schedule(schedule)
		Settings.set_value(&"tier_radius_m", 30000.0)  # everything near for now
		var cap: CapitalStandin = standins.add_capital(&"cruiser", Factions.EARTH_ALLIANCE, "CRUISER",
				world.to_universe(Vector3(0.0, 0.0, -15000.0)), Basis.IDENTITY, Vector3(0.0, 0.0, -30.0))
		cap.damageable.invulnerable = true
		var target: Combatant = _raider("TARGET", Vector3(0.0, 0.0, -17000.0), IdleBrain.new())
		target.damageable.invulnerable = true
		standins.active = true
		var guns: int = cap.guns().size()
		var gun_offsets: Array[Vector3] = []
		for gun: TurretStandin in cap.guns():
			gun_offsets.append(cap.to_local(gun.global_position))
		await _ticks(90)
		var shots_near: int = _shots(cap)
		assert_gt(shots_near, 0, "%s: the cruiser's guns fire at the hostile 2 km off" % schedule)
		Settings.set_value(&"tier_radius_m", RADIUS_M)
		await _ticks(4)
		assert_true(cap.is_tier_parked() and not _in_jolt(cap), "%s: 15 km out, the capital is a row" % schedule)
		assert_true(_parked(target.ship), "%s: and so is its target" % schedule)
		var at_demotion: int = _shots(cap)
		await _ticks(90)
		assert_eq(_shots(cap), at_demotion, "%s: a tier capital's turrets fire nothing (T22 gives them their aggregated fire)" % schedule)
		assert_eq(cap.guns().size(), guns, "%s: the turrets are still its children" % schedule)
		Settings.set_value(&"tier_radius_m", 30000.0)
		await _ticks(4)
		assert_true(_in_jolt(cap) and cap.visible, "%s: promoted, back in Jolt" % schedule)
		for i: int in guns:
			assert_lt(cap.to_local(cap.guns()[i].global_position).distance_to(gun_offsets[i]), 0.01, "%s: gun %d rides where it was" % [schedule, i])
		var cruise: float = cap.linear_velocity.distance_to(Vector3(0.0, 0.0, -30.0))
		assert_lt(cruise, 1.0, "%s: it kept its cruise (%s)" % [schedule, cap.linear_velocity])
		await _ticks(90)
		assert_gt(_shots(cap), at_demotion, "%s: and its guns fire again" % schedule)
		standins.clear()


func test_a_hulk_row_comes_back_as_a_hulk_and_goes_back_as_one() -> void:
	if _skipped():
		return
	for schedule: StringName in SCHEDULES:
		if schedule != SCHEDULES[0]:
			await _rebuild()
		_use_schedule(schedule)
		Settings.set_value(&"tier_radius_m", RADIUS_M)
		var at := Vector3(0.0, 0.0, -15000.0)
		var c: Combatant = _raider("HULK", at, _ai_brain(at, 9), Vector3(5.0, 0.0, -60.0))
		var near_at := Vector3(0.0, 0.0, -3000.0)
		_raider("NEAR", near_at, _ai_brain(near_at, 10))  # a near thinker, so the step runs on this schedule
		await _ticks(4)
		_assert_step_ran(schedule)
		var id: int = c.ship.get_instance_id()
		assert_true(sim.core.tier_has(id), "%s: the far ship is a row" % schedule)
		assert_true(sim.core.tier_set_hulk(id, true), "%s: flagged a hulk" % schedule)
		var drift: Vector3 = sim.core.tier_state(id)["velocity"]
		await _ticks(60)
		assert_eq(sim.core.tier_state(id)["velocity"], drift, "%s: a hulk row drifts on, whatever its pilot said" % schedule)
		assert_true(sim.core.tier_has(id), "%s: and is still there after a second idle" % schedule)
		Settings.set_value(&"tier_radius_m", 0.0)
		await _ticks(3)
		assert_true(c.ship.visible and _in_jolt(c.ship), "%s: promoted" % schedule)
		assert_true(c.ship.hulk, "%s: as a hulk" % schedule)
		assert_null(c.driver.brain, "%s: with no pilot" % schedule)
		assert_lt(c.ship.linear_velocity.distance_to(drift), 0.01, "%s: at its drift (%s)" % [schedule, c.ship.linear_velocity])
		await _ticks(60)
		assert_lt(c.ship.linear_velocity.distance_to(drift), 0.01, "%s: it coasts under Jolt, no force in a second (%s)" % [schedule, c.ship.linear_velocity])
		assert_false(c.ship.get_combat_command().fire, "%s: its trigger is released" % schedule)
		# The hulk's body goes back into a row as a hulk, and comes back as one again.
		Settings.set_value(&"tier_radius_m", RADIUS_M)
		await _ticks(3)
		assert_true(_parked(c.ship) and sim.core.tier_has(id), "%s: demoted again, a row" % schedule)
		assert_true(bool(sim.core.tier_state(id)["hulk"]), "%s: still a hulk in the tier" % schedule)
		assert_lt((sim.core.tier_state(id)["velocity"] as Vector3).distance_to(drift), 0.01, "%s: on the same drift" % schedule)
		await _ticks(30)
		assert_lt((sim.core.tier_state(id)["velocity"] as Vector3).distance_to(drift), 0.01, "%s: with no force in the tier" % schedule)
		Settings.set_value(&"tier_radius_m", 0.0)
		await _ticks(3)
		assert_true(c.ship.visible and _in_jolt(c.ship) and c.ship.hulk, "%s: and back on its body a hulk" % schedule)
		assert_null(c.driver.brain, "%s: still with no pilot" % schedule)


func test_a_release_while_tiered_takes_the_row_away() -> void:
	if _skipped():
		return
	for schedule: StringName in SCHEDULES:
		if schedule != SCHEDULES[0]:
			await _rebuild()
		_use_schedule(schedule)
		var c: Combatant = _raider("GONE", Vector3(0.0, 0.0, -15000.0), IdleBrain.new())
		await _ticks(4)
		var id: int = c.ship.get_instance_id()
		assert_true(sim.core.tier_has(id), "%s: a row" % schedule)
		pool.release(c)
		assert_false(sim.core.tier_has(id), "%s: released, no row" % schedule)
		assert_eq(tier.tier_fighters(), 0)
		assert_false(c.ship.is_tier_parked(), "%s: parked by the pool, not the tier" % schedule)
		var again: Combatant = _raider("AGAIN", Vector3(0.0, 0.0, -2000.0), IdleBrain.new())
		await _ticks(3)
		assert_true(again.ship.visible and _in_jolt(again.ship) and not again.ship.is_tier_parked(), "%s: the pool's ship flies again, near" % schedule)
		assert_eq(int(sim.core.tier_count()), 0)


func test_the_radius_at_zero_or_the_core_off_promotes_every_row() -> void:
	if _skipped():
		return
	for schedule: StringName in SCHEDULES:
		if schedule != SCHEDULES[0]:
			await _rebuild()
		_use_schedule(schedule)
		Settings.set_value(&"tier_radius_m", RADIUS_M)
		var far: Array[Combatant] = []
		for i: int in 5:
			far.append(_raider("F%d" % i, Vector3(float(i) * 100.0, 0.0, -15000.0), IdleBrain.new(), Vector3(0.0, 0.0, -50.0)))
		await _ticks(4)
		assert_eq(int(sim.core.tier_count()), 5, "%s: five rows" % schedule)
		Settings.set_value(&"tier_radius_m", 0.0)
		await _ticks(2)
		assert_eq(int(sim.core.tier_count()), 0, "%s: the radius at 0, the tier is off, every row promoted" % schedule)
		for c: Combatant in far:
			assert_true(c.ship.visible and _in_jolt(c.ship), "%s is back" % c.display_name)
			assert_lt(c.ship.global_position.z, -15000.0 - 50.0 * 4 * DT * 0.5, "%s came back where the row had flown to (%s)" % [c.display_name, c.ship.global_position])
		Settings.set_value(&"tier_radius_m", RADIUS_M)
		await _ticks(3)
		assert_eq(int(sim.core.tier_count()), 5, "%s: and demoted again when the radius is back" % schedule)
		Settings.set_value(&"perf_native_core", false)
		await _ticks(2)
		assert_eq(tier.tier_fighters(), 0, "%s: the core off, every row promoted" % schedule)
		for c: Combatant in far:
			assert_true(c.ship.visible and _in_jolt(c.ship), "%s is back on its body" % c.display_name)
		Settings.set_value(&"perf_native_core", true)


func test_with_the_core_gone_a_tiered_ship_comes_back_where_it_was_parked_in_the_current_frame() -> void:
	if _skipped():
		return
	for schedule: StringName in SCHEDULES:
		if schedule != SCHEDULES[0]:
			await _rebuild()
		_use_schedule(schedule)
		var c: Combatant = _raider("ORPHAN", Vector3(300.0, 0.0, -15000.0), IdleBrain.new())
		await _ticks(4)
		assert_true(_parked(c.ship), "%s: a tier row" % schedule)
		var parked_at: UniversePos = world.to_universe(c.ship.global_position)
		world.rebase(Vector3(0.0, 0.0, -4000.0))  # the parked body is not shifted: its row is
		await _ticks(1)
		sim.get_parent().remove_child(sim)
		sim.free()  # the rows are lost with the core
		await _ticks(2)
		assert_false(c.ship.is_tier_parked(), "%s: promoted when the core went" % schedule)
		var error: float = world.to_universe(c.ship.global_position).offset_to(parked_at).length()
		assert_lt(error, 0.01, "%s: back where it was parked, in the frame of now (off by %.1f m)" % [schedule, error])
		await _rebuild()  # a core again for the next pass and the teardown


func test_a_gdscript_pilot_beside_a_tier_row_perceives_only_the_bodies_its_scan_holds() -> void:
	if _skipped():
		return
	tier.set_physics_process(false)  # one ship into the tier by hand; its neighbours stay on their bodies
	for schedule: StringName in SCHEDULES:
		if schedule != SCHEDULES[0]:
			await _rebuild()
			tier.set_physics_process(false)
		_use_schedule(schedule)
		var far: Array[Combatant] = []
		for i: int in 4:
			far.append(_raider("FAR %d" % i, Vector3(float(i) * 100.0, 0.0, -15000.0), ThrustBrain.new()))
		await _ticks(3)
		for i: int in 2:
			assert_true(tier.demote_body(far[i].ship.get_instance_id()), "%s: FAR %d into the tier" % [schedule, i])
		var thinks: int = (far[2].driver.brain as ThrustBrain).thinks
		await _ticks(30)  # the others' GDScript pilots perceive beside the rows every tick
		assert_gt((far[2].driver.brain as ThrustBrain).thinks, thinks, "%s: the ships on their bodies kept thinking" % schedule)
		var scan: ContactScan = ContactScan.shared(get_tree())
		var names: PackedStringArray = []
		for contact: Contact in scan.contacts_for(far[2].ship.get_instance_id(), far[2].ship.global_position, far[2].faction):
			names.append(contact.name)
		assert_false(names.has("FAR 0") or names.has("FAR 1"), "%s: no tier row among a GDScript scan's contacts (%s)" % [schedule, names])
		assert_true(names.has("FAR 3"), "%s: the neighbour on its body is (%s)" % [schedule, names])


func test_bodies_the_director_cannot_demote_do_not_use_up_its_handovers() -> void:
	if _skipped():
		return
	for schedule: StringName in SCHEDULES:
		if schedule != SCHEDULES[0]:
			await _rebuild()
		_use_schedule(schedule)
		tier.handovers_per_tick = 1
		var far: Array[Combatant] = []
		for i: int in 3:
			far.append(_raider("F%d" % i, Vector3(float(i) * 100.0, 0.0, -15000.0), IdleBrain.new()))
		var strays: Array[Combatant] = _strays(4)
		await _ticks(2)
		var listed: PackedInt64Array = sim.core.tier_far_bodies(Vector3.ZERO, player.ship.get_instance_id(), RADIUS_M * 1.1, 100)
		var first: int = listed[0] if not listed.is_empty() else 0
		assert_true(strays.any(func(c: Combatant) -> bool: return c.ship.get_instance_id() == first), "%s: a stray leads the far rows" % schedule)
		await _ticks(6)
		for c: Combatant in far:
			assert_true(_parked(c.ship), "%s: %s was demoted past the strays" % [schedule, c.display_name])
		for stray: Combatant in strays:
			assert_true(_in_jolt(stray.ship), "%s: %s stays in Jolt (not the director's to demote)" % [schedule, stray.display_name])
		assert_eq(tier.demotions, 3, "%s: one demotion a tick, three in all" % schedule)


func test_one_thread_and_six_give_the_same_rows_with_tier_rows_among_the_contacts() -> void:
	if _skipped():
		return
	for schedule: StringName in SCHEDULES:
		var digests: Array[PackedInt64Array] = []
		for threads: int in [1, 6]:
			await _rebuild()
			Settings.set_value(&"perf_threads", threads)
			_use_schedule(schedule)
			SimClock.reset()
			var fliers: Array[Combatant] = []
			for i: int in 6:
				var at := Vector3(float(i) * 200.0 - 500.0, 0.0, -3500.0)
				fliers.append(_raider("A%d" % i, at, _ai_brain(at, 100 + i)))
			for i: int in 6:
				var at := Vector3(float(i) * 200.0 - 500.0, 0.0, -11500.0)
				fliers.append(_raider("B%d" % i, at, _ai_brain(at, 200 + i), Vector3(0.0, 0.0, 60.0)))
			sim.core.set_parallel_min(2)
			var run := PackedInt64Array()
			for t: int in 180:
				await _ticks(1)
				run.append(int(sim.core.rows_digest()))
			digests.append(run)
			_assert_step_ran(schedule)
			assert_gt(tier.demotions, 0, "%s, %d threads: some ships went into the tier" % [schedule, threads])
		var first: int = -1
		for i: int in digests[0].size():
			if digests[0][i] != digests[1][i]:
				first = i
				break
		assert_eq(first, -1, "%s: the rows are the same bits with one thread and six, tier rows included (first difference at tick %d)" % [schedule, first])


# Shots the capital's guns fired so far (the native rows' state pulled into the turrets).
func _shots(cap: CapitalStandin) -> int:
	standins.pull_native_state()
	var total: int = 0
	for gun: TurretStandin in cap.guns():
		total += gun.shots
	return total
