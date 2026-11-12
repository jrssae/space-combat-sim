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
## - `battle` (M4-T07, Q15, Q19, Q21): the grand multi-side battle, `BattleMix.GRAND`. Fights of 24 on an 8 km lattice, the
##   player's fight first, four sides every pair hostile, each side's fighters coming in from its own direction (+Z, -Z, +X,
##   -X) and its capitals 5 km behind its fights, cruising into them. An asteroid slab over the player's fight, the battle in a low orbit of Epsilon III.
##   Mine belts (M4-T12) 1.5 km out from each fight, each side's toward its own direction (`mines`).
## - `typical` (M4-T07, Q21): most missions, `BattleMix.TYPICAL`: two fights of about 25 on two sides, the capitals behind.
##   N counts fighters and capitals; the mix fixes how many of each.
##
## Each entry: `kind` (`fighter` or `capital`), `type` (pool type; `capital` for a capital), `class` (a capital's), `faction`,
## `side` (index into `sides`), `radius` (m, a capital's hull sphere, 0 for a fighter), `offset` (m, from the player),
## `basis`, `velocity` (m/s), `behaviour` (a `BrainFactory` spec; a transit leader's carries its `patrol` route, relative to
## the player), `seed` (the brain's), `group` (the fight or wing index), `fight_centre` (battle and typical), `wing` (the
## transit wing's name, else empty) and `leader` (a transit wing's leader).

const FURBALL: StringName = &"furball"
const SPREAD: StringName = &"spread"
const TRANSIT: StringName = &"transit"
const BATTLE: StringName = &"battle"
const TYPICAL: StringName = &"typical"
const NAMES: Array[StringName] = [FURBALL, SPREAD, TRANSIT, BATTLE, TYPICAL]
## The M4-T01 layouts: fighters only, allies against raiders.
const FIGHTER_LAYOUTS: Array[StringName] = [FURBALL, SPREAD, TRANSIT]
const KIND_FIGHTER: StringName = &"fighter"
const KIND_CAPITAL: StringName = &"capital"

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

## Battle and typical (M4-T07). A fight's fighters, its lattice spacing, and each side's ball: this far out from the centre
## along the side's direction, this wide. A side's capitals sit `CAPITAL_STANDOFF_M` behind its fight, side by side.
const FIGHT_SIZE: int = 24
const FIGHT_SPACING_M: float = 8000.0
const FIGHT_SIDE_OFFSET_M: float = 800.0
const FIGHT_SIDE_RADIUS_M: float = 400.0
const CAPITAL_STANDOFF_M: float = 5000.0
const CAPITAL_LATERAL_M: float = 2500.0
## The sides, the first two the game's own; the bench factions exist only while a battle runs (`faction_table`).
const BATTLE_SIDES: Array[StringName] = [Factions.EARTH_ALLIANCE, Factions.RAIDERS, &"bench_c", &"bench_d"]
## Each side's fighters: the pool they come from and the profile they fly.
const SIDE_TYPES: Array[StringName] = [ShipPool.ALLY_TYPE, ShipPool.DEFAULT_TYPE, ShipPool.DEFAULT_TYPE, ShipPool.ALLY_TYPE]
const SIDE_PROFILES: Array[String] = [ALLY_PROFILE, RAIDER_PROFILE, RAIDER_PROFILE, ALLY_PROFILE]
## The asteroid slab, centred on the player's fight: rocks of these radii, never this close to a ship's hull.
const ROCK_SLAB_M: Vector3 = Vector3(20000.0, 5000.0, 20000.0)
const ROCK_RADIUS_MIN_M: float = 20.0
const ROCK_RADIUS_MAX_M: float = 200.0
const ROCK_CLEARANCE_M: float = 100.0
## Mine belts (M4-T12): each side's share of a fight's mines on an arc 90 degrees wide toward its own direction, this far out
## from the fight's centre (between its fighters' start and its capitals), this deep and this high either way, m.
const MINE_BELT_RADIUS_M: float = 1500.0
const MINE_BELT_DEPTH_M: float = 150.0
const MINE_BELT_HEIGHT_M: float = 150.0
const MINE_BELT_ARC_RAD: float = PI / 2.0
## The battle's gravity (Q22, M6-T07): the battle is flown in a low orbit of this body of the star system's data, so the
## tide of a real body's pull reaches every mover (about 0.026 m/s^2 10 km from the battle's centre).
const GRAVITY_BODY: StringName = &"epsilon_iii"
const GRAVITY_ALTITUDE_M: float = 400000.0


static func is_layout(layout: StringName) -> bool:
	return NAMES.has(layout)


## Whether the layout's sides fight (transit flies with them neutral).
static func fights(layout: StringName) -> bool:
	return layout != TRANSIT


## Whether the layout carries the battle's stand-ins and its mix (M4-T07).
static func has_mix(layout: StringName) -> bool:
	return layout == BATTLE or layout == TYPICAL


## The capital share a run uses in place of its profile's (the 1 000 stretch's upper edge, M4-T25); below 0 the profile's.
static var capital_share: float = -1.0


## The `BattleMix` counts of `layout` at `n` ships; empty for a layout without a mix.
static func mix(layout: StringName, n: int) -> Dictionary:
	var p: Dictionary = {}
	match layout:
		BATTLE:
			p = BattleMix.profile(BattleMix.GRAND)
		TYPICAL:
			p = BattleMix.profile(BattleMix.TYPICAL)
		_:
			return {}
	if capital_share >= 0.0:
		p["capital_share"] = capital_share
	return BattleMix.counts(p, n)


## The factions that fly in `layout`, by side index.
static func sides(layout: StringName) -> Array[StringName]:
	var count: int = int(mix(layout, 1).get("sides", 2))
	return BATTLE_SIDES.slice(0, count)


## The session faction table a layout needs (every pair of its sides hostile), or null when the game's own will do.
static func faction_table(layout: StringName) -> FactionTable:
	var list: Array[StringName] = sides(layout)
	if list.size() <= 2:
		return null
	var factions: Array = []
	var relations: Array = []
	for i: int in list.size():
		factions.append({"id": String(list[i]), "name": String(list[i]).capitalize()})
		for j: int in range(i + 1, list.size()):
			relations.append({"a": String(list[i]), "b": String(list[j]), "relation": "hostile"})
	factions.append({"id": String(Factions.NEUTRAL), "name": "Neutral"})
	var made: Dictionary = FactionTable.from_dict({"factions": factions, "relations": relations, "default": "neutral"})
	return made["table"] if bool(made["ok"]) else null


## Where a side comes in from, and its capitals sit: a unit vector out from the fight's centre.
static func side_direction(side: int) -> Vector3:
	return [Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT][side % 4]


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
		BATTLE, TYPICAL:
			_battle(out, layout, n, rng)
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
	return _fighter(0 if ally else 1, at, basis, velocity, group)


static func _fighter(side: int, at: Vector3, basis: Basis, velocity: Vector3, group: int) -> Dictionary:
	return {
		"kind": KIND_FIGHTER,
		"type": SIDE_TYPES[side],
		"class": "",
		"faction": BATTLE_SIDES[side],
		"side": side,
		"radius": 0.0,
		"offset": at,
		"basis": basis,
		"velocity": velocity,
		"behaviour": {"type": "ai", "profile": SIDE_PROFILES[side]},
		"seed": 0,
		"group": group,
		"fight_centre": Vector3.ZERO,
		"wing": "",
		"leader": false,
	}


# Fights of `FIGHT_SIZE` on the lattice, each side's fighters in a ball on its own side of the centre facing in, then each
# side's capitals behind its fights in turn, side by side when a fight has more than one.
static func _battle(out: Array[Dictionary], layout: StringName, n: int, rng: RandomNumberGenerator) -> void:
	var m: Dictionary = mix(layout, n)
	var side_count: int = int(m["sides"])
	var fighters: int = int(m["fighters"])
	var centres: Array[Vector3] = fight_centres(layout, n)
	var groups: int = centres.size()
	for g: int in groups:
		var size: int = fighters / groups + (1 if g < fighters % groups else 0)
		var taken: Array[Vector3] = []
		for k: int in size:
			# Sides taken in turn over the whole plan keep them even when a fight's size does not divide.
			var side: int = out.size() % side_count
			var direction: Vector3 = side_direction(side)
			var ball: Vector3 = centres[g] + direction * FIGHT_SIDE_OFFSET_M
			var at: Vector3 = _free_point(rng, ball, FIGHT_SIDE_RADIUS_M, 0.0, taken)
			var e: Dictionary = _fighter(side, at, Basis.looking_at(-direction, Vector3.UP), Vector3.ZERO, g)
			e["fight_centre"] = centres[g]
			out.append(e)
	var placed: PackedInt32Array = PackedInt32Array()
	placed.resize(side_count)
	var classes: Array[StringName] = BattleMix.class_order(m)
	for j: int in classes.size():
		var side: int = j % side_count
		var k: int = placed[side]
		placed[side] = k + 1
		var fight: int = k % groups
		var slot: int = k / groups
		var direction: Vector3 = side_direction(side)
		var across: Vector3 = Vector3.RIGHT if absf(direction.z) > 0.5 else Vector3.BACK
		# Slot 0 straight behind the fight, then alternately either side of it.
		var lateral: float = float((slot + 1) / 2) * (1.0 if slot % 2 == 1 else -1.0) * CAPITAL_LATERAL_M
		var at: Vector3 = centres[fight] + direction * CAPITAL_STANDOFF_M + across * lateral
		out.append({
			"kind": KIND_CAPITAL,
			"type": KIND_CAPITAL,
			"class": String(classes[j]),
			"faction": BATTLE_SIDES[side],
			"side": side,
			"radius": CapitalStandin.hull_radius(classes[j]),
			"offset": at,
			"basis": Basis.looking_at(-direction, Vector3.UP),
			"velocity": -direction * CapitalStandin.CRUISE_MPS,
			"behaviour": {},
			"seed": 0,
			"group": fight,
			"fight_centre": centres[fight],
			"wing": "",
			"leader": false,
		})


## The centres of the fights of `layout` at `n` ships: the player's first, the rest nearest it on the `FIGHT_SPACING_M`
## lattice, in as many layers as the area's depth holds.
static func fight_centres(layout: StringName, n: int) -> Array[Vector3]:
	var m: Dictionary = mix(layout, n)
	if m.is_empty():
		return []
	var groups: int = maxi(1, roundi(float(m["fighters"]) / float(FIGHT_SIZE)))
	var layers: int = floori((m["area_m"] as Vector3).y * 0.5 / FIGHT_SPACING_M)
	return slab_lattice(groups, FIGHT_SPACING_M, layers)


## The first `count` points of a lattice of spacing `spacing_m` at most `layers` cells above and below the first, nearest the
## first first, shifted `FIGHT_AHEAD_M` ahead.
static func slab_lattice(count: int, spacing_m: float, layers: int) -> Array[Vector3]:
	var reach: int = 0
	while (2 * reach + 1) * (2 * reach + 1) * (2 * mini(reach, layers) + 1) < count:
		reach += 1
	var cells: Array[Vector3i] = []
	var depth: int = mini(reach, layers)
	for x: int in range(-reach, reach + 1):
		for y: int in range(-depth, depth + 1):
			for z: int in range(-reach, reach + 1):
				cells.append(Vector3i(x, y, z))
	cells.sort_custom(_nearer_cell)
	var out: Array[Vector3] = []
	for i: int in count:
		out.append(Vector3(cells[i]) * spacing_m + Vector3(0.0, 0.0, -FIGHT_AHEAD_M))
	return out


## The asteroid slab of `layout` (box in the player's frame), centred on the player's fight; empty for a layout without rocks.
static func rock_slab(layout: StringName, n: int) -> AABB:
	var centres: Array[Vector3] = fight_centres(layout, n)
	if centres.is_empty():
		return AABB()
	return AABB(centres[0] - ROCK_SLAB_M * 0.5, ROCK_SLAB_M)


## How many of the layout's fights lie inside its rock slab.
static func fights_in_slab(layout: StringName, n: int) -> int:
	var slab: AABB = rock_slab(layout, n)
	var inside: int = 0
	for c: Vector3 in fight_centres(layout, n):
		inside += 1 if slab.has_point(c) else 0
	return inside


## The rocks of `layout` for `seed`: `offset` (m, from the player) and `radius` (m), log-uniform in size, seeded, none within
## `ROCK_CLEARANCE_M` of the player or a ship's hull; the mix's count, or `count_override` when 0 or more. Empty for a layout
## without rocks.
static func rocks(layout: StringName, n: int, seed_value: int, count_override: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var count: int = int(mix(layout, n).get("asteroids", 0)) if count_override < 0 else count_override
	if count <= 0 or not has_mix(layout):
		return out
	var ships: Array[Dictionary] = plan(layout, n, seed_value)
	var slab: AABB = rock_slab(layout, n)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([String(layout), n, seed_value, "rocks"])
	for i: int in count:
		for attempt: int in 50:
			var radius: float = ROCK_RADIUS_MIN_M * pow(ROCK_RADIUS_MAX_M / ROCK_RADIUS_MIN_M, rng.randf())
			var at: Vector3 = slab.position + Vector3(rng.randf(), rng.randf(), rng.randf()) * slab.size
			if _rock_clear(at, radius, ships):
				out.append({"offset": at, "radius": radius})
				break
	return out


static func _rock_clear(at: Vector3, radius: float, ships: Array[Dictionary]) -> bool:
	if at.length() - radius < ROCK_CLEARANCE_M:
		return false
	for e: Dictionary in ships:
		var reach: float = radius + float(e["radius"]) + ROCK_CLEARANCE_M
		if at.distance_squared_to(e["offset"] as Vector3) < reach * reach:
			return false
	return true


## The mine belts of `layout` for `seed` (M4-T12): the mix's mines shared out over the fights and, in each, over the sides in
## turn, each on its side's arc. Each: `offset` (m, from the player), `faction`, `side`, `fight_centre`. None inside a trigger
## radius of a ship's starting hull. Empty for a layout without a mix.
static func mines(layout: StringName, n: int, seed_value: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var count: int = int(mix(layout, n).get("mines", 0))
	var centres: Array[Vector3] = fight_centres(layout, n)
	if count <= 0 or centres.is_empty():
		return out
	var ships: Array[Dictionary] = plan(layout, n, seed_value)
	var side_list: Array[StringName] = sides(layout)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([String(layout), n, seed_value, "mines"])
	for g: int in centres.size():
		var size: int = count / centres.size() + (1 if g < count % centres.size() else 0)
		for k: int in size:
			var side: int = k % side_list.size()
			var heading: float = atan2(side_direction(side).x, side_direction(side).z)
			var at: Vector3 = centres[g]
			for attempt: int in 50:
				var angle: float = heading + (rng.randf() - 0.5) * MINE_BELT_ARC_RAD
				var radius: float = MINE_BELT_RADIUS_M + rng.randf_range(-MINE_BELT_DEPTH_M, MINE_BELT_DEPTH_M)
				at = centres[g] + Vector3(sin(angle) * radius, rng.randf_range(-MINE_BELT_HEIGHT_M, MINE_BELT_HEIGHT_M),
						cos(angle) * radius)
				if _mine_clear(at, ships):
					break
			out.append({"offset": at, "faction": side_list[side], "side": side, "fight_centre": centres[g]})
	return out


static func _mine_clear(at: Vector3, ships: Array[Dictionary]) -> bool:
	for e: Dictionary in ships:
		var reach: float = float(e["radius"]) + MineStandin.TRIGGER_RADIUS_M
		if at.distance_squared_to(e["offset"] as Vector3) <= reach * reach:
			return false
	return true


## The layout's gravity: the body of the star system's data it orbits (`body`) and at what height (`altitude_m`); empty for a
## layout flown where nothing pulls.
static func gravity_orbit(layout: StringName) -> Dictionary:
	if int(mix(layout, 1).get("gravity_sources", 0)) <= 0:
		return {}
	return {"body": GRAVITY_BODY, "altitude_m": GRAVITY_ALTITUDE_M}


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
