class_name LaunchCut
extends RefCounted
## Chooses a launch's camera cut (M7-T08, maintainer: "multiple cinematic camera options ... so they never feel stale"): one shot
## variant per phase of the launch from the profile's pools (`LaunchProfile.phases`), each pool drawn from a shuffle bag so no
## variant comes back before the rest of its pool has played, and none plays twice in a row. An optional phase is left out now and
## then, so cuts differ in length too. A wave of `row_wave_min` or more fighters films its drop with a row shot (held over several
## ejections, maintainer) and leaves the exit out: longer, wider shots of the row rather than a cut per fighter.
##
## Seeded, never a shared generator: every draw is a hash of the launch's seed, the phase and the draw, so a pinned seed gives the
## same cut. The bags are this object's own: keep one per scenario run (`LaunchDirector` does), so the variety runs across launches.
## M8's squadron launch draws from the same pools.

var profile: LaunchProfile = null
## Per phase name: the variant indices still in the bag, and the one played last (-1 none).
var _bags: Dictionary = {}
var _last: Dictionary = {}
## Every cut so far, oldest first: each an Array of `{phase, variant}` ids (for the console and tests).
var history: Array[Array] = []


func _init(p_profile: LaunchProfile) -> void:
	profile = p_profile


## One launch's cut with `seed_value` for a first wave of `wave_size` fighters: the chosen shots in phase order, each
## `{phase, variant, shot, step, at_s, fill, row, subject}`; a phase left out is missing.
func pick(seed_value: int, wave_size: int = 1) -> Array[Dictionary]:
	var wave: bool = wave_size >= profile.row_wave_min
	var out: Array[Dictionary] = []
	var record: Array = []
	for p: int in profile.phases.size():
		var phase: Dictionary = profile.phases[p]
		var name: String = phase["phase"]
		var variants: Array = phase["variants"]
		if variants.is_empty():
			continue
		if float(phase["optional"]) > 0.0 and (wave or unit(seed_value, name, -1) < float(phase["optional"])):
			continue
		var rows_only: bool = wave and variants.any(func(v: Dictionary) -> bool: return bool(v["row"]))
		var i: int = _draw(seed_value, name, variants, rows_only)
		var v: Dictionary = variants[i]
		out.append({"phase": name, "variant": v["id"], "shot": v["shot"], "step": phase["step"], "at_s": float(phase["at_s"]),
				"fill": v["fill"], "row": bool(v["row"]), "subject": v["subject"]})
		record.append({"phase": name, "variant": String(v["id"])})
	history.append(record)
	return out


## A seeded number in [0, 1) for `seed_value`, a name and a draw: the same arguments always give the same number.
static func unit(seed_value: int, name: String, draw: int) -> float:
	return float(hash([seed_value, name, draw]) & 0xFFFFFF) / float(0x1000000)


# Takes a variant out of the phase's bag (a bag of the row variants alone for a wave), weighted, refilling it when empty and never
# the one played last.
func _draw(seed_value: int, name: String, variants: Array, rows_only: bool = false) -> int:
	var bag_name: String = name + (" (wave)" if rows_only else "")
	var bag: Array = _bags.get(bag_name, [])
	var last: int = int(_last.get(name, -1))
	if bag.is_empty():
		for i: int in variants.size():
			if not rows_only or bool((variants[i] as Dictionary)["row"]):
				bag.append(i)
	var choices: Array = bag.filter(func(i: int) -> bool: return i != last)
	if choices.is_empty():
		choices = bag
	var total: float = 0.0
	for i: int in choices:
		total += float((variants[i] as Dictionary)["weight"])
	var at: float = unit(seed_value, bag_name, bag.size()) * total
	var chosen: int = choices[-1]
	for i: int in choices:
		at -= float((variants[i] as Dictionary)["weight"])
		if at < 0.0:
			chosen = i
			break
	bag.erase(chosen)
	_bags[bag_name] = bag
	_last[name] = chosen
	return chosen
