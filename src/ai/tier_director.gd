class_name TierDirector
extends Node
## The low-attention tier's director (M4-T21, architecture §17.14): a fighter or a capital beyond `tier_radius_m` of the
## player leaves Jolt and the scene's processing and lives as a core row integrated by the native tier at `tier_hz` from its
## held command; coming within the radius promotes it back onto its body with its position, velocity, attitude, command and
## assist state carried over exactly, and the reverse demotes it. A child of `World` at physics priority -12, before the
## core's first sync (-11), so a tick's rows never hold a body and its tier row at once.
##
## Each tick the core names the fighters and capitals in Jolt beyond the demotion radius (the radius plus `HYSTERESIS`)
## and the tier rows within the radius, from the player's position; the director hands over at most `HANDOVERS_PER_TICK`
## of them, promotions first. A demoted ship keeps its name, pilot, hull and selection; its body is parked (hidden, not
## processing: out of Jolt, out of the scan, its hosted driver not live, its cannon idle). A capital parks with its turrets
## and emitters. With no live player nothing moves. With the radius at 0, or the core off, every tier row is promoted.
##
## Far proxies (M4-T23): a demoted fighter is drawn as a far dot from its row (`FarDots`, its hull's paint), a capital as an
## instance of the mesh its body draws (`FarHulls`); a promotion takes the row in the tick its body shows. A row that comes
## back inside a rock or a mine is moved clear by the core first (it flew through them as a row), by the shortest way out: a
## fighter as a sphere, a capital as its hull box (fix round 1).
##
## A hulk (M12 groundwork): a tier row flagged a hulk drifts with no force and no brain and is never removed for being idle;
## promotion brings it back as a hulk (`Ship.hulk`: no pilot, no thrust, no assist), not a live ship.
##
## Tier brains and fire (M4-T22): a tier fighter's hosted driver is handed to the tier (`AiPilotDriver.set_tiered`), so the
## AI step thinks for it at `tier_brain_hz` on the same contact grid as the near brains; its parked cannon's gate fires and
## the core rolls each shot against the pilot's target. The director lands those hits at the start of the next tick through
## each target's `Damageable` (`land_hits`, which the stand-ins' far capitals use too); the core keeps each tier row's hull
## fraction in step with its `Damageable` (`note_hull`). A ship whose AI pilot the host does not step yet waits in Jolt until it does.
##
## Console: provider `tier`.

const NODE_NAME: StringName = &"TierDirector"
const PRIORITY: int = SimCore.PRIORITY - 1
## A ship is demoted this much beyond the radius it is promoted at, so one on the line does not flip every tick.
const HYSTERESIS: float = 0.1
## Handovers a tick carries at most (a battle's start would otherwise park hundreds in one tick).
const HANDOVERS_PER_TICK: int = 64
const TIER_META: StringName = &"_scs_tier_row"

static var _current: TierDirector = null
## The tier's hulls by body id, found once and kept while the director's world lives (cleared when it leaves).
static var _damageables: Dictionary[int, Damageable] = {}

var world: WorldFrame = null
var ships: ShipPool = null
## The battle's stand-ins (the capitals and the moon); null outside the main scene.
var standins: StandinDirector = null
## Handovers so far, and the last tick's cost (wall clock, a readout).
var promotions: int = 0
var demotions: int = 0
var last_us: int = 0
## Handovers a tick carries at most (`HANDOVERS_PER_TICK`; a test lowers it).
var handovers_per_tick: int = HANDOVERS_PER_TICK
## The seed the tier's rolls draw from (the bench's seed; 0 elsewhere), pushed to the core when it changes (fix round 1).
var seed_value: int = 0
var _seed_given: int = -1
## Rams the tier landed so far (fix round 1).
var rams_landed: int = 0

var _tiered_ships: Dictionary[int, Combatant] = {}
var _tiered_capitals: Dictionary[int, CapitalStandin] = {}
## The world's origin when each body was parked, so a body restored with no row left lands in the frame of now.
var _park_origins: Dictionary[int, UniversePos] = {}
var _types: Dictionary[ShipSpec, int] = {}
var _types_core: Object = null
var _ships_by_body: Dictionary[int, Combatant] = {}
var _ships_known: int = -1
var _capitals_by_body: Dictionary[int, CapitalStandin] = {}
var _capitals_known: int = -1
var _sim: SimCore = null
var _period_given: int = -1
var _gravity_given: GravityStandin = null
var _gravity_gm_given: float = NAN
## Tier fighters' hits landed so far, and the last tick's landing cost (wall clock, a readout).
var hits_landed: int = 0
var land_us: int = 0
# The tier's main-thread cost summed since `reset_costs` (wall clock, readouts): the fighters' part (the integration, their
# cannons' rolls, the landing), the far capitals' rolls, the rows, and the ticks summed.
var _cost_fighters_us: float = 0.0
var _cost_capitals_us: float = 0.0
var _cost_fighter_rows: int = 0
var _cost_capital_rows: int = 0
var _cost_ticks: int = 0
var _shots_at_reset: int = 0
var _hits_at_reset: int = 0
var _rolls_at_reset: int = 0
# The tier's thinks summed since `reset_costs` (fix round 1): how many, their time in the AI step's job, the most in a tick.
var _cost_thinks: int = 0
var _cost_think_us: float = 0.0
var _cost_thinks_max: int = 0


func _init() -> void:
	name = NODE_NAME
	process_physics_priority = PRIORITY


func _enter_tree() -> void:
	_current = self


func _ready() -> void:
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if _current == self:
		_current = null
		_damageables.clear()


## The director under `p_world`, made on first ask with the pool and the stand-ins it works for.
static func attach(p_world: WorldFrame, p_ships: ShipPool, p_standins: StandinDirector = null) -> TierDirector:
	var found := p_world.get_node_or_null(NodePath(NODE_NAME)) as TierDirector
	if found != null:
		return found
	var made := TierDirector.new()
	made.world = p_world
	made.ships = p_ships
	made.standins = p_standins
	p_world.add_child(made)
	return made


## The latest director in a tree, or null.
static func current() -> TierDirector:
	return _current if _current != null and is_instance_valid(_current) else null


## The radius ships are promoted at, m (`tier_radius_m`; 0 = the tier is off).
static func radius_m() -> float:
	return float(Settings.get_value(&"tier_radius_m"))


## The beat's period in ticks for `tier_hz`.
static func period_ticks() -> int:
	return AiThinkRate.period_ticks(float(Settings.get_value(&"tier_hz")), Engine.physics_ticks_per_second)


## Ticks between a tier fighter's thinks for `tier_brain_hz` (M4-T22).
static func brain_period_ticks() -> int:
	return AiThinkRate.period_ticks(float(Settings.get_value(&"tier_brain_hz")), Engine.physics_ticks_per_second)


## Where a tiered body's row flies now, `[Transform3D, velocity, spin]`, or empty when `body` is not in the tier (M4-T22: a
## death in the tier happens where its row is, not where its node was parked).
static func row_pose(body: Node3D) -> Array:
	var director: TierDirector = current()
	if director == null or body == null or director._sim == null or not is_instance_valid(director._sim) or director._sim.core == null:
		return []
	var state: Dictionary = director._sim.core.tier_state(body.get_instance_id())
	if state.is_empty():
		return []
	return [Transform3D(state["basis"], state["position"]), state["velocity"], state["angular"]]


## Where `body` flies now (M4-T23): its tier row's position while it is in the tier, else its own.
static func flying_position(body: Node3D) -> Vector3:
	var pose: Array = row_pose(body) if body != null and body.has_meta(TIER_META) else []
	return (pose[0] as Transform3D).origin if not pose.is_empty() else body.global_position


## How fast `body` flies now (M4-T23): its tier row's velocity while it is in the tier, else its body's.
static func flying_velocity(body: RigidBody3D) -> Vector3:
	var pose: Array = row_pose(body) if body != null and body.has_meta(TIER_META) else []
	return pose[1] if not pose.is_empty() else body.linear_velocity


## Lands tier hits through each target's `Damageable` (M4-T22), in order: `targets` and `shooters` by body id, each hit's
## damage and where it landed. A target gone or already destroyed takes nothing. Returns how many landed.
static func land_hits(targets: PackedInt64Array, shooters: PackedInt64Array, damage: PackedFloat64Array,
		points: PackedVector3Array) -> int:
	var landed: int = 0
	for k: int in targets.size():
		var target: Damageable = _damageable_of(targets[k])
		if target == null or target.hull.destroyed:
			continue
		var faction: StringName = &""
		var shooter: Damageable = _damageable_of(shooters[k])
		if shooter != null:
			faction = shooter.faction
		target.apply_hit(HitInfo.new(targets[k], shooters[k], faction, damage[k], points[k], Vector3.ZERO, 0.0, HitInfo.CAUSE_BOLT))
		landed += 1
	return landed


func _physics_process(_delta: float) -> void:
	step()


## One tick of the director: the frame to the core, then the promotions and demotions the core names.
func step() -> void:
	var started: int = Time.get_ticks_usec()  # a readout, never gameplay time
	var sim: SimCore = SimCore.for_tree(get_tree())
	var radius: float = radius_m()
	if sim == null or radius <= 0.0:
		promote_all()
		last_us = Time.get_ticks_usec() - started
		return
	_sim = sim
	_land_fighter_hits(sim)
	_land_rams(sim)
	_sum_costs(sim)
	_push_frame(sim)
	_prune(sim)
	var frame: Array = AiPilotDriver.driver_frame()
	if not bool(frame[0]):
		last_us = Time.get_ticks_usec() - started
		return
	var at: Vector3 = frame[1]
	var player_body: int = AiPilotDriver.player.ship.get_instance_id()
	var budget: int = handovers_per_tick
	for body_id: int in (sim.core.tier_near_rows(at, radius, budget) as PackedInt64Array):
		promote_body(body_id)
		budget -= 1
	if budget > 0:
		# Every far body is asked for: one the director cannot demote must not use up a handover.
		var far: PackedInt64Array = sim.core.tier_far_bodies(at, player_body, radius * (1.0 + HYSTERESIS), sim.core.node_count())
		for body_id: int in far:
			if budget <= 0:
				break
			if demote_body(body_id):
				budget -= 1
	last_us = Time.get_ticks_usec() - started


## Demotes the pooled ship or capital whose body is `body_id` into the tier now. False when it is not one of this
## director's bodies, is parked already, or the core refused.
func demote_body(body_id: int) -> bool:
	var sim: SimCore = SimCore.for_tree(get_tree())
	if sim == null:
		return false
	_sim = sim
	var c: Combatant = _ship_of(body_id)
	if c != null:
		return _demote_ship(sim, c)
	var cap: CapitalStandin = _capital_of(body_id)
	if cap != null:
		return _demote_capital(sim, cap)
	return false


## Promotes the tier row of body `body_id` back onto its body now. False when the body is not in the tier.
func promote_body(body_id: int) -> bool:
	if _sim == null or not is_instance_valid(_sim) or _sim.core == null:
		return false
	var state: Dictionary = _sim.core.tier_take(body_id)
	if state.is_empty():
		return false
	_restore(body_id, state)
	promotions += 1
	return true


## Promotes every tier row (the tier switched off, or the core gone: then the bodies come back where they stand).
func promote_all() -> void:
	if _tiered_ships.is_empty() and _tiered_capitals.is_empty():
		return
	var core_alive: bool = _sim != null and is_instance_valid(_sim) and _sim.core != null
	for body_id: int in _tiered_ships.keys():
		var state: Dictionary = _sim.core.tier_take(body_id) if core_alive else {}
		_restore(body_id, state)
		promotions += 1
	for body_id: int in _tiered_capitals.keys():
		var state: Dictionary = _sim.core.tier_take(body_id) if core_alive else {}
		_restore(body_id, state)
		promotions += 1
	_tiered_ships.clear()
	_tiered_capitals.clear()
	_park_origins.clear()


## A pooled ship leaves play while it is in the tier (`ShipPool.release`): its row goes with it.
func forget(c: Combatant) -> void:
	if c == null or not is_instance_valid(c.ship):
		return
	var body_id: int = c.ship.get_instance_id()
	if not _tiered_ships.erase(body_id):
		return
	_park_origins.erase(body_id)
	if c.driver != null:
		c.driver.set_tiered(false)
	if _sim != null and is_instance_valid(_sim) and _sim.core != null:
		_sim.core.tier_remove(body_id)  # leaves play, not a promotion (fix round 1)
	c.ship.remove_meta(TIER_META)


## A capital leaves play while it is in the tier (destroyed, M4-T23): its row goes with it.
func forget_capital(cap: CapitalStandin) -> void:
	if cap == null:
		return
	var body_id: int = cap.get_instance_id()
	if not _tiered_capitals.erase(body_id):
		return
	_park_origins.erase(body_id)
	if _sim != null and is_instance_valid(_sim) and _sim.core != null:
		_sim.core.tier_remove(body_id)  # dies, not a promotion (fix round 1)


## Fighters and capitals in the tier now.
func tier_fighters() -> int:
	return _tiered_ships.size()


func tier_capitals() -> int:
	return _tiered_capitals.size()


## Registers `spec` with `layout` as a tier type on `core` once and returns its index (-1 when it cannot fly).
func type_of(core: Object, spec: ShipSpec, layout: ThrusterLayout) -> int:
	if core != _types_core:
		_types.clear()
		_types_core = core
	if _types.has(spec):
		return _types[spec]
	if spec == null or layout == null or not layout.valid:
		return -1
	var a: Array = FlightBatch.type_arrays(spec, layout)
	var index: int = int(core.tier_register_type(a[0], a[1], a[2], a[3], a[4], a[5], layout.center_of_mass))
	if index >= 0:
		_types[spec] = index
	return index


## A ship's held command as the tier takes it: its row command when it flies one, else the command and trigger it holds.
static func held_command(sim: SimCore, c: Combatant) -> PackedFloat64Array:
	var row: PackedFloat64Array = sim.core.row_command(c.ship.get_instance_id())
	if row.size() >= 12:
		return row.slice(1)
	var cmd: FlightCommand = c.ship.flight_command()
	return PackedFloat64Array([cmd.main_left, cmd.main_right, cmd.retro_left, cmd.retro_right, cmd.strafe.x, cmd.strafe.y,
			cmd.rot.x, cmd.rot.y, cmd.rot.z, 1.0 if cmd.brake else 0.0, 1.0 if c.ship.get_combat_command().fire else 0.0])


# --- the handovers -------------------------------------------------------------------------------------------------------


func _demote_ship(sim: SimCore, c: Combatant) -> bool:
	var ship: Ship = c.ship
	if not is_instance_valid(ship) or not ship.is_inside_tree() or not ship.can_process() or not ship.visible:
		return false
	if ship.tier_exempt or _waits_for_host(c):
		return false
	var type_ix: int = type_of(sim.core, ship.spec, ship.get_layout())
	if type_ix < 0:
		return false
	var body_id: int = ship.get_instance_id()
	var command: PackedFloat64Array = held_command(sim, c)
	var handle: int = int(sim.core.tier_add(SimCore.KIND_SHIP, body_id, c.damageable.get_instance_id(), type_ix,
			ship.global_position, ship.linear_velocity, ship.global_basis, ship.angular_velocity))
	if handle == 0:
		return false
	sim.core.tier_set_attrs(body_id, c.targetable.get_instance_id(), c.faction, c.display_name, c.damageable.bounding_radius,
			c.targetable.broadcast_range_m, c.damageable.hull.fraction())
	sim.core.tier_set_control(body_id, Vector3.ZERO, command, ship.assist_state(), ship.assist_on)
	if ship.hulk:
		sim.core.tier_set_hulk(body_id, true)
	sim.core.tier_set_proxy(body_id, -1, FarDots.asset_paint(ship.spec.asset_id if ship.spec != null else ""))
	FarDots.attach(world)
	ships.park_in_tier(c)
	if c.driver != null:
		c.driver.set_tiered(true)
	_tiered_ships[body_id] = c
	_park_origins[body_id] = _origin()
	demotions += 1
	return true


func _demote_capital(sim: SimCore, cap: CapitalStandin) -> bool:
	if not is_instance_valid(cap) or not cap.is_inside_tree() or not cap.can_process() or not cap.visible:
		return false
	var body_id: int = cap.get_instance_id()
	var handle: int = int(sim.core.tier_add(SimCore.KIND_CAPITAL, body_id, cap.damageable.get_instance_id(), 0,
			cap.global_position, cap.linear_velocity, cap.global_basis, cap.angular_velocity))
	if handle == 0:
		return false
	sim.core.tier_set_attrs(body_id, cap.targetable.get_instance_id(), cap.faction, cap.targetable.display_name,
			cap.damageable.bounding_radius, cap.targetable.broadcast_range_m, cap.damageable.hull.fraction())
	sim.core.tier_set_control(body_id, cap.cruise_velocity, PackedFloat64Array(), 0.0, false)
	sim.core.tier_set_box(body_id, cap.half_extents())  # cleared of rocks by its hull, not its bounding sphere (fix round 1)
	var hulls: FarHulls = FarHulls.attach(world)
	sim.core.tier_set_proxy(body_id, hulls.class_of(cap.drawn_mesh()) if hulls != null else -1, FarDots.DEFAULT_PAINT)
	if hulls == null:
		FarDots.attach(world)
	cap.park_for_tier()
	_tiered_capitals[body_id] = cap
	_park_origins[body_id] = _origin()
	demotions += 1
	return true


# The body back from its row: where the row says (or, with no row left, where the body was parked, in today's frame).
func _restore(body_id: int, state: Dictionary) -> void:
	var parked_origin: UniversePos = _park_origins.get(body_id)
	_park_origins.erase(body_id)
	var c: Combatant = _tiered_ships.get(body_id)
	if c != null:
		_tiered_ships.erase(body_id)
		if c.driver != null:
			c.driver.set_tiered(false)
		if is_instance_valid(c.ship):
			if state.is_empty():
				_reframe(c.ship, parked_origin)
			ships.return_from_tier(c, state)
			if bool(state.get("hulk", false)):
				_make_hulk(c)
		return
	var cap: CapitalStandin = _tiered_capitals.get(body_id)
	if cap != null:
		_tiered_capitals.erase(body_id)
		if is_instance_valid(cap):
			if state.is_empty():
				_reframe(cap, parked_origin)
				cap.unpark_from_tier(cap.global_transform, cap.linear_velocity, cap.angular_velocity)
			else:
				cap.unpark_from_tier(Transform3D(state["basis"], state["position"]), state["velocity"], state["angular"])


# A parked body skipped every rebase since it was parked; this puts it back at the same universe position in the frame of now.
func _reframe(body: Node3D, parked_origin: UniversePos) -> void:
	if parked_origin == null or world == null or not is_instance_valid(world):
		return
	body.global_position = world.universe_to_local(parked_origin.plus_local(body.global_position))


func _origin() -> UniversePos:
	return world.origin if world != null and is_instance_valid(world) else null


# A promoted hulk: no pilot, no thrust, no assist, its trigger released; it coasts under Jolt as it drifted in the tier.
func _make_hulk(c: Combatant) -> void:
	if c.driver != null:
		c.driver.brain = null
	c.ship.set_hulk(true)
	c.cannon.set_combat_command(CombatCommand.new())


# A native AI pilot the host does not step yet would never think in the tier: it stays in Jolt until it is hosted.
func _waits_for_host(c: Combatant) -> bool:
	var pilot := c.driver.brain as AiPilot if c.driver != null else null
	return pilot != null and pilot.native_capable() and not c.driver.is_hosted()


# Body `body_id`'s `Damageable`, found once and kept (a ship keeps its hull for life; fix round 2: looking it up among
# the children per hit was most of a far hit's cost).
static func _damageable_of(body_id: int) -> Damageable:
	var known: Damageable = _damageables.get(body_id)
	if known != null and is_instance_valid(known):
		return known
	_damageables.erase(body_id)
	if not is_instance_id_valid(body_id):
		return null
	var found: Damageable = Damageable.of(instance_from_id(body_id) as Node)
	if found != null:
		_damageables[body_id] = found
	return found


# The tier fighters' hits the core rolled since the last tick, landed now (before any handover, so a kill parks its ship
# through the pool before the sync).
func _land_fighter_hits(sim: SimCore) -> void:
	if int(sim.core.tier_hit_count()) == 0:
		land_us = 0
		return
	var started: int = Time.get_ticks_usec()  # a readout, never gameplay time
	var hits: Array = sim.core.tier_take_hits()
	var targets: PackedInt64Array = hits[0]
	if not targets.is_empty():
		hits_landed += land_hits(targets, hits[1], hits[2], hits[3])
	land_us = Time.get_ticks_usec() - started


## Starts the tier's cost readouts afresh (the bench calls it at its window's start).
func reset_costs() -> void:
	_cost_fighters_us = 0.0
	_cost_capitals_us = 0.0
	_cost_fighter_rows = 0
	_cost_capital_rows = 0
	_cost_ticks = 0
	_shots_at_reset = int(_sim.core.tier_shots()) if _sim != null and is_instance_valid(_sim) and _sim.core != null else 0
	_hits_at_reset = hits_landed
	_rolls_at_reset = standins.tier_group_rolls if standins != null and is_instance_valid(standins) else 0
	_cost_thinks = 0
	_cost_think_us = 0.0
	_cost_thinks_max = 0


## What the tier did since `reset_costs` (the bench's window): the cost means (`cost_means`), the fighters' shots rolled and
## hits landed, and the mean rows.
func window_summary() -> Dictionary:
	var means: PackedFloat64Array = cost_means()
	var ticks: float = float(maxi(_cost_ticks, 1))
	var shots: int = (int(_sim.core.tier_shots()) if _sim != null and is_instance_valid(_sim) and _sim.core != null else 0) - _shots_at_reset
	var fighter_rows: float = float(_cost_fighter_rows) / ticks
	var think_us: float = _cost_think_us / ticks
	return {"fighters_us": means[0], "capitals_us": means[1], "per_fighter_us": means[2], "per_capital_us": means[3],
			"fighter_rows": fighter_rows, "capital_rows": float(_cost_capital_rows) / ticks,
			"shots": shots, "hits": hits_landed - _hits_at_reset,
			"capital_rolls": (standins.tier_group_rolls if standins != null and is_instance_valid(standins) else 0) - _rolls_at_reset,
			"thinks_per_tick": float(_cost_thinks) / ticks, "thinks_max": _cost_thinks_max, "think_us": think_us,
			"per_fighter_think_us": think_us / maxf(fighter_rows, 1.0),
			"think_schedule": String(Settings.get_value(&"sim_step"))}


## The tier's main-thread cost per tick since `reset_costs`, us: `[fighters, capitals, per fighter row, per capital row]`
## (wall clock, a readout; the fighters' thinks run in the AI step's job, off the main thread, and are not in it).
func cost_means() -> PackedFloat64Array:
	var ticks: float = float(maxi(_cost_ticks, 1))
	var fighters: float = _cost_fighters_us / ticks
	var capitals: float = _cost_capitals_us / ticks
	return PackedFloat64Array([fighters, capitals, fighters / maxf(float(_cost_fighter_rows) / ticks, 1.0),
			capitals / maxf(float(_cost_capital_rows) / ticks, 1.0)])


# The last tick's tier work into the sums: the integration and the fighters' rolls (the core and its cannons), this
# tick's landing, and the far capitals' rolls (the stand-ins' weapon rows).
func _sum_costs(sim: SimCore) -> void:
	var fighters: int = int(sim.core.tier_fighters())
	var capitals: int = int(sim.core.tier_capitals())
	if fighters + capitals == 0:
		return
	var cannons_us: float = float(sim.cannons.tier_us()) if sim.cannons != null else 0.0
	# The integration is shared by row count; the capitals' launch rolls are inside their figure.
	var step_us: float = float(sim.core.tier_step_us())
	var share: float = float(fighters) / float(fighters + capitals)
	_cost_fighters_us += step_us * share + cannons_us + float(land_us)
	_cost_capitals_us += step_us * (1.0 - share) + (standins.tier_fire_us() if standins != null and is_instance_valid(standins) else 0.0)
	_cost_fighter_rows += fighters
	_cost_capital_rows += capitals
	_cost_ticks += 1
	var host: Object = NativeBrains.host(get_tree())
	if host != null and host.has_method(&"tier_thinks"):
		var thinks: int = int(host.tier_thinks())
		_cost_thinks += thinks
		_cost_thinks_max = maxi(_cost_thinks_max, thinks)
		_cost_think_us += float(host.tier_think_us())


# The rams the core finds where a tier ship meets its rammer's target, landed by the near rule (`RamResolver.ram_pending`),
# through the ram resolver when there is one (so `ram_resolved` hears them). Timed into the fighters' landing cost; nothing
# to look for with no tier rows.
func _land_rams(sim: SimCore) -> void:
	if int(sim.core.tier_fighters()) + int(sim.core.tier_capitals()) == 0:
		return
	var started: int = Time.get_ticks_usec()  # a readout, never gameplay time
	var found: Array = sim.core.tier_ram_contacts(get_physics_process_delta_time())
	var rammers: PackedInt64Array = found[0]
	if rammers.is_empty():
		land_us += Time.get_ticks_usec() - started
		return
	var pending: Array[Array] = []
	for k: int in rammers.size():
		var first: Dictionary = _ram_hull(rammers[k], (found[2] as PackedVector3Array)[k])
		var second: Dictionary = _ram_hull((found[1] as PackedInt64Array)[k], (found[3] as PackedVector3Array)[k])
		if first.is_empty() or second.is_empty():
			continue
		pending.append_array(RamResolver.ram_pending(first, second, (found[4] as PackedVector3Array)[k], "tier ram"))
	var rams: RamResolver = RamResolver.current()
	if rams != null:
		rams.land(pending)
	else:
		for ram: Array in pending:
			(ram[0] as Damageable).apply_hit(ram[1] as HitInfo)
	rams_landed += pending.size()
	land_us += Time.get_ticks_usec() - started


# A hull as the ram rule takes it, from body `body_id` and the velocity its row has; empty when it is gone or destroyed.
func _ram_hull(body_id: int, velocity: Vector3) -> Dictionary:
	if not is_instance_id_valid(body_id):
		return {}
	var body := instance_from_id(body_id) as Node3D
	var damageable: Damageable = Damageable.of(body)
	if damageable == null or damageable.hull.destroyed:
		return {}
	return {"id": body_id, "damageable": damageable, "velocity": velocity, "mass": damageable.ram_mass()}


# --- the frame and the bookkeeping -----------------------------------------------------------------------------------------


# The beat's period and the pull, pushed when they change (a rebase moves the core's own copy of the sources).
func _push_frame(sim: SimCore) -> void:
	if seed_value != _seed_given:
		_seed_given = seed_value
		sim.core.tier_set_seed(seed_value)
	var period: int = period_ticks()
	if period != _period_given:
		_period_given = period
		sim.core.tier_set_period(period)
	var moon: GravityStandin = standins.gravity() if standins != null and is_instance_valid(standins) else null
	var gm: float = moon.gm if moon != null else 0.0
	if moon != _gravity_given or gm != _gravity_gm_given:
		_gravity_given = moon
		_gravity_gm_given = gm
		if moon == null:
			sim.core.tier_set_gravity(PackedVector3Array(), PackedFloat64Array())
		else:
			sim.core.tier_set_gravity(PackedVector3Array([moon.local_position()]), PackedFloat64Array([gm]))


# Rows whose body is gone (a capital freed by the bench's clear) leave the tier.
func _prune(sim: SimCore) -> void:
	for body_id: int in _tiered_capitals.keys():
		var cap: CapitalStandin = _tiered_capitals[body_id]
		if not is_instance_valid(cap) or not cap.is_inside_tree():
			_tiered_capitals.erase(body_id)
			_park_origins.erase(body_id)
			sim.core.tier_remove(body_id)
	for body_id: int in _tiered_ships.keys():
		var c: Combatant = _tiered_ships[body_id]
		if not is_instance_valid(c.ship) or not c.ship.is_inside_tree():
			_tiered_ships.erase(body_id)
			_park_origins.erase(body_id)
			sim.core.tier_remove(body_id)


func _ship_of(body_id: int) -> Combatant:
	if ships == null or not is_instance_valid(ships):
		return null
	if ships.pool_size() != _ships_known:
		_ships_known = ships.pool_size()
		_ships_by_body.clear()
		for c: Combatant in ships.all_ships():
			_ships_by_body[c.ship.get_instance_id()] = c
	return _ships_by_body.get(body_id)


func _capital_of(body_id: int) -> CapitalStandin:
	if standins == null or not is_instance_valid(standins):
		return null
	var capitals: Array[CapitalStandin] = standins.capitals()
	if capitals.size() != _capitals_known or not _capitals_by_body.has(body_id):
		_capitals_known = capitals.size()
		_capitals_by_body.clear()
		for cap: CapitalStandin in capitals:
			if is_instance_valid(cap):
				_capitals_by_body[cap.get_instance_id()] = cap
	return _capitals_by_body.get(body_id)


## The last frame's far proxy update on the CPU, us (M4-T23): the far dots' and the far hulls' refreshes.
func proxy_us() -> int:
	var dots: FarDots = FarDots.of(world)
	var hulls: FarHulls = FarHulls.of(world)
	return (dots.last_refresh_us if dots != null else 0) + (hulls.last_refresh_us if hulls != null else 0)


func _register_console() -> void:
	DebugConsole.registry.register_provider(&"tier", ConsoleVars.new({
		&"radius_m": {"get": radius_m, "unit": "m", "doc": "Ships within this of the player fly in Jolt; beyond it plus 10 % they are tier rows (the setting tier_radius_m; 0 = off)"},
		&"period_ticks": {"get": period_ticks, "doc": "Ticks between a tier row's beats (the setting tier_hz)"},
		&"fighters": {"get": tier_fighters, "doc": "Fighters in the tier now"},
		&"capitals": {"get": tier_capitals, "doc": "Capitals in the tier now"},
		&"rows": {"get": func() -> int: return int(_sim.core.tier_count()) if _sim != null and is_instance_valid(_sim) and _sim.core != null else 0,
				"doc": "Tier rows in the core now"},
		&"hulks": {"get": func() -> int: return int(_sim.core.tier_hulks()) if _sim != null and is_instance_valid(_sim) and _sim.core != null else 0,
				"doc": "Tier rows drifting as hulks"},
		&"promotions": {"get": func() -> int: return promotions, "doc": "Rows handed back onto their bodies so far"},
		&"demotions": {"get": func() -> int: return demotions, "doc": "Bodies parked into the tier so far"},
		&"step_us": {"get": func() -> int: return int(_sim.core.tier_step_us()) if _sim != null and is_instance_valid(_sim) and _sim.core != null else 0,
				"unit": "us", "doc": "The last tick's tier integration inside the core's first sync; wall clock"},
		&"director_us": {"get": func() -> int: return last_us, "unit": "us", "doc": "The last tick's handovers; wall clock"},
		&"brain_period_ticks": {"get": brain_period_ticks, "doc": "Ticks between a tier fighter's thinks (the setting tier_brain_hz, M4-T22)"},
		&"shots": {"get": func() -> int: return int(_sim.core.tier_shots()) if _sim != null and is_instance_valid(_sim) and _sim.core != null else 0,
				"doc": "Tier fighters' shots rolled so far (M4-T22)"},
		&"hits": {"get": func() -> int: return int(_sim.core.tier_hits()) if _sim != null and is_instance_valid(_sim) and _sim.core != null else 0,
				"doc": "Tier fighters' rolled hits so far (M4-T22)"},
		&"hits_landed": {"get": func() -> int: return hits_landed, "doc": "Tier fighters' hits landed through a Damageable so far (a target gone takes none)"},
		&"land_us": {"get": func() -> int: return land_us, "unit": "us", "doc": "The last tick's landing of the tier fighters' hits; wall clock"},
		&"capital_rolls": {"get": func() -> int: return standins.tier_group_rolls if standins != null and is_instance_valid(standins) else 0,
				"doc": "Far capitals' group rolls run so far, one a second each (M4-T22)"},
		&"capital_hits": {"get": func() -> int: return standins.tier_hits_landed if standins != null and is_instance_valid(standins) else 0,
				"doc": "Far capitals' rolled hits landed since the bench's window began (M4-T22)"},
		&"capital_fire_us": {"get": func() -> float: return standins.tier_fire_us() if standins != null and is_instance_valid(standins) else 0.0,
				"unit": "us", "doc": "The last tick's far-capital rolls; wall clock (M4-T22)"},
		&"seed": {"get": func() -> int: return seed_value, "doc": "The seed the tier's rolls draw from (the bench's seed; fix round 1)"},
		&"rams": {"get": func() -> int: return rams_landed, "doc": "Rams the tier landed so far (a committed rammer meeting its target where one of the two is a tier row; fix round 1)"},
		&"thinks": {"get": func() -> int: return int(NativeBrains.host(get_tree()).tier_thinks()) if NativeBrains.host(get_tree()) != null else 0,
				"doc": "Tier fighters' thinks in the last handed-over AI step (fix round 1)"},
		&"think_us": {"get": func() -> float: return float(NativeBrains.host(get_tree()).tier_think_us()) if NativeBrains.host(get_tree()) != null else 0.0,
				"unit": "us", "doc": "Their summed time on the step's own clock: the worker thread when sim_step is threaded, the main thread when delayed (fix round 1)"},
		&"proxy_dots": {"get": func() -> int: return FarDots.of(world).tier_shown if FarDots.of(world) != null else 0,
				"doc": "Tier fighters drawn as far dots by the last frame (M4-T23)"},
		&"proxy_hulls": {"get": func() -> int: return FarHulls.of(world).shown if FarHulls.of(world) != null else 0,
				"doc": "Tier capitals drawn as far hull instances by the last frame (M4-T23)"},
		&"proxy_us": {"get": proxy_us, "unit": "us",
				"doc": "The last frame's far proxy update on the CPU: the far dots (near and tier) and the far hulls; wall clock (M4-T23)"},
		&"flashes": {"get": func() -> int: return FarFlashes.of(world).flash_count() if FarFlashes.of(world) != null else 0,
				"doc": "Far deaths shining as point flashes now (M4-T23)"},
		&"cleared": {"get": func() -> int: return int(_sim.core.tier_cleared()) if _sim != null and is_instance_valid(_sim) and _sim.core != null else 0,
				"doc": "Promotions moved clear of a rock or mine they overlapped so far (M4-T23)"},
		&"cost_us": {"get": func() -> String: return "%.1f fighters, %.1f capitals; %.3f a fighter, %.2f a capital" % Array(cost_means()),
				"doc": "The tier's main-thread cost per tick since the bench's window began (or the first tier row): the fighters' part (integration, rolls, landing), the far capitals' rolls, and each per row, us; wall clock (M4-T22)"},
	}), self)
