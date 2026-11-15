class_name BotFleet
extends Node
## The station's maintenance bots (M7-T11, M7-T35, Q11, D78): the crew of `BotCrew`, a pool of bots living in the cargo bay (the
## freighters' cargo is the cargo pods' work since M7-T34, `CargoPodFleet`, which heed this fleet's alarm log). The crew patrols
## in peace, one bot an area at a time and irregularly: along the spine, the fins, the drum (riding its turn, so nothing strikes
## them) and out to the jumpgate and along its arm. In a fight it goes out to repair: one bot a damaged section or grid mount, each
## adding health at a fixed rate (`data/station/bot_points.json`).
##
## Crew bots hang from the station's node itself, never from its visuals (the far drawing shrinks those), so they ride rebases and
## drifts and stay true out at the gate; their motion is in the station's frame, with the drum and the gate placed each tick
## (`BotFrames`). They take no hits and are no contacts.
##
## **Fighting near them** (any hit near the station, any shot of its grid, the grid going weapons free) sends peace bots home
## and stops new patrols until the quiet has held (`BotAlert`, T11's habit); a repair bot backs off its spot while hits land close.
## The cargo pods read the same log (`alert`, `now_s`).
##
## Cost (D78): a dozen kinematic bots a tick in GDScript; `tick_us` reads the last tick's cost.
##
## Console: provider and command `bots`.

const PROVIDER: StringName = &"bots"
const ACTIONS: Array[StringName] = [&"info", &"hide", &"show", &"goto", &"cargo", &"send", &"peace", &"battle", &"follow", &"skip"]
## `bots skip`: the most crew time one call runs ahead, s.
const SKIP_MAX_S: float = 1200.0
## `bots goto` and `bots follow`: how far from the bot the player or camera is put by default, metres.
const GOTO_M: float = 25.0
## How often the crew decides and the alarms are asked, s (a bot's reaction needs no more).
const POLL_S: float = 0.25
## `bots battle`: the areas it damages, in turn (sections and mounts on the frame and the drum), and how much by default.
const BATTLE_AREAS: Array[String] = ["L10", "green_zone", "L3", "vanes", "command", "I6", "docking_sphere", "L1", "hub",
		"I2", "spine", "reactor"]
const BATTLE_HP: float = 600.0

var bots: Array[MaintenanceBot] = []
var crew: BotCrew = null
var frames := BotFrames.new()
var alert := BotAlert.new()
## Hits close to a repair bot (the duck's short memory).
var near_hits := BotAlert.new()
## The station (or any node whose frame the alert's points are in).
var origin: Node3D = null
var station: Station = null
## `bots hide`: every bot goes in and stays in until `bots show`.
var held_in: bool = false
## Wall-clock microseconds of the last physics tick's work and a running average, for D78's record.
var tick_us: int = 0
var tick_us_avg: float = 0.0

var _now_s: float = 0.0
var _poll_s: float = 0.0
var _alarmed := PackedByteArray()
var _ducked := PackedByteArray()
var _free_seen: int = 0
var _hooked: bool = false
var _followed: MaintenanceBot = null
## The drum's turn run ahead during `bots skip`, rad (the station's own angle stands still meanwhile).
var _skip_turn: float = 0.0
var _follow_pose: Transform3D = Transform3D.IDENTITY


## Builds the crew for `p_station` (its visuals, grid and sections built). False when the crew's file is broken.
func build(p_station: Station) -> bool:
	station = p_station
	var areas: BotRepairAreas = null
	if p_station.sections != null and p_station.grid != null:
		areas = BotRepairAreas.make(p_station.sections, p_station.grid.health, p_station.hardpoints.grid_mounts)
		areas.repair_section = p_station.repair_section
		areas.repair_mount = p_station.grid.repair_some
	frames.pivot = p_station.drum_origin
	return build_on(p_station, p_station, BotData.load_file(), MeshAssets.for_asset(MaintenanceBot.ASSET_ID), areas)


## Builds the crew from `data` under `crew_parent` (its frame is the station's); alerts are in `p_origin`'s frame and `areas` are
## what the crew repairs (none in a bare fleet). For tests and `build`.
func build_on(p_origin: Node3D, crew_parent: Node3D, data: BotData, mesh: Mesh, areas: BotRepairAreas = null) -> bool:
	name = "Bots"
	origin = p_origin
	if not data.valid:
		push_warning("BotFleet: %s; the station has no maintenance bots" % data.error)
		return false
	if mesh == null:
		push_warning("BotFleet: no %s mesh (run scripts/gen_assets.sh, then import); the bots are not drawn" % MaintenanceBot.ASSET_ID)
	near_hits.radius_m = data.duck_radius_m
	near_hits.quiet_s = data.duck_s
	crew = BotCrew.make(data, frames, areas, data.trunk[0])
	for i: int in crew.motions.size():
		var bot := MaintenanceBot.new()
		bot.setup("Bot%d" % (i + 1), "crew", StationHardpoints.FRAME, crew.motions[i], mesh)
		crew_parent.add_child(bot)
		bots.append(bot)
	_resize_alarms()
	return not bots.is_empty()


func _ready() -> void:
	_register_console()
	_hook_combat()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _physics_process(delta: float) -> void:
	var started: int = Time.get_ticks_usec()
	_now_s += delta
	_poll_s += delta
	_refresh_frames()
	if _poll_s >= POLL_S:
		_poll_s = 0.0
		_refresh_alarms()
		_decide()
	for i: int in bots.size():
		bots[i].advance(delta, false)
	crew.work(delta, _ducked)
	tick_us = Time.get_ticks_usec() - started
	tick_us_avg += (float(tick_us) - tick_us_avg) * 0.02


## A shot or hit at `point` (World frame) now: the bots near it go home or in.
func note_combat_at(point: Vector3) -> void:
	alert.note(origin.to_local(point), _now_s)


## A hit on or near the station at `point` (World frame): fighting, and a repair bot close to it backs off.
func note_hit_at(point: Vector3) -> void:
	var local: Vector3 = origin.to_local(point)
	alert.note(local, _now_s)
	near_hits.note(local, _now_s)


## Fighting on the station that has no place of its own (the grid going weapons free): every bot goes in.
func note_combat_everywhere() -> void:
	alert.note_everywhere(_now_s)


## The fleet's own clock, s (it counts physics time, so a pause stops it).
func now_s() -> float:
	return _now_s


## Crew bots out of the bay now.
func out_count() -> int:
	return crew.out_count() if crew != null else 0


## Crew bots in the bay (all of them while `bots hide` holds).
func hidden_count() -> int:
	return bots.size() - out_count()


func _resize_alarms() -> void:
	_alarmed.resize(bots.size())
	_ducked.resize(bots.size())


# The drum's angle and turn, and where the gate stands, in the station's frame, for this tick's moves.
func _refresh_frames() -> void:
	if station == null:
		return
	frames.drum_angle = fposmod(station.drum_angle + _skip_turn, TAU)
	frames.spin_rate = station.spin.rate_rad_s if station.spinning else 0.0
	var gate: Jumpgate = _gate()
	frames.has_gate = gate != null
	if gate != null:
		frames.gate = station.global_transform.affine_inverse() * gate.global_transform


func _gate() -> Jumpgate:
	if station == null or station.main == null or station.main.gates == null:
		return null
	var gate: Jumpgate = station.main.gates.gate()
	return gate if gate != null and is_instance_valid(gate) and gate.is_inside_tree() else null


func _decide() -> void:
	if held_in:
		for m: BotCrewMotion in crew.motions:
			m.recall()
		return
	var quiet: bool = not alert.is_alarmed(crew.data.trunk[0], _now_s)
	crew.decide(_now_s, _alarmed, quiet)


## Asks each bot whether fighting is near it, and watches the grid's latch.
func _refresh_alarms() -> void:
	if station != null and station.grid != null:
		var free: int = station.grid.free_sides().size()
		if free > _free_seen:
			alert.note_everywhere(_now_s)
		_free_seen = free
	for i: int in bots.size():
		var bot: MaintenanceBot = bots[i]
		var here: Vector3 = origin.to_local(bot.global_position) if bot.is_inside_tree() else Vector3.ZERO
		_alarmed[i] = 1 if alert.is_alarmed(here, _now_s) else 0
		_ducked[i] = 1 if near_hits.is_alarmed(here, _now_s) else 0


# Hits anywhere (the hit resolver's) and the grid's shots are the combat the bots hear.
func _hook_combat() -> void:
	if _hooked or station == null:
		return
	_hooked = true
	if station.main != null:
		var resolver := station.main.get_node_or_null(^"Combat/HitResolver") as HitResolver
		if resolver != null:
			resolver.hit_resolved.connect(_on_hit)
	if station.grid != null:
		for mount: TurretMount in station.grid.mounts:
			mount.shot_fired.connect(_on_grid_shot.bind(mount))


func _on_hit(info: HitInfo) -> void:
	note_hit_at(info.point)


func _on_grid_shot(_at: Vector3, mount: TurretMount) -> void:
	note_combat_at(mount.global_position)


func _register_console() -> void:
	DebugConsole.registry.register_provider(PROVIDER, ConsoleVars.new({
		&"count": {"get": func() -> int: return bots.size(), "type": TYPE_INT, "doc": "Maintenance bots in the crew (the cargo bay's pool)"},
		&"out": {"get": out_count, "type": TYPE_INT, "doc": "Crew bots out of the cargo bay now"},
		&"peace_out": {"get": func() -> int: return crew.peace_out(), "type": TYPE_INT, "doc": "Crew bots out on a peace patrol"},
		&"repair_out": {"get": func() -> int: return crew.repair_out(), "type": TYPE_INT, "doc": "Crew bots out on a repair"},
		&"working": {"get": func() -> int: return crew.working(), "type": TYPE_INT, "doc": "Repair bots at their spot, repairing now"},
		&"repaired_hp": {"get": func() -> float: return crew.repaired_hp, "type": TYPE_FLOAT, "doc": "Health the crew has added so far"},
		&"jobs": {"get": _jobs_text, "doc": "Each crew bot out: its job (peace area or repair area) and what it is doing"},
		&"areas": {"get": _areas_text, "doc": "Peace areas with their bot (or the seconds until the next trip), and the damaged repair areas with theirs"},
		&"hidden": {"get": hidden_count, "type": TYPE_INT, "doc": "Crew bots in the cargo bay"},
		&"held": {"get": func() -> bool: return held_in, "type": TYPE_BOOL, "doc": "bots hide holds them inside until bots show"},
		&"tick_us": {"get": func() -> int: return tick_us, "type": TYPE_INT, "doc": "Wall-clock microseconds of the last physics tick's bot work"},
		&"tick_us_avg": {"get": func() -> float: return tick_us_avg, "type": TYPE_FLOAT, "doc": "Running average of that, microseconds"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(PROVIDER,
			"The station's maintenance bots (M7-T11, M7-T35): info (each bot's job), hide (every bot goes home and stays), show (they go out again), send <area> (a peace patrol now: spine, fins_port, fins_starboard, drum_fore, drum_aft, gate), peace on|off (peace patrols), battle [n] [hp] (damage n of the station's sections and grid mounts, default 6 by 600 hp, and sound the alarm: the crew goes out to repair), follow <n|area|off> [metres] (a camera on bot n, or on the bot of a peace area or a repair area such as spine or L10, sending one to a peace area that has none), skip [seconds] (run the crew that far ahead at once, default 60, for viewing), goto <n> [metres] (put the player that far from bot n), cargo [n|off|view|bayview] (the same as pods cargo: the cargo scene with its cargo pods, M7-T34)",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"info"), ConsoleArg.string_optional(&"a"),
					ConsoleArg.float_optional(&"metres", null, 3.0)]), _cmd_bots, self)


func _jobs_text() -> String:
	var parts := PackedStringArray()
	for i: int in bots.size():
		var m: BotCrewMotion = crew.motions[i]
		if not m.is_docked():
			parts.append("%s %s" % [bots[i].name, m.phase_name()])
	return "%d out (%d patrol, %d repair)%s" % [crew.out_count(), crew.peace_out(), crew.repair_out(),
			(": " + "; ".join(parts)) if not parts.is_empty() else ""]


func _areas_text() -> String:
	var parts := PackedStringArray()
	for a: int in crew.peace_bot.size():
		var label: String = crew.data.peace[a]["name"]
		var bot: int = crew.peace_bot[a]
		parts.append("%s %s" % [label, bots[bot].name if bot >= 0 else "next in %.0f s" % maxf(crew.peace_due_s[a] - _now_s, 0.0)])
	if crew.areas != null:
		for area: int in crew.areas.damaged():
			var h: Vector2 = crew.areas.health_of(area)
			var bot: int = crew.repair_bot[area]
			parts.append("%s %.0f/%.0f %s" % [crew.areas.name_of(area), h.x, h.y, bots[bot].name if bot >= 0 else "waiting"])
	return ", ".join(parts)


func _cmd_bots(args: Dictionary) -> ConsoleResult:
	var a: String = str(args[&"a"]) if args[&"a"] != null else ""
	match StringName(args[&"action"]):
		&"hide":
			held_in = true
			_decide()
			return ConsoleResult.line("bots going home: %s" % _jobs_text())
		&"show":
			held_in = false
			alert.clear()
			return ConsoleResult.line("bots free to go out again")
		&"goto":
			return _goto(int(a) if a.is_valid_int() else 1, float(args[&"metres"]) if args[&"metres"] != null else GOTO_M)
		&"follow":
			return _follow(a, float(args[&"metres"]) if args[&"metres"] != null else GOTO_M)
		&"skip":
			return _skip(float(a) if a.is_valid_float() else 60.0)
		&"send":
			return _send(a)
		&"peace":
			if a != "on" and a != "off":
				return ConsoleResult.failure("bots peace on|off")
			crew.peace_on = a == "on"
			if not crew.peace_on:
				crew.recall_peace()
			return ConsoleResult.line("peace patrols %s" % a)
		&"battle":
			return _battle(int(a) if a.is_valid_int() else 6, float(args[&"metres"]) if args[&"metres"] != null else BATTLE_HP)
		&"cargo":
			if station == null or station.cargo_pods == null or station.cargo_pods.cargo == null:
				return ConsoleResult.failure("bots cargo: no station in play")
			return station.cargo_pods.cargo.command(a)
	var lines := PackedStringArray()
	for i: int in bots.size():
		var m: BotCrewMotion = crew.motions[i]
		lines.append("%s %s %.1f m/s at %s" % [bots[i].name, m.phase_name(), m.speed_mps, m.position.round()])
	return ConsoleResult.line("%d bots, %s; areas: %s; %.0f us a tick (average %.0f); %s" % [bots.size(), _jobs_text(), _areas_text(),
			float(tick_us), tick_us_avg, "; ".join(lines)])


func _send(area_name: String) -> ConsoleResult:
	var names := PackedStringArray()
	for a: int in crew.data.peace.size():
		names.append(String(crew.data.peace[a]["name"]))
		if crew.data.peace[a]["name"] == area_name:
			if crew.send_peace(a, _now_s):
				return ConsoleResult.line("%s sent to %s" % [bots[crew.peace_bot[a]].name, area_name])
			return ConsoleResult.failure("bots send %s: a bot is already on it, no bot is free%s" % [area_name,
					" or there is no jumpgate in the scene" if crew.data.peace[a]["kind"] == "gate" else ""])
	return ConsoleResult.failure("bots send <%s>" % "|".join(names))


# Damages `n` areas of `BATTLE_AREAS` by `hp` (a light mount or an interceptor is knocked out by the default) and sounds the
# alarm, so the crew's battle work can be watched.
func _battle(n: int, hp: float) -> ConsoleResult:
	if station == null or station.sections == null or station.grid == null:
		return ConsoleResult.failure("bots battle: no station in play")
	var hit := PackedStringArray()
	for k: int in mini(maxi(n, 1), BATTLE_AREAS.size()):
		var key: String = BATTLE_AREAS[k]
		var section: int = station.sections.index_of(key)
		if section >= 0:
			station.damage_section(section, hp)
		else:
			var mount: int = station.grid.health.index_of(key)
			if mount < 0:
				continue
			station.grid.damage_mount(mount, hp)
		hit.append(key)
	note_combat_everywhere()
	_decide()
	return ConsoleResult.line("damaged %s by %.0f hp; %s" % [", ".join(hit), hp, _jobs_text()])


# Puts the player `metres` from bot `n` (1 to the crew's size), at rest against the station, looking at it: for captures.
func _goto(n: int, metres: float) -> ConsoleResult:
	if n < 1 or n > bots.size():
		return ConsoleResult.failure("bots goto <1 to %d> [metres]" % bots.size())
	if station == null or station.main == null or not station.main.player_alive:
		return ConsoleResult.failure("bots goto: no player to move")
	var bot: MaintenanceBot = bots[n - 1]
	var look: Vector3 = bot.global_position
	# On the side away from the hull, so the view is clear, a little ahead of the bot's side.
	var out: Vector3 = ((bot.get_parent() as Node3D).global_basis * bot.motion.up).normalized()
	var beside: Vector3 = out.cross(bot.global_basis.z).normalized()
	var at: Vector3 = look + (out * 0.8 + beside * 0.6).normalized() * metres
	var forward: Vector3 = (look - at).normalized()
	var up: Vector3 = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.98 else Vector3.BACK
	station.main.ship.reset_to(Transform3D(Basis.looking_at(forward, up), at))
	var world: WorldFrame = WorldFrame.of(station)
	station.main.ship.linear_velocity = world.rest_velocity() if world != null else Vector3.ZERO
	station.main.ship.angular_velocity = Vector3.ZERO
	return ConsoleResult.line("%.0f m from %s (%s)" % [metres, bot.name, bot.motion.phase_name()])


# A cinematic camera that keeps bot `which` in view from `metres` behind and above it, until `bots follow off`.
func _follow(which: String, metres: float) -> ConsoleResult:
	if station == null or station.main == null or station.main.camera_rig == null:
		return ConsoleResult.failure("bots follow: no camera")
	if which == "off":
		_followed = null
		station.main.camera_rig.stop_shot()
		return ConsoleResult.line("follow camera off")
	var n: int = int(which) if which.is_valid_int() else _bot_of_area(which) + 1
	if n < 1 or n > bots.size():
		return ConsoleResult.failure("bots follow <1 to %d|area|off> [metres]" % bots.size())
	_followed = bots[n - 1]
	_follow_pose = _followed.get_global_transform_interpolated()
	var k: float = metres
	var key: Dictionary = {"position": {"actor": "bot", "offset": [0.45 * k, 0.35 * k, k]},
			"look_at": {"actor": "bot", "offset": [0.0, 0.0, -2.0]}, "fov": 55}
	var made: Dictionary = CinematicShot.from_dict(&"bot_follow", {"keys": [key.merged({"t": 0.0}), key.merged({"t": 36000.0})]})
	if not bool(made["ok"]):
		return ConsoleResult.failure("bots follow: %s" % made["error"])
	station.main.camera_rig.play_shot(made["shot"], _follow_actor, _follow_to_local)
	station.main.letterbox.shown = false
	return ConsoleResult.line("following %s from %.0f m (%s)" % [_followed.name, metres, _followed.motion.phase_name()])


# The bot on peace area or repair area `area_name` (a section's or a mount's name), sending one to a peace area that has none;
# -1 when there is none.
func _bot_of_area(area_name: String) -> int:
	for a: int in crew.data.peace.size():
		if crew.data.peace[a]["name"] == area_name:
			if crew.peace_bot[a] < 0:
				crew.send_peace(a, _now_s)
			return crew.peace_bot[a]
	if crew.areas != null:
		for r: int in crew.areas.count():
			if crew.areas.target(r)["name"] == area_name:
				return crew.repair_bot[r]
	return -1


# Runs the crew `seconds` ahead in one go (the drum turning on with it), so a far patrol or a long repair can be watched now.
func _skip(seconds: float) -> ConsoleResult:
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var omega: float = frames.spin_rate
	for i: int in int(clampf(seconds, 0.0, SKIP_MAX_S) / dt):
		_skip_turn = fposmod(_skip_turn + omega * dt, TAU)
		_physics_process(dt)
	_skip_turn = 0.0
	for bot: MaintenanceBot in bots:
		bot.reset_physics_interpolation()
	return ConsoleResult.line("crew ran %.0f s ahead: %s" % [seconds, _jobs_text()])


func _follow_actor(actor: String) -> Variant:
	if actor != "bot":
		return null
	if _followed != null and is_instance_valid(_followed) and _followed.is_visible_in_tree():
		_follow_pose = _followed.get_global_transform_interpolated()
	return _follow_pose


func _follow_to_local(offset: PackedFloat64Array) -> Vector3:
	var world: WorldFrame = station.main.world
	return world.universe_to_local(UniversePos.new(offset[0], offset[1], offset[2], world.origin.system_id))
