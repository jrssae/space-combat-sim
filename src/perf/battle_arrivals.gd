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

const SHARE_M: float = JumpPointPool.SHARE_M
## A later wave's points open one after another over this long, so a tick brings a few ships, not hundreds.
const SPREAD_S: float = 1.0
## Between the last point of a wave closing and the next wave's first opening.
const MARGIN_S: float = 0.5

## Each point: `members` (plan indices, the first opens it), `fight` (its ships' fight), `capital` (a capital's own),
## `wave` and `at_s` (sim seconds after the start).
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
	for p: int in made.size():
		var wave: int = p / cap
		var in_wave: int = mini(cap, made.size() - wave * cap)
		var at_s: float = 0.0 if wave == 0 else wave * out.period_s + SPREAD_S * float(p - wave * cap) / float(in_wave)
		var point: Dictionary = {"members": made[p]["members"], "fight": made[p]["fight"], "capital": made[p]["capital"],
				"wave": wave, "at_s": at_s}
		out.points.append(point)
		for member: int in point["members"] as PackedInt32Array:
			out.entry_point[member] = p
	return out


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


## The most points open at any one time over the whole arrival.
func max_open() -> int:
	var events: Array[Vector2] = []  # (time, +1 opening or -1 done); a close before an opening at the same time
	for point: Dictionary in points:
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
