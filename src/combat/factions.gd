class_name Factions
extends RefCounted
## Faction ids and the one relation query every combat system uses (architecture §15.1 D25, §15.15, §16 D30): hit
## detection (no friendly fire unless `settings.friendly_fire`), hostile-first target cycling, AI target choice and the
## HUD colours. No scene tree. The rule is data: `data/factions.json`, parsed by `FactionTable`, held here as the
## active table and loaded on the first query. Callers keep asking `relation` / `is_hostile` and do not change.
##
## With the file at its defaults the rule is M2's, checked in this order:
## 1. Same faction id -> FRIENDLY. (This includes `neutral` with itself and two identical unknown ids.)
## 2. Either side `neutral` or not a known faction -> NEUTRAL.
## 3. `earth_alliance` against `raiders` -> HOSTILE (symmetric).
## A pair the file does not list is the file's `default` (neutral); an id the file does not list is NEUTRAL to everything
## but itself. A broken file warns once and the built-in M2 rule (`FactionTable.builtin`) stays active.
##
## Tests that swap the table (`use_table`, console `relation`) call `reset()` afterwards: the table is process-wide state.

const EARTH_ALLIANCE: StringName = &"earth_alliance"
const RAIDERS: StringName = &"raiders"
const NEUTRAL: StringName = &"neutral"

enum Relation { FRIENDLY, NEUTRAL, HOSTILE }

## The faction data file (architecture §16 D30).
const TABLE_PATH: String = "res://data/factions.json"

## Target box, lead reticle and radar dot colours by relation (maintainer answer Q4: hostile red, friendly blue,
## neutral or unknown yellow).
const HOSTILE_COLOR: Color = Color(1.0, 0.35, 0.25)
const NEUTRAL_COLOR: Color = Color(1.0, 0.85, 0.25)
const FRIENDLY_COLOR: Color = Color(0.45, 0.7, 1.0)
## The HUD's own line work (boresight, gauges, radar sphere): green, independent of any faction.
const HUD_LINE_COLOR: Color = Color(0.55, 1.0, 0.6)

## The active table; null until the first query (or after `reset`), then loaded from `TABLE_PATH`.
static var _table: FactionTable = null


## How a ship of faction `a` regards a ship of faction `b`. Symmetric.
static func relation(a: StringName, b: StringName) -> Relation:
	return table().relation(a, b)


## True when ships of `a` and `b` may shoot each other.
static func is_hostile(a: StringName, b: StringName) -> bool:
	return relation(a, b) == Relation.HOSTILE


## True when the active table lists the faction (`earth_alliance`, `raiders` and `neutral` in the shipped file); any
## other id is "unknown" and `relation` treats it as neutral.
static func is_known(faction: StringName) -> bool:
	return table().has(faction)


## The active table, loading `TABLE_PATH` on first use. A file that does not validate warns and leaves the built-in M2 rule.
static func table() -> FactionTable:
	if _table == null:
		var error: String = load_table(TABLE_PATH)
		if not error.is_empty():
			push_warning("Factions: %s; using the built-in rule" % error)
			_table = FactionTable.builtin()
	return _table


## Replaces the active table (tests, scenarios). null is `reset`.
static func use_table(new_table: FactionTable) -> void:
	_table = new_table


## Forgets the active table, and with it every session change made through the console: the next query reloads the file.
static func reset() -> void:
	_table = null


## Loads and validates the file at `path`. On success it becomes the active table and "" comes back; on failure the
## active table is left as it was and the path-qualified error comes back.
static func load_table(path: String = TABLE_PATH) -> String:
	var result: Dictionary = FactionTable.load_file(path)
	if not result["ok"]:
		return String(result["error"])
	_table = result["table"]
	return ""


## The HUD colour for a relation. Anything that is not FRIENDLY or HOSTILE reads as neutral/unknown yellow.
static func hud_color(rel: Relation) -> Color:
	match rel:
		Relation.HOSTILE:
			return HOSTILE_COLOR
		Relation.FRIENDLY:
			return FRIENDLY_COLOR
	return NEUTRAL_COLOR
