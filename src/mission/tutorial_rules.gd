class_name TutorialRules
extends RefCounted
## The tutorial's grading rules as data (M8 D79, `data/missions/tutorial_rules.json`): how a buoy-course time is rated against
## the instructor's own, and what the raid's losses make of the qualification. Pure.

const DEFAULT_PATH: String = "res://data/missions/tutorial_rules.json"
const EXEMPLARY: StringName = &"exemplary"
const PAR: StringName = &"par"
const BELOW_PAR: StringName = &"below_par"
const BUOY_DESTROYED: StringName = &"buoy_destroyed"
## Best first.
const RATINGS: Array[StringName] = [EXEMPLARY, PAR, BELOW_PAR, BUOY_DESTROYED]

## The instructor's own time round the course, s, and how far over it still rates exemplary and par (0.10: within 10 %).
var instructor_time_s: float = 60.0
var exemplary_within: float = 0.10
var par_within: float = 0.40
## The most Starfuries and civilians lost in the raid that still qualify the pilot as squadron leader at once.
var leader_max_starfuries_lost: int = 1
var leader_max_civilians_lost: int = 0
## Raiders through the jumpgate, and the number the strike carrier launches.
var gate_raiders: int = 6
var carrier_raiders: int = 8


## The rules in `path`: `{ok: true, rules}` or `{ok: false, error}`.
static func load_file(path: String = DEFAULT_PATH) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary):
		return {"ok": false, "error": "%s: not a JSON object" % path}
	return from_dict(data, path)


static func from_dict(data: Dictionary, source: String = "tutorial rules") -> Dictionary:
	var rules := TutorialRules.new()
	var course: Dictionary = data.get("course", {})
	var leader: Dictionary = data.get("squadron_leader", {})
	var raid: Dictionary = data.get("raid", {})
	rules.instructor_time_s = float(course.get("instructor_time_s", rules.instructor_time_s))
	rules.exemplary_within = float(course.get("exemplary_within", rules.exemplary_within))
	rules.par_within = float(course.get("par_within", rules.par_within))
	rules.leader_max_starfuries_lost = int(leader.get("max_starfuries_lost", rules.leader_max_starfuries_lost))
	rules.leader_max_civilians_lost = int(leader.get("max_civilians_lost", rules.leader_max_civilians_lost))
	rules.gate_raiders = int(raid.get("gate_raiders", rules.gate_raiders))
	rules.carrier_raiders = int(raid.get("carrier_raiders", rules.carrier_raiders))
	if rules.instructor_time_s <= 0.0:
		return {"ok": false, "error": "%s: course.instructor_time_s must be above 0" % source}
	if rules.exemplary_within < 0.0 or rules.par_within < rules.exemplary_within:
		return {"ok": false, "error": "%s: course.par_within must be at least exemplary_within, both 0 or more" % source}
	if rules.gate_raiders < 1 or rules.carrier_raiders < 1:
		return {"ok": false, "error": "%s: raid.gate_raiders and raid.carrier_raiders must be 1 or more" % source}
	return {"ok": true, "rules": rules}


func exemplary_time_s() -> float:
	return instructor_time_s * (1.0 + exemplary_within)


func par_time_s() -> float:
	return instructor_time_s * (1.0 + par_within)


## How a run of the course rates: a destroyed buoy is the worst whatever the time.
func rating(time_s: float, buoy_destroyed: bool) -> StringName:
	if buoy_destroyed:
		return BUOY_DESTROYED
	if time_s <= exemplary_time_s():
		return EXEMPLARY
	return PAR if time_s <= par_time_s() else BELOW_PAR


## The rank the tutorial earns: leader at once for an exemplary course and a raid with few enough losses, else the squadron.
func rank(course_rating: StringName, starfuries_lost: int, civilians_lost: int) -> StringName:
	if course_rating == EXEMPLARY and starfuries_lost <= leader_max_starfuries_lost \
			and civilians_lost <= leader_max_civilians_lost:
		return Career.SQUADRON_LEADER
	return Career.SQUADRON_PILOT


## A perfect score: no Starfury lost, whether or not the carrier got away.
static func perfect(starfuries_lost: int) -> bool:
	return starfuries_lost <= 0
