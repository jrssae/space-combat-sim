class_name TargetMenu
extends RefCounted
## The target menu's pages on a `RadialMenu` (architecture §18.19, M5-T25), pure. Opened with the candidate list as it is at
## that moment (the game is paused while it shows, so nothing in it goes stale): the first ring is the six categories with
## their counts, the second the nearest eight of one category (the launch base first in ALLIES) and "none" in the down slice; each ring has one slice per entry
## (D90, M8-T24). `select` opens a category or returns what the pilot picked, for the owner to carry out:
##     {action: target, id, label}           a ship becomes the target
##     {action: waypoint, id, label, point}  a beacon or an objective becomes the HUD waypoint (`id` 0 for a bare place)
##     {action: clear_target} / {action: clear_waypoint}   "none"
## A capital's pick first opens its subsystem rings (M10-T18, `CapitalSubsystems`): WHOLE SHIP and the groups, then a group's members; the
## pick then carries `subsystem` (a key, "" for the whole ship). A pick closes the menu. A second-ring slot also carries its `source` (the `TargetInfo` or the objective it was built from),
## which the preview panel reads for the highlighted entry (T43).

const HEADING: String = "TACTICAL PAUSE"
const NONE_LABEL: String = "NONE"
const UNKNOWN_LABEL: String = "UNKNOWN"
const ACTION_TARGET: StringName = &"target"
const ACTION_WAYPOINT: StringName = &"waypoint"
const ACTION_CLEAR_TARGET: StringName = &"clear_target"
const ACTION_CLEAR_WAYPOINT: StringName = &"clear_waypoint"
## A subsystem ring's entry that opens its group (never returned by `select`).
const ACTION_GROUP: StringName = &"group"
## An objective's text is cut to this on its slice; the whole text shows under the ring while it is highlighted.
const OBJECTIVE_LABEL_CHARS: int = 16
## The categories whose picks set the waypoint rather than the target.
const WAYPOINT_CATEGORIES: Array[TargetCategories.Category] = [TargetCategories.Category.NAVIGATION,
		TargetCategories.Category.OBJECTIVES]

var radial: RadialMenu = RadialMenu.new()
## The category whose ring is open, or -1 on the first ring and when closed.
var category: int = -1

## Gives a ship's subsystem entries (`CapitalSubsystems.list`, nearest first) by its target id, or none for a hull that has none or
## whose make is not identified (M10-T18). Set by the owner; picking such a ship then opens its subsystem rings.
var subsystems_of: Callable = Callable()

var _counts: Dictionary = {}
# The subsystem entries and the pick they belong to while a subsystem ring is open.
var _subsystems: Array[Dictionary] = []
var _pending: Dictionary = {}
var _nearest: Dictionary = {}
var _objectives: Array[Dictionary] = []
var _own_position: Vector3 = Vector3.ZERO


## "850 m", "1.9 km".
static func range_text(range_m: float) -> String:
	return "%.1f km" % (range_m / 1000.0) if range_m >= 1000.0 else "%.0f m" % range_m


## Opens on the categories. `objectives` are the mission's active objectives that name a place or an actor, in the mission's
## order: `{text, label, target_id, point (UniversePos or null), position (World-local)}`; the first eight show.
## `base_id` is the launch base's target id (0 for none): it heads its ring while it is a candidate (maintainer, 2026-11-20).
func open(candidates: Array[TargetInfo], own_position: Vector3, own_faction: StringName,
		objectives: Array[Dictionary] = [], base_id: int = 0) -> void:
	_own_position = own_position
	var summary: Dictionary = TargetCategories.summarise(candidates, own_position, own_faction, TargetCategories.RING_SIZE,
			TargetCategories.IDENT_RANGE_M, base_id)
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
	_subsystems = []
	_pending = {}


## Which subsystem ring is open: 0 on none, 1 on the groups (whole ship, bridge, ...), 2 on one group's members.
func subsystem_level() -> int:
	return maxi(radial.depth() - 2, 0) if radial.is_open() and category >= 0 else 0


## How many entries `c` holds in all (the first ring's numbers).
func count(c: TargetCategories.Category) -> int:
	if c == TargetCategories.Category.OBJECTIVES:
		return _objectives.size()
	return int(_counts.get(c, 0))


## The page showing: `categories`, a category's name in lower case, or "" when closed.
func page_name() -> String:
	if not radial.is_open():
		return ""
	if subsystem_level() > 0:
		return "subsystems" if subsystem_level() == 1 else "members"
	return "categories" if category < 0 else String(TargetCategories.NAMES[category]).to_lower()


func point(v: Vector2) -> bool:
	return radial.point(v)


## B: from a category back to the categories, from the categories out. Returns whether the menu is still open.
func back() -> bool:
	var still_open: bool = radial.back()
	if radial.depth() < 2:
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
	if picked["action"] == ACTION_GROUP:
		picked = _open_members(picked["group"])
		if picked.is_empty():
			return {}
	if picked["action"] == ACTION_TARGET and subsystem_level() == 0 and _open_subsystems(picked):
		return {}
	close(&"pick")
	return picked


# A ship with subsystems opens its groups ring instead of being targeted at once: "whole ship" first, then each group it has
# (ring of at most eight). Returns whether a ring opened.
func _open_subsystems(picked: Dictionary) -> bool:
	if not subsystems_of.is_valid():
		return false
	var found: Array[Dictionary] = []
	found.assign(subsystems_of.call(int(picked["id"])))
	if found.is_empty():
		return false
	_subsystems = found
	_pending = picked
	var color: Color = radial.color()
	var whole: Dictionary = picked.duplicate()
	whole["subsystem"] = ""
	var entries: Array[Dictionary] = [{"label": CapitalSubsystems.WHOLE_LABEL, "sub": "", "color": color, "payload": whole}]
	for group: String in CapitalSubsystems.GROUPS:
		var members: Array[Dictionary] = CapitalSubsystems.members(found, group)
		if not members.is_empty():
			entries.append({"label": CapitalSubsystems.GROUP_LABELS[group], "sub": _group_sub(members), "color": color,
					"payload": {"action": ACTION_GROUP, "group": group}})
	radial.push("%s · %s" % [HEADING, str(picked["label"])], entries, color)
	return true


# A group with one member is that member's pick (returned); with more, its own ring of the first eight (nothing returned).
func _open_members(group: String) -> Dictionary:
	var members: Array[Dictionary] = CapitalSubsystems.members(_subsystems, group)
	if members.size() == 1:
		var only: Dictionary = _pending.duplicate()
		only["subsystem"] = members[0]["key"]
		return only
	var color: Color = radial.color()
	var entries: Array[Dictionary] = []
	for member: Dictionary in members.slice(0, TargetCategories.RING_SIZE):
		var pick: Dictionary = _pending.duplicate()
		pick["subsystem"] = member["key"]
		entries.append({"label": member["label"], "sub": CapitalSubsystems.state_text(member), "color": _state_color(member, color),
				"payload": pick})
	radial.push("%s · %s" % [HEADING, CapitalSubsystems.GROUP_LABELS[group]], entries, color)
	return {}


# "3 of 4 working" for a group, the state for a single member.
static func _group_sub(members: Array[Dictionary]) -> String:
	if members.size() == 1:
		return CapitalSubsystems.state_text(members[0])
	var working: int = 0
	for member: Dictionary in members:
		working += 1 if bool(member["works"]) else 0
	return "%d of %d working" % [working, members.size()]


static func _state_color(member: Dictionary, fallback: Color) -> Color:
	return fallback if bool(member["works"]) else Factions.UNIDENTIFIED_COLOR


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
	radial.push("%s · %s" % [HEADING, TargetCategories.NAMES[c]], RadialMenu.arrange(entries, none), color)


func _contact_entry(info: TargetInfo, c: TargetCategories.Category, color: Color) -> Dictionary:
	var label: String = UNKNOWN_LABEL if c == TargetCategories.Category.UNKNOWN else info.display_name.to_upper()
	# A nav buoy is a waypoint; a navigation target that offers an interaction (a bay, the gate) is targeted, so X can act on it.
	var waypoint: bool = c == TargetCategories.Category.NAVIGATION and info.interaction_kind == &""
	var action: StringName = ACTION_WAYPOINT if waypoint else ACTION_TARGET
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
