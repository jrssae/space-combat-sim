class_name HulkRoster
extends RefCounted
## The disabled hulks kept in play, oldest first (M10-T10, D12.7, Q19): past the cap the oldest are scuttled, so a long battle
## does not fill the space with wrecks. Pure: it holds keys (body ids) in the order they were disabled.

var cap: int = 8

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


## The hulks past the cap, oldest first: the ones to scuttle. A cap below 0 keeps every hulk.
func over_cap() -> PackedInt64Array:
	if cap < 0 or _order.size() <= cap:
		return PackedInt64Array()
	return _order.slice(0, _order.size() - cap)


## Every hulk, oldest first.
func keys() -> PackedInt64Array:
	return _order.duplicate()
