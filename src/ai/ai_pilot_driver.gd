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
## `URGENT_SEEK_HORIZON_S` when the filter says urgent; the brain's turn command and combat command are left as they are.
## When nothing threatens, the brain's command reaches the ship untouched. A held brake (all stop) is never filtered.
## The tie-break seed is `hash(display_name)`, so a ship dodges the same way in every run.

## Seconds between looking for a nearer hostile (a selection that is gone is replaced at once).
const RETARGET_S: float = 0.5
## The urgent dodge's seek horizon, s: the RCS reaches full strafe for a quarter of the velocity error it would at 1 s.
const URGENT_SEEK_HORIZON_S: float = 0.25

var combatant: Combatant = null
var world: WorldFrame = null
var brain: PilotBrain = null:
	set(value):
		brain = value
		last_hit_s = -INF
		if value != null:
			value.reset()
## Whether the avoidance filter changed this tick's command (the ship is dodging something), and whether it was urgent.
var avoiding: bool = false
var avoiding_urgent: bool = false
## Sim time of this hull's latest hit (`Damageable.hit_taken`), -INF since the brain was set.
var last_hit_s: float = -INF

var _capability: ShipCapability = null
var _retarget_in_s: float = 0.0


func _init() -> void:
	process_physics_priority = -10


func _ready() -> void:
	if combatant != null and combatant.damageable != null:
		combatant.damageable.hit_taken.connect(_on_hit_taken)


func _physics_process(delta: float) -> void:
	step(delta)


## One tick. `_physics_process` calls it; public so tests can drive it.
func step(delta: float) -> void:
	if brain == null or combatant == null or not is_instance_valid(combatant.ship):
		return
	_retarget(delta)
	var p: Perception = perceive()
	brain.has_desired_velocity = false
	var pc: PilotCommand = brain.think(p, delta)
	_avoid(p, pc.flight)
	combatant.apply_commands(pc.flight, pc.combat)


## A `Perception` of this tick.
func perceive() -> Perception:
	var ship: Ship = combatant.ship
	var p := Perception.new()
	p.now_s = SimClock.now()
	p.position = ship.global_position
	p.basis = ship.global_basis
	p.velocity = ship.linear_velocity
	p.angular_velocity = ship.angular_velocity
	p.hull_fraction = combatant.damageable.hull.fraction() if combatant.damageable != null else 1.0
	p.faction = combatant.faction
	if _capability == null:
		_capability = ShipCapability.from_spec(ship.spec, ship.get_layout())
	p.capability = _capability
	var weapon: WeaponSpec = combatant.cannon.weapon
	p.muzzle_speed_mps = weapon.muzzle_speed_mps
	p.weapon_lifetime_s = weapon.lifetime_s
	p.frame_origin = world.to_universe(Vector3.ZERO) if world != null else UniversePos.new()
	var targeting: TargetingController = ship.targeting
	if targeting.system.has_selection() and is_instance_id_valid(targeting.selected_id()):
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
	PilotSteering.apply_seek(flight, PilotSteering.seek(p.velocity, filtered, p.basis, p.capability, horizon))


func _on_hit_taken(_info: HitInfo) -> void:
	last_hit_s = SimClock.now()


func _retarget(delta: float) -> void:
	var targeting: TargetingController = combatant.ship.targeting
	_retarget_in_s -= delta
	if _retarget_in_s <= 0.0 or not _selection_is_live(targeting):
		_retarget_in_s = RETARGET_S
		targeting.select_nearest_hostile()


# A selection exists and its target can still be targeted (a destroyed or parked ship is replaced at once).
func _selection_is_live(targeting: TargetingController) -> bool:
	if not targeting.system.has_selection() or not is_instance_id_valid(targeting.selected_id()):
		return false
	var targetable := instance_from_id(targeting.selected_id()) as Targetable
	return targetable != null and targetable.is_active()
