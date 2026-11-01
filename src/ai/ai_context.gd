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
## The objective (M3-T17, Q21): one target by display name (`objective_name`), set by `ai <name> objective <target|none>`, a
## spawn's `objective` or (M5) a mission script. `refresh` finds it among the near contacts, then the broadcasts; the attack
## flies to it from any broadcast range and attacks it once near, whatever its faction (a raider sent at a buoy).
##
## A guard post (M3-T10, `BehaviourGuard`): a fixed `guard_post` or the ship `guard_name` (its slot `guard_offset`, body frame)
## and `guard_radius_m`. While the post is known this tick (`guarding`), `may_attack` also requires the hostile to be inside
## the radius of it (`guard_point`) or to have the guarded ship selected, whatever the order.
##
## Orders gate what may be attacked (`may_attack`), so a behaviour that attacks asks the context instead of reading the
## order itself:
## - ENGAGE_AT_WILL (the default, and a ship without a wing): any hostile ship.
## - ATTACK_MY_TARGET: only the leader's selected target (`leader_target_id`); nothing while it has none.
## - FORM_ON_ME: nothing, and no retreat either (`may_retreat`): formation only, though an evasion is still allowed.
## - COVER_ME: stay with the leader and defend it: hostiles within `engage_radius_m` of it, while within `COVER_LEASH_M`
##   of it. A ship with no leader at all engages at will.

enum Order { ENGAGE_AT_WILL, ATTACK_MY_TARGET, FORM_ON_ME, COVER_ME }

## Order words (scenario `orders`, the console's `wing order`), by `Order` value.
const ORDER_WORDS: Array[StringName] = [&"engage", &"attack", &"form", &"cover"]
const DEFAULT_ENGAGE_RADIUS_M: float = 2000.0
## Under COVER ME a ship farther than this from its leader breaks off and rejoins (the engage radius plus 1 km of room).
const COVER_LEASH_M: float = 3000.0

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
## The `Targetable` ids of this ship's wingmates, leader included, itself not (M3-T10, `BehaviourRally`); empty outside a wing.
var wing_ids: PackedInt64Array = PackedInt64Array()
## The wing's link to its leader (M3-T07): where the leader is (null when it has no live leader) and how fast it moves
## (World frame), as of the `WingDirector`'s last tick. The formation flies on it when the leader is beyond sensor range;
## in sight, the leader's contact (this tick, with its attitude) is used instead.
var leader_link_position: UniversePos = null
var leader_link_velocity: Vector3 = Vector3.ZERO
## The route this pilot leads (M3-T09, the instructor; `BehaviourFollowPath.attach` sets it), or null.
var route: Route = null
## The last target the attack behaviour flew at (kept while other behaviours fly, 0 before the first): evade's awareness tells
## its own target's fire from everyone else's (M3-T18).
var attack_target_id: int = 0
## The target the pilot's behaviour in control wanted selected last tick (`AiPilot.wanted_target_id`), for a rammer's pick.
var current_target_id: int = 0
## The objective's display name ("NAV ALPHA", compared case-insensitively), "" for none (M3-T17).
var objective_name: String = ""
## The guard post (M3-T10): a fixed point, or a ship by display name with an offset in its body frame, and the radius.
var guard_post: UniversePos = null
var guard_name: String = ""
var guard_offset: Vector3 = Vector3.ZERO
var guard_radius_m: float = 1500.0

## Derived each tick by `refresh`: the leader among the friendly contacts (null when not in sight), the hostile ships in
## sensor range with, by the same index, the offset from this ship to each (World frame) and its length, and the ids of
## this ship and of every friendly contact (the targets that count as "a friend" being attacked).
var leader: Contact = null
var hostiles: Array[Contact] = []
var hostile_offsets: PackedVector3Array = PackedVector3Array()
var hostile_ranges: PackedFloat64Array = PackedFloat64Array()
var friendly_ids: PackedInt64Array = PackedInt64Array()
## The objective's contact this tick (near first, then broadcast), null while it is not seen or heard; and its range, m.
var objective: Contact = null
var objective_range_m: float = INF
## The guard post this tick: whether there is one, where (World) and how fast it moves, and the guarded ship's contact (null
## for a fixed post).
var guarding: bool = false
var guard_point: Vector3 = Vector3.ZERO
var guard_velocity: Vector3 = Vector3.ZERO
var guarded: Contact = null


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
	_refresh_guard(p)
	objective = null
	objective_range_m = INF
	if not objective_name.is_empty():
		objective = _named(p.contacts, objective_name)
		if objective == null:
			objective = _named(p.broadcasts, objective_name)
		if objective != null:
			objective_range_m = objective.position.distance_to(own_position)


func _refresh_guard(p: Perception) -> void:
	guarded = null
	guarding = false
	if not guard_name.is_empty():
		guarded = _named(p.contacts, guard_name)
		if guarded == null:
			return  # out of sight: no post this tick
		var right: Vector3 = guarded.forward.cross(guarded.up)
		guard_point = guarded.position + right * guard_offset.x + guarded.up * guard_offset.y - guarded.forward * guard_offset.z
		guard_velocity = guarded.velocity
		guarding = true
	elif guard_post != null:
		guard_point = p.to_local(guard_post)
		guard_velocity = Vector3.ZERO
		guarding = true


## Whether `c` is inside the guard zone: within the radius of the post, or with the guarded ship selected.
func in_guard_zone(c: Contact) -> bool:
	if guarded != null and c.target_id == guarded.id:
		return true
	return c.position.distance_squared_to(guard_point) <= guard_radius_m * guard_radius_m


static func _named(contacts: Array[Contact], wanted: String) -> Contact:
	for c: Contact in contacts:
		if c.name.length() == wanted.length() and c.name.nocasecmp_to(wanted) == 0:
			return c
	return null


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
	wing_ids.clear()


## Whether the orders let this pilot attack `c` (a hostile ship).
func may_attack(c: Contact) -> bool:
	if c == null or not c.is_ship or c.relation != Factions.Relation.HOSTILE:
		return false
	if guarding and not in_guard_zone(c):
		return false
	match order:
		Order.FORM_ON_ME:
			return false
		Order.ATTACK_MY_TARGET:
			return leader_target_id != 0 and c.id == leader_target_id
		Order.COVER_ME:
			if leader == null:
				return leader_link_position == null  # leader out of sight: rejoin before fighting
			if perception.position.distance_squared_to(leader.position) > COVER_LEASH_M * COVER_LEASH_M:
				return false
			return c.position.distance_squared_to(leader.position) <= engage_radius_m * engage_radius_m
	return true


## Whether the orders let this pilot attack any hostile ship it sees now (the formation stands aside then).
func has_attackable() -> bool:
	match order:
		Order.FORM_ON_ME:
			return false
		Order.ENGAGE_AT_WILL:
			if not guarding:
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
