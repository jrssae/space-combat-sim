class_name HangarRules
extends RefCounted
## What a capital carrier's hangar decides (M10-T17, D12.10, Q73; the recovery of Q25 to Q30): when it launches a wing, when the
## next one, and when its craft come home. Pure: numbers in, a decision out; `CapitalHangar` does it. The numbers are data
## (`capitals.json`, `carrier_launch`: its `defaults` under a hull's own entry).

const DEFAULTS: Dictionary = {
	"wings": [12],  # fighters launched at a time, first wing first
	"next_wing_threat": 1.5,  # the next wing goes once the threat is this many times what the last one met
	"warship_weight": 6.0,  # a hostile warship counts as this many fighters
	"next_wing_losses": 0.25,  # or once the wings out have lost this share of their fighters
	"calm_s": 30.0,  # no hostile within reach this long: everyone comes home
	"fighter_return_hull": 0.2,  # a fighter under this share of its hull comes home alone
	"wait_s": 90.0,  # before a jump it waits this long for its craft, then leaves the rest
	"launch_gap_s": 0.8,  # between two craft leaving one bay
	"lanes": 3,  # craft side by side at the back of a big hall
	"elevator_abreast": 3,  # craft side by side on a lift
	"elevator_rows": 2,  # and rows of them a trip,
	"elevator_row_gap_m": 14.0,  # this far apart along the hall
	"approach_m": 60.0,  # a returning craft is taken in this far outside the mouth
	"clear_m": 40.0,  # a launch lets go this far past the mouth
	"door_lead_m": 1500.0,  # a door opens for a returning craft this far out
}


## A hull's options: its own entry over the file's defaults over `DEFAULTS`.
static func options(hull_type: StringName) -> Dictionary:
	var table: Dictionary = CapitalData.table("carrier_launch")
	var out: Dictionary = DEFAULTS.duplicate(true)
	var hulls: Dictionary = table.get("hulls", {}) if table.get("hulls") is Dictionary else {}
	for layer: Variant in [table.get("defaults", {}), hulls.get(String(hull_type), {})]:
		if layer is Dictionary:
			for key: Variant in layer:
				out[key] = layer[key]
	var wings: Array = []
	for n: Variant in out["wings"] if out["wings"] is Array else [out["wings"]]:
		if int(n) > 0:
			wings.append(int(n))
	out["wings"] = wings
	return out


## The threat as one number: hostile fighters, a warship counting `warship_weight` of them.
static func threat(fighters: int, warships: int, warship_weight: float) -> float:
	return float(maxi(fighters, 0)) + float(maxi(warships, 0)) * warship_weight


## How many fighters wing `index` (0 first) takes with `left` in the hangar: its share by `wings`, at most what is left; a last
## wing takes the rest. 0 once every wing has gone.
static func wing_size(wings: Array, index: int, left: int) -> int:
	if index < 0 or index >= wings.size() or left <= 0:
		return 0
	if index == wings.size() - 1:
		return left
	return mini(int(wings[index]), left)


## Whether the first wing goes: a hostile is within reach and nothing has launched yet.
static func first_wing_due(threat_now: float, wings_out: int) -> bool:
	return wings_out == 0 and threat_now > 0.0


## Whether the next wing goes (Q73): some are out, more wings wait, and the threat has grown to `next_wing_threat` times what
## the last wing met, or the wings out have lost `next_wing_losses` of what they took out.
static func next_wing_due(threat_now: float, threat_at_last: float, launched: int, lost: int, options: Dictionary) -> bool:
	if launched <= 0:
		return false
	var grew: bool = threat_now >= float(options["next_wing_threat"]) * maxf(threat_at_last, 1.0)
	var hurt: bool = float(lost) >= float(options["next_wing_losses"]) * float(launched)
	return grew or hurt


## Whether everyone comes home because the fight is over: nothing hostile within reach for `calm_s`.
static func fight_over(calm_for_s: float, options: Dictionary) -> bool:
	return calm_for_s >= float(options["calm_s"])


## Whether one craft comes home alone: its hull is under its share.
static func goes_home(hull_fraction: float, options: Dictionary) -> bool:
	return hull_fraction < float(options["fighter_return_hull"])


## Whether a carrier about to jump stops waiting (Q73, Q27): nobody is still on the way back, or their time is up.
static func may_leave(returning: int, waited_s: float, options: Dictionary) -> bool:
	return returning <= 0 or waited_s >= float(options["wait_s"])


## The callsign of a carrier's `k`-th wing (0 first) for `faction`, from the file's `callsigns` (the faction's own, else
## `default`), round again with a number after a full turn.
static func callsign(faction: StringName, k: int) -> String:
	var table: Dictionary = CapitalData.table("carrier_launch").get("callsigns", {}) as Dictionary
	var names: Array = table.get(String(faction), table.get("default", ["Wing"])) as Array
	if names.is_empty():
		names = ["Wing"]
	var base: String = str(names[k % names.size()])
	return base if k < names.size() else "%s%d" % [base, k / names.size() + 1]
