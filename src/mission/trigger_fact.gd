class_name TriggerFact
extends Trigger
## `fact` (M8 D79): a number the game keeps about the run (`MissionFacts`: gate jumps flown, hostile hits, ships lost, the
## player's hull) has reached `at_least`, or with `below` has fallen under it. Forced, it only latches: the script places
## whatever the step would have moved.

var fact: StringName = &""
var at_least: float = 1.0
var below: bool = false


func _init(p_fact: StringName = &"", p_at_least: float = 1.0, p_below: bool = false) -> void:
	kind = &"fact"
	fact = p_fact
	at_least = p_at_least
	below = p_below


func test(world: MissionWorld) -> bool:
	var value: float = world.fact(fact)
	return value < at_least if below else value >= at_least


func describe() -> String:
	return "fact %s %s %s" % [fact, "<" if below else ">=", at_least]
