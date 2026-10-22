class_name DebugFlags
extends RefCounted
## Session-only cheats (architecture §6.4), owned by DebugConsole and exposed as the `debug` provider.
## Never saved: nothing here reaches Settings or the disk, so every session starts with all flags off.
## Gameplay reads them directly, e.g. M2 hull damage skips the player while `DebugConsole.flags.invulnerable`.

signal changed(flag: StringName, value: bool)

const NAMES: Array[StringName] = [&"invulnerable"]

## The player takes no damage (`god`). M1 has no damage; M2 checks this.
var invulnerable: bool = false:
	set = set_invulnerable


func set_invulnerable(value: bool) -> void:
	if invulnerable == value:
		return
	invulnerable = value
	changed.emit(&"invulnerable", value)


func names() -> Array[StringName]:
	return NAMES.duplicate()


func has_flag(flag: StringName) -> bool:
	return NAMES.has(flag)


func get_flag(flag: StringName) -> bool:
	match flag:
		&"invulnerable":
			return invulnerable
	return false


## Returns false for an unknown flag.
func set_flag(flag: StringName, value: bool) -> bool:
	match flag:
		&"invulnerable":
			set_invulnerable(value)
			return true
	return false


## Every flag off.
func reset() -> void:
	for flag: StringName in NAMES:
		set_flag(flag, false)
