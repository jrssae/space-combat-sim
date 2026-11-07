class_name SandboxSelect
extends ChoiceListScreen
## The front end's Sandbox page (architecture §18, D57): the combat scenarios as they have always been, started without
## encounters or objectives.

const SCENARIOS: Array[Dictionary] = [
	{"id": &"combat_sandbox", "text": "Combat sandbox"},
	{"id": &"dogfight", "text": "Dogfight"},
	{"id": &"instructor_route", "text": "Instructor route"},
	{"id": &"civilian_showcase", "text": "Civilian ships"},
]


func setup_sandbox() -> void:
	setup("Sandbox", SCENARIOS)
	add_back_option()
