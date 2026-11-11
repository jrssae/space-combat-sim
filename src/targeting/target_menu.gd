class_name TargetMenu
extends RefCounted
## The target menu's pages on a `RadialMenu` (architecture §18.19, M5-T25), pure. Opened with the candidate list as it is at
## that moment (the game is paused while it shows, so nothing in it goes stale): the first ring is the six categories with
## their counts, the second the nearest five of one category and "none" in the down slice. `select` opens a category or
## returns what the pilot picked, for the owner to carry out:
##     {action: target, id, label}           a ship becomes the target
##     {action: waypoint, id, label, point}  a beacon or an objective becomes the HUD waypoint (`id` 0 for a bare place)
##     {action: clear_target} / {action: clear_waypoint}   "none"
## A pick closes the menu. A second-ring slot also carries its `source` (the `TargetInfo` or the objective it was built from),
## which the preview panel reads for the highlighted entry (T43).

const HEADING: String = "TACTICAL PAUSE"
const NONE_LABEL: String = "NONE"
const UNKNOWN_LABEL: String = "UNKNOWN"
const ACTION_TARGET: StringName = &"target"
const ACTION_WAYPOINT: StringName = &"waypoint"
const ACTION_CLEAR_TARGET: StringName = &"clear_target"
const ACTION_CLEAR_WAYPOINT: StringName = &"clear_waypoint"
## Every category's ring has this many slices: five entries and "none", so a slot is always in the same direction.
const RING_SLICES: int = TargetCategories.RING_SIZE + 1
## An objective's text is cut to this on its slice; the whole text shows under the ring while it is highlighted.
const OBJECTIVE_LABEL_CHARS: int = 16
## The categories whose picks set the waypoint rather than the target.
const WAYPOINT_CATEGORIES: Array[TargetCategories.Category] = [TargetCategories.Category.NAVIGATION,
		TargetCategories.Category.OBJECTIVES]

var radial: RadialMenu = RadialMenu.new()
## The category whose ring is open, or -1 on the first ring and when closed.
var category: int = -1

var _counts: Dictionary = {}
var _nearest: Dictionary = {}
var _objectives: Array[Dictionary] = []
var _own_position: Vector3 = Vector3.ZERO


## "850 m", "1.9 km".
static func range_text(range_m: float) -> String:
	return "%.1f km" % (range_m / 1000.0) if range_m >= 1000.0 else "%.0f m" % range_m


## Opens on the categories. `objectives` are the mission's active objectives that name a place or an actor, in the mission's
## order: `{text, label, target_id, point (UniversePos or null), position (World-local)}`; the first five show.
func open(candidates: Array[TargetInfo], own_position: Vector3, own_faction: StringName,
		objectives: Array[Dictionary] = []) -> void:
	_own_position = own_position
	var summary: Dictionary = TargetCategories.summarise(candidates, own_position, own_faction)
	_counts = summary["counts"]
	_nearest = summary["nearest"]
	_objectives = objectives.slice(0, TargetCategories.RING_SIZE)
	category = -1
	var slots: Array[Dictionary] = []
	for c: TargetCategories.Category in TargetCategories.ORDER:
		var n: int = count(c)
		slots.append({"label": TargetCategories.NAMES[c], "sub": "%d in range" % n if c == TargetCategories.Category.ENEMIES else str(n),
				"color": TargetCategories.COLORS[c], "payload": c})
	radial.open(HEADING, slots, Factions.HUD_LINE_COLOR)


func is_open() -> bool:
	return radial.is_open()


func close(reason: StringName = &"close") -> void:
	radial.close(reason)
	category = -1


## How many entries `c` holds in all (the first ring's numbers).
func count(c: TargetCategories.Category) -> int:
	if c == TargetCategories.Category.OBJECTIVES:
		return _objectives.size()
	return int(_counts.get(c, 0))


## The page showing: `categories`, a category's name in lower case, or "" when closed.
func page_name() -> String:
	if not radial.is_open():
		return ""
	return "categories" if category < 0 else String(TargetCategories.NAMES[category]).to_lower()


func point(v: Vector2) -> bool:
	return radial.point(v)


## B: from a category back to the categories, from the categories out. Returns whether the menu is still open.
func back() -> bool:
	var still_open: bool = radial.back()
	category = -1
	return still_open


## A. On the first ring it opens the highlighted category and returns nothing; on the second it closes the menu and returns
## the pick (see the class comment).
func select() -> Dictionary:
	var entry: Dictionary = radial.select()
	if entry.is_empty():
		return {}
	if category < 0:
		_open_category(entry["payload"] as TargetCategories.Category)
		return {}
	var picked: Dictionary = (entry["payload"] as Dictionary).duplicate()
	close(&"pick")
	return picked


func _open_category(c: TargetCategories.Category) -> void:
	category = c
	var color: Color = TargetCategories.COLORS[c]
	var entries: Array[Dictionary] = []
	if c == TargetCategories.Category.OBJECTIVES:
		for objective: Dictionary in _objectives:
			entries.append(_objective_entry(objective, color))
	else:
		var listed: Array[TargetInfo] = _nearest[c]
		for info: TargetInfo in listed:
			entries.append(_contact_entry(info, c, color))
	var clears: StringName = ACTION_CLEAR_WAYPOINT if WAYPOINT_CATEGORIES.has(c) else ACTION_CLEAR_TARGET
	var none: Dictionary = {"label": NONE_LABEL, "sub": "", "color": Factions.UNIDENTIFIED_COLOR, "payload": {"action": clears}}
	radial.push("%s · %s" % [HEADING, TargetCategories.NAMES[c]], RadialMenu.arrange(entries, none, RING_SLICES), color)


func _contact_entry(info: TargetInfo, c: TargetCategories.Category, color: Color) -> Dictionary:
	var label: String = UNKNOWN_LABEL if c == TargetCategories.Category.UNKNOWN else info.display_name.to_upper()
	var action: StringName = ACTION_WAYPOINT if c == TargetCategories.Category.NAVIGATION else ACTION_TARGET
	return {"label": label, "sub": range_text(TargetingSystem.range_between(_own_position, info.position)), "color": color,
			"source": info, "payload": {"action": action, "id": info.id, "label": label, "point": null}}


func _objective_entry(objective: Dictionary, color: Color) -> Dictionary:
	var text: String = str(objective.get("text", "")).to_upper()
	var label: String = str(objective.get("label", "")).to_upper()
	var short: String = text if text.length() <= OBJECTIVE_LABEL_CHARS else text.left(OBJECTIVE_LABEL_CHARS - 1).strip_edges() + "…"
	var at: Vector3 = objective.get("position", _own_position)
	return {"label": short, "sub": "%s  %s" % [label, range_text(TargetingSystem.range_between(_own_position, at))],
			"detail": text, "color": color, "source": objective,
			"payload": {"action": ACTION_WAYPOINT, "id": int(objective.get("target_id", 0)), "label": label,
					"point": objective.get("point")}}
