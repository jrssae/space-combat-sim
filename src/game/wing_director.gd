class_name WingDirector
extends Node
## Owns the wings and carries their orders to the pilots (architecture §16 D36, §16.3, M3-T07). `Combat/WingDirector` in the
## main scene, `process_physics_priority` 290: after the resolvers (a member destroyed this tick is already down), before the
## waves (300).
##
## Each tick, for every wing (`refresh`): members that are down, left play or no longer fly an `AiPilot` leave their slot.
## When one was destroyed, the ones behind move up so the formation has no hole (`Wing.close_gaps`, M8-T13; they keep their
## callsigns and paint); a member that only left (released, made leader) leaves its slot open.
## Then each member's `AiContext` gets the wing's view: its order (`Wing.effective_order`: engage at will while the leader is
## dead), the leader's id and selected target, the engage radius, its slot offset, and the link to the leader that a member
## beyond sensor range flies on.
##
## Members: `add_member` takes a ship in play whose driver flies an `AiPilot` and gives it the formation behaviour if it has
## none; `remove_member` gives the ship back its own orders.
##
## Orders (`give_order`) come from `UiCommand` edges (keys 1-4, through `Main`) and the console, never from `Input`. An order
## changes every member's at once and posts one acknowledgement line (`acknowledged`, `last_ack`; `ack_text` is the HUD's
## line, held `ACK_HOLD_S` of sim time). ATTACK MY TARGET is refused, with a line saying so, while the leader has no hostile
## selected.
##
## Replenish (maintainer Q8, AC11): `replenish` gives every empty slot of the player's wing an allied Starfury from the pool,
## named by `Wing.callsign(slot)`, `REPLENISH_DISTANCE_M` behind the leader along the body frame's +Z (the leader's velocity
## may be zero or anything), at the leader's velocity, on the `ally_starfury` profile and the wing's order. `Main` calls it
## on `WaveDirector.wave_started`. It refreshes first, so a wingman shot down this very tick counts as empty whatever the
## physics order. It launches nothing while the leader is down or the game is paused, fills what the pool can, and warns
## once if it falls short (not when the scenario pools no allies). A replacement takes the callsign of the wingman whose loss
## left its slot empty (`callsign_for`). A callsign already carried by a ship in play is not given twice: that slot takes the
## next free number.
##
## Scenario wings (M3-T10): `declare` takes a scenario's `wings[]`; `join` puts a ship spawned into a named wing, after the
## ships that left play this tick give up their slots, and warns when the wing cannot take it. The wing is
## created on first use (as declared, or a group engaging at will in a finger-four). The declared leader leads, or else the
## first to join. The player's wing is created by Main. An AI-led wing whose leader is down hands the lead to its lowest
## slot (`refresh`), so a raider group keeps flying as a group; the player's wing waits for the player.
##
## Running lights (M3-T27): the members of the player's wing copy the player's, every tick.
##
## Flights of three (M8-T19, D85; `FlightRules`, `data/wings/flights.json`): a squadron split into flights is several wings
## of one name, numbered by `Wing.flight` (`flights_of`). Newcomers take the next place (`next_flight_place`, `take_place`):
## the first flight without a lead, then its empty slots, then a new flight. The pilots of an AI-led flight get the flight's
## rules each tick (`AiContext.cover`; a wingman's `cohesion_m`), and the leads of a squadron's later flights hold a slot on
## its first AI lead while there is nothing to fight. A wing declared `flight` that the player leads is the player's own
## flight: it has two slots, only they take the player's orders, and the rest of the squadron flies in flights from 2 on.
##
## Console (§16.4), for the player's wing (`player_wing`): provider `wing` (`name`, `order`, `formation`, `members`,
## `last_ack`) and `wing [order|formation|replenish] [value]`.

## A new acknowledgement (or refusal) line.
signal acknowledged(line: String)

const ACK_HOLD_S: float = 3.5
const PRIORITY: int = 290
const WHAT_CHOICES: Array[StringName] = [&"order", &"formation", &"replenish"]
## Replacements enter this far behind the leader.
const REPLENISH_DISTANCE_M: float = 1500.0
const REPLENISH_PROFILE: String = "ally_starfury"
## The orders in key order (1-4, then 7 and 8: M8-T19's hold-fire orders), as the console lists them.
const ORDERS_BY_KEY: Array[AiContext.Order] = [AiContext.Order.ATTACK_MY_TARGET, AiContext.Order.FORM_ON_ME,
		AiContext.Order.ENGAGE_AT_WILL, AiContext.Order.COVER_ME, AiContext.Order.FORM_HOLD_FIRE, AiContext.Order.HOLD_POSITION]

var world: WorldFrame = null
## Where replacements come from (`ShipPool.ALLY_TYPE` ships); null: `replenish` launches nothing.
var pool: ShipPool = null
var wings: Array[Wing] = []
## The latest acknowledgement or refusal line ("" before the first order).
var last_ack: String = ""
## Orders the player's wing took so far (a refused one is not counted): M8's control checks read it.
var orders_given: int = 0

var _ack_age_s: float = INF
# Scenario `wings[]` declarations by lower-case name.
var _declared: Dictionary = {}
# Replacements launched so far; part of each brain seed so a run repeats.
var _launched: int = 0
## How flights fly (M8-T19); a test may set its own.
var flight_rules: FlightRules = FlightRules.shared()


func _init() -> void:
	process_physics_priority = PRIORITY


func _ready() -> void:
	DebugConsole.registry.register_provider(&"wing", ConsoleVars.new({
		&"name": {"get": func() -> String: return _player_wing_name(), "doc": "The player's wing"},
		&"order": {"get": _console_order,
				"doc": "Its order: attack (my target), form (on me), engage (at will), cover (me), form_hold (form up, hold fire) or hold (hold position, hold fire)"},
		&"formation": {"get": _console_formation, "doc": "Its formation: finger_four, wedge or line_abreast"},
		&"members": {"get": _console_members, "doc": "Each member: callsign, hull %, behaviour (state)"},
		&"last_ack": {"get": func() -> String: return last_ack, "doc": "The latest acknowledgement line"},
		&"flights": {"get": _console_flights, "doc": "The flights of the player's squadron (M8-T19): number, lead, wingmen"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"wing",
			"Order the player's wing (wing order attack|form|engage|cover|form_hold|hold: the last two are form up and hold fire, and hold position and hold fire), change its formation (wing formation finger_four|wedge|line_abreast) or launch replacements for its empty slots from the pool (wing replenish); alone, show the wing",
			[ConsoleArg.enum_optional(&"what", WHAT_CHOICES), ConsoleArg.string_optional(&"value").with_suggestions(_value_words)]),
			_cmd_wing, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func setup(p_world: WorldFrame, p_pool: ShipPool = null) -> void:
	world = p_world
	pool = p_pool


## A new wing led by `leader` (empty, COVER ME, finger-four).
func create_wing(wing_name: String, leader: Combatant) -> Wing:
	var wing := Wing.new(wing_name, leader)
	wings.append(wing)
	return wing


## Records a scenario's `wings[]` declarations (replacing earlier ones). A declared wing led by the player gets its order
## and formation on the player's wing at once.
func declare(declarations: Array[Dictionary]) -> void:
	_declared.clear()
	for d: Dictionary in declarations:
		_declared[String(d["name"]).to_lower()] = d
		var wing: Wing = wing_named(String(d["name"]))
		if wing != null and String(d["leader"]) == "player":
			wing.order = int(d["order"]) as AiContext.Order
			wing.formation.shape = int(d["formation"]) as Formation.Shape
			if not String(d.get("home", "")).is_empty():
				wing.home = StringName(d["home"])
			if bool(d.get("flight", false)):
				command_flight(wing)


## The wing called `wing_name` (case-insensitive), or null.
func wing_named(wing_name: String) -> Wing:
	for wing: Wing in wings:
		if wing.name.to_lower() == wing_name.to_lower():
			return wing
	return null


## Puts `ship`, just placed in play from a spawn naming `wing_name`, into that wing (see the class notes). Ships that left
## play this tick give up their slots first. Returns the wing, or null with a warning when the ship cannot join (no
## `AiPilot`, the wing full).
func join(wing_name: String, ship: Combatant) -> Wing:
	if wing_name.is_empty():
		return null
	if _pilot_of(ship) == null:
		push_warning("WingDirector: %s could not join %s: it flies no AiPilot" % [ship.display_name if ship != null else "null",
				wing_name])
		return null
	var d: Dictionary = _declared.get(wing_name.to_lower(), {})
	var wing: Wing = wing_named(wing_name)
	if bool(d.get("flight", false)):
		# A squadron of flights (M8-T19): the player's own flight first while it has room, then the AI flights.
		var own: Wing = wing if wing != null and wing.leader != null and wing.leader.is_player else null
		if own != null:
			refresh(own)
			if not own.is_full():
				give_home(own, ship)
				return _add_joining(own, ship)
		# Behind the player's own flight the others fly under their own AI: the declared order is the player's wing's.
		var order: AiContext.Order = AiContext.Order.ENGAGE_AT_WILL if own != null \
				else int(d.get("order", AiContext.Order.ENGAGE_AT_WILL)) as AiContext.Order
		var place: Dictionary = next_flight_place(String(d.get("name", wing_name)), 2 if own != null else 1,
				StringName(d.get("home", "")), order, int(d.get("formation", Formation.Shape.FINGER_FOUR)) as Formation.Shape)
		return take_place(place, ship)
	if wing == null:
		wing = create_wing(String(d.get("name", wing_name)), null)
		wing.order = int(d.get("order", AiContext.Order.ENGAGE_AT_WILL)) as AiContext.Order
		wing.formation.shape = int(d.get("formation", Formation.Shape.FINGER_FOUR)) as Formation.Shape
		wing.home = StringName(d.get("home", ""))
	else:
		refresh(wing)
	give_home(wing, ship)
	var named_leader: String = String(d.get("leader", ""))
	if wing.leader != null and wing.leader.is_player:
		return _add_joining(wing, ship)
	if not leader_alive(wing) and (named_leader.is_empty() or named_leader.to_lower() == ship.display_name.to_lower()
			or wing.members().is_empty()):
		_lead(wing, ship)
		return wing
	if named_leader.to_lower() == ship.display_name.to_lower():
		_lead(wing, ship)
		return wing
	return _add_joining(wing, ship)


## A ship that comes to `wing` through the scenario, a launch or a replenish takes the wing's home dock (M8-T06), unless the
## scenario gave it one of its own (or none on purpose).
static func give_home(wing: Wing, ship: Combatant) -> void:
	if wing != null and ship != null and not ship.home_assigned and wing.home != &"":
		ship.home = wing.home


# A joining ship takes a slot; a refusal is a scenario that does not fit its wing, so it is reported.
func _add_joining(wing: Wing, ship: Combatant) -> Wing:
	if add_member(wing, ship) > 0:
		return wing
	var why: String = "already in it" if wing.slot_of(ship) > 0 else ("not in play" if ship.damageable == null
			or not ship.damageable.is_active() else "the wing is full")
	push_warning("WingDirector: %s could not join %s: %s" % [ship.display_name, wing.name, why])
	return null


## Hands `wing`'s lead to its lowest slot; the old lead, still flying, takes a slot of its own flight (M8-T06: a lead that
## goes to dock leaves the flight in the air under its wingman). False when nobody can take over.
func hand_lead(wing: Wing) -> bool:
	if wing == null or wing.members().is_empty() or (wing.leader != null and wing.leader.is_player):
		return false
	_lead(wing, wing.members()[0])
	refresh(wing)
	return true


# Makes `ship` lead `wing`. A living old leader takes a slot.
func _lead(wing: Wing, ship: Combatant) -> void:
	var old: Combatant = wing.leader
	if wing.slot_of(ship) > 0:
		remove_member(wing, ship)
	var pilot: AiPilot = _pilot_of(ship)
	if pilot != null:
		pilot.context.clear_wing()
		_give_rally(pilot)
		if wing.flight > 0 and pilot.behaviour(&"formation") == null:
			pilot.add_behaviour(BehaviourFormation.new(pilot.profile))  # a flight's lead forms on its squadron's (M8-T19)
	wing.leader = ship
	_paint(wing, ship, 1 if wing.flight == 0 else _wing_number(wing, ship.display_name, wing.first_number))
	if old != null and old != ship and not old.is_player and old.damageable != null and old.damageable.is_active():
		add_member(wing, old)


# A Starfury that takes a place in a wing wears the wing's livery and `number` (the leader 01, a member its callsign's, or its
# slot's when it has another name), whatever the pool gave it (M4-T30b). Hulls without a livery table are left alone.
func _paint(wing: Wing, member: Combatant, number: int) -> void:
	if member == null or member.ship == null or member.ship.spec == null:
		return
	var section: Dictionary = MeshAssets.livery_section(member.ship.spec.asset_id)
	if not section.is_empty() and (pool == null or pool.type_of(member) == ShipPool.ALLY_TYPE):
		member.ship.set_livery(Livery.for_wing(wing.name, number, section))


# A wing's AI ships rally on an engaged wingmate when they have nothing to attack (`BehaviourRally`).
static func _give_rally(pilot: AiPilot) -> void:
	if pilot.behaviour(&"rally") == null:
		pilot.add_behaviour(BehaviourRally.new(pilot.profile))


## Makes `wing`, which the player leads, the player's own flight (M8-T19, D85): it keeps only a flight's slots, so only those
## wingmen take the player's orders. Returns false, changing nothing, when a slot beyond them is flown.
func command_flight(wing: Wing) -> bool:
	if wing == null or not wing.resize(flight_rules.wingmen()):
		return false
	wing.flight = 1
	return true


## The flights of squadron `squadron_name` (any case), in flight order: every wing of that name that is a flight.
func flights_of(squadron_name: String) -> Array[Wing]:
	var out: Array[Wing] = []
	for wing: Wing in wings:
		if wing.flight > 0 and wing.name.to_lower() == squadron_name.to_lower():
			out.append(wing)
	out.sort_custom(func(a: Wing, b: Wing) -> bool: return a.flight < b.flight)
	return out


## How many ships fly in squadron `squadron_name`'s flights, leads and the player included.
func flight_strength(squadron_name: String) -> int:
	var n: int = 0
	for wing: Wing in flights_of(squadron_name):
		refresh(wing)
		n += wing.members().size() + (1 if leader_alive(wing) else 0)
	return n


## Where the next newcomer to squadron `squadron_name` flies, among its AI flights from number `first_flight` on (2 when the
## player commands the first): `{"wing", "slot"}`, slot 0 for a flight without a living lead, else its first empty slot
## (`Wing.fill_order`), else a new flight, made here with `home`, `order` and `shape`.
func next_flight_place(squadron_name: String, first_flight: int = 1, home: StringName = &"",
		order: AiContext.Order = AiContext.Order.ENGAGE_AT_WILL, shape: Formation.Shape = Formation.Shape.FINGER_FOUR) -> Dictionary:
	var next: int = first_flight
	for wing: Wing in flights_of(squadron_name):
		if wing.flight < first_flight or (wing.leader != null and wing.leader.is_player):
			continue
		refresh(wing)
		if not leader_alive(wing):
			return {"wing": wing, "slot": 0}
		var free: PackedInt32Array = wing.fill_order()
		if not free.is_empty():
			return {"wing": wing, "slot": free[0]}
		next = maxi(next, wing.flight + 1)
	var made := Wing.new(squadron_name.to_upper(), null, flight_rules.wingmen())
	made.flight = next
	made.first_number = flight_rules.first_number(next)
	made.order = order
	made.formation.shape = shape
	made.home = home
	wings.append(made)
	return {"wing": made, "slot": 0}


## The callsign for the newcomer to `place` (`next_flight_place`): the place's own, or the lost wingman's, or the next free
## number when a ship in play carries it.
func place_callsign(place: Dictionary) -> String:
	var wing: Wing = place["wing"]
	var slot: int = place["slot"]
	if slot > 0:
		return callsign_for(wing, slot)
	var callsign: String = wing.callsign(0)
	return pool.next_name(wing.name, wing.first_number) if pool != null and _callsign_in_play(wing, callsign) else callsign


## Puts `ship` in `place`: it leads the flight, or takes the slot. Returns the flight, or null with a warning.
func take_place(place: Dictionary, ship: Combatant) -> Wing:
	var wing: Wing = place["wing"]
	if _pilot_of(ship) == null:
		push_warning("WingDirector: %s could not join %s: it flies no AiPilot" % [ship.display_name if ship != null else "null",
				wing.name])
		return null
	give_home(wing, ship)
	if int(place["slot"]) == 0:
		_lead(wing, ship)
		refresh(wing)
		return wing
	if add_member(wing, ship, int(place["slot"])) > 0:
		return wing
	push_warning("WingDirector: %s could not join %s flight %d" % [ship.display_name, wing.name, wing.flight])
	return null


## Takes away the AI flights of squadron `squadron_name` that nobody flies (a launch that fell through).
func drop_empty_flights(squadron_name: String) -> void:
	for wing: Wing in flights_of(squadron_name):
		if wing.leader == null and wing.members().is_empty():
			wings.erase(wing)


## The AI lead a squadron's flights form on (M8-T19): the lead of its first AI-led flight with a living lead, or null.
func squadron_lead(squadron_name: String) -> Combatant:
	for wing: Wing in flights_of(squadron_name):
		if wing.leader != null and not wing.leader.is_player and leader_alive(wing):
			return wing.leader
	return null


## The wing the player leads, else the first wing, else null.
func player_wing() -> Wing:
	for wing: Wing in wings:
		if wing.leader != null and wing.leader.is_player:
			return wing
	return wings[0] if not wings.is_empty() else null


## Puts a ship in play into `slot` of `wing` (-1: the one `Wing.fill_order` picks) and briefs its pilot. Returns the slot, or -1 when the
## wing refuses it, it does not fly an `AiPilot`, or it is not in play (`refresh` would drop it).
func add_member(wing: Wing, member: Combatant, slot: int = -1) -> int:
	var pilot: AiPilot = _pilot_of(member)
	if wing == null or pilot == null or member.damageable == null or not member.damageable.is_active():
		return -1
	var at: int = wing.add_member(member, slot)
	if at < 0:
		return -1
	_paint(wing, member, _wing_number(wing, member.display_name, at + wing.first_number))
	if pilot.behaviour(&"formation") == null:
		pilot.add_behaviour(BehaviourFormation.new(pilot.profile))
	_give_rally(pilot)
	refresh(wing)
	return at


## Gives every empty slot of `wing` (default: the player's) a replacement from the ally pool and returns the ships launched
## (see the class notes).
func replenish(wing: Wing = null) -> Array[Combatant]:
	var launched: Array[Combatant] = []
	if wing == null:
		wing = player_wing()
	if wing == null or pool == null or world == null or not is_inside_tree() or get_tree().paused:
		return launched
	refresh(wing)  # a wingman shot down this very tick is an empty slot already
	var empty: PackedInt32Array = wing.fill_order()  # the arms stay even if the pool runs dry
	if empty.is_empty() or not leader_alive(wing) or pool.pool_size(ShipPool.ALLY_TYPE) == 0:
		return launched
	var leader: Ship = wing.leader.ship
	var basis: Basis = leader.global_basis.orthonormalized()
	var velocity: Vector3 = leader.linear_velocity
	# Universe positions, used at once: nothing outlives the call, since a rebase moves the origin.
	var anchor: UniversePos = world.to_universe(leader.global_position)
	for slot: int in empty:
		if pool.free_count(ShipPool.ALLY_TYPE) == 0:
			break
		var lane: Vector3 = wing.slot_offset(slot)
		var at: UniversePos = anchor.plus_local(basis * Vector3(lane.x, lane.y, REPLENISH_DISTANCE_M))
		var callsign: String = callsign_for(wing, slot)
		var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": REPLENISH_PROFILE,
				"orders": String(AiContext.order_word(wing.order))}, at, hash([callsign, _launched]))
		if not bool(made["ok"]):
			push_warning("WingDirector: replenish: %s" % made["error"])
			break
		var ally: Combatant = pool.acquire(callsign, at, basis, velocity, made["brain"] as PilotBrain, ShipPool.ALLY_TYPE)
		if ally == null:
			break
		give_home(wing, ally)
		if add_member(wing, ally, slot) != slot:
			pool.release(ally)  # leave the slot for the next call
			break
		_launched += 1
		launched.append(ally)
	if launched.size() < empty.size():
		push_warning("WingDirector: replenish launched %d of %d wingmen for %s: %d of %d allied ships were free" % [
				launched.size(), empty.size(), wing.name, pool.free_count(ShipPool.ALLY_TYPE) + launched.size(),
				pool.pool_size(ShipPool.ALLY_TYPE)])
	return launched


## `WaveDirector.wave_started`: the downed wingmen are replaced (Q8).
func on_wave_started(_number: int, _wave_name: String) -> void:
	replenish()


## Takes `member` out of `wing`; its pilot flies on its own (engage at will, no slot, no leader).
func remove_member(wing: Wing, member: Combatant) -> void:
	if wing == null or not wing.remove_member(member):
		return
	var pilot: AiPilot = _pilot_of(member)
	if pilot != null:
		pilot.context.clear_wing()


## Takes `member` out of `wing` whether it flies a slot or leads it, so a launch that falls through leaves no ghosts behind.
## A leaderless wing takes the next ship `join`s as its leader.
func leave(wing: Wing, member: Combatant) -> void:
	if wing == null:
		return
	if wing.leader == member:
		wing.leader = null
		var pilot: AiPilot = _pilot_of(member)
		if pilot != null:
			pilot.context.clear_wing()
	remove_member(wing, member)


## Gives `wing` (default: the player's) a new order and posts one acknowledgement line. Returns `{"ok", "line"}`. ATTACK MY
## TARGET without a hostile selected is refused (`ok` false, order unchanged, the refusal is the line).
func give_order(new_order: AiContext.Order, wing: Wing = null) -> Dictionary:
	if wing == null:
		wing = player_wing()
	if wing == null:
		return {"ok": false, "line": "there is no wing to order"}
	refresh(wing)  # the line comes from a member that is still flying
	var target_name: String = ""
	if new_order == AiContext.Order.ATTACK_MY_TARGET:
		var target: Targetable = leader_hostile_target(wing)
		if target == null:
			_post(wing.refusal_no_hostile())
			return {"ok": false, "line": last_ack}
		target_name = target.display_name
	wing.order = new_order
	if wing == player_wing():
		orders_given += 1
	refresh(wing)
	_post(wing.ack_for(new_order, target_name))
	return {"ok": true, "line": last_ack}


## Changes `wing`'s (default: the player's) formation; the members take their new slots at once.
func set_formation(shape: Formation.Shape, wing: Wing = null) -> void:
	if wing == null:
		wing = player_wing()
	if wing == null:
		return
	wing.formation.shape = shape
	refresh(wing)


## The HUD's acknowledgement line: the latest one for `ACK_HOLD_S` after it was posted, then "".
func ack_text() -> String:
	return last_ack if _ack_age_s < ACK_HOLD_S else ""


## The hostile the leader of `wing` has selected, or null (none, not hostile, gone, or the leader is dead).
func leader_hostile_target(wing: Wing) -> Targetable:
	if not leader_alive(wing):
		return null
	var id: int = wing.leader.ship.targeting.selected_id()
	if id == 0 or not is_instance_id_valid(id):
		return null
	var target := instance_from_id(id) as Targetable
	if target == null or not target.is_active() or not Factions.is_hostile(wing.leader.faction, target.faction):
		return null
	return target


func leader_alive(wing: Wing) -> bool:
	var leader: Combatant = wing.leader
	return leader != null and is_instance_valid(leader.ship) and _in_play(leader)


## Whether a ship still counts for its wing (see `_in_play`).
static func is_in_play(c: Combatant) -> bool:
	return _in_play(c)


# Whether a ship still counts for its wing: active, or flying as a low-attention tier row (M4-T21) and not destroyed.
static func _in_play(c: Combatant) -> bool:
	if c.damageable == null:
		return false
	if c.damageable.is_active():
		return true
	return (
		is_instance_valid(c.ship) and c.ship.is_inside_tree() and c.ship.is_tier_parked()
		and not c.damageable.hull.destroyed
	)


## One row per member of `wing` (default: the player's), in slot order: `callsign`, `slot`, `hull` (0..1), `behaviour` and
## `state`. The console's `wing.members`.
func roster(wing: Wing = null) -> Array[Dictionary]:
	if wing == null:
		wing = player_wing()
	var out: Array[Dictionary] = []
	if wing == null:
		return out
	for member: Combatant in wing.members():
		var d: Dictionary = member.driver.brain.describe() if _pilot_of(member) != null else {}
		out.append({"callsign": member.display_name, "slot": wing.slot_of(member),
				"hull": member.damageable.hull.fraction() if member.damageable != null else 0.0,
				"behaviour": _activity(wing, member, d), "state": str(d.get("state", "none"))})
	return out


## The HUD roster of `wing` (default: the player's), one row per slot flown or lost, in slot order (M3-T11): `callsign`,
## `hull`, `behaviour`, `target` and `down`. A lost slot reads `down` under the callsign of the wingman that went down
## (M8-T13: the hole it left, at the back once the wing closed up) until a replacement takes it; a slot never flown is left out.
func hud_roster(wing: Wing = null) -> Array[Dictionary]:
	if wing == null:
		wing = player_wing()
	var out: Array[Dictionary] = []
	if wing == null:
		return out
	for slot: int in range(1, wing.size + 1):
		var member: Combatant = wing.member_at(slot)
		if member == null:
			if wing.is_lost(slot):
				out.append({"callsign": wing.lost_callsign(slot), "hull": 0.0, "behaviour": "", "target": "", "down": true})
			continue
		var d: Dictionary = member.driver.brain.describe() if _pilot_of(member) != null else {}
		out.append({"callsign": member.display_name,
				"hull": member.damageable.hull.fraction() if member.damageable != null else 0.0,
				"behaviour": _activity(wing, member, d), "target": str(d.get("target", "")), "down": false})
	return out


# What a roster row says a member is doing: its pilot's behaviour, or `docking` on its way to the docking bay and `docked`
# while it is inside (M8-T06), whatever the docking pilot flies meanwhile; `holding` while it is stopped under the order to
# hold position (M8-T19).
static func _activity(wing: Wing, member: Combatant, described: Dictionary) -> String:
	var docking: String = wing.dock_status(member)
	if not docking.is_empty():
		return docking
	var behaviour: String = str(described.get("behaviour", "none"))
	if wing.leader_away and (behaviour == "follow_path" or behaviour == "idle"):
		# Broken off while the leader docks, with nothing to fight: holding its fire, or standing by.
		return "holding" if wing.holds_fire() else "standing_by"
	return "holding" if str(described.get("state", "")) == "holding" else behaviour


func _physics_process(delta: float) -> void:
	_ack_age_s += delta
	for wing: Wing in wings:
		refresh(wing)


## Drops the members that are down and briefs the others (see the class notes). Runs every tick; public for the tests.
## The player is back after its death (M8-T17; maintainer, 2026-11-20: they fly back, no teleport): its wing drops whatever it
## was doing for the player (a jump's break-off) and is briefed under its order again, so its wingmen fly back to their slots
## round the respawned player as formation flies them (far off at the profile's cruise plus `FormationState`'s far extra,
## through the leader's link while it is out of sight).
func regroup(wing: Wing) -> void:
	if wing == null or wing.leader == null or not wing.leader.is_player:
		return
	wing.leader_away = false
	refresh(wing)


func refresh(wing: Wing) -> void:
	var shot_down: bool = false
	for member: Combatant in wing.members():
		if wing.is_away(member):
			continue  # docked for repair (M8-T06): out of play with its slot kept, not lost
		if _pilot_of(member) == null or not _in_play(member):
			var slot: int = wing.slot_of(member)
			remove_member(wing, member)
			wing.mark_lost(slot, member.display_name)
			shot_down = shot_down or (member.damageable != null and member.damageable.hull.destroyed)
	if shot_down:
		wing.close_gaps()  # the ones behind the hole move up; their new offsets go out below
	var alive: bool = leader_alive(wing)
	if not alive and (wing.leader == null or not wing.leader.is_player) and not wing.members().is_empty():
		_lead(wing, wing.members()[0])  # the lowest slot leads on
		alive = true
	# The player is docking (M8-T06): its wingmen break off. No leader to follow or form on, and the order `away_order` gives.
	var detached: bool = wing.leader_away and wing.leader != null and wing.leader.is_player
	if detached:
		alive = false
	var order: AiContext.Order = wing.away_order() if detached else wing.effective_order(alive)
	var leader_id: int = 0
	var target_id: int = 0
	var link: UniversePos = null
	var link_velocity := Vector3.ZERO
	if wing.leader != null and wing.leader.targetable != null and not detached:
		leader_id = wing.leader.targetable.get_instance_id()
	if alive:
		var ship: Ship = wing.leader.ship
		target_id = ship.targeting.selected_id()
		if world != null:
			link = world.to_universe(ship.global_position)
		link_velocity = ship.linear_velocity
	var ids := PackedInt64Array()
	if wing.leader != null and wing.leader.targetable != null and alive:
		ids.append(wing.leader.targetable.get_instance_id())
	for member: Combatant in wing.members():
		if member.targetable != null and not wing.is_away(member):
			ids.append(member.targetable.get_instance_id())
	var leader_pilot: AiPilot = _pilot_of(wing.leader) if alive else null
	if leader_pilot != null:
		_set_wing_ids(leader_pilot.context, ids, wing.leader)
	for member: Combatant in wing.members():
		if wing.is_away(member):
			continue
		var ctx: AiContext = _pilot_of(member).context
		_set_wing_ids(ctx, ids, member)
		ctx.order = order
		ctx.leader_id = leader_id
		ctx.leader_target_id = target_id
		ctx.engage_radius_m = wing.engage_radius_m
		ctx.has_slot = not detached
		ctx.slot_offset = wing.slot_offset(wing.slot_of(member))
		ctx.leader_link_position = link
		ctx.leader_link_velocity = link_velocity
		# An AI flight's wingmen cover their flight and stay near their lead; the player's own follow its orders.
		var ai_flight: bool = wing.flight > 0 and alive and not wing.leader.is_player
		ctx.cover = ai_flight
		ctx.cohesion_m = flight_rules.cohesion_m if ai_flight else 0.0
		ctx.rejoined_m = flight_rules.rejoined_m if ai_flight else 0.0
		# An evading wingman of a flight, or of a wing told to form up, turns back at the cohesion distance (M8-T06).
		var forming: bool = order == AiContext.Order.FORM_ON_ME or order == AiContext.Order.FORM_HOLD_FIRE
		ctx.leash_m = flight_rules.cohesion_m if ai_flight or (alive and forming) else 0.0
		# Far off its slot (a respawn, a gate, a recall) it closes fast and brakes in time (M8-T17).
		ctx.catch_up_m = flight_rules.catch_up_beyond_m
		ctx.catch_up_mps = minf(flight_rules.catch_up_mps, member.ship.spec.assist_speed_max_mps) if member.ship.spec != null \
				else flight_rules.catch_up_mps
		# FORM ON ME is weapons free near the player (M8-T13); not while the wing follows the player through a gate.
		var weapons_free: bool = order == AiContext.Order.FORM_ON_ME and alive and not wing.jumping
		ctx.form_engage_m = flight_rules.form_engage_m if weapons_free else 0.0
		ctx.form_leash_m = flight_rules.form_leash_m if weapons_free else 0.0
		ctx.form_off_slot_s = flight_rules.form_off_slot_s if weapons_free else 0.0
		if alive and wing.leader.is_player:
			member.ship.running_lights = wing.leader.ship.running_lights
	if leader_pilot != null and wing.flight > 0:
		_brief_flight_lead(wing, leader_pilot.context)


# A flight's AI lead (M8-T19): it covers its flight, and unless it is the squadron's own lead it holds a slot on that one
# while there is nothing to fight, so a squadron's flights form up together.
func _brief_flight_lead(wing: Wing, ctx: AiContext) -> void:
	ctx.cover = true
	ctx.order = wing.order
	var lead: Combatant = squadron_lead(wing.name)
	if lead == null or lead == wing.leader or lead.targetable == null:
		ctx.leader_id = 0
		ctx.has_slot = false
		ctx.leader_link_position = null
		return
	var first: int = 0
	for other: Wing in flights_of(wing.name):
		if other.leader == lead:
			first = other.flight
	var spread := Formation.new(wing.formation.shape, wing.formation.spacing_m * flight_rules.lead_spacing)
	ctx.leader_id = lead.targetable.get_instance_id()
	ctx.leader_target_id = lead.ship.targeting.selected_id()
	ctx.has_slot = true
	ctx.slot_offset = spread.offset(wing.flight - first)
	ctx.leader_link_position = world.to_universe(lead.ship.global_position) if world != null else null
	ctx.leader_link_velocity = lead.ship.linear_velocity


# `ids` without `self_ship`'s own.
static func _set_wing_ids(ctx: AiContext, ids: PackedInt64Array, self_ship: Combatant) -> void:
	var own: int = self_ship.targetable.get_instance_id() if self_ship.targetable != null else 0
	var mates := PackedInt64Array()
	for id: int in ids:
		if id != own:
			mates.append(id)
	ctx.wing_ids = mates  # assigned whole: the context notes the change for a pilot the host steps (M4-T35)


func _post(line: String) -> void:
	last_ack = line
	_ack_age_s = 0.0
	acknowledged.emit(line)


## The callsign for a newcomer to `slot`: that of the wingman whose loss left it empty (M8-T13: the survivors moved up and
## kept theirs), else the slot's own. If a ship in play carries it (a console `spawn ally`, a wingman that moved up): the
## first free number after the wing's own, so no two ships share a name.
func callsign_for(wing: Wing, slot: int) -> String:
	var lost: String = wing.lost_callsign(slot)
	if not lost.is_empty() and not _callsign_in_play(wing, lost):
		return lost
	var callsign: String = wing.callsign(slot)
	if not _callsign_in_play(wing, callsign):
		return callsign
	# An AI flight looks through its own numbers first; a wing the player leads past its own (the player is number 1).
	var ai_flight: bool = wing.flight > 0 and not (wing.leader != null and wing.leader.is_player)
	return pool.next_name(wing.name, wing.first_number if ai_flight else wing.size + ShipPool.ALLY_FIRST_NUMBER)


func _callsign_in_play(wing: Wing, callsign: String) -> bool:
	if wing.leader != null and wing.leader.display_name == callsign:
		return true
	for other: Combatant in pool.alive():
		if other.display_name == callsign:
			return true
	return false


# The number in `callsign` when it is one of `wing`'s own (`ALPHA 3` in ALPHA: 3), else `otherwise`.
static func _wing_number(wing: Wing, callsign: String, otherwise: int) -> int:
	var parsed: Array = Livery.parse_name(callsign)
	return int(parsed[1]) if String(parsed[0]).to_lower() == wing.name.to_lower() and int(parsed[1]) > 0 else otherwise


static func _pilot_of(member: Combatant) -> AiPilot:
	if member == null or member.driver == null:
		return null
	return member.driver.brain as AiPilot


# --- console -------------------------------------------------------------------------------------------------------


func _player_wing_name() -> String:
	var wing: Wing = player_wing()
	return wing.name if wing != null else ""


func _console_order() -> String:
	var wing: Wing = player_wing()
	return String(AiContext.order_word(wing.order)) if wing != null else ""


func _console_formation() -> String:
	var wing: Wing = player_wing()
	return String(wing.formation.shape_name()) if wing != null else ""


func _console_flights() -> PackedStringArray:
	var out := PackedStringArray()
	var own: Wing = player_wing()
	for wing: Wing in (flights_of(own.name) if own != null else [] as Array[Wing]):
		var names := PackedStringArray()
		for member: Combatant in wing.members():
			names.append(member.display_name)
		out.append("%d: %s + %s" % [wing.flight, wing.leader.display_name if wing.leader != null else "no lead",
				", ".join(names) if not names.is_empty() else "none"])
	return out


func _console_members() -> PackedStringArray:
	var out := PackedStringArray()
	for row: Dictionary in roster():
		out.append("%s %d%% %s (%s)" % [row["callsign"], roundi(float(row["hull"]) * 100.0), row["behaviour"], row["state"]])
	return out


# The order words in key order.
static func _order_words() -> PackedStringArray:
	var out := PackedStringArray()
	for order: AiContext.Order in ORDERS_BY_KEY:
		out.append(String(AiContext.order_word(order)))
	return out


func _value_words() -> PackedStringArray:
	var out: PackedStringArray = _order_words()
	out.append_array(PackedStringArray(Formation.NAMES))
	return out


func _cmd_wing(args: Dictionary) -> ConsoleResult:
	var wing: Wing = player_wing()
	if wing == null:
		return ConsoleResult.failure("there is no wing in this scenario")
	var what: Variant = args.get(&"what")
	var value: Variant = args.get(&"value")
	if what == null:
		var names := PackedStringArray()
		for member: Combatant in wing.members():
			names.append(member.display_name)
		return ConsoleResult.line("%s: order %s, formation %s, members %s" % [wing.name, AiContext.order_word(wing.order),
				wing.formation.shape_name(), ", ".join(names) if not names.is_empty() else "none"])
	if StringName(what) == &"replenish":
		if value != null:
			return ConsoleResult.failure("wing replenish takes no value, got '%s'" % value)
		return _cmd_replenish(wing)
	if StringName(what) == &"order":
		var words: PackedStringArray = _order_words()
		if value == null:
			return ConsoleResult.line("%s order: %s" % [wing.name, AiContext.order_word(wing.order)])
		var order: int = AiContext.order_from_word(String(value))
		if order < 0:
			return ConsoleResult.failure("wing order expects one of %s, got '%s'%s" % ["|".join(words), value,
					ConsoleFormat.did_you_mean(String(value), words)])
		var result: Dictionary = give_order(order as AiContext.Order, wing)
		return ConsoleResult.line(result["line"]) if bool(result["ok"]) else ConsoleResult.failure(result["line"])
	var shapes := PackedStringArray(Formation.NAMES)
	if value == null:
		return ConsoleResult.line("%s formation: %s" % [wing.name, wing.formation.shape_name()])
	var shape: int = Formation.shape_from_name(String(value))
	if shape < 0:
		return ConsoleResult.failure("wing formation expects one of %s, got '%s'%s" % ["|".join(shapes), value,
				ConsoleFormat.did_you_mean(String(value), shapes)])
	var before: StringName = wing.formation.shape_name()
	set_formation(shape as Formation.Shape, wing)
	return ConsoleResult.line("%s formation: %s -> %s" % [wing.name, before, wing.formation.shape_name()])


func _cmd_replenish(wing: Wing) -> ConsoleResult:
	refresh(wing)  # a wingman shot down a moment ago leaves its slot first
	if wing.empty_slots().is_empty():
		return ConsoleResult.line("%s: no empty slot" % wing.name)
	var launched: Array[Combatant] = replenish(wing)
	if launched.is_empty():
		return ConsoleResult.failure("%s: nothing launched (%s)" % [wing.name, _why_not_replenished(wing)])
	var names := PackedStringArray()
	for member: Combatant in launched:
		names.append(member.display_name)
	return ConsoleResult.line("%s: launched %s (%.0f m astern)" % [wing.name, ", ".join(names), REPLENISH_DISTANCE_M])


# Why `replenish` had nothing to launch, for the console.
func _why_not_replenished(wing: Wing) -> String:
	if pool == null or world == null or not is_inside_tree():
		return "no ship pool"
	if get_tree().paused:
		return "the game is paused"
	if not leader_alive(wing):
		return "the leader is down"
	if pool.free_count(ShipPool.ALLY_TYPE) == 0:
		return "no free allied ship: %d of %d in the pool are in use" % [pool.alive(ShipPool.ALLY_TYPE).size(),
				pool.pool_size(ShipPool.ALLY_TYPE)]
	return "no ship could join"
