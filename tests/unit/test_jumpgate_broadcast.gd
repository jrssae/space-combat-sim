extends GutTest
## The jumpgate prop (M6-T14, AC8): its beacon is heard 1 000 km out as a nav buoy's is, it locks on as a prop, and its vortex
## and points come from the generated hardpoints.

var _holder: Node3D


func before_each() -> void:
	_holder = Node3D.new()
	add_child_autofree(_holder)


func _gate() -> Jumpgate:
	var gate: Jumpgate = Jumpgate.create("JUMPGATE")
	_holder.add_child(gate)
	return gate


func test_the_gate_broadcasts_to_1000_km() -> void:
	var gate: Jumpgate = _gate()
	assert_eq(gate.targetable.broadcast_range_m, 1.0e6)
	assert_eq(gate.targetable.broadcast_range_m, NavBuoy.BROADCAST_RANGE_M, "as far as a nav beacon")
	assert_true(Targetable.broadcasters().has(gate.targetable), "listed with the broadcasters the AI hears")
	assert_eq(gate.targetable.kind, Targetable.Kind.PROP)
	assert_eq(gate.targetable.display_name, "JUMPGATE")


func test_the_player_can_select_it_from_999_km_but_not_1001() -> void:
	var gate: Jumpgate = _gate()
	var system := TargetingSystem.new()
	system.set_candidates([gate.targetable.to_target_info()] as Array[TargetInfo])
	assert_eq(system.in_range(gate.global_position + Vector3(0.0, 0.0, 999000.0)).size(), 1)
	assert_eq(system.in_range(gate.global_position + Vector3(0.0, 0.0, 1001000.0)).size(), 0)


func test_its_points_and_vortex_come_from_the_hardpoints() -> void:
	var gate: Jumpgate = _gate()
	assert_almost_eq(gate.radius_m, 720.0, 0.1)
	assert_eq(gate.arrival_forward, Vector3.FORWARD, "arrivals leave along -Z")
	assert_eq(gate.departure_forward, Vector3.BACK, "departures fly in along +Z")
	assert_lt(gate.departure_point.z, -1000.0, "the departure point is well in front")
	assert_eq(gate.vortex.tips.size(), 4, "one glow per inner tip")
	assert_gt(gate.collision_body.get_child_count(), 40, "a box per truss and fin")
	assert_false(gate.vortex.is_active())
	assert_true(gate.vortex.open(JumpVortex.Direction.ARRIVAL))
	assert_false(gate.vortex.open(JumpVortex.Direction.DEPARTURE), "one direction per opening")
	gate.vortex.advance(VortexTiming.OPEN_AT_S)
	assert_true(gate.vortex.is_open_for(JumpVortex.Direction.ARRIVAL))
	gate.vortex.update_visuals()
	assert_true(gate.vortex.funnel.visible)
	gate.vortex.close()
	gate.vortex.advance(VortexTiming.CLOSE_S + 0.01)
	assert_false(gate.vortex.is_active(), "gone once closed")
	assert_false(gate.vortex.funnel.visible)
