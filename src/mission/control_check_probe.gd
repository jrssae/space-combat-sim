class_name ControlCheckProbe
extends RefCounted
## Reads what the control checks measure from the game (M8 D80): the player's ship, its camera, weapon, wing and menus, and the
## command `Main` sampled this tick. A thin adapter: `MissionRunner` calls it once per physics tick while a check is open.


## This tick's sample. With the player down only the command's events are filled, so nothing passes on a wreck.
static func sample(main: Main) -> ControlCheckSample:
	var out := ControlCheckSample.new()
	out.events = ControlCheckSample.events_of(main.adapter.last)
	var ship: Ship = main.ship
	if ship == null or not is_instance_valid(ship) or not main.player_alive:
		return out
	out.velocity = ship.linear_velocity - ship.rest_velocity()
	out.basis = ship.global_basis
	out.angular_velocity = ship.angular_velocity
	var wing: Wing = main.wings.player_wing()
	out.state = {
		ControlCheckSample.ASSIST: ship.assist_on,
		ControlCheckSample.CAMERA: String(CameraRig.mode_name(main.camera_rig.mode)),
		ControlCheckSample.LOOK_DEG: main.camera_rig.look_goal().length(),
		ControlCheckSample.LIGHTS: ship.running_lights,
		ControlCheckSample.TRACKING: ship.get_flight_output().tracking,
		ControlCheckSample.TARGET: ship.targeting.selected_id(),
		ControlCheckSample.FIRE_MODE: String(PulseCannonGate.mode_name(main.cannon.gate.mode)),
		ControlCheckSample.INTERACTIONS: main.interactions.runs,
		ControlCheckSample.WING_ORDER: String(AiContext.order_word(wing.order)) if wing != null else "",
		ControlCheckSample.WING_ORDERS: main.wings.orders_given,
		ControlCheckSample.TARGET_MENUS: main.target_menu.opens,
	}
	return out
