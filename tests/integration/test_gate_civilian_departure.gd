extends GutTest
## Civilians jump briskly (M8-T17, maintainer 2026-11-19): a run civilian leaving through the gate is flown in by the gate once it
## is in front of it, lined up on the axis and run in at the run-in's speed as far as its own mains take it, then swallowed past
## the threshold (where the hull's limits stop). A Skylark took 33 s from 3 km out to gone, slowing for the gate and off the axis.

var main: Main


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func after_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func test_a_skylark_lines_up_on_the_axis_and_runs_in_briskly() -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.scenario_seed = 5
	main.encounters = false
	main.encounter_pools_path = "res://data/encounters/free_flight.json"
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var gate: Jumpgate = main.gates.gate()
	if main.far_props.station == null or gate == null or not main.traffic.lanes_ready():
		pending("the station or the gate is not built here")
		return
	main.combatant.damageable.invulnerable = true
	var traffic: StationTraffic = main.traffic
	var length: float = traffic._run_length(traffic.plan.dock_in)
	var ends: float = minf(StationTraffic.RUN_END_M, length * 0.5)
	var skylark: Combatant = traffic._join_outbound(&"skylark_transport", (length - 7000.0 - ends) / maxf(length - 2.0 * ends, 1.0), {})
	assert_not_null(skylark)
	if skylark == null:
		return
	var ship: Ship = skylark.ship
	var accel: float = ShipCapability.from_spec(ship.spec, ship.get_layout()).a_main
	var departed: int = gate.departed
	var t: float = 0.0
	var from_3km: float = -1.0
	var off_axis_at_mouth: float = -1.0
	var fastest_before: float = 0.0
	var was_z: float = gate.local_of(ship.global_position).z
	while t < 120.0 and gate.departed == departed:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var local: Vector3 = gate.local_of(ship.global_position)
		if from_3km < 0.0 and ship.global_position.distance_to(gate.global_position) < 3000.0:
			from_3km = t
		if local.z < 0.0:
			fastest_before = maxf(fastest_before, (ship.linear_velocity - main.world.anchored_velocity()).length())
		if off_axis_at_mouth < 0.0 and was_z < 0.0 and local.z >= 0.0:
			off_axis_at_mouth = Vector2(local.x, local.y).length()
		was_z = local.z
	assert_eq(gate.departed, departed + 1, "it went through")
	assert_gt(from_3km, 0.0)
	gut.p("3 km out to gone in %.1f s, %.0f m off the axis at the mouth, %.0f m/s at most before it (mains %.2f m/s^2)" % [
			t - from_3km, off_axis_at_mouth, fastest_before, accel])
	assert_lt(t - from_3km, 28.0, "brisk: from 3 km out to gone well under the 33 s it took")
	assert_lt(off_axis_at_mouth, 200.0, "on the axis at the mouth")
	assert_lte(fastest_before, Jumpgate.AI_RUN_IN_MPS + 5.0, "no faster than the run-in before the threshold")
