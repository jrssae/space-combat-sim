class_name DestructionDirector
extends Node
## What happens when a ship's hull reaches zero (architecture §15.7, §16 D35). It listens to every watched `Damageable.destroyed`:
##
## - a **pooled ship**, raider or ally alike: its pose and velocity are read, then it is released to the `ShipPool` in the same
##   tick (hidden, not processing, `Targetable` and `Damageable` inactive, so nothing targets or hits it afterwards); an
##   `Explosion` (radius = its bounding radius) appears under `effects` at its position, drifting with its velocity, and
##   `DebrisPool.burst` breaks it into its asset's chunks (the raider's wings and hump; generic shards for an asset without
##   any). A **Starfury** (an ally or the player) dies where it was hit (M3-T28): the killing hit's point picks the cabin or arm
##   that leaves first, the explosion starts at that chunk's joint and `DebrisPool.stage_wreck` frees the rest one by one over
##   the next second. A console `kill` or a hit without a point blasts from the centre, in a seeded order;
## - the **player**: the same effects, then the ship is hidden and disabled and `player_destroyed` is
##   emitted (Main ignores input while the player is dead); after `RESPAWN_DELAY_S` of sim time `respawn_due` is emitted and Main
##   puts the ship back at the scenario start with a full hull. A respawn before then (Back) cancels it (`cancel_respawn`).
##
## Signals: `ship_destroyed` for every pooled ship; `raider_destroyed` as well when it is a raider (a kill, which is what the
## waves count). An ally's death is a `ship_destroyed` only. Which is which is the pool type (`ShipPool.DEFAULT_TYPE` raiders,
## `ShipPool.ALLY_TYPE` allies), never the faction relation, so a `relation` change on the console cannot turn kills into losses.
##
## The level of detail (M4-T23, `ExplosionLod`): how a death is drawn depends on its fireball's size on the current picture:
## the full effects while it is 8 px or more in radius, a reduced explosion (no light, the gas shell only, no debris) down to
## 2 px, and below that a point flash in the world's `FarFlashes`, with no node and no particle. A death in the low-attention tier is drawn where its row
## flew. A **capital** stand-in's death (`watch_capital`) is drawn the same way; the capital then leaves play (and the tier)
## and `capital_destroyed` is emitted. A **mine** that goes off (`watch_mines`, M7-T64, M10-T15) is drawn the same way, its fireball as big
## as its blast; at most `MINE_BLASTS_MAX` of its explosions are alive at once and the rest are far flashes, so a battle's
## chains stay cheap. Every death's killing hit carries its blast's energy, radius and point (`set_blast`).
##
## **Death blasts** (M10-T09, D12.6): every death is a falloff blast (`BlastResolver`) sized by the hull's class and what it
## carries (`BlastTable`): a pooled hull's by its role and cargo, from where its explosion starts; a capital's by the section
## that blew (its reactor's without one), from that section's centre. It hurts and pushes whatever is near, friend or foe, and
## a hull it kills blows in turn in the same tick. The far flash reads the same blast's energy.
##
## Console: `kill [target|all|allies|player]` destroys now, bypassing god mode: the selected pooled ship or capital, every
## raider, every ally, or the player. `blast [source] [ahead_m]` sets off a test blast ahead of the player (its fireball as
## big as its radius); provider `blasts` (`BlastResolver.stats`).

## A pooled ship was destroyed (it is already back in the pool): a raider or an allied Starfury.
signal ship_destroyed(combatant: Combatant, info: HitInfo)
## A raider was destroyed (it is already back in the pool). Follows `ship_destroyed`.
signal raider_destroyed(combatant: Combatant, info: HitInfo)
## A nav buoy was destroyed (it is already hidden and out of play).
signal buoy_destroyed(buoy: NavBuoy, info: HitInfo)
## The player's hull reached zero.
signal player_destroyed(info: HitInfo)
## `RESPAWN_DELAY_S` of sim time passed since the player died.
signal respawn_due
## A capital stand-in was destroyed (it has left play) (M4-T23).
signal capital_destroyed(capital: CapitalBody, info: HitInfo)
## A station was destroyed (M10-T65, Q72): its blast is drawn and set off; the wreck stays. A mission that needs it fails.
signal station_destroyed(station: Station)
## A mine's explosion was drawn as an explosion at `at` (M7-T64): once a tick, so a chain sounds as one blast.
signal mine_exploded(at: Vector3)

const RESPAWN_DELAY_S: float = 3.0
## DamageZones' X-fighter zones -> the Starfury chunk each one is.
const ZONE_CHUNKS: Dictionary[int, StringName] = {
	DamageZones.CABIN: &"cabin", DamageZones.UPPER_LEFT: &"arm_ul", DamageZones.UPPER_RIGHT: &"arm_ur",
	DamageZones.LOWER_LEFT: &"arm_ll", DamageZones.LOWER_RIGHT: &"arm_lr",
}
const KILL_CHOICES: Array[StringName] = [&"target", &"all", &"allies", &"player"]
## Mine explosions alive at once (M7-T64); past it a mine's blast is a far flash.
const MINE_BLASTS_MAX: int = 12
## A station's fireball against its blast's reach (M10-T65; to judge in play).
const STATION_FIREBALL_SHARE: float = 0.25

var world: WorldFrame = null
var pool: ShipPool = null
var debris: DebrisPool = null
## Where explosions get their sparks (`Main` sets it).
var fx: FxPool = null
## Where explosions are added (`World/Effects`).
var effects: Node3D = null
var player: Combatant = null

## Where the last ship's explosion started (World-local); sounds follow it.
var last_blast_position: Vector3 = Vector3.ZERO
## Mine blasts drawn so far, by level (`ExplosionLod.Level`: full, reduced, far flash), for tests and readouts.
var mine_blasts := PackedInt32Array([0, 0, 0])

var _watched: Array[Combatant] = []
var _watched_capitals: Array[CapitalBody] = []
var _respawn_at_s: float = INF
var _mine_explosions: Array[Explosion] = []
var _mine_sound_frame: int = -1

static var _current: DestructionDirector = null


func _ready() -> void:
	DebugConsole.registry.register_command(ConsoleCommand.new(&"kill",
			"Destroy the selected target, every raider, every allied ship or the player now (bypasses god mode)",
			[ConsoleArg.enum_optional(&"who", KILL_CHOICES, &"target")]), _cmd_kill, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"blast",
			"Set off a test blast (a row of the blasts' table) ahead of the player: it hurts and pushes what it reaches",
			[ConsoleArg.enum_optional(&"source", BlastTable.names(), &"fighter_death"),
			ConsoleArg.float_optional(&"ahead_m", 60.0, 0.0, 20000.0)]), _cmd_blast, self)
	DebugConsole.registry.register_provider(&"blasts", ConsoleVars.new({
		&"blasts": {"get": func() -> int: return BlastResolver.blasts, "doc": "Blasts landed (deaths, sections, missiles, tests)"},
		&"hulls_hurt": {"get": func() -> int: return BlastResolver.hulls_hurt, "doc": "Hulls the blasts hurt"},
		&"pushed": {"get": func() -> int: return BlastResolver.pushed, "doc": "Hulls the blasts pushed"},
		&"last": {"get": func() -> String: return "%s at %s: %d reached, %d hurt" % [BlastResolver.last_source,
				BlastResolver.last_centre, BlastResolver.last_reached, BlastResolver.last_hurt], "doc": "The last blast"},
		&"last_us": {"get": func() -> int: return BlastResolver.last_us,
				"doc": "The last landing's cost (a blast and the chain it starts), us"},
		&"max_us": {"get": func() -> int: return BlastResolver.max_us, "doc": "The costliest landing's, us"},
		&"mean_us": {"get": func() -> float: return float(BlastResolver.stats()["mean_us"]), "doc": "A blast's mean cost, us"},
		&"reach_mean_us": {"get": func() -> float: return float(BlastResolver.stats()["reach_mean_us"]),
				"doc": "Of that, the native core's walk over the hulls, us"},
		&"native_mean_us": {"get": func() -> float: return float(BlastResolver.stats()["native_mean_us"]),
				"doc": "Of that, the native batch's whole share, us (M10-T76)"},
	}), self)


func _enter_tree() -> void:
	_current = self


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if _current == self:
		_current = null


## The latest director in a tree, or null.
static func current() -> DestructionDirector:
	return _current if _current != null and is_instance_valid(_current) else null


func _physics_process(_delta: float) -> void:
	if SimClock.now() >= _respawn_at_s:
		_respawn_at_s = INF
		respawn_due.emit()


## Connects to every ship in `pool` and to `player`. Call it after the pool is prepared and the player is spawned.
func setup(p_world: WorldFrame, p_pool: ShipPool, p_debris: DebrisPool, p_effects: Node3D, p_player: Combatant) -> void:
	world = p_world
	pool = p_pool
	debris = p_debris
	effects = p_effects
	player = p_player
	for combatant: Combatant in pool.all_ships():
		watch(combatant)
	watch(player)


## Reacts to this ship's `destroyed` from now on. Watching a ship twice is harmless.
func watch(combatant: Combatant) -> void:
	if combatant == null or combatant.damageable == null or _watched.has(combatant):
		return
	_watched.append(combatant)
	combatant.damageable.destroyed.connect(_on_destroyed.bind(combatant))


## Reacts to this buoy's `destroyed` from now on: an explosion and shards at its position, then it leaves play (hidden, not freed).
func watch_buoy(buoy: NavBuoy) -> void:
	if buoy == null or buoy.damageable == null:
		return
	buoy.damageable.destroyed.connect(_on_buoy_destroyed.bind(buoy))


## Reacts to this capital's `destroyed` from now on (M4-T23): its blast at its level of detail, then it leaves play.
func watch_capital(cap: CapitalBody) -> void:
	if cap == null or cap.damageable == null or _watched_capitals.has(cap):
		return
	_watched_capitals.append(cap)
	cap.damageable.destroyed.connect(_on_capital_destroyed.bind(cap))


## Reacts to this station's death from now on (M10-T65): its blast drawn at its level of detail and set off. Twice is harmless.
func watch_station(station: Station) -> void:
	if station != null and not station.station_destroyed.is_connected(_on_station_destroyed):
		station.station_destroyed.connect(_on_station_destroyed.bind(station))


## Draws every mine of `field` that goes off from now on (M7-T64, M10-T15). Watching a field twice is harmless.
func watch_mines(field: MineField) -> void:
	if field == null or field.detonated.is_connected(_on_mine_detonated):
		return
	field.detonated.connect(_on_mine_detonated)


## True while a respawn of the player is pending.
func respawn_pending() -> bool:
	return _respawn_at_s < INF


## Drops a pending respawn: the player was put back another way (Back, the console's `respawn`).
func cancel_respawn() -> void:
	_respawn_at_s = INF


func _on_destroyed(info: HitInfo, combatant: Combatant) -> void:
	var ship: Ship = combatant.ship
	var xform: Transform3D = ship.global_transform
	var velocity: Vector3 = ship.linear_velocity
	var spin: Vector3 = ship.angular_velocity
	# A ship in the low-attention tier (M4-T22) died where its row flew, not where its node was parked.
	var tiered: bool = ship.is_tier_parked()
	if tiered:
		var pose: Array = TierDirector.row_pose(ship)
		if not pose.is_empty():
			xform = pose[0]
			velocity = pose[1]
			spin = pose[2]
	var radius: float = combatant.damageable.bounding_radius
	var hardpoints: Hardpoints = ship.get_hardpoints()
	var staged: bool = combatant.damageable.zones.layout == DamageZones.Layout.X_FIGHTER and hardpoints.valid and not hardpoints.chunks.is_empty()
	var first: int = first_chunk(hardpoints.chunks, info, xform) if staged else -1
	# The ship leaves play in this very tick, before anything else in it looks at it.
	if combatant == player:
		ship.visible = false
		ship.process_mode = Node.PROCESS_MODE_DISABLED
		_respawn_at_s = SimClock.now() + RESPAWN_DELAY_S
	else:
		pool.release(combatant)
	var blast: BlastSpec = BlastTable.hull_death(ship.spec.asset_id if ship.spec != null else "")
	var level: ExplosionLod.Level = _level_at(radius, xform.origin)
	if level == ExplosionLod.Level.FULL:
		_spawn_effects(ship, xform, velocity, spin, radius, hardpoints, staged, first)
	else:
		last_blast_position = xform.origin
		_spawn_far(level, xform.origin, velocity, radius, blast.energy_j())
	set_blast(info, blast, last_blast_position)
	if combatant == player:
		player_destroyed.emit(info)
	else:
		ship_destroyed.emit(combatant, info)
		if pool.type_of(combatant) == ShipPool.DEFAULT_TYPE:
			raider_destroyed.emit(combatant, info)
	BlastResolver.set_off(blast, last_blast_position, combatant.damageable.faction)


func _on_capital_destroyed(info: HitInfo, cap: CapitalBody) -> void:
	var xform: Transform3D = cap.global_transform
	var velocity: Vector3 = cap.linear_velocity
	if cap.is_tier_parked():
		var pose: Array = TierDirector.row_pose(cap)
		if not pose.is_empty():
			xform = pose[0]
			velocity = pose[1]
		var tier: TierDirector = TierDirector.current()
		if tier != null:
			tier.forget_capital(cap)
	var blast: Array = capital_blast(cap, xform)
	cap.leave_play()
	var radius: float = cap.damageable.bounding_radius
	last_blast_position = xform.origin
	var level: ExplosionLod.Level = _level_at(radius, xform.origin)
	if level == ExplosionLod.Level.FULL:
		_add_explosion(radius, velocity, xform.origin, false)
	else:
		_spawn_far(level, xform.origin, velocity, radius, (blast[0] as BlastSpec).energy_j())
	set_blast(info, blast[0], blast[1])
	capital_destroyed.emit(cap, info)
	BlastResolver.set_off(blast[0], blast[1], cap.faction)


func _on_station_destroyed(_section: String, station: Station) -> void:
	if not is_instance_valid(station):
		return
	var blast: Array = station.death_blast()
	var spec: BlastSpec = blast[0]
	var at: Vector3 = blast[1]
	var velocity: Vector3 = world.rest_velocity() if world != null and is_instance_valid(world) else Vector3.ZERO
	var radius: float = STATION_FIREBALL_SHARE * spec.radius_m if spec != null else 500.0  # the reactor's fireball, not the whole blast
	last_blast_position = at
	var level: ExplosionLod.Level = _level_at(radius, at)
	if level == ExplosionLod.Level.FULL:
		_add_explosion(radius, velocity, at, false)
	else:
		_spawn_far(level, at, velocity, radius, spec.energy_j() if spec != null else 0.0)
	station_destroyed.emit(station)
	if spec != null:
		BlastResolver.set_off(spec, at, Factions.EARTH_ALLIANCE)


func _on_mine_detonated(_slot: int, kind_index: int, at: Vector3) -> void:
	draw_mine_blast(at, kind_index)


## A mine's blast at `at` (World frame), of mine kind `kind_index` (`MineKinds`): drawn at its level of detail like a death,
## capped so a battle's chains stay cheap. Returns the level it was drawn at.
func draw_mine_blast(at: Vector3, kind_index: int = MineKinds.PROX) -> ExplosionLod.Level:
	var blast: BlastSpec = MineKinds.blast(kind_index)
	var radius: float = (blast.radius_m if blast != null else 100.0) / Explosion.FIREBALL_FINAL_SCALE
	var velocity: Vector3 = world.rest_velocity() if world != null and is_instance_valid(world) else Vector3.ZERO
	var level: ExplosionLod.Level = _level_at(radius, at)
	if level != ExplosionLod.Level.FAR and _mine_explosions_alive() >= MINE_BLASTS_MAX:
		level = ExplosionLod.Level.FAR
	if level == ExplosionLod.Level.FAR:
		_spawn_far(level, at, velocity, radius, blast.energy_j() if blast != null else 0.0)
	else:
		var explosion: Explosion = _add_explosion(radius, velocity, at, level == ExplosionLod.Level.REDUCED)
		if explosion != null:
			_mine_explosions.append(explosion)
		var frame: int = Engine.get_physics_frames()
		if level == ExplosionLod.Level.FULL and frame != _mine_sound_frame:
			_mine_sound_frame = frame
			mine_exploded.emit(at)
	mine_blasts[level] += 1
	return level


# Mine explosions still showing; drops the finished ones.
func _mine_explosions_alive() -> int:
	var still: Array[Explosion] = []
	for explosion: Explosion in _mine_explosions:
		if is_instance_valid(explosion) and not explosion.is_queued_for_deletion():
			still.append(explosion)
	_mine_explosions = still
	return still.size()


# How a death of a hull of `radius` at `at` is drawn: from its fireball's size on the current picture (the full effect with no
# camera).
func _level_at(radius: float, at: Vector3) -> ExplosionLod.Level:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return ExplosionLod.Level.FULL
	return ExplosionLod.level(radius, camera.global_position.distance_to(at), ExplosionLod.picture_lines(get_viewport()), camera.fov)


# A death past the full effect's distance: a reduced explosion, or a far flash with no node and no particle.
func _spawn_far(level: ExplosionLod.Level, at: Vector3, velocity: Vector3, radius: float, energy_j: float) -> void:
	if level == ExplosionLod.Level.REDUCED:
		_add_explosion(radius, velocity, at, true)
		return
	var flashes: FarFlashes = FarFlashes.attach(world)
	if flashes != null:
		flashes.add(at, velocity, radius, energy_j)


func _add_explosion(radius: float, velocity: Vector3, at: Vector3, reduced: bool) -> Explosion:
	if effects == null or not is_instance_valid(effects):
		return null
	var explosion: Explosion = Explosion.create(radius, velocity, reduced)
	explosion.fx = fx
	explosion.position = at
	effects.add_child(explosion)
	explosion.reset_physics_interpolation()
	return explosion


func _on_buoy_destroyed(info: HitInfo, buoy: NavBuoy) -> void:
	var xform: Transform3D = buoy.global_transform
	var radius: float = maxf(buoy.damageable.bounding_radius, 1.5)
	var velocity: Vector3 = buoy.velocity
	var spin: Vector3 = xform.basis.y.normalized() * deg_to_rad(buoy.spin_dps)
	buoy.set_destroyed(true)
	# Building the explosion and the shards is the costly part: done right after the hit resolver's tick, not inside it.
	_spawn_buoy_effects.call_deferred(xform, radius, velocity, spin, buoy.get_instance_id())
	buoy_destroyed.emit(buoy, info)


func _spawn_buoy_effects(xform: Transform3D, radius: float, velocity: Vector3, spin: Vector3, buoy_id: int) -> void:
	if effects != null and is_instance_valid(effects):
		var explosion: Explosion = Explosion.create(radius, velocity)
		explosion.fx = fx
		explosion.position = xform.origin
		effects.add_child(explosion)
		explosion.reset_physics_interpolation()
	if debris != null and is_instance_valid(debris):
		debris.burst(&"nav_buoy", [] as Array[Dictionary], xform, velocity, spin, hash([buoy_id, Engine.get_physics_frames()]))


func _spawn_effects(ship: Ship, xform: Transform3D, velocity: Vector3, spin: Vector3, radius: float, hardpoints: Hardpoints,
		staged: bool, first: int) -> void:
	var chunks: Array[Dictionary] = hardpoints.chunks if hardpoints.valid else ([] as Array[Dictionary])
	var seed_value: int = hash([ship.get_instance_id(), Engine.get_physics_frames()])
	# A Starfury's blast starts at the joint of the part that leaves first.
	last_blast_position = xform * (chunks[first]["joint"] as Vector3) if first >= 0 else xform.origin
	_add_explosion(radius, velocity, last_blast_position, false)
	if debris != null and is_instance_valid(debris):
		if staged:
			debris.stage_wreck(StringName(ship.spec.asset_id), chunks, xform, velocity, spin, seed_value, first, ship.livery)
		else:
			debris.burst(StringName(ship.spec.asset_id), chunks, xform, velocity, spin, seed_value, ship.livery)
		var pods: CargoPods = CargoPods.of(ship)
		if pods != null and pods.count > 0:
			# A Bokmai sheds its mounted pods with its chunks (M5-T16, D59).
			debris.burst(StringName(ship.spec.asset_id), pods.debris_entries(), xform, velocity, spin, seed_value + 1, null, false)


## Writes a death's blast onto its killing hit (M4-T22, M10-T09): `blast`'s energy and radius, at `at`.
static func set_blast(info: HitInfo, blast: BlastSpec, at: Vector3) -> void:
	if info == null or blast == null:
		return
	info.blast_energy_j = blast.energy_j()
	info.blast_radius_m = blast.radius_m
	info.blast_point = at


## A capital's death blast and its centre (World frame), `[BlastSpec, Vector3]`, with the hull at `xform`: the blast of the
## section that blew, from that section's centre; without one (a console kill, a stand-in), its first reactor's, else from
## the hull's centre.
static func capital_blast(cap: CapitalBody, xform: Transform3D) -> Array:
	var ship := cap as CapitalShip
	if ship == null:
		var cls: StringName = (cap as CapitalStandin).ship_class if cap is CapitalStandin else &""
		return [BlastTable.capital_death(&"", cls, cap.faction, BlastTable.DEFAULT_KIND), xform.origin]
	var section: CapitalSection = null
	if ship.damage != null:
		section = ship.damage.sections.get(ship.damage.blown)
		if section == null:
			for s: CapitalSection in ship.damage.sections.values():
				if s.kind == CapitalSection.REACTOR:
					section = s
					break
	var kind: String = section.kind if section != null else BlastTable.DEFAULT_KIND
	var centre: Vector3 = xform * section.box.get_center() if section != null else xform.origin
	return [BlastTable.capital_death(ship.type_id, ship.capital_class, cap.faction, kind), centre]


## The index in `chunks` of the part the killing hit landed on (`info.point` is World-local, put into the ship's frame by
## `xform`), or -1 when there is no point (a console kill) or no chunk by that name.
static func first_chunk(chunks: Array[Dictionary], info: HitInfo, xform: Transform3D) -> int:
	if info == null or info.cause == HitInfo.CAUSE_CONSOLE:
		return -1
	var zone: int = DamageZones.zone_for(DamageZones.Layout.X_FIGHTER, xform.affine_inverse() * info.point)
	var wanted: StringName = ZONE_CHUNKS.get(zone, &"")
	for i: int in chunks.size():
		if StringName(chunks[i]["name"]) == wanted:
			return i
	return -1


# --- console -----------------------------------------------------------------------------------------------------


func _cmd_blast(args: Dictionary) -> ConsoleResult:
	var ship: Ship = player.ship if player != null else null
	if ship == null or not ship.visible:
		return ConsoleResult.failure("blast: no player ship")
	var spec: BlastSpec = BlastTable.spec(StringName(args[&"source"]))
	if spec == null:
		return ConsoleResult.failure("blast: no row %s in the table" % args[&"source"])
	var at: Vector3 = ship.global_position - ship.global_basis.z * float(args[&"ahead_m"])
	var velocity: Vector3 = world.rest_velocity() if world != null and is_instance_valid(world) else Vector3.ZERO
	_add_explosion(spec.radius_m / Explosion.FIREBALL_FINAL_SCALE, velocity, at, false)
	BlastResolver.set_off(spec, at, Factions.NEUTRAL)
	return ConsoleResult.line("%s %.0f m ahead: d0 %.0f, radius %.0f m; %d reached, %d hurt (%d us)" % [spec.source,
			float(args[&"ahead_m"]), spec.d0, spec.radius_m, BlastResolver.last_reached, BlastResolver.last_hurt,
			BlastResolver.last_us])


# A selected target that is not a pooled ship (a capital, M4-T23): destroyed through its owner's hull.
func _kill_other(target_id: int) -> ConsoleResult:
	var marker := instance_from_id(target_id) as Targetable if is_instance_id_valid(target_id) else null
	var hull: Damageable = Damageable.of(marker.get_parent()) if marker != null else null
	if hull == null:
		return ConsoleResult.failure("the selected target has no hull")
	if not hull.kill():
		return ConsoleResult.failure("%s is already destroyed" % marker.display_name)
	return ConsoleResult.line("%s destroyed" % marker.display_name)


func _cmd_kill(args: Dictionary) -> ConsoleResult:
	var who: StringName = StringName(args[&"who"])
	match who:
		&"player":
			if player == null or not player.damageable.kill():
				return ConsoleResult.failure("the player is not alive")
			return ConsoleResult.line("the player's ship destroyed")
		&"all":
			var killed: int = 0
			for combatant: Combatant in pool.alive(ShipPool.DEFAULT_TYPE):
				killed += 1 if combatant.damageable.kill() else 0
			return ConsoleResult.line("destroyed %d raider(s)" % killed)
		&"allies":
			var lost: int = 0
			for combatant: Combatant in pool.alive(ShipPool.ALLY_TYPE):
				lost += 1 if combatant.damageable.kill() else 0
			if lost == 0:
				return ConsoleResult.failure("no allied ships in play")
			return ConsoleResult.line("destroyed %d allied ship(s)" % lost)
	var ship: Ship = player.ship if player != null else null
	if ship == null or not ship.targeting.system.has_selection():
		return ConsoleResult.failure("no target selected")
	var target: Combatant = pool.find_by_target_id(ship.targeting.selected_id())
	if target == null:
		return _kill_other(ship.targeting.selected_id())
	var target_name: String = target.display_name
	return ConsoleResult.line("%s destroyed" % target_name) if target.damageable.kill() else ConsoleResult.failure("%s is already destroyed" % target_name)
