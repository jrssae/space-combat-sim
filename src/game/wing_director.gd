class_name WingDirector
extends Node
## Owns the wings and carries their orders to the pilots (architecture §16 D36, §16.3, M3-T07). `Combat/WingDirector` in the
## main scene, `process_physics_priority` 290: after the resolvers (a member destroyed this tick is already down) and before
## the waves (300).
##
## Every tick, for every wing (`refresh`): members whose hull is down or whose ship left play (`Damageable.is_active`), or
## that no longer fly an `AiPilot`, leave their slot. Then each member's `AiContext` gets the wing's view: the order it flies
## (`Wing.effective_order`: engage at will while the leader is dead), the leader's `Targetable` id and selected target, the
## engage radius, its slot offset in the current formation, and the link to the leader (universe position and velocity),
## which a member beyond sensor range flies on. The pilots read them on their next tick.
##
## Members: `add_member` takes a ship in play whose driver flies an `AiPilot` and gives the pilot the formation behaviour
## when it has none; `remove_member` gives the ship back its own orders (engage at will, no slot).
##
## Orders (`give_order`) come from `UiCommand` edges (keys 1-4, through `Main`) and the console, never from `Input`. An
## order changes the wing's order, and with it every member's at once, and posts one acknowledgement line
## (`acknowledged`, `last_ack`; `ack_text` is the HUD's line, shown for `ACK_HOLD_S` of sim time). ATTACK MY TARGET is
## refused, with a line saying so, while the leader has no hostile selected; the order then stays as it was.
##
## Replenish (maintainer Q8, AC11): `replenish` gives every empty slot of the player's wing an allied Starfury from the pool
## (`ShipPool.ALLY_TYPE`), `Wing.callsign(slot)` by name, `REPLENISH_DISTANCE_M` behind the leader along its nose axis (the body
## frame's +Z, as the formation's slots are; its velocity can be zero or point anywhere) in the slot's lane, at the leader's
## velocity, on the `ally_starfury` profile and the wing's current order. `Main` calls it on `WaveDirector.wave_started`
## (`on_wave_started`). It refreshes the wing first, so a wingman shot down in the very tick the wave starts counts as an empty
## slot whoever calls it, in the physics order or not. It launches nothing while the leader is down or the game is paused, and fills what the pool can: one warning
## when it falls short, none when the scenario pools no allies. A callsign already carried by a ship in play (a console `spawn
## ally`) is not given twice: that slot takes the next free number after the wing's own.
##
## Console (§16.4), for the player's wing (`player_wing`): provider `wing` (`name`, `order`, `formation`, `members`,
## `last_ack`) and `wing [order|formation|replenish] [value]`.

## A new acknowledgement (or refusal) line.
signal acknowledged(line: String)

const ACK_HOLD_S: float = 3.0
const PRIORITY: int = 290
const WHAT_CHOICES: Array[StringName] = [&"order", &"formation", &"replenish"]
## Replacements enter this far behind the leader.
const REPLENISH_DISTANCE_M: float = 1500.0
const REPLENISH_PROFILE: String = "ally_starfury"
## The orders in key order (1-4), as the console lists them.
const ORDERS_BY_KEY: Array[AiContext.Order] = [AiContext.Order.ATTACK_MY_TARGET, AiContext.Order.FORM_ON_ME,
		AiContext.Order.ENGAGE_AT_WILL, AiContext.Order.COVER_ME]

var world: WorldFrame = null
## Where replacements come from (`ShipPool.ALLY_TYPE` ships); null: `replenish` launches nothing.
var pool: ShipPool = null
var wings: Array[Wing] = []
## The latest acknowledgement or refusal line ("" before the first order).
var last_ack: String = ""

var _ack_age_s: float = INF
# Replacements launched so far: part of each one's brain seed, so a run repeats.
var _launched: int = 0


func _init() -> void:
	process_physics_priority = PRIORITY


func _ready() -> void:
	DebugConsole.registry.register_provider(&"wing", ConsoleVars.new({
		&"name": {"get": func() -> String: return _player_wing_name(), "doc": "The player's wing"},
		&"order": {"get": _console_order, "doc": "Its order: attack (my target), form (on me), engage (at will) or cover (me)"},
		&"formation": {"get": _console_formation, "doc": "Its formation: finger_four, wedge or line_abreast"},
		&"members": {"get": _console_members, "doc": "Each member: callsign, hull %, behaviour (state)"},
		&"last_ack": {"get": func() -> String: return last_ack, "doc": "The latest acknowledgement line"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"wing",
			"Order the player's wing (wing order attack|form|engage|cover), change its formation (wing formation finger_four|wedge|line_abreast) or launch replacements for its empty slots from the pool (wing replenish); alone, show the wing",
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


## The wing the player leads, else the first wing, else null.
func player_wing() -> Wing:
	for wing: Wing in wings:
		if wing.leader != null and wing.leader.is_player:
			return wing
	return wings[0] if not wings.is_empty() else null


## Puts a ship in play into `slot` of `wing` (-1: the first empty one) and briefs its pilot at once. Returns the slot, or -1
## when the wing refuses it (`Wing.add_member`), it does not fly an `AiPilot`, or it is not in play (spawn or acquire it
## first: `refresh` would drop it at once).
func add_member(wing: Wing, member: Combatant, slot: int = -1) -> int:
	var pilot: AiPilot = _pilot_of(member)
	if wing == null or pilot == null or member.damageable == null or not member.damageable.is_active():
		return -1
	var at: int = wing.add_member(member, slot)
	if at < 0:
		return -1
	if pilot.behaviour(&"formation") == null:
		pilot.add_behaviour(BehaviourFormation.new(pilot.profile))
	refresh(wing)
	return at


## Gives every empty slot of `wing` (default: the player's) a replacement from the ally pool and returns the ships launched,
## lowest slot first (see the class notes). `Main` calls it when a wave starts; the console's `wing replenish` calls it too.
func replenish(wing: Wing = null) -> Array[Combatant]:
	var launched: Array[Combatant] = []
	if wing == null:
		wing = player_wing()
	if wing == null or pool == null or world == null or not is_inside_tree() or get_tree().paused:
		return launched
	refresh(wing)  # a wingman shot down this very tick is an empty slot already
	var empty: PackedInt32Array = wing.empty_slots()
	if empty.is_empty() or not leader_alive(wing) or pool.pool_size(ShipPool.ALLY_TYPE) == 0:
		return launched
	var leader: Ship = wing.leader.ship
	var basis: Basis = leader.global_basis.orthonormalized()
	var velocity: Vector3 = leader.linear_velocity
	# Positions are taken now, as universe positions, and used at once: nothing here outlives the call (a rebase moves the origin).
	var anchor: UniversePos = world.to_universe(leader.global_position)
	for slot: int in empty:
		if pool.free_count(ShipPool.ALLY_TYPE) == 0:
			break
		var lane: Vector3 = wing.slot_offset(slot)
		var at: UniversePos = anchor.plus_local(basis * Vector3(lane.x, lane.y, REPLENISH_DISTANCE_M))
		var callsign: String = _callsign_for(wing, slot)
		var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": REPLENISH_PROFILE,
				"orders": String(AiContext.order_word(wing.order))}, at, hash([callsign, _launched]))
		if not bool(made["ok"]):
			push_warning("WingDirector: replenish: %s" % made["error"])
			break
		var ally: Combatant = pool.acquire(callsign, at, basis, velocity, made["brain"] as PilotBrain, ShipPool.ALLY_TYPE)
		if ally == null:
			break
		if add_member(wing, ally, slot) != slot:
			pool.release(ally)  # not in play after all; leave the slot for the next call
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


## Gives `wing` (default: the player's) a new order and posts its one acknowledgement line. Returns `{"ok", "line"}`;
## ATTACK MY TARGET without a hostile selected by the leader is refused (`ok` false, the order unchanged, the refusal is
## the line posted).
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
	return leader != null and leader.damageable != null and is_instance_valid(leader.ship) and leader.damageable.is_active()


## One row per member of `wing` (default: the player's), in slot order: `callsign`, `slot`, `hull` (0..1), `behaviour`
## and `state` (its brain's `describe`). The console's `wing.members`; the HUD roster's data (M3-T11).
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
				"behaviour": str(d.get("behaviour", "none")), "state": str(d.get("state", "none"))})
	return out


## The HUD roster of `wing` (default: the player's), one row per slot in slot order (M3-T11): `callsign`, `hull` (0..1),
## `behaviour` and `target` (its pilot's, "" when none) and `down`. A slot whose member was shot down reads `down` with
## its slot's callsign until a replacement takes it; a slot never flown is left out.
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
				out.append({"callsign": wing.callsign(slot), "hull": 0.0, "behaviour": "", "target": "", "down": true})
			continue
		var d: Dictionary = member.driver.brain.describe() if _pilot_of(member) != null else {}
		out.append({"callsign": member.display_name,
				"hull": member.damageable.hull.fraction() if member.damageable != null else 0.0,
				"behaviour": str(d.get("behaviour", "none")), "target": str(d.get("target", "")), "down": false})
	return out


func _physics_process(delta: float) -> void:
	_ack_age_s += delta
	for wing: Wing in wings:
		refresh(wing)


## Drops the members that are down and briefs the others (see the class notes). Runs every tick; public for the tests.
func refresh(wing: Wing) -> void:
	for member: Combatant in wing.members():
		if _pilot_of(member) == null or member.damageable == null or not member.damageable.is_active():
			var slot: int = wing.slot_of(member)
			remove_member(wing, member)
			wing.mark_lost(slot)  # shot down: the slot reads DOWN on the HUD until a replacement takes it
	var alive: bool = leader_alive(wing)
	var order: AiContext.Order = wing.effective_order(alive)
	var leader_id: int = 0
	var target_id: int = 0
	var link: UniversePos = null
	var link_velocity := Vector3.ZERO
	if wing.leader != null and wing.leader.targetable != null:
		leader_id = wing.leader.targetable.get_instance_id()
	if alive:
		var ship: Ship = wing.leader.ship
		target_id = ship.targeting.selected_id()
		if world != null:
			link = world.to_universe(ship.global_position)
		link_velocity = ship.linear_velocity
	for member: Combatant in wing.members():
		var ctx: AiContext = _pilot_of(member).context
		ctx.order = order
		ctx.leader_id = leader_id
		ctx.leader_target_id = target_id
		ctx.engage_radius_m = wing.engage_radius_m
		ctx.has_slot = true
		ctx.slot_offset = wing.slot_offset(wing.slot_of(member))
		ctx.leader_link_position = link
		ctx.leader_link_velocity = link_velocity


func _post(line: String) -> void:
	last_ack = line
	_ack_age_s = 0.0
	acknowledged.emit(line)


# The slot's callsign, unless a ship in play carries it (a console `spawn ally`, say): then the first free number after the wing's
# own, so no two ships answer to one name and the callsigns of the slots still to be filled stay free.
func _callsign_for(wing: Wing, slot: int) -> String:
	var callsign: String = wing.callsign(slot)
	var taken: bool = wing.leader != null and wing.leader.display_name == callsign
	for other: Combatant in pool.alive():
		taken = taken or other.display_name == callsign
	return pool.next_name(wing.name, wing.size + ShipPool.ALLY_FIRST_NUMBER) if taken else callsign


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


func _console_members() -> PackedStringArray:
	var out := PackedStringArray()
	for row: Dictionary in roster():
		out.append("%s %d%% %s (%s)" % [row["callsign"], roundi(float(row["hull"]) * 100.0), row["behaviour"], row["state"]])
	return out


# The order words in key order: attack, form, engage, cover.
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
