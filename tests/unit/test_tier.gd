extends GutTest
## The low-attention tier's rows and integrator (M4-T21, architecture §17.14): a far fighter or capital lives in the core as
## a row with no body and no node, integrated from its held command on its beat (`tier_hz`, staggered) and advanced every
## tick; a hulk drifts with no force and is never removed; the rows join the scan's rows after the statics, flagged tier,
## and move with a rebase; the core names what the director demotes and promotes. Driven through the core's native API
## with a hand-held tick, so the beats and the bits are under the test's control. Skips, saying why, when the library is
## not built.

const SPEC_PATH: String = "res://assets/ships/starfury_aurora.tres"
const LAYOUT_PATH: String = "res://tests/fixtures/hardpoints_nominal.json"
const DT: float = 1.0 / 60.0
const PERIOD: int = 3
const SETTINGS: Array[StringName] = []
const NO_NODES: Array[Node] = []

var world: WorldFrame
var projectiles: Node3D
var _saved: Dictionary = {}
var _tick: int = 1000


func before_each() -> void:
	for key: StringName in SETTINGS:
		_saved[key] = Settings.get_value(key)
	Factions.reset()
	ContactScan.invalidate()
	ContactScan.clear_statics()
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	_tick = 1000


func after_each() -> void:
	ContactScan.clear_statics()
	ContactScan.invalidate()
	for key: StringName in SETTINGS:
		Settings.set_value(key, _saved[key])
	Factions.reset()


func _skipped() -> bool:
	if NativeLib.has_class(NativeProbe.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there is no tier to test")
	return true


func _core() -> SimCore:
	var sim: SimCore = SimCore.attach(world)
	assert_not_null(sim, "a core attaches to the world")
	sim.core.tier_set_period(PERIOD)
	return sim


# The Starfury as a tier type: its spec and nominal hardpoints, as the director registers a pooled ship's type.
func _starfury_type(sim: SimCore) -> int:
	var spec: ShipSpec = load(SPEC_PATH) as ShipSpec
	var layout: ThrusterLayout = ThrusterLayout.load_file(LAYOUT_PATH)
	assert_true(layout.valid, "the nominal hardpoints load")
	var a: Array = FlightBatch.type_arrays(spec, layout)
	var type_ix: int = int(sim.core.tier_register_type(a[0], a[1], a[2], a[3], a[4], a[5], layout.center_of_mass))
	assert_gte(type_ix, 0, "the type registers")
	return type_ix


# One core tick by hand: the tier steps inside the first sync.
func _step(sim: SimCore, ticks: int = 1) -> void:
	for i: int in ticks:
		_tick += 1
		sim.core.sync_in(_tick, DT)


# A fighter row with a held command (`main_left, main_right, retro_left, retro_right, strafe x, y, rot x, y, z, brake, fire`).
func _fighter(sim: SimCore, type_ix: int, body_id: int, at: Vector3, velocity: Vector3, angular: Vector3,
		command: PackedFloat64Array = PackedFloat64Array(), assist_on: bool = false, basis: Basis = Basis.IDENTITY) -> int:
	var handle: int = int(sim.core.tier_add(SimCore.KIND_SHIP, body_id, 0, type_ix, at, velocity, basis, angular))
	assert_lt(handle, 0, "a tier handle is below zero, apart from the bodies' handles")
	assert_true(sim.core.tier_set_attrs(body_id, body_id + 500000, Factions.EARTH_ALLIANCE, "TIER %d" % body_id, 12.0, 0.0, 1.0))
	assert_true(sim.core.tier_set_control(body_id, Vector3.ZERO, command, 0.0, assist_on))
	return handle


func _capital(sim: SimCore, body_id: int, at: Vector3, velocity: Vector3, cruise: Vector3) -> int:
	var handle: int = int(sim.core.tier_add(SimCore.KIND_CAPITAL, body_id, 0, 0, at, velocity, Basis.IDENTITY, Vector3.ZERO))
	assert_true(sim.core.tier_set_attrs(body_id, 0, Factions.RAIDERS, "CAP %d" % body_id, 150.0, 0.0, 1.0))
	assert_true(sim.core.tier_set_control(body_id, cruise, PackedFloat64Array(), 0.0, false))
	return handle


static func _orthonormal(b: Basis) -> bool:
	return b.is_equal_approx(b.orthonormalized()) and absf(b.determinant() - 1.0) < 1e-4


# --- the integrator ------------------------------------------------------------------------------------------------------


func test_a_coasting_fighter_keeps_its_velocity_and_spin_bit_for_bit() -> void:
	if _skipped():
		return
	var sim: SimCore = _core()
	var type_ix: int = _starfury_type(sim)
	var v := Vector3(123.456, -7.5, -300.25)
	var w := Vector3(0.1, -0.05, 0.3)
	_fighter(sim, type_ix, 701, Vector3(5000.0, 10.0, -20000.0), v, w)
	var before: Dictionary = sim.core.tier_state(701)
	_step(sim, 600)
	var after: Dictionary = sim.core.tier_state(701)
	assert_eq(after["velocity"], v, "no command, no gravity: the velocity does not change by a bit over 10 s")
	assert_eq(after["angular"], w, "nor the spin")
	var moved: Vector3 = (after["position"] as Vector3) - (before["position"] as Vector3)
	assert_lt(moved.distance_to(v * 10.0), 1.0, "it moved 10 s of its velocity, within the 32-bit rounding of 600 steps 20 km out (%s)" % moved)
	assert_true(_orthonormal(after["basis"]), "the basis stays orthonormal while it spins")
	assert_ne(after["basis"], before["basis"], "and it did turn")
	assert_eq(int(sim.core.tier_beats()), 200, "a beat every %d ticks" % PERIOD)


func test_gravity_pulls_a_tier_row_as_the_stand_in_pulls_a_body() -> void:
	if _skipped():
		return
	var sim: SimCore = _core()
	var type_ix: int = _starfury_type(sim)
	var moon := GravityStandin.new()
	add_child_autofree(moon)
	moon.install(world, world.to_universe(Vector3(0.0, -400000.0, 0.0)), 0.03 * 400000.0 * 400000.0)
	sim.core.tier_set_gravity(PackedVector3Array([Vector3(0.0, -400000.0, 0.0)]), PackedFloat64Array([moon.gm]))
	var at := Vector3(3000.0, 200.0, -12000.0)
	assert_eq(sim.core.tier_gravity_at(at), moon.accel(at), "the same pull, bit for bit, as GravityStandin.accel")
	_fighter(sim, type_ix, 702, at, Vector3.ZERO, Vector3.ZERO)
	_step(sim, PERIOD)  # the first beat sets the pull; then it applies every tick
	var v0: Vector3 = sim.core.tier_state(702)["velocity"]
	_step(sim, 60)
	var v1: Vector3 = sim.core.tier_state(702)["velocity"]
	var dv: Vector3 = v1 - v0
	assert_lt(dv.distance_to(moon.accel(at) * 1.0), 0.002, "one second of the pull in one second (%s)" % dv)
	assert_lt(dv.y, 0.0, "downward, toward the moon")


func test_a_held_command_pushes_a_fighter_and_the_speed_ceiling_holds() -> void:
	if _skipped():
		return
	var sim: SimCore = _core()
	var type_ix: int = _starfury_type(sim)
	var full := PackedFloat64Array([1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	_fighter(sim, type_ix, 703, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, full, true)
	_step(sim, 60)
	var state: Dictionary = sim.core.tier_state(703)
	var v: Vector3 = state["velocity"]
	var spec: ShipSpec = load(SPEC_PATH) as ShipSpec
	var layout: ThrusterLayout = ThrusterLayout.load_file(LAYOUT_PATH)
	var mains: int = 0
	for group: int in layout.nozzle_groups:
		mains += 1 if group < 2 else 0
	var expected: float = float(mains) * spec.pod_main_thrust / spec.mass  # every main nozzle, no governor loss at low speed
	assert_lt(v.z, 0.0, "full main thrust pushes along the nose (-Z)")
	assert_between(-v.z, expected * 0.8, expected * 1.02, "about one second of the pods' acceleration (%.1f m/s)" % -v.z)
	assert_lt(absf(v.x) + absf(v.y), 0.5, "and not sideways")
	# A row launched above the ceiling is held to it from its first tick.
	_fighter(sim, type_ix, 704, Vector3(1000.0, 0.0, 0.0), Vector3(0.0, 0.0, -2.0 * spec.speed_limit_mps), Vector3.ZERO, full, false)
	_step(sim, PERIOD + 1)
	var fast: Vector3 = sim.core.tier_state(704)["velocity"]
	assert_lte(fast.length(), spec.speed_limit_mps * 1.0001, "the hard ceiling (%.0f) holds a tier row too (%.0f)" % [
			spec.speed_limit_mps, fast.length()])


func test_the_assist_damps_a_spin_on_the_beat_and_the_accel_is_held_between() -> void:
	if _skipped():
		return
	var sim: SimCore = _core()
	var type_ix: int = _starfury_type(sim)
	var zero := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	_fighter(sim, type_ix, 705, Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 0.5, 0.0), zero, true)
	var before: float = (sim.core.tier_state(705)["angular"] as Vector3).length()
	_step(sim, 120)
	var after: float = (sim.core.tier_state(705)["angular"] as Vector3).length()
	assert_lt(after, before * 0.5, "flight assist brings the spin down over 2 s (%.3f from %.3f rad/s)" % [after, before])
	var alpha_before: Vector3 = sim.core.tier_state(705)["alpha"]
	_step(sim, 1)
	var alpha_mid: Vector3 = sim.core.tier_state(705)["alpha"]
	_step(sim, 1)
	var alpha_after: Vector3 = sim.core.tier_state(705)["alpha"]
	var changes: int = int(alpha_before != alpha_mid) + int(alpha_mid != alpha_after)
	assert_lte(changes, 1, "between two beats the angular acceleration is held, so at most one change in two ticks")


func test_a_capital_row_comes_back_to_its_cruise_at_two_metres_per_second_squared_at_most() -> void:
	if _skipped():
		return
	var sim: SimCore = _core()
	var cruise := Vector3(0.0, 0.0, -30.0)
	_capital(sim, 801, Vector3(20000.0, 0.0, 0.0), Vector3(40.0, 0.0, -30.0), cruise)
	var worst: float = 0.0
	for i: int in 600:
		_step(sim, 1)
		worst = maxf(worst, (sim.core.tier_state(801)["accel"] as Vector3).length())
	var v: Vector3 = sim.core.tier_state(801)["velocity"]
	assert_lte(worst, 2.0 * 1.0001, "the engines push 2 m/s^2 at most (%.3f)" % worst)
	assert_almost_eq(v.distance_to(cruise), 20.0, 0.5, "after 10 s at the 2 m/s^2 cap, 20 of the 40 m/s error is left (%s)" % v)
	_step(sim, 1200)
	v = sim.core.tier_state(801)["velocity"]
	assert_lt(v.distance_to(cruise), 1.0, "and after 30 s it cruises (%s)" % v)
	assert_eq(sim.core.tier_state(801)["angular"], Vector3.ZERO, "a capital does not spin")


func test_a_hulk_drifts_on_its_last_motion_and_is_never_removed() -> void:
	if _skipped():
		return
	var sim: SimCore = _core()
	var type_ix: int = _starfury_type(sim)
	var full := PackedFloat64Array([1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0])
	var v := Vector3(10.0, 2.0, -40.0)
	var w := Vector3(0.0, 0.0, 0.2)
	_fighter(sim, type_ix, 706, Vector3(100.0, 0.0, -30000.0), v, w, full, true)
	_step(sim, 10)
	assert_ne(sim.core.tier_state(706)["velocity"], v, "a live row flies its command")
	assert_true(sim.core.tier_set_hulk(706, true))
	var at_hulk: Vector3 = sim.core.tier_state(706)["velocity"]
	var spin_at_hulk: Vector3 = sim.core.tier_state(706)["angular"]
	_step(sim, 600)
	var state: Dictionary = sim.core.tier_state(706)
	assert_eq(state["velocity"], at_hulk, "a hulk's velocity does not change by a bit: no force, whatever its command says")
	assert_eq(state["angular"], spin_at_hulk, "it keeps spinning as it was when it went dead")
	assert_true(bool(state["hulk"]))
	assert_eq(int(sim.core.tier_hulks()), 1)
	assert_true(sim.core.tier_has(706), "10 s idle: still there")
	var row: int = int(sim.core.row_of_id(706))
	assert_gte(row, 0, "a hulk is a scan row")
	var flags: int = int(sim.core.row_flags(row))
	assert_eq(flags & 48, 48, "flagged tier and hulk (%d)" % flags)
	assert_eq(flags & SimCore.FLAG_HULL_ACTIVE, 0, "no active hull: nothing sweeps or rams it")
	# A hulk is not a ship to the contacts: it is out of the brains' targeting (the scan's is_ship column).
	var zero := Vector3.ZERO
	_fighter(sim, type_ix, 707, zero, zero, zero)
	_step(sim, 1)
	var snapshot: Array = sim.core.snapshot_all()
	var ids: PackedInt64Array = snapshot[0]
	assert_false(ids.has(706) or ids.has(707), "tier rows stay out of the scan GDScript builds (after node_count)")
	var take: Dictionary = sim.core.tier_take(706)
	assert_true(bool(take["hulk"]), "promotion hands the hulk flag back")
	assert_false(sim.core.tier_has(706))
	assert_eq(int(sim.core.tier_count()), 1, "the other row stays")
	assert_eq(sim.core.tier_state(707)["body_id"], 707, "and keeps its own state after the swap")


# --- the rows --------------------------------------------------------------------------------------------------------------


func test_tier_rows_join_the_scan_rows_after_the_statics_flagged_tier() -> void:
	if _skipped():
		return
	StaticRows.register(12345, Vector3(50.0, 0.0, 0.0), 20.0, BodyKind.STATIC, Factions.NEUTRAL, world)
	var sim: SimCore = _core()
	var type_ix: int = _starfury_type(sim)
	_fighter(sim, type_ix, 708, Vector3(0.0, 0.0, -15000.0), Vector3(0.0, 0.0, -100.0), Vector3.ZERO)
	_capital(sim, 802, Vector3(0.0, 0.0, -25000.0), Vector3.ZERO, Vector3(0.0, 0.0, -30.0))
	sim.sync_now()
	assert_eq(sim.rows(), 3, "a static and two tier rows")
	assert_eq(int(sim.core.node_count()), 0, "no body row")
	var fighter_row: int = int(sim.core.row_of_id(708))
	var capital_row: int = int(sim.core.row_of_id(802))
	assert_gte(fighter_row, 1, "the tier rows come after the static")
	assert_gte(capital_row, 1)
	assert_eq(int(sim.core.row_flags(fighter_row)) & (SimCore.FLAG_TIER | SimCore.FLAG_HULL), SimCore.FLAG_TIER | SimCore.FLAG_HULL)
	assert_eq(int(sim.core.row_flags(fighter_row)) & SimCore.FLAG_RIGID, 0, "no Jolt body")
	assert_eq(sim.core.row_name(fighter_row), "TIER 708", "the name rides beside the row")
	assert_eq(sim.core.row_name(capital_row), "CAP 802")
	assert_eq(int(sim.core.row_flags(fighter_row)) & SimCore.FLAG_TIER, SimCore.FLAG_TIER)
	var snapshot_ids: Array = []
	assert_eq(int(sim.core.rows_digest()) != 0, true)
	var state_708: Dictionary = sim.core.tier_state(708)
	assert_eq(int(state_708["marker_id"]), 708 + 500000, "the row carries its marker's id")
	var handle: int = sim.handle_of(708)
	assert_lt(handle, 0, "the tier row's handle")
	assert_eq(sim.row_of(handle), fighter_row, "and it resolves")
	var digest: int = int(sim.core.rows_digest())
	sim.sync_now()
	assert_ne(int(sim.core.rows_digest()), digest, "the rows move between syncs: the digest sees the tier")
	var state: Dictionary = sim.core.tier_state(708)
	assert_eq(sim.core.row_position(fighter_row), state["position"], "the scan row holds the tier row's place")
	var snapshot: Array = sim.core.snapshot_all()
	assert_eq((snapshot[0] as PackedInt64Array).size(), 1, "the registry's face carries the static only")


func test_a_rebase_shifts_the_tier_rows_and_the_pull_once() -> void:
	if _skipped():
		return
	var sim: SimCore = _core()
	var type_ix: int = _starfury_type(sim)
	sim.core.tier_set_gravity(PackedVector3Array([Vector3(0.0, -400000.0, 0.0)]), PackedFloat64Array([4.8e9]))
	_fighter(sim, type_ix, 709, Vector3(100.0, 200.0, -15000.0), Vector3.ZERO, Vector3.ZERO)
	sim.sync_now()
	var at: Vector3 = sim.core.tier_state(709)["position"]
	var pull: Vector3 = sim.core.tier_gravity_at(at)
	var offset := Vector3(4000.0, -300.0, 2500.0)
	world.rebase(offset)
	var after: Vector3 = sim.core.tier_state(709)["position"]
	assert_eq(after, at - offset, "the row moved by the rebase, as a node does")
	assert_eq(sim.core.row_position(int(sim.core.row_of_id(709))), after, "and so did its scan row, once")
	assert_eq(sim.core.tier_gravity_at(after), pull, "the moon moved with it: the same pull at the same place")


func test_the_core_names_the_far_bodies_to_demote_and_the_near_rows_to_promote() -> void:
	if _skipped():
		return
	var near: RigidBody3D = _body(Vector3(0.0, 0.0, -3000.0), "NEAR")
	var far: RigidBody3D = _body(Vector3(0.0, 0.0, -12000.0), "FAR")
	var player: RigidBody3D = _body(Vector3(0.0, 0.0, -40000.0), "PLAYER")
	var sim: SimCore = _core()
	var type_ix: int = _starfury_type(sim)
	_fighter(sim, type_ix, 710, Vector3(0.0, 0.0, -9000.0), Vector3.ZERO, Vector3.ZERO)
	_fighter(sim, type_ix, 711, Vector3(0.0, 0.0, -20000.0), Vector3.ZERO, Vector3.ZERO)
	sim.sync_now()
	var at := Vector3.ZERO
	var to_demote: PackedInt64Array = sim.core.tier_far_bodies(at, player.get_instance_id(), 11000.0, 64)
	assert_eq(to_demote, PackedInt64Array([far.get_instance_id()]), "the far body, not the near one, not the player")
	assert_eq(sim.core.tier_far_bodies(at, player.get_instance_id(), 11000.0, 0).size(), 0, "capped")
	var to_promote: PackedInt64Array = sim.core.tier_near_rows(at, 10000.0, 64)
	assert_eq(to_promote, PackedInt64Array([710]), "the tier row within the radius, not the one beyond")
	assert_eq(sim.core.tier_far_bodies(at, 0, 2000.0, 64).size(), 3, "all three bodies beyond 2 km when none is excluded")
	near.free()


func test_take_hands_the_state_back_exactly_and_keeps_the_other_rows_whole() -> void:
	if _skipped():
		return
	var sim: SimCore = _core()
	var type_ix: int = _starfury_type(sim)
	var basis := Basis(Vector3(0.3, 0.5, 0.8).normalized(), 1.1)
	var cmd := PackedFloat64Array([0.25, 0.75, 0.0, 0.1, 0.2, -0.3, 0.4, -0.5, 0.6, 1.0, 1.0])
	_fighter(sim, type_ix, 712, Vector3(1.0, 2.0, 3.0), Vector3(4.0, 5.0, 6.0), Vector3(0.01, 0.02, 0.03), cmd, true, basis)
	assert_true(sim.core.tier_set_control(712, Vector3.ZERO, cmd, 0.37, true))
	_fighter(sim, type_ix, 713, Vector3(9.0, 9.0, 9.0), Vector3.ZERO, Vector3.ZERO)
	var first: Dictionary = sim.core.tier_take(712)
	assert_eq(first["position"], Vector3(1.0, 2.0, 3.0))
	assert_eq(first["velocity"], Vector3(4.0, 5.0, 6.0))
	assert_eq(first["angular"], Vector3(0.01, 0.02, 0.03))
	assert_eq(first["basis"], basis)
	assert_eq(float(first["pod_yaw"]), 0.37)
	assert_true(bool(first["assist_on"]))
	assert_eq(first["command"], cmd, "the held command, trigger included")
	assert_eq(int(sim.core.tier_count()), 1)
	assert_eq(sim.core.tier_state(713)["position"], Vector3(9.0, 9.0, 9.0), "the row that moved into the gap is itself")
	sim.sync_now()
	assert_eq(sim.core.row_name(int(sim.core.row_of_id(713))), "TIER 713", "with its own name")
	assert_true(sim.core.tier_take(712).is_empty(), "taking a body that is not in the tier gives nothing")
	assert_eq(int(sim.core.tier_add(SimCore.KIND_SHIP, 713, 0, type_ix, Vector3.ZERO, Vector3.ZERO, Basis.IDENTITY, Vector3.ZERO)),
			0, "a body in the tier is not added twice")


# A rigid body with a marker and a hull, as a ship has them, so the core lists it as a fighter in Jolt.
func _body(at: Vector3, label: String) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.freeze = true
	world.add_child(body)
	body.add_to_group(WorldFrame.SHIFTABLE_GROUP)
	body.global_position = at
	var hull := Damageable.new()
	hull.faction = Factions.EARTH_ALLIANCE
	hull.bounding_radius = 12.0
	body.add_child(hull)
	var t := Targetable.new()
	t.name = "Targetable"
	t.display_name = label
	t.faction = Factions.EARTH_ALLIANCE
	body.add_child(t)
	return body
