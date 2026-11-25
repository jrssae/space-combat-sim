class_name CapitalWithdraw
extends RefCounted
## Where a capital ship withdraws to (M10-T16, D12.10): through its own jump point when it can open one, else a friendly
## departure point within `FRIENDLY_POINT_M`, else the nearest jumpgate, else nowhere (it fights on). Per event: once when
## its brain asks. Pure but for the point it opens and the departure it books.

## How far a friendly departure point may be to be worth flying to, m.
const FRIENDLY_POINT_M: float = 20000.0
const VIA_NONE: StringName = &"none"
const VIA_OWN_POINT: StringName = &"own_point"
const VIA_FRIENDLY_POINT: StringName = &"friendly_point"
const VIA_GATE: StringName = &"gate"


## Books `ship`'s way out and returns `{via, at}` (`at` the universe point its helm flies for, null for none). `pool` opens its
## own point; `on_through(ship)` runs once it is through.
static func find_exit(ship: CapitalShip, world: WorldFrame, pool: JumpPointPool, on_through: Callable) -> Dictionary:
	var none: Dictionary = {"via": VIA_NONE, "at": null}
	if ship == null or world == null:
		return none
	var carriers: CarrierJumps = CarrierJumps.attach(world)
	if ship.can_open_jump_point() and ship.jump_drive.is_ready(SimClock.now()):
		var own: JumpVortex = ship.open_own_point(pool, JumpVortex.Direction.DEPARTURE)
		if own != null:
			carriers.send_departure(ship, own, on_through)
			return {"via": VIA_OWN_POINT, "at": world.to_universe(_inside(own))}
	var friendly: JumpVortex = _friendly_point(ship, world, pool, carriers)
	if friendly != null:
		carriers.send_departure(ship, friendly, on_through)
		return {"via": VIA_FRIENDLY_POINT, "at": world.to_universe(_inside(friendly))}
	var gate: Jumpgate = _nearest_gate(ship, world)
	if gate != null:
		gate.send_departure(ship, on_through)
		return {"via": VIA_GATE, "at": world.to_universe(gate.global_position)}
	return none


# The far end of a point's funnel, World: what a ship flies for to go through it.
static func _inside(point: JumpVortex) -> Vector3:
	return point.true_frame() * Vector3(0.0, 0.0, point.fit.depth_m)


# The nearest open departure point a friendly ship holds within reach.
static func _friendly_point(ship: CapitalShip, world: WorldFrame, pool: JumpPointPool, carriers: CarrierJumps) -> JumpVortex:
	var candidates: Array[JumpVortex] = carriers.held_departures()
	if pool != null:
		candidates.append_array(pool.points())
	var best: JumpVortex = null
	var best_d: float = FRIENDLY_POINT_M
	for point: JumpVortex in candidates:
		if point == null or not is_instance_valid(point) or not point.is_active() or not point.held:
			continue
		if point.direction != JumpVortex.Direction.DEPARTURE or point.opener == null or not is_instance_valid(point.opener):
			continue
		var opener_side: StringName = point.opener.get("faction") if point.opener.get("faction") != null else &""
		if opener_side.is_empty() or Factions.relation(ship.faction, opener_side) != Factions.Relation.FRIENDLY:
			continue
		var d: float = ship.global_position.distance_to(point.true_frame().origin)
		if d < best_d:
			best_d = d
			best = point
	return best


static func _nearest_gate(ship: CapitalShip, world: WorldFrame) -> Jumpgate:
	var best: Jumpgate = null
	for node: Node in ship.get_tree().get_nodes_in_group(Jumpgate.GROUP):
		var gate := node as Jumpgate
		if gate == null or not gate.is_inside_tree() or gate.vortex == null or not world.is_ancestor_of(gate):
			continue
		if best == null or ship.global_position.distance_squared_to(gate.global_position) \
				< ship.global_position.distance_squared_to(best.global_position):
			best = gate
	return best
