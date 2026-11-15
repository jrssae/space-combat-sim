class_name BotCrew
extends RefCounted
## The station's maintenance crew (M7-T35): who goes out of the cargo bay, where and when. Pure: the fleet feeds it the clock and
## the alarms each tick, it starts and recalls trips on the bots' motions and turns a working bot's time into repairs.
##
## - **Peace:** each patrol area (the spine, the fins, the drum, the jumpgate) sends one bot at a time, after a wait drawn from a
##   hash of the area and its trip number, so the bots come and go irregularly; `peace_min` to `peace_max` are out at once, and
##   none starts while fighting is near the station. A peace bot near a fight turns for home (T11's habit).
## - **Battle:** every damaged area (a section or a grid mount) gets one bot, the most urgent first, up to `battle_max` repairing
##   at once; a short pool calls peace bots home to free them. A bot at its work spot adds `repair_hp_s` to its area each second
##   until it is whole, then flies home; while hits land close to it, it backs off and waits.
## - **One bot per area**, in peace and battle alike: an area keeps its bot until the bot is back in the bay.

var data: BotData = null
var frames: BotFrames = null
var areas: BotRepairAreas = null
var planner: BotTripPlanner = null
var motions: Array[BotCrewMotion] = []
## Per peace area (in `data.peace` order): the bot on it or -1, trips flown, and when the next may start (crew clock, s).
var peace_bot := PackedInt32Array()
var peace_trips := PackedInt32Array()
var peace_due_s := PackedFloat64Array()
## Per repair area: the bot on it or -1.
var repair_bot := PackedInt32Array()
## Health added by the crew so far, for the console.
var repaired_hp: float = 0.0
## False stops new peace trips (`bots peace off`); battle repairs go on.
var peace_on: bool = true

var _area_of_bot := PackedInt32Array()
var _repair_of_bot := PackedInt32Array()


static func make(p_data: BotData, p_frames: BotFrames, p_areas: BotRepairAreas, dock: Vector3) -> BotCrew:
	var crew := BotCrew.new()
	crew.data = p_data
	crew.frames = p_frames
	crew.areas = p_areas
	crew.planner = BotTripPlanner.make(p_data, p_frames, p_areas)
	for i: int in p_data.pool:
		var m := BotCrewMotion.new()
		m.setup(p_frames, dock, p_data.accel_mps2, p_data.spin_s)
		crew.motions.append(m)
	crew._area_of_bot.resize(p_data.pool)
	crew._area_of_bot.fill(-1)
	crew._repair_of_bot.resize(p_data.pool)
	crew._repair_of_bot.fill(-1)
	var n: int = p_data.peace.size()
	crew.peace_bot.resize(n)
	crew.peace_bot.fill(-1)
	crew.peace_trips.resize(n)
	crew.peace_due_s.resize(n)
	for a: int in n:
		# The first trips start spread over a whole wait, each area at its own moment.
		crew.peace_due_s[a] = p_data.peace_wait_s.y * unit_of(p_data.peace[a]["name"], -1)
	crew.repair_bot.resize(p_areas.count() if p_areas != null else 0)
	crew.repair_bot.fill(-1)
	return crew


static func unit_of(area_name: String, n: int) -> float:
	return BotTripPlanner.unit([area_name, n, "wait"])


## One crew decision at crew time `now_s`: free the areas whose bots are home, send repair bots, recall peace bots near a fight
## (`alarmed[i]` per bot) and send peace bots when it is quiet (`quiet`).
func decide(now_s: float, alarmed: PackedByteArray, quiet: bool) -> void:
	_release_homeward(now_s)
	_send_repairs()
	for i: int in motions.size():
		if _area_of_bot[i] >= 0 and i < alarmed.size() and alarmed[i] != 0:
			motions[i].recall()
	_release_homeward(now_s)
	if quiet and peace_on:
		_send_peace(now_s)


## A tick of work after the bots moved: each bot at its work spot repairs its area by `delta` seconds' worth; `duck[i]` true
## sends bot `i` back off its spot.
func work(delta: float, duck: PackedByteArray) -> void:
	for i: int in motions.size():
		var m: BotCrewMotion = motions[i]
		var area: int = _repair_of_bot[i]
		if area < 0 or m.is_docked():
			continue
		m.duck_goal_m = data.duck_m if i < duck.size() and duck[i] != 0 and m.can_duck() else 0.0
		if not m.at_work():
			continue
		var amount: float = data.repair_hp_s * delta
		var before: float = areas.health_of(area).x
		var whole: bool = areas.repair(area, amount)
		repaired_hp += areas.health_of(area).x - before
		if whole:
			m.work_done()


## Sends a peace bot to area `a` now, whatever its wait (`bots send`); false when it has one out or no bot is free.
func send_peace(a: int, now_s: float) -> bool:
	if a < 0 or a >= peace_bot.size() or peace_bot[a] >= 0:
		return false
	return _launch_peace(a, now_s)


## Calls every peace bot home.
func recall_peace() -> void:
	for i: int in motions.size():
		if _area_of_bot[i] >= 0:
			motions[i].recall()


func out_count() -> int:
	var n: int = 0
	for m: BotCrewMotion in motions:
		n += 0 if m.is_docked() else 1
	return n


func peace_out() -> int:
	var n: int = 0
	for i: int in motions.size():
		n += 1 if _area_of_bot[i] >= 0 and not motions[i].is_docked() else 0
	return n


func repair_out() -> int:
	var n: int = 0
	for i: int in motions.size():
		n += 1 if _repair_of_bot[i] >= 0 and not motions[i].is_docked() else 0
	return n


## Bots working at their spot now.
func working() -> int:
	var n: int = 0
	for i: int in motions.size():
		n += 1 if _repair_of_bot[i] >= 0 and motions[i].at_work() else 0
	return n


## What bot `i` is on: the peace area's or repair area's name, or "".
func job_of(i: int) -> String:
	if _area_of_bot[i] >= 0:
		return String(data.peace[_area_of_bot[i]]["name"])
	if _repair_of_bot[i] >= 0:
		return areas.name_of(_repair_of_bot[i])
	return ""


## The repair area bot `i` works on, or -1.
func repair_area_of(i: int) -> int:
	return _repair_of_bot[i]


func _free_bot() -> int:
	for i: int in motions.size():
		if motions[i].is_docked() and _area_of_bot[i] < 0 and _repair_of_bot[i] < 0:
			return i
	return -1


# An area's claim ends when its bot is back in the bay (one bot an area, out and home), and the bot is free again.
func _release_homeward(now_s: float) -> void:
	for i: int in motions.size():
		if not motions[i].is_docked():
			continue
		var a: int = _area_of_bot[i]
		if a >= 0:
			if peace_bot[a] == i:
				peace_bot[a] = -1
				peace_due_s[a] = now_s + lerpf(data.peace_wait_s.x, data.peace_wait_s.y, unit_of(data.peace[a]["name"], peace_trips[a]))
			_area_of_bot[i] = -1
		var r: int = _repair_of_bot[i]
		if r >= 0:
			if repair_bot[r] == i:
				repair_bot[r] = -1
			_repair_of_bot[i] = -1


func _send_repairs() -> void:
	if areas == null:
		return
	for area: int in areas.damaged():
		if repair_bot[area] >= 0:
			continue
		if repair_out() >= data.battle_max:
			return
		var bot: int = _free_bot()
		if bot < 0:
			recall_peace()  # the peace bots come home to be sent out again
			return
		var trip: BotTrip = planner.repair_trip(area)
		if trip == null:
			continue
		motions[bot].start(trip)
		_repair_of_bot[bot] = area
		repair_bot[area] = bot


func _send_peace(now_s: float) -> void:
	var out: int = peace_out()
	while out < data.peace_max:
		# The area most overdue goes; below the floor the next one due goes at once.
		var pick: int = -1
		for a: int in peace_bot.size():
			if peace_bot[a] >= 0 or not _can_fly(a):
				continue
			if pick < 0 or peace_due_s[a] < peace_due_s[pick]:
				pick = a
		if pick < 0 or (peace_due_s[pick] > now_s and out >= data.peace_min):
			return
		if not _launch_peace(pick, now_s):
			return
		out += 1


func _can_fly(a: int) -> bool:
	return String(data.peace[a]["kind"]) != "gate" or frames.has_gate


func _launch_peace(a: int, _now_s: float) -> bool:
	var bot: int = _free_bot()
	if bot < 0:
		return false
	var trip: BotTrip = planner.peace_trip(data.peace[a], peace_trips[a])
	if trip == null:
		return false
	peace_trips[a] += 1
	motions[bot].start(trip)
	_area_of_bot[bot] = a
	peace_bot[a] = bot
	return true
