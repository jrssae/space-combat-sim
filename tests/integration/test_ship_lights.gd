extends GutTest
## AC31 in the real scene (M3-T22, Q23): every main pod nozzle has a light whose energy follows its plume (0 at idle, full at full
## thrust, the plume's colour), every shot adds a muzzle-flash light for 60 ms, an explosion's light keeps its curve, and all of
## them go through the rig's `LightPicker`, never a `Light3D` of their own. Pooled ships take their lights out of the competition
## when parked. Headless, so no GPU: how it looks is P9 and AC35.

const RAIDER_SPEC: String = "res://assets/ships/raider_delta_v.tres"
const FIGHT_TICKS: int = 900

var main: Main
var rig: SplatLightRig
var source: FakeInputSource
var output: FlightOutput = null


func before_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true
	ContactScan.invalidate()
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.waves_auto_start = false
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame  # the ships' first `_process` puts their lights in the competition
	rig = main.space_environment.light_rig


func after_each() -> void:
	DebugConsole.flags.invulnerable = false
	ContactScan.invalidate()


func _source() -> FlightOutput:
	return output


func _full_output(level: float) -> FlightOutput:
	var pods: int = main.ship.get_layout().pod_count()
	var made := FlightOutput.new()
	made.main_levels.resize(pods)
	made.main_levels.fill(level)
	made.retro_levels.resize(pods)
	made.retro_levels.fill(level)
	return made


func _settle(visuals: ThrusterVisuals) -> void:
	for i: int in 90:
		visuals.advance(1.0 / 60.0)


func _lights(parent: Node, out: Array = []) -> Array:
	if parent is Light3D:
		out.append(parent)
	for child: Node in parent.get_children():
		_lights(child, out)
	return out


func _mains(layout: ThrusterLayout) -> int:
	var n: int = 0
	for group: Variant in layout.nozzle_groups:
		n += 1 if ThrusterLayout.is_main_group(group) else 0
	return n


func _registered(visuals: ThrusterVisuals) -> bool:
	for i: int in visuals.glow_count():
		if visuals.nozzle_light(i) != null and not rig.has_emitter(visuals.nozzle_light(i)):
			return false
	return true


func _shining() -> int:
	var n: int = 0
	for light: Light3D in rig.slots():
		n += 1 if light.light_energy > 0.0 else 0
	return n


func _camera_position() -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d()
	return camera.global_position if camera != null else Vector3.ZERO


# --- nozzles --------------------------------------------------------------------------------------------------------


func test_every_main_pod_nozzle_has_a_light_and_no_other_nozzle_does() -> void:
	var visuals: ThrusterVisuals = main.thrusters
	var layout: ThrusterLayout = main.ship.get_layout()
	assert_gt(_mains(layout), 0)
	assert_eq(visuals.light_count(), _mains(layout))
	for i: int in visuals.glow_count():
		var is_main: bool = i < layout.nozzle_count() and ThrusterLayout.is_main_group(layout.nozzle_groups[i])
		assert_eq(visuals.nozzle_light(i) != null, is_main, "plume %s" % visuals.glow(i).name)
	assert_true(rig.candidate_count() >= _mains(layout), "the nozzles are among the rig's candidates in the chase camera")
	assert_true(_registered(visuals))


func test_the_light_follows_the_plume_from_idle_to_full_thrust() -> void:
	var visuals: ThrusterVisuals = main.thrusters
	visuals.setup(main.ship.get_layout(), _source)
	var lights: Array[LightEmitter] = []
	for i: int in visuals.glow_count():
		if visuals.nozzle_light(i) != null:
			lights.append(visuals.nozzle_light(i))
	output = null
	_settle(visuals)
	for emitter: LightEmitter in lights:
		assert_eq(emitter.energy, 0.0, "dark at idle")
	output = _full_output(1.0)
	_settle(visuals)
	for emitter: LightEmitter in lights:
		assert_almost_eq(emitter.energy, EmitterCurves.NOZZLE_PEAK_ENERGY, 1e-3, "full at full thrust")
	output = _full_output(0.5)
	_settle(visuals)
	for emitter: LightEmitter in lights:
		assert_almost_eq(emitter.energy, 0.5 * EmitterCurves.NOZZLE_PEAK_ENERGY, 1e-3, "half at half thrust")


func test_the_light_is_the_plumes_colour_out_along_the_exhaust_and_the_players_own() -> void:
	var visuals: ThrusterVisuals = main.thrusters
	visuals.setup(main.ship.get_layout(), _source)
	output = _full_output(1.0)
	_settle(visuals)
	await get_tree().process_frame
	rig.update(_camera_position())
	var checked: int = 0
	for i: int in visuals.glow_count():
		var emitter: LightEmitter = visuals.nozzle_light(i)
		if emitter == null:
			continue
		checked += 1
		var plume: Node3D = visuals.glow(i)
		assert_eq(emitter.color, EmitterCurves.light_color(main.ship.spec.engine_glow_color))
		assert_eq(emitter.priority, LightEmitter.PRIORITY_PLAYER_OWN, "the player's nozzles outrank the rest")
		assert_almost_eq(emitter.omni_range, EmitterCurves.NOZZLE_RANGE_M, 1e-6)
		var pose: Transform3D = plume.get_global_transform_interpolated()
		assert_lt(emitter.position.distance_to(pose.origin + pose.basis.y * EmitterCurves.NOZZLE_OFFSET_M), 1e-3,
				"1.5 m out along the exhaust")
	assert_gt(checked, 0)


func test_a_raiders_nozzle_lights_are_ordinary_priority() -> void:
	DebugConsole.registry.execute("spawn raider 300")
	var raider: Combatant = main.ships.alive(ShipPool.DEFAULT_TYPE)[0]
	assert_gt(raider.thrusters.light_count(), 0, "raiders too")
	for i: int in raider.thrusters.glow_count():
		if raider.thrusters.nozzle_light(i) != null:
			assert_eq(raider.thrusters.nozzle_light(i).priority, LightEmitter.PRIORITY_NOZZLE)


func test_a_nozzle_light_survives_a_rebase() -> void:
	var visuals: ThrusterVisuals = main.thrusters
	visuals.setup(main.ship.get_layout(), _source)
	output = _full_output(1.0)
	_settle(visuals)
	main.world.rebase(Vector3(40.0, -10.0, 25.0))
	await get_tree().process_frame
	rig.update(_camera_position())
	var emitter: LightEmitter = null
	for i: int in visuals.glow_count():
		emitter = emitter if emitter != null else visuals.nozzle_light(i)
	var plume: Node3D = visuals.glow(0)
	var pose: Transform3D = plume.get_global_transform_interpolated()
	assert_lt(emitter.position.distance_to(pose.origin + pose.basis.y * EmitterCurves.NOZZLE_OFFSET_M), 1e-3,
			"still on the nozzle after the world moved")
	assert_true(rig.picked().has(emitter))


# --- muzzle flashes -------------------------------------------------------------------------------------------------


func _fire_once() -> void:
	var cmd := CombatCommand.new()
	cmd.fire = true
	main.cannon.set_combat_command(cmd)
	main.cannon.step(SimClock.now() + 10.0)
	cmd.fire = false


func _flash_of(index: int) -> MuzzleFlash:
	return main.ship.get_muzzles()[index].get_node("MuzzleFlash") as MuzzleFlash


func test_a_shot_adds_a_flash_light_for_sixty_milliseconds() -> void:
	var before: int = rig.candidate_count()
	_fire_once()
	assert_eq(rig.candidate_count(), before + 1, "the shot's flash joins the competition")
	var shot: MuzzleFlash = null
	for i: int in main.ship.get_muzzles().size():
		if _flash_of(i).is_active():
			shot = _flash_of(i)
	assert_not_null(shot)
	var emitter: LightEmitter = shot.light_emitter()
	assert_eq(emitter.priority, LightEmitter.PRIORITY_MUZZLE_FLASH)
	assert_gt(emitter.energy, 0.0)
	shot.advance(0.05)
	assert_gt(emitter.energy, 0.0, "still on at 50 ms")
	assert_eq(rig.candidate_count(), before + 1)
	shot.advance(0.011)
	assert_eq(emitter.energy, 0.0, "out at 60 ms")
	assert_eq(rig.candidate_count(), before, "and out of the competition")
	assert_eq(_lights(main).size(), 8, "no node for it")


func test_the_flash_light_sits_ahead_of_the_muzzle_and_is_picked() -> void:
	_fire_once()
	rig.update(_camera_position())
	var found: bool = false
	for emitter: LightEmitter in rig.picked():
		if emitter != null and emitter.priority == LightEmitter.PRIORITY_MUZZLE_FLASH:
			found = true
			var nearest: float = INF
			for muzzle: Node3D in main.ship.get_muzzles():
				nearest = minf(nearest, emitter.position.distance_to(muzzle.get_global_transform_interpolated() * Vector3(0.0, 0.0, -EmitterCurves.FLASH_OFFSET_M)))
			assert_lt(nearest, 1e-3)
	assert_true(found, "the shot's flash holds a slot")


func test_shots_reuse_one_record_and_never_pile_up() -> void:
	var emitters: Dictionary = {}
	for i: int in main.ship.get_muzzles().size():
		emitters[_flash_of(i).light_emitter()] = true
	var before: int = rig.candidate_count()
	for shot: int in 6:
		for i: int in main.ship.get_muzzles().size():
			_flash_of(i).trigger()
			_flash_of(i).trigger()  # a restart must not enter twice
	assert_eq(rig.candidate_count(), before + main.ship.get_muzzles().size())
	for i: int in main.ship.get_muzzles().size():
		assert_true(emitters.has(_flash_of(i).light_emitter()), "the same record every time")
		_flash_of(i).advance(1.0)
	assert_eq(rig.candidate_count(), before)


# --- explosions -----------------------------------------------------------------------------------------------------


func _explode(at: Vector3) -> Explosion:
	var explosion := Explosion.create(6.0, Vector3.ZERO)
	main.world.add_child(explosion)
	explosion.global_position = at
	return explosion


func test_an_explosions_light_goes_through_the_picker_on_its_curve() -> void:
	var baseline: int = rig.candidate_count()
	var explosion: Explosion = _explode(main.ship.global_position + Vector3(0.0, 0.0, 30.0))
	assert_eq(rig.candidate_count(), baseline + 1)
	explosion.advance(Explosion.LIGHT_S / 3.0)
	rig.update(_camera_position())
	assert_true(rig.picked().has(explosion.emitter))
	assert_eq(explosion.emitter.priority, LightEmitter.PRIORITY_EXPLOSION)
	assert_almost_eq(explosion.emitter.energy, 8.0, 1e-4)
	assert_almost_eq(explosion.emitter.omni_range, 24.0, 1e-6, "4 x radius")
	assert_eq(_lights(main).size(), 8, "the rig's eight, and no light of the explosion's own")
	explosion.advance(Explosion.LIGHT_S)
	assert_eq(explosion.emitter.energy, 0.0)
	assert_eq(rig.candidate_count(), baseline, "out of the competition when the light is over")


func test_a_freed_explosion_leaves_the_competition() -> void:
	var baseline: int = rig.candidate_count()
	var explosion: Explosion = _explode(Vector3(0.0, 0.0, -50.0))
	explosion.advance(0.05)
	assert_eq(rig.candidate_count(), baseline + 1)
	explosion.free()
	rig.update(_camera_position())
	assert_eq(rig.candidate_count(), baseline)


func test_an_explosions_light_survives_a_rebase() -> void:
	var explosion: Explosion = _explode(main.ship.global_position + Vector3(20.0, 0.0, 20.0))
	explosion.advance(Explosion.LIGHT_S / 3.0)
	main.world.rebase(Vector3(300.0, 0.0, -80.0))
	rig.update(_camera_position())
	var slot: int = rig.picked().find(explosion.emitter)
	assert_gte(slot, 0, "still picked")
	var light: Light3D = rig.slots()[slot + 1]
	assert_lt(light.global_position.distance_to(explosion.global_position), 1e-3, "where the explosion is now")


# --- pooled ships ---------------------------------------------------------------------------------------------------


func test_a_pooled_ship_has_lights_only_while_it_is_in_play() -> void:
	var baseline: int = rig.candidate_count()
	DebugConsole.registry.execute("spawn raider 300")
	await get_tree().process_frame
	await get_tree().process_frame
	var raider: Combatant = main.ships.alive(ShipPool.DEFAULT_TYPE)[0]
	var raider_lights: int = raider.thrusters.light_count()
	assert_gt(raider_lights, 0)
	assert_eq(rig.candidate_count(), baseline + raider_lights)
	# A shot in flight when the ship is parked must go too.
	var cmd := CombatCommand.new()
	cmd.fire = true
	raider.cannon.set_combat_command(cmd)
	raider.cannon.step(SimClock.now() + 10.0)
	assert_eq(rig.candidate_count(), baseline + raider_lights + 1)
	main.ships.release(raider)
	assert_eq(rig.candidate_count(), baseline, "parked: no nozzle and no flash is a candidate")
	await get_tree().process_frame
	assert_eq(rig.candidate_count(), baseline)
	for round: int in 2:
		main.ships.acquire("RAIDER X", main.world.to_universe(main.ship.global_position + Vector3(0.0, 0.0, -300.0)))
		await get_tree().process_frame
		await get_tree().process_frame
		assert_eq(rig.candidate_count(), baseline + raider_lights, "back once, not twice (round %d)" % round)
		main.ships.release(main.ships.alive(ShipPool.DEFAULT_TYPE)[0])
		assert_eq(rig.candidate_count(), baseline)


func test_a_ship_that_is_freed_leaves_nothing_behind() -> void:
	var baseline: int = rig.candidate_count()
	var made: Combatant = ShipAssembly.build(load(RAIDER_SPEC) as ShipSpec, main.world, main.projectiles, {})
	main.world.spawn(made.ship, main.world.to_universe(Vector3(0.0, 400.0, 0.0)))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(rig.candidate_count(), baseline + made.thrusters.light_count())
	made.ship.free()
	rig.update(_camera_position())
	assert_eq(rig.candidate_count(), baseline)


# --- a fight --------------------------------------------------------------------------------------------------------


func test_in_a_sandbox_fight_at_most_eight_lights_shine_and_the_players_nozzles_stay_picked() -> void:
	assert_true(DebugConsole.registry.execute("wave start 1")[0].ok)
	source.hold(InputAdapter.MAIN_RIGHT, 1.0)
	source.hold(InputAdapter.FIRE)
	var most_candidates: int = 0
	var own_lit_ticks: int = 0
	var flash_ticks: int = 0
	var cost_total_us: int = 0
	for tick: int in FIGHT_TICKS:
		await get_tree().physics_frame
		await get_tree().process_frame
		rig.update(_camera_position())
		assert_lte(_shining(), 8, "tick %d" % tick)
		assert_eq(_lights(main).size(), 8, "no other Light3D, tick %d" % tick)
		most_candidates = maxi(most_candidates, rig.candidate_count())
		cost_total_us += int(DebugConsole.registry.read("lights.cost_us")["value"])
		var own: Array[LightEmitter] = []
		for i: int in main.thrusters.glow_count():
			var emitter: LightEmitter = main.thrusters.nozzle_light(i)
			if emitter != null and emitter.energy > 0.0:
				own.append(emitter)
		if not own.is_empty():
			own_lit_ticks += 1
			for emitter: LightEmitter in own:
				assert_true(rig.picked().has(emitter), "the player's nozzle holds a slot, tick %d" % tick)
		for picked: LightEmitter in rig.picked():
			flash_ticks += 1 if picked != null and picked.priority == LightEmitter.PRIORITY_MUZZLE_FLASH else 0
	assert_gt(own_lit_ticks, FIGHT_TICKS / 2, "the player's engines fired through the fight")
	assert_gt(flash_ticks, 0, "shots were lit")
	gut.p("sandbox fight: %d ticks, most candidates %d, own nozzles lit %d ticks, flash picked %d slot-ticks, picker cost mean %d us" % [
			FIGHT_TICKS, most_candidates, own_lit_ticks, flash_ticks, cost_total_us / FIGHT_TICKS])
