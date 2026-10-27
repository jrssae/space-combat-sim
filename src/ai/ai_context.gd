class_name AiContext
extends RefCounted
## What an `AiPilot`'s behaviours decide from (architecture §16 D34): this tick's `Perception` plus what the pilot's wing
## tells it, and a few lists derived from the contacts once per tick so every behaviour does not walk them again.
##
## One context per pilot, kept across ticks: `AiPilot.think` calls `refresh(p)` with the tick's perception; the wing fields
## (`order`, `leader_id`, `leader_target_id`, `engage_radius_m`, the slot and the leader link) are set from outside the
## brain (M3-T07's `WingDirector`; `BrainFactory`'s `orders`) and stay until changed. Later tasks add their own fields here
## the same way: the guard post (T10); the route (`route`, T09).
##
## Orders gate what may be attacked (`may_attack`), so a behaviour that attacks asks the context instead of reading the
## order itself:
## - ENGAGE_AT_WILL (the default, and a ship without a wing): any hostile ship.
## - ATTACK_MY_TARGET: only the leader's selected target (`leader_target_id`); nothing while it has none.
## - FORM_ON_ME: nothing, and no retreat either (`may_retreat`): formation only, though an evasion is still allowed.
## - COVER_ME: hostiles within `engage_radius_m` of the leader, or whose selected target is the leader. A ship that cannot
##   see its leader (none, or beyond sensor range) engages at will.

enum Order { ENGAGE_AT_WILL, ATTACK_MY_TARGET, FORM_ON_ME, COVER_ME }

## Order words (scenario `orders`, the console's `wing order`), by `Order` value.
const ORDER_WORDS: Array[StringName] = [&"engage", &"attack", &"form", &"cover"]
const DEFAULT_ENGAGE_RADIUS_M: float = 2000.0

var profile: AiProfile = null
## This tick's perception (the pilot's own; read, never write).
var perception: Perception = Perception.new()

## Wing (set from outside the brain).
var order: Order = Order.ENGAGE_AT_WILL
## The leader's `Targetable` id (`Contact.id`), 0 for none.
var leader_id: int = 0
## The target the leader has selected (a `Contact.id`), 0 for none.
var leader_target_id: int = 0
var engage_radius_m: float = DEFAULT_ENGAGE_RADIUS_M
## The formation slot (M3-T07): whether this pilot has one, and its offset from the leader in the leader's body frame
## (`Formation.offset`).
var has_slot: bool = false
## m, x right, y up, +z behind.
var slot_offset: Vector3 = Vector3.ZERO
## The wing's link to its leader (M3-T07): where the leader is (null when it has no live leader) and how fast it moves
## (World frame), as of the `WingDirector`'s last tick. The formation flies on it when the leader is beyond sensor range;
## in sight, the leader's contact (this tick, with its attitude) is used instead.
var leader_link_position: UniversePos = null
var leader_link_velocity: Vector3 = Vector3.ZERO
## The route this pilot leads (M3-T09, the instructor; `BehaviourFollowPath.attach` sets it), or null.
var route: Route = null

## Derived each tick by `refresh`: the leader among the friendly contacts (null when not in sight), the hostile ships in
## sensor range with, by the same index, the offset from this ship to each (World frame) and its length, and the ids of
## this ship and of every friendly contact (the targets that count as "a friend" being attacked).
var leader: Contact = null
var hostiles: Array[Contact] = []
var hostile_offsets: PackedVector3Array = PackedVector3Array()
var hostile_ranges: PackedFloat64Array = PackedFloat64Array()
var friendly_ids: PackedInt64Array = PackedInt64Array()


## The `Order` for a word of `ORDER_WORDS`, or -1.
static func order_from_word(word: String) -> int:
	return ORDER_WORDS.find(StringName(word.to_lower()))


static func order_word(value: Order) -> StringName:
	return ORDER_WORDS[value]


## Takes this tick's perception and rebuilds the derived lists (reusing their storage).
func refresh(p: Perception) -> void:
	perception = p
	leader = null
	hostiles.clear()
	hostile_offsets.clear()
	hostile_ranges.clear()
	friendly_ids.clear()
	if p.self_id != 0:
		friendly_ids.append(p.self_id)
	var own_position: Vector3 = p.position
	for c: Contact in p.contacts:
		var relation: Factions.Relation = c.relation
		if relation == Factions.Relation.HOSTILE:
			if c.is_ship:
				hostiles.append(c)
				var offset: Vector3 = c.position - own_position
				hostile_offsets.append(offset)
				hostile_ranges.append(offset.length())
		elif relation == Factions.Relation.FRIENDLY:
			friendly_ids.append(c.id)
			if c.id == leader_id:
				leader = c


## Back to a ship without a wing: engage at will, no leader, no slot, no link (the wing fields only).
func clear_wing() -> void:
	order = Order.ENGAGE_AT_WILL
	leader_id = 0
	leader_target_id = 0
	engage_radius_m = DEFAULT_ENGAGE_RADIUS_M
	has_slot = false
	slot_offset = Vector3.ZERO
	leader_link_position = null
	leader_link_velocity = Vector3.ZERO


## Whether the orders let this pilot attack `c` (a hostile ship).
func may_attack(c: Contact) -> bool:
	if c == null or not c.is_ship or c.relation != Factions.Relation.HOSTILE:
		return false
	match order:
		Order.FORM_ON_ME:
			return false
		Order.ATTACK_MY_TARGET:
			return leader_target_id != 0 and c.id == leader_target_id
		Order.COVER_ME:
			if leader == null:
				return true
			return c.target_id == leader_id \
					or c.position.distance_squared_to(leader.position) <= engage_radius_m * engage_radius_m
	return true


## Whether the orders let this pilot attack any hostile ship it sees now (the formation stands aside then).
func has_attackable() -> bool:
	match order:
		Order.FORM_ON_ME:
			return false
		Order.ENGAGE_AT_WILL:
			return not hostiles.is_empty()
	for c: Contact in hostiles:
		if may_attack(c):
			return true
	return false


## Whether the orders let this pilot retreat: not under FORM_ON_ME (formation only; an evasion is still allowed).
func may_retreat() -> bool:
	return order != Order.FORM_ON_ME


## Seconds since this hull was last hit (INF before the first hit).
func seconds_since_hit() -> float:
	return perception.now_s - perception.last_hit_s
