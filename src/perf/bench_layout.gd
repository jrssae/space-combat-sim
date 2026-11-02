class_name BenchLayout
extends RefCounted
## Where the benchmark's ships start (M4-T01, `docs/milestones/m4-performance-and-scale.md`, "Benchmark layouts"). Pure and
## seeded: the same layout, count and seed always give the same ships, places and pilots.
##
## The frame is the player's: the player at the origin with its nose along -Z (the runner turns it so). Half the ships are
## allied Starfuries (`ShipPool.ALLY_TYPE`, the `ally_starfury` profile), half raiders (`ShipPool.DEFAULT_TYPE`, `raider`).
## - `furball`: everyone in one fight in a 2 km ball 2.5 km ahead, allies on the near half facing the raiders on the far half,
##   so every ship sees every other one: the worst case for the scan and the behaviours.
## - `spread`: fights of about 12 (6 against 6, the setting's full squadron; maintainer 2026-11-02) on a 20 km lattice, the
##   first just ahead of the player. Ships of different fights are far out of each other's sensor range.
## - `transit`: wings of four (the setting's common patrol), alternating sides, on a 6 km lattice. Each leader flies a looped
##   square route at cruise, its wingmen in finger-four slots; every leader starts at the same corner, so the wings fly
##   parallel lanes. No fight: the runner makes the two sides neutral for the run (`fights`).
##
## Each entry: `type` (pool type), `offset` (m, from the player), `basis`, `velocity` (m/s), `behaviour` (a `BrainFactory`
## spec; a transit leader's carries its `patrol` route, relative to the player), `seed` (the brain's), `group` (the fight or
## wing index), `wing` (the transit wing's name, else empty) and `leader` (a transit wing's leader).

const FURBALL: StringName = &"furball"
const SPREAD: StringName = &"spread"
const TRANSIT: StringName = &"transit"
const NAMES: Array[StringName] = [FURBALL, SPREAD, TRANSIT]

## Where a fight's centre sits ahead of the player (furball, and spread's first fight), m.
const FIGHT_AHEAD_M: float = 2500.0
const FURBALL_RADIUS_M: float = 2000.0
## No two ships start closer than this, m.
const MIN_SPACING_M: float = 50.0
const GROUP_SIZE: int = 12
const GROUP_SPACING_M: float = 20000.0
## A spread fight's two sides: balls of this radius, this far ahead and behind the fight's centre, m.
const SIDE_RADIUS_M: float = 400.0
const SIDE_OFFSET_M: float = 600.0
const WING_SIZE: int = 4
const WING_SPACING_M: float = 6000.0
## A transit route is a square of this side around the wing's lattice point, flown at this speed.
const ROUTE_SIDE_M: float = 4000.0
const CRUISE_MPS: float = 80.0
const ALLY_PROFILE: String = "ally_starfury"
const RAIDER_PROFILE: String = "raider"
## Facing +Z: the far side of a fight looks back at the near side.
const FACING_BACK: Basis = Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0))


static func is_layout(layout: StringName) -> bool:
	return NAMES.has(layout)


## Whether the layout's sides fight (transit flies with them neutral).
static func fights(layout: StringName) -> bool:
	return layout != TRANSIT


## The ships of `layout` with `n` ships for `seed` (empty for an unknown layout or no ships).
static func plan(layout: StringName, n: int, seed_value: int) -> Array[Dictionary]:
	if n <= 0 or not is_layout(layout):
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([String(layout), n, seed_value])
	var out: Array[Dictionary] = []
	match layout:
		FURBALL:
			_furball(out, n, rng)
		SPREAD:
			_spread(out, n, rng)
		TRANSIT:
			_transit(out, n)
	for i: int in out.size():
		out[i]["seed"] = hash([String(layout), seed_value, i])
	return out


## The first `count` points of a cubic lattice of spacing `spacing_m`, nearest the first first, shifted `FIGHT_AHEAD_M` ahead.
static func lattice(count: int, spacing_m: float) -> Array[Vector3]:
	var reach: int = 0
	while (2 * reach + 1) * (2 * reach + 1) * (2 * reach + 1) < count:
		reach += 1
	var cells: Array[Vector3i] = []
	for x: int in range(-reach, reach + 1):
		for y: int in range(-reach, reach + 1):
			for z: int in range(-reach, reach + 1):
				cells.append(Vector3i(x, y, z))
	cells.sort_custom(_nearer_cell)
	var out: Array[Vector3] = []
	for i: int in count:
		out.append(Vector3(cells[i]) * spacing_m + Vector3(0.0, 0.0, -FIGHT_AHEAD_M))
	return out


## The centres of `count` spread fights.
static func group_centres(count: int) -> Array[Vector3]:
	return lattice(count, GROUP_SPACING_M)


static func _nearer_cell(a: Vector3i, b: Vector3i) -> bool:
	var la: int = a.x * a.x + a.y * a.y + a.z * a.z
	var lb: int = b.x * b.x + b.y * b.y + b.z * b.z
	if la != lb:
		return la < lb
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z


static func _furball(out: Array[Dictionary], n: int, rng: RandomNumberGenerator) -> void:
	var centre := Vector3(0.0, 0.0, -FIGHT_AHEAD_M)
	var taken: Array[Vector3] = []
	for i: int in n:
		var ally: bool = i % 2 == 0
		# Allies fill the half of the ball toward the player, raiders the far half.
		var at: Vector3 = _free_point(rng, centre, FURBALL_RADIUS_M, 1.0 if ally else -1.0, taken)
		out.append(_entry(ally, at, Basis.IDENTITY if ally else FACING_BACK, Vector3.ZERO, 0))


static func _spread(out: Array[Dictionary], n: int, rng: RandomNumberGenerator) -> void:
	var groups: int = maxi(1, roundi(float(n) / float(GROUP_SIZE)))
	var centres: Array[Vector3] = group_centres(groups)
	for g: int in groups:
		var size: int = n / groups + (1 if g < n % groups else 0)
		var taken: Array[Vector3] = []
		for k: int in size:
			# Alternating over the whole plan keeps the totals half and half when groups are odd.
			var ally: bool = (out.size() % 2) == 0
			var side: Vector3 = centres[g] + Vector3(0.0, 0.0, SIDE_OFFSET_M if ally else -SIDE_OFFSET_M)
			var at: Vector3 = _free_point(rng, side, SIDE_RADIUS_M, 0.0, taken)
			out.append(_entry(ally, at, Basis.IDENTITY if ally else FACING_BACK, Vector3.ZERO, g))


static func _transit(out: Array[Dictionary], n: int) -> void:
	var wings: int = ceili(float(n) / float(WING_SIZE))
	var centres: Array[Vector3] = lattice(wings, WING_SPACING_M)
	var half: float = ROUTE_SIDE_M * 0.5
	var slots := Formation.new()
	var allies: int = 0
	var raiders: int = 0
	for w: int in wings:
		var size: int = mini(WING_SIZE, n - w * WING_SIZE)
		var ally: bool = allies <= raiders
		var c: Vector3 = centres[w]
		# A square flown counter-clockwise seen from above, starting at its near left corner toward the far left one.
		var corners: Array[Vector3] = [c + Vector3(-half, 0.0, half), c + Vector3(-half, 0.0, -half),
				c + Vector3(half, 0.0, -half), c + Vector3(half, 0.0, half)]
		var nose: Vector3 = (corners[1] - corners[0]).normalized()
		var basis := Basis.looking_at(nose, Vector3.UP)
		var velocity: Vector3 = nose * CRUISE_MPS
		var route: Array = []
		for k: int in [1, 2, 3, 0]:
			route.append([corners[k].x, corners[k].y, corners[k].z])
		var wing_name: String = "TRANSIT %d" % (w + 1)
		for k: int in size:
			var at: Vector3 = corners[0] + basis * slots.offset(k)
			var e: Dictionary = _entry(ally, at, basis, velocity, w)
			e["wing"] = wing_name
			e["leader"] = k == 0
			if k == 0:
				(e["behaviour"] as Dictionary)["patrol"] = {"waypoints": route, "cruise_mps": CRUISE_MPS}
			out.append(e)
		if ally:
			allies += size
		else:
			raiders += size


static func _entry(ally: bool, at: Vector3, basis: Basis, velocity: Vector3, group: int) -> Dictionary:
	return {
		"type": ShipPool.ALLY_TYPE if ally else ShipPool.DEFAULT_TYPE,
		"offset": at,
		"basis": basis,
		"velocity": velocity,
		"behaviour": {"type": "ai", "profile": ALLY_PROFILE if ally else RAIDER_PROFILE},
		"seed": 0,
		"group": group,
		"wing": "",
		"leader": false,
	}


# A point in the ball (`half_sign` > 0: only its +Z half, < 0: only its -Z half, 0: all of it) at least `MIN_SPACING_M` from
# every point in `taken`, which it joins.
static func _free_point(rng: RandomNumberGenerator, centre: Vector3, radius: float, half_sign: float,
		taken: Array[Vector3]) -> Vector3:
	var at: Vector3 = centre
	for attempt: int in 200:
		var direction := Vector3(rng.randfn(), rng.randfn(), rng.randfn())
		if direction.length_squared() < 1e-12:
			continue
		direction = direction.normalized()
		if half_sign != 0.0 and signf(direction.z) != signf(half_sign):
			direction.z = -direction.z
		at = centre + direction * radius * pow(rng.randf(), 1.0 / 3.0)
		var clear: bool = true
		for other: Vector3 in taken:
			if other.distance_squared_to(at) < MIN_SPACING_M * MIN_SPACING_M:
				clear = false
				break
		if clear:
			break
	taken.append(at)
	return at
