class_name AiContext
extends RefCounted
## What an `AiPilot`'s behaviours decide from (architecture §16 D34): this tick's `Perception`, what the wing tells the
## pilot, and lists derived once per tick so behaviours do not each walk the contacts.
##
## One context per pilot, kept across ticks. The wing fields (`order`, `leader_id`, `leader_target_id`, `engage_radius_m`,
## the slot, the leader link) are set from outside (`WingDirector`, `BrainFactory`) and stay until changed.
##
## Objective (M3-T17, Q21): one target by display name (`objective_name`), set by `ai <name> objective`, a spawn's
## `objective` or (M5) a mission script. Attack flies to it from any broadcast range and attacks it once near, whatever
## its faction (a raider sent at a buoy).
##
## Guard post (M3-T10): while the post is known (`guarding`), `may_attack` also needs the hostile inside the post's radius
## or the guarded ship to have it selected, whatever the order.
##
## Orders gate what may be attacked (`may_attack`), so behaviours ask the context instead of reading the order:
## - ENGAGE_AT_WILL (default, and a ship without a wing): any hostile ship.
## - ATTACK_MY_TARGET: only the leader's selected target; nothing while it has none.
## - FORM_ON_ME: nothing, and no retreat (`may_retreat`). An evasion is still allowed.
## - COVER_ME: defend the leader: hostiles within `engage_radius_m` of it, while within `COVER_LEASH_M` of it. With no
##   leader at all, engage at will.

enum Order { ENGAGE_AT_WILL, ATTACK_MY_TARGET, FORM_ON_ME, COVER_ME }

## Order words (scenario `orders`, the console's `wing order`), by `Order` value.
const ORDER_WORDS: Array[StringName] = [&"engage", &"attack", &"form", &"cover"]
const DEFAULT_ENGAGE_RADIUS_M: float = 2000.0
## Under COVER ME a ship farther than this from its leader breaks off and rejoins (the engage radius plus 1 km of room).
const COVER_LEASH_M: float = 3000.0

var profile: AiProfile = null
## This tick's perception (the pilot's own; read, never write).
var perception: Perception = Perception.new()

## Wing (set from outside the brain). Every field a native slot mirrors marks the context changed (`_changed`), so a pilot the
## host steps without a GDScript think (M4-T35) pushes it at the next batch; assign `wing_ids` whole, never edit it in place.
var order: Order = Order.ENGAGE_AT_WILL:
	set(value):
		order = value
		_changed()
## The leader's `Targetable` id (`Contact.id`), 0 for none.
var leader_id: int = 0:
	set(value):
		leader_id = value
		_changed()
## The target the leader has selected (a `Contact.id`), 0 for none.
var leader_target_id: int = 0:
	set(value):
		leader_target_id = value
		_changed()
var engage_radius_m: float = DEFAULT_ENGAGE_RADIUS_M:
	set(value):
		engage_radius_m = value
		_changed()
## The formation slot (M3-T07) and its offset from the leader in the leader's body frame (`Formation.offset`).
var has_slot: bool = false:
	set(value):
		has_slot = value
		_changed()
## m, x right, y up, +z behind.
var slot_offset: Vector3 = Vector3.ZERO:
	set(value):
		slot_offset = value
		_changed()
## The `Targetable` ids of this ship's wingmates, leader included, itself not (M3-T10, `BehaviourRally`); empty outside a wing.
var wing_ids: PackedInt64Array = PackedInt64Array():
	set(value):
		wing_ids = value
		_changed()
## The wing's link to its leader (M3-T07), World frame, null without a live leader. Used while the leader is beyond
## sensor range; in sight, its contact (with attitude) is used instead.
var leader_link_position: UniversePos = null:
	set(value):
		leader_link_position = value
		_changed()
var leader_link_velocity: Vector3 = Vector3.ZERO:
	set(value):
		leader_link_velocity = value
		_changed()
## The route this pilot leads (M3-T09, the instructor; `BehaviourFollowPath.attach` sets it), or null.
var route: Route = null:
	set(value):
		route = value
		_changed()
## The last target attack flew at, kept while other behaviours fly (M3-T18). Evade uses it to tell its own target's fire
## from everyone else's.
var attack_target_id: int = 0
## The target selected last tick (`AiPilot.wanted_target_id`), for a rammer's pick.
var current_target_id: int = 0
## The objective's display name ("NAV ALPHA", compared case-insensitively), "" for none (M3-T17).
var objective_name: String = "":
	set(value):
		objective_name = value
		_changed()
## The guard post (M3-T10): a fixed point, or a ship by display name with an offset in its body frame, and the radius.
var guard_post: UniversePos = null:
	set(value):
		guard_post = value
		_changed()
var guard_name: String = "":
	set(value):
		guard_name = value
		_changed()
var guard_offset: Vector3 = Vector3.ZERO:
	set(value):
		guard_offset = value
		_changed()
var guard_radius_m: float = 1500.0:
	set(value):
		guard_radius_m = value
		_changed()
## The pilot whose native slot mirrors this context (M4-T35), set when the slot is made; the batch asks it to push a changed
## context when the host steps its driver. Held weakly: the pilot owns this context, and a strong back-reference kept
## every pilot and context alive to the end of the process (CI's "instances leaked at exit").
var native_pilot: AiPilot:
	set(value):
		_native_pilot = weakref(value) if value != null else null
	get:
		return _native_pilot.get_ref() as AiPilot if _native_pilot != null else null
var _native_pilot: WeakRef = null
# The contexts changed since the last batch took them (M4-T35).
static var _dirty: Array[AiContext] = []
var _dirty_listed: bool = false

## Derived each tick by `refresh`: the leader (null when not in sight), hostile ships in sensor range with their offsets
## (World frame) and ranges at the same index, and the ids of this ship and every friendly contact.
var leader: Contact = null
var hostiles: Array[Contact] = []
var hostile_offsets: PackedVector3Array = PackedVector3Array()
var hostile_ranges: PackedFloat64Array = PackedFloat64Array()
var friendly_ids: PackedInt64Array = PackedInt64Array()
## The objective's contact this tick (near first, then broadcast), null while it is not seen or heard; and its range, m.
var objective: Contact = null
var objective_range_m: float = INF
## The native brain this pilot thinks in (M4-T17), null on the GDScript path: a behaviour asked from outside between thinks
## (`BehaviourRam.commit`) goes through it, since the lists below are not refreshed on the native path.
var native_host: Object = null
var native_slot: int = -1
## The guard post this tick: where (World), how fast it moves, and the guarded ship's contact (null for a fixed post).
var guarding: bool = false
var guard_point: Vector3 = Vector3.ZERO
var guard_velocity: Vector3 = Vector3.ZERO
var guarded: Contact = null


## The `Order` for a word of `ORDER_WORDS`, or -1.
static func order_from_word(word: String) -> int:
	return ORDER_WORDS.find(StringName(word.to_lower()))


static func order_word(value: Order) -> StringName:
	return ORDER_WORDS[value]


## Takes this tick's perception and rebuilds the derived lists. Always in GDScript: the native split (`kernels::pilot::
## context_lists`, M4-T16) costs more to hand back than this short loop, so it waits for T17's native brains, which read
## it without crossing into GDScript.
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


## The contacts this pilot keeps beyond its nearest k (M4-T04): its wingmates, its leader and the leader's target, its own
## targets and the route's pace ship.
func keep_ids() -> PackedInt64Array:
	var ids: PackedInt64Array = wing_ids.duplicate()
	for id: int in [leader_id, leader_target_id, current_target_id, attack_target_id]:
		if id > 0:
			ids.append(id)
	if route != null and route.pace_id != 0:
		ids.append(route.pace_id)
	return ids


## The names it keeps the same way: the objective and the guarded ship.
func keep_names() -> PackedStringArray:
	var names := PackedStringArray()
	if not objective_name.is_empty():
		names.append(objective_name)
	if not guard_name.is_empty():
		names.append(guard_name)
	return names


## Back to a ship without a wing (the wing fields only).
func clear_wing() -> void:
	order = Order.ENGAGE_AT_WILL
	leader_id = 0
	leader_target_id = 0
	engage_radius_m = DEFAULT_ENGAGE_RADIUS_M
	has_slot = false
	slot_offset = Vector3.ZERO
	leader_link_position = null
	leader_link_velocity = Vector3.ZERO
	wing_ids = PackedInt64Array()


## The contexts changed since the last call, each once; the list starts afresh (M4-T35, `BrainBatch`).
static func take_changed() -> Array[AiContext]:
	var out: Array[AiContext] = _dirty
	_dirty = []
	for ctx: AiContext in out:
		ctx._dirty_listed = false
	return out


# Lists this context for the next batch's push (once until taken).
func _changed() -> void:
	if not _dirty_listed:
		_dirty_listed = true
		_dirty.append(self)


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


## Whether the orders let this pilot attack a hostile it sees now (the formation stands aside then).
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
