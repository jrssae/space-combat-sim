class_name StaticRows
extends RefCounted
## Stub (M4-T29, tests first): the store of rows with no node. Filled in by the change.

## The rows that bolts hit and ships ram.
class Solid extends RefCounted:
	var ids: PackedInt64Array = PackedInt64Array()
	var positions: PackedVector3Array = PackedVector3Array()
	var radii: PackedFloat64Array = PackedFloat64Array()
	var factions: Array[StringName] = []

static var ids: PackedInt64Array = PackedInt64Array()
static var positions: PackedVector3Array = PackedVector3Array()
static var radii: PackedFloat64Array = PackedFloat64Array()
static var factions: Array[StringName] = []
static var kinds: PackedByteArray = PackedByteArray()
static var version: int = 0
static var registrations: int = 0
static var solid_builds: int = 0


static func register(_id: int, _position: Vector3, _radius: float, _kind: int = BodyKind.STATIC,
		_faction: StringName = Factions.NEUTRAL, _world: Node = null) -> void:
	pass


static func unregister(_id: int) -> bool:
	return false


static func unregister_many(_ids: PackedInt64Array) -> void:
	pass


static func shift(_offset: Vector3, _world: Node) -> void:
	pass


static func clear() -> void:
	pass


static func count() -> int:
	return 0


static func has(_id: int) -> bool:
	return false


static func position_of(_id: int) -> Vector3:
	return Vector3.INF


static func new_id() -> int:
	return 0


static func solid() -> Solid:
	return Solid.new()
