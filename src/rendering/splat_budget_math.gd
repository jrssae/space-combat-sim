class_name SplatBudgetMath
extends RefCounted
## Which ships draw a coarser level so the visible splats fit the budget (M3-T20, Q22). Pure.
##
## It works from each ship's wanted level, never the level drawn now, so stepping a ship down cannot change the next frame's plan.


## How many levels past its wanted one each ship should draw. `ships` holds, per ship: `wanted` (a level), `levels` (its chain,
## finest first), `splats` (per entry of `levels`), `distance` and `forced` (a level forced from the console stays as it is and
## counts as it is). `fixed` is the splats nothing can step down. The farthest ships go first, one level each per round, until the
## sum fits. Returns `extra` (one per ship), `fits` and `total` (the splats drawn, `fixed` included).
static func plan(ships: Array, fixed: int, budget: int) -> Dictionary:
	var extra := PackedInt32Array()
	extra.resize(ships.size())
	extra.fill(0)
	var at := PackedInt32Array()  # position in each ship's chain
	at.resize(ships.size())
	var total: int = fixed
	var movable: Array[int] = []
	for i: int in ships.size():
		var ship: Dictionary = ships[i]
		at[i] = chain_index(ship["levels"] as PackedInt32Array, int(ship["wanted"]))
		total += (ship["splats"] as PackedInt32Array)[at[i]]
		if not bool(ship["forced"]):
			movable.append(i)
	if total <= budget:
		return {"extra": extra, "fits": true, "total": total}
	movable.sort_custom(func(a: int, b: int) -> bool:
		var far_a: float = float((ships[a] as Dictionary)["distance"])
		var far_b: float = float((ships[b] as Dictionary)["distance"])
		return far_a > far_b if far_a != far_b else a < b)
	var stepped: bool = true
	while stepped and total > budget:
		stepped = false
		for i: int in movable:
			var ship: Dictionary = ships[i]
			var splats: PackedInt32Array = ship["splats"]
			if at[i] + 1 >= splats.size():
				continue
			total += splats[at[i] + 1] - splats[at[i]]
			at[i] += 1
			extra[i] += 1
			stepped = true
			if total <= budget:
				break
	return {"extra": extra, "fits": total <= budget, "total": total}


## Where a level sits in a chain: the nearest entry that is not finer than it, or the coarsest.
static func chain_index(levels: PackedInt32Array, level: int) -> int:
	for i: int in levels.size():
		if levels[i] >= level:
			return i
	return levels.size() - 1
