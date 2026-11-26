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
##   Mines (M4-T12, M7-T65) in small chained groups where the fighters fight inside the slab (`mines`).
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
## Mine groups (M7-T65): each side's share laid as seeded groups of 4 to 8 inside the rock slab, where the fighters were measured
## to fight: ahead of each side's capitals, 2.5 to 4.4 km out along its direction from the fight's centre, where its fighters come out
## of their jump points and the others' meet them. A side's groups lie on the other sides' approaches.
const MINE_GROUP_MIN: int = 4
const MINE_GROUP_MAX: int = 8
const MINE_GROUP_MEAN: float = 6.0
## Each mine of a group lies this far from one laid before it, inside its blast, so a group goes off as a chain.
const MINE_STEP_MIN_M: float = 40.0
const MINE_STEP_MAX_M: float = 70.0
## No two mines of a group closer than this.
const MINE_SPACING_M: float = 30.0
## The nearest mines of two groups never closer than this (the blast and a margin), so no chain crosses.
const MINE_GROUP_GAP_M: float = 250.0
## Where a group's first mine lies on an approach: along it from the fight's centre, across it, and above the centre (the
## measured fights sit lower than the centre), m.
const MINE_ALONG_MIN_M: float = 2500.0
const MINE_ALONG_MAX_M: float = 4400.0
const MINE_ACROSS_M: float = 700.0
const MINE_HEIGHT_MIN_M: float = -1000.0
const MINE_HEIGHT_MAX_M: float = 300.0
## A mine stays this far clear of a rock's bounding sphere and inside the slab by this much, m.
const MINE_ROCK_CLEARANCE_M: float = 10.0
const MINE_SLAB_MARGIN_M: float = 100.0
## The player starts at the origin, about this big.
const MINE_PLAYER_RADIUS_M: float = 20.0
## The cell of the grids that keep the obstacles and the laid mines, m.
const MINE_GRID_M: float = 250.0
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


## The rocks of `layout` for `seed`: `offset` (m, from the player) and `radius` (m, bounding), log-uniform in size, seeded, none
## within `ROCK_CLEARANCE_M` of the player or a ship's hull, each with a generated rock's `shape` and `basis` from its own hash
## (M7-T48); the mix's count, or `count_override` when 0 or more. Empty for a layout without rocks.
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
				var rock: Dictionary = {"offset": at, "radius": radius}
				rock.merge(AsteroidBelt.seeded_look(hash([String(layout), n, seed_value, "rock", i])))
				out.append(rock)
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


## The mines of `layout` for `seed` (M7-T65): the mix's mines shared over the sides, each side's share in seeded groups of
## `MINE_GROUP_MIN` to `MINE_GROUP_MAX`, laid in the fights inside the rock slab on the other sides' approaches. Each: `offset` (m,
## from the player), `faction`, `side`, `group` (index over the layout), `fight_centre`. Within a group every mine lies inside a
## blast of another, groups lie `MINE_GROUP_GAP_M` apart, and none lies inside a starting hull's trigger or a rock. `rock_list`
## is the run's rocks (`rocks` for `seed` when null). Empty for a layout without a mix.
static func mines(layout: StringName, n: int, seed_value: int, rock_list: Variant = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var count: int = int(mix(layout, n).get("mines", 0))
	var slab: AABB = rock_slab(layout, n)
	var fights: Array[Vector3] = []
	for c: Vector3 in fight_centres(layout, n):
		if slab.has_point(c):
			fights.append(c)
	if count <= 0 or fights.is_empty():
		return out
	var side_list: Array[StringName] = sides(layout)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([String(layout), n, seed_value, "mines"])
	var obstacles: Dictionary = {}
	for e: Dictionary in plan(layout, n, seed_value):
		_grid_add(obstacles, e["offset"] as Vector3, float(e["radius"]) + MineKinds.number(MineKinds.PROX, "trigger_m"))
	_grid_add(obstacles, Vector3.ZERO, MINE_PLAYER_RADIUS_M + MineKinds.number(MineKinds.PROX, "trigger_m"))
	var rock_rows: Array = rock_list if rock_list is Array else rocks(layout, n, seed_value)
	for r: Dictionary in rock_rows:
		_grid_add(obstacles, r["offset"] as Vector3, float(r["radius"]) + MineField.BODY_RADIUS_M + MINE_ROCK_CLEARANCE_M)
	var inside := slab.grow(-MINE_SLAB_MARGIN_M)
	var laid: Dictionary = {}  # every mine laid so far, to keep groups apart
	var specs: Array[Vector2i] = mine_groups(count, side_list.size(), rng)
	for g: int in specs.size():
		var side: int = specs[g].x
		var group: Array[Vector3] = []
		var fight: Vector3 = fights[g % fights.size()]
		for attempt: int in 200:
			# The next fight only once this one has no room; the approach of another side, in turn over this side's groups.
			fight = fights[(g + attempt / 50) % fights.size()]
			var other: int = (side + 1 + (g / side_list.size() + attempt) % (side_list.size() - 1)) % side_list.size()
			group = _mine_group(rng, fight, side_direction(other), specs[g].y, inside, obstacles, laid)
			if not group.is_empty():
				break
		for at: Vector3 in group:
			_grid_add(laid, at, MINE_GROUP_GAP_M)
			out.append({"offset": at, "faction": side_list[side], "side": side, "group": g, "fight_centre": fight})
	return out


## The groups for `count` mines over `side_count` sides: `Vector2i(side, size)`, sides taken in turn, each side's sizes from
## `MINE_GROUP_MIN` to `MINE_GROUP_MAX` and adding up to its share (the first sides take the remainder).
static func mine_groups(count: int, side_count: int, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var per_side: Array = []
	var most: int = 0
	for side: int in side_count:
		var share: int = count / side_count + (1 if side < count % side_count else 0)
		var groups: int = clampi(roundi(float(share) / MINE_GROUP_MEAN), ceili(float(share) / MINE_GROUP_MAX),
				maxi(1, share / MINE_GROUP_MIN))
		var sizes := PackedInt32Array()
		sizes.resize(groups)
		sizes.fill(mini(MINE_GROUP_MIN, share / groups))
		var left: int = share - sizes[0] * groups
		while left > 0:
			# The rest one at a time to a random group with room, so the sizes vary.
			var k: int = rng.randi_range(0, groups - 1)
			if sizes[k] < MINE_GROUP_MAX:
				sizes[k] += 1
				left -= 1
		per_side.append(sizes)
		most = maxi(most, groups)
	var out: Array[Vector2i] = []
	for k: int in most:
		for side: int in side_count:
			var sizes: PackedInt32Array = per_side[side]
			if k < sizes.size():
				out.append(Vector2i(side, sizes[k]))
	return out


# One group of `size` mines on the approach `direction` of the fight at `centre`: the first at a seeded place in the measured
# fight volume, each next a step from one laid before. Empty when it cannot be laid clear of `obstacles`, of other groups
# (`laid`) and inside `inside`.
static func _mine_group(rng: RandomNumberGenerator, centre: Vector3, direction: Vector3, size: int, inside: AABB,
		obstacles: Dictionary, laid: Dictionary) -> Array[Vector3]:
	var across: Vector3 = direction.cross(Vector3.UP)
	var first: Vector3 = centre + direction * rng.randf_range(MINE_ALONG_MIN_M, MINE_ALONG_MAX_M) \
			+ across * rng.randf_range(-MINE_ACROSS_M, MINE_ACROSS_M) + Vector3.UP * rng.randf_range(MINE_HEIGHT_MIN_M, MINE_HEIGHT_MAX_M)
	var group: Array[Vector3] = []
	if not _mine_spot_clear(first, group, inside, obstacles, laid):
		return group
	group.append(first)
	while group.size() < size:
		var placed: bool = false
		for attempt: int in 40:
			var step := Vector3(rng.randfn(), rng.randfn(), rng.randfn())
			if step.length_squared() < 1e-6:
				continue
			var at: Vector3 = group[rng.randi_range(0, group.size() - 1)] + step.normalized() * rng.randf_range(MINE_STEP_MIN_M, MINE_STEP_MAX_M)
			if _mine_spot_clear(at, group, inside, obstacles, laid):
				group.append(at)
				placed = true
				break
		if not placed:
			group.clear()
			break
	return group


# Spheres (`at`, `reach`) kept in every `MINE_GRID_M` cell they overlap, so a point asks only its own cell.
static func _grid_add(grid: Dictionary, at: Vector3, reach: float) -> void:
	var lo: Vector3i = _grid_cell(at - Vector3.ONE * reach)
	var hi: Vector3i = _grid_cell(at + Vector3.ONE * reach)
	for x: int in range(lo.x, hi.x + 1):
		for y: int in range(lo.y, hi.y + 1):
			for z: int in range(lo.z, hi.z + 1):
				var key := Vector3i(x, y, z)
				if not grid.has(key):
					grid[key] = []
				(grid[key] as Array).append(Vector4(at.x, at.y, at.z, reach))


# Whether `at` lies inside a sphere of `grid`.
static func _grid_reaches(grid: Dictionary, at: Vector3) -> bool:
	for s: Vector4 in grid.get(_grid_cell(at), []) as Array:
		if at.distance_squared_to(Vector3(s.x, s.y, s.z)) < s.w * s.w:
			return true
	return false


static func _grid_cell(at: Vector3) -> Vector3i:
	return Vector3i(floori(at.x / MINE_GRID_M), floori(at.y / MINE_GRID_M), floori(at.z / MINE_GRID_M))


static func _mine_spot_clear(at: Vector3, group: Array[Vector3], inside: AABB, obstacles: Dictionary,
		laid: Dictionary) -> bool:
	if not inside.has_point(at) or _grid_reaches(obstacles, at) or _grid_reaches(laid, at):
		return false
	for other: Vector3 in group:
		if other.distance_squared_to(at) < MINE_SPACING_M * MINE_SPACING_M:
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
