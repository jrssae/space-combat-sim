class_name DebriefPage
extends ChoiceListScreen
## The debrief's one page (architecture §18, D56): Retry and Front end on the left, the whole debrief on the right whichever
## option has the focus, and when none has it.

## The right panel's content (`DebriefModel.panel`).
var panel: Dictionary = {}


func info() -> Dictionary:
	return panel
