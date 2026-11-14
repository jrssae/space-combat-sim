class_name BotFleet
extends Node
## The station's maintenance bots (M7-T11, Q11, D78): a handful of ambient drones, each flying a slow loop round a patch of hull
## (`data/station/bot_points.json`: the Cobra arms, the spine, the bow, the drum, the reactor). Bots on the drum ride its pivot,
## so they turn with it; the rest hang from the frame. They never touch the hull (the loops keep their clearance, tested),
## take no hits and are no contacts.
##
## **They go in when fighting starts near them.** Any hit near the station, any shot of its grid, and the grid going weapons free
## (the grid's own latch, edge only) is an alarm for the bots within reach of it (`BotAlert`); each goes on round its loop to
## its hatch, slips into the hull and stays hidden until the quiet has held for 60 s, then comes out. The fleet is the pool:
## hidden bots stay in the tree, not drawn.
##
## Cost (D78): the bots' motion is a few GDScript steps a tick; `tick_us` reads the last tick's cost. At a handful of bots this
## stays in GDScript; a crowd of ambient drones would go native.
##
## Console: provider and command `bots`.

const PROVIDER: StringName = &"bots"
const ACTIONS: Array[StringName] = [&"info", &"hide", &"show", &"goto", &"cargo"]
## `bots goto`: how far from the bot the player is put by default, metres.
const GOTO_M: float = 25.0
## How often the alarms are asked, s (a bot's reaction needs no more).
const POLL_S: float = 0.25
## Spacing of the bots' first start along a loop and of their coming out, so they never move in step.
const START_SPREAD_M: float = 37.0
const EMERGE_SPREAD_S: float = 3.0

var bots: Array[MaintenanceBot] = []
## The cargo ferry's bots (`bots cargo`): between the cargo bay and a freighter, on the frame; none until the scene is loaded.
var ferry_bots: Array[MaintenanceBot] = []
## The cargo scene (the freighter and its ferry), null in a bare fleet.
var cargo: BotCargoScene = null
var alert := BotAlert.new()
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
var _free_seen: int = 0
var _hooked: bool = false
var _frame_parent: Node3D = null
var _mesh: Mesh = null


## Builds the bots for `p_station`'s frame and drum (its visuals must be built). False when there are no loops to fly.
func build(p_station: Station) -> bool:
	station = p_station
	cargo = BotCargoScene.new()
	cargo.name = "Cargo"
	cargo.fleet = self
	cargo.station = p_station
	add_child(cargo)
	return build_on(p_station, p_station.frame_piece, p_station.drum_pivot, BotData.load_file(),
			MeshAssets.for_asset(MaintenanceBot.ASSET_ID))


## Builds the bots from `data` under `frame_parent` and `drum_parent`; alerts are in `p_origin`'s frame. For tests and `build`.
func build_on(p_origin: Node3D, frame_parent: Node3D, drum_parent: Node3D, data: BotData, mesh: Mesh) -> bool:
	name = "Bots"
	origin = p_origin
	_frame_parent = frame_parent
	_mesh = mesh
	if not data.valid:
		push_warning("BotFleet: %s; the station has no maintenance bots" % data.error)
		return false
	if mesh == null:
		push_warning("BotFleet: no %s mesh (run scripts/gen_assets.sh, then import); the bots are not drawn" % MaintenanceBot.ASSET_ID)
	var number: int = 0
	for entry: Dictionary in data.loops:
		var loop: BotLoop = BotLoop.from_points(entry["points"])
		var hatches: Array[Dictionary] = []
		for h: Dictionary in entry["hatches"]:
			hatches.append({"name": h["name"], "s": loop.control_s[h["at"]], "inside": h["inside"]})
		var count: int = int(entry["bots"])
		for k: int in count:
			var motion := BotMotion.new()
			motion.setup(loop, hatches, float(entry["speed_mps"]), entry["up"],
					loop.length_m * float(k) / float(count) + START_SPREAD_M * float(number), EMERGE_SPREAD_S * float(number))
			var bot := MaintenanceBot.new()
			bot.setup("Bot%d" % (number + 1), entry["name"], entry["body"], motion, mesh)
			(drum_parent if entry["body"] == StationHardpoints.DRUM else frame_parent).add_child(bot)
			bots.append(bot)
			number += 1
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
	if _poll_s >= POLL_S:
		_poll_s = 0.0
		_refresh_alarms()
	for i: int in bots.size():
		bots[i].advance(delta, held_in or _alarmed[i] != 0)
	for j: int in ferry_bots.size():
		ferry_bots[j].advance(delta, held_in or _alarmed[bots.size() + j] != 0)
	tick_us = Time.get_ticks_usec() - started
	tick_us_avg += (float(tick_us) - tick_us_avg) * 0.02


## A shot or hit at `point` (World frame) now: the bots near it go in.
func note_combat_at(point: Vector3) -> void:
	alert.note(origin.to_local(point), _now_s)


## Fighting on the station that has no place of its own (the grid going weapons free): every bot goes in.
func note_combat_everywhere() -> void:
	alert.note_everywhere(_now_s)


## The fleet's own clock, s (it counts physics time, so a pause stops it).
func now_s() -> float:
	return _now_s


## Bots hidden now, and bots in each phase, `[patrol, retreat, enter, hidden, exit]`.
func phase_counts() -> PackedInt32Array:
	var counts := PackedInt32Array([0, 0, 0, 0, 0])
	for bot: MaintenanceBot in bots:
		counts[int((bot.motion as BotMotion).phase)] += 1
	return counts


func hidden_count() -> int:
	return phase_counts()[BotMotion.Phase.HIDDEN]


## Ferry bots inside the cargo bay's wall now.
func ferry_hidden_count() -> int:
	var count: int = 0
	for bot: MaintenanceBot in ferry_bots:
		count += 0 if bot.motion.is_visible() else 1
	return count


## Adds a ferry bot flying `motion` (a `BotFerryMotion`) on the frame; the bot.
func add_ferry_bot(motion: BotMover) -> MaintenanceBot:
	var bot := MaintenanceBot.new()
	bot.setup("Ferry%d" % (ferry_bots.size() + 1), "cargo_ferry", StationHardpoints.FRAME, motion, _mesh)
	_frame_parent.add_child(bot)
	ferry_bots.append(bot)
	_resize_alarms()
	return bot


## Takes every ferry bot away.
func clear_ferry() -> void:
	for bot: MaintenanceBot in ferry_bots:
		bot.get_parent().remove_child(bot)
		bot.free()
	ferry_bots.clear()
	_resize_alarms()


func _resize_alarms() -> void:
	_alarmed.resize(bots.size() + ferry_bots.size())


## Asks each bot whether fighting is near it, and watches the grid's latch.
func _refresh_alarms() -> void:
	if station != null and station.grid != null:
		var free: int = station.grid.free_sides().size()
		if free > _free_seen:
			alert.note_everywhere(_now_s)
		_free_seen = free
	for i: int in bots.size() + ferry_bots.size():
		var bot: MaintenanceBot = bots[i] if i < bots.size() else ferry_bots[i - bots.size()]
		var here: Vector3 = origin.to_local(bot.global_position) if bot.is_inside_tree() else Vector3.ZERO
		_alarmed[i] = 1 if alert.is_alarmed(here, _now_s) else 0


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
	note_combat_at(info.point)


func _on_grid_shot(_at: Vector3, mount: TurretMount) -> void:
	note_combat_at(mount.global_position)


func _register_console() -> void:
	DebugConsole.registry.register_provider(PROVIDER, ConsoleVars.new({
		&"count": {"get": func() -> int: return bots.size(), "type": TYPE_INT, "doc": "Maintenance bots flying the station's loops"},
		&"hidden": {"get": func() -> int: return hidden_count(), "type": TYPE_INT, "doc": "Bots inside the hull (fighting nearby, or bots hide)"},
		&"phases": {"get": _phases_text, "doc": "Bots in each phase: patrol, retreat (to a hatch), enter, hidden, exit"},
		&"ferry": {"get": func() -> String: return "%d ferry bots (%d inside the bay's wall)%s" % [ferry_bots.size(), ferry_hidden_count(),
				", %s at its hold point" % BotCargoScene.FREIGHTER_NAME if cargo != null and cargo.freighter != null else ""],
				"doc": "The cargo ferry (bots cargo): its bots, how many are inside the cargo bay's wall, and whether the Saturn 3 is at the hold point"},
		&"held": {"get": func() -> bool: return held_in, "type": TYPE_BOOL, "doc": "bots hide holds them inside until bots show"},
		&"tick_us": {"get": func() -> int: return tick_us, "type": TYPE_INT, "doc": "Wall-clock microseconds of the last physics tick's bot work"},
		&"tick_us_avg": {"get": func() -> float: return tick_us_avg, "type": TYPE_FLOAT, "doc": "Running average of that, microseconds"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(PROVIDER,
			"The station's maintenance bots (M7-T11): info, hide (every bot goes in and stays), show (they come out again), goto <n> [metres] (put the player that far from bot n, looking at it), cargo [n|off|view|bayview] (a Saturn 3 backed in at the cargo bay's hold point and n ferry bots, default 5, shuttling between its pods and the bay; off removes them; view and bayview put the player where the bots can be seen)",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"info"), ConsoleArg.string_optional(&"a"),
					ConsoleArg.float_optional(&"metres", null, 3.0)]), _cmd_bots, self)


func _phases_text() -> String:
	var c: PackedInt32Array = phase_counts()
	return "patrol %d, retreat %d, enter %d, hidden %d, exit %d" % [c[0], c[1], c[2], c[3], c[4]]


func _cmd_bots(args: Dictionary) -> ConsoleResult:
	match StringName(args[&"action"]):
		&"hide":
			held_in = true
			return ConsoleResult.line("bots going in: %s" % _phases_text())
		&"show":
			held_in = false
			alert.clear()
			return ConsoleResult.line("bots coming out once they have been in %.0f s: %s" % [BotMotion.MIN_HIDDEN_S, _phases_text()])
		&"goto":
			var which: String = str(args[&"a"]) if args[&"a"] != null else "1"
			return _goto(int(which) if which.is_valid_int() else 0, float(args[&"metres"]) if args[&"metres"] != null else GOTO_M)
		&"cargo":
			if cargo == null:
				return ConsoleResult.failure("bots cargo: no station in play")
			return cargo.command(str(args[&"a"]) if args[&"a"] != null else "")
	var lines := PackedStringArray()
	for bot: MaintenanceBot in bots + ferry_bots:
		lines.append("%s on %s (%s) %s %.1f m/s at %s" % [bot.name, bot.loop_name, bot.home_body,
				bot.motion.phase_name(), bot.motion.speed_mps, bot.motion.position.round()])
	return ConsoleResult.line("%d bots (%s); %.0f us a tick (average %.0f); %s" % [bots.size(), _phases_text(), float(tick_us),
			tick_us_avg, "; ".join(lines)])


# Puts the player `metres` from bot `n` (1 to the fleet's size), at rest against the station, looking at it: for captures.
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
	return ConsoleResult.line("%.0f m from %s on %s" % [metres, bot.name, bot.loop_name])
