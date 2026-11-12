class_name MissionCatalog
extends RefCounted
## The missions the front end lists (architecture §18, D57): every scenario file with a `mission` block, read through
## `ScenarioLoader`, so a new mission is a new file and never an edit here. A file that does not load, or has no block, is not
## a mission.

## Missions in `dir`, by id: `{id: StringName, title: String, briefing: String}`. `read` turns a path into a loaded scenario
## (`ScenarioLoader.load` by default); the block is the loader's `mission` entry.
static func entries(dir: String = GameFlow.SCENARIO_DIR, read: Callable = ScenarioLoader.load) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var files: PackedStringArray = DirAccess.get_files_at(dir)
	files.sort()
	for file: String in files:
		if file.get_extension() != "json":
			continue
		var scenario: Variant = read.call(dir.path_join(file))
		if not (scenario is Dictionary) or not bool((scenario as Dictionary).get("ok", false)):
			var why: Variant = (scenario as Dictionary).get("error", "") if scenario is Dictionary else "not a scenario"
			push_warning("MissionCatalog: %s is not listed: %s" % [file, why])
			continue
		var block: Variant = (scenario as Dictionary).get("mission")
		if not (block is Dictionary) or (block as Dictionary).is_empty():
			continue  # the loader reports "no mission" as an empty block
		var id: String = file.get_basename()
		var title: String = String((block as Dictionary).get("title", ""))
		out.append({
			"id": StringName(id),
			"title": title if not title.is_empty() else id.replace("_", " ").capitalize(),
			"briefing": String((block as Dictionary).get("briefing", "")),
		})
	return out
