class_name TransponderConsole
extends RefCounted
## The console command `transponder <reveal|hide> [target|player|all]` (M10-T02): scripts and testers give a renegade away or
## put its disguise back on without staging a fight. Only ships whose faction broadcasts another's transponder change.


## Applies `action` (`reveal` or `hide`) to `ships` (null entries skipped) and says how many changed.
static func apply(action: StringName, ships: Array[Targetable]) -> ConsoleResult:
	var changed: int = 0
	for targetable: Targetable in ships:
		if targetable == null:
			continue
		var broadcast: StringName = Factions.table().transponder(targetable.faction)
		if broadcast.is_empty():
			continue
		if action == &"reveal" and targetable.is_disguised():
			targetable.reveal()
			changed += 1
		elif action == &"hide" and not targetable.is_disguised():
			targetable.disguise_as(broadcast)
			changed += 1
	return ConsoleResult.line("transponder %s: %d ship%s changed" % [action, changed, "" if changed == 1 else "s"])
