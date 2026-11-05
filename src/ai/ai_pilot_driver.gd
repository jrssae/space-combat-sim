class_name AiPilotDriver
extends Node
## Runs a `PilotBrain` for one ship (architecture §15.3, §15.8, §16.3, §17.4). A child of the AI ship at
## `process_physics_priority` -10, so the ship uses this tick's command. Each think (every tick, or at the far rate: below) it
## builds a fresh `Perception` (contacts and incoming fire from the shared `ContactScan`, broadcasts beyond 5 km, M3-T17), asks
## the brain, filters the brain's desired velocity through
## `AvoidanceMath` (D33) and hands the result to `Combatant.apply_commands`, the same call the player's input uses. With no
## brain the ship keeps the commands it has.
##
## Avoidance: when the filter changes the wish, thrust is sought again toward the filtered velocity (with
## `URGENT_SEEK_HORIZON_S` when urgent), allocated as the brain allocated its own (`desired_all_axes`, M3-T07). Turn and
## combat commands are left alone. A held brake is never filtered. The tie-break seed is `hash(display_name)`, so a ship
## dodges the same way every run.
##
## Targeting (`PilotBrain.wanted_target_id`): a brain that leaves it at `TARGET_NEAREST_HOSTILE` (every M2 brain) gets the
## nearest hostile, refreshed every `RETARGET_S`. Otherwise the driver follows the brain's target, or clears the selection
## for `TARGET_NONE`.
##
## Think rate (M4-T04, §17.4): a ship within `ai_think_near_m` of a live player thinks every tick; a farther one (every one
## with no player alive) thinks at `ai_think_far_hz` on staggered ticks (`AiThinkRate`) and holds its last command between:
## the driver does not replace it, so the ship keeps flying it (`Ship` holds a command until the next) and its physics steps
## every tick. A think is given the time since the last one. A new pilot or a hit wakes the ship for the next tick; anything
## else (a target lost, the line crossed) waits at most one far period. Avoidance runs with the think.
##
## Nearest-k (M4-T04): with `ai_nearest_k` above 0 the perception's contacts are the nearest k (`ContactScan.nearest_for`),
## and when that leaves any out, the nearest hostile ship, what the brain keeps (`PilotBrain.keep_ids`, `keep_names`), the
## selected target and the latest attacker of the last `KEEP_ATTACKER_S`. The brain scores, avoids and checks its fire lane
## against them alone.
##
## Statics (M4-T09): the perception's `statics` are the nearest `ai_nearest_static_k` rocks and mines (`ContactScan.statics_for`),
## never among the contacts; avoidance steers round them with the contacts.
##
## Native kernels (M4-T16, §17.13): on a core scan the perception also carries the scan's pilot kernels, the core rows its
## contacts and statics were picked from and the ship's relation row, so avoidance, the fire lane and the context lists
## each run in one native call (`AvoidanceMath.filter_seen`, `FireLane.clear_seen`, `AiContext.refresh`), bit for bit
## with the GDScript, which answers off the core. The tie-break seed is passed in as before.
##
## Native brains (M4-T17, §17.13): with the native host on (`NativeBrains.host`), an `AiPilot` thinks in one native call
## over the core's rows: the driver hands it a perception without contact lists (the host picks them from the rows as the
## scan would) and takes the finished command, the dodge flags and the wanted target back; the avoidance ran inside. When
## the host declines (the ship has no row this tick, the rows moved under the scan), the driver perceives and thinks in
## GDScript as before.
##
## Commands as rows (M4-T33, `perf_native_commands`): a native think in a rows batch hands in only what the rows do not
## hold (the core reads the hull and the selection at the sync), and the host writes the command into the core, where the
## flight batch flies it the same tick. The driver does nothing for that think at -9 unless the batch names it: the ship's
## first command from its row (the ship and the cannon are handed their commands once, and fly the row's from then on), a
## changed trigger (the cannon's command), a target to select. The rest it reads when it next needs it: whether the think
## landed (the think rate's clock and wake), and the pilot's state (`AiPilot.set_pending`). A new pilot, or a command set
## from GDScript, releases the ship from its row.
##
## Console (§16.4, M3-T06): `AiConsole` is registered while any driver is in the tree, owned by the newest. `think_us()` is
## wall-clock time, a profiling readout (AC13), never gameplay time.

## Seconds between looking for a nearer hostile (a selection that is gone is replaced at once).
const RETARGET_S: float = 0.5
## The urgent dodge's seek horizon, s: the RCS reaches full strafe for a quarter of the velocity error it would at 1 s.
const URGENT_SEEK_HORIZON_S: float = 0.25
## Whoever hit this ship stays in its contacts this long after the hit, however far within the sensors (M4-T04).
const KEEP_ATTACKER_S: float = AiTemperament.PROVOKED_S
const RATE_SETTINGS: Array[StringName] = [&"ai_think_rate", &"ai_think_near_m", &"ai_think_far_hz", &"ai_nearest_k",
		&"ai_nearest_static_k"]

# Every driver in the tree (the console's view), and the think-time sums for `think_us`.
static var _live: Array[AiPilotDriver] = []
static var _think_frame: int = -1
static var _think_sum_us: int = 0
static var _think_last_us: int = 0
## The player's ship (`ShipAssembly` registers it through `register_player`), for the think rate's distance rule (M4-T04).
## Null: no player. Cleared when that ship leaves the tree, so a finished scene's player never counts.
static var player: Combatant = null
# Work counts of the latest tick the drivers ran (M4-T04): thinks near and far, held ticks, contacts handed to a brain.
static var _count_frame: int = -1
static var _thinks_near: int = 0
static var _thinks_far: int = 0
static var _held: int = 0
static var _contacts_max: int = 0
static var _thinks_native: int = 0
static var _thinks_fallback: int = 0
# The host and batch of this physics frame (`_frame_host`).
static var _lookup_frame: int = -1
static var _frame_host_cached: Object = null
static var _frame_batch: BrainBatch = null
# The think-rate and nearest-k settings, read on first use and again after any of them changes.
static var _settings_read: bool = false
static var _rate_on: bool = true
static var _near_sq: float = 4.0e6
static var _period: int = 3
static var _nearest_k: int = 12
static var _nearest_static_k: int = 4
# The player as seen at the start of this physics tick.
static var _player_frame: int = -1
static var _player_for: Combatant = null
static var _player_live: bool = false
static var _player_at: Vector3 = Vector3.ZERO

var combatant: Combatant = null
var world: WorldFrame = null
var brain: PilotBrain = null:
	set(value):
		brain = value
		last_hit_s = -INF
		last_bolt_hit_s = -INF
		last_attacker_id = 0
		_unselectable_id = 0
		_woken = true  # a new pilot decides at once
		_since_think_s = 0.0
		_steps = 0
		_ordinal = maxi(_live.find(self), 0)
		if combatant != null:
			_tie_hash = hash(combatant.display_name)
		_landing = null
		_avoid_from_pilot = false
		if combatant != null and is_instance_valid(combatant.ship):
			combatant.ship.release_row_command()  # a new pilot takes the ship from its row afresh
		if value != null:
			value.reset()
		_start_lights(value)
## Whether the avoidance filter changed this tick's command (the ship is dodging), and whether it was urgent. Read from
## the pilot after a rows think (M4-T33).
var avoiding: bool = false:
	get:
		return _pilot_avoiding(false) if _avoid_from_pilot else avoiding
var avoiding_urgent: bool = false:
	get:
		return _pilot_avoiding(true) if _avoid_from_pilot else avoiding_urgent
## Sim time of this hull's latest hit (`Damageable.hit_taken`), and of its latest bolt hit, -INF since the brain was set.
var last_hit_s: float = -INF
var last_bolt_hit_s: float = -INF
## The `Targetable` id of whoever hit this hull last (0: nobody, or the console).
var last_attacker_id: int = 0
## Whether the ship was within `ai_think_near_m` of a live player at its last step (M4-T04).
var near_player: bool = false

var _capability: ShipCapability = null
## The mean of the ship's muzzles, ship-local (muzzles never move on the hull, so computed once).
var _muzzle_local: Vector3 = Vector3.ZERO
var _muzzle_known: bool = false
# The avoidance tie-break, `hash(display_name)`, taken when the pilot is set (M4-T17's native path passes it in), and the
# perception a native think reads, reused tick after tick (the native think consumes it at once; nothing keeps it).
var _tie_hash: int = 0
var _lite: Perception = null
# `settings.friendly_fire` as last read, kept current through `Settings.changed` (read once per think otherwise).
static var _friendly_fire: int = -1
var _retarget_in_s: float = 0.0
var _unselectable_id: int = 0
# This ship is hiding: its lights are off until the brain attacks (M3-T27).
var _hiding: bool = false
# Think rate (M4-T04): steps since the pilot was set, this driver's place in the stagger, time since the last think, and
# whether the next step thinks whatever the rate.
var _steps: int = 0
var _ordinal: int = 0
var _since_think_s: float = 0.0
var _woken: bool = true
# `_keep_lists`, made once: the scan calls it only when the nearest-k cut leaves something out.
var _keeper: Callable = _keep_lists
# A rows think waiting to be read (M4-T33): the tick's answer, this ship's place in it, and the think rate's clock and wake
# as they stood before it (put back if the host declined it); whether `avoiding` reads the pilot; the combat command the
# ship and the cannon hold while the ship flies from its row.
var _landing: BrainAnswer = null
var _landing_index: int = 0
var _landing_since_s: float = 0.0
var _landing_woken: bool = false
var _avoid_from_pilot: bool = false
var _row_combat: CombatCommand = null
static var _frame_rows: bool = false
static var _no_origin: UniversePos = UniversePos.new()


func _init() -> void:
	process_physics_priority = -10


func _enter_tree() -> void:
	_live.append(self)
	AiConsole.register(DebugConsole.registry, self)
	_settings_read = false  # they may have changed while no driver listened
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)


func _exit_tree() -> void:
	_live.erase(self)
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)
	DebugConsole.registry.unregister_owner(self)
	if not _live.is_empty():
		AiConsole.register(DebugConsole.registry, _live.back())


func _ready() -> void:
	if combatant != null and combatant.damageable != null:
		combatant.damageable.hit_taken.connect(_on_hit_taken)


func _physics_process(delta: float) -> void:
	step(delta, true)


## One tick. `_physics_process` calls it with `batched` (a native think joins the tick's `BrainBatch`, M4-T18, and
## finishes in `finish_native` at -9); public so tests can drive it, by default thinking at once.
func step(delta: float, batched: bool = false) -> void:
	if brain == null or combatant == null or not is_instance_valid(combatant.ship):
		return
	var started_us: int = Time.get_ticks_usec()  # profiling readout only, never gameplay time
	if not _settings_read:
		_read_settings()
	if _landing != null:
		_settle_landing()
	near_player = _is_near_player()
	_steps += 1
	_since_think_s += delta
	if not AiThinkRate.thinks(_rate_on, _woken, near_player, _steps, _ordinal, _period):
		_count_held()
		_add_think_time(Time.get_ticks_usec() - started_us)
		return  # the ship flies the last command on
	var dt: float = _since_think_s  # one tick when it thinks every tick
	var pc: PilotCommand = null
	var pilot := brain as AiPilot
	if pilot != null and pilot.native_capable():
		var host: Object = _frame_host() if batched else NativeBrains.host(get_tree())
		if host != null:
			if batched and _frame_rows and _step_rows(pilot, host, dt):
				_add_think_time(Time.get_ticks_usec() - started_us)
				return  # the rows batch thinks it; the core flies its command
			# The scan stage on the native path: the shared scan's build and the perception (the lists are picked inside the
			# think, which the think stage counts).
			var timed: bool = ContactScan.timing
			var scan_started_us: int = Time.get_ticks_usec() if timed else 0  # profiling readout only
			var scan: ContactScan = ContactScan.shared(get_tree())
			var p: Perception = _perceive_lite(scan, host) if scan.rows_fresh() else null
			if timed:
				ContactScan.add_time(Time.get_ticks_usec() - scan_started_us)
			if p != null and batched:
				var batch: BrainBatch = _frame_batch
				var slot: int = pilot.prepare_native(p) if batch != null else -1
				if slot >= 0 and batch.add(self, host, p, slot, dt, scan.rows_version_taken()):
					_add_think_time(Time.get_ticks_usec() - started_us)
					return  # the batch thinks it and calls finish_native this tick
			if p != null:
				pc = pilot.try_think_native(p, dt)
			if pc == null and pilot.has_native_slot():
				_hold_declined()
				_add_think_time(Time.get_ticks_usec() - started_us)
				return
	_act(pc, pilot, dt)
	_add_think_time(Time.get_ticks_usec() - started_us)


## The end of a native think the tick's `BrainBatch` carried (M4-T18): the think's output starts at `base` in the batch's
## answer `out` (-1 when the host declined it); `dt` the time the think was given.
func finish_native(out: PackedFloat64Array, base: int, dt: float) -> void:
	var started_us: int = Time.get_ticks_usec()  # profiling readout only, never gameplay time
	var pilot := brain as AiPilot
	if pilot == null or combatant == null or not is_instance_valid(combatant.ship):
		return
	var pc: PilotCommand = pilot.apply_native(out, base)
	if pc == null:
		_hold_declined()
	else:
		_act(pc, pilot, dt)
	_add_think_time(Time.get_ticks_usec() - started_us)


# A native think into this tick's rows batch (M4-T33): the slot readied, the inputs handed in, the answer kept. The think
# rate's clock and wake are reset now as a landed think resets them, and put back if the host declines it. False when the
# think cannot go that way (stale rows, no slot, another batch): the caller then takes today's path.
func _step_rows(pilot: AiPilot, host: Object, dt: float) -> bool:
	var batch: BrainBatch = _frame_batch
	if batch == null:
		return false
	var timed: bool = ContactScan.timing
	var scan_started_us: int = Time.get_ticks_usec() if timed else 0  # profiling readout only
	var scan: ContactScan = ContactScan.shared(get_tree())
	var fresh: bool = scan.rows_fresh()
	if timed:
		ContactScan.add_time(Time.get_ticks_usec() - scan_started_us)
	if not fresh:
		return false
	var slot: int = pilot.prepare_rows(host, self, scan)
	if slot < 0:
		return false
	if _friendly_fire < 0:
		_friendly_fire = 1 if bool(Settings.get_value(&"friendly_fire")) else 0
	var index: int = batch.add_rows(self, host, slot, dt, combatant.faction, scan, near_player, last_attacker_id, last_hit_s,
			last_bolt_hit_s, scan.rows_version_taken(), SimClock.now(), _friendly_fire == 1,
			world.origin if world != null else _no_origin)
	if index < 0:
		return false
	_landing = batch.answer()
	_landing_index = index
	_landing_since_s = _since_think_s
	_landing_woken = _woken
	_since_think_s = 0.0
	_woken = false
	pilot.set_pending(_landing, index)
	_avoid_from_pilot = true
	return true


# Reads whether the last rows think landed: a declined one leaves the think rate's clock and wake as they would be.
func _settle_landing() -> void:
	var answer: BrainAnswer = _landing
	_landing = null
	if not answer.thought(_landing_index):
		_since_think_s += _landing_since_s
		_woken = _woken or _landing_woken


## What a rows batch names this driver for (M4-T33): `events` (`BrainBatch.EVENT_*`) from the think at `base` of the
## answer `out`. The ship's first command from its row hands the ship and the cannon their commands, as a think did; a
## changed trigger reaches the cannon; the first shot ends the hiding; a wanted target is selected.
func rows_event(events: int, out: PackedFloat64Array, base: int) -> void:
	if combatant == null or not is_instance_valid(combatant.ship):
		return
	var fire: bool = out[base + AiPilot.NATIVE_FIRE] != 0.0
	var trigger: bool = events & (BrainBatch.EVENT_ENTER | BrainBatch.EVENT_FIRE) != 0
	if events & BrainBatch.EVENT_ENTER != 0 or (trigger and _row_combat == null):
		_row_combat = CombatCommand.new()
		_row_combat.fire = fire
		combatant.apply_commands(AiPilot.native_flight(out, base), _row_combat)
		combatant.ship.use_row_command()
	elif trigger:
		_row_combat.fire = fire
	if trigger and fire and _hiding:  # the first shot ends the hiding (Q27)
		_hiding = false
		combatant.ship.running_lights = true
	if events & BrainBatch.EVENT_SELECT != 0:
		_follow_target(AiPilot.native_target_id(out, base))


## Adds a rows batch's counts to the tick's (M4-T33): thinks near and far, declined thinks (each held, as a far-rate tick
## is), and the most contacts a think saw.
static func add_rows_counts(near: int, far: int, declined: int, contacts: int) -> void:
	_roll_counts()
	_thinks_near += near
	_thinks_far += far
	_thinks_native += near + far
	_thinks_fallback += declined
	_held += declined
	_contacts_max = maxi(_contacts_max, contacts)


## The ship's body id (the native slot's bound body).
func own_body_id() -> int:
	return combatant.ship.get_instance_id()


## The perception a native slot is bound from (`AiPilot.prepare_rows`, when the slot or the ship is new).
func lite_perception(scan: ContactScan, host: Object) -> Perception:
	return _perceive_lite(scan, host)


# The dodge as the pilot's last landed native think left it.
func _pilot_avoiding(urgent: bool) -> bool:
	var pilot := brain as AiPilot
	if pilot == null:
		return false
	pilot.settle_native()
	return pilot.native_avoiding_urgent if urgent else pilot.native_avoiding


# Declined with a brain in the slot: the GDScript objects hold only a mirror, so this tick is held, as a far-rate tick
# is, and the think waits for the next one.
func _hold_declined() -> void:
	_roll_counts()
	_thinks_fallback += 1
	_count_held()


# What a think ends with: the GDScript brain when no native command came (`pc` null), avoidance, the selection and the
# command handed to the ship.
func _act(pc: PilotCommand, pilot: AiPilot, dt: float) -> void:
	_avoid_from_pilot = false
	_since_think_s = 0.0
	_woken = false
	_count_think(near_player)
	_retarget(dt)
	if pc != null:
		_thinks_native += 1
		_contacts_max = maxi(_contacts_max, pilot.native_contacts)
		avoiding = pilot.native_avoiding
		avoiding_urgent = pilot.native_avoiding_urgent
	else:
		var p: Perception = perceive()
		_contacts_max = maxi(_contacts_max, p.contacts.size())
		brain.has_desired_velocity = false
		pc = brain.think(p, dt)
		_avoid(p, pc.flight)
	if _hiding and pc.combat != null and pc.combat.fire:  # the first shot ends the hiding (Q27)
		_hiding = false
		combatant.ship.running_lights = true
	_follow_target(brain.wanted_target_id)
	combatant.apply_commands(pc.flight, pc.combat)


# A pool ship is somebody new each time: its lights start as its new pilot wants them, whatever the last one did.
func _start_lights(new_brain: PilotBrain) -> void:
	_hiding = new_brain != null and new_brain.flies_dark
	if combatant != null and is_instance_valid(combatant.ship):
		combatant.ship.running_lights = not _hiding


## Wall-clock microseconds every driver's `step` took in the last complete physics tick (the console's `ai.think_us`).
static func think_us() -> int:
	return _think_last_us


## Wall-clock microseconds every driver's `step` has taken so far in the current physics tick (`PerfProbe`, M4-T01).
static func think_us_this_tick() -> int:
	return _think_sum_us if _think_frame == Engine.get_physics_frames() else 0


## Makes `c` the player AI ships measure their think rate from, until its ship leaves the tree.
static func register_player(c: Combatant) -> void:
	player = c
	c.ship.tree_exited.connect(func() -> void:
		if player == c:
			player = null)


## How many AI ships near the player thought in the latest tick the drivers ran (M4-T04).
static func thinks_near() -> int:
	return _thinks_near


## How many AI ships far from the player (or with no player alive) thought in the latest tick the drivers ran.
static func thinks_far() -> int:
	return _thinks_far


## How many AI ships held their last command in the latest tick the drivers ran.
static func held() -> int:
	return _held


## How many AI ships thought in the native brains in the latest tick the drivers ran (M4-T17).
static func thinks_native() -> int:
	return _thinks_native


## How many native pilots the host declined in the latest tick (the rows moved under the frame's scan, or the ship had no
## row): each held its last command for that tick, as a held think does, so its brain never ran on a stale mirror (M4-T17).
static func thinks_fallback() -> int:
	return _thinks_fallback


## The most contacts any AI ship scored and avoided in the latest tick the drivers ran.
static func contacts_max() -> int:
	return _contacts_max


## A `Perception` of this tick.
func perceive() -> Perception:
	var ship: Ship = combatant.ship
	var p := Perception.new()
	p.now_s = SimClock.now()
	p.position = ship.global_position
	p.basis = ship.global_basis
	p.velocity = ship.linear_velocity
	p.angular_velocity = ship.angular_velocity
	p.self_id = combatant.targetable.get_instance_id() if combatant.targetable != null else 0
	p.hull_fraction = combatant.damageable.hull.fraction() if combatant.damageable != null else 1.0
	p.faction = combatant.faction
	if _capability == null:
		_capability = ShipCapability.from_spec(ship.spec, ship.get_layout())
	p.capability = _capability
	_ensure_muzzle(ship)
	p.muzzle_offset = ship.global_basis * _muzzle_local
	var weapon: WeaponSpec = combatant.cannon.weapon
	p.muzzle_speed_mps = weapon.muzzle_speed_mps
	p.weapon_lifetime_s = weapon.lifetime_s
	if world != null:
		p.frame_origin = world.origin  # a rebase assigns a new origin, so keep this tick's
	var targeting: TargetingController = ship.targeting
	if (brain == null or brain.reads_target()) and targeting.system.has_selection() \
			and is_instance_id_valid(targeting.selected_id()):
		var targetable := instance_from_id(targeting.selected_id()) as Targetable
		if targetable != null and targetable.is_active():
			p.target = targetable.to_target_info()
			p.target_hostile = Factions.is_hostile(combatant.faction, targetable.faction)
	var timed: bool = ContactScan.timing
	var scan_started_us: int = Time.get_ticks_usec() if timed else 0  # profiling readout only (M4-T01)
	var scan: ContactScan = ContactScan.shared(get_tree())
	var own_id: int = ship.get_instance_id()
	if not _settings_read:
		_read_settings()
	if _nearest_k > 0:
		p.contacts = scan.nearest_for(own_id, p.position, p.faction, _nearest_k, _keeper)
	else:
		p.contacts = scan.contacts_for(own_id, p.position, p.faction)
	var contact_rows: PackedInt32Array = scan.picked_rows
	p.statics = scan.statics_for(own_id, p.position, p.faction, _nearest_static_k)
	var kernels: Object = scan.pilot_kernels()
	if kernels != null:
		p.kernels = kernels
		p.contact_rows = contact_rows
		p.static_rows = scan.picked_rows
		p.relation_row = scan.relation_row(p.faction)
	p.incoming_fire = scan.incoming_fire(own_id, p.position, p.velocity, p.faction)
	p.broadcasts = ContactScan.shared_broadcasts().broadcasts_for(own_id, p.position, p.faction)
	if timed:
		ContactScan.add_time(Time.get_ticks_usec() - scan_started_us)
	p.last_hit_s = last_hit_s
	p.last_bolt_hit_s = last_bolt_hit_s
	p.last_attacker_id = last_attacker_id
	p.friendly_fire = bool(Settings.get_value(&"friendly_fire"))
	return p


## The perception of a native think (M4-T17): the ship's own state and what the host cannot read from the rows, with no
## contact lists (the host picks them from the rows as `perceive` would).
func _perceive_lite(scan: ContactScan, host: Object) -> Perception:
	var ship: Ship = combatant.ship
	if _lite == null:
		_lite = Perception.new()
	var p: Perception = _lite
	p.now_s = SimClock.now()  # the pose and motion come from the ship's row, so they are not read here (M4-T18)
	p.self_id = combatant.targetable.get_instance_id() if combatant.targetable != null else 0
	p.hull_fraction = combatant.damageable.hull.fraction() if combatant.damageable != null else 1.0
	p.faction = combatant.faction
	if _capability == null:
		_capability = ShipCapability.from_spec(ship.spec, ship.get_layout())
	p.capability = _capability
	_ensure_muzzle(ship)
	p.muzzle_local = _muzzle_local
	var weapon: WeaponSpec = combatant.cannon.weapon
	p.muzzle_speed_mps = weapon.muzzle_speed_mps
	p.weapon_lifetime_s = weapon.lifetime_s
	if world != null:
		p.frame_origin = world.origin
	p.brains = host
	p.own_body_id = ship.get_instance_id()
	p.selected_id = ship.targeting.selected_id()
	p.bounding_radius = combatant.damageable.bounding_radius if combatant.damageable != null else 0.0
	p.tie_hash = _tie_hash
	p.relation_row = scan.relation_row(p.faction)
	p.last_hit_s = last_hit_s
	p.last_bolt_hit_s = last_bolt_hit_s
	p.last_attacker_id = last_attacker_id
	if _friendly_fire < 0:
		_friendly_fire = 1 if bool(Settings.get_value(&"friendly_fire")) else 0
	p.friendly_fire = _friendly_fire == 1
	return p


# The mean of the ship's muzzles in its frame, found once.
func _ensure_muzzle(ship: Ship) -> void:
	if _muzzle_known:
		return
	_muzzle_known = true
	var mean := Vector3.ZERO
	var muzzles: Array[Node3D] = ship.get_muzzles()
	for muzzle: Node3D in muzzles:
		mean += ship.to_local(muzzle.global_position)
	_muzzle_local = mean / float(muzzles.size()) if not muzzles.is_empty() else Vector3.ZERO


# Applies the avoidance filter (D33) to the brain's wish.
func _avoid(p: Perception, flight: FlightCommand) -> void:
	avoiding = false
	avoiding_urgent = false
	if flight.brake or (p.contacts.is_empty() and p.statics.is_empty()):
		return
	var wish: Vector3 = brain.desired_velocity if brain.has_desired_velocity else p.velocity
	var radius: float = combatant.damageable.bounding_radius if combatant.damageable != null else 0.0
	# A committed rammer flies into its target (M3-T13), everything else is still avoided; rocks and mines too (M4-T09).
	var result: Dictionary = AvoidanceMath.filter_seen(p, radius, wish, brain.avoid_exempt_id, hash(combatant.display_name))
	var filtered: Vector3 = result["v_des"]
	if filtered == wish:
		return
	avoiding = true
	avoiding_urgent = bool(result["urgent"])
	var horizon: float = URGENT_SEEK_HORIZON_S if avoiding_urgent else PilotSteering.HORIZON_S
	var all_axes: bool = brain.has_desired_velocity and brain.desired_all_axes
	PilotSteering.apply_seek(flight, PilotSteering.seek(p.velocity, filtered, p.basis, p.capability, horizon, all_axes))


# What stays in the contacts beyond the nearest k: what the brain keeps, the selection and a recent attacker. Asked only
# when the cut leaves something out (`ContactScan.nearest_for`).
func _keep_lists() -> Array:
	var ids: PackedInt64Array = brain.keep_ids().duplicate() if brain != null else PackedInt64Array()
	var targeting: TargetingController = combatant.ship.targeting
	if targeting.system.has_selection():
		ids.append(targeting.selected_id())
	if last_attacker_id != 0 and SimClock.now() - last_hit_s <= KEEP_ATTACKER_S:
		ids.append(last_attacker_id)
	return [ids, brain.keep_names() if brain != null else PackedStringArray()]


func _on_hit_taken(info: HitInfo) -> void:
	_woken = true  # a hit is answered on the next tick, far or near
	last_hit_s = SimClock.now()
	if info != null and info.cause == HitInfo.CAUSE_BOLT:
		last_bolt_hit_s = last_hit_s
	if info != null and info.shooter_id != 0 and is_instance_id_valid(info.shooter_id):
		var shooter := instance_from_id(info.shooter_id) as Node
		var marker := shooter.get_node_or_null(^"Targetable") as Targetable if shooter != null else null
		if marker != null:
			last_attacker_id = marker.get_instance_id()


# M2's rule for a brain that leaves the choice to the driver.
func _retarget(delta: float) -> void:
	if brain.wanted_target_id != PilotBrain.TARGET_NEAREST_HOSTILE:
		return  # the brain chooses (`_follow_brain_target`)
	var targeting: TargetingController = combatant.ship.targeting
	_retarget_in_s -= delta
	if _retarget_in_s <= 0.0 or not _selection_is_live(targeting):
		_retarget_in_s = RETARGET_S
		ContactScan.note_selection(combatant.ship)
		targeting.select_nearest_hostile()


# Keeps the selection on what the brain wants (`wanted`). A target it cannot select is not retried until it wants another.
func _follow_target(wanted: int) -> void:
	if wanted == PilotBrain.TARGET_NEAREST_HOSTILE:
		return
	var targeting: TargetingController = combatant.ship.targeting
	if wanted == PilotBrain.TARGET_NONE:
		if targeting.system.has_selection():
			ContactScan.note_selection(combatant.ship)
			targeting.clear_selection()
		return
	if wanted == _unselectable_id or targeting.selected_id() == wanted:
		return
	ContactScan.note_selection(combatant.ship)
	_unselectable_id = 0 if targeting.select_id(wanted) else wanted


# Starts the work counts afresh on the first driver of a tick.
static func _roll_counts() -> void:
	var frame: int = Engine.get_physics_frames()
	if frame != _count_frame:
		_count_frame = frame
		_thinks_near = 0
		_thinks_far = 0
		_held = 0
		_contacts_max = 0
		_thinks_native = 0
		_thinks_fallback = 0


static func _count_think(near: bool) -> void:
	_roll_counts()
	if near:
		_thinks_near += 1
	else:
		_thinks_far += 1


static func _count_held() -> void:
	_roll_counts()
	_held += 1


# Whether a live player flies within `ai_think_near_m` of this ship.
func _is_near_player() -> bool:
	var frame: int = Engine.get_physics_frames()
	if frame != _player_frame or _player_for != player:
		_player_frame = frame
		_player_for = player
		_player_live = player != null and is_instance_valid(player.ship) and player.damageable != null \
				and player.damageable.is_active()
		if _player_live:
			_player_at = player.ship.global_position
	return _player_live and combatant.ship.global_position.distance_squared_to(_player_at) <= _near_sq


static func _read_settings() -> void:
	_settings_read = true
	_rate_on = bool(Settings.get_value(&"ai_think_rate"))
	var near_m: float = float(Settings.get_value(&"ai_think_near_m"))
	_near_sq = near_m * near_m
	_period = AiThinkRate.period_ticks(float(Settings.get_value(&"ai_think_far_hz")), Engine.physics_ticks_per_second)
	_nearest_k = int(Settings.get_value(&"ai_nearest_k"))
	_nearest_static_k = int(Settings.get_value(&"ai_nearest_static_k"))
	NativeBrains.set_settings(_nearest_k, _nearest_static_k)


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key in RATE_SETTINGS:
		_settings_read = false
	elif key == &"friendly_fire":
		_friendly_fire = -1


## Adds wall-clock microseconds to this tick's think time (the `BrainBatch`'s native call, M4-T18); a readout only.
static func add_think_time(us: int) -> void:
	_add_think_time(us)


# The tick's brain host and batch for the drivers' physics steps, looked up once a physics frame (a hand-driven step
# looks them up itself).
static func _frame_host() -> Object:
	var frame: int = Engine.get_physics_frames()
	if frame != _lookup_frame:
		_lookup_frame = frame
		var tree := Engine.get_main_loop() as SceneTree
		_frame_host_cached = NativeBrains.host(tree)
		_frame_batch = BrainBatch.for_tree(tree)
		_frame_rows = _frame_batch != null and BrainBatch.rows_mode()
	return _frame_host_cached


static func _add_think_time(us: int) -> void:
	var frame: int = Engine.get_physics_frames()
	if frame != _think_frame:
		_think_last_us = _think_sum_us if _think_frame >= 0 else 0
		_think_sum_us = 0
		_think_frame = frame
	_think_sum_us += us


# Whether the selection can still be targeted (a destroyed or parked ship is replaced at once).
func _selection_is_live(targeting: TargetingController) -> bool:
	if not targeting.system.has_selection() or not is_instance_id_valid(targeting.selected_id()):
		return false
	var targetable := instance_from_id(targeting.selected_id()) as Targetable
	return targetable != null and targetable.is_active()


## The drivers flying a ship in play, for `AiConsole`.
static func flying() -> Array[AiPilotDriver]:
	var out: Array[AiPilotDriver] = []
	for driver: AiPilotDriver in _live:
		if driver.brain != null and driver.combatant != null and is_instance_valid(driver.combatant.ship) \
				and driver.combatant.ship.can_process():
			out.append(driver)
	return out
