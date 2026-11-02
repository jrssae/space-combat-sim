class_name AiPilotDriver
extends Node
## Runs a `PilotBrain` for one ship (architecture §15.3, §15.8, §16.3). A child of the AI ship at `process_physics_priority`
## -10, so the ship uses this tick's command. Each tick it builds a fresh `Perception` (contacts and incoming fire from the
## shared `ContactScan`, broadcasts beyond 5 km, M3-T17), asks the brain, filters the brain's desired velocity through
## `AvoidanceMath` (D33) and hands the result to `Combatant.apply_commands`, the same call the player's input uses. With no
## brain the ship keeps the commands it has.
##
## Avoidance: when the filter changes the wish, thrust is sought again toward the filtered velocity (with
## `URGENT_SEEK_HORIZON_S` when urgent), allocated as the brain allocated its own (`desired_all_axes`, M3-T07). Turn and
## combat commands are left alone. A held brake is never filtered. The tie-break seed is `hash(display_name)`, so a ship
## dodges the same way every run.
##
## Targeting (`PilotBrain.wanted_target_id`): a brain that leaves it at `TARGET_NEAREST_HOSTILE` (every M2 brain) gets the
## nearest hostile, refreshed every `RETARGET_S`. Otherwise the driver follows the brain's target, or clears the selection
## for `TARGET_NONE`.
##
## Console (§16.4, M3-T06): `AiConsole` is registered while any driver is in the tree, owned by the newest. `think_us()` is
## wall-clock time, a profiling readout (AC13), never gameplay time.

## Seconds between looking for a nearer hostile (a selection that is gone is replaced at once).
const RETARGET_S: float = 0.5
## The urgent dodge's seek horizon, s: the RCS reaches full strafe for a quarter of the velocity error it would at 1 s.
const URGENT_SEEK_HORIZON_S: float = 0.25

# Every driver in the tree (the console's view), and the think-time sums for `think_us`.
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
		last_bolt_hit_s = -INF
		last_attacker_id = 0
		_unselectable_id = 0
		if value != null:
			value.reset()
		_start_lights(value)
## Whether the avoidance filter changed this tick's command (the ship is dodging), and whether it was urgent.
var avoiding: bool = false
var avoiding_urgent: bool = false
## Sim time of this hull's latest hit (`Damageable.hit_taken`), and of its latest bolt hit, -INF since the brain was set.
var last_hit_s: float = -INF
var last_bolt_hit_s: float = -INF
## The `Targetable` id of whoever hit this hull last (0: nobody, or the console).
var last_attacker_id: int = 0

var _capability: ShipCapability = null
## The mean of the ship's muzzles, ship-local (muzzles never move on the hull, so computed once).
var _muzzle_local: Vector3 = Vector3.ZERO
var _muzzle_known: bool = false
var _retarget_in_s: float = 0.0
var _unselectable_id: int = 0
# This ship is hiding: its lights are off until the brain attacks (M3-T27).
var _hiding: bool = false


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
	if _hiding and pc.combat != null and pc.combat.fire:  # the first shot ends the hiding (Q27)
		_hiding = false
		combatant.ship.running_lights = true
	_follow_brain_target()
	_avoid(p, pc.flight)
	combatant.apply_commands(pc.flight, pc.combat)
	_add_think_time(Time.get_ticks_usec() - started_us)


# A pool ship is somebody new each time: its lights start as its new pilot wants them, whatever the last one did.
func _start_lights(new_brain: PilotBrain) -> void:
	_hiding = new_brain != null and new_brain.flies_dark
	if combatant != null and is_instance_valid(combatant.ship):
		combatant.ship.running_lights = not _hiding


## Wall-clock microseconds every driver's `step` took in the last complete physics tick (the console's `ai.think_us`).
static func think_us() -> int:
	return _think_last_us


## Wall-clock microseconds every driver's `step` has taken so far in the current physics tick (`PerfProbe`, M4-T01).
static func think_us_this_tick() -> int:
	return _think_sum_us if _think_frame == Engine.get_physics_frames() else 0


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
	if not _muzzle_known:
		_muzzle_known = true
		var mean := Vector3.ZERO
		var muzzles: Array[Node3D] = ship.get_muzzles()
		for muzzle: Node3D in muzzles:
			mean += ship.to_local(muzzle.global_position)
		_muzzle_local = mean / float(muzzles.size()) if not muzzles.is_empty() else Vector3.ZERO
	p.muzzle_offset = ship.global_basis * _muzzle_local
	var weapon: WeaponSpec = combatant.cannon.weapon
	p.muzzle_speed_mps = weapon.muzzle_speed_mps
	p.weapon_lifetime_s = weapon.lifetime_s
	if world != null:
		p.frame_origin = world.origin  # a rebase assigns a new origin, so keep this tick's
	var targeting: TargetingController = ship.targeting
	if (brain == null or brain.reads_target()) and targeting.system.has_selection() \
			and is_instance_id_valid(targeting.selected_id()):
		var targetable := instance_from_id(targeting.selected_id()) as Targetable
		if targetable != null and targetable.is_active():
			p.target = targetable.to_target_info()
			p.target_hostile = Factions.is_hostile(combatant.faction, targetable.faction)
	var timed: bool = ContactScan.timing
	var scan_started_us: int = Time.get_ticks_usec() if timed else 0  # profiling readout only (M4-T01)
	var scan: ContactScan = ContactScan.shared(get_tree())
	var own_id: int = ship.get_instance_id()
	p.contacts = scan.contacts_for(own_id, p.position, p.faction)
	p.incoming_fire = scan.incoming_fire(own_id, p.position, p.velocity, p.faction)
	p.broadcasts = ContactScan.shared_broadcasts().broadcasts_for(own_id, p.position, p.faction)
	if timed:
		ContactScan.add_time(Time.get_ticks_usec() - scan_started_us)
	p.last_hit_s = last_hit_s
	p.last_bolt_hit_s = last_bolt_hit_s
	p.last_attacker_id = last_attacker_id
	p.friendly_fire = bool(Settings.get_value(&"friendly_fire"))
	return p


# Applies the avoidance filter (D33) to the brain's wish.
func _avoid(p: Perception, flight: FlightCommand) -> void:
	avoiding = false
	avoiding_urgent = false
	if flight.brake or p.contacts.is_empty():
		return
	var wish: Vector3 = brain.desired_velocity if brain.has_desired_velocity else p.velocity
	var radius: float = combatant.damageable.bounding_radius if combatant.damageable != null else 0.0
	var contacts: Array[Contact] = p.contacts
	if brain.avoid_exempt_id != 0:  # a committed rammer flies into its target (M3-T13); everything else is still avoided
		contacts = []
		for c: Contact in p.contacts:
			if c.id != brain.avoid_exempt_id:
				contacts.append(c)
	var result: Dictionary = AvoidanceMath.filter(p.position, p.velocity, radius, contacts, wish, p.capability,
			hash(combatant.display_name))
	var filtered: Vector3 = result["v_des"]
	if filtered == wish:
		return
	avoiding = true
	avoiding_urgent = bool(result["urgent"])
	var horizon: float = URGENT_SEEK_HORIZON_S if avoiding_urgent else PilotSteering.HORIZON_S
	var all_axes: bool = brain.has_desired_velocity and brain.desired_all_axes
	PilotSteering.apply_seek(flight, PilotSteering.seek(p.velocity, filtered, p.basis, p.capability, horizon, all_axes))


func _on_hit_taken(info: HitInfo) -> void:
	last_hit_s = SimClock.now()
	if info != null and info.cause == HitInfo.CAUSE_BOLT:
		last_bolt_hit_s = last_hit_s
	if info != null and info.shooter_id != 0 and is_instance_id_valid(info.shooter_id):
		var shooter := instance_from_id(info.shooter_id) as Node
		var marker := shooter.get_node_or_null(^"Targetable") as Targetable if shooter != null else null
		if marker != null:
			last_attacker_id = marker.get_instance_id()


# M2's rule for a brain that leaves the choice to the driver.
func _retarget(delta: float) -> void:
	if brain.wanted_target_id != PilotBrain.TARGET_NEAREST_HOSTILE:
		return  # the brain chooses (`_follow_brain_target`)
	var targeting: TargetingController = combatant.ship.targeting
	_retarget_in_s -= delta
	if _retarget_in_s <= 0.0 or not _selection_is_live(targeting):
		_retarget_in_s = RETARGET_S
		targeting.select_nearest_hostile()


# Keeps the selection on what the brain wants. A target it cannot select is not retried until it wants another.
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


# Whether the selection can still be targeted (a destroyed or parked ship is replaced at once).
func _selection_is_live(targeting: TargetingController) -> bool:
	if not targeting.system.has_selection() or not is_instance_id_valid(targeting.selected_id()):
		return false
	var targetable := instance_from_id(targeting.selected_id()) as Targetable
	return targetable != null and targetable.is_active()


## The drivers flying a ship in play, for `AiConsole`.
static func flying() -> Array[AiPilotDriver]:
	var out: Array[AiPilotDriver] = []
	for driver: AiPilotDriver in _live:
		if driver.brain != null and driver.combatant != null and is_instance_valid(driver.combatant.ship) \
				and driver.combatant.ship.can_process():
			out.append(driver)
	return out
