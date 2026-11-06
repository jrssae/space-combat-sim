class_name BodyKind
extends RefCounted
## What sort of thing a scanned body is (M4-T09, architecture §17.8), so the contact scan can keep rocks and mines out of a
## fighter's nearest contacts and hand them to avoidance as obstacles instead. The values follow the plan's list for
## `Targetable.kind` (M4-T07): ship, capital, turret, missile, mine, static, prop. A body that says nothing is a ship.

const SHIP: int = 0
const CAPITAL: int = 1
const TURRET: int = 2
const MISSILE: int = 3
const MINE: int = 4
const STATIC: int = 5
const PROP: int = 6

const NAMES: Array[StringName] = [&"ship", &"capital", &"turret", &"missile", &"mine", &"static", &"prop"]


## The kind a `kind` property holds: a name from `NAMES` (any case) or one of the values above; anything else is a ship.
static func from_variant(value: Variant) -> int:
	match typeof(value):
		TYPE_INT:
			var i: int = value
			return i if i >= SHIP and i <= PROP else SHIP
		TYPE_STRING_NAME, TYPE_STRING:
			var at: int = NAMES.find(StringName(String(value).to_lower()))
			return at if at >= 0 else SHIP
	return SHIP


## Whether bodies of this kind are obstacles (`ContactScan.statics_for`) rather than contacts: static rows and mines.
static func is_static(kind: int) -> bool:
	return kind == STATIC or kind == MINE


## The kind of the body `marker` (a `Targetable`) marks: its `kind` property when it has one, else a ship.
static func of(marker: Object) -> int:
	return from_variant(marker.get(&"kind")) if marker != null else SHIP
