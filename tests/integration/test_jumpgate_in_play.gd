extends GutTest
## The jumpgate in play (M6-T14, AC8) on the real main scene: the player targets the gate, X asks for the jump, the autopilot flies
## it out through the orange vortex and it comes back through the blue one with the controls returned; an AI ship sent by a
## mission comes out of the blue vortex and leaves through the orange one; an encounter's raiders come out of the gate when its
## pools file asks. Standard tier: each boots the scene and flies tens of seconds.

const DT: float = 1.0 / 60.0

var main: Main
var source: FakeInputSource
var gate: Jumpgate


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func after_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = false
	ContactScan.invalidate()


func _start(raiders: int = 0, allies: int = 0, pools_path: String = "") -> void:
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.raider_pool_size = raiders
	main.ally_pool_size = allies
	main.waves_auto_start = false
	main.encounter_pools_path = pools_path
	add_child_autofree(main)
	await _ticks(2)
	gate = main.gates.gate()


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


# The player `metres` in front of the gate on its axis, nose on it, at rest.
func _put_player_in_front(metres: float) -> void:
	var at: Vector3 = gate.global_transform * Vector3(0.0, 0.0, -metres)
	main.ship.reset_to(Transform3D(Basis.looking_at(gate.global_position - at, gate.global_basis.y), at))
	await _ticks(3)


func test_the_player_jumps_out_and_comes_back_through_the_blue_vortex() -> void:
	await _start()
	assert_not_null(gate, "free flight places the gate")
	assert_not_null(main.far_props.station, "free flight places the station's stand-in (M6-T09)")
	assert_almost_eq(gate.global_position.distance_to(main.far_props.station.global_position), 50000.0, 10.0,
			"on the station's rail, 50 km from it (M6-T09)")
	await _put_player_in_front(2600.0)
	assert_false(main.gates.jump_offered(), "not offered until the gate is targeted")
	assert_true(main.ship.targeting.select_id(gate.targetable.get_instance_id()))
	await _ticks(2)
	assert_true(main.gates.jump_offered())
	assert_eq(main.gates.prompt_line(), GateJumpPrompt.TEXT, "the HUD's prompt")
	source.hold(InputAdapter.AUTOTRACK)
	await _ticks(1)
	source.release(InputAdapter.AUTOTRACK)
	assert_true(main.gates.jump.is_active(), "X asked for the jump")
	assert_false(main.adapter.autotrack_on, "and did not switch auto-track on")
	assert_true(main.controls_locked())
	var saw_departure_open: bool = false
	var saw_hidden: bool = false
	var came_back_blue: bool = false
	var came_out_ahead: bool = false
	var shot_seen: bool = false
	var shrank_going: float = 1.0
	var shrank_coming: float = 1.0
	var transits: VortexTransits = VortexTransits.attach(main.world)
	var clearing_ticks: int = 0
	for i: int in 60 * 60:
		await _ticks(1)
		saw_departure_open = saw_departure_open or gate.vortex.is_open_for(JumpVortex.Direction.DEPARTURE)
		saw_hidden = saw_hidden or not main.ship.visible
		shot_seen = shot_seen or main.camera_rig.is_playing_shot()
		if main.gates.jump.state == GateJump.State.RUN_IN:
			shrank_going = minf(shrank_going, transits.scale_of(main.ship))
		if main.gates.jump.state == GateJump.State.CLEARING:
			clearing_ticks += 1
			shrank_coming = minf(shrank_coming, transits.scale_of(main.ship))
			if clearing_ticks == 1:
				came_back_blue = gate.vortex.is_open_for(JumpVortex.Direction.ARRIVAL)
				assert_gt(gate.local_of(main.ship.global_position).z, gate.fit.depth_m * 0.9,
						"it comes back out of the funnel's ring (M6-T22)")
			var local: Vector3 = gate.local_of(main.ship.global_position)
			came_out_ahead = came_out_ahead or (local.z < 0.0
					and main.ship.linear_velocity.dot(gate.global_basis * Vector3.FORWARD) > 100.0)
		if not main.gates.jump.is_active():
			break
	assert_eq(main.gates.jump.completed, 1, "the jump finished (%s)" % main.gates.jump.ended_why)
	assert_true(saw_departure_open, "it went in through the orange (departure) vortex")
	assert_true(saw_hidden, "out of sight while away")
	assert_true(came_back_blue, "it came back while the blue (arrival) vortex was open")
	assert_true(came_out_ahead, "flying out of the gate's front")
	assert_true(shot_seen, "the cinematic followed it")
	assert_lt(shrank_going, 0.5, "it shrank flying down the funnel to the ring")
	assert_lt(shrank_coming, 0.5, "and came out shrunk, growing")
	assert_eq(transits.scale_of(main.ship), 1.0, "whole at the end")
	assert_eq(gate.departed, 1)
	assert_eq(gate.arrived, 1)
	assert_true(main.ship.visible)
	assert_false(main.controls_locked(), "the controls are back")
	assert_false(main.camera_rig.is_playing_shot())


func test_an_ai_ship_arrives_through_the_gate_and_leaves_through_it() -> void:
	await _start(0, 2)
	await _put_player_in_front(6000.0)
	var stage := MissionStage.new()
	stage.setup(main, null)
	var parsed: Variant = ScenarioLoader.parse_spawn({"type": "starfury_ally", "name": "VISITOR", "anchor": "origin",
			"behaviour": {"type": "ai", "profile": "ally_starfury", "orders": "engage"}}, "spawn", &"local")
	assert_true(parsed is Dictionary, str(parsed))
	var entry: Dictionary = parsed
	entry["arrival"] = &"gate"
	assert_eq(stage.spawn_through_gate(entry), "VISITOR")
	assert_eq(main.ships.alive(&"starfury_ally").size(), 0, "not in play until the vortex is open")
	assert_eq(gate.vortex.direction_name(), &"arrival", "the blue vortex opens")
	var placed_while_open: bool = false
	for i: int in 8 * 60:
		await _ticks(1)
		if gate.arrived == 1:
			placed_while_open = gate.vortex.is_open_for(JumpVortex.Direction.ARRIVAL)
			break
	assert_true(placed_while_open, "it came out once the blue vortex was open")
	var visitor: Combatant = main.ships.alive(&"starfury_ally")[0] if not main.ships.alive(&"starfury_ally").is_empty() else null
	assert_not_null(visitor)
	if visitor == null:
		return
	var transits: VortexTransits = VortexTransits.of(main.world)
	if transits.is_passing(visitor.ship):
		assert_gt(gate.local_of(visitor.ship.global_position).z, gate.fit.depth_m * 0.9, "out of the funnel's ring (M6-T22)")
	else:
		# 6 km off it is under 2 px on screen: it comes out in place, with only the ring's flash (M6-T22).
		assert_eq(transits.arrivals_unseen, 1, "too small on screen to fly the funnel")
		assert_lt(gate.local_of(visitor.ship.global_position).distance_to(gate.arrival_point), 50.0, "at the arrival point")
	assert_true(stage.depart("VISITOR"))
	var saw_orange: bool = false
	for i: int in 90 * 60:
		await _ticks(1)
		saw_orange = saw_orange or gate.vortex.is_open_for(JumpVortex.Direction.DEPARTURE)
		if gate.departed == 1:
			break
	assert_eq(gate.departed, 1, "it went through")
	assert_true(saw_orange, "through the orange vortex")
	assert_eq(main.ships.alive(&"starfury_ally").size(), 0, "and left play, back to its pool")
	stage.teardown()


func test_an_encounter_raid_comes_out_of_the_gate_when_its_file_asks() -> void:  # via the gate (M6-T23)
	DebugConsole.flags.invulnerable = true
	await _start(0, 0, "res://tests/fixtures/encounters/gate_raids.json")
	await _put_player_in_front(6000.0)
	var director: EncounterDirector = main.encounter_director
	assert_not_null(director)
	director.enable()
	var e: EncounterEvent = director.take_forced(&"raid")
	assert_true(director.start(e))
	assert_eq(director.in_transit, e.count(), "the raiders wait for the vortex")
	assert_eq(gate.vortex.direction_name(), &"arrival")
	for i: int in 8 * 60:
		await _ticks(1)
		if director.in_transit == 0:
			break
	assert_eq(director.alive_of(&"raid"), e.count(), "every raider came through")
	assert_eq(director.gate_events, 1)
	assert_eq(CarrierJumps.attach(main.world).carriers_used, 0, "a raid through the gate needs no carrier (M6-T23)")
	assert_eq(director.jumps.opened, 0, "and opens no jump point")
	for c: Combatant in director.alive():
		assert_lt(gate.local_of(c.ship.global_position).length(), gate.fit.depth_m + 100.0,
				"%s came out of the gate's funnel" % c.display_name)
