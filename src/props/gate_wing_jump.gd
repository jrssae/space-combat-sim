class_name GateWingJump
extends RefCounted
## The player's wingmen when the player jumps through the gate (M8-T17; maintainer, 2026-11-20). Under FORM ON ME or FORM UP,
## HOLD FIRE they follow the player through: spared by its departure vortex from the start, flown in by the gate right behind
## the player, and brought out with the player, side by side, on the round trip. Those within `GateJump.FOLLOW_RANGE_M` of the
## mouth as the run-in starts count: the gate paces them in to cross the mouth `GateJump.FOLLOW_TRAIL_S` after the player, one
## `GateJump.FOLLOW_SPACING_S` apart, and the vortex is held open for them (`holding`, the jump's `HOLD` with the camera on the
## gate) until the last is through, or at once called off if one dies or the order changes; the others veer off. Under any other order
## the wing breaks off (`Wing.leader_away`, as while the player docks), keeps clear of the vortex like every AI pilot
## (`VortexKeepOuts`) and rejoins once the player is back. `JumpgateHost` calls it on `GateJump`'s events.

## The orders under which the wingmen go through with the player.
const FOLLOW_ORDERS: Array[AiContext.Order] = [AiContext.Order.FORM_ON_ME, AiContext.Order.FORM_HOLD_FIRE]
## Followers come out this far apart beside the player, alternating sides.
const ARRIVAL_SPREAD_M: float = 120.0
## While a follower is on its way the vortex is kept open at least this much longer, each tick.
const KEEP_OPEN_S: float = 1.0
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
## Followers carried through with the player so far, and holds called off early (readouts).
var carried: int = 0
var called_off: int = 0

var _sent_all: bool = false  # the followers were sent in (or let go) as the player crossed the mouth
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


## One tick of the jump: the followers are spared by the gate's vortex, and the hold called off when one of them dies or the
## wing's order changes.
func step() -> void:
	if gate == null or not is_instance_valid(gate) or followers.is_empty():
		return
	if gate.vortex.is_active():
		for member: Combatant in followers:
			if _usable(member) and not away.has(member):
				gate.vortex.spare(member.ship)
	if _sent_all:
		_watch_hold()


## The run-in starts, the player at the mouth in `eta_s`: the followers in range are handed to the gate, paced to trail the
## player through the mouth; the rest veer off.
func on_run_in(eta_s: float) -> void:
	if gate == null or not is_instance_valid(gate) or _sent_all:
		return
	var mouth: Vector3 = gate.vortex.true_frame().origin
	var at: float = SimClock.now() + maxf(eta_s, 0.0) + GateJump.FOLLOW_TRAIL_S
	for member: Combatant in followers.duplicate():
		if _usable(member) and member.ship.global_position.distance_to(mouth) <= GateJump.FOLLOW_RANGE_M:
			gate.vortex.spare(member.ship)
			gate.send_departure(member.ship, _through.bind(member), GateJump.SWALLOW_S, at)
			sent.append(member)
			at += GateJump.FOLLOW_SPACING_S
		else:
			_let_go(member)  # too far to wait for: it keeps clear and rejoins after
	_sent_all = true


## Whether the vortex is held for followers still on their way through.
func holding() -> bool:
	return not pending().is_empty()


## Whether this jump held the vortex for followers at all.
func held() -> bool:
	return not sent.is_empty()


## The followers sent in and not yet through.
func pending() -> Array[Combatant]:
	var out: Array[Combatant] = []
	for member: Combatant in sent:
		if not away.has(member) and _usable(member):
			out.append(member)
	return out


## The follower the hold's camera watches: the one still outside nearest the mouth (the next to go in), else the one in the
## funnel (null when none is left).
func lead() -> Combatant:
	var best: Combatant = null
	var best_to_go: float = INF
	var frame: Transform3D = gate.vortex.true_frame() if is_instance_valid(gate) else Transform3D.IDENTITY
	for member: Combatant in pending():
		if not member.ship.visible:
			continue
		var local: Vector3 = frame.affine_inverse() * member.ship.global_position
		var to_go: float = local.length() if local.z < 0.0 else 1.0e6 + local.z  # one already in the funnel only when none is outside
		if to_go < best_to_go:
			best = member
			best_to_go = to_go
	return best


## The last follower still outside the funnel, farthest from the mouth (the lead when none is), for a take framing them all.
func last() -> Combatant:
	var best: Combatant = null
	var best_d: float = -1.0
	var frame: Transform3D = gate.vortex.true_frame() if is_instance_valid(gate) else Transform3D.IDENTITY
	for member: Combatant in pending():
		var local: Vector3 = frame.affine_inverse() * member.ship.global_position
		if member.ship.visible and local.z < 0.0 and local.length() > best_d:
			best = member
			best_d = local.length()
	return best if best != null else lead()


## The cut to black before the arrival (the hold ran out): a follower already in the funnel goes now, nobody sees it; one still
## outside stays behind.
func take_rest() -> void:
	var transits: VortexTransits = VortexTransits.of(main.world) if main != null else null
	for member: Combatant in pending():
		var inside: bool = transits != null and transits.is_passing(member.ship)
		if is_instance_valid(gate):
			gate.cancel_departure(member.ship)
		if inside:
			_take_away(member)
		else:
			_let_go(member)


# A follower died or the order no longer follows while the vortex is held: nobody else is waited for, the vortex closes.
func _watch_hold() -> void:
	var lost: bool = false
	for member: Combatant in sent:
		if not away.has(member) and not _usable(member):
			lost = true
	if not lost and (wing == null or follows(wing.order)):
		if holding():
			gate.vortex.extend(KEEP_OPEN_S)
		else:
			_close_behind()
		return
	called_off += 1
	var transits: VortexTransits = VortexTransits.of(main.world)
	for member: Combatant in sent.duplicate():
		if away.has(member):
			continue
		if is_instance_valid(member) and is_instance_valid(member.ship):
			var inside: bool = transits != null and transits.is_passing(member.ship)
			gate.cancel_departure(member.ship)
			if not inside:
				_let_go(member)  # still outside: it keeps clear of the closing vortex
		sent.erase(member)
	_close_behind()


# The last follower is through (or nobody is waited for any more): the departure vortex folds now, its closing sweep at its end.
func _close_behind() -> void:
	var v: JumpVortex = gate.vortex
	if v.is_active() and v.direction == JumpVortex.Direction.DEPARTURE and v.passing == 0 and gate.departing() == 0:
		v.close()


# A follower that does not go through after all: no longer spared, so it keeps clear like every AI pilot.
func _let_go(member: Combatant) -> void:
	followers.erase(member)
	if _usable(member) and is_instance_valid(gate):
		gate.vortex.unspare(member.ship)


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
	sent.clear()  # out again: nobody is waited for any more


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
	_sent_all = false
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
