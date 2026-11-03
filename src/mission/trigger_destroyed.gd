class_name TriggerDestroyed
extends Trigger
## `destroyed` (D52): every named ship is out of play (`all`), or at least one is. Forced (D51), the named ships still in play
## are released, with no explosion and no kill credit: all of them, or only the first for `all` false (the step would have gone
## on at the first loss).

var names: PackedStringArray = PackedStringArray()
var all: bool = true


func _init(p_names: PackedStringArray = PackedStringArray(), p_all: bool = true) -> void:
	kind = &"destroyed"
	names = p_names
	all = p_all


func actors() -> PackedStringArray:
	return names


func test(world: MissionWorld) -> bool:
	for actor: String in names:
		var gone: bool = not world.is_alive(actor)
		if gone and not all:
			return true
		if not gone and all:
			return false
	return all


func force(world: MissionWorld) -> void:
	for actor: String in names:
		if world.is_alive(actor):
			world.release(actor)
			if not all:
				return


func describe() -> String:
	return "destroyed %s of %s" % ["all" if all else "any", ", ".join(names)]
