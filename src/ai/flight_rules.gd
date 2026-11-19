class_name FlightRules
extends RefCounted
## How fighters fly in flights (M8-T19, D85), from `data/wings/flights.json`: a flight's size, how far a wingman may stray from
## its lead before it rejoins, and how far apart a squadron's flights form up. Pure; `split` says which flight and place a
## squadron's nth fighter takes.

const PATH: String = "res://data/wings/flights.json"

## Ships in a flight, the lead included.
var size: int = 3
## A wingman farther than this from its lead breaks off and rejoins, m; it fights again within `rejoined_m`.
var cohesion_m: float = 2500.0
var rejoined_m: float = 1000.0
## The slots of a squadron's flight leads, in formation spacings.
var lead_spacing: float = 4.0

static var _shared: FlightRules = null


## The game's rules, read once.
static func shared() -> FlightRules:
	if _shared == null:
		_shared = from_file()
	return _shared


## The rules in `path`; a missing or broken file, or a bad number, warns and keeps the default.
static func from_file(path: String = PATH) -> FlightRules:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not (parsed is Dictionary):
		push_warning("FlightRules: %s is missing or not a JSON object; defaults" % path)
		return FlightRules.new()
	return from_dict(parsed as Dictionary, path)


static func from_dict(d: Dictionary, source: String = "flights") -> FlightRules:
	var rules := FlightRules.new()
	var flight_size: Variant = d.get("size", rules.size)
	if (flight_size is float or flight_size is int) and int(flight_size) >= 2 and float(flight_size) == float(int(flight_size)):
		rules.size = int(flight_size)
	else:
		push_warning("FlightRules: %s: size must be a whole number of 2 or more; %d kept" % [source, rules.size])
	rules.cohesion_m = _positive(d, "cohesion_m", rules.cohesion_m, source)
	rules.rejoined_m = _positive(d, "rejoined_m", rules.rejoined_m, source)
	rules.lead_spacing = _positive(d, "lead_spacing", rules.lead_spacing, source)
	if rules.rejoined_m >= rules.cohesion_m:
		push_warning("FlightRules: %s: rejoined_m must be less than cohesion_m; half of it used" % source)
		rules.rejoined_m = 0.5 * rules.cohesion_m
	return rules


static func _positive(d: Dictionary, key: String, fallback: float, source: String) -> float:
	var value: Variant = d.get(key, fallback)
	if (value is float or value is int) and float(value) > 0.0:
		return float(value)
	push_warning("FlightRules: %s: %s must be a number above 0; %s kept" % [source, key, fallback])
	return fallback


## Wingmen in a flight: its size less the lead.
func wingmen() -> int:
	return size - 1


## Where a squadron's fighter number `index` (0 first) flies when the squadron is split into flights from `first_flight` on:
## `Vector2i(flight, place)`, flights counted from 1 and place 0 the lead. Flights fill in order, so a count that does not
## divide leaves the last flight short.
func split(index: int, first_flight: int = 1) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(first_flight + index / size, index % size)


## The number the lead of flight `flight` (1 first) carries in its squadron's callsigns: 1, 4, 7, ... for flights of three.
func first_number(flight: int) -> int:
	return 1 + (maxi(flight, 1) - 1) * size
