class_name Wing
extends RefCounted
## A leader and the ships flying with it (architecture §16 D36, M3-T07): which member flies which slot of the formation,
## the wing's order and the acknowledgement lines. Pure: members are `Combatant` handles, never read here. The
## `WingDirector` owns the wings, applies their order and slots to the members' `AiContext`s every tick and drops members
## that are down.
##
## Slots: 0 is the leader; members fly 1..`size` (`Formation.offset`). Callsigns number them from the leader:
## `callsign(0)` is ALPHA 1 (the player), slot 1 ALPHA 2 and so on. The order (`AiContext.Order`, default COVER ME) holds
## for every member while the leader lives; while it is dead the wing engages at will (`effective_order`) and resumes
## the order when it is back.
##
## Gaps (M8-T13): `close_gaps` gives the wing the shape its count of ships would have built joining one by one: the
## members behind an empty slot move up their arm and the arms are evened after. The director calls it when a member is
## destroyed, so losses leave no hole; a pilot keeps its callsign when it moves, and the callsign of the one that went down
## goes with the empty slot to the back (`lost_callsign`).

const DEFAULT_NAME: String = "ALPHA"
## Members besides the leader: three wingmen in a finger-four (maintainer Q4).
const DEFAULT_SIZE: int = 3
## What a member says to each order (by `AiContext.Order` value); ATTACK MY TARGET names the target.
const ORDER_PHRASES: Array[String] = ["ENGAGING AT WILL", "ATTACKING %s", "FORMING UP", "COVERING YOU"]

var name: String = DEFAULT_NAME
var leader: Combatant = null
var formation: Formation = Formation.new()
var order: AiContext.Order = AiContext.Order.COVER_ME
## COVER ME engages hostiles within this of the leader.
var engage_radius_m: float = AiContext.DEFAULT_ENGAGE_RADIUS_M
## Member slots (1..size).
var size: int = DEFAULT_SIZE

# By slot - 1; null for an empty slot.
var _by_slot: Array[Combatant] = []
# By slot - 1: the callsign of the member that went down, while nobody has taken its place (the HUD roster's DOWN); "" otherwise.
var _lost: Array[String] = []
# Whether `close_gaps` has nothing to do: the members and the shape are as it last left them.
var _closed: bool = false
var _closed_shape: Formation.Shape = Formation.Shape.FINGER_FOUR


func _init(p_name: String = DEFAULT_NAME, p_leader: Combatant = null, p_size: int = DEFAULT_SIZE) -> void:
	name = p_name
	leader = p_leader
	size = maxi(p_size, 0)
	_by_slot.resize(size)
	_lost.resize(size)
	_lost.fill("")


## Puts `member` in `slot` (1..size), or for -1 in the empty slot that keeps the arms even (`fill_order`). Returns the slot, or -1 when the slot is taken or
## out of range, the wing is full, or `member` is null, the leader or already a member.
func add_member(member: Combatant, slot: int = -1) -> int:
	if member == null or member == leader or slot_of(member) > 0:
		return -1
	if slot == -1:
		var free: PackedInt32Array = fill_order()
		if free.is_empty():
			return -1
		slot = free[0]
	if slot < 1 or slot > size or _by_slot[slot - 1] != null:
		return -1
	_by_slot[slot - 1] = member
	_lost[slot - 1] = ""
	_closed = false
	return slot


## Changes the number of member slots to `new_size`, keeping every member in its slot (a station wing launched for the
## player's wing makes room for the rest of the wing, M7-T58). Returns false, changing nothing, when a slot it would cut is flown.
func resize(new_size: int) -> bool:
	new_size = maxi(new_size, 0)
	for i: int in range(new_size, size):
		if _by_slot[i] != null:
			return false
	_by_slot.resize(new_size)
	_lost.resize(new_size)  # new slots come as "": not lost
	size = new_size
	_closed = false  # the centre slot goes with the size
	return true


## Takes `member` out of its slot. Returns whether it was a member.
func remove_member(member: Combatant) -> bool:
	var slot: int = slot_of(member)
	if slot < 1:
		return false
	_by_slot[slot - 1] = null
	_closed = false
	return true


## Marks an empty `slot` lost: its member, called `lost_name` (default: the slot's callsign), went down. `add_member` clears
## the mark. Ignored for a slot out of range or flown.
func mark_lost(slot: int, lost_name: String = "") -> void:
	if slot >= 1 and slot <= size and _by_slot[slot - 1] == null:
		_lost[slot - 1] = lost_name if not lost_name.is_empty() else callsign(slot)


## Whether a member went down and `slot` is the empty place it left the wing with.
func is_lost(slot: int) -> bool:
	return slot >= 1 and slot <= size and not _lost[slot - 1].is_empty()


## The callsign of the member whose loss left `slot` empty, or "" when the slot is not lost.
func lost_callsign(slot: int) -> String:
	return _lost[slot - 1] if slot >= 1 and slot <= size else ""


## `member`'s slot (1..size), or -1.
func slot_of(member: Combatant) -> int:
	if member == null:
		return -1
	var i: int = _by_slot.find(member)
	return i + 1 if i >= 0 else -1


## The member in `slot`, or null (an empty slot, or slot 0: the leader is `leader`).
func member_at(slot: int) -> Combatant:
	return _by_slot[slot - 1] if slot >= 1 and slot <= size else null


## The members, in slot order.
func members() -> Array[Combatant]:
	var out: Array[Combatant] = []
	for member: Combatant in _by_slot:
		if member != null:
			out.append(member)
	return out


## The slots nobody flies, ascending.
func empty_slots() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i: int in size:
		if _by_slot[i] == null:
			out.append(i + 1)
	return out


## The empty slots in the order newcomers should take them (M7-T74): each on the arm with fewer ships, nearest the leader
## first, the centre slot last, so the V stays balanced and nobody already flying has to move.
func fill_order() -> PackedInt32Array:
	var balance: int = 0  # ships on the right arm less those on the left
	for i: int in size:
		if _by_slot[i] != null:
			balance += formation.side(i + 1, size)
	var free: Array[int] = []
	free.assign(empty_slots())
	var out := PackedInt32Array()
	while not free.is_empty():
		var best: int = 0
		for j: int in range(1, free.size()):
			if _fills_before(free[j], free[best], balance):
				best = j
		var slot: int = free[best]
		free.remove_at(best)
		balance += formation.side(slot, size)
		out.append(slot)
	return out


# Whether empty slot `a` should be filled before `b` with the arms at `balance`: the centre last, then the one leaving the arms
# more even, then the one nearer the leader, then the lower slot.
func _fills_before(a: int, b: int, balance: int) -> bool:
	var better: int = _better_place(a, b, balance)
	return better > 0 if better != 0 else a < b


# Which of slots `a` and `b` is the better place for one more ship with the arms at `balance`: 1 for `a`, -1 for `b`, 0 when
# they are as good as each other (mirror slots of even arms).
func _better_place(a: int, b: int, balance: int) -> int:
	var a_side: int = formation.side(a, size)
	var b_side: int = formation.side(b, size)
	if (a_side == 0) != (b_side == 0):
		return 1 if b_side == 0 else -1
	var a_skew: int = absi(balance + a_side)
	var b_skew: int = absi(balance + b_side)
	if a_skew != b_skew:
		return 1 if a_skew < b_skew else -1
	var a_depth: float = formation.offset(a, size).length_squared()
	var b_depth: float = formation.offset(b, size).length_squared()
	if a_depth != b_depth:
		return 1 if a_depth < b_depth else -1
	return 0


## Closes the holes losses left (M8-T13), so the wing flies the shape its count would have built by `fill_order`. First the
## members behind an empty slot move up their own arm, keeping their order, so nobody crosses the V for a hole on its side.
## Then, while a ship would be better placed in the first slot a newcomer would take (an arm two longer than the other, the
## centre slot flown beside an open arm slot), the worst placed one moves there. Mirror slots count as equal, so a wing that
## is already even stays as it is. Returns the moves in order, each (from, to).
func close_gaps() -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	if _closed and _closed_shape == formation.shape:
		return moves
	_closed = true
	_closed_shape = formation.shape
	for arm_side: int in [-1, 1]:
		var arm: PackedInt32Array = _arm_slots(arm_side)
		var next: int = 0
		for slot: int in arm:
			if _by_slot[slot - 1] == null:
				continue
			if arm[next] != slot:
				_move(slot, arm[next], moves)
			next += 1
	for _i: int in size:  # every move puts a ship in a better place, so this many is the most there can be
		var free: PackedInt32Array = fill_order()
		var from: int = _worst_placed(free[0]) if not free.is_empty() else 0
		if from == 0:
			break
		_move(from, free[0], moves)
	return moves


# The slots on one side of the leader (-1 left, 1 right), nearest the leader first.
func _arm_slots(arm_side: int) -> PackedInt32Array:
	var slots: Array[int] = []
	for slot: int in range(1, size + 1):
		if formation.side(slot, size) == arm_side:
			slots.append(slot)
	slots.sort_custom(func(a: int, b: int) -> bool:
		var a_depth: float = formation.offset(a, size).length_squared()
		var b_depth: float = formation.offset(b, size).length_squared()
		return a_depth < b_depth if a_depth != b_depth else a < b)
	return PackedInt32Array(slots)


# The flown slot whose ship should move to empty slot `to`, or 0 when every ship is placed as well as it would be there: the
# centre slot before an arm's, then the one furthest from the leader.
func _worst_placed(to: int) -> int:
	var balance: int = 0
	for i: int in size:
		if _by_slot[i] != null:
			balance += formation.side(i + 1, size)
	var worst: int = 0
	for slot: int in range(1, size + 1):
		if _by_slot[slot - 1] == null or _better_place(to, slot, balance - formation.side(slot, size)) <= 0:
			continue
		if worst == 0 or _moves_before(slot, worst):
			worst = slot
	return worst


# Whether the ship in flown slot `a` should give up its place before the one in `b`.
func _moves_before(a: int, b: int) -> bool:
	var a_centre: bool = formation.side(a, size) == 0
	if a_centre != (formation.side(b, size) == 0):
		return a_centre
	var a_depth: float = formation.offset(a, size).length_squared()
	var b_depth: float = formation.offset(b, size).length_squared()
	return a_depth > b_depth if a_depth != b_depth else a > b


# Moves the member in `from` to empty slot `to`. The lost mark goes the other way: the hole is now where the ship came from.
func _move(from: int, to: int, moves: Array[Vector2i]) -> void:
	_by_slot[to - 1] = _by_slot[from - 1]
	_by_slot[from - 1] = null
	_lost[from - 1] = _lost[to - 1]
	_lost[to - 1] = ""
	moves.append(Vector2i(from, to))


func is_full() -> bool:
	return empty_slots().is_empty()


## The callsign of a slot: the wing's name and the slot counted from the leader (slot 0 = `ALPHA 1`).
func callsign(slot: int) -> String:
	return "%s %d" % [name, slot + 1]


## A slot's offset from the leader in the leader's body frame (`formation`, for this wing's size).
func slot_offset(slot: int) -> Vector3:
	return formation.offset(slot, size)


## The order the members fly: `order` while the leader lives, ENGAGE AT WILL while it is dead.
func effective_order(leader_alive: bool) -> AiContext.Order:
	return order if leader_alive else AiContext.Order.ENGAGE_AT_WILL


## Who answers for the wing: the member in the lowest slot, or the wing's name when it has none.
func speaker() -> String:
	var list: Array[Combatant] = members()
	return list[0].display_name if not list.is_empty() else name


## The one line acknowledging `new_order` (`ALPHA 2: COPY, FORMING UP`); `target_name` for ATTACK MY TARGET. A wing
## without members says so (`ALPHA: NO WINGMEN`).
func ack_for(new_order: AiContext.Order, target_name: String = "") -> String:
	if members().is_empty():
		return "%s: NO WINGMEN" % name
	var phrase: String = ORDER_PHRASES[new_order]
	if new_order == AiContext.Order.ATTACK_MY_TARGET:
		phrase = phrase % (target_name if not target_name.is_empty() else "YOUR TARGET")
	return "%s: COPY, %s" % [speaker(), phrase]


## The line refusing ATTACK MY TARGET while the leader has no hostile selected.
func refusal_no_hostile() -> String:
	return "%s: UNABLE, NO HOSTILE SELECTED" % speaker()
