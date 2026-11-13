class_name BattleArrivals
extends RefCounted
## How a battle's ships come in (M6-T20, AC13): every ship of the plan arrives out of a jump point, in waves of at most a pool's
## worth of points. Pure and seeded by the plan alone: the same plan always gives the same points and times.
##
## Points: the group rule of `JumpPointPool` (ships of one side and one fight within `SHARE_M` of the point's first ship come out
## of it together); a capital opens its own. Waves bring whole fights, the player's first: the points are taken in fight order,
## `max_points` to a wave. The first wave opens at once (the battle's start); each later one a point's whole life after the one
## before, its points spread over `SPREAD_S`, so the pool never holds more than `max_points` open and none is taken back early.
## A battle small enough for one wave places every ship at the start, as before (the seeded weapon battle's recording relies on it).
##
## Who opens the points (M6-T23): only a capital can. Each fighter group comes through a capital's point of its side arriving in
## the same wave within `CAPITAL_NEAR_M` of it (the nearest with room: a capital brings `GROUPS_PER_CAPITAL` groups), coming in
## with that capital; a group with no such capital comes through the battle's jumpgate. So the pool opens one point per capital,
## never more than `max_points` a wave; a group's unit still counts toward its wave, so the waves keep T20's pace.

const SHARE_M: float = JumpPointPool.SHARE_M
## A later wave's points open one after another over this long, so a tick brings a few ships, not hundreds.
const SPREAD_S: float = 1.0
## Between the last point of a wave closing and the next wave's first opening.
const MARGIN_S: float = 0.5
## How each unit comes in: a capital out of its own point, a fighter group through a capital's, or through the jumpgate.
const VIA_OWN: StringName = &"own"
const VIA_CAPITAL: StringName = &"capital"
const VIA_GATE: StringName = &"gate"
## A fighter group rides a capital's point only from this close: its own fight's capitals (5 km behind it, 2.5 km to the side),
## never the next fight's (8 km on).
const CAPITAL_NEAR_M: float = 6000.0
## The fighter groups one capital brings through its point (the rest of its fight's groups take the gate).
const GROUPS_PER_CAPITAL: int = 1

## Each unit: `members` (plan indices, the first opens it), `fight` (its ships' fight), `capital` (a capital's own), `side`,
## `wave`, `at_s` (sim seconds after the start), `via` (`VIA_OWN`, `VIA_CAPITAL` or `VIA_GATE`) and `rides` (for `VIA_CAPITAL`,
## the unit of the capital whose point it comes through; -1 otherwise). Only `VIA_OWN` units open a point of the pool.
var points: Array[Dictionary] = []
## The point each plan entry comes out of.
var entry_point := PackedInt32Array()
var waves: int = 0
## Seconds from one wave to the next.
var period_s: float = 0.0
## How long one point is open, flash to closing flash.
var life_s: float = 0.0


## The arrivals of `entries` (a `BenchLayout.plan`) for a pool of `max_points`, each point held open `hold_s`.
static func plan(entries: Array[Dictionary], max_points: int = JumpPointPool.MAX_POINTS,
		hold_s: float = VortexTiming.DEFAULT_HOLD_S) -> BattleArrivals:
	var out := BattleArrivals.new()
	out.life_s = VortexTiming.new(hold_s).done_at_s()
	out.period_s = out.life_s + SPREAD_S + MARGIN_S
	out.entry_point.resize(entries.size())
	var made: Array[Dictionary] = []
	for i: int in entries.size():
		var e: Dictionary = entries[i]
		var capital: bool = StringName(e["kind"]) == BenchLayout.KIND_CAPITAL
		var joined: int = -1
		if not capital:
			for p: int in made.size():
				var point: Dictionary = made[p]
				if not bool(point["capital"]) and int(point["side"]) == int(e["side"]) and int(point["fight"]) == int(e["group"]) \
						and (point["at"] as Vector3).distance_to(e["offset"] as Vector3) < SHARE_M:
					joined = p
					break
		if joined < 0:
			made.append({"members": PackedInt32Array(), "fight": int(e["group"]), "side": int(e["side"]), "capital": capital,
					"at": e["offset"] as Vector3, "order": made.size()})
			joined = made.size() - 1
		var members: PackedInt32Array = made[joined]["members"]
		members.append(i)
		made[joined]["members"] = members  # a packed array is copied out of a dictionary
	made.sort_custom(_fight_order)
	var cap: int = maxi(max_points, 1)
	out.waves = ceili(float(made.size()) / float(cap))
	var units: Array[Dictionary] = []
	for p: int in made.size():
		var wave: int = p / cap
		var in_wave: int = mini(cap, made.size() - wave * cap)
		var at_s: float = 0.0 if wave == 0 else wave * out.period_s + SPREAD_S * float(p - wave * cap) / float(in_wave)
		var capital: bool = made[p]["capital"]
		units.append({"members": made[p]["members"], "fight": made[p]["fight"], "capital": capital, "side": made[p]["side"],
				"wave": wave, "at_s": at_s, "via": VIA_OWN if capital else VIA_GATE, "rides": -1, "at": made[p]["at"], "order": p})
	_ride_capitals(units)
	units.sort_custom(_open_order)  # a group riding a capital comes in with it
	var index_of: Dictionary = {}
	for p: int in units.size():
		index_of[int(units[p]["order"])] = p
	for p: int in units.size():
		var unit: Dictionary = units[p]
		if int(unit["rides"]) >= 0:
			unit["rides"] = index_of[int(unit["rides"])]
		unit.erase("at")
		unit.erase("order")
		out.points.append(unit)
		for member: int in unit["members"] as PackedInt32Array:
			out.entry_point[member] = p
	return out


# Gives each fighter group the nearest capital point of its side in its wave within reach that still has room; it then comes in
# when that capital does. `rides` holds the capital's `order` until the units are sorted.
static func _ride_capitals(units: Array[Dictionary]) -> void:
	var room: Dictionary = {}  # capital order -> groups it can still bring
	for unit: Dictionary in units:
		if bool(unit["capital"]):
			room[int(unit["order"])] = GROUPS_PER_CAPITAL
	for unit: Dictionary in units:
		if bool(unit["capital"]):
			continue
		var best: Dictionary = {}
		var best_m: float = CAPITAL_NEAR_M
		for other: Dictionary in units:
			if not bool(other["capital"]) or int(other["side"]) != int(unit["side"]) or int(other["wave"]) != int(unit["wave"]) \
					or int(room[int(other["order"])]) <= 0:
				continue
			var d: float = (other["at"] as Vector3).distance_to(unit["at"] as Vector3)
			if d <= best_m:
				best_m = d
				best = other
		if best.is_empty():
			continue
		room[int(best["order"])] = int(room[int(best["order"])]) - 1
		unit["via"] = VIA_CAPITAL
		unit["rides"] = int(best["order"])
		unit["at_s"] = best["at_s"]


static func _open_order(a: Dictionary, b: Dictionary) -> bool:
	if float(a["at_s"]) != float(b["at_s"]):
		return float(a["at_s"]) < float(b["at_s"])
	return int(a["order"]) < int(b["order"])


## When the last point opens, s after the start (0 for a single wave).
func last_at_s() -> float:
	return float(points[-1]["at_s"]) if not points.is_empty() else 0.0


## The plan entries that come in at the start, in plan order.
func first_wave_entries() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i: int in entry_point.size():
		if int(points[entry_point[i]]["wave"]) == 0:
			out.append(i)
	return out


## Units that come in each way (`VIA_OWN`, `VIA_CAPITAL`, `VIA_GATE`), and the ships each brings.
func count_via(via: StringName) -> int:
	var n: int = 0
	for point: Dictionary in points:
		n += 1 if StringName(point["via"]) == via else 0
	return n


func ships_via(via: StringName) -> int:
	var n: int = 0
	for point: Dictionary in points:
		n += (point["members"] as PackedInt32Array).size() if StringName(point["via"]) == via else 0
	return n


## The most points of the pool open at any one time over the whole arrival (only capitals open one).
func max_open() -> int:
	var events: Array[Vector2] = []  # (time, +1 opening or -1 done); a close before an opening at the same time
	for point: Dictionary in points:
		if StringName(point["via"]) != VIA_OWN:
			continue
		events.append(Vector2(float(point["at_s"]), 1.0))
		events.append(Vector2(float(point["at_s"]) + life_s, -1.0))
	events.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	var open: int = 0
	var most: int = 0
	for event: Vector2 in events:
		open += int(event.y)
		most = maxi(most, open)
	return most


static func _fight_order(a: Dictionary, b: Dictionary) -> bool:
	if int(a["fight"]) != int(b["fight"]):
		return int(a["fight"]) < int(b["fight"])
	return int(a["order"]) < int(b["order"])
