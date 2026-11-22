extends GutTest
## Disabled hulks on the Omega in the real main scene (M10-T10, D12.7, Q19, AC8's hulk clause): a disabled hull loses power,
## control and thrust in stages and then drifts cold on its last motion, still a target whose sections can blow; its lights go
## out while a sister's stay lit; a jump point it held collapses; in the low-attention tier it is a hulk row that ignores its
## cruise, and comes back a hulk; a scuttle is silent and makes a hulk; a hulk destroyed blasts as its kind does; the Vorlons never leave a hulk.

const TYPE: StringName = &"ea_omega"
const SPEED_UP: float = 4.0

var main: Main
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8
var _radius_backup: float = 10000.0


func before_each() -> void:
	get_tree().paused = false
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame
	_radius_backup = float(Settings.get_value(&"tier_radius_m"))
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.scenario_seed = 3
	add_child_autofree(main)
	await wait_physics_frames(2)
	DebugConsole.flags.invulnerable = true


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	Settings.set_value(&"tier_radius_m", _radius_backup)
	DebugConsole.flags.invulnerable = false


# An Omega for Earth Alliance `ahead_m` along the player's nose, bow with the player's, holding `speed` along its bow.
func _spawn(display_name: String, ahead_m: float, speed: float = 0.0) -> CapitalShip:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(TYPE, Factions.EARTH_ALLIANCE, display_name, rest)
	assert_not_null(cap, "the Omega is generated (scripts/gen_assets.sh)")
	if cap == null:
		return null
	var basis: Basis = main.ship.global_basis
	main.world.spawn(cap, main.world.to_universe(main.ship.global_position - basis.z * ahead_m), basis)
	cap.set_course(-basis.z, rest - basis.z * speed)
	return cap


func _fly(seconds: float, done: Callable = Callable()) -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < seconds:
		await get_tree().physics_frame
		if done.is_valid() and bool(done.call()):
			break
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute_tokens(line.split(" ", false))


func _disable(cap: CapitalShip) -> void:
	assert_true(_run("capital focus %s" % String(cap.name)).ok, "focused by its node name (the console splits on spaces)")
	var out: ConsoleResult = _run("capital disable")
	assert_true(out.ok, out.error)
	assert_true(cap.is_hulk(), "disabled")


func test_it_loses_power_then_control_then_thrust_and_drifts_cold_still_a_target() -> void:
	var cap: CapitalShip = _spawn("EAS Agamemnon", 4000.0, 40.0)
	if cap == null:
		return
	var cold: Array[bool] = []
	cap.hulk_cold.connect(func() -> void: cold.append(true))
	await _fly(1.0)
	var built_thrust: float = cap.flight_spec.pod_main_thrust
	_disable(cap)
	assert_eq(cap.hulk_stages.stage, HulkStages.Stage.POWER_LOST, "power goes first")
	assert_eq(cap.damage.live_mounts().size(), 0, "nothing fires without power")
	assert_eq(cap.damage.live_bays().size(), 0, "nor launches")
	assert_eq(cap.flight_spec.pod_main_thrust, built_thrust, "the drive is not cut at once")
	assert_true(cap.flight_assist(), "the helm still steers on its last orders")
	assert_gt(cap.flight_command().main_left + cap.flight_command().main_right, 0.0, "the mains still push, winding down")
	var orders: Vector3 = cap.cruise_velocity
	cap.set_course(Vector3.UP, orders + Vector3(0.0, 100.0, 0.0))
	assert_eq(cap.cruise_velocity, orders, "its brain is released: no new orders reach the helm")
	await _fly(cap.hulk_stages.control_loss_s, func() -> bool: return not cap.hulk_stages.has_control())
	assert_eq(cap.hulk_stages.stage, HulkStages.Stage.CONTROL_LOST, "then control")
	assert_eq(cap.flight_command().rot, Vector3.ZERO, "no steering")
	assert_false(cap.flight_assist(), "and no assist")
	await _fly(cap.hulk_stages.cold_s, func() -> bool: return cap.hulk_stages.is_cold())
	assert_eq(cold, [true], "then the drive is cold")
	assert_eq(cap.flight_spec.pod_main_thrust, 0.0)
	await wait_physics_frames(2)
	var v0: Vector3 = cap.linear_velocity
	var w0: Vector3 = cap.angular_velocity
	await _fly(3.0)
	assert_lt((cap.linear_velocity - v0).length(), 0.05, "it drifts on its last motion")
	assert_lt((cap.angular_velocity - w0).length(), 1e-4, "its tumble kept")
	assert_true(cap.visible and cap.targetable.is_inside_tree(), "still a target")
	assert_eq(cap.targetable.kind, Targetable.Kind.CAPITAL)
	var destroyed: Array[HitInfo] = []
	main.director.capital_destroyed.connect(func(c: CapitalBody, info: HitInfo) -> void:
		if c == cap:
			destroyed.append(info))
	assert_true(_run("capital damage magazine 6000").ok, "its sections can still be hit")
	assert_eq(cap.damage.blown, "magazine", "and blow")
	await wait_physics_frames(2)
	assert_eq(destroyed.size(), 1, "the destruction director took the hulk's death")
	assert_false(cap.is_hulk(), "destroyed, no longer a hulk")


func test_its_lights_go_out_while_a_sisters_stay_lit_and_come_back_whole() -> void:
	var cap: CapitalShip = _spawn("EAS Agamemnon", 4000.0)
	var sister: CapitalShip = _spawn("EAS Achilles", 7000.0)
	if cap == null or sister == null:
		return
	await wait_physics_frames(2)
	var shared: Array[float] = _glow(sister)
	assert_false(shared.is_empty(), "the Omega's hull glows")
	_disable(cap)
	var lights: CapitalHulkLights = cap._lights
	assert_not_null(lights)
	assert_gt(lights.count(), 0, "its glowing surfaces have materials of their own")
	await _fly(cap.hulk_stages.lights_fade_s + 0.6, func() -> bool: return not cap.hulk_stages.lights_fading())
	await wait_frames(2)
	assert_eq(lights.level, 0.0, "its lights are out")
	for value: float in _glow(cap):
		assert_eq(value, 0.0, "every glowing surface dark")
	assert_eq(_glow(sister), shared, "its sister, on the same materials, stays lit")
	cap.damageable.restore()
	assert_false(cap.is_hulk())
	assert_eq(_glow(cap), shared, "whole again, it wears the shared materials lit")


func test_a_jump_point_it_held_collapses_when_it_is_disabled() -> void:
	var cap: CapitalShip = _spawn("EAS Agamemnon", 4000.0)
	if cap == null:
		return
	await wait_physics_frames(3)
	var pool := JumpPointPool.new()
	pool.world = main.world
	main.world.add_child(pool)
	pool.prepare(2)
	var point: JumpVortex = cap.open_own_point(pool)
	assert_not_null(point, "the Omega opens its own point")
	await _fly(1.0)
	assert_eq(pool.collapses, 0, "held while it fights")
	_disable(cap)
	await wait_physics_frames(3)
	assert_eq(pool.collapses, 1, "a hulk holds nothing open")


func test_in_the_tier_it_is_a_hulk_row_that_ignores_its_cruise_and_comes_back_a_hulk() -> void:
	Settings.set_value(&"tier_radius_m", 30000.0)
	var cap: CapitalShip = _spawn("EAS Agamemnon", 15000.0)
	var later: CapitalShip = _spawn("EAS Achilles", 18000.0)
	if cap == null or later == null:
		return
	await wait_physics_frames(3)
	var sim: SimCore = SimCore.for_tree(get_tree())
	_disable(cap)
	cap.cruise_velocity += Vector3(0.0, 0.0, -50.0)  # a live row would chase this; a hulk must not
	Settings.set_value(&"tier_radius_m", 10000.0)
	await _fly(1.0, func() -> bool: return cap.is_tier_parked() and later.is_tier_parked())
	assert_true(cap.is_tier_parked() and later.is_tier_parked(), "both are tier rows")
	assert_true(cap.hulk_stages.is_cold(), "a hulk goes into the tier cold")
	assert_eq(int(sim.core.tier_hulks()), 1, "a hulk row")
	var v0: Vector3 = TierDirector.flying_velocity(cap)
	await _fly(2.0)
	assert_lt((TierDirector.flying_velocity(cap) - v0).length(), 0.05, "it drifts, its cruise ignored")
	_disable(later)
	assert_eq(int(sim.core.tier_hulks()), 2, "one disabled in the tier becomes a hulk row")
	assert_true(later.hulk_stages.is_cold())
	Settings.set_value(&"tier_radius_m", 30000.0)
	await _fly(1.0, func() -> bool: return not cap.is_tier_parked() and not later.is_tier_parked())
	assert_false(cap.is_tier_parked(), "back within the radius it is a body")
	assert_true(cap.is_hulk(), "and still a hulk")
	assert_eq(cap.flight_command().main_left, 0.0, "with no command")
	await wait_physics_frames(2)
	assert_lt((cap.linear_velocity - v0).length(), 0.05, "drifting as its row did")


func test_a_scuttle_is_silent_and_makes_a_hulk_with_no_cap() -> void:
	var ships: Array[CapitalShip] = []
	for i: int in 3:
		var c: CapitalShip = _spawn("EAS Agamemnon" if i == 0 else "EAS Achilles" if i == 1 else "EAS Ajax", 4000.0 * (i + 1) - 6000.0)
		if c == null:
			return
		ships.append(c)
	await wait_physics_frames(3)
	var deaths: Array = []
	main.director.capital_destroyed.connect(func(c: CapitalBody, info: HitInfo) -> void: deaths.append([c, info]))
	for c: CapitalShip in ships:
		assert_true(c.scuttle(), "the crew scuttles it")
		assert_false(c.scuttle(), "once")
	await _fly(1.0)
	assert_true(deaths.is_empty(), "no blast, no explosion")
	for c: CapitalShip in ships:
		assert_true(c.is_hulk())
		assert_eq(c.damage.live_mounts().size(), 0, "it stops firing")
	await _fly(ships[0].hulk_stages.cold_s, func() -> bool: return ships[0].hulk_stages.is_cold())
	assert_true(ships[0].hulk_stages.is_cold(), "it goes through the stages")
	assert_eq(CapitalFlight.of(main.world).hulks.size(), 3, "every hulk stays: there is no cap")
	await _fly(1.0)
	assert_true(deaths.is_empty(), "none scuttled by a count")
	var listed: ConsoleResult = _run("capital hulks")
	assert_true(listed.ok, listed.error)
	assert_string_contains("\n".join(listed.lines), "3 hulks")
	assert_true(_run("capital focus %s" % String(ships[0].name)).ok)
	assert_false(_run("capital scuttle").ok, "already disabled")


func test_a_destroyed_hulk_blasts_as_big_as_any_ship_of_its_kind() -> void:
	var hulk: CapitalShip = _spawn("EAS Agamemnon", 4000.0)
	var fresh: CapitalShip = _spawn("EAS Achilles", -4000.0)
	if hulk == null or fresh == null:
		return
	await wait_physics_frames(3)
	var blasts: Dictionary = {}
	main.director.capital_destroyed.connect(func(c: CapitalBody, info: HitInfo) -> void: blasts[c] = info.blast_energy_j)
	hulk.scuttle()
	await _fly(1.0)
	hulk.damageable.kill()
	fresh.damageable.kill()
	await wait_physics_frames(2)
	assert_gt(float(blasts.get(hulk, 0.0)), 0.0, "the hulk blows")
	assert_eq(blasts.get(hulk), blasts.get(fresh), "with the blast of a ship of its kind, no special scuttle blast")


func test_a_vorlon_or_shadow_ship_explodes_instead_of_becoming_a_hulk() -> void:
	var cap: CapitalShip = CapitalShip.create(TYPE, &"vorlons", "Vorlon test", Vector3.ZERO)
	if cap == null:
		return
	main.world.spawn(cap, main.world.to_universe(main.ship.global_position + Vector3(0.0, 0.0, -6000.0)), Basis.IDENTITY)
	await wait_physics_frames(3)
	var deaths: Array = []
	main.director.capital_destroyed.connect(func(c: CapitalBody, info: HitInfo) -> void: deaths.append([c, info.cause]))
	assert_true(cap.scuttle(), "the order is taken")
	await wait_physics_frames(3)
	assert_eq(deaths, [[cap, HitInfo.CAUSE_NO_HULK]], "it blows at once, a hulk never forms")
	assert_false(cap.is_hulk())
	assert_true(cap.hulk_stages.is_live(), "no wind-down began")


func test_the_console_reads_the_wind_down() -> void:
	var cap: CapitalShip = _spawn("EAS Agamemnon", 4000.0)
	if cap == null:
		return
	await wait_physics_frames(2)
	assert_string_contains(str(DebugConsole.registry.read("capital.hulk").get("value")), "live")
	_disable(cap)
	assert_string_contains(str(DebugConsole.registry.read("capital.hulk").get("value")), "power lost")
	assert_string_contains(_run("capital disable").lines[0], "already disabled")
	assert_eq(str(DebugConsole.registry.read("capital.hulks").get("value")), "1")
	assert_eq(str(DebugConsole.registry.read("capital.state").get("value")), "disabled")


# The glow strengths of every glowing surface of `cap`'s hull and rotors, in walk order.
func _glow(cap: CapitalShip) -> Array[float]:
	var out: Array[float] = []
	var roots: Array[Node] = [cap.hull_piece]
	for rotor: CapitalRotor in cap.rotors:
		roots.append(rotor.visual_pivot)
	for root: Node in roots:
		_glow_under(root, out)
	return out


func _glow_under(node: Node, out: Array[float]) -> void:
	var mesh_node := node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		for i: int in mesh_node.mesh.get_surface_count():
			var keys: Dictionary = CapitalHulkLights._energies(mesh_node.mesh.surface_get_material(i))
			var active: Material = mesh_node.get_active_material(i)
			for key: StringName in keys:
				out.append(_energy_of(active, key))
	for child: Node in node.get_children():
		_glow_under(child, out)


static func _energy_of(material: Material, key: StringName) -> float:
	if material is StandardMaterial3D:
		return (material as StandardMaterial3D).emission_energy_multiplier
	var value: Variant = (material as ShaderMaterial).get_shader_parameter(key)
	return float(value) if value != null else 0.0
