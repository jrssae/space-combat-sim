extends GutTest
## A capital carrier's hangar decisions (M10-T17, D12.10, Q73; Q25 to Q30's recovery): its options by hull, its wings, when the
## next one goes, when its craft come home, and where they sit in its bays (`HangarRules`, `BayBerths`, `BayElevator`).


func _bay(name: String, extra: Dictionary) -> Dictionary:
	var bay: Dictionary = {"name": name, "kind": "bay", "position": [0.0, 0.0, -400.0], "forward": [0.0, 0.0, -1.0],
			"up": [0.0, 1.0, 0.0], "exit": [0.0, 0.0, -470.0], "mouth_m": [62.0, 27.0], "depth_m": 140.0,
			"craft": "starfury_ally", "capacity": 24}
	return bay.merged(extra, true)


func test_the_hulls_wings_are_data() -> void:
	assert_eq(HangarRules.options(&"ea_nova")["wings"], [12, 12], "the Nova launches two wings of 12 (Q73)")
	assert_eq(HangarRules.options(&"ea_omega")["wings"], [8, 8, 8, 8], "the Omega four wings of 8 (the maintainer, 2026-11-26)")
	assert_eq(HangarRules.options(&"ea_hyperion")["wings"], [6], "the Hyperion its 6")
	var nova: Dictionary = HangarRules.options(&"ea_nova")
	for key: String in HangarRules.DEFAULTS:
		assert_true(nova.has(key), "every option is filled in: %s" % key)
	assert_eq(float(CapitalBrainSpec.tuning()[12]), 15000.0, "a carrier counts hostiles within 15 km (D12.10)")


func test_a_wing_takes_its_share_and_the_last_the_rest() -> void:
	assert_eq(HangarRules.wing_size([12, 12], 0, 24), 12)
	assert_eq(HangarRules.wing_size([12, 12], 1, 15), 15, "the last wing takes whatever came back aboard too")
	assert_eq(HangarRules.wing_size([12, 12], 0, 5), 5, "no more than are aboard")
	assert_eq(HangarRules.wing_size([12, 12], 2, 10), 0, "every wing has gone")
	assert_eq(HangarRules.wing_size([32], 0, 32), 32)


func test_the_first_wing_goes_on_a_threat_and_the_next_as_it_grows_or_takes_losses() -> void:
	var o: Dictionary = HangarRules.options(&"ea_nova")
	assert_false(HangarRules.first_wing_due(0.0, 0), "nothing within reach")
	assert_true(HangarRules.first_wing_due(1.0, 0), "a single hostile within 15 km")
	assert_false(HangarRules.first_wing_due(5.0, 1), "the first has gone")
	assert_eq(HangarRules.threat(4, 1, float(o["warship_weight"])), 4.0 + float(o["warship_weight"]), "a warship weighs as several")
	assert_false(HangarRules.next_wing_due(6.0, 6.0, 12, 0, o), "the same threat, no losses: the first wing copes")
	assert_true(HangarRules.next_wing_due(9.0, 6.0, 12, 0, o), "the threat grew by half")
	assert_true(HangarRules.next_wing_due(6.0, 6.0, 12, 3, o), "a quarter of the first wing lost")
	assert_false(HangarRules.next_wing_due(6.0, 6.0, 12, 2, o))
	assert_false(HangarRules.next_wing_due(50.0, 6.0, 0, 0, o), "none out yet")


func test_craft_come_home_when_the_fight_is_over_badly_hurt_or_before_a_jump() -> void:
	var o: Dictionary = HangarRules.options(&"ea_omega")
	assert_false(HangarRules.fight_over(float(o["calm_s"]) - 1.0, o))
	assert_true(HangarRules.fight_over(float(o["calm_s"]), o), "nothing hostile within reach for a while")
	assert_true(HangarRules.goes_home(0.15, o), "under a fifth of its hull")
	assert_false(HangarRules.goes_home(0.5, o))
	assert_false(HangarRules.may_leave(3, 10.0, o), "a jump waits for its craft")
	assert_true(HangarRules.may_leave(0, 1.0, o), "everyone aboard")
	assert_true(HangarRules.may_leave(3, float(o["wait_s"]), o), "time up: the rest are left (Q27)")


func test_wings_take_their_factions_callsigns_in_turn() -> void:
	assert_eq(HangarRules.callsign(&"earth_alliance", 0), "Delta")
	assert_eq(HangarRules.callsign(&"earth_alliance", 1), "Echo")
	assert_eq(HangarRules.callsign(&"earth_alliance", 6), "Delta2", "round again with a number")
	assert_eq(Livery.parse_name("Delta 3"), ["Delta", 3], "a Starfury wears its wing's livery")
	assert_false(HangarRules.callsign(&"narn", 0).is_empty(), "a faction with none takes the default")


func test_a_lift_bay_has_two_rows_of_three_on_the_lift() -> void:
	var lift := _bay("bay_fore", {"elevator": [0.0, -9.0, -420.0], "elevator_travel_m": 30.0, "recovers": true})
	var c: CarrierCradles = BayBerths.of({"bays": [lift]}, HangarRules.options(&"ea_nova"))
	assert_eq(c.count(), 6, "two rows of three abreast on the lift: six craft a trip")
	for i: int in c.count():
		var front: bool = i < 3
		var run_in: float = 50.0 + (-7.0 if front else 7.0)  # the rows 14 m apart round the lift's point
		assert_almost_eq(c.positions[i].y, -9.0, 1e-4, "on the floor, a third of the mouth under the exit")
		assert_almost_eq(c.positions[i].z, -470.0 + run_in, 1e-4, "on the lift, %s row" % ("front" if front else "back"))
		assert_almost_eq(c.lift_m[i], 30.0, 1e-4)
		assert_true(c.out_axes[i].is_equal_approx(Vector3.FORWARD), "out of the mouth")
		assert_true((-c.bases[i].z).is_equal_approx(Vector3.FORWARD), "nose out")
		assert_almost_eq(c.launch_m[i], run_in + 40.0, 1e-3, "from the lift past the mouth")
		assert_almost_eq(c.approach_m[i], run_in + 60.0, 1e-3, "and back in from outside it")
	assert_almost_eq(c.positions[2].x - c.positions[0].x, 40.0, 1e-3, "20 m apart")


func test_a_big_hall_launches_from_lanes_at_its_back_and_single_bays_from_mid_hall() -> void:
	var c: CarrierCradles = BayBerths.of({"bays": [_bay("bay_fore", {"capacity": 32})]}, HangarRules.options(&"ea_omega"))
	assert_eq(c.count(), 3)
	assert_almost_eq(c.positions[0].z, -470.0 + 140.0 - BayBerths.BACK_GAP_M, 1e-3, "near the back wall")
	var single := _bay("bay_fury_1_r", {"forward": [1.0, 0.0, 0.0], "exit": [16.5, 39.3, 73.0], "mouth_m": [21.9, 12.1],
			"depth_m": 15.5, "capacity": 1})
	var shuttle := _bay("bay_shuttle", {"forward": [0.0, 0.0, 1.0], "exit": [0.0, 84.3, -14.0], "mouth_m": [28.0, 24.0],
			"depth_m": 42.0, "craft": "ea_shuttle", "capacity": 2, "berths": 1, "poses": {"ea_shuttle": {}, "ea_atmo_shuttle": {}}})
	var h: CarrierCradles = BayBerths.of({"bays": [single, shuttle, {"name": "hangar_door", "kind": "door"}]}, HangarRules.options(&"ea_hyperion"))
	assert_eq(h.count(), 2, "one each: a single-fury bay, a one-berth shuttle bay")
	assert_almost_eq(h.positions[0].x, 16.5 - 7.75, 1e-3, "mid-hall")
	assert_almost_eq(h.positions[0].y, 39.3 - 12.1 / 3.0, 1e-3)
	assert_true(h.takes(1, &"ea_atmo_shuttle") and h.takes(1, &"ea_shuttle") and not h.takes(1, &"starfury_ally"),
			"the shuttle bay takes the Kestrel too (its poses)")
	assert_true(h.takes(0, &"starfury_ally") and not h.takes(0, &"ea_shuttle"))


func test_returning_craft_share_a_bays_lane_and_wait_their_turn() -> void:
	var c: CarrierCradles = BayBerths.of({"bays": [_bay("bay_fore", {"capacity": 32})]}, HangarRules.options(&"ea_omega"))
	c.set_state(0, CarrierCradles.State.BUSY)
	c.set_state(1, CarrierCradles.State.BUSY)
	c.set_state(2, CarrierCradles.State.BUSY)
	assert_eq(c.nearest_free(Vector3(0.0, 0.0, -600.0)), -1, "every lane in use")
	assert_true(c.nearest_taking(Vector3(0.0, 0.0, -600.0), &"starfury_ally") >= 0, "a returning craft still has a lane to wait at")
	assert_eq(c.nearest_taking(Vector3.ZERO, &"ea_shuttle"), -1, "but not one that does not take it")


func test_a_lift_sinks_for_a_trip_rises_with_it_and_takes_craft_down() -> void:
	var lift := BayElevator.new()
	assert_true(lift.is_free() and is_equal_approx(lift.height(), 1.0), "flush with the floor")
	assert_true(lift.fetch())
	assert_false(lift.fetch(), "busy")
	var ended: int = -1
	var t: float = 0.0
	while ended != BayElevator.State.DOWN:
		ended = lift.advance(0.1)
		t += 0.1
	assert_almost_eq(t, lift.travel_s, 0.11)
	assert_almost_eq(lift.height(), 0.0, 1e-6)
	assert_true(lift.rise())
	lift.advance(0.5 * lift.travel_s)
	assert_almost_eq(lift.height(), 0.5, 1e-4, "eased as the kernel's lift")
	lift.advance(0.5 * lift.travel_s)
	assert_true(lift.is_free() and lift.trips_up == 1)
	assert_true(lift.lower())
	lift.advance(lift.travel_s)
	assert_eq(lift.state, BayElevator.State.RETURNING, "craft off at the deck, it comes back up empty")
	lift.advance(lift.travel_s)
	assert_true(lift.is_free() and lift.trips_down == 1)


func test_a_scenario_capital_may_carry_its_loadouts_craft() -> void:
	var read: Variant = ScenarioLoader._capitals([{"type": "ea_nova", "hangar": false}, {"type": "ea_omega"}], "test")
	assert_true(read is Array, str(read))
	if read is Array:
		assert_false(bool((read as Array)[0]["hangar"]), "a parked line-up ship opts out")
		assert_true(bool((read as Array)[1]["hangar"]), "full by default")
	var showcase: Dictionary = ScenarioLoader.load("res://data/scenarios/ship_showcase.json")
	var carriers: int = 0
	for entry: Dictionary in showcase.get("capitals", []):
		if not bool(entry["standin"]) and String(entry["type"]).begins_with("ea_") and String(entry["type"]) != "ea_asimov":
			carriers += 1
			assert_false(bool(entry["hangar"]), "the showcase's parked %s launches nothing" % entry["type"])
	assert_gt(carriers, 0, "the line-up has its carriers")
