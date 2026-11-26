class_name LinerSchedule
extends RefCounted
## When the Asimov liners call at Babylon 5 in free flight (M10-T53, Q85): the wait from one visit's departure to the next
## arrival (20 min on average), how many liners a visit brings (about one in ten brings two, never more), how long each stays
## at its standoff spot (15 to 30 min) and which names they wear. Pure: every answer is a hash of the session seed and the
## visit's index, so a session's liners are the same on every run.

## Liners a visit brings at the most.
const MAX_AT_ONCE: int = 2

var seed_value: int = 0
## The wait before the first visit of a session, and from a visit's departure to the next arrival, s (least, most).
var first_s: Vector2 = Vector2(120.0, 900.0)
var gap_s: Vector2 = Vector2(600.0, 1800.0)
## How long a liner holds at its standoff spot, s (least, most).
var stay_s: Vector2 = Vector2(900.0, 1800.0)
## The share of visits that bring a second liner.
var pair_share: float = 0.1
## Names to draw from (the hull's list in `data/ships/names.json`).
var name_count: int = 1


## The schedule of `data` (traffic.json's `liner`; absent keys keep their defaults) for a session's seed.
static func from_data(data: Dictionary, p_seed: int, p_name_count: int) -> LinerSchedule:
	var s := LinerSchedule.new()
	s.seed_value = p_seed
	s.name_count = maxi(p_name_count, 1)
	s.first_s = span_of(data.get("first_s"), s.first_s)
	s.gap_s = span_of(data.get("gap_s"), s.gap_s)
	s.stay_s = span_of(data.get("stay_s"), s.stay_s)
	s.pair_share = clampf(float(data.get("pair_share", s.pair_share)), 0.0, 1.0)
	return s


## Seconds of free flight from the last visit's departure (the session's start for visit 0) to visit `index`'s arrival.
func wait_s(index: int) -> float:
	var span: Vector2 = first_s if index <= 0 else gap_s
	return lerpf(span.x, span.y, _unit("wait", index, 0))


## How many liners visit `index` brings: one, or two for `pair_share` of the visits.
func liners(index: int) -> int:
	return MAX_AT_ONCE if _unit("pair", index, 0) < pair_share else 1


## How long liner `k` of visit `index` holds at its standoff spot, s.
func stay(index: int, k: int) -> float:
	return lerpf(stay_s.x, stay_s.y, _unit("stay", index, k))


## The place in the name list of liner `k` of visit `index`; a visit's two liners never draw the same one.
func name_index(index: int, k: int) -> int:
	var first: int = int(_unit("name", index, 0) * float(name_count)) % name_count
	if k <= 0 or name_count < 2:
		return first
	return (first + 1 + int(_unit("name", index, 1) * float(name_count - 1)) % (name_count - 1)) % name_count


## The mean wait between visits, s (what the data asks for on average).
func mean_gap_s() -> float:
	return 0.5 * (gap_s.x + gap_s.y)


func _unit(what: String, index: int, k: int) -> float:
	return float(hash([seed_value, "liner " + what, index, k])) / 4294967296.0


## A [least, most] pair of `raw` (a JSON array), ordered and not negative; `fallback` when it is not one.
static func span_of(raw: Variant, fallback: Vector2) -> Vector2:
	if not (raw is Array) or (raw as Array).size() < 2:
		return fallback
	var low: float = maxf(float((raw as Array)[0]), 0.0)
	return Vector2(low, maxf(float((raw as Array)[1]), low))
