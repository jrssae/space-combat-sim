extends GutTest
## PulseCannon with its capacitor (architecture §6.3, M2-T14), wired by hand as in test_weapons.gd: a plain RigidBody3D
## stands in for the ship and Marker3D muzzles sit at the hardpoints fixture's positions. SimClock's own processing is
## off and the clock is advanced by hand, so the recharge is exact. Covers the cannon-level behaviour (an empty
## capacitor spawns nothing, a charge gauge for the HUD) and the `weapons.charge` console key.

const FIXTURE: String = "res://tests/fixtures/hardpoints_nominal.json"
const DT: float = 1.0 / 60.0
const CAP: float = WeaponCapacitor.DEFAULT_CAPACITY
const COST: float = WeaponCapacitor.DEFAULT_COST_PER_SHOT
const RATE: float = WeaponCapacitor.DEFAULT_RECHARGE_PER_S

var world: WorldFrame
var projectiles_node: Node3D
var body: RigidBody3D
var cannon: PulseCannon
var cmd: CombatCommand
var fired_times: Array[float] = []

var _saved_clock_s: float = 0.0
var _clock_was_processing: bool = true


func before_each() -> void:
	_saved_clock_s = SimClock.now()
	_clock_was_processing = SimClock.is_physics_processing()
	SimClock.set_physics_process(false)
	SimClock.reset(100.0)
	fired_times.clear()

	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles_node = Node3D.new()
	projectiles_node.name = "Projectiles"
	world.add_child(projectiles_node)

	body = RigidBody3D.new()
	body.gravity_scale = 0.0
	body.can_sleep = false
	world.add_child(body)

	var muzzle_nodes: Array[Node3D] = []
	for entry: Dictionary in _read_muzzles():
		var marker := Marker3D.new()
		marker.name = "Muzzle_%s" % entry["name"]
		var p: Array = entry["position"]
		marker.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		body.add_child(marker)
		muzzle_nodes.append(marker)

	cannon = PulseCannon.new()
	cannon.name = "PulseCannon"
	body.add_child(cannon)
	cannon.setup(body, muzzle_nodes, projectiles_node, null, true)
	cannon.projectile_fired.connect(func(_i: int, _p: Projectile) -> void: fired_times.append(SimClock.now()))
	cannon.set_physics_process(false)
	cmd = CombatCommand.new()
	cannon.set_combat_command(cmd)


func after_each() -> void:
	SimClock.reset(_saved_clock_s)
	SimClock.set_physics_process(_clock_was_processing)


func _read_muzzles() -> Array:
	var file := FileAccess.open(FIXTURE, FileAccess.READ)
	assert_not_null(file, "fixture opens")
	var data: Variant = JSON.parse_string(file.get_as_text())
	return (data as Dictionary)["muzzles"]


func _tick() -> void:
	SimClock.advance(DT)
	cannon.step(SimClock.now())


func _hold_fire_for(seconds: float) -> void:
	cmd.fire = true
	cannon.set_combat_command(cmd)
	for i: int in roundi(seconds / DT):
		_tick()


func _idle_for(seconds: float) -> void:
	cmd.fire = false
	cannon.set_combat_command(cmd)
	for i: int in roundi(seconds / DT):
		_tick()


func _bolts() -> int:
	var count: int = 0
	for child: Node in projectiles_node.get_children():
		if child is Projectile and not child.is_queued_for_deletion():
			count += 1
	return count


func _console(line: String) -> ConsoleResult:
	var results: Array[ConsoleResult] = DebugConsole.registry.execute(line)
	assert_eq(results.size(), 1, "one statement: " + line)
	return results[0]


# --- the cannon spends and recharges ------------------------------------------------------------------------------


func test_the_cannon_starts_with_a_full_capacitor() -> void:
	assert_not_null(cannon.gate.capacitor)
	assert_eq(cannon.charge_fraction(), 1.0)


func test_firing_drains_the_capacitor_and_idle_time_refills_it() -> void:
	_hold_fire_for(1.0)
	assert_eq(fired_times.size(), 4, "4 shots in the first second, the M1 rate")
	# The store was full at the first shot, so nothing was clipped after it: spent 4 shots, recharged since the first.
	var expected: float = (CAP - 4.0 * COST + RATE * (SimClock.now() - fired_times[0])) / CAP
	assert_almost_eq(cannon.charge_fraction(), expected, 1e-9)
	assert_lt(cannon.charge_fraction(), 1.0, "spent")
	_idle_for(CAP / RATE)
	assert_eq(cannon.charge_fraction(), 1.0, "full again after capacity / rate")


func test_an_empty_capacitor_spawns_nothing() -> void:
	cannon.set_charge_fraction(0.0)
	_hold_fire_for(0.4)
	assert_eq(_bolts(), 0, "the trigger is held and nothing comes out")
	assert_eq(fired_times.size(), 0)


func test_fire_resumes_when_the_capacitor_can_pay() -> void:
	cannon.set_charge_fraction(0.0)
	_hold_fire_for(1.0)
	assert_gt(fired_times.size(), 0, "fires again once recharged")
	assert_almost_eq(fired_times[0] - 100.0, COST / RATE, 2.0 * DT, "the first bolt comes after cost / rate")


func test_a_two_second_burst_is_the_m1_rate() -> void:
	_hold_fire_for(2.0)
	assert_eq(fired_times.size(), 8)
	assert_eq(_bolts(), 8)


func test_sustained_fire_is_limited() -> void:
	_hold_fire_for(10.0)
	assert_lt(fired_times.size(), 40, "unlimited would be 40 in 10 s")
	assert_lte(float(fired_times.size()) * COST, CAP + RATE * 10.0 + 1e-6)
	assert_gt(fired_times.size(), 12, "but it is more than the first charge")


func test_the_charge_gauge_follows_the_sim_clock_while_idle() -> void:
	cannon.set_charge_fraction(0.0)
	SimClock.advance(2.0)
	assert_almost_eq(cannon.charge_fraction(), 2.0 * RATE / CAP, 1e-9, "read between ticks, no step needed")


# --- console ---------------------------------------------------------------------------------------------------


func test_console_charge_reads_and_is_writable() -> void:
	var provider: ConsoleStateProvider = DebugConsole.registry.get_provider(&"weapons")
	assert_true(provider.has_key(&"charge"))
	assert_true(provider.is_writable(&"charge"))
	assert_eq(_console("get weapons.charge").lines, PackedStringArray(["weapons.charge = 1.00"]))
	var result: ConsoleResult = _console("set weapons.charge 0.25")
	assert_true(result.ok, result.text())
	assert_almost_eq(float(DebugConsole.registry.read("weapons.charge")["value"]), 0.25, 1e-9)
	assert_almost_eq(cannon.charge_fraction(), 0.25, 1e-9)
	assert_string_contains(_console("get weapons.charge").lines[0], "weapons.charge = 0.25")


func test_console_charge_rejects_out_of_range_values() -> void:
	assert_false(_console("set weapons.charge 1.5").ok)
	assert_false(_console("set weapons.charge -0.1").ok)
	assert_eq(cannon.charge_fraction(), 1.0, "unchanged")


func test_console_charge_zero_blocks_the_fire() -> void:
	assert_true(_console("set weapons.charge 0").ok)
	_hold_fire_for(0.3)
	assert_eq(_bolts(), 0)
