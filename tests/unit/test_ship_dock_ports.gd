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
