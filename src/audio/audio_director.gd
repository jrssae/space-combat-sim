class_name AudioDirector
extends Node3D
## The game's sound (architecture §15.1 D29, M2-T12). It plays the procedurally generated `sfx_combat` sounds through a pool of
## `VOICES` `AudioStreamPlayer3D`s (when all are busy the oldest voice is stolen), an engine hum per ship, and a few 2D players for
## warnings. Space is audible, as in the show (Q5): shots, hits and explosions play positionally, outside the ship.
##
## Hooks (`connect_combat`, `watch_ship`): a ship's `PulseCannon.projectile_fired` (`pulse_fire` for the Starfury's side,
## `raider_fire` for the others), `HitResolver.hit_resolved` (`hit_hull` at the hit point), the destruction director's
## `raider_destroyed` / `player_destroyed` (`explosion`), the player's hull below 25 % (`warning_beep`, repeating) and a new
## selection (`target_blip`). Each ship gets a looping `engine_loop` child (so it follows the ship and a rebase) that plays while
## the ship is in play and within `ENGINE_RANGE_M` of the listener; its pitch and volume follow the flight output's thrust levels.
##
## `settings.sfx_volume` (0..1) is the gain of the `SFX` bus (`default_bus_layout.tres`; created at run time if it is missing).
## The Dummy audio driver of a headless run plays silently, and nothing here errors without sound files.
##
## Console: provider `audio` (`sounds`, `voices_active`, `volume`) and `sfx <name>` (play at the player).

const SOUND_DIR: String = "res://assets/generated/sfx_combat"
const SOUND_NAMES: Array[StringName] = [&"pulse_fire", &"raider_fire", &"hit_hull", &"explosion", &"engine_loop", &"warning_beep", &"target_blip"]
const BUS: StringName = &"SFX"
const VOICES: int = 16
const UI_VOICES: int = 4
const ENGINE_RANGE_M: float = 1500.0
const WARNING_HULL: float = 0.25
const WARNING_INTERVAL_S: float = 1.5
## Engine hum: gain (dB) and pitch at idle and at full thrust.
const HUM_DB: Vector2 = Vector2(-30.0, -9.0)
const HUM_PITCH: Vector2 = Vector2(0.8, 1.5)
const HUM_IDLE_LEVEL: float = 0.12

## The ship whose position the console's `sfx` and the distance checks refer to (the player's).
var player: Combatant = null

var _streams: Dictionary = {}  # StringName -> AudioStreamWAV
var _voices: Array[AudioStreamPlayer3D] = []
var _voice_serial: Array[int] = []
var _serial: int = 0
var _ui_voices: Array[AudioStreamPlayer] = []
var _engines: Array[Dictionary] = []  # {combatant, player}
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


func _process(delta: float) -> void:
	_update_engines()
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
	# The engine hum loops over the whole file (the manifest's loop points are 0 to the last sample).
	if _streams.has(&"engine_loop"):
		var loop: AudioStreamWAV = (_streams[&"engine_loop"] as AudioStreamWAV).duplicate() as AudioStreamWAV
		loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loop.loop_begin = 0
		loop.loop_end = int(loop.get_length() * float(loop.mix_rate))
		_streams[&"engine_loop"] = loop


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
		destruction.raider_destroyed.connect(func(c: Combatant, _info: HitInfo) -> void: play(&"explosion", c.ship.global_position, 3.0))
		destruction.player_destroyed.connect(func(_info: HitInfo) -> void: play(&"explosion", player.ship.global_position, 3.0))
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
	if not _streams.has(&"engine_loop"):
		return
	var hum := AudioStreamPlayer3D.new()
	hum.name = "EngineHum"
	hum.stream = _streams[&"engine_loop"]
	hum.bus = BUS
	hum.unit_size = 30.0
	hum.max_distance = ENGINE_RANGE_M
	hum.volume_db = HUM_DB.x
	combatant.ship.add_child(hum)
	_engines.append({"combatant": combatant, "player": hum})


func engine_count() -> int:
	return _engines.size()


# --- engines and warnings --------------------------------------------------------------------------------------------


func _listener_position() -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null:
		return camera.global_position
	return player.ship.global_position if player != null and is_instance_valid(player.ship) else Vector3.ZERO


func _update_engines() -> void:
	var listener: Vector3 = _listener_position()
	for entry: Dictionary in _engines:
		var combatant: Combatant = entry["combatant"]
		var hum: AudioStreamPlayer3D = entry["player"]
		if not is_instance_valid(combatant.ship) or not is_instance_valid(hum):
			continue
		var ship: Ship = combatant.ship
		var live: bool = ship.is_visible_in_tree() and ship.can_process() and ship.global_position.distance_to(listener) <= ENGINE_RANGE_M
		if not live:
			if hum.playing:
				hum.stop()
			continue
		var level: float = engine_level(ship.get_flight_output())
		hum.volume_db = lerpf(HUM_DB.x, HUM_DB.y, level)
		hum.pitch_scale = lerpf(HUM_PITCH.x, HUM_PITCH.y, level)
		if not hum.playing:
			hum.play()


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
