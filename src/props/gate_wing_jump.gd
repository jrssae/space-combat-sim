class_name GateWingJump
extends RefCounted
## The player's wingmen when the player jumps through the gate (M8-T17; maintainer, 2026-11-20). Under FORM ON ME or FORM UP,
## HOLD FIRE they follow the player through: spared by its departure vortex from the start, flown in by the gate right behind
## the player, carried away in the black and brought out with the player, side by side, on the round trip. Under any other order
## the wing breaks off (`Wing.leader_away`, as while the player docks), keeps clear of the vortex like every AI pilot
## (`VortexKeepOuts`) and rejoins once the player is back. `JumpgateHost` calls it on `GateJump`'s events.

## The orders under which the wingmen go through with the player.
const FOLLOW_ORDERS: Array[AiContext.Order] = [AiContext.Order.FORM_ON_ME, AiContext.Order.FORM_HOLD_FIRE]
## Followers come out this far apart beside the player, alternating sides.
const ARRIVAL_SPREAD_M: float = 120.0
## At the cut to black a follower still this near the gate goes through with the player; one farther stays behind and rejoins.
const TAKE_WITHIN_M: float = 4000.0
## Where a follower waits while away: behind the gate, beside the player's own wait, this far apart.
const PARK_SPACING_M: float = 300.0

var main: Main = null
var gate: Jumpgate = null
var wing: Wing = null
## The wingmen going through with the player, those sent into the funnel and those carried away (hidden, waiting).
var followers: Array[Combatant] = []
var sent: Array[Combatant] = []
var away: Array[Combatant] = []
## Whether the wing broke off for this jump (an order that does not follow).
var detached: bool = false
## Followers carried through with the player so far (a readout).
var carried: int = 0

var _kept: Dictionary = {}  # follower -> {layer, mask, tier_exempt} while it is away


## Whether a wing under `order` goes through the gate with its leader.
static func follows(order: AiContext.Order) -> bool:
	return FOLLOW_ORDERS.has(order)


## The jump starts: the player's wing either follows or breaks off.
func begin(p_main: Main, p_gate: Jumpgate) -> void:
	finish()
	main = p_main
	gate = p_gate
	wing = main.wings.player_wing() if main.wings != null else null
	if wing == null or wing.leader != main.combatant:
		wing = null
		return
	if not follows(wing.order):
		detached = true
		wing.leader_away = true
		main.wings.refresh(wing)
		return
	for member: Combatant in wing.members():
		if _usable(member) and wing.dock_status(member).is_empty():
			followers.append(member)


## One tick of the jump: the followers are spared by the gate's vortex, and sent in once the player is in the funnel.
func step() -> void:
	if gate == null or not is_instance_valid(gate) or followers.is_empty():
		return
	if gate.vortex.is_active():
		for member: Combatant in followers:
			if _usable(member) and not away.has(member):
				gate.vortex.spare(member.ship)
	var transits: VortexTransits = VortexTransits.of(main.world)
	if not sent.is_empty() or transits == null or not transits.is_passing(main.ship):
		return
	for member: Combatant in followers:
		if _usable(member):
			sent.append(member)
			gate.send_departure(member.ship, _through.bind(member), GateJump.SWALLOW_S)


## The cut to black before the arrival: a follower still on its way through goes now (nobody sees it), one far off stays.
func take_rest() -> void:
	for member: Combatant in followers:
		if away.has(member) or not _usable(member):
			continue
		if is_instance_valid(gate):
			gate.cancel_departure(member.ship)
		if sent.has(member) and member.ship.global_position.distance_to(gate.global_position) <= TAKE_WITHIN_M:
			_take_away(member)


## The player is coming out of the arrival: the followers come out beside it, the same way.
func bring_out() -> void:
	var k: int = 0
	for member: Combatant in away:
		if not is_instance_valid(member) or not is_instance_valid(member.ship):
			continue
		var side: float = -1.0 if k % 2 == 0 else 1.0
		var offset := Vector3(side * ARRIVAL_SPREAD_M * float(floori(k / 2.0) + 1), 0.0, 0.0)
		_restore(member, gate.arrival_transform(offset), gate.arrival_velocity() + main.world.rest_velocity())
		gate.bring_through(member.ship, true, GateJump.BURST_OUT_S)
		carried += 1
		k += 1
	away.clear()


## The jump is over (or called off): the wing is the player's again under its own order.
func finish() -> void:
	for member: Combatant in sent:
		if not away.has(member) and _usable(member) and is_instance_valid(gate):
			gate.cancel_departure(member.ship)
	for member: Combatant in away:  # never brought out (the jump ended early): back at the gate's way out, in sight
		if is_instance_valid(member) and is_instance_valid(member.ship) and is_instance_valid(gate):
			_restore(member, gate.arrival_transform(), gate.arrival_velocity() + main.world.rest_velocity())
	if detached and wing != null:
		wing.leader_away = false
		main.wings.refresh(wing)
	followers.clear()
	sent.clear()
	away.clear()
	_kept.clear()
	detached = false
	wing = null


# A follower through the ring (or taken in the black): hidden, touching nothing, at rest behind the gate, its slot kept.
func _through(_body: Node3D, member: Combatant) -> void:
	_take_away(member)


func _take_away(member: Combatant) -> void:
	if away.has(member) or not _usable(member):
		return
	var ship: Ship = member.ship
	_kept[member] = {"layer": ship.collision_layer, "mask": ship.collision_mask, "tier": ship.tier_exempt}
	ship.collision_layer = 0
	ship.collision_mask = 0
	ship.tier_exempt = true
	if member.driver != null:
		member.driver.in_passage = true  # nobody flies it while it is away
	ship.set_flight_command(FlightCommand.new())
	ship.set_combat_command(CombatCommand.new())
	var park := Vector3(PARK_SPACING_M * float(away.size() + 1), 0.0, JumpgateHost.PARK_BEHIND_M)
	ship.reset_to(Transform3D(ship.global_basis, gate.global_transform * park))
	ship.linear_velocity = main.world.rest_velocity()
	ship.visible = false
	wing.set_away(member, true)
	away.append(member)


# Back in play as before `_take_away`, at `xform` flying at `velocity`.
func _restore(member: Combatant, xform: Transform3D, velocity: Vector3) -> void:
	var ship: Ship = member.ship
	var kept: Dictionary = _kept.get(member, {})
	if not kept.is_empty():
		ship.collision_layer = int(kept["layer"])
		ship.collision_mask = int(kept["mask"])
		ship.tier_exempt = bool(kept["tier"])
	ship.reset_to(xform)
	ship.linear_velocity = velocity
	ship.visible = true
	ship.reset_physics_interpolation()
	if member.driver != null:
		member.driver.in_passage = false
	if wing != null:
		wing.set_away(member, false)
	_kept.erase(member)


func _usable(member: Combatant) -> bool:
	return is_instance_valid(member) and is_instance_valid(member.ship) and member.ship.is_inside_tree() \
			and (member.damageable == null or not member.damageable.hull.destroyed)
