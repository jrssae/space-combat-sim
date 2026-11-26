class_name HitSummary
extends RefCounted
## One ship's tick of beam hits, landed in one native batch (M10-T75, Q94; `Damageable.hits_landed`): instead of a `HitInfo` a
## hit, every attacker that hit it this tick, the damage and the points removed, and where. The AI's attacker memory, the
## carriers' jump-away, a capital's section counters, the HUD's damage zones and the core's hull column read it.

## Every field reads the batch's columns (`ScsBeamRows.land`, row `k`) when asked, so a summary costs only what its
## listeners read.

## The body hit last (a capital's hull or rotor), the cause (`HitInfo.CAUSE_BEAM`).
var target_id: int:
	get:
		return (_cols[1] as PackedInt64Array)[_k]
var cause: StringName = HitInfo.CAUSE_BEAM
## Every ship that hit it this tick, in the order each first did, and each one's faction.
var attackers: PackedInt64Array:
	get:
		var at: PackedInt32Array = _cols[7]
		return (_cols[8] as PackedInt64Array).slice(at[_k], at[_k + 1])
var factions: Array[StringName]:
	get:
		var at: PackedInt32Array = _cols[7]
		var ix: PackedInt32Array = _cols[9]
		var out: Array[StringName] = []
		for i: int in range(at[_k], at[_k + 1]):
			out.append(_names[ix[i]] if ix[i] >= 0 and ix[i] < _names.size() else &"")
		return out
## The ship whose hit landed last.
var last_shooter: int:
	get:
		return (_cols[2] as PackedInt64Array)[_k]
var hits: int:
	get:
		return (_cols[3] as PackedInt32Array)[_k]
## Hull points the hits carried, and those they removed.
var damage: float:
	get:
		return (_cols[4] as PackedFloat64Array)[_k]
var applied: float:
	get:
		return (_cols[5] as PackedFloat64Array)[_k]
## Where the last hit landed, `World`-local.
var point: Vector3:
	get:
		return (_cols[6] as PackedVector3Array)[_k]
## A capital's: each hit's section, by the damage store's slot (`CapitalDamage.section_name`).
var sections: PackedInt32Array:
	get:
		var at: PackedInt32Array = _cols[10]
		return (_cols[11] as PackedInt32Array).slice(at[_k], at[_k + 1])
## The zones the points went to and how many (a fighter's silhouette zones, the station's sections).
var zones: PackedInt32Array:
	get:
		var at: PackedInt32Array = _cols[12]
		return (_cols[13] as PackedInt32Array).slice(at[_k], at[_k + 1])
var zone_amounts: PackedFloat64Array:
	get:
		var at: PackedInt32Array = _cols[12]
		return (_cols[14] as PackedFloat64Array).slice(at[_k], at[_k + 1])

var _cols: Array = []
var _k: int = 0
var _names: Array = []


## Row `k` of the batch's summary columns, the attackers' factions named from the core's `names`.
static func from_columns(cols: Array, k: int, names: Array) -> HitSummary:
	var s := HitSummary.new()
	s._cols = cols
	s._k = k
	s._names = names
	return s


## The faction of attacker `shooter_id`, or "" for one that did not hit it.
func faction_of(shooter_id: int) -> StringName:
	var at: int = Array(attackers).find(shooter_id)
	var all: Array[StringName] = factions
	return all[at] if at >= 0 and at < all.size() else &""
