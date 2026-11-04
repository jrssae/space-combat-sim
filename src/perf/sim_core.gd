class_name SimCore
extends Node
## The native simulation core's facade (M4-T15, architecture §17.13). Stub: the core is not built yet.

const NATIVE_CLASS: StringName = &"ScsSimCore"
const NODE_NAME: StringName = &"SimCore"
const PRIORITY: int = -11
const OUT_PRIORITY: int = 2_000_000

const KIND_SHIP: int = 0
const KIND_CAPITAL: int = 1
const KIND_TURRET: int = 2
const KIND_MISSILE: int = 3
const KIND_MINE: int = 4
const KIND_STATIC: int = 5
const KIND_PROP: int = 6
const KIND_BOLT: int = 7
const KIND_BEAM: int = 8


static func attach(_world: Node) -> SimCore:
	return null


static func for_tree(_tree: SceneTree) -> SimCore:
	return null


func sync_now() -> bool:
	return false


func sync_out_now() -> void:
	pass


func rows() -> int:
	return -1


func handle_of(_body_id: int) -> int:
	return -1


func row_of(_handle: int) -> int:
	return -1


func row_name(_handle: int) -> String:
	return ""


func row_position(_handle: int) -> Vector3:
	return Vector3.INF


func body_ids() -> PackedInt64Array:
	return PackedInt64Array()


func body_positions() -> PackedVector3Array:
	return PackedVector3Array()


func bolt_positions() -> PackedVector3Array:
	return PackedVector3Array()


func static_positions() -> PackedVector3Array:
	return PackedVector3Array()


func add_row(_row: Dictionary) -> int:
	return -1


func row(_handle: int) -> Dictionary:
	return {}


func set_row_command(_handle: int, _command: PackedFloat64Array) -> void:
	pass


func remove_row(_handle: int) -> void:
	pass


func engine_calls() -> PackedInt64Array:
	return PackedInt64Array([-1, -1])
