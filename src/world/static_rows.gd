class_name StaticRows
extends RefCounted
## Things in the world with no node of their own (M4-T29, architecture §17.16): an asteroid field's rocks (by RID) and a mine
## belt's mines. Each is registered once and removed once, and no tick walks them: the contact scan appends them as rows, and
## the hit and ram resolvers keep the solid ones (rocks: bolts hit them, ships ram them) in a grid built only when one changes.
## A row belongs to the `WorldFrame` it was registered with (its position is in that frame) and moves only on that world's
## rebase or drift; a row with no world never moves. A move is not a change of rows (M6-T06, L4): the columns shift in place
## natively, the solid rows with them, and `moves` counts it, so nothing kept by `version` is built again. Ids must be unique
## and not instance ids: a rock uses its body's RID id, a mine one from `new_id`.
##
## Mines are obstacles, not hulls: bolts and rams pass them (the mine's own trigger is what sets it off), and only their own
## side knows where they are (Q27, `ContactScan.statics_for`).

## Rocks do not move, so a ram is decided by the ship's own change of velocity.
const SOLID_MASS_KG: float = 1.0e15
## A solid row's hull points: nothing breaks a rock.
const SOLID_HULL: float = 1.0e9
## The native class that shifts the columns (M6-T06).
const NATIVE_CLASS: StringName = &"ScsStaticRows"


## The solid rows (kind `BodyKind.STATIC`) in registration order: what the resolvers keep in their grids.
class Solid extends RefCounted:
	var ids: PackedInt64Array = PackedInt64Array()
	var positions: PackedVector3Array = PackedVector3Array()
	var radii: PackedFloat64Array = PackedFloat64Array()
	var factions: Array[StringName] = []
	var worlds: PackedInt64Array = PackedInt64Array()
	## `StaticRows.solid_version` when it was built.
	var version: int = -1
	## Shifts taken in place since it was built: a holder of the positions takes them again when it changes.
	var moves: int = 0


## The rows, column by column, in registration order. Read, never write: go through the functions below.
static var ids: PackedInt64Array = PackedInt64Array()
static var positions: PackedVector3Array = PackedVector3Array()
static var radii: PackedFloat64Array = PackedFloat64Array()
static var factions: Array[StringName] = []
static var kinds: PackedByteArray = PackedByteArray()
static var worlds: PackedInt64Array = PackedInt64Array()  # the owning WorldFrame's instance id, 0 for none
## Changes whenever any row does; `solid_version` only when a solid one does (a mine coming and going leaves it). A shift
## changes neither: it bumps `moves`.
static var version: int = 0
static var solid_version: int = 0
static var moves: int = 0
## Work counts: rows registered since the game started, and how often the solid rows were gathered again.
static var registrations: int = 0
static var solid_builds: int = 0

static var _solid: Solid = null
static var _columns: Dictionary = {}
static var _columns_version: int = -1
static var _native: Object = null


## Adds a row. `kind` is a `BodyKind` (a rock is `STATIC`, a mine `MINE`); `world` the frame `position` is in.
static func register(id: int, position: Vector3, radius: float, kind: int = BodyKind.STATIC,
		faction: StringName = Factions.NEUTRAL, world: Node = null) -> void:
	ids.append(id)
	positions.append(position)
	radii.append(radius)
	factions.append(faction)
	kinds.append(kind)
	worlds.append(world.get_instance_id() if world != null else 0)
	registrations += 1
	_changed(kind == BodyKind.STATIC)


## Removes row `id`; false when there is none.
static func unregister(id: int) -> bool:
	var at: int = ids.find(id)
	if at < 0:
		return false
	var solid_row: bool = kinds[at] == BodyKind.STATIC
	_remove_at(at)
	_changed(solid_row)
	return true


## Removes every row in `gone` (unknown ids are ignored), in one pass.
static func unregister_many(gone: PackedInt64Array) -> void:
	if gone.is_empty() or ids.is_empty():
		return
	var drop: Dictionary = {}
	for id: int in gone:
		drop[id] = true
	var solid_row: bool = false
	var at: int = ids.size() - 1
	var removed: bool = false
	while at >= 0:
		if drop.has(ids[at]):
			solid_row = solid_row or kinds[at] == BodyKind.STATIC
			_remove_at(at)
			removed = true
		at -= 1
	if removed:
		_changed(solid_row)


## Moves the rows registered with `world` by `offset` (`WorldFrame.rebase` and its drift shift them with its nodes), and
## the solid rows with them, in place.
static func shift(offset: Vector3, world: Node) -> void:
	if ids.is_empty() or world == null:
		return
	var owner: int = world.get_instance_id()
	var native: Object = _shifter()
	var shifted: PackedVector3Array = native.shift(positions, worlds, owner, offset)
	if int(native.moved()) == 0:
		return
	positions = shifted
	moves += 1
	if _solid != null and _solid.version == solid_version:
		_solid.positions = native.shift(_solid.positions, _solid.worlds, owner, offset)
		if int(native.moved()) > 0:
			_solid.moves += 1


## Removes every row.
static func clear() -> void:
	var solid_row: bool = kinds.has(BodyKind.STATIC)
	ids.clear()
	positions.clear()
	radii.clear()
	factions.clear()
	kinds.clear()
	worlds.clear()
	_changed(solid_row)


static func count() -> int:
	return ids.size()


static func has(id: int) -> bool:
	return ids.has(id)


## Row `id`'s position, or `Vector3.INF` when there is none.
static func position_of(id: int) -> Vector3:
	var at: int = ids.find(id)
	return positions[at] if at >= 0 else Vector3.INF


## An id no other row, RID or node will use.
static func new_id() -> int:
	return rid_allocate_id()


## The solid rows as of now, gathered again only after a solid row changed. Shared: read, never write.
static func solid() -> Solid:
	if _solid != null and _solid.version == solid_version:
		return _solid
	var out := Solid.new()
	for s: int in ids.size():
		if kinds[s] != BodyKind.STATIC:
			continue
		out.ids.append(ids[s])
		out.positions.append(positions[s])
		out.radii.append(radii[s])
		out.factions.append(factions[s])
		out.worlds.append(worlds[s])
	out.version = solid_version
	_solid = out
	solid_builds += 1
	return out


## The columns a scan row has that every static row fills alike (empty names, zero velocity, the default axes, not a ship,
## no hull), one entry a row, made again only when the rows change: the scan appends them whole instead of row by row.
static func scan_columns() -> Dictionary:
	if _columns_version == version:
		return _columns
	var n: int = ids.size()
	var names := PackedStringArray()
	names.resize(n)
	var zeros := PackedVector3Array()
	zeros.resize(n)
	var forwards := PackedVector3Array()
	forwards.resize(n)
	forwards.fill(Vector3.FORWARD)
	var ups := PackedVector3Array()
	ups.resize(n)
	ups.fill(Vector3.UP)
	var no_bytes := PackedByteArray()
	no_bytes.resize(n)
	var no_ids := PackedInt64Array()
	no_ids.resize(n)
	var statics: int = 0
	for kind: int in kinds:
		if BodyKind.is_static(kind):
			statics += 1
	_columns = {"names": names, "zeros": zeros, "forwards": forwards, "ups": ups, "not_ship": no_bytes, "no_hull": no_ids,
			"statics": statics}
	_columns_version = version
	return _columns


# The native shift (the library is required, M4-T37), made on first use.
static func _shifter() -> Object:
	if _native == null:
		_native = NativeLib.instantiate(NATIVE_CLASS)
	return _native


static func _remove_at(at: int) -> void:
	ids.remove_at(at)
	positions.remove_at(at)
	radii.remove_at(at)
	factions.remove_at(at)
	kinds.remove_at(at)
	worlds.remove_at(at)


static func _changed(solid_row: bool) -> void:
	version += 1
	if solid_row:
		solid_version += 1
