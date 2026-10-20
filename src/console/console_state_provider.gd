class_name ConsoleStateProvider
extends RefCounted
## A whitelist of state one subsystem exposes to the console as `provider.key` paths (architecture §6.4).
## State is read only through these methods, never by reflection: a key that is not listed does not exist
## (`get ship.queue_free` is "unknown key"). Writable keys describe their type and range through `value_arg`,
## and the registry validates text against it before `write` is called.
##
## Most subsystems use ConsoleVars (a Dictionary of getters/setters) instead of subclassing this.


func keys() -> Array[StringName]:
	return []


func has_key(key: StringName) -> bool:
	return keys().has(key)


func read(_key: StringName) -> Variant:
	return null


func unit(_key: StringName) -> String:
	return ""


func doc(_key: StringName) -> String:
	return ""


func is_writable(_key: StringName) -> bool:
	return false


## Type, range and choices of a writable key, as the parser for `set` text. Null for read-only keys.
func value_arg(_key: StringName) -> ConsoleArg:
	return null


## Writes an already validated value. Returns "" on success, otherwise why it was refused.
func write(key: StringName, _value: Variant) -> String:
	return "%s is read-only" % key


## True if the key has a default that `default <path>` can restore.
func can_reset(_key: StringName) -> bool:
	return false


## Restores the default. Returns "" on success, otherwise why not.
func reset(key: StringName) -> String:
	return "%s has no default" % key


## True if the value differs from what is saved (shown as `*` by `state`).
func is_modified(_key: StringName) -> bool:
	return false
