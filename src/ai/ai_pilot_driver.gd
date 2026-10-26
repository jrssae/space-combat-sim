class_name AiPilotDriver
extends Node
## Runs a `PilotBrain` for one ship (architecture §15.3, §15.8, §16.3). A child of the AI ship, `process_physics_priority` -10
## so the ship uses this tick's command (the ship runs at priority 0). Each tick it keeps the ship's `TargetingController` on
## the nearest hostile, builds a fresh `Perception` (current positions and velocities, read from the nodes, not from last
## tick's candidate list; contacts and incoming fire from this tick's shared `ContactScan`), asks the brain, runs the
## brain's desired velocity through `AvoidanceMath` (D33), and hands the result to `Combatant.apply_commands`: the very call
## the player's input goes through. With no brain it does nothing and the ship keeps the commands it has.
##
## Avoidance: the wish is the brain's `desired_velocity` when it sought one this tick, else the current velocity (a coasting
## brain). When the filter changes it, the thrust (mains, retros, strafe) is sought again toward the filtered velocity, with
## `URGENT_SEEK_HORIZON_S` when the filter says urgent and allocated as the brain allocated its own (`desired_all_axes`: a
## held nose keeps its mains and retros working at any angle, M3-T07); the brain's turn and combat commands are left as
## they are.
## When nothing threatens, the brain's command reaches the ship untouched. A held brake (all stop) is never filtered.
## The tie-break seed is `hash(display_name)`, so a ship dodges the same way in every run.
##
## Targeting (`PilotBrain.wanted_target_id`): a brain that leaves it at `TARGET_NEAREST_HOSTILE` (every M2 brain) gets the
## M2 rule, the nearest hostile, refreshed every `RETARGET_S`. Otherwise the driver follows the brain after its `think`: the
## named target is selected (`AiPilot`'s attack target), `TARGET_NONE` clears the selection, and the nearest-hostile rule
## stays out of it.
##
## Console (§16.4, M3-T06): `AiConsole`'s provider `ai` and command `ai <name>`, registered while any driver is in the tree
## (owner: the newest; handed to another when it leaves). `think_us()` is the wall-clock time every driver's `step` took in
## the last complete physics tick: a profiling readout (AC13), never gameplay time.

## Seconds between looking for a nearer hostile (a selection that is gone is replaced at once).
const RETARGET_S: float = 0.5
## The urgent dodge's seek horizon, s: the RCS reaches full strafe for a quarter of the velocity error it would at 1 s.
const URGENT_SEEK_HORIZON_S: float = 0.25

# Every driver in the tree (the console's view), and the think-time sums: the frame being summed, its running sum, and the
# last complete frame's.
static var _live: Array[AiPilotDriver] = []
static var _think_frame: int = -1
static var _think_sum_us: int = 0
static var _think_last_us: int = 0

var combatant: Combatant = null
var world: WorldFrame = null
var brain: PilotBrain = null:
	set(value):
		brain = value
		last_hit_s = -INF
		_unselectable_id = 0
		if value != null:
			value.reset()
## Whether the avoidance filter changed this tick's command (the ship is dodging something), and whether it was urgent.
var avoiding: bool = false
var avoiding_urgent: bool = false
## Sim time of this hull's latest hit (`Damageable.hit_taken`), -INF since the brain was set.
var last_hit_s: float = -INF

var _capability: ShipCapability = null
var _retarget_in_s: float = 0.0
var _unselectable_id: int = 0


func _init() -> void:
	process_physics_priority = -10


func _enter_tree() -> void:
	_live.append(self)
	AiConsole.register(DebugConsole.registry, self)


func _exit_tree() -> void:
	_live.erase(self)
	DebugConsole.registry.unregister_owner(self)
	if not _live.is_empty():
		AiConsole.register(DebugConsole.registry, _live.back())


func _ready() -> void:
	if combatant != null and combatant.damageable != null:
		combatant.damageable.hit_taken.connect(_on_hit_taken)


func _physics_process(delta: float) -> void:
	step(delta)


## One tick. `_physics_process` calls it; public so tests can drive it.
func step(delta: float) -> void:
	if brain == null or combatant == null or not is_instance_valid(combatant.ship):
		return
	var started_us: int = Time.get_ticks_usec()  # profiling readout only, never gameplay time
	_retarget(delta)
	var p: Perception = perceive()
	brain.has_desired_velocity = false
	var pc: PilotCommand = brain.think(p, delta)
	_follow_brain_target()
	_avoid(p, pc.flight)
	combatant.apply_commands(pc.flight, pc.combat)
	_add_think_time(Time.get_ticks_usec() - started_us)


## Wall-clock microseconds every driver's `step` took in the last complete physics tick (the console's `ai.think_us`).
static func think_us() -> int:
	return _think_last_us


## A `Perception` of this tick.
func perceive() -> Perception:
	var ship: Ship = combatant.ship
	var p := Perception.new()
	p.now_s = SimClock.now()
	p.position = ship.global_position
	p.basis = ship.global_basis
	p.velocity = ship.linear_velocity
	p.angular_velocity = ship.angular_velocity
	p.self_id = combatant.targetable.get_instance_id() if combatant.targetable != null else 0
	p.hull_fraction = combatant.damageable.hull.fraction() if combatant.damageable != null else 1.0
	p.faction = combatant.faction
	if _capability == null:
		_capability = ShipCapability.from_spec(ship.spec, ship.get_layout())
	p.capability = _capability
	var weapon: WeaponSpec = combatant.cannon.weapon
	p.muzzle_speed_mps = weapon.muzzle_speed_mps
	p.weapon_lifetime_s = weapon.lifetime_s
	if world != null:
		p.frame_origin = world.origin  # a rebase assigns a new origin, so this one stays the tick's
	var targeting: TargetingController = ship.targeting
	if (brain == null or brain.reads_target()) and targeting.system.has_selection() \
			and is_instance_id_valid(targeting.selected_id()):
		var targetable := instance_from_id(targeting.selected_id()) as Targetable
		if targetable != null and targetable.is_active():
			p.target = targetable.to_target_info()
			p.target_hostile = Factions.is_hostile(combatant.faction, targetable.faction)
	var scan: ContactScan = ContactScan.shared(get_tree())
	var own_id: int = ship.get_instance_id()
	p.contacts = scan.contacts_for(own_id, p.position, p.faction)
	p.incoming_fire = scan.incoming_fire(own_id, p.position, p.velocity, p.faction)
	p.last_hit_s = last_hit_s
	p.friendly_fire = bool(Settings.get_value(&"friendly_fire"))
	return p


# The avoidance filter (D33) on the brain's wish; re-seeks the thrust when it changes it.
func _avoid(p: Perception, flight: FlightCommand) -> void:
	avoiding = false
	avoiding_urgent = false
	if flight.brake or p.contacts.is_empty():
		return
	var wish: Vector3 = brain.desired_velocity if brain.has_desired_velocity else p.velocity
	var radius: float = combatant.damageable.bounding_radius if combatant.damageable != null else 0.0
	var result: Dictionary = AvoidanceMath.filter(p.position, p.velocity, radius, p.contacts, wish, p.capability,
			hash(combatant.display_name))
	var filtered: Vector3 = result["v_des"]
	if filtered == wish:
		return
	avoiding = true
	avoiding_urgent = bool(result["urgent"])
	var horizon: float = URGENT_SEEK_HORIZON_S if avoiding_urgent else PilotSteering.HORIZON_S
	var all_axes: bool = brain.has_desired_velocity and brain.desired_all_axes
	PilotSteering.apply_seek(flight, PilotSteering.seek(p.velocity, filtered, p.basis, p.capability, horizon, all_axes))


func _on_hit_taken(_info: HitInfo) -> void:
	last_hit_s = SimClock.now()


# M2's rule, for a brain that leaves the choice to the driver: the nearest hostile, refreshed every `RETARGET_S`.
func _retarget(delta: float) -> void:
	if brain.wanted_target_id != PilotBrain.TARGET_NEAREST_HOSTILE:
		return  # the brain chooses (`_follow_brain_target`)
	var targeting: TargetingController = combatant.ship.targeting
	_retarget_in_s -= delta
	if _retarget_in_s <= 0.0 or not _selection_is_live(targeting):
		_retarget_in_s = RETARGET_S
		targeting.select_nearest_hostile()


# The selection a brain that chooses wants: its target (one it cannot select, a hull with no `Targetable`, is not tried again
# until it wants another), or none.
func _follow_brain_target() -> void:
	var wanted: int = brain.wanted_target_id
	if wanted == PilotBrain.TARGET_NEAREST_HOSTILE:
		return
	var targeting: TargetingController = combatant.ship.targeting
	if wanted == PilotBrain.TARGET_NONE:
		if targeting.system.has_selection():
			targeting.clear_selection()
		return
	if wanted == _unselectable_id or targeting.selected_id() == wanted:
		return
	_unselectable_id = 0 if targeting.select_id(wanted) else wanted


static func _add_think_time(us: int) -> void:
	var frame: int = Engine.get_physics_frames()
	if frame != _think_frame:
		_think_last_us = _think_sum_us if _think_frame >= 0 else 0
		_think_sum_us = 0
		_think_frame = frame
	_think_sum_us += us


# A selection exists and its target can still be targeted (a destroyed or parked ship is replaced at once).
func _selection_is_live(targeting: TargetingController) -> bool:
	if not targeting.system.has_selection() or not is_instance_id_valid(targeting.selected_id()):
		return false
	var targetable := instance_from_id(targeting.selected_id()) as Targetable
	return targetable != null and targetable.is_active()


## The drivers flying a ship in play (a brain set, the ship processing), in the order they entered the tree: the console's
## view (`AiConsole`).
static func flying() -> Array[AiPilotDriver]:
	var out: Array[AiPilotDriver] = []
	for driver: AiPilotDriver in _live:
		if driver.brain != null and driver.combatant != null and is_instance_valid(driver.combatant.ship) \
				and driver.combatant.ship.can_process():
			out.append(driver)
	return out
