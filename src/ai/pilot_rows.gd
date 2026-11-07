class_name PilotRows
extends RefCounted
## A perception's own lists as rows for the native pilot kernels (M4-T42): what answers avoidance and the fire lane when
## the lists are not on the core's rows (a perception built by hand, or core rows that moved since the scan was taken).
## Row i is the i-th contact, with a faction of its own whose relation is the contact's, so the kernels answer exactly as
## they do over the core's rows.

const PILOT_CLASS: StringName = &"ScsPilotKernels"


## Kernels holding `contacts` as rows 0 to n-1; null when the library cannot load them (it logs why).
static func kernels_of(contacts: Array[Contact]) -> Object:
	var n: int = contacts.size()
	var ids := PackedInt64Array()
	var positions := PackedVector3Array()
	var velocities := PackedVector3Array()
	var radii := PackedFloat64Array()
	var kinds := PackedByteArray()
	var factions := PackedInt32Array()
	var is_ship := PackedByteArray()
	ids.resize(n)
	positions.resize(n)
	velocities.resize(n)
	radii.resize(n)
	kinds.resize(n)
	factions.resize(n)
	is_ship.resize(n)
	for i: int in n:
		var c: Contact = contacts[i]
		ids[i] = c.id
		positions[i] = c.position
		velocities[i] = c.velocity
		radii[i] = c.bounding_radius
		kinds[i] = c.kind
		factions[i] = i
		is_ship[i] = 1 if c.is_ship else 0
	var kernels: Object = NativeLib.instantiate(PILOT_CLASS)
	if kernels == null or not kernels.load(ids, positions, velocities, radii, kinds, factions, is_ship):
		return null
	return kernels


## Each contact's relation to the asking ship, by row (the faction row `kernels_of` gives every contact its own of).
static func relations(contacts: Array[Contact]) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(contacts.size())
	for i: int in contacts.size():
		out[i] = contacts[i].relation
	return out


## Rows `from` to `from + count - 1`.
static func span(from: int, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(count)
	for i: int in count:
		out[i] = from + i
	return out
