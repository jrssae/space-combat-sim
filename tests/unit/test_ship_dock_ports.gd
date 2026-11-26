extends GutTest
## A hull's docking collars and where a craft lies mated on one (M10-T53, Q84): `ShipDockPorts`.

const HATCH: Dictionary = {"name": "stern_hatch", "position": [0.0, -0.5, 13.8], "out": [0.0, 0.0, 1.0], "up": [0.0, 1.0, 0.0]}


func _hull() -> Dictionary:
	return {"docking_ports": [
		{"name": "collar_r", "position": [56.0, -43.0, -171.0], "out": [0.0, 0.0, -1.0], "up": [0.0, 1.0, 0.0]},
		{"name": "collar_l", "position": [-56.0, -43.0, -171.0], "out": [0.0, 0.0, -2.0], "up": [0.0, 1.0, 0.3]},
		{"name": "side", "position": [100.0, 0.0, 0.0], "out": [1.0, 0.0, 0.0], "up": [0.0, 1.0, 0.0]},
		{"name": "broken", "position": [1.0, 2.0], "out": [0.0, 0.0, -1.0]},
		"not a port"]}


func test_a_hulls_collars_are_read_from_its_hardpoints() -> void:
	var ports: ShipDockPorts = ShipDockPorts.of(_hull())
	assert_eq(ports.count(), 3, "an entry that is not a port is skipped")
	assert_eq(Array(ports.names), ["collar_r", "collar_l", "side"])
	assert_eq(ports.index_of("side"), 2)
	assert_eq(ports.index_of("nowhere"), -1)
	assert_almost_eq(ports.outs[1], Vector3.FORWARD, Vector3.ONE * 1e-6, "directions are made unit")
	assert_almost_eq(ports.ups[1], Vector3.UP, Vector3.ONE * 1e-6, "and the up square to the way out")
	assert_eq(ShipDockPorts.of({}).count(), 0, "a hull without collars has none")
	assert_eq(ShipDockPorts.of({"docking_ports": "no"}).count(), 0)


func test_a_craft_without_a_lock_has_no_port() -> void:
	assert_true(ShipDockPorts.craft_port({"docking_ports": []}).is_empty(), "the Kestrel only lands in bays (Q93)")
	assert_true(ShipDockPorts.craft_port({}).is_empty())
	var hatch: Dictionary = ShipDockPorts.craft_port({"docking_ports": [HATCH]})
	assert_eq(hatch["position"], Vector3(0.0, -0.5, 13.8))
	assert_eq(hatch["out"], Vector3.BACK)


func test_a_shuttle_mates_by_its_stern_with_its_nose_out() -> void:
	var ports: ShipDockPorts = ShipDockPorts.of(_hull())
	var hatch: Dictionary = ShipDockPorts.port_of(HATCH)
	var mated: Transform3D = ports.mate(0, hatch, 0.3)
	assert_almost_eq(-mated.basis.z, Vector3.FORWARD, Vector3.ONE * 1e-6, "its nose along the collar's way out")
	assert_almost_eq(mated.basis.y, Vector3.UP, Vector3.ONE * 1e-6, "its top along the collar's up")
	assert_almost_eq(mated * (hatch["position"] as Vector3), Vector3(56.0, -43.0, -171.3), Vector3.ONE * 1e-5,
			"its hatch on the collar's axis, the gap out of it")
	assert_almost_eq(mated.basis.determinant(), 1.0, 1e-6, "a rotation, not a mirror")


func test_a_collar_on_the_flank_turns_the_craft_to_it() -> void:
	var ports: ShipDockPorts = ShipDockPorts.of(_hull())
	var hatch: Dictionary = ShipDockPorts.port_of(HATCH)
	var mated: Transform3D = ports.mate(2, hatch, 0.0)
	assert_almost_eq(-mated.basis.z, Vector3.RIGHT, Vector3.ONE * 1e-6, "nose away from the hull")
	assert_almost_eq(mated.basis * (hatch["out"] as Vector3), Vector3.LEFT, Vector3.ONE * 1e-6, "its lock faces the collar")
	assert_almost_eq(mated * (hatch["position"] as Vector3), Vector3(100.0, 0.0, 0.0), Vector3.ONE * 1e-5)


func test_the_lane_runs_out_of_the_collar_along_its_axis() -> void:
	var ports: ShipDockPorts = ShipDockPorts.of(_hull())
	var hatch: Dictionary = ShipDockPorts.port_of(HATCH)
	var start: Vector3 = ports.lane_point(0, hatch, 0.3, 220.0)
	assert_almost_eq(start - ports.mate(0, hatch, 0.3).origin, Vector3(0.0, 0.0, -220.0), Vector3.ONE * 1e-5)


func test_the_nearest_free_collar_is_picked() -> void:
	var ports: ShipDockPorts = ShipDockPorts.of(_hull())
	var near_left := Vector3(-80.0, -40.0, -400.0)
	assert_eq(ports.nearest_free(near_left, [false, false, false]), 1)
	assert_eq(ports.nearest_free(near_left, [false, true, false]), 0, "a taken collar is passed over")
	assert_eq(ports.nearest_free(near_left, [true, true, true]), -1, "none free")


# --- a visitors' bay's berths (stage 2: the Asimov's shuttle bay) ------------------------------------------------------------

func _bay_hull() -> Dictionary:
	var hull: Dictionary = _hull()
	hull["bays"] = [
		{"name": "bay_shuttle", "kind": "bay", "position": [0.0, -20.0, -80.0], "forward": [0.0, 0.0, -1.0], "up": [0.0, 1.0, 0.0],
			"exit": [0.0, -24.0, -116.0], "mouth_m": [70.0, 24.0], "depth_m": 70.0, "craft": "ea_shuttle", "capacity": 2, "berths": 2,
			"berth_craft": ["ea_shuttle", "ea_atmo_shuttle"], "berth_fan_deg": [-20.0, 20.0], "berth_run_m": [50.0, 54.0], "visitors": true},
		{"name": "bay_fury", "kind": "bay", "position": [0.0, 30.0, 0.0], "forward": [1.0, 0.0, 0.0], "up": [0.0, 1.0, 0.0],
			"exit": [20.0, 30.0, 0.0], "mouth_m": [20.0, 12.0], "depth_m": 16.0, "craft": "starfury_ally", "capacity": 1}]
	return hull


func test_a_fanned_bay_gives_each_berth_its_own_lane_and_craft() -> void:
	var berths: CarrierCradles = BayBerths.of(_bay_hull(), HangarRules.DEFAULTS)
	assert_eq(Array(berths.names), ["bay_shuttle_0", "bay_shuttle_1", "bay_fury_0"])
	assert_eq(Array(berths.crafts[0]), ["ea_shuttle"], "a berth takes its own craft only")
	assert_eq(Array(berths.crafts[1]), ["ea_atmo_shuttle"])
	var sill := Vector3(0.0, -32.0, -116.0)  # the middle of the mouth, on the deck: a third of the hall's height under the exit
	for i: int in 2:
		var turn: float = deg_to_rad([-20.0, 20.0][i])
		var way := Vector3(sin(turn), 0.0, -cos(turn))
		assert_almost_eq(berths.out_axes[i], way, Vector3.ONE * 1e-5, "its way out, turned to starboard of the bay's")
		assert_almost_eq(berths.positions[i], sill - way * [50.0, 54.0][i], Vector3.ONE * 1e-4, "its lane runs through the sill's middle")
		assert_almost_eq(-berths.bases[i].z, way, Vector3.ONE * 1e-5, "a craft rests nose out along its lane")
	assert_gt(berths.positions[0].x, 15.0, "the crew shuttle's berth to starboard")
	assert_lt(berths.positions[1].x, -15.0, "the Kestrel's to port")
	assert_eq(Array(BayBerths.crafts_of(_bay_hull()["bays"][0])), ["ea_shuttle", "ea_atmo_shuttle"], "the bay takes both")


func test_a_visitors_bay_adds_its_berths_after_the_collars() -> void:
	var hull: Dictionary = _bay_hull()
	var ports: ShipDockPorts = ShipDockPorts.of(hull)
	ports.add_berths(hull, BayBerths.of(hull, HangarRules.DEFAULTS))
	assert_eq([ports.count(), ports.collar_count(), ports.bay_count()], [5, 3, 2], "the fury bay takes no visitors")
	assert_eq(Array(ports.names).slice(3), ["bay_shuttle_0", "bay_shuttle_1"])
	assert_eq([ports.is_berth(0), ports.is_berth(3)], [false, true])
	assert_eq([ports.cradles[0], ports.cradles[3], ports.cradles[4]], [-1, 0, 1], "a berth is the hangar's cradle")
	assert_eq([ports.berth_for("ea_shuttle"), ports.berth_for("ea_atmo_shuttle"), ports.berth_for("starfury_ally")], [3, 4, -1])
	assert_true(ports.takes(0, "ea_shuttle", true), "a collar takes any craft with a lock")
	assert_false(ports.takes(0, "ea_atmo_shuttle", false), "and none without")
	assert_true(ports.takes(4, "ea_atmo_shuttle", false), "a berth takes its craft, lock or not")
	assert_false(ports.takes(4, "ea_shuttle", true))
	assert_almost_eq(ports.bay_mouth, Vector3(0.0, -20.0, -116.0), Vector3.ONE * 1e-4, "the middle of the hall's mouth")
	var rest := Vector3(0.0, -5.5, -5.6)
	var berthed: Transform3D = ports.mate(4, {"rest": rest})
	assert_almost_eq(-berthed.basis.z, ports.outs[4], Vector3.ONE * 1e-5, "nose out along its lane")
	assert_almost_eq(berthed * rest, ports.positions[4], Vector3.ONE * 1e-4, "its rest point on the deck")
	assert_almost_eq(ports.lane_point(4, {"rest": rest}, 0.3, 100.0), berthed.origin + ports.outs[4] * 100.0, Vector3.ONE * 1e-4)
