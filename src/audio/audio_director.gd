class_name AudioDirector
extends Node3D
## The game's sound (architecture §15.1 D29, M2-T12). It plays the procedurally generated `sfx_combat` sounds through a pool of
## `VOICES` `AudioStreamPlayer3D`s (when all are busy the oldest voice is stolen), an engine hum per ship, and a few 2D players for
## warnings. Space is audible, as in the show (Q5): shots, hits and explosions play positionally, outside the ship.
##
## Hooks (`connect_combat`, `watch_ship`): cannon fire (`pulse_fire` for the Starfury's side, `raider_fire` for the others),
## hits (`hit_hull`), destruction (`explosion`), the player's hull below 25 % (`warning_beep`, repeating) and a new selection
## (`target_blip`). The engines are heard through `ENGINE_VOICES` pairs of looping voices (`engine_loop` and `thruster_loop`), handed to
## the nearest ships in play within `ENGINE_RANGE_M` of the listener and moved to them every frame (M4-T36, §17.21): a voice
## budget instead of two players on every ship, so 500 ships cost the audio server and the frame no more than a dozen do. Pitch and
## volume follow the thrust levels; a ship that gets a voice starts from idle, as it did when it came into range.
##
## `settings.sfx_volume` (0..1) is the gain of the `SFX` bus (`default_bus_layout.tres`; created at run time if it is missing).
## The Dummy audio driver of a headless run plays silently, and nothing here errors without sound files.
##
## Console: provider `audio` (`sounds`, `voices_active`, `volume`) and `sfx <name>` (play at the player).

const SOUND_DIR: String = "res://assets/generated/sfx_combat"
const SOUND_NAMES: Array[StringName] = [&"pulse_fire", &"raider_fire", &"hit_hull", &"explosion", &"engine_loop", &"thruster_loop", &"warning_beep", &"target_blip"]
const BUS: StringName = &"SFX"
const VOICES: int = 16
const UI_VOICES: int = 4
const ENGINE_RANGE_M: float = 1500.0
## Engine voice pairs (M4-T36): at most this many ships are heard at once, the nearest. A 13th ship at 1.5 km would be at the
## hum's idle gain less its distance, below hearing next to the near ones.
const ENGINE_VOICES: int = 12
## Ships looked at each frame for a voice: every ship, up to this many, else this many in turn (a full round in a few frames).
const ENGINE_SCAN_PER_FRAME: int = 32
const WARNING_HULL: float = 0.25
const WARNING_INTERVAL_S: float = 1.5
## Engine hum: gain (dB) and pitch at idle and at full thrust. The pitch stays low: a rumble, not a whine.
const HUM_DB: Vector2 = Vector2(-30.0, -9.0)
const HUM_PITCH: Vector2 = Vector2(0.8, 1.25)
const HUM_IDLE_LEVEL: float = 0.12
## The heard level moves toward the thrust level at these rates (per second), so the rumble builds and dies away.
const HUM_RISE_PER_S: float = 1.2
const HUM_FALL_PER_S: float = 0.8
## Attitude thrusters: gain (dB) at silence and at full demand, pitch range, and their quicker spool.
const THRUSTER_DB: Vector2 = Vector2(-60.0, -16.0)
const THRUSTER_PITCH: Vector2 = Vector2(0.9, 1.2)
const THRUSTER_RISE_PER_S: float = 4.0
const THRUSTER_FALL_PER_S: float = 2.5

## The ship whose position the console's `sfx` and the distance checks refer to (the player's).
var player: Combatant = null

var _streams: Dictionary = {}  # StringName -> AudioStreamWAV
var _voices: Array[AudioStreamPlayer3D] = []
var _voice_serial: Array[int] = []
var _serial: int = 0
var _ui_voices: Array[AudioStreamPlayer] = []
# The watched ships and, per ship, its heard hum and hiss levels and its voice (-1 for none).
var _engine_ships: Array[Combatant] = []
var _engine_levels := PackedFloat64Array()
var _thruster_levels := PackedFloat64Array()
var _voice_of := PackedInt32Array()
# The engine voice pairs and the ship each serves (-1 for none).
var _hums: Array[AudioStreamPlayer3D] = []
var _hisses: Array[AudioStreamPlayer3D] = []
var _voice_ship := PackedInt32Array()
var _scan_at: int = 0
var _warn_in_s: float = 0.0
var _played: Dictionary = {}  # StringName -> times played (tests and the console)


func _ready() -> void:
	_ensure_bus()
	apply_volume(float(Settings.get_value(&"sfx_volume")))
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
	for i: int in ENGINE_VOICES:
		_hums.append(_engine_voice("EngineHum%d" % i, &"engine_loop", 30.0, HUM_DB.x))
		_hisses.append(_engine_voice("ThrusterHiss%d" % i, &"thruster_loop", 20.0, THRUSTER_DB.x))
		_voice_ship.append(-1)
	for i: int in UI_VOICES:
		var ui := AudioStreamPlayer.new()
		ui.name = "UiVoice%d" % i
		ui.bus = BUS
		add_child(ui)
		_ui_voices.append(ui)
	DebugConsole.registry.register_provider(&"audio", ConsoleVars.new({
		&"sounds": {"get": func() -> PackedStringArray: return sound_names(), "doc": "Sounds loaded"},
		&"voices_active": {"get": voices_active, "doc": "3D voices playing now (at most %d)" % VOICES},
		&"volume": {"get": func() -> float: return float(Settings.get_value(&"sfx_volume")),
				"set": func(value: Variant) -> void: Settings.set_value(&"sfx_volume", clampf(float(value), 0.0, 1.0)),
				"type": TYPE_FLOAT, "min": 0.0, "max": 1.0, "doc": "SFX gain 0..1 (settings.sfx_volume)"},
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
	for voice: AudioStreamPlayer3D in _hums + _hisses:
		voice.stop()
		voice.stream = null


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
	for sound_name: StringName in SOUND_NAMES:
		var path: String = SOUND_DIR.path_join("%s.wav" % sound_name)
		if not ResourceLoader.exists(path):
			push_warning("AudioDirector: %s is missing or not imported (run scripts/gen_assets.sh, then import); no %s" % [path, sound_name])
			continue
		var stream := load(path) as AudioStreamWAV
		if stream != null:
			_streams[sound_name] = stream
	# The loops run over the whole file.
	for loop_name: StringName in [&"engine_loop", &"thruster_loop"]:
		if _streams.has(loop_name):
			var loop: AudioStreamWAV = (_streams[loop_name] as AudioStreamWAV).duplicate() as AudioStreamWAV
			loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
			loop.loop_begin = 0
			loop.loop_end = int(loop.get_length() * float(loop.mix_rate))
			_streams[loop_name] = loop


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


## Gives a ship its gun sounds and its engine hum.
func watch_ship(combatant: Combatant) -> void:
	if combatant == null or combatant.cannon == null:
		return
	var shot: StringName = &"pulse_fire" if combatant.faction == Factions.EARTH_ALLIANCE else &"raider_fire"
	combatant.cannon.projectile_fired.connect(func(_index: int, projectile: Projectile) -> void:
		play(shot, projectile.global_position, -3.0, randf_range(0.96, 1.04)))
	_engine_ships.append(combatant)
	_engine_levels.append(HUM_IDLE_LEVEL)
	_thruster_levels.append(0.0)
	_voice_of.append(-1)


## Ships whose engines can be heard (every watched ship).
func engine_count() -> int:
	return _engine_ships.size()


## The engine hum playing for `ship`, or null when it has no voice (parked, out of range, or beyond the nearest `ENGINE_VOICES`).
func engine_voice_of(ship: Ship) -> AudioStreamPlayer3D:
	var e: int = _engine_index(ship)
	return _hums[_voice_of[e]] if e >= 0 and _voice_of[e] >= 0 else null


## The thruster hiss voice paired with `ship`'s hum, or null.
func thruster_voice_of(ship: Ship) -> AudioStreamPlayer3D:
	var e: int = _engine_index(ship)
	return _hisses[_voice_of[e]] if e >= 0 and _voice_of[e] >= 0 else null


## The heard hum level of `ship` (0..1; the idle floor while it has no voice).
func engine_level_of(ship: Ship) -> float:
	var e: int = _engine_index(ship)
	return _engine_levels[e] if e >= 0 else 0.0


## Engine voices serving a ship now.
func engine_voices_used() -> int:
	var n: int = 0
	for e: int in _voice_ship:
		n += 1 if e >= 0 else 0
	return n


# --- engines and warnings --------------------------------------------------------------------------------------------


func _listener_position() -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null:
		return camera.global_position
	return player.ship.global_position if player != null and is_instance_valid(player.ship) else Vector3.ZERO


# Hands the voices to the nearest audible ships, then plays each served ship's engines at its drawn place.
func _update_engines(delta: float) -> void:
	var listener: Vector3 = _listener_position()
	_scan_engines(listener)
	for v: int in _hums.size():
		var e: int = _voice_ship[v]
		if e < 0:
			continue
		if _audible_distance(e, listener) < 0.0:
			_release_voice(v)  # out of play or range: it restarts cold
			continue
		var ship: Ship = _engine_ships[e].ship
		var output: FlightOutput = ship.get_flight_output()
		var level: float = ramp(_engine_levels[e], engine_level(output), delta, HUM_RISE_PER_S, HUM_FALL_PER_S)
		_engine_levels[e] = level
		var hum: AudioStreamPlayer3D = _hums[v]
		hum.global_position = ship.global_position
		hum.volume_db = lerpf(HUM_DB.x, HUM_DB.y, level)
		hum.pitch_scale = lerpf(HUM_PITCH.x, HUM_PITCH.y, level)
		if not hum.playing and hum.stream != null:
			hum.play()
		var hiss: AudioStreamPlayer3D = _hisses[v]
		var heard: float = ramp(_thruster_levels[e], thruster_level(output), delta, THRUSTER_RISE_PER_S, THRUSTER_FALL_PER_S)
		_thruster_levels[e] = heard
		hiss.global_position = ship.global_position
		hiss.volume_db = lerpf(THRUSTER_DB.x, THRUSTER_DB.y, heard)
		hiss.pitch_scale = lerpf(THRUSTER_PITCH.x, THRUSTER_PITCH.y, heard)
		if heard > 0.001 and not hiss.playing and hiss.stream != null:
			hiss.play()
		elif heard <= 0.001 and hiss.playing:
			hiss.stop()


# Looks at the next ships in turn: an audible one without a voice takes a free voice, or the voice of the farthest served ship
# when it is nearer than that one.
func _scan_engines(listener: Vector3) -> void:
	var n: int = _engine_ships.size()
	if n == 0 or _hums.is_empty():
		return
	for k: int in mini(n, ENGINE_SCAN_PER_FRAME):
		var e: int = _scan_at % n
		_scan_at = (_scan_at + 1) % n
		if _voice_of[e] >= 0:
			continue
		var distance: float = _audible_distance(e, listener)
		if distance < 0.0:
			continue
		var v: int = _voice_ship.find(-1)
		if v < 0:
			v = _farthest_voice(listener)
			if _audible_distance(_voice_ship[v], listener) <= distance:
				continue
			_release_voice(v)
		_voice_ship[v] = e
		_voice_of[e] = v


# The ship's distance from the listener when it can be heard (in play, within range), else -1.
func _audible_distance(e: int, listener: Vector3) -> float:
	var combatant: Combatant = _engine_ships[e]
	if not is_instance_valid(combatant.ship):
		return -1.0
	var ship: Ship = combatant.ship
	if not ship.is_visible_in_tree() or not ship.can_process():
		return -1.0
	var distance: float = ship.global_position.distance_to(listener)
	return distance if distance <= ENGINE_RANGE_M else -1.0


func _farthest_voice(listener: Vector3) -> int:
	var far: int = 0
	var far_m: float = -INF
	for v: int in _voice_ship.size():
		var d: float = _audible_distance(_voice_ship[v], listener)
		if d < 0.0:
			return v  # serving a ship no longer heard: free to take
		if d > far_m:
			far = v
			far_m = d
	return far


# Frees a voice; its ship is heard again from idle when it next gets one.
func _release_voice(v: int) -> void:
	var e: int = _voice_ship[v]
	if e >= 0:
		_voice_of[e] = -1
		_engine_levels[e] = HUM_IDLE_LEVEL
		_thruster_levels[e] = 0.0
	_voice_ship[v] = -1
	_hums[v].stop()
	_hisses[v].stop()


func _engine_index(ship: Ship) -> int:
	for e: int in _engine_ships.size():
		if _engine_ships[e].ship == ship:
			return e
	return -1


func _engine_voice(voice_name: String, sound: StringName, unit_size: float, volume_db: float) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.name = voice_name
	voice.stream = _streams.get(sound)
	voice.bus = BUS
	voice.unit_size = unit_size
	voice.max_distance = ENGINE_RANGE_M
	voice.volume_db = volume_db
	voice.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # placed on its ship every frame
	voice.add_to_group(WorldFrame.SHIFTABLE_GROUP)
	add_child(voice)
	return voice


## `current` moved toward `target` by at most `rise_per_s` (going up) or `fall_per_s` (going down) times `delta`.
static func ramp(current: float, target: float, delta: float, rise_per_s: float, fall_per_s: float) -> float:
	var rate: float = rise_per_s if target > current else fall_per_s
	return move_toward(current, target, rate * maxf(delta, 0.0))


## 0..1 demand on the attitude thrusters (RCS force or torque, whichever is larger); 0 for no output.
static func thruster_level(output: FlightOutput) -> float:
	if output == null:
		return 0.0
	var force: float = maxf(absf(output.rcs_force_level.x), absf(output.rcs_force_level.y))
	var torque: float = maxf(absf(output.rcs_torque_level.x), maxf(absf(output.rcs_torque_level.y), absf(output.rcs_torque_level.z)))
	return clampf(maxf(force, torque), 0.0, 1.0)


## 0..1 thrust level of a flight output: the strongest of the mean main level, the mean retro level and the RCS, over an idle floor.
static func engine_level(output: FlightOutput) -> float:
	if output == null:
		return HUM_IDLE_LEVEL
	var mains: float = _mean(output.main_levels)
	var retros: float = _mean(output.retro_levels)
	return clampf(maxf(HUM_IDLE_LEVEL, maxf(mains, 0.7 * retros)), 0.0, 1.0)


static func _mean(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for v: float in values:
		total += v
	return total / float(values.size())


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
