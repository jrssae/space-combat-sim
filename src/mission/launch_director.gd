class_name LaunchDirector
extends Node
## Cobra-bay launches in the game (M7-T08, D76, AC7): the node side of `LaunchSequence`. Each tick it moves the launches on with
## the drum's angle, carries every fighter still on its rack or rail with the drum, swings the doors' leaves, hands each fighter
## over at its release point and, for the player, plays the launch camera's shots and holds the controls.
##
## - **Carried with the drum.** A fighter on the rack or the rail is put each tick where the drum carries it, with the drum's
##   velocity there (and its spin), never as a free body beside a turning door: its body keeps integrating but feels no force
##   (`custom_integrator`), touches nothing (no collision layers) and stays out of the low-attention tier. It is placed in the
##   drum's pose from before Jolt's step, so after the step it stands where the drum's body does, and a rebase moves the two
##   together. At the release it gets its layers back and flies on with the hand-off state.
## - **The player** is first in the wave: the controls stay held until the hand-off; the shots of the `LaunchProfile` play as the
##   fighter enters each step. A or Start (`Main`'s skip) jumps to the hand-off state; under the spine it waits for clear space.
##   Wingmen (the player's wing) take the other racks of the arm, in the wave order, and the second row behind them.
## - **Wing launches** (`launch wing <wing>`): twelve AI Starfuries from the ally pool (topped up when short), named after the
##   wing, launched in two waves.
##
## Console: provider and command `launch`.

## The player's fighter was handed over (its release, or a skip's).
signal player_released
## Every fighter of a launch is away and its doors are shut.
signal launch_finished(wing: String)

const NODE_NAME: StringName = &"LaunchDirector"
## After the drum is turned (`Station.SPIN_PRIORITY`, -50) and before the tier (-12) and the core's sync (-11).
const PRIORITY: int = -45
const PROVIDER: StringName = &"launch"
const WINGS: PackedStringArray = ["alpha", "beta", "delta", "zeta"]
## What a wing launch's Starfuries fly once away.
const WING_PROFILE: String = "ally_starfury"

var main: Main = null
var profile: LaunchProfile = null
## The launches running: each `{seq: LaunchSequence, ships: Dictionary (id -> Combatant), player: String, wing: String}`.
var launches: Array[Dictionary] = []
## The player's last hand-off in the World: `id`, `bay`, `transform`, `velocity`, `angular`, `drum_angle` (the drum's angle it
## was given at), `skipped`.
var last_handoff: Dictionary = {}
## The scenario's start bay (`player.launch_bay`), relaunched on a respawn; empty for none.
var start_bay: String = ""

var _leaves: StationDoorLeaves = null
var _carried: Dictionary = {}  # Ship instance id -> {layer, mask, exempt}
var _prev_angle: float = NAN  # the drum's angle last tick: its body's pose before this tick's step
var _player_step: StringName = &""
var _played: Dictionary = {}  # shot entries already played in the player's current step
var _skip_asked: bool = false
var _shots_cut: bool = false  # the player skipped: no more shots this launch
var _launch_shot: Dictionary = {}  # the player's latest launch: its shots, its skip
## The fill light of the shot playing (a profile's `fill`), lit through the scene's `LightRig` only while its shot is on screen.
var fill: LightEmitter = null
var _fill_shot: CinematicShot = null
var _fill_spec: Dictionary = {}


func _init() -> void:
	name = NODE_NAME
	process_physics_priority = PRIORITY
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _ready() -> void:
	if main != null:
		main.player_respawned.connect(_on_player_respawned)
	var made: Dictionary = LaunchProfile.load_file()
	if bool(made["ok"]):
		profile = made["profile"]
	else:
		push_error("LaunchDirector: %s" % made["error"])
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	_drop_fill()


# The fill follows its actor as drawn, and goes out with its shot.
func _process(_delta: float) -> void:
	if fill == null:
		return
	if main == null or main.camera_rig == null or main.camera_rig.playing_shot() != _fill_shot:
		_drop_fill()
		return
	var pose: Variant = _actor_pose(String(_fill_spec["actor"]))
	if pose != null:
		fill.position = (pose as Transform3D) * (_fill_spec["offset"] as Vector3)


## The station launches come from, or null.
func station() -> Station:
	if main == null or main.far_props == null:
		return null
	var s: Station = main.far_props.station
	return s if s != null and is_instance_valid(s) and s.hardpoints != null else null


## Puts the player on wing `wing`'s rack over door `door` with its wingmen on the arm's other racks, and starts the launch.
## Returns "" or why it cannot.
func launch_player(wing: String, door: int, with_wingmen: bool = true) -> String:
	if main == null or not main.player_alive:
		return "no player to launch"
	if player_launch().size() > 0:
		return "the player is already launching"
	var ships: Array[Combatant] = [main.combatant]
	if with_wingmen:
		var own: Wing = main.wings.player_wing() if main.wings != null else null
		if own != null and own.leader == main.combatant:
			for member: Combatant in own.members():
				if _can_carry(member) and ships.size() < 12:
					ships.append(member)
	var why: String = _start(wing, door, ships, main.combatant.display_name)
	if why.is_empty():
		_player_step = &""
		_played.clear()
		_shots_cut = false
		_skip_asked = false
	return why


## A scenario's `launch_bay` start (`cobra_bay_<wing>_<door>`); "" or why not.
func launch_from_bay(bay_name: String, with_wingmen: bool = true) -> String:
	var s: Station = station()
	if s == null:
		return "no station in this scenario (anchor it on babylon5)"
	var bay: Dictionary = s.hardpoints.bay(bay_name)
	if bay.is_empty():
		return "no launch bay '%s'" % bay_name
	return launch_player(str(bay["wing"]), int(bay["door_number"]), with_wingmen)


## Twelve AI Starfuries launch from wing `wing`'s arm in two waves; "" or why not.
func launch_wing(wing: String) -> String:
	var s: Station = station()
	if s == null:
		return "no station in this scenario"
	if not WINGS.has(wing.to_lower()):
		return "no wing '%s' (%s)" % [wing, ", ".join(WINGS)]
	for launch: Dictionary in launches:
		if launch["wing"] == wing.to_lower():
			return "wing %s is launching already" % wing
	var pool: ShipPool = main.ships
	var short: int = 12 - pool.free_count(ShipPool.ALLY_TYPE)
	if short > 0:
		pool.prepare(ShipPool.ALLY_TYPE, short)  # a console launch may hitch; a mission sizes its pools
	var ships: Array[Combatant] = []
	var prefix: String = wing.to_upper()
	var at: UniversePos = main.world.to_universe(s.global_position)
	for i: int in 12:
		var callsign: String = pool.next_name(prefix, 1)
		var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": WING_PROFILE}, at,
				hash([callsign, main.scenario_seed]))
		var ally: Combatant = pool.acquire(callsign, at, Basis.IDENTITY, main.world.rest_velocity(),
				made["brain"] as PilotBrain if bool(made["ok"]) else null, ShipPool.ALLY_TYPE)
		if ally == null:
			break
		ships.append(ally)
	if ships.is_empty():
		return "no allied Starfury free"
	var why: String = _start(wing, 1, ships, "")
	if not why.is_empty():
		for ally: Combatant in ships:
			pool.release(ally)
	return why


# A scenario that starts in a bay starts there again after a respawn, without the wingmen (they flew on).
func _on_player_respawned() -> void:
	if not start_bay.is_empty():
		var why: String = launch_from_bay(start_bay, false)
		if not why.is_empty():
			push_warning("LaunchDirector: respawn in %s: %s" % [start_bay, why])


## The launch the player is in (not yet handed over), or empty.
func player_launch() -> Dictionary:
	for launch: Dictionary in launches:
		var id: String = launch["player"]
		if not id.is_empty() and (launch["seq"] as LaunchSequence).fighter(id)["phase"] != LaunchSequence.Phase.RELEASED:
			return launch
	return {}


## The player is on a rack or a rail: the controls are held (`Main.controls_locked`).
func locks_controls() -> bool:
	return not player_launch().is_empty()


## The player asked to skip the launch (A or Start during its shots, `launch skip`, a skipped mission step).
func skip() -> void:
	if player_launch().is_empty():
		return
	_skip_asked = true
	_shots_cut = true


## Every launch's state, one line each.
func describe() -> String:
	var lines := PackedStringArray()
	for launch: Dictionary in launches:
		var seq: LaunchSequence = launch["seq"]
		lines.append("wing %s, %.1f s, arm %.1f deg%s: %s" % [launch["wing"], seq.time_s, seq.arm_angle_now(),
				" (under the spine)" if seq.blocked_now() else "", seq.describe()])
	return " | ".join(lines) if not lines.is_empty() else "no launch"


func _physics_process(delta: float) -> void:
	var s: Station = station()
	if s == null:
		_prev_angle = NAN
		return
	var rate: float = s.spin.rate_rad_s if s.spinning else 0.0
	# The drum's body is still at last tick's angle until Jolt steps: carry the fighters from there.
	var angle: float = s.drum_angle - rate * delta if is_nan(_prev_angle) else _prev_angle
	_prev_angle = s.drum_angle
	if launches.is_empty():
		return
	if _leaves == null:
		_leaves = StationDoorLeaves.find(s.drum_piece, s.hardpoints)
	for launch: Dictionary in launches.duplicate():
		_step(launch, s, delta, angle, rate)


func _step(launch: Dictionary, s: Station, delta: float, angle: float, rate: float) -> void:
	var seq: LaunchSequence = launch["seq"]
	var player_id: String = launch["player"]
	if is_same(launch, _launch_shot) and _skip_asked:
		_skip_asked = false
		seq.drum_angle = angle
		seq.spin_rate_rad_s = rate
		seq.skip(player_id)
		if seq.fighter(player_id)["phase"] == LaunchSequence.Phase.RELEASED:
			_hand_over(launch, player_id, s, true)
	for e: Dictionary in seq.advance(delta, angle, rate):
		if e["kind"] == "release":
			_hand_over(launch, String(e["id"]), s, false)
	for f: Dictionary in seq.fighters:
		if f["phase"] != LaunchSequence.Phase.RELEASED:
			_carry(launch, String(f["id"]), s)
	if _leaves != null:
		for i: int in seq.bays.size():
			_leaves.set_open(String(seq.bays[i]["name"]), seq.door_angle_deg(i))
	if is_same(launch, _launch_shot):
		_direct_camera(launch)
	if seq.finished():
		launches.erase(launch)
		launch_finished.emit(String(launch["wing"]))


# Puts a fighter where the drum carries it this tick.
func _carry(launch: Dictionary, id: String, s: Station) -> void:
	var c: Combatant = (launch["ships"] as Dictionary).get(id)
	if not _alive(c):
		if c != null and is_instance_valid(c) and c.ship != null and is_instance_valid(c.ship):
			_free(c.ship)  # lost on the rack: it falls as any wreck does
		return
	var ship: Ship = c.ship
	var key: int = ship.get_instance_id()
	var first: bool = not _carried.has(key)
	if first:
		_carried[key] = {"layer": ship.collision_layer, "mask": ship.collision_mask, "exempt": ship.tier_exempt}
		ship.collision_layer = 0
		ship.collision_mask = 0
		ship.custom_integrator = true  # no thrust or assist moves it while it rides the drum
		ship.tier_exempt = true
	_place(ship, _world_state((launch["seq"] as LaunchSequence).state_of(id, s.drum_origin), s))
	if first:
		ship.reset_physics_interpolation()


# Lets a fighter go at its release point with the hand-off state.
func _hand_over(launch: Dictionary, id: String, s: Station, skipped: bool) -> void:
	var c: Combatant = (launch["ships"] as Dictionary).get(id)
	if not _alive(c):
		return
	var seq: LaunchSequence = launch["seq"]
	var state: Dictionary = _world_state(seq.handoff_of(id, s.drum_origin), s)
	var ship: Ship = c.ship
	_place(ship, state)
	_free(ship)
	if id == launch["player"]:
		last_handoff = state.merged({"id": id, "bay": seq.bays[seq.fighter(id)["bay"]]["name"], "drum_angle": seq.drum_angle,
				"skipped": skipped})
		player_released.emit()


func _place(ship: Ship, state: Dictionary) -> void:
	ship.global_transform = state["transform"]
	ship.linear_velocity = state["velocity"]
	ship.angular_velocity = state["angular"]


func _free(ship: Ship) -> void:
	var key: int = ship.get_instance_id()
	var kept: Dictionary = _carried.get(key, {})
	if kept.is_empty():
		return
	ship.collision_layer = int(kept["layer"])
	ship.collision_mask = int(kept["mask"])
	ship.tier_exempt = bool(kept["exempt"])
	ship.custom_integrator = false
	_carried.erase(key)


# The station frame's state in the World: the station's place and its velocity against the World added.
func _world_state(state: Dictionary, s: Station) -> Dictionary:
	var xform: Transform3D = s.global_transform
	var rest: Vector3 = main.world.rest_velocity() if main != null else Vector3.ZERO
	return {"transform": xform * (state["transform"] as Transform3D), "velocity": xform.basis * (state["velocity"] as Vector3) + rest,
			"angular": xform.basis * (state["angular"] as Vector3)}


func _start(wing: String, door: int, ships: Array[Combatant], player_id: String) -> String:
	var s: Station = station()
	if s == null:
		return "no station in this scenario (anchor it on babylon5)"
	if profile == null:
		return "no launch profile (%s)" % LaunchProfile.DEFAULT_PATH
	for launch: Dictionary in launches:
		if launch["wing"] == wing.to_lower():
			return "wing %s is launching already" % wing
	var ids := PackedStringArray()
	var by_id: Dictionary = {}
	for c: Combatant in ships:
		ids.append(c.display_name)
		by_id[c.display_name] = c
	var rate: float = s.spin.rate_rad_s if s.spinning else 0.0
	var angle: float = s.drum_angle if is_nan(_prev_angle) else _prev_angle
	var seq := LaunchSequence.create(s.hardpoints, wing, ids, profile, door, angle, rate)
	if not seq.valid:
		return seq.error
	var launch: Dictionary = {"seq": seq, "ships": by_id, "player": player_id, "wing": wing.to_lower()}
	launches.append(launch)
	if not player_id.is_empty():
		_launch_shot = launch
	for id: String in ids:
		_carry(launch, id, s)
	return ""


func _can_carry(c: Combatant) -> bool:
	return _alive(c) and not c.ship.is_tier_parked() and not _carried.has(c.ship.get_instance_id())


func _alive(c: Combatant) -> bool:
	return c != null and is_instance_valid(c) and c.ship != null and is_instance_valid(c.ship) and c.damageable != null \
			and c.damageable.is_active() and (not c.is_player or main.player_alive)


# --- the launch camera -------------------------------------------------------------------------------------------------


# Plays each shot of the player's step once its time in the step has come.
func _direct_camera(launch: Dictionary) -> void:
	var seq: LaunchSequence = launch["seq"]
	var id: String = launch["player"]
	var step: StringName = seq.step_of(id)
	if step != _player_step:
		_player_step = step
		_played.clear()
	if _shots_cut or main == null or main.camera_rig == null:
		return
	for i: int in profile.shots.size():
		var entry: Dictionary = profile.shots[i]
		if entry["step"] != step or _played.has(i) or seq.step_time(id) < float(entry["at_s"]) - LaunchSequence.EPS_S:
			continue
		_played[i] = true
		main.camera_rig.play_shot(entry["shot"], _actor_pose, _origin_to_local)
		_light_fill(entry)


# Lights the shot's fill (replacing the last one), or puts the last one out when this shot has none.
func _light_fill(entry: Dictionary) -> void:
	_drop_fill()
	var spec: Dictionary = entry.get("fill", {})
	var rig: LightRig = LightRig.of(self)
	if spec.is_empty() or rig == null:
		return
	fill = LightEmitter.new("launch fill", LightEmitter.PRIORITY_MUZZLE_FLASH, spec["color"], float(spec["energy"]),
			float(spec["range_m"]))
	_fill_shot = entry["shot"]
	_fill_spec = spec
	var pose: Variant = _actor_pose(String(spec["actor"]))
	if pose != null:
		fill.position = (pose as Transform3D) * (spec["offset"] as Vector3)
	rig.add_emitter(fill)


func _drop_fill() -> void:
	if fill == null:
		return
	var rig: LightRig = LightRig.of(self)
	if rig != null:
		rig.remove_emitter(fill)
	fill = null
	_fill_shot = null
	_fill_spec = {}



# The shots' actors: `fighter` (the player's ship as drawn) and `bay` (the player's door as the drum is drawn).
func _actor_pose(actor: String) -> Variant:
	if actor == "fighter" or actor == "player":
		return main.ship.get_global_transform_interpolated() if main != null and main.player_alive else null
	if actor == "bay" and not _launch_shot.is_empty():
		var s: Station = station()
		var seq: LaunchSequence = _launch_shot["seq"]
		var f: Dictionary = seq.fighter(String(_launch_shot["player"]))
		if s == null or f.is_empty():
			return null
		var drum := Transform3D(Basis(Vector3.BACK, s.visual_angle(Engine.get_physics_interpolation_fraction())), s.drum_origin)
		return s.get_global_transform_interpolated() * drum * LaunchSequence.door_frame(seq.bays[f["bay"]])
	return null


func _origin_to_local(offset: PackedFloat64Array) -> Vector3:
	return main.world.universe_to_local(UniversePos.new(offset[0], offset[1], offset[2], main.world.origin.system_id))


# --- console -------------------------------------------------------------------------------------------------------------


func _register_console() -> void:
	DebugConsole.registry.register_provider(PROVIDER, ConsoleVars.new({
		&"active": {"get": func() -> int: return launches.size(), "type": TYPE_INT, "doc": "Launches running (M7-T08)"},
		&"player": {"get": func() -> bool: return locks_controls(), "type": TYPE_BOOL,
				"doc": "The player is on a rack or a rail, controls held until the hand-off"},
		&"fighters": {"get": describe, "doc": "Each launch's fighters: bay, wave, phase (staged, moving, racked, held, dropping, released)"},
		&"held": {"get": _held_text, "doc": "Fighters holding under the spine (their arm in a blocked sector)"},
		&"handoff": {"get": _handoff_text, "doc": "The player's last hand-off: bay, speed against the station, skipped or played"},
		&"start_bay": {"get": func() -> String: return start_bay, "doc": "The scenario's launch bay (player.launch_bay), or empty"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(PROVIDER,
			"Cobra-bay launches (M7-T08): launch <wing> <door> (the player and its wingmen), launch wing <wing> (twelve AI Starfuries in two waves), launch skip, launch status",
			[ConsoleArg.string_optional(&"a", "status"), ConsoleArg.string_optional(&"b")]), _cmd_launch, self)


func _held_text() -> String:
	var names := PackedStringArray()
	for launch: Dictionary in launches:
		for f: Dictionary in (launch["seq"] as LaunchSequence).fighters:
			if f["phase"] == LaunchSequence.Phase.HELD:
				names.append(String(f["id"]))
	return ", ".join(names) if not names.is_empty() else "none"


func _handoff_text() -> String:
	if last_handoff.is_empty():
		return "none"
	var rest: Vector3 = main.world.rest_velocity() if main != null else Vector3.ZERO
	return "%s from %s at %.1f m/s against the station%s" % [last_handoff["id"], last_handoff["bay"],
			((last_handoff["velocity"] as Vector3) - rest).length(), " (skipped)" if bool(last_handoff["skipped"]) else ""]


func _cmd_launch(args: Dictionary) -> ConsoleResult:
	var a: String = str(args[&"a"]).to_lower()
	var b: String = str(args[&"b"]).to_lower() if args[&"b"] != null else ""
	if a == "status":
		return ConsoleResult.line(describe())
	if a == "skip":
		if player_launch().is_empty():
			return ConsoleResult.failure("launch skip: the player is not launching")
		skip()
		return ConsoleResult.line("launch skipped")
	if a == "wing":
		var why_wing: String = launch_wing(b)
		return ConsoleResult.failure("launch wing: %s" % why_wing) if not why_wing.is_empty() \
				else ConsoleResult.line("wing %s launching: twelve Starfuries in two waves" % b)
	if WINGS.has(a) and b.is_valid_int():
		var why: String = launch_player(a, int(b))
		return ConsoleResult.failure("launch: %s" % why) if not why.is_empty() \
				else ConsoleResult.line("launching from cobra_bay_%s_%s" % [a, b])
	return ConsoleResult.failure("launch <alpha|beta|delta|zeta> <1-6>, launch wing <wing>, launch skip, launch status")
