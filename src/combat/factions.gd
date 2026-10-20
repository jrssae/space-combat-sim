class_name Factions
extends RefCounted
## Faction ids and the one relation query every combat system uses (architecture §15.1 D25, §15.15): hit
## detection (no friendly fire), hostile-first target cycling, AI target choice and the HUD colours. Pure: no scene
## tree. M3 turns the fixed rule into data; callers keep asking `relation` / `is_hostile` and do not change.
##
## Rule, checked in this order:
## 1. Same faction id -> FRIENDLY. (This includes `neutral` with itself and two identical unknown ids.)
## 2. Either side `neutral` or not a known faction -> NEUTRAL.
## 3. `earth_alliance` against `raiders` -> HOSTILE (symmetric).

const EARTH_ALLIANCE: StringName = &"earth_alliance"
const RAIDERS: StringName = &"raiders"
const NEUTRAL: StringName = &"neutral"

enum Relation { FRIENDLY, NEUTRAL, HOSTILE }

## Target box, lead reticle and radar dot colours by relation (maintainer answer Q4: hostile red, friendly blue,
## neutral or unknown yellow).
const HOSTILE_COLOR: Color = Color(1.0, 0.35, 0.25)
const NEUTRAL_COLOR: Color = Color(1.0, 0.85, 0.25)
const FRIENDLY_COLOR: Color = Color(0.45, 0.7, 1.0)
## The HUD's own line work (boresight, gauges, radar sphere): green, independent of any faction.
const HUD_LINE_COLOR: Color = Color(0.55, 1.0, 0.6)


## How a ship of faction `a` regards a ship of faction `b`. Symmetric.
static func relation(a: StringName, b: StringName) -> Relation:
	if a == b:
		return Relation.FRIENDLY
	if not is_known(a) or not is_known(b) or a == NEUTRAL or b == NEUTRAL:
		return Relation.NEUTRAL
	return Relation.HOSTILE


## True when ships of `a` and `b` may shoot each other.
static func is_hostile(a: StringName, b: StringName) -> bool:
	return relation(a, b) == Relation.HOSTILE


## True for `earth_alliance`, `raiders` and `neutral`; any other id is "unknown" and `relation` treats it as
## neutral.
static func is_known(faction: StringName) -> bool:
	return faction == EARTH_ALLIANCE or faction == RAIDERS or faction == NEUTRAL


## The HUD colour for a relation. Anything that is not FRIENDLY or HOSTILE reads as neutral/unknown yellow.
static func hud_color(rel: Relation) -> Color:
	match rel:
		Relation.HOSTILE:
			return HOSTILE_COLOR
		Relation.FRIENDLY:
			return FRIENDLY_COLOR
	return NEUTRAL_COLOR
