class_name Career
extends RefCounted
## The pilot's standing across missions (M8 D79): the rank earned so far and the best buoy-course rating. Pure; `CareerStore`
## keeps it on disk beside the settings. A rank is only ever raised: a worse run later never takes one away.

const UNASSIGNED: StringName = &"unassigned"
const SQUADRON_PILOT: StringName = &"squadron_pilot"
const SQUADRON_LEADER: StringName = &"squadron_leader"
## Lowest first.
const RANKS: Array[StringName] = [UNASSIGNED, SQUADRON_PILOT, SQUADRON_LEADER]
const RANK_NAMES: Dictionary = {
	UNASSIGNED: "Unassigned pilot",
	SQUADRON_PILOT: "Squadron pilot",
	SQUADRON_LEADER: "Squadron leader",
}

var rank: StringName = UNASSIGNED
## The best course rating flown (`TutorialRules.RATINGS`), or &"" before any.
var course: StringName = &""


## Raises the rank to `p_rank` if it is higher. Returns whether it changed.
func award(p_rank: StringName) -> bool:
	if RANKS.find(p_rank) <= RANKS.find(rank):
		return false
	rank = p_rank
	return true


## Sets the rank outright (the console). Returns false for a word that is no rank.
func set_rank(p_rank: StringName) -> bool:
	if not RANKS.has(p_rank):
		return false
	rank = p_rank
	return true


func rank_name() -> String:
	return String(RANK_NAMES.get(rank, String(rank)))


func describe() -> String:
	return "%s%s" % [rank_name(), "" if course == &"" else " (buoy course: %s)" % String(course).replace("_", " ")]


func to_dict() -> Dictionary:
	return {"rank": String(rank), "course": String(course)}


## A career from saved data; anything unreadable gives a fresh one, and a course rating that is none reads as never flown
## (an unknown word would rank below every real rating and block each later improvement).
static func from_dict(data: Variant) -> Career:
	var out := Career.new()
	if data is Dictionary:
		out.set_rank(StringName(str((data as Dictionary).get("rank", UNASSIGNED))))
		var saved := StringName(str((data as Dictionary).get("course", "")))
		out.course = saved if TutorialRules.RATINGS.has(saved) else &""
	return out
