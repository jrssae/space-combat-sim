class_name AudioDirector
extends Node3D
## The game's sound (architecture §15.1 D29, M2-T12). It plays the procedurally generated `sfx_combat` sounds through a pool of
## `VOICES` `AudioStreamPlayer3D`s (when all are busy the oldest voice is stolen), engine voices on the ships, and a few 2D
## players for warnings. Space is audible, as in the show (Q5): shots, hits and explosions play positionally, outside the ship.
##
## Hooks (`connect_combat`, `watch_ship`): cannon fire (`pulse_fire` for the Starfury's side, `raider_fire` for the others),
## hits (`hit_hull`), destruction (`explosion`), the player's hull below 25 % (`warning_beep`, repeating) and a new selection
## (`target_blip`).
##
## Engines (M5-T19, D60): each ship gets a looping `main_burst` voice per pod and the player's ship an `rcs_burst` voice per
## RCS cluster, children of the ship at their nozzles, so they follow it and a rebase. `EngineVoices` decides which sound
## (at most `settings.engine_voice_cap`: the player's first, then the nearest ships in range, re-ranked every
## `ENGINE_REALLOCATE_S`) and shapes each voice's attack and release on the frame's delta; a frame touches only those voices.
##
## The menus' sounds (`sfx_ui`: move, accept, back; M5-T02) load beside these and play through `play_ui`. The front end has an
## `AudioDirector` of its own for them; they keep sounding while the tree is paused, because the pause menu is where they are heard.
##
## `settings.sfx_volume` (0..1) is the gain of the `SFX` bus (`default_bus_layout.tres`; created at run time if it is missing).
## The Dummy audio driver of a headless run plays silently, and nothing here errors without sound files.
##
## Console: provider `audio` (`sounds`, `voices_active`, `volume`, `engine_voices`, `engine_sounding`, `engine_frame_work`) and
## `sfx <name>` (play at the player; a burst plays once).

const SOUND_DIR: String = "res://assets/generated/sfx_combat"
const UI_SOUND_DIR: String = "res://assets/generated/sfx_ui"
const UI_SOUND_NAMES: Array[StringName] = [&"ui_move", &"ui_accept", &"ui_back"]
const SOUND_NAMES: Array[StringName] = [&"pulse_fire", &"raider_fire", &"hit_hull", &"explosion", &"main_burst", &"rcs_burst", &"warning_beep", &"target_blip"]
## The engine bursts, looped for as long as their thrusters fire.
const LOOPS: Array[StringName] = [&"main_burst", &"rcs_burst"]
const BUS: StringName = &"SFX"
const VOICES: int = 16
const UI_VOICES: int = 4
const WARNING_HULL: float = 0.25
const WARNING_INTERVAL_S: float = 1.5
## Gain (dB) of each gun's shot. The M5 guns hold a flat tone, so they play lower than M2's decaying shots (-3 dB) to keep
## the same loudness per shot (K-weighted, M5-T18).
const SHOT_DB: Dictionary[StringName, float] = {&"pulse_fire": -12.0, &"raider_fire": -13.0}
## Engine voices at full level: gain (dB) and distance scale of a pod's burst and an RCS cluster's. Four pods at full thrust
## come out about as loud as a held shot, as the reference's roars sit beside its gun.
const POD_DB: float = -9.0
const RCS_DB: float = -10.0
const POD_UNIT_SIZE: float = 25.0
const RCS_UNIT_SIZE: float = 15.0
## How often the ships heard are re-ranked, s.
const ENGINE_REALLOCATE_S: float = 0.25

## The ship whose position the console's `sfx` and the distance checks refer to (the player's).
var player: Combatant = null

var _streams: Dictionary = {}  # StringName -> AudioStreamWAV
var _voices: Array[AudioStreamPlayer3D] = []
var _voice_serial: Array[int] = []
var _serial: int = 0
var _ui_voices: Array[AudioStreamPlayer] = []
var _warn_in_s: float = 0.0
var _played: Dictionary = {}  # StringName -> times played (tests and the console)
var _loops: Dictionary = {}  # StringName -> a looping copy of the stream
## Engine-voice work of the last frame: voices stepped and applied, and their ships checked and read (tests, console).
var engine_frame_work: int = 0
var _engine := EngineVoices.new()
var _engine_ships: Array[Combatant] = []  # by EngineVoices ship id
var _engine_ids: Dictionary = {}  # Ship instance id -> EngineVoices ship id
var _engine_nodes: Array[AudioStreamPlayer3D] = []  # by voice id
var _engine_node_at_retro := PackedByteArray()  # where each pod node sits now
var _engine_distance_sq := PackedFloat64Array()
var _engine_rerank_in_s: float = 0.0


func _ready() -> void:
	_ensure_bus()
	apply_volume(float(Settings.get_value(&"sfx_volume")))
	_engine.cap = int(Settings.get_value(&"engine_voice_cap"))
	Settings.changed.connect(_on_setting_changed)
	_load_sounds()
	for i: int in VOICES:
		var voice := AudioStreamPlayer3D.new()
		voice.name = "Voice%d" % i
		voice.bus = BUS
		voice.unit_size = 60.0
		voice.max_distance = 6000.0
		voice.add_to_group(WorldFrame.SHIFTABLE_GROUP)
		add_child(voice)
		_voices.append(voice)
		_voice_serial.append(0)
	for i: int in UI_VOICES:
		var ui := AudioStreamPlayer.new()
		ui.name = "UiVoice%d" % i
		ui.process_mode = Node.PROCESS_MODE_ALWAYS
		ui.bus = BUS
		add_child(ui)
		_ui_voices.append(ui)
	DebugConsole.registry.register_provider(&"audio", ConsoleVars.new({
		&"sounds": {"get": func() -> PackedStringArray: return sound_names(), "doc": "Sounds loaded"},
		&"voices_active": {"get": voices_active, "doc": "3D voices playing now (at most %d)" % VOICES},
		&"volume": {"get": func() -> float: return float(Settings.get_value(&"sfx_volume")),
				"set": func(value: Variant) -> void: Settings.set_value(&"sfx_volume", clampf(float(value), 0.0, 1.0)),
				"type": TYPE_FLOAT, "min": 0.0, "max": 1.0, "doc": "SFX gain 0..1 (settings.sfx_volume)"},
		&"engine_voices": {"get": engine_voices_granted, "doc": "Engine voices granted now (at most settings.engine_voice_cap)"},
		&"engine_sounding": {"get": engine_voices_sounding, "doc": "Engine voices playing now"},
		&"engine_frame_work": {"get": func() -> int: return engine_frame_work,
				"doc": "Engine voices and voiced ships touched in the last frame"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"sfx", "Play a sound at the player",
			[ConsoleArg.enum_required(&"name", SOUND_NAMES)] as Array[ConsoleArg]), _cmd_sfx, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	# A voice still sounding at quit would keep its stream alive past the scene ("resources still in use at exit").
	for voice: AudioStreamPlayer3D in _voices:
		voice.stop()
		voice.stream = null
	for ui: AudioStreamPlayer in _ui_voices:
		ui.stop()
		ui.stream = null
	for node: AudioStreamPlayer3D in _engine_nodes:
		if is_instance_valid(node):
			node.stop()
			node.stream = null


func _process(delta: float) -> void:
	_update_engines(delta)
	_update_warning(delta)


# --- sounds and voices ---------------------------------------------------------------------------------------------


## Names of the sounds that loaded.
func sound_names() -> PackedStringArray:
	var out := PackedStringArray()
	for sound_name: StringName in _streams:
		out.append(String(sound_name))
	out.sort()
	return out


func has_sound(sound_name: StringName) -> bool:
	return _streams.has(sound_name)


## How many times `sound_name` has been played (tests).
func times_played(sound_name: StringName) -> int:
	return int(_played.get(sound_name, 0))


## 3D voices playing now.
func voices_active() -> int:
	var n: int = 0
	for voice: AudioStreamPlayer3D in _voices:
		n += 1 if voice.playing else 0
	return n


## Plays `sound_name` at the World-local `at`. With every voice busy the oldest is stolen. Returns the voice, or null when the
## sound is not loaded.
func play(sound_name: StringName, at: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer3D:
	if not _streams.has(sound_name):
		return null
	var index: int = _free_voice()
	var voice: AudioStreamPlayer3D = _voices[index]
	_serial += 1
	_voice_serial[index] = _serial
	voice.stream = _streams[sound_name]
	voice.global_position = at
	voice.reset_physics_interpolation()  # no blend from its last sound or a rebase
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.play()
	_played[sound_name] = times_played(sound_name) + 1
	return voice


## Plays `sound_name` in 2D (warnings, the target blip).
func play_ui(sound_name: StringName, volume_db: float = 0.0) -> AudioStreamPlayer:
	if not _streams.has(sound_name):
		return null
	var ui: AudioStreamPlayer = _ui_voices[0]
	for candidate: AudioStreamPlayer in _ui_voices:
		if not candidate.playing:
			ui = candidate
			break
	ui.stream = _streams[sound_name]
	ui.volume_db = volume_db
	ui.play()
	_played[sound_name] = times_played(sound_name) + 1
	return ui


# The first idle voice, else the one started longest ago.
func _free_voice() -> int:
	var oldest: int = 0
	for i: int in _voices.size():
		if not _voices[i].playing:
			return i
		if _voice_serial[i] < _voice_serial[oldest]:
			oldest = i
	return oldest


func _load_sounds() -> void:
	_load_set(SOUND_DIR, SOUND_NAMES)
	_load_set(UI_SOUND_DIR, UI_SOUND_NAMES)
	# The engine voices loop the whole file; `play` keeps the plain stream, so a burst played by name ends.
	for loop_name: StringName in LOOPS:
		if _streams.has(loop_name):
			var loop: AudioStreamWAV = (_streams[loop_name] as AudioStreamWAV).duplicate() as AudioStreamWAV
			loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
			loop.loop_begin = 0
			loop.loop_end = int(loop.get_length() * float(loop.mix_rate))
			loop.resource_name = String(loop_name)
			_loops[loop_name] = loop


func _load_set(dir: String, names: Array[StringName]) -> void:
	for sound_name: StringName in names:
		var path: String = dir.path_join("%s.wav" % sound_name)
		if not ResourceLoader.exists(path):
			push_warning("AudioDirector: %s is missing or not imported (run scripts/gen_assets.sh, then import); no %s" % [path, sound_name])
			continue
		var stream := load(path) as AudioStreamWAV
		if stream != null:
			_streams[sound_name] = stream


# --- volume ----------------------------------------------------------------------------------------------------------


## Sets the SFX bus gain from a 0..1 value.
func apply_volume(linear: float) -> void:
	var index: int = AudioServer.get_bus_index(BUS)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(clampf(linear, 0.0, 1.0)) if linear > 0.0 else -80.0)


func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) >= 0:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, BUS)
	AudioServer.set_bus_send(index, &"Master")


func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key == &"sfx_volume":
		apply_volume(float(value))
	elif key == &"engine_voice_cap":
		_engine.cap = int(value)
		_engine_rerank_in_s = 0.0


# --- hooks -------------------------------------------------------------------------------------------------------------


## Wires the combat events: hits, explosions, the player's warnings and target blip.
func connect_combat(resolver: HitResolver, destruction: DestructionDirector, p_player: Combatant) -> void:
	player = p_player
	if resolver != null:
		resolver.hit_resolved.connect(func(info: HitInfo) -> void: play(&"hit_hull", info.point, -4.0, randf_range(0.92, 1.08)))
	if destruction != null:
		destruction.ship_destroyed.connect(func(_c: Combatant, _info: HitInfo) -> void: play(&"explosion", destruction.last_blast_position, 3.0))
		destruction.buoy_destroyed.connect(func(buoy: NavBuoy, _info: HitInfo) -> void: play(&"explosion", buoy.global_position, 0.0, 1.15))
		destruction.player_destroyed.connect(func(_info: HitInfo) -> void: play(&"explosion", destruction.last_blast_position, 3.0))
	if player != null:
		player.ship.targeting.target_changed.connect(func(id: int) -> void:
			if id != TargetingSystem.NO_TARGET:
				play_ui(&"target_blip", -6.0))


## Gives a ship its gun sounds and its engine voices.
func watch_ship(combatant: Combatant) -> void:
	if combatant == null or combatant.cannon == null:
		return
	var shot: StringName = &"pulse_fire" if combatant.faction == Factions.EARTH_ALLIANCE else &"raider_fire"
	var shot_db: float = SHOT_DB[shot]
	combatant.cannon.projectile_fired.connect(func(_index: int, projectile: Projectile) -> void:
		play(shot, projectile.global_position, shot_db, randf_range(0.96, 1.04)))
	_add_engine_voices(combatant)


## Engine voices granted now.
func engine_voices_granted() -> int:
	return _engine.active.size()


## Engine voices playing now.
func engine_voices_sounding() -> int:
	var n: int = 0
	for v: int in _engine.active:
		n += 1 if _engine_nodes[v].playing else 0
	return n


## Engine voices granted to `ship` now (tests).
func engine_voices_of(ship: Ship) -> int:
	var id: int = int(_engine_ids.get(ship.get_instance_id(), -1))
	var n: int = 0
	for v: int in _engine.active:
		n += 1 if _engine.voice_ship[v] == id else 0
	return n


## Ships with engine voices.
func engine_ship_count() -> int:
	return _engine.ship_count()


## Work of the last re-rank: one per ship.
func engine_allocate_work() -> int:
	return _engine.allocate_work


## Re-ranks which ships are heard: the player's first, then the nearest in range. Runs every `ENGINE_REALLOCATE_S` by itself.
func reallocate_engines() -> void:
	_engine_rerank_in_s = ENGINE_REALLOCATE_S
	var listener: Vector3 = _listener_position()
	_engine_distance_sq.resize(_engine_ships.size())
	for id: int in _engine_ships.size():
		var combatant: Combatant = _engine_ships[id]
		_engine_distance_sq[id] = combatant.ship.global_position.distance_squared_to(listener) if _in_play(combatant) else -1.0
	_engine.allocate(_engine_distance_sq)
	for v: int in _engine.revoked:
		var node: AudioStreamPlayer3D = _engine_nodes[v]
		if is_instance_valid(node) and node.playing:
			node.stop()


# --- engines and warnings --------------------------------------------------------------------------------------------


# Builds a ship's voice nodes at its nozzles, from the voices `EngineVoices` made for its layout.
func _add_engine_voices(combatant: Combatant) -> void:
	var layout: ThrusterLayout = combatant.ship.get_layout()
	if not _loops.has(&"main_burst") or layout == null or not layout.valid or _engine_ids.has(combatant.ship.get_instance_id()):
		return
	var id: int = _engine.add_ship(layout, combatant == player)
	_engine_ships.append(combatant)
	_engine_ids[combatant.ship.get_instance_id()] = id
	var pods: int = 0
	var clusters: int = 0
	for v: int in _engine.voices_of(id):
		var is_pod: bool = _engine.voice_kind[v] == EngineVoices.Kind.POD
		var node := AudioStreamPlayer3D.new()
		node.name = ("EnginePod%d" % pods) if is_pod else ("EngineRcs%d" % clusters)
		pods += 1 if is_pod else 0
		clusters += 0 if is_pod else 1
		node.stream = _loops.get(&"main_burst" if is_pod else &"rcs_burst")
		node.bus = BUS
		node.unit_size = POD_UNIT_SIZE if is_pod else RCS_UNIT_SIZE
		node.max_distance = EngineVoices.AUDIBLE_RANGE_M
		node.position = _engine.voice_position[v]
		combatant.ship.add_child(node)
		_engine_nodes.append(node)
		_engine_node_at_retro.append(0)
	_engine_rerank_in_s = 0.0


func _listener_position() -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null:
		return camera.global_position
	return player.ship.global_position if player != null and is_instance_valid(player.ship) else Vector3.ZERO


static func _in_play(combatant: Combatant) -> bool:
	return is_instance_valid(combatant.ship) and combatant.ship.is_visible_in_tree() and combatant.ship.can_process()


# Moves the granted engine voices on by a frame: linear in voices, whatever the number of ships.
func _update_engines(delta: float) -> void:
	var work: int = 0
	var all_in_play: bool = true
	for id: int in _engine.voiced_ships:
		work += 1
		all_in_play = all_in_play and _in_play(_engine_ships[id])
	_engine_rerank_in_s -= delta
	if _engine_rerank_in_s <= 0.0 or not all_in_play:
		reallocate_engines()  # a ship that left play is dropped at once
	for id: int in _engine.voiced_ships:
		work += 1
		_engine.set_output(id, _engine_ships[id].ship.get_flight_output())
	_engine.step(delta)
	work += _engine.step_work
	for v: int in _engine.active:
		work += 1
		_apply_engine_voice(v)
	engine_frame_work = work


# Gives a voice's node its level (and a jet its brightness, a pod its nozzle), starting or stopping it on the way.
func _apply_engine_voice(v: int) -> void:
	var node: AudioStreamPlayer3D = _engine_nodes[v]
	var level: float = _engine.level[v]
	if level <= 0.0:
		if node.playing:
			node.stop()
		return
	if _engine.voice_kind[v] == EngineVoices.Kind.POD:
		node.volume_db = POD_DB + linear_to_db(level)
		if _engine.at_retro[v] != _engine_node_at_retro[v]:
			_engine_node_at_retro[v] = _engine.at_retro[v]
			node.position = _engine.voice_retro_position[v] if _engine.at_retro[v] == 1 else _engine.voice_position[v]
			node.reset_physics_interpolation()
	else:
		node.volume_db = RCS_DB + linear_to_db(level)
		node.pitch_scale = EngineVoices.rcs_pitch(level)
	if not node.playing and node.stream != null:
		node.play(EngineVoices.start_offset(v, node.stream.get_length()))


func _update_warning(delta: float) -> void:
	if player == null or not is_instance_valid(player.ship):
		return
	var fraction: float = player.damageable.hull.fraction()
	if fraction >= WARNING_HULL or player.damageable.hull.destroyed:
		_warn_in_s = 0.0
		return
	_warn_in_s -= delta
	if _warn_in_s <= 0.0:
		_warn_in_s = WARNING_INTERVAL_S
		play_ui(&"warning_beep", -3.0)


# --- console ---------------------------------------------------------------------------------------------------------


func _cmd_sfx(args: Dictionary) -> ConsoleResult:
	var sound_name: StringName = StringName(args[&"name"])
	if not has_sound(sound_name):
		return ConsoleResult.failure("%s is not loaded (run scripts/gen_assets.sh, then import)" % sound_name)
	var at: Vector3 = player.ship.global_position if player != null and is_instance_valid(player.ship) else Vector3.ZERO
	play(sound_name, at)
	return ConsoleResult.line("playing %s" % sound_name)
