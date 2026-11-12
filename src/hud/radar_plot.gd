class_name RadarPlot
extends RefCounted
## The radar's contacts placed on the sphere for one frame (M4-T36, architecture §17.21): `RadarModel.plot`'s output, in drawing
## order (far to near, the selected one last), as packed arrays a painter draws in a few batched calls, without an object per
## contact.

var ids := PackedInt64Array()
## Radar-space points inside the unit sphere (`RadarModel.Dot.point`).
var points := PackedVector3Array()
var ranges := PackedFloat64Array()
var colors := PackedColorArray()
## Each drawn contact's faction, built when read (tests and readouts): the painter never reads it.
var factions: Array[StringName]:
	get:
		var out: Array[StringName] = []
		out.resize(_order.size())
		for k: int in _order.size():
			out[k] = _faction_names[_faction_ix[_order[k]]]
		return out
## 1 for a broadcast contact beyond the sensors, drawn hollow on the rim.
var rims := PackedByteArray()
## The selected contact's index (always the last), or -1.
var selected_index: int = -1
## Each point on a radar of radius 1 centred at the origin (`RadarModel.to_screen`): a painter's transform places them all.
var point_units := PackedVector2Array()
## Each stalk as a pair (foot, point) on that unit radar, and its colour: one segment per contact.
var stalk_units := PackedVector2Array()
var stalk_colors := PackedColorArray()

# What `factions` is built from: the drawn order as indices into the contacts, theirs, and the names those index.
var _order := PackedInt32Array()
var _faction_ix := PackedInt32Array()
var _faction_names: Array[StringName] = []


## Keeps what `factions` needs to name each drawn contact's faction.
func bind_factions(order: PackedInt32Array, contact_faction_ix: PackedInt32Array, names: Array[StringName]) -> void:
	_order = order
	_faction_ix = contact_faction_ix
	_faction_names = names


func size() -> int:
	return ids.size()


## The plot as `RadarModel.Dot`s (tests and the readouts that want objects).
func to_dots() -> Array[RadarModel.Dot]:
	var out: Array[RadarModel.Dot] = []
	var names: Array[StringName] = factions
	for i: int in ids.size():
		var dot := RadarModel.Dot.new()
		dot.id = ids[i]
		dot.point = points[i]
		dot.foot = Vector3(dot.point.x, dot.point.y, 0.0)
		dot.range_m = ranges[i]
		dot.color = colors[i]
		dot.faction = names[i]
		dot.selected = i == selected_index
		dot.above = dot.point.z >= 0.0
		dot.rim = rims[i] == 1
		out.append(dot)
	return out


## The screen transform of a radar of `radius_px` centred at `centre`: applied to the unit points it gives `RadarModel.to_screen`.
static func screen_transform(centre: Vector2, radius_px: float) -> Transform2D:
	return Transform2D(Vector2(radius_px, 0.0), Vector2(0.0, radius_px), centre)
