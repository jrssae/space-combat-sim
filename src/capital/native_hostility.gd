class_name NativeHostility
extends RefCounted
## Keeps a native row set's relations table (by the core's faction indices) in step with `Factions` (M10-T12, M10-T14): built
## again only when the core knows a new faction, another table is active or a relation changed. The rows take
## `faction_count()` and `set_hostility(count, matrix)`: 1 hostile, 2 friendly (the interceptors guard friends, M10-T13), 0 neutral.

var _count: int = -1
var _table: FactionTable = null
var _revision: int = -1


func refresh(rows: Object, sim: SimCore) -> void:
	var count: int = int(rows.faction_count())
	var table: FactionTable = Factions.table()
	if count == _count and table == _table and table.revision == _revision:
		return
	_count = count
	_table = table
	_revision = table.revision
	var names: Array = sim.core.factions()
	var matrix := PackedByteArray()
	matrix.resize(count * count)
	for a: int in count:
		for b: int in count:
			var relation: Factions.Relation = Factions.relation(names[a], names[b])
			matrix[a * count + b] = 1 if relation == Factions.Relation.HOSTILE else (2 if relation == Factions.Relation.FRIENDLY else 0)
	rows.set_hostility(count, matrix)
