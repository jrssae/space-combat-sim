class_name AiPilotDriver
extends Node
## Runs a `PilotBrain` for one ship (architecture §15.3, §15.8). A child of the AI ship, `process_physics_priority` -10 so the
## ship uses this tick's command (the ship runs at priority 0). Each tick it keeps the ship's `TargetingController` on the
## nearest hostile, builds a fresh `Perception` (current positions and velocities, read from the nodes, not from last tick's
## candidate list), asks the brain, and hands the result to `Combatant.apply_commands`: the very call the player's input goes
## through. With no brain it does nothing and the ship keeps the commands it has.

## Seconds between looking for a nearer hostile (a selection that is gone is replaced at once).
const RETARGET_S: float = 0.5

var combatant: Combatant = null
var world: WorldFrame = null
var brain: PilotBrain = null:
	set(value):
		brain = value
		if value != null:
			value.reset()

var _capability: ShipCapability = null
var _retarget_in_s: float = 0.0


func _init() -> void:
	process_physics_priority = -10


func _physics_process(delta: float) -> void:
	step(delta)


## One tick. `_physics_process` calls it; public so tests can drive it.
func step(delta: float) -> void:
	if brain == null or combatant == null or not is_instance_valid(combatant.ship):
		return
	_retarget(delta)
	var pc: PilotCommand = brain.think(perceive(), delta)
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
	return p


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
