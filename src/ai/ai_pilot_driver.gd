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
##
## Targeting: a brain that names a target (`PilotBrain.wanted_target_id`, `AiPilot`'s attack target) gets it selected after
## its `think`, and the nearest-hostile rule leaves that selection alone while it lasts; a brain with no preference (0, every
## M2 brain) keeps the M2 rule.
##
## Console (§16.4, M3-T06): provider `ai` (`ships`, `by_behaviour`, `think_us`) and command `ai <name>`, registered while any
## driver is in the tree (owner: the newest; handed to another when it leaves). `think_us` is the wall-clock time every
## driver's `step` took in the last complete physics tick: a profiling readout (AC13), never gameplay time.

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
	_register_console(self)


func _exit_tree() -> void:
	_live.erase(self)
	DebugConsole.registry.unregister_owner(self)
	if not _live.is_empty():
		_register_console(_live.back())


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
	p.frame_origin = world.to_universe(Vector3.ZERO) if world != null else UniversePos.new()
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
	PilotSteering.apply_seek(flight, PilotSteering.seek(p.velocity, filtered, p.basis, p.capability, horizon))


func _on_hit_taken(_info: HitInfo) -> void:
	last_hit_s = SimClock.now()


func _retarget(delta: float) -> void:
	var targeting: TargetingController = combatant.ship.targeting
	var wanted: int = brain.wanted_target_id
	if wanted != 0 and targeting.selected_id() == wanted and _selection_is_live(targeting):
		return  # the brain's own choice stands
	_retarget_in_s -= delta
	if _retarget_in_s <= 0.0 or not _selection_is_live(targeting):
		_retarget_in_s = RETARGET_S
		targeting.select_nearest_hostile()


# Selects the brain's wanted target when it names one the targeting computer does not have selected. One it cannot select
# (a hull with no `Targetable`) is not tried again until the brain wants another.
func _follow_brain_target() -> void:
	var wanted: int = brain.wanted_target_id
	var targeting: TargetingController = combatant.ship.targeting
	if wanted == 0 or wanted == _unselectable_id or targeting.selected_id() == wanted:
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


# --- console -----------------------------------------------------------------------------------------------------


static func _register_console(owner: AiPilotDriver) -> void:
	DebugConsole.registry.register_provider(&"ai", ConsoleVars.new({
		&"ships": {"get": _console_ships, "doc": "AI ships in play: name, behaviour (state)"},
		&"by_behaviour": {"get": _console_by_behaviour, "doc": "How many AI ships run each behaviour"},
		&"think_us": {"get": think_us, "unit": "us",
				"doc": "Wall-clock time of every AI driver in the last physics tick (profiling only)"},
	}), owner)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"ai",
			"Show an AI ship's behaviour, its state and every behaviour's last score",
			[ConsoleArg.string_rest(&"name").with_suggestions(_console_names)]), _cmd_ai, owner)


# The drivers flying a ship in play (a brain set, the ship processing), in tree order.
static func _flying() -> Array[AiPilotDriver]:
	var out: Array[AiPilotDriver] = []
	for driver: AiPilotDriver in _live:
		if driver.brain != null and driver.combatant != null and is_instance_valid(driver.combatant.ship) \
				and driver.combatant.ship.can_process():
			out.append(driver)
	return out


static func _console_ships() -> PackedStringArray:
	var out := PackedStringArray()
	for driver: AiPilotDriver in _flying():
		var d: Dictionary = driver.brain.describe()
		out.append("%s %s (%s)" % [driver.combatant.display_name, d.get("behaviour", "none"), d.get("state", "none")])
	return out


static func _console_by_behaviour() -> Dictionary:
	var out: Dictionary = {}
	for driver: AiPilotDriver in _flying():
		var behaviour: String = str(driver.brain.describe().get("behaviour", "none"))
		out[behaviour] = int(out.get(behaviour, 0)) + 1
	return out


static func _console_names() -> PackedStringArray:
	var out := PackedStringArray()
	for driver: AiPilotDriver in _flying():
		out.append(driver.combatant.display_name)
	return out


static func _cmd_ai(args: Dictionary) -> ConsoleResult:
	var wanted: String = String(args[&"name"]).strip_edges()
	for driver: AiPilotDriver in _flying():
		if driver.combatant.display_name.to_lower() == wanted.to_lower():
			return ConsoleResult.success(describe_lines(driver.combatant.display_name, driver.brain.describe()))
	var names: PackedStringArray = _console_names()
	return ConsoleResult.failure("no AI ship named '%s' (AI ships: %s)%s" % [wanted,
			", ".join(names) if not names.is_empty() else "none", ConsoleFormat.did_you_mean(wanted, names)])


## The `ai <name>` lines for a brain's `describe()`: `NAME: behaviour (state)`, then its other fields, then the scores.
static func describe_lines(ship_name: String, d: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	out.append("%s: %s (%s)" % [ship_name, d.get("behaviour", "none"), d.get("state", "none")])
	var fields := PackedStringArray()
	for key: Variant in d:
		if key != "behaviour" and key != "state" and key != "scores":
			fields.append("%s %s" % [key, ConsoleFormat.value(d[key])])
	if not fields.is_empty():
		out.append("  " + ", ".join(fields))
	if d.has("scores"):
		var scores: Dictionary = d["scores"]
		var parts := PackedStringArray()
		for id: Variant in scores:
			parts.append("%s %.2f%s" % [id, float(scores[id]), " *" if str(id) == str(d.get("behaviour", "")) else ""])
		out.append("  scores: " + ", ".join(parts))
	return out
