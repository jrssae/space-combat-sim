class_name HulkRoster
extends RefCounted
## The disabled hulks in play, oldest first (M10-T10, D12.7): there is no cap, a hulk stays until it is destroyed. Pure: it
## holds keys (body ids) in the order they were disabled.

var _order := PackedInt64Array()


## Notes `key` as the newest hulk (once).
func add(key: int) -> void:
	if not _order.has(key):
		_order.append(key)


## `key` is no longer a hulk (destroyed, whole again, gone).
func remove(key: int) -> void:
	var at: int = _order.find(key)
	if at >= 0:
		_order.remove_at(at)


func has(key: int) -> bool:
	return _order.has(key)


func size() -> int:
	return _order.size()


## Every hulk, oldest first.
func keys() -> PackedInt64Array:
	return _order.duplicate()
