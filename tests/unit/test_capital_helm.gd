extends GutTest
## A capital's helm (M10-T07, Q51): a reaction hull with retros brakes on its retros with its bow held; one with no retros
## turns to burn against its motion and turns back once it has stopped; a gravitic hull pushes along any axis without turning.
## Turns are paced to what the hull's torque can stop.

const HARDPOINTS: Dictionary = {"center_of_mass": [0.0, 0.0, 0.0], "engines": [
	{"name": "r", "position": [20.0, 0.0, 150.0], "exhaust": [0.0, 0.0, 1.0]},
	{"name": "l", "position": [-20.0, 0.0, 150.0], "exhaust": [0.0, 0.0, 1.0]},
]}


func _helm(propulsion: StringName, retro: float, fraction: float = 0.0) -> CapitalHelm:
	var spec := ShipSpec.new()
	spec.mass = 1.0e7
	spec.inertia = Vector3(7.0e10, 7.0e10, 1.0e9)
	spec.pod_main_thrust = 1.0e7
	spec.pod_retro_thrust = retro
	spec.rcs_force_max = Vector3(1.0e6, 1.0e6, 0.0)
	spec.rcs_torque_max = Vector3(7.0e8, 7.0e8, 1.0e7)
	spec.rate_max = Vector3(4.0, 4.0, 3.0)
	spec.propulsion = propulsion
	spec.gravitic_fraction = fraction
	var layout: ThrusterLayout = CapitalPropulsion.layout(HARDPOINTS)
	var flown: ShipSpec = CapitalPropulsion.flight_spec(spec, CapitalPropulsion.main_count(layout))
	var helm: CapitalHelm = CapitalHelm.make(flown, layout)
	helm.heading = Vector3.FORWARD
	return helm


func test_with_retros_it_brakes_with_its_bow_held() -> void:
	var helm: CapitalHelm = _helm(CapitalPropulsion.REACTION, 5.0e6)
	helm.velocity = Vector3.ZERO
	var cmd: FlightCommand = helm.command(Basis.IDENTITY, Vector3(0.0, 0.0, -20.0))
	assert_false(helm.flipping)
	assert_gt(cmd.retro_left, 0.0, "the retros brake")
	assert_eq(cmd.retro_left, cmd.retro_right, "both sides together")
	assert_eq(cmd.main_left, 0.0)
	assert_almost_eq(cmd.rot.length(), 0.0, 1e-6, "the bow stays on its heading")


func test_without_retros_it_flips_burns_and_turns_back() -> void:
	var helm: CapitalHelm = _helm(CapitalPropulsion.REACTION, 0.0)
	helm.velocity = Vector3.ZERO
	var moving := Vector3(0.0, 0.0, -20.0)
	var cmd: FlightCommand = helm.command(Basis.IDENTITY, moving)
	assert_true(helm.flipping, "it must slow and has no retros")
	assert_eq(cmd.retro_left, 0.0, "nothing pushes aft")
	assert_eq(cmd.main_left, 0.0, "no burn while the bow points the wrong way")
	assert_gt(cmd.rot.length(), 0.1, "it turns")
	var turned := Basis(Vector3.UP, PI)  # the bow now points along its motion's reverse
	cmd = helm.command(turned, moving)
	assert_true(helm.flipping)
	assert_gt(cmd.main_left, 0.5, "turned round, it burns its mains against its motion")
	cmd = helm.command(turned, Vector3(0.0, 0.0, -0.2))
	assert_false(helm.flipping, "stopped, the flip is over")
	assert_eq(cmd.main_left, 0.0)
	assert_gt(cmd.rot.length(), 0.1, "and it turns back to its heading")


func test_a_small_slowing_does_not_start_a_flip() -> void:
	var helm: CapitalHelm = _helm(CapitalPropulsion.REACTION, 0.0)
	helm.velocity = Vector3(0.0, 0.0, -18.0)
	helm.command(Basis.IDENTITY, Vector3(0.0, 0.0, -20.0))
	assert_false(helm.flipping, "under %.0f m/s it coasts down rather than turning a 300 m hull" % CapitalHelm.FLIP_ENTER_MPS)


func test_a_gravitic_hull_pushes_along_any_axis_without_turning() -> void:
	var helm: CapitalHelm = _helm(CapitalPropulsion.GRAVITIC, 0.0, 0.5)
	assert_true(helm.is_gravitic())
	helm.velocity = Vector3(10.0, 0.0, 0.0)
	var cmd: FlightCommand = helm.command(Basis.IDENTITY, Vector3(0.0, 0.0, -20.0))
	assert_false(helm.flipping)
	assert_gt(cmd.retro_left, 0.0, "it brakes backward")
	assert_gt(cmd.strafe.x, 0.0, "and slides sideways")
	assert_almost_eq(cmd.rot.length(), 0.0, 1e-6, "with its bow held")


func test_a_turn_is_paced_to_what_the_torque_can_stop() -> void:
	var helm: CapitalHelm = _helm(CapitalPropulsion.REACTION, 5.0e6)
	helm.velocity = Vector3.ZERO
	var rate_max: Vector3 = helm.capability().rate_max_rad
	var alpha: float = helm.capability().alpha_max_rad.y
	for angle_deg: float in [2.0, 20.0, 90.0]:
		helm.heading = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(angle_deg))
		var cmd: FlightCommand = helm.command(Basis.IDENTITY, Vector3.ZERO)
		var asked: float = absf(cmd.rot.y) * rate_max.y
		var stoppable: float = sqrt(2.0 * alpha * deg_to_rad(angle_deg))
		assert_lt(asked, stoppable + 1e-6, "at %.0f deg it asks no faster a turn than it can stop from" % angle_deg)
		assert_gt(asked, 0.0)
