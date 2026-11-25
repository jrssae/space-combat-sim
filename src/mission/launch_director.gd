class_name LaunchDirector
extends Node
## Cobra-bay launches in the game (M7-T08, D76, AC7): the node side of `LaunchSequence`. Each tick it moves the launches on with
## the drum's angle, carries every fighter still on its rack or rail with the drum, slides the doors' leaves, hands each fighter
## over at its release point and, for the player, plays the launch camera's shots and holds the controls.
##
## - **Carried with the drum.** A fighter on the rack or the rail is put each tick where the drum carries it, with the drum's
##   velocity there (and its spin), never as a free body beside a turning door: its body keeps integrating but feels no force
##   (`custom_integrator`), touches nothing (no collision layers) and stays out of the low-attention tier. It is placed in the
##   drum's pose from before Jolt's step, so after the step it stands where the drum's body does, and a rebase moves the two
##   together. At the release it gets its layers back and flies on with the hand-off state.
## - **The player** is first in the wave: the controls stay held until the hand-off. Each launch gets its own camera cut, one variant
##   per phase from the profile's pools (`LaunchCut`, seeded by the scenario's seed, the bay and the run's launch count, or
##   `cut_seed` when pinned), each played as the fighter has been long enough in its step. A or Start (`Main`'s skip) jumps to the hand-off state; under the spine it waits for clear space.
##   After a played hand-off its engines light for `burn_s` (`step_player`, as the gate jump's autopilot), so it clears the arm
##   under thrust; a skip leaves the controls to the player at once.
##   Wingmen (the player's wing) take the other racks of the arm, in the wave order, and the second row behind them.
## - **Wing launches** (`launch wing <wing>`, `launch wing all`): twelve AI Starfuries from the ally pool (topped up when short),
##   named after the wing, launched in two waves. A wing the player leads (Alpha, with the player as Alpha 1) takes the launched
##   ships as its own wingmen, as many as its eleven slots have room for, so they answer the player's orders (M7-T58).
##   Flights (M8-T19, D85): a wing nobody but the station commands flies as flights of three (`WingDirector.next_flight_place`:
##   BETA 1 leads 2 and 3, BETA 4 leads 5 and 6, ...), and so does the rest of a wing the player leads when the scenario gives
##   the player only its own flight (`wings[].flight`): two of the launched ships fill it, the others fly in flights from 2 on.
##
## - **The squadron launch** (`launch squadron`, `MissionApi.launch_squadron`; M8-T03, D81): a `SquadronLaunch` cinematic: the
##   squadron's flights launch, flip and form up filmed from outside, then the player launches alone with the exterior shots
##   (`exterior_cut`, also the relaunch after a repair, M8-T06); a skip lands in the end state.
##
## Console: provider and command `launch`.

## The player's fighter was handed over (its release, or a skip's).
signal player_released
## Every fighter of a launch is away and its doors are shut.
signal launch_finished(wing: String)
## The squadron-launch cinematic ended: the player was handed over and the squadron let go on its slots.
signal squadron_finished

const NODE_NAME: StringName = &"LaunchDirector"
## After the drum is turned (`Station.SPIN_PRIORITY`, -50) and before the tier (-12) and the core's sync (-11).
const PRIORITY: int = -45
const PROVIDER: StringName = &"launch"
const WINGS: PackedStringArray = ["alpha", "beta", "delta", "zeta"]
## Starfuries in a full wing launch.
const WING_SIZE: int = 12
## What a wing launch's Starfuries fly once away.
const WING_PROFILE: String = "ally_starfury"
const EXTERIOR_PATH: String = "res://data/launch/exterior_launch.json"

var main: Main = null
var profile: LaunchProfile = null
## The launches running: each `{seq: LaunchSequence, ships: Dictionary (id -> Combatant), player: String, wing: String}`.
var launches: Array[Dictionary] = []
## The player's last hand-off in the World: `id`, `bay`, `transform`, `velocity`, `angular`, `drum_angle` (the drum's angle it
## was given at), `skipped`.
var last_handoff: Dictionary = {}
## The scenario's start bay (`player.launch_bay`), relaunched on a respawn; empty for none.
var start_bay: String = ""

## Each wing launched (its name, lower case) -> the Starfuries it sent as `{combatant, name}`, so the station knows which wing is
## still out and how strong it is (`wing_strength`).
var _wing_ships: Dictionary = {}

var _leaves: StationDoorLeaves = null
var _carried: Dictionary = {}  # Ship instance id -> {layer, mask, exempt}
var _prev_angle: float = NAN  # the drum's angle last tick: its body's pose before this tick's step
var _step_starts: Dictionary = {}  # each step the player's fighter has been in -> when it began (launch time)
## When the player's launch cuts: the least hold, and a row shot held over several ejections (`LaunchShotSequencer`).
var sequencer: LaunchShotSequencer = null
var _skip_asked: bool = false
var _shots_cut: bool = false  # the player skipped: no more shots this launch
var _launch_shot: Dictionary = {}  # the player's latest launch: its shots, its skip
var _burn_left_s: float = 0.0  # the player's engines after the hand-off
## The shuffle bags of this scenario run's cuts, and how many player launches it has had.
var cut: LaunchCut = null
var launch_count: int = 0
## Pins every cut's seed (tests, `launch seed <n>`); -1 seeds each launch from the scenario, the bay and the launch count.
var cut_seed: int = -1
## The fill light of the shot playing (a profile's `fill`), lit through the scene's `LightRig` only while its shot is on screen.
var fill: LightEmitter = null
var _fill_shot: CinematicShot = null
var _fill_spec: Dictionary = {}
var _fill_id: String = ""
## The shot this director put on screen last (null none): `cut_shots` stops only its own.
var _playing: CinematicShot = null
## A variant pinned for the review sheets (`launch force`, M8-T30): the next launch plays it in its phase and holds it to its end.
var review_variant: StringName = &""
var _review_holding: bool = false
## The `bay_fixed` actor: the followed fighter's door in the station's frame as the shot began, so a camera stays put in space
## while the drum turns on (M8-T30).
var _fixed_bay: Transform3D = Transform3D.IDENTITY
## The shot on screen ends early once its fighter reaches this step (a variant's `until`), and that fighter.
var _playing_until: StringName = &""
var _playing_subject: String = ""
## The shared key light on the subject of the launch shot playing (M8-T30: the show kept a hard key light on its fighters).
var _key_light: CinematicKeyLight = CinematicKeyLight.new()
## The player's launch filmed from outside (the squadron launch's last, a relaunch after a repair): its profile and shuffle bags.
var exterior_profile: LaunchProfile = null
var exterior_cut: LaunchCut = null
## The squadron-launch cinematic's settings (`SquadronLaunch.load_settings`), its shuffle bags, and the last one run (null none).
var squadron_settings: Dictionary = {}
var squadron_cut: LaunchCut = null
var squadron: SquadronLaunch = null


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
		cut = LaunchCut.new(profile)
	else:
		push_error("LaunchDirector: %s" % made["error"])
	var outside: Dictionary = LaunchProfile.load_file(EXTERIOR_PATH)
	if bool(outside["ok"]):
		exterior_profile = outside["profile"]
		exterior_cut = LaunchCut.new(exterior_profile)
	else:
		push_error("LaunchDirector: %s" % outside["error"])
	squadron_settings = SquadronLaunch.load_settings()
	if bool(squadron_settings["ok"]):
		squadron_cut = LaunchCut.new(squadron_settings["profile"])
	else:
		push_error("LaunchDirector: %s" % squadron_settings["error"])
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	_drop_fill()
	_key_light.detach()


# The fill follows its actor as drawn, and goes out with its shot.
func _process(_delta: float) -> void:
	_light_subject()
	if fill == null:
		return
	if main == null or main.camera_rig == null or main.camera_rig.playing_shot() != _fill_shot:
		_drop_fill()
		return
	var pose: Variant = _actor_pose_of(String(_fill_spec["actor"]), _fill_id)
	if pose != null:
		fill.position = (pose as Transform3D) * (_fill_spec["offset"] as Vector3)


## The station launches come from, or null.
func station() -> Station:
	if main == null or main.far_props == null:
		return null
	var s: Station = main.far_props.station
	return s if s != null and is_instance_valid(s) and s.hardpoints != null else null


## Puts the player on wing `wing`'s rack over door `door` with its wingmen on the arm's other racks, and starts the launch;
## `exterior` films it from outside the station (`exterior_cut`). Returns "" or why it cannot.
func launch_player(wing: String, door: int, with_wingmen: bool = true, exterior: bool = false) -> String:
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
	var seed_value: int = cut_seed if cut_seed >= 0 else hash([main.scenario_seed, wing.to_lower(), door, launch_count])
	var why: String = _start(wing, door, ships, main.combatant.display_name, seed_value)
	if why.is_empty():
		launch_count += 1
		var outside: bool = exterior and exterior_cut != null
		_film(_launch_shot, exterior_cut if outside else cut, seed_value, ships.size())
		_launch_shot["exterior"] = outside
	return why


# Gives a launch about to be filmed its camera cut from `bag` and resets the cutting.
func _film(launch: Dictionary, bag: LaunchCut, seed_value: int, size: int) -> void:
	_launch_shot = launch
	launch["cut"] = bag.pick(seed_value, mini(size, (launch["seq"] as LaunchSequence).bays.size()))
	launch["pool"] = bag.profile
	launch["used"] = {}
	launch["cut_seed"] = seed_value
	_step_starts.clear()
	sequencer = LaunchShotSequencer.new(bag.profile)
	_shots_cut = false
	_skip_asked = false


## The squadron-launch cinematic (M8-T03, D81) from wing `wing`'s arm (empty: the player's wing, else alpha): `flights` flights
## of three (0: the data's), the player's own included, then the player alone from door `door` (0: the data's). Returns "" or
## why not.
func launch_squadron(wing: String = "", door: int = 0, flights: int = 0) -> String:
	if not bool(squadron_settings.get("ok", false)):
		return "no squadron launch data (%s)" % SquadronLaunch.DEFAULT_PATH
	if main == null or not main.player_alive:
		return "no player to launch"
	if squadron != null and squadron.running():
		return "the squadron launch is running"
	if not player_launch().is_empty():
		return "the player is already launching"
	var s: Station = station()
	if s == null:
		return "no station in this scenario (anchor it on babylon5)"
	if not s.has_power():
		return "%s has no power" % Station.DISPLAY_NAME  # a hulk or a wreck launches nothing (M10-T65)
	var own: Wing = main.wings.player_wing() if main.wings != null else null
	if own != null and (own.leader != main.combatant):
		own = null
	if wing.is_empty():
		wing = own.name.to_lower() if own != null and WINGS.has(own.name.to_lower()) else "alpha"
	door = door if door > 0 else int(squadron_settings["player_door"])
	flights = clampi(flights if flights > 0 else int(squadron_settings["flights"]), 1, 4)
	var extra: Array[Combatant] = []
	if own != null:
		for member: Combatant in own.members():
			if _can_carry(member):
				extra.append(member)
	var count: int = mini(3 * (flights - 1), WING_SIZE - extra.size())
	if count <= 0 and extra.is_empty():
		return "a squadron of one flight with no wingmen: launch the player alone (launch <wing> <door>)"
	main.world.return_home()  # the player's launch is the last of it: the station's rail first (M7-T71)
	var why: String = launch_wing(wing, count, extra, true) if count > 0 \
			else _start(wing, 1, extra, "", hash([main.scenario_seed, wing, "squadron"]))
	if not why.is_empty():
		return why
	var launch: Dictionary = launches[-1]
	launch["squadron"] = true
	squadron = SquadronLaunch.new(self, wing, door, squadron_settings)
	squadron.begin(launch, s)
	var seed_value: int = cut_seed if cut_seed >= 0 else hash([main.scenario_seed, wing, "squadron", launch_count])
	_film(launch, squadron_cut, seed_value, (launch["ships"] as Dictionary).size())
	return ""


## A scenario's `launch_bay` start (`cobra_bay_<wing>_<door>`); "" or why not.
func launch_from_bay(bay_name: String, with_wingmen: bool = true) -> String:
	var s: Station = station()
	if s == null:
		return "no station in this scenario (anchor it on babylon5)"
	if not s.has_power():
		return "%s has no power" % Station.DISPLAY_NAME  # a hulk or a wreck launches nothing (M10-T65)
	var bay: Dictionary = s.hardpoints.bay(bay_name)
	if bay.is_empty():
		return "no launch bay '%s'" % bay_name
	return launch_player(str(bay["wing"]), int(bay["door_number"]), with_wingmen)


## Whether wing `wing` was launched in this run (it may be gone since).
func has_flown(wing: String) -> bool:
	return _wing_ships.has(wing.to_lower())


## Whether a launch of wing `wing` is running now.
func is_launching(wing: String) -> bool:
	for launch: Dictionary in launches:
		if launch["wing"] == wing.to_lower():
			return true
	return false


## How many of wing `wing`'s launched Starfuries still fly for it: in play, not shot down and not handed to someone else.
func wing_strength(wing: String) -> int:
	var n: int = 0
	var in_play: Array[Combatant] = main.ships.alive(ShipPool.ALLY_TYPE)
	for entry: Dictionary in _wing_ships.get(wing.to_lower(), []):
		var c: Combatant = entry["combatant"]
		if is_instance_valid(c) and is_instance_valid(c.ship) and c.display_name == entry["name"] and in_play.has(c) \
				and WingDirector.is_in_play(c):
			n += 1
	return n


## `count` AI Starfuries (a full wing of twelve by default) launch from wing `wing`'s arm in two waves; "" or why not. `extra`
## ships in play go first in the same launch, and `as_flights` keeps the player's wing as it is: the new ships fill only its empty
## slots and fly in flights from 2 on (the squadron launch, M8-T03).
func launch_wing(wing: String, count: int = WING_SIZE, extra: Array[Combatant] = [], as_flights: bool = false) -> String:
	var s: Station = station()
	if s == null:
		return "no station in this scenario"
	if not s.has_power():
		return "%s has no power" % Station.DISPLAY_NAME  # a hulk or a wreck launches nothing (M10-T65)
	if not WINGS.has(wing.to_lower()):
		return "no wing '%s' (%s)" % [wing, ", ".join(WINGS)]
	for launch: Dictionary in launches:
		if launch["wing"] == wing.to_lower():
			return "wing %s is launching already" % wing
	var pool: ShipPool = main.ships
	count = clampi(count, 1, WING_SIZE)
	var prefix: String = wing.to_upper()
	var led: Wing = _player_led_wing(prefix)
	# The player commands only its own flight (M8-T19): its two slots take the first ships, the rest fly in flights from 2 on.
	var own_flight: bool = led != null and (led.flight > 0 or as_flights)
	var size_before: int = led.size if led != null else 0
	var slots := PackedInt32Array()
	if led != null:
		main.wings.refresh(led)  # a wingman down a moment ago frees its slot
		if not own_flight:
			led.resize(maxi(led.size, WING_SIZE - 1))  # the player flies number 1, the rest of the wing the other eleven
		slots = led.fill_order()  # the arms stay even if fewer launch
	if led == null or own_flight:
		count = mini(count, WING_SIZE - (main.wings.flight_strength(prefix) if main.wings != null else 0))
	else:
		count = mini(count, slots.size())
	count = mini(count, WING_SIZE - extra.size())
	if count <= 0:
		return "wing %s is full: every %s is flown" % [prefix, "slot of the player's wing" if led != null and not own_flight
				else "place of its flights"]
	# A station scenario built these at load (`StationTraffic.reserve_pools`); a console launch elsewhere may hitch.
	main.ensure_free(ShipPool.ALLY_TYPE, count)
	var ships: Array[Combatant] = []
	var flights: Array[Wing] = []  # the flight each ship of `ships` took, null for one in the player's wing
	var at: UniversePos = main.world.to_universe(s.global_position)
	for i: int in count:
		var to_led: bool = led != null and i < slots.size()
		var place: Dictionary = {}  # empty without a wing director: the ship flies alone
		if not to_led and main.wings != null:
			place = main.wings.next_flight_place(prefix, 2 if own_flight else 1, s.home_id)  # the station's own: it docks here (M8-T06)
		var callsign: String = pool.next_name(prefix, 1)
		if to_led:
			callsign = main.wings.callsign_for(led, slots[i])
		elif not place.is_empty():
			callsign = main.wings.place_callsign(place)
		var behaviour: Dictionary = {"type": "ai", "profile": WING_PROFILE}
		if to_led:
			behaviour["orders"] = String(AiContext.order_word(led.order))
		var made: Dictionary = BrainFactory.from_behaviour(behaviour, at, hash([callsign, main.scenario_seed]))
		var ally: Combatant = pool.acquire(callsign, at, Basis.IDENTITY, main.world.anchored_velocity(),
				made["brain"] as PilotBrain if bool(made["ok"]) else null, ShipPool.ALLY_TYPE)
		if ally == null:
			break
		if to_led and main.wings.add_member(led, ally, slots[i]) != slots[i]:
			pool.release(ally)  # a ship the player's wing refuses would fly on deaf to its orders
			break
		if not place.is_empty() and main.wings.take_place(place, ally) == null:
			pool.release(ally)
			break
		ships.append(ally)
		flights.append(place.get("wing") as Wing)
	if main.wings != null:
		main.wings.drop_empty_flights(prefix)  # a flight made for a ship the pool could not give
	var going: Array[Combatant] = extra.duplicate()
	going.append_array(ships)
	var why: String = "no allied Starfury free" if ships.is_empty() else \
			_start(wing, 1, going, "", hash([main.scenario_seed, wing.to_lower(), "wing", SimClock.now()]))
	if not why.is_empty():
		for i: int in ships.size():
			if flights[i] != null:
				main.wings.leave(flights[i], ships[i])
			elif led != null:
				main.wings.remove_member(led, ships[i])
			pool.release(ships[i])
		if led != null and not own_flight:
			led.resize(size_before)  # the player's wing as it was, so a replenish does not fill slots it never had
		if main.wings != null:
			main.wings.drop_empty_flights(prefix)  # a retry starts from nothing, not from flights of parked hulls
		return why
	var in_play: Array[Combatant] = main.ships.alive(ShipPool.ALLY_TYPE)
	var sent: Array = _wing_ships.get(wing.to_lower(), []).filter(func(e: Dictionary) -> bool:
		return is_instance_valid(e["combatant"]) and in_play.has(e["combatant"]) and not ships.has(e["combatant"]))  # a hull sent again is one entry
	for ally: Combatant in ships:
		sent.append({"combatant": ally, "name": ally.display_name})
	_wing_ships[wing.to_lower()] = sent
	return ""


# The wing called `wing_name` when the player leads it, or null: its launched ships fly as the player's wingmen.
func _player_led_wing(wing_name: String) -> Wing:
	var wing: Wing = main.wings.wing_named(wing_name) if main.wings != null else null
	return wing if wing != null and wing.leader != null and wing.leader.is_player else null


## Launches ships already in play from wing `wing`'s arm, from door `door` on: fighters repaired in the main docking bay go
## out again this way (M8-T06). They keep their pilots and their wings. Returns "" or why not.
func launch_ships(wing: String, door: int, ships: Array[Combatant]) -> String:
	if ships.is_empty():
		return "no ship to launch"
	if not WINGS.has(wing.to_lower()):
		return "no wing '%s' (%s)" % [wing, ", ".join(WINGS)]
	for c: Combatant in ships:
		if not _can_carry(c):
			return "%s cannot be carried" % (c.display_name if c != null else "a ship")
	return _start(wing, door, ships, "", hash([main.scenario_seed, wing.to_lower(), "relaunch", SimClock.now()]))


## Launches every wing the station has (`launch wing all`). Returns `{lines, launched}`: one line per wing (how many launched,
## or why it did not) and how many wings went.
func launch_all_wings() -> Dictionary:
	var lines := PackedStringArray()
	var launched: int = 0
	for wing: String in WINGS:
		var why: String = launch_wing(wing)
		if why.is_empty():
			launched += 1
		lines.append("wing %s: %s" % [wing, why if not why.is_empty() else "%d launching" % _last_launch_size(wing)])
	return {"lines": lines, "launched": launched}


# How many fighters the running launch of `wing` carries.
func _last_launch_size(wing: String) -> int:
	for launch: Dictionary in launches:
		if launch["wing"] == wing.to_lower():
			return (launch["ships"] as Dictionary).size()
	return 0


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
	return not player_launch().is_empty() or (squadron != null and squadron.running())


## The player asked to skip the launch (A or Start during its shots, `launch skip`, a skipped mission step).
func skip() -> void:
	_burn_left_s = 0.0
	if squadron != null and squadron.stage == SquadronLaunch.Stage.WINGS:
		squadron.skip_asked = true
		return
	if player_launch().is_empty():
		return
	_skip_asked = true
	_shots_cut = true


## The player's flight command for this tick while its engines burn after the hand-off (`Main` flies it as the gate jump's
## autopilot), else null.
func step_player(delta: float) -> FlightCommand:
	if _burn_left_s <= 0.0 or profile == null or main == null or not main.player_alive:
		_burn_left_s = 0.0
		return null
	_burn_left_s -= delta
	if _burn_left_s <= 0.0:
		_burn_left_s = 0.0
		if not _review_holding:
			cut_shots()  # the thrusters cut: the controls are the pilot's at once (M8-T30)
		return null
	var burn := FlightCommand.new()
	burn.main_left = profile.burn_throttle
	burn.main_right = profile.burn_throttle
	return burn


## Ends the launch's camera at once, the launch itself going on (the thrusters cutting, M8-T30; M8-T32's abort): the shot on screen
## stops if it is one of this director's, and no more are played for this launch.
func cut_shots() -> void:
	_shots_cut = true
	_review_holding = false
	_drop_fill()
	if main != null and main.camera_rig != null and _playing != null and main.camera_rig.playing_shot() == _playing:
		main.camera_rig.stop_shot()
	_playing = null


## Pins variant `id` of any launch pool for the next launch that draws from it, held to its end (the review sheets); "" or why not.
func force_variant(id: StringName) -> String:
	for bag: LaunchCut in [cut, exterior_cut, squadron_cut]:
		if bag == null:
			continue
		for phase: Dictionary in bag.profile.phases:
			for variant: Dictionary in phase["variants"]:
				if variant["id"] == id:
					bag.force = id
					review_variant = id
					return ""
	return "no launch shot variant '%s'" % id


## Every launch's state, one line each.
func describe() -> String:
	var lines := PackedStringArray()
	for launch: Dictionary in launches:
		var seq: LaunchSequence = launch["seq"]
		lines.append("wing %s, %.1f s, arm %.1f deg%s: %s" % [launch["wing"], seq.time_s, seq.arm_angle_now(),
				" (under the spine)" if seq.blocked_now() else "", seq.describe()])
	return " | ".join(lines) if not lines.is_empty() else "no launch"


## Whether the player's latest launch was filmed from outside the station (the exterior shots).
func filmed_exterior() -> bool:
	return bool(_launch_shot.get("exterior", false))


## The station's door leaves as the launches slide them; null until a launch has run.
func door_leaves() -> StationDoorLeaves:
	return _leaves


func _physics_process(delta: float) -> void:
	var s: Station = station()
	if s == null:
		_prev_angle = NAN
		return
	var rate: float = s.spin.rate_rad_s if s.spinning else 0.0
	# The drum's body is still at last tick's angle until Jolt steps: carry the fighters from there.
	var angle: float = s.drum_angle - rate * delta if is_nan(_prev_angle) else _prev_angle
	_prev_angle = s.drum_angle
	var cinematic: bool = squadron != null and squadron.running()
	if cinematic:
		squadron.advance(delta)
		if squadron.skip_asked:
			squadron.skip_now(s)
	if launches.is_empty() and not cinematic:
		return
	if _leaves == null:
		_leaves = StationDoorLeaves.find(s.drum_piece, s.hardpoints)
	for launch: Dictionary in launches.duplicate():
		_step(launch, s, delta, angle, rate)
	if squadron != null:
		squadron.place(s)


func _step(launch: Dictionary, s: Station, delta: float, angle: float, rate: float) -> void:
	var seq: LaunchSequence = launch["seq"]
	var player_id: String = launch["player"]
	if is_same(launch, _launch_shot) and _skip_asked and not player_id.is_empty():
		_skip_asked = false
		seq.drum_angle = angle
		seq.spin_rate_rad_s = rate
		seq.skip(player_id)
		if seq.fighter(player_id)["phase"] == LaunchSequence.Phase.RELEASED:
			_hand_over(launch, player_id, s, true)
	for e: Dictionary in seq.advance(delta, angle, rate):
		if e["kind"] == "release":
			_hand_over(launch, String(e["id"]), s, bool(seq.fighter(String(e["id"]))["skip"]))  # a skip held under the spine is still one
	for f: Dictionary in seq.fighters:
		if f["phase"] != LaunchSequence.Phase.RELEASED:
			_carry(launch, String(f["id"]), s)
	if _leaves != null:
		for i: int in seq.bays.size():
			_leaves.set_open(String(seq.bays[i]["name"]), seq.door_share(i))
	if is_same(launch, _launch_shot):
		_direct_camera(launch)
	if seq.finished():
		launches.erase(launch)
		launch_finished.emit(String(launch["wing"]))


## Ends a launch at once with its doors shut (the squadron cinematic's skip; its fighters are already placed elsewhere).
func end_launch(launch: Dictionary) -> void:
	launches.erase(launch)
	var seq: LaunchSequence = launch["seq"]
	if _leaves != null:
		for bay: Dictionary in seq.bays:
			_leaves.set_open(String(bay["name"]), 0.0)
	launch_finished.emit(String(launch["wing"]))


## Holds a ship out of the flight model at the station-frame `state` this tick (a scripted cinematic flight, M8-T03), as the
## drum carries a fighter on its rack.
func hold(ship: Ship, state: Dictionary, s: Station) -> void:
	var first: bool = _grip(ship)
	_place(ship, _world_state(state, s))
	if first:
		ship.reset_physics_interpolation()


## Gives a held ship back to the flight model.
func let_go(ship: Ship) -> void:
	_free(ship)


## Whether a ship is in play and alive.
func is_flying(c: Combatant) -> bool:
	return _alive(c)


# Puts a fighter where the drum carries it this tick.
func _carry(launch: Dictionary, id: String, s: Station) -> void:
	var c: Combatant = (launch["ships"] as Dictionary).get(id)
	if not _alive(c):
		if c != null and is_instance_valid(c) and c.ship != null and is_instance_valid(c.ship):
			_free(c.ship)  # lost on the rack: it falls as any wreck does
		return
	var ship: Ship = c.ship
	var first: bool = _grip(ship)
	_place(ship, _world_state((launch["seq"] as LaunchSequence).state_of(id, s.drum_origin), s))
	if first:
		ship.reset_physics_interpolation()


# Takes a ship out of the flight model and out of reach; true when it was not held already.
func _grip(ship: Ship) -> bool:
	var key: int = ship.get_instance_id()
	if _carried.has(key):
		return false
	_carried[key] = {"layer": ship.collision_layer, "mask": ship.collision_mask, "exempt": ship.tier_exempt}
	ship.collision_layer = 0
	ship.collision_mask = 0
	ship.custom_integrator = true  # no thrust or assist moves it while it rides the drum
	ship.tier_exempt = true
	ship.clamped = true  # the clamp moves it: no plume, puff or engine sound until the ejection
	InteriorLight.set_inside(ship, true)  # in the hall the sun does not reach it; back in the open at its hand-off
	return true


# Lets a fighter go at its release point with the hand-off state.
func _hand_over(launch: Dictionary, id: String, s: Station, skipped: bool) -> void:
	var c: Combatant = (launch["ships"] as Dictionary).get(id)
	if not _alive(c):
		return
	var seq: LaunchSequence = launch["seq"]
	if bool(launch.get("squadron", false)) and squadron != null and squadron.running():
		squadron.take(id, seq.handoff_of(id, s.drum_origin), s)  # held on: it flies its way to its slot
		return
	var state: Dictionary = _world_state(seq.handoff_of(id, s.drum_origin), s)
	var ship: Ship = c.ship
	_place(ship, state)
	_free(ship)
	if id == launch["player"]:
		last_handoff = state.merged({"id": id, "bay": seq.bays[seq.fighter(id)["bay"]]["name"], "drum_angle": seq.drum_angle,
				"skipped": skipped})
		_burn_left_s = 0.0 if skipped else profile.burn_s
		var cinematic: bool = squadron != null and squadron.running()
		if cinematic:
			squadron.finish()
		player_released.emit()
		if cinematic:
			squadron_finished.emit()


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
	ship.clamped = false
	InteriorLight.set_inside(ship, false)
	_carried.erase(key)


# The station frame's state in the World: the station's place and its velocity against the World added.
func _world_state(state: Dictionary, s: Station) -> Dictionary:
	var xform: Transform3D = s.global_transform
	var rest: Vector3 = main.world.anchored_velocity() if main != null else Vector3.ZERO  # the station's, wherever the frame is
	return {"transform": xform * (state["transform"] as Transform3D), "velocity": xform.basis * (state["velocity"] as Vector3) + rest,
			"angular": xform.basis * (state["angular"] as Vector3)}


func _start(wing: String, door: int, ships: Array[Combatant], player_id: String, seed_value: int) -> String:
	var s: Station = station()
	if s == null:
		return "no station in this scenario (anchor it on babylon5)"
	if not s.has_power():
		return "%s has no power" % Station.DISPLAY_NAME  # a hulk or a wreck launches nothing (M10-T65)
	if profile == null:
		return "no launch profile (%s)" % LaunchProfile.DEFAULT_PATH
	for launch: Dictionary in launches:
		if launch["wing"] == wing.to_lower():
			return "wing %s is launching already" % wing
	if not player_id.is_empty():
		main.world.return_home()  # the player's launch: the station's rail first (M7-T71)
	var ids := PackedStringArray()
	var by_id: Dictionary = {}
	for c: Combatant in ships:
		ids.append(c.display_name)
		by_id[c.display_name] = c
	var rate: float = s.spin.rate_rad_s if s.spinning else 0.0
	var angle: float = s.drum_angle if is_nan(_prev_angle) else _prev_angle
	var seq := LaunchSequence.create(s.hardpoints, wing, ids, profile, door, angle, rate, seed_value)
	if not seq.valid:
		return seq.error
	var offset: float = seq.stored_pose_offset_deg(seq.bays[0])
	if offset > 1.0:
		push_warning("LaunchDirector: the station's rack pose is %.1f deg from the profile's stored pose; the profile's is used" % offset)
	var launch: Dictionary = {"seq": seq, "ships": by_id, "player": player_id, "wing": wing.to_lower()}
	launches.append(launch)
	if not player_id.is_empty():
		_launch_shot = launch
	# Launched from this station's bays, a fighter belongs here: it comes back to its docking bay for repair (M8-T06).
	for c: Combatant in ships:
		if not c.home_assigned:
			c.home = s.home_id
		var own: Wing = main.wings.player_wing() if c.is_player and main.wings != null else null
		if own != null and own.leader == c and own.home == &"":
			own.home = c.home
	for id: String in ids:
		_carry(launch, id, s)
	return ""


func _can_carry(c: Combatant) -> bool:
	return _alive(c) and not c.ship.is_tier_parked() and not _carried.has(c.ship.get_instance_id())


func _alive(c: Combatant) -> bool:
	return c != null and is_instance_valid(c) and c.ship != null and is_instance_valid(c.ship) and c.damageable != null \
			and c.damageable.is_active() and (not c.is_player or main.player_alive)


# --- the launch camera -------------------------------------------------------------------------------------------------


# Plays each shot of the cut once the fighter it follows has been long enough in its step (the player in its own launch).
func _direct_camera(launch: Dictionary) -> void:
	var seq: LaunchSequence = launch["seq"]
	var shots: Array[Dictionary] = launch.get("cut", [] as Array[Dictionary])
	for follows: String in LaunchProfile.FOLLOWS:
		var id: String = follow_id(launch, follows)
		var step: StringName = seq.step_of(id) if not id.is_empty() else &""
		if not step.is_empty() and not _step_starts.has("%s|%s" % [id, step]):
			_step_starts["%s|%s" % [id, step]] = seq.time_s - seq.step_time(id)
	if _review_holding:
		if main != null and main.camera_rig != null and main.camera_rig.playing_shot() == _playing:
			if not _until_reached(launch):
				return  # a review shot plays to its end, whatever launch comes next
			main.camera_rig.stop_shot()  # its own end: the ship has left the hall
		_review_holding = false
	if _shots_cut or main == null or main.camera_rig == null or sequencer == null:
		return
	var due := PackedInt32Array()
	for i: int in shots.size():
		var entry: Dictionary = shots[i]
		var key: String = "%s|%s" % [follow_id(launch, String(entry.get("follows", "lead"))), entry["step"]]
		if _step_starts.has(key) and seq.time_s - float(_step_starts[key]) >= float(entry["at_s"]) - LaunchSequence.EPS_S:
			due.append(i)
	var play: int = sequencer.next(seq.time_s, due, shots, released_count(seq), wave_left(seq))
	if play >= 0:
		var subject: String = follow_id(launch, String(shots[play].get("follows", "lead")))
		_play(shots[play]["shot"], subject, shots[play].get("until", &""))
		_light_fill(shots[play], subject)
		if review_variant != &"" and shots[play]["variant"] == review_variant:
			review_variant = &""
			_review_holding = true
			_shots_cut = true  # held to its end for the review sheet
	if play >= 0:
		(launch["used"] as Dictionary)[shots[play]["variant"]] = seq.time_s
	elif _shot_ending(launch):
		_fill(launch)


# The director's shot ends this tick (its last key, or its `until`), or nothing is on screen: the next shot must go on now, so the
# cockpit never shows between.
func _shot_ending(launch: Dictionary) -> bool:
	var rig: CameraRig = main.camera_rig
	if not rig.is_playing_shot():
		return true
	if rig.playing_shot() != _playing:
		return false
	return rig.shot_time_s() + get_physics_process_delta_time() >= _playing.duration_s - 1e-6 or _until_reached(launch)


# The shot on screen has had its least hold and its fighter has reached the variant's `until` step.
func _until_reached(launch: Dictionary) -> bool:
	if _playing_until == &"" or main.camera_rig.shot_time_s() < profile.min_shot_s - LaunchSequence.EPS_S:
		return false
	var seq: LaunchSequence = launch["seq"]
	var step: int = LaunchProfile.STEPS.find(seq.step_of(_playing_subject))
	return step >= LaunchProfile.STEPS.find(_playing_until)


# Between the cut's phases, another shot of the launch's pool (M8-T30, maintainer: no angle 3 s or longer, the sequence keeps
# its length): from the latest phase its fighter has reached, one not yet played in this launch, else the one played longest
# ago; a hold shot only while its fighter holds. Seeded like the cut.
func _fill(launch: Dictionary) -> void:
	var seq: LaunchSequence = launch["seq"]
	var pool: LaunchProfile = launch.get("pool")
	var used: Dictionary = launch["used"]
	if pool == null:
		return
	var best: Array[Dictionary] = []  # the latest eligible phase's unused variants
	var oldest: Dictionary = {}
	var oldest_at: float = INF
	for p: int in range(pool.phases.size() - 1, -1, -1):
		var phase: Dictionary = pool.phases[p]
		var subject: String = follow_id(launch, String(phase.get("follows", "lead")))
		var now: int = LaunchProfile.STEPS.find(seq.step_of(subject)) if not subject.is_empty() else -1
		var at: int = LaunchProfile.STEPS.find(phase["step"])
		if now < 0 or at > now or (phase["step"] == &"hold" and now != at):
			continue
		for variant: Dictionary in phase["variants"]:
			var entry: Dictionary = {"variant": variant, "subject": subject}
			if not used.has(variant["id"]):
				if best.is_empty() or best[0]["phase"] == p:
					entry["phase"] = p
					best.append(entry)
			elif float(used[variant["id"]]) < oldest_at:
				oldest_at = float(used[variant["id"]])
				oldest = entry
	var chosen: Dictionary = oldest
	if not best.is_empty():
		chosen = best[mini(int(LaunchCut.unit(int(launch.get("cut_seed", 0)), "fill", used.size()) * best.size()), best.size() - 1)]
	if chosen.is_empty():
		return
	var variant: Dictionary = chosen["variant"]
	used[variant["id"]] = seq.time_s
	_play(variant["shot"], chosen["subject"], variant.get("until", &""))
	_light_fill(variant, chosen["subject"])
	sequencer.note(seq.time_s, variant["id"], released_count(seq))


func _play(shot: CinematicShot, subject: String, until: StringName = &"") -> void:
	_playing = shot
	_playing_until = until
	_playing_subject = subject
	var door: Variant = _door_in_station(subject, 1.0)
	_fixed_bay = door if door != null else Transform3D.IDENTITY  # `bay_fixed`: the door where it was as the shot began
	main.camera_rig.play_shot(shot, _actor_pose_of.bind(subject), _origin_to_local)


## The fighter a camera phase follows in `launch` (`LaunchProfile.FOLLOWS`), or "" when the launch has none.
static func follow_id(launch: Dictionary, follows: String) -> String:
	var seq: LaunchSequence = launch["seq"]
	if seq.fighters.is_empty():
		return ""
	match follows:
		"wave2":
			for f: Dictionary in seq.fighters:
				if int(f["wave"]) == 2 and int(f["k"]) == 0:
					return String(f["id"])
			return ""
		"last":
			return String(seq.fighters[-1]["id"])
	var player: String = launch["player"]
	return player if not player.is_empty() else String(seq.fighters[0]["id"])


## How many fighters of a launch were let go so far.
static func released_count(seq: LaunchSequence) -> int:
	return seq.fighters.filter(func(f: Dictionary) -> bool: return f["phase"] == LaunchSequence.Phase.RELEASED).size()


## How many of a launch's first wave are still to go.
static func wave_left(seq: LaunchSequence) -> int:
	return seq.fighters.filter(func(f: Dictionary) -> bool:
		return int(f["wave"]) == 1 and f["phase"] != LaunchSequence.Phase.RELEASED).size()


# Lights the shot's fill (replacing the last one), or puts the last one out when this shot has none.
func _light_fill(entry: Dictionary, subject: String = "") -> void:
	_drop_fill()
	var spec: Dictionary = entry.get("fill", {})
	var rig: LightRig = LightRig.of(self)
	if spec.is_empty() or rig == null:
		return
	fill = LightEmitter.new("launch fill", LightEmitter.PRIORITY_MUZZLE_FLASH, spec["color"], float(spec["energy"]),
			float(spec["range_m"]))
	_fill_shot = entry["shot"]
	_fill_spec = spec
	_fill_id = subject
	var pose: Variant = _actor_pose_of(String(spec["actor"]), subject)
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



# The shots' actors for the player's own launch.
func _actor_pose(actor: String) -> Variant:
	return _actor_pose_of(actor, "")


# The shots' actors as drawn: `fighter` (the followed fighter, `id`; "" the player), `bay` (its door as the drum turns), `bay_fixed`
# (that door where it was as the shot began, fixed in space), `fighter_fixed` (the fighter's place with that door's axes: a camera that
# follows the ship without turning with it, so its flip shows), `station`, and `formation` (the squadron launch's formation anchor).
func _actor_pose_of(actor: String, id: String) -> Variant:
	var s: Station = station()
	if actor == "station":
		return s.get_global_transform_interpolated() if s != null else null
	if actor == "formation":
		return s.get_global_transform_interpolated() * squadron.anchor if s != null and squadron != null else null
	var player: String = String(_launch_shot.get("player", "")) if not _launch_shot.is_empty() else ""
	if id.is_empty():
		id = player
	if actor == "fighter" or actor == "player":
		if id == player or id.is_empty() or actor == "player":
			return main.ship.get_global_transform_interpolated() if main != null and main.player_alive else null
		var c: Combatant = (_launch_shot["ships"] as Dictionary).get(id)
		return c.ship.get_global_transform_interpolated() if _alive(c) else null
	if actor == "bay":
		var door: Variant = _door_in_station(id, Engine.get_physics_interpolation_fraction())
		return s.get_global_transform_interpolated() * (door as Transform3D) if door != null else null
	if actor == "bay_fixed":
		return s.get_global_transform_interpolated() * _fixed_bay if s != null else null
	if actor == "fighter_fixed":
		var ship: Ship = _subject_ship(id)
		if s == null or ship == null:
			return null
		return Transform3D((s.get_global_transform_interpolated() * _fixed_bay).basis, ship.get_global_transform_interpolated().origin)
	return null


# The followed fighter's door in the station's frame as the drum is drawn (`fraction` of the way to this tick), or null.
func _door_in_station(id: String, fraction: float) -> Variant:
	var s: Station = station()
	if s == null or _launch_shot.is_empty():
		return null
	var seq: LaunchSequence = _launch_shot["seq"]
	var f: Dictionary = seq.fighter(id if not id.is_empty() else String(_launch_shot.get("player", "")))
	if f.is_empty():
		return null
	var drum := Transform3D(Basis(Vector3.BACK, s.visual_angle(fraction)), s.drum_origin)
	return drum * LaunchSequence.door_frame(seq.bays[f["bay"]])


# The followed fighter carries the key light while one of this director's shots is on screen, and loses it after.
func _light_subject() -> void:
	var ship: Ship = null
	if main != null and main.camera_rig != null and _playing != null and main.camera_rig.playing_shot() == _playing:
		ship = _subject_ship(_playing_subject)
	if ship == null:
		_key_light.detach()
		return
	var to_sun: Vector3 = main.space_environment.key_star.global_basis.z \
			if main.space_environment != null and main.space_environment.key_star != null else Vector3.ZERO
	_key_light.attach(ship, to_sun)


# The ship of the fighter `id` in the filmed launch ("" the player), or null.
func _subject_ship(id: String) -> Ship:
	var player: String = String(_launch_shot.get("player", "")) if not _launch_shot.is_empty() else ""
	if id.is_empty() or id == player:
		return main.ship if main.player_alive else null
	var c: Combatant = (_launch_shot.get("ships", {}) as Dictionary).get(id)
	return c.ship if _alive(c) else null


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
		&"cut": {"get": _cut_text, "doc": "The player's last launch's camera cut: its seed and each phase's shot variant (a phase left out is missing)"},
		&"launches": {"get": func() -> int: return launch_count, "type": TYPE_INT, "doc": "Player launches this scenario run (seeds the cuts)"},
		&"squadron": {"get": func() -> String: return squadron.describe() if squadron != null else "none",
				"doc": "The squadron-launch cinematic (M8-T03): its stage and how many of the squadron are on their slots"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(PROVIDER,
			"Cobra-bay launches (M7-T08): launch <wing> <door> (the player and its wingmen), launch wing <wing> (twelve AI Starfuries in two waves; a wing the player leads takes them as its wingmen), launch wing all (every wing), launch squadron [wing] (the squadron-launch cinematic, M8-T03: the squadron's flights launch and form up filmed from outside, then the player), launch skip, launch status, launch cut (the last camera cut), launch seed <n|off> (pin the cuts' seed), launch preview <variant> (play one shot variant now, for look sheets), launch force <variant> (the next launch plays that variant in its phase and holds it to its end, for review sheets; M8-T30)",
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
	if a == "cut":
		return ConsoleResult.line(_cut_text())
	if a == "force":
		var why_force: String = force_variant(StringName(str(args[&"b"]) if args[&"b"] != null else ""))
		return ConsoleResult.failure("launch force: %s" % why_force) if not why_force.is_empty() \
				else ConsoleResult.line("the next launch plays %s in its phase, held to its end" % args[&"b"])
	if a == "preview":
		return _preview(str(args[&"b"]) if args[&"b"] != null else "")
	if a == "seed":
		if b == "off":
			cut_seed = -1
			return ConsoleResult.line("launch cuts seeded per launch")
		if not b.is_valid_int() or int(b) < 0:
			return ConsoleResult.failure("launch seed <n|off>")
		cut_seed = int(b)
		return ConsoleResult.line("launch cuts seeded with %d" % cut_seed)
	if a == "skip":
		if player_launch().is_empty() and (squadron == null or not squadron.running()):
			return ConsoleResult.failure("launch skip: the player is not launching")
		skip()
		return ConsoleResult.line("launch skipped")
	if a == "squadron":
		var why_squadron: String = launch_squadron(b)
		if not why_squadron.is_empty():
			return ConsoleResult.failure("launch squadron: %s" % why_squadron)
		return ConsoleResult.line("squadron launching: %d Starfuries, then the player from cobra_bay_%s_%d" % [squadron.ships.size(),
				squadron.wing, squadron.door])
	if a == "wing" and b == "all":
		var outcome: Dictionary = launch_all_wings()
		var lines: PackedStringArray = outcome["lines"]
		return ConsoleResult.success(lines) if int(outcome["launched"]) > 0 \
				else ConsoleResult.failure("launch wing all: %s" % "; ".join(lines))
	if a == "wing":
		var why_wing: String = launch_wing(b)
		if not why_wing.is_empty():
			return ConsoleResult.failure("launch wing: %s" % why_wing)
		var joined: String = " as the player's wingmen" if _player_led_wing(b.to_upper()) != null else ""
		return ConsoleResult.line("wing %s launching: %d Starfuries in two waves%s" % [b, _last_launch_size(b), joined])
	if WINGS.has(a) and b.is_valid_int():
		var why: String = launch_player(a, int(b))
		return ConsoleResult.failure("launch: %s" % why) if not why.is_empty() \
				else ConsoleResult.line("launching from cobra_bay_%s_%s" % [a, b])
	return ConsoleResult.failure("launch <alpha|beta|delta|zeta> <1-6>, launch wing <wing|all>, launch squadron [wing], launch skip, launch status, launch cut, launch seed <n|off>")


# Plays one variant of the profile's pools on the player's launch now, as its phase would (for look sheets).
func _preview(id: String) -> ConsoleResult:
	if _launch_shot.is_empty():
		return ConsoleResult.failure("launch preview: no player launch to film")
	var ids := PackedStringArray()
	for bag: LaunchCut in [cut, exterior_cut, squadron_cut]:
		if bag == null:
			continue
		for phase: Dictionary in bag.profile.phases:
			for variant: Dictionary in phase["variants"]:
				ids.append(String(variant["id"]))
				if String(variant["id"]) == id:
					_shots_cut = true  # the cut's own shots stand aside
					_review_holding = true  # and it plays to its end
					var subject: String = follow_id(_launch_shot, String(phase.get("follows", "lead")))
					_play(variant["shot"], subject, variant.get("until", &""))
					_light_fill(variant, subject)
					return ConsoleResult.line("previewing %s (%s phase)" % [id, phase["phase"]])
	return ConsoleResult.failure("launch preview <%s>" % "|".join(ids))


func _cut_text() -> String:
	if _launch_shot.is_empty() or not _launch_shot.has("cut"):
		return "none"
	var parts := PackedStringArray()
	for entry: Dictionary in _launch_shot["cut"] as Array[Dictionary]:
		parts.append("%s %s" % [entry["phase"], entry["variant"]])
	return "seed %d: %s" % [int(_launch_shot["cut_seed"]), ", ".join(parts)]
