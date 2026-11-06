class_name WaveDirector
extends Node
## Runs the combat sandbox's waves (architecture §15.10, M2-T09): owns the pure `WavePlan`, spawns raiders from the `ShipPool`
## with a `BrainFactory` brain, counts kills and losses, and feeds the HUD's status line. Free flight has no waves.
##
## Spawn positions are offsets from the player's universe position when the wave activates, or from the scenario's origin,
## as `UniversePos`. Never from the World's local origin, which the rebase keeps near the player (M3-T14).
##
## Waves are about raiders: allied ships in the pool (M3-T08) are not counted, not cleared when a wave starts or stops, and
## a destroyed ally is no kill.
##
## `process_physics_priority` 300: after the hit resolver (200), so a raider destroyed this tick is already out of `alive`.
## Kills: every raider destroyed counts, by anyone (rams included). `credit` (`KillCredit`, M3-T16, Q18) counts the player's
## own kills and assists. Losses: the player's deaths. All counts last the session. The wave goes on across the player's
## death (maintainer answer Q6): `on_player_respawned()` only makes the raiders pick the respawned player up at once.
##
## Console: provider `waves` and `wave [start|next|stop|restart] [index]`.

signal wave_started(number: int, wave_name: String)
signal wave_cleared(number: int)
signal kills_changed(kills: int)

const COMMANDS: Array[StringName] = [&"start", &"next", &"stop", &"restart"]

var world: WorldFrame = null
var pool: ShipPool = null
## Spawns that name a wing join it here (M3-T10: raider groups); null: they fly alone.
var wings: WingDirector = null
var player: Combatant = null
var scenario_id: StringName = &""
var plan: WavePlan = WavePlan.new()
var kills: int = 0
var losses: int = 0
## The player's kills and assists (`player_kills`, `player_assists`).
var credit: KillCredit = KillCredit.new()
## Called with the HUD status line whenever it changes (`Main` sets `status_line`).
var status_sink: Callable = Callable()

var _anchor_player: UniversePos = null
var _anchor_origin: UniversePos = null
var _status: String = ""
var _last_state: WavePlan.State = WavePlan.State.IDLE


func _init() -> void:
	process_physics_priority = 300


func _ready() -> void:
	DebugConsole.registry.register_provider(&"waves", ConsoleVars.new({
		&"scenario": {"get": func() -> String: return String(scenario_id), "doc": "The scenario that is loaded"},
		&"index": {"get": func() -> int: return plan.wave_number, "doc": "Wave number (1-based, counts through the loops); 0 before the first"},
		&"name": {"get": func() -> String: return plan.current_name(), "doc": "Name of the current wave"},
		&"state": {"get": func() -> String: return String(plan.state_name()), "doc": "idle, countdown, active or cleared"},
		&"next_in_s": {"get": func() -> float: return plan.countdown_remaining(), "unit": "s", "doc": "Seconds until the wave starts"},
		&"alive": {"get": func() -> int: return _raiders_alive().size(), "doc": "Raiders alive"},
		&"kills": {"get": func() -> int: return kills, "doc": "Raiders destroyed this session, by anyone"},
		&"player_kills": {"get": func() -> int: return credit.player_kills, "doc": "Raiders the player destroyed (the killing bolt or ram)"},
		&"player_assists": {"get": func() -> int: return credit.player_assists, "doc": "Raiders someone else destroyed after the player fired at them while they were selected"},
		&"losses": {"get": func() -> int: return losses, "doc": "Times the player was destroyed"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"wave",
			"Drive the waves: start [index] (1 = the first), next (skip this wave), stop, restart",
			[ConsoleArg.enum_required(&"action", COMMANDS), ConsoleArg.int_optional(&"index", 1, 1, 99)]), _cmd_wave, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


## Takes the waves from a validated scenario (`ScenarioLoader`) and wires the pool, the player and the destruction events.
## `auto_start` begins wave 1's countdown at once.
func setup(p_world: WorldFrame, p_pool: ShipPool, p_player: Combatant, scenario: Dictionary, destruction: DestructionDirector,
		auto_start: bool) -> void:
	world = p_world
	pool = p_pool
	player = p_player
	scenario_id = scenario.get("scenario_id", &"")
	var waves: Array[Dictionary] = scenario.get("waves", [] as Array[Dictionary])
	var loop: Dictionary = scenario.get("loop", {"from_wave": 0, "add_per_loop": 1})
	var pool_size: int = int((scenario.get("pools", {}) as Dictionary).get(ShipPool.DEFAULT_TYPE, 0))
	plan = WavePlan.new(waves, int(loop["from_wave"]), int(loop["add_per_loop"]), pool_size)
	plan.skill_step = float(loop.get("skill_step", 0.0))
	if destruction != null:
		destruction.raider_destroyed.connect(_on_raider_destroyed)
		destruction.player_destroyed.connect(_on_player_destroyed)
	if player != null:
		credit.player_id = player.ship.get_instance_id()
		if not player.cannon.shot_fired.is_connected(_on_player_fired):
			player.cannon.shot_fired.connect(_on_player_fired)
	if pool != null and not pool.acquired.is_connected(_on_pool_acquired):
		pool.acquired.connect(_on_pool_acquired)
	if auto_start and not waves.is_empty() and pool_size > 0:
		start(0)


## Begins wave `index` (0-based): clears the field and starts its countdown.
func start(index: int = 0) -> void:
	if plan.waves.is_empty():
		return
	_clear_field()
	plan.start(index)
	_after_change()


func stop() -> void:
	plan.stop()
	_after_change()


## The player is back: surviving raiders pick the respawned player up as their target straight away.
func on_player_respawned() -> void:
	if pool == null:
		return
	for combatant: Combatant in _raiders_alive():
		if combatant.driver != null:
			combatant.driver._retarget_in_s = 0.0


func _physics_process(delta: float) -> void:
	if not plan.is_running() or pool == null:
		return
	var requests: Array[Dictionary] = plan.update(delta, _raiders_alive().size())
	for request: Dictionary in requests:
		_spawn(request)
	_after_change()


# --- spawning ------------------------------------------------------------------------------------------------------


func _spawn(request: Dictionary) -> void:
	var anchor: UniversePos = _anchor_for(request)
	var offset: Vector3 = request["offset"]
	var at: UniversePos = anchor.plus_local(offset)
	var velocity: Vector3 = request["velocity"]
	var number: int = int(request["wave_number"])
	var raider_name: String = pool.next_name()
	var seed_value: int = hash([raider_name, number])
	var made: Dictionary = BrainFactory.from_behaviour(_tempered(request["behaviour"], raider_name, number), anchor, seed_value)
	if not bool(made["ok"]):
		push_warning("WaveDirector: %s" % made["error"])
		return
	var player_local: Vector3 = player.ship.global_position if player != null and is_instance_valid(player.ship) else Vector3.ZERO
	var at_local: Vector3 = world.universe_to_local(at)
	# Nose along its drift, or toward the player when it starts at rest.
	var heading: Vector3 = velocity if velocity.length() > 1.0 else (player_local - at_local)
	var basis: Basis = ScenarioLoader.basis_facing(heading if heading.length() > 1e-3 else Vector3.FORWARD)
	var brain: PilotBrain = made["brain"]
	if brain is AiPilot and player != null and (brain as AiPilot).context.objective_name.is_empty():
		# The wave is about the player (Q6): a raider with nothing else in sight comes back for it (M3-T10).
		(brain as AiPilot).context.objective_name = player.display_name
	var placed: Combatant = pool.acquire(raider_name, at, basis, velocity, brain, StringName(request["type"]))
	if placed != null and wings != null and not String(request.get("wing", "")).is_empty():
		wings.join(String(request["wing"]), placed)


# Rolls an AI spawn's skill and aggression inside the wave's ranges (M3-T13), unless the spawn sets them. Seeded per raider
# and wave. Other behaviours come back unchanged.
func _tempered(behaviour: Variant, raider_name: String, number: int) -> Variant:
	if not (behaviour is Dictionary) or str((behaviour as Dictionary).get("type", "")) != "ai":
		return behaviour
	var out: Dictionary = (behaviour as Dictionary).duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([raider_name, number, "temperament"])
	var skill: Vector2 = plan.skill_range(number)
	if skill.x >= 0.0 and not out.has("skill"):
		out["skill"] = rng.randf_range(skill.x, skill.y)
	var aggression: Vector2 = plan.aggression_range(number)
	if aggression.x >= 0.0 and not out.has("aggression"):
		out["aggression"] = rng.randf_range(aggression.x, aggression.y)
	return out


# The anchor's universe position when the wave activated, kept for the whole wave.
func _anchor_for(request: Dictionary) -> UniversePos:
	var number: int = int(request["wave_number"])
	if _anchor_wave != number or _anchor_player == null:
		_anchor_wave = number
		_anchor_origin = UniversePos.new(0.0, 0.0, 0.0, world.origin.system_id)  # where the scenario's props are
		_anchor_player = world.to_universe(player.ship.global_position) if player != null and is_instance_valid(player.ship) else _anchor_origin
	return _anchor_player if StringName(request["anchor"]) == &"player" else _anchor_origin


var _anchor_wave: int = -1


func _clear_field() -> void:
	if pool == null:
		return
	for combatant: Combatant in _raiders_alive():
		pool.release(combatant)
	_anchor_wave = -1
	_anchor_player = null


# --- events and status ------------------------------------------------------------------------------------------------


# The raiders in play: what a wave has to clear. Allied ships share the pool and are none of its business.
func _raiders_alive() -> Array[Combatant]:
	return pool.alive(ShipPool.DEFAULT_TYPE) if pool != null else ([] as Array[Combatant])


func _on_raider_destroyed(combatant: Combatant, info: HitInfo) -> void:
	kills += 1
	credit.credit(combatant.targetable.get_instance_id(), info.shooter_id if info != null else 0)
	kills_changed.emit(kills)
	_after_change()


# A pool ship back in play is somebody new: the player's shots at its last life earn nothing now.
func _on_pool_acquired(combatant: Combatant) -> void:
	credit.forget(combatant.targetable.get_instance_id())


func _on_player_fired(_muzzle_index: int, _at: Vector3) -> void:
	credit.note_shot(player.ship.targeting.selected_id())


func _on_player_destroyed(_info: HitInfo) -> void:
	losses += 1
	_after_change()


func _after_change() -> void:
	if plan.state != _last_state:
		if plan.state == WavePlan.State.ACTIVE:
			wave_started.emit(plan.wave_number, plan.current_name())
		elif plan.state == WavePlan.State.CLEARED:
			wave_cleared.emit(plan.wave_number)
		_last_state = plan.state
	var line: String = status_line()
	if line != _status:
		_status = line
		if status_sink.is_valid():
			status_sink.call(line)


## The HUD's top-centre line for the current state.
func status_line() -> String:
	if not plan.is_running():
		return ""
	var head: String = "WAVE %d  %s" % [plan.wave_number, plan.current_name()]
	match plan.state:
		WavePlan.State.COUNTDOWN:
			return "%s   IN %d" % [head, ceili(plan.countdown_remaining())]
		WavePlan.State.CLEARED:
			return "%s   CLEARED   %s" % [head, _tally()]
	return "%s   RAIDERS %d   %s" % [head, _raiders_alive().size(), _tally()]


# Every raider destroyed, then the player's share: `KILLS 7   YOURS 3   ASSISTS 2`.
func _tally() -> String:
	return "KILLS %d   YOURS %d   ASSISTS %d" % [kills, credit.player_kills, credit.player_assists]


# --- console ---------------------------------------------------------------------------------------------------------


func _cmd_wave(args: Dictionary) -> ConsoleResult:
	if plan.waves.is_empty():
		return ConsoleResult.failure("this scenario (%s) has no waves" % scenario_id)
	var index: int = int(args[&"index"])
	match StringName(args[&"action"]):
		&"start":
			if index > plan.waves.size():
				return ConsoleResult.failure("there are %d scripted waves" % plan.waves.size())
			start(index - 1)
			return ConsoleResult.line("wave %d (%s) starts in %d s" % [plan.wave_number, plan.current_name(), ceili(plan.countdown_remaining())])
		&"next":
			_clear_field()
			plan.skip()
			_after_change()
			return ConsoleResult.line("on to wave %d (%s)" % [plan.wave_number, plan.current_name()] if plan.is_running() else "no more waves")
		&"stop":
			_clear_field()
			stop()
			return ConsoleResult.line("waves stopped")
		&"restart":
			_clear_field()
			plan.restart()
			_after_change()
			return ConsoleResult.line("wave %d restarts" % plan.wave_number)
	return ConsoleResult.failure("unknown action")
