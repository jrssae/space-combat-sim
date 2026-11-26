class_name CapitalHangar
extends CarrierDock
## A capital carrier's hangar (M10-T17, D12.10, Q53, Q58, Q71, Q73): its craft in its bays, launched through the ship pool as
## its faction's, and recovered as the raider carrier recovers its own (Q25 to Q30). A child of the `CapitalShip`; the dock it
## extends flies the craft out of and into the bays on the native rows (`ScsDockRows`), and this node decides.
##
## - **Stock.** Counts by craft type (`stock`): its loadout's craft (`stock_from_loadout`) from the moment it is made, unless
##   `stocked_on_spawn` is off (a test's lone capital) or it is emptied (`empty`: a parked line-up ship). Once it is in play the
##   pool gets the stock's worth of ships. A craft only exists while it is out: taken from the pool to launch, given back when
##   it docks.
## - **Wings** (`HangarRules`): the first wing goes when the brain sees a hostile within reach (`on_threat`), the next once the
##   threat has grown or the wings out have lost a share of theirs (the Nova's two of 12, the Omega's four of 8). While the
##   hangar launches, its brain holds the ship's course (the Launch state).
## - **Per tick** the dock's rows run in native code and place the bodies they hold (`native_bodies`); this node's tick only
##   steps its bays' doors and lifts while they work, and sleeps once nobody is out and every bay is at rest.
## - **Bays.** A bay with a roll-up door (the Hyperion's) opens it only for its own craft's launch or recovery, then shuts it.
##   A bay with a lift (the Nova's) sinks it empty, brings a trip of craft up (two rows of three) and sends them out, sinking for
##   the next once they have run clear, and takes craft drawn in back down (`BayElevator`, drawn by `BayElevatorNode`). A big hall (the Omega's) launches from lanes at its back. A shuttle that
##   folds its wings (`WingFoldNode`) folds them before it enters and spreads them once it has left.
## - **Recovery.** Every craft out is called home once nothing hostile has been within reach for a while, a badly hurt one
##   alone, and all of them before a jump: the jump waits a time for them (`ready_to_jump`), then leaves the rest.
## - A hulk or a ship with no power launches nothing and takes nobody in (Q72, Q78), nor does a lost bay.
## Console: command `hangar`, provider `hangars` (`HangarConsole`).

## The hangar finished a wing's queue: `wing` is its number (0 first), `size` the craft it sent.
signal wing_launched(wing: int, size: int)
## A craft out came home and went back to its pool.
signal recovered(ship: Ship, type: StringName)

const NODE_NAME: StringName = &"Hangar"
## How often the hangar decides about wings and recovery, s.
const DECIDE_S: float = 0.5
## A door shuts this long after its bay was last used, s.
const DOOR_IDLE_S: float = 3.0
## Craft drawn onto a lift wait this long for others before it takes them down, s.
const LIFT_GATHER_S: float = 2.0
## A lift sinks for its next trip this long after its last trip reached the floor: its craft have run clear of it by then, s.
const LIFT_CLEAR_S: float = 1.5
## How often the bays' doors, queues and lifts are looked at, s (the lifts' own motion is stepped every tick).
const PUMP_S: float = 0.1

## Whether a carrier comes into play with its loadout's craft aboard (M10-T17, the maintainer: full by default). A test or a
## balance fight with a lone capital turns it off for its run (and back on after) to keep that capital's hangar empty.
static var stocked_on_spawn: bool = true
## A bay launches nothing while a craft coming home is this near its approach point, m.
const RETURN_CLEAR_M: float = 400.0

var ship: CapitalShip = null
var options: Dictionary = {}
## Craft aboard by type.
var stock: Dictionary = {}
## Whether it launches and recovers on its own (the console and tests turn it off to drive it by hand; a jump still recalls).
var auto: bool = true
## The brain's last count of hostiles within reach.
var threat_fighters: int = 0
var threat_warships: int = 0
## Wings out in this fight, the fighters they took, how many of those were lost, and the threat the last one met.
var wings_out: int = 0
var wing_fighters: int = 0
var wing_losses: int = 0
var threat_at_last: float = 0.0
## Seconds with nothing hostile within reach; whether every craft is called home.
var calm_for_s: float = 0.0
var recalling: bool = false
## Waiting to jump, and for how long.
var jumping: bool = false
var waited_s: float = 0.0
## Readouts: wings sent, craft sent, craft recovered, craft left behind at a jump, launches refused (no power, no pool ship).
var wings_sent: int = 0
var sent: int = 0
var recoveries: int = 0
var left_behind: int = 0
var refused: int = 0
## Its own cost so far: ticks and their time, us (the dock's rows and this node's decisions; a readout).
var ticks: int = 0
var tick_us: float = 0.0

var _bays: Dictionary = {}  # bay name -> {queue, since_s, idle_s, lift, aboard, gather_s, cradles}
var _out: Dictionary = {}  # ship instance id -> {ship, combatant, type}
var _decide_s: float = 0.0
var _launching: bool = false
var _fought: bool = false  # a hostile came within reach since everyone was last home
var _clock_s: float = 0.0  # the hangar's own time while awake, for its lifts' cycle
var _pump_s: float = 0.0
var _moving: Array[BayElevator] = []  # the lifts on the move, stepped every tick
var _lift_bay: Dictionary = {}  # lift -> its bay
var _pool_ready: bool = false
var _prepared: Dictionary = {}  # craft type -> ships this hangar has built into the pool


## A hangar for `p_ship` from its bays and its hull's options; null when no bay takes craft. Call before it enters the tree.
static func make(p_ship: CapitalShip) -> CapitalHangar:
	var opts: Dictionary = HangarRules.options(p_ship.type_id)
	var berths: CarrierCradles = BayBerths.of(p_ship.hardpoints(), opts)
	if berths.count() == 0:
		return null
	var made := CapitalHangar.new()
	made.name = NODE_NAME
	made.ship = p_ship
	made.options = opts
	made.setup(berths)
	made.launch_gap_s = float(opts["launch_gap_s"])
	made.capture_gate = made._may_enter
	made.native_bodies = true
	for i: int in berths.count():
		var bay: String = berths.bays[i]
		if not made._bays.has(bay):
			made._bays[bay] = {"queue": [], "since_s": INF, "idle_s": 0.0, "lift": null, "aboard": [], "gather_s": 0.0,
					"cradles": [], "lifted_at": -INF}
		(made._bays[bay]["cradles"] as Array).append(i)
		if berths.lift_m[i] > 0.0 and made._bays[bay]["lift"] == null:
			made._bays[bay]["lift"] = BayElevator.new()
			made._lift_bay[made._bays[bay]["lift"]] = bay
	if stocked_on_spawn:
		made.stock_from_loadout()
	return made


## The hangar of `capital`, or null.
static func of(capital: Node) -> CapitalHangar:
	return capital.get_node_or_null(NodePath(NODE_NAME)) as CapitalHangar if capital != null else null


func _ready() -> void:
	super._ready()
	launched.connect(_on_launched)
	docked.connect(_on_docked)
	in_bay.connect(_on_in_bay)
	var hull: Damageable = Damageable.of(ship)
	if hull != null:
		hull.destroyed.connect(_on_hull_destroyed)
	_add_lift_nodes()
	lifted.connect(_on_lifted)
	set_physics_process(true)
	_prepare_when_placed.call_deferred()


## Fills the hangar with the loadout's craft (`loadouts.json` `launches`) that its bays take and the catalogue has, up to the
## bays' capacity. Returns how many came aboard.
func stock_from_loadout() -> int:
	_wake()
	stock.clear()
	var launches: Dictionary = CapitalData.hull_entry(String(ship.type_id)).get("launches", {}) as Dictionary
	var total: int = 0
	for raw: Variant in launches:
		var type := StringName(str(raw))
		var room: int = capacity_for(type)
		var n: int = mini(int(launches[raw]), room)
		if n > 0 and ShipCatalog.has_type(type):
			stock[type] = n
			total += n
	return total


## Empties the hangar: nothing aboard or queued (a lone capital in a test or a balance fight; `hangar empty`).
func empty() -> void:
	_clear_queues()
	stock.clear()


## Makes sure the ship pool can field the stock: adds ships of each type to it up to the most this hangar has carried. Returns
## how many were built.
func prepare_pool() -> int:
	var pool: ShipPool = ShipPool.for_tree(get_tree()) if is_inside_tree() else null
	if pool == null:
		return 0
	_pool_ready = true
	var built: int = 0
	for type: Variant in stock:
		var more: int = int(stock[type]) - int(_prepared.get(type, 0))
		if more > 0:
			built += pool.prepare(type, more)
			_prepared[type] = int(stock[type])
	return built


## How many craft of `type` the bays hold together.
func capacity_for(type: StringName) -> int:
	var room: int = 0
	for raw: Variant in ship.hardpoints().get("bays", []):
		var bay: Dictionary = raw
		if BayBerths.crafts_of(bay).has(String(type)):
			room += maxi(int(bay.get("capacity", 1)), 1)
	return room


## Fighters aboard (the stock's fighter types), craft out, and craft waiting in a bay's queue.
func fighters_aboard() -> int:
	var n: int = 0
	for type: Variant in stock:
		n += int(stock[type]) if _is_fighter(type) else 0
	return n


func out_count() -> int:
	return _out.size()


func queued_count() -> int:
	var n: int = 0
	for bay: Dictionary in _bays.values():
		n += (bay["queue"] as Array).size()
	return n


## Whether it is launching now: a craft waits in a bay's queue or is on its way out.
func is_launching() -> bool:
	if queued_count() > 0:
		return true
	for key: int in _held.keys():
		if not bool(_held[key]["returning"]):
			return true
	return false


## The brain's count of hostiles within reach changed (`CapitalBrains`).
func on_threat(fighters: int, warships: int) -> void:
	_wake()
	threat_fighters = maxi(fighters, 0)
	threat_warships = maxi(warships, 0)


## Queues `count` craft of `type` for launch (an order, the console). Returns how many it queued.
func launch(type: StringName, count: int) -> int:
	set_physics_process(true)
	var queued: int = 0
	for k: int in count:
		if int(stock.get(type, 0)) <= 0 or not _queue_one(type):
			break
		queued += 1
	return queued


## Launches the next wing of fighters now. Returns how many it queued.
func launch_wing() -> int:
	set_physics_process(true)
	var size: int = HangarRules.wing_size(options["wings"], wings_out, fighters_aboard())
	var queued: int = 0
	for k: int in size:
		var type: StringName = _next_fighter_type()
		if type == &"" or not _queue_one(type):
			break
		queued += 1
	if queued > 0:
		wings_out += 1
		wings_sent += 1
		wing_fighters += queued
		threat_at_last = HangarRules.threat(threat_fighters, threat_warships, float(options["warship_weight"]))
		wing_launched.emit(wings_out - 1, queued)
	return queued


## Calls every craft out home. Returns how many it could send to a bay now (the rest are called again at the next decision).
func recall_all() -> int:
	set_physics_process(true)
	recalling = true
	var n: int = 0
	for entry: Dictionary in _out.values():
		n += 1 if _recall_one(entry) else 0
	return n


## The ship wants to jump (its brain withdraws, D12.10): its craft are called home and the jump waits for them, up to
## `wait_s`, then leaves the rest. True once it may go.
func ready_to_jump() -> bool:
	set_physics_process(true)
	if not jumping:
		jumping = true
		waited_s = 0.0
		_clear_queues()
		recall_all()
	if not HangarRules.may_leave(_out.size(), waited_s, options):
		return false
	left_behind += _out.size()
	abandon()
	for key: int in _out.keys():
		_forget(key)
	return true


## The roll-up door of `bay` (null when it has none).
func door_of(bay: String) -> BayDoorNode:
	return ship.bay_doors.get(bay) as BayDoorNode


## The lift of `bay` (null when it has none).
func lift_of(bay: String) -> BayElevator:
	return _bays[bay]["lift"] as BayElevator if _bays.has(bay) else null


## The bays it launches from, in hardpoint order.
func bay_names() -> PackedStringArray:
	return PackedStringArray(_bays.keys())


## The craft out, each `{ship, combatant, type}`.
func craft_out() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _out.values():
		out.append(entry)
	return out


func _physics_process(delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	_clock_s += delta
	super._physics_process(delta)
	set_physics_process(true)
	for lift: BayElevator in _moving:
		_advance_lift(lift, delta)  # every tick: a lift moves in step with the rows it carries
	_pump_s += delta
	if _pump_s >= PUMP_S:
		for bay: String in _bays:
			_pump(bay, _pump_s)
		_pump_s = 0.0
		_decide_s += PUMP_S
		if _decide_s >= DECIDE_S:
			_decide(_decide_s)
			_decide_s = 0.0
		if _out.is_empty() and _held.is_empty() and queued_count() == 0 and _all_idle():
			# Nobody out, nothing to send, every bay at rest: it sleeps until a threat, an order or a stock wakes it.
			_all_home()
			_push_launching()
			set_physics_process(false)
	ticks += 1
	tick_us += float(Time.get_ticks_usec() - t0)


# Back to work, deciding at once (a sleeping hangar heard of a threat or was stocked).
func _wake() -> void:
	set_physics_process(true)
	_decide_s = DECIDE_S
	_pump_s = PUMP_S


# Everyone is home: the next fight starts with the first wing again.
func _all_home() -> void:
	wings_out = 0
	wing_fighters = 0
	wing_losses = 0
	recalling = false
	_fought = threat_fighters + threat_warships > 0


# Whether every bay is at rest: nothing queued, its door shut, its lift up.
func _all_idle() -> bool:
	for bay: String in _bays:
		var door: BayDoorNode = door_of(bay)
		var lift: BayElevator = _bays[bay]["lift"]
		if not (_bays[bay]["queue"] as Array).is_empty() or (door != null and door.amount > 0.0) or (lift != null and not lift.is_free()):
			return false
	return true


# The wings and the recovery, a couple of times a second.
func _decide(dt: float) -> void:
	drop_gone_rows()
	_drop_gone()
	if not has_power():
		_clear_queues()
		return
	var threat_now: float = HangarRules.threat(threat_fighters, threat_warships, float(options["warship_weight"]))
	if jumping:
		waited_s += dt
	if threat_now > 0.0:
		calm_for_s = 0.0
		_fought = true
		recalling = jumping
	elif _fought:
		calm_for_s += dt
		if auto and not recalling and not _out.is_empty() and HangarRules.fight_over(calm_for_s, options):
			recall_all()
	for entry: Dictionary in _out.values():
		var hull: Damageable = Damageable.of(entry["ship"])
		if recalling or (auto and hull != null and HangarRules.goes_home(hull.hull.fraction(), options)):
			_recall_one(entry)
	if _out.is_empty() and queued_count() == 0 and not is_launching():
		_all_home()
	_push_launching()
	if not auto or jumping or recalling:
		return
	if wings_out < (options["wings"] as Array).size() and fighters_aboard() > 0 and (HangarRules.first_wing_due(threat_now, wings_out)
			or (wings_out > 0 and queued_count() == 0
			and HangarRules.next_wing_due(threat_now, threat_at_last, wing_fighters, wing_losses, options))):
		launch_wing()


# One bay a tick: its door, its lift and its next launch.
func _pump(bay: String, delta: float) -> void:
	var state: Dictionary = _bays[bay]
	var queue: Array = state["queue"]
	var door: BayDoorNode = door_of(bay)
	var lift: BayElevator = state["lift"]
	if queue.is_empty() and int(held_in_bay.get(bay, 0)) == 0 and (door == null or door.amount <= 0.0) \
			and (lift == null or lift.is_free()):
		return  # at rest
	if not queue.is_empty() and (not has_power() or not ship.bay_works(bay)):
		refused += queue.size()
		_clear_queue(bay)  # a dark ship or a lost bay launches nothing (Q72)
	if door != null:
		if not queue.is_empty() or _bay_busy(bay):
			state["idle_s"] = 0.0
			ship.set_bay_door(bay, true)
		else:
			state["idle_s"] = float(state["idle_s"]) + delta
			if door.is_open() and float(state["idle_s"]) >= DOOR_IDLE_S:
				ship.set_bay_door(bay, false)
	var door_ready: bool = door == null or door.amount >= 1.0
	if lift != null:
		_pump_lift(bay, state, lift, delta, door_ready)
		return
	state["since_s"] = float(state["since_s"]) + delta
	if queue.is_empty() or not door_ready or float(state["since_s"]) < launch_gap_s or _returning_near(bay):
		return
	var type: StringName = queue[0]
	for i: int in state["cradles"]:
		if cradles.states[i] == CarrierCradles.State.FREE and cradles.takes(i, type):
			queue.pop_front()
			state["since_s"] = 0.0
			_send(type, i)
			return


# One tick of a moving lift: down on the deck it takes its trip aboard and rises with it the same tick, so the lift and the
# craft's rows move together.
func _advance_lift(lift: BayElevator, delta: float) -> void:
	var ended: int = lift.advance(delta)
	if ended == BayElevator.State.DOWN:
		var state: Dictionary = _bays[_lift_bay[lift]]
		var queue: Array = state["queue"]
		for i: int in state["cradles"]:
			if not queue.is_empty() and cradles.takes(i, queue[0]):
				_send(queue.pop_front(), i)
		lift.rise()
	elif lift.is_free():
		_moving.erase(lift)


# Starts a lift moving (`move` is its fetch or lower): it is stepped every tick until it is back at the floor.
func _start_lift(lift: BayElevator, move: Callable) -> void:
	if bool(move.call()) and not _moving.has(lift):
		_moving.append(lift)


# A lift bay at rest: it sinks empty for a trip, and takes craft drawn in down in a group.
func _pump_lift(bay: String, state: Dictionary, lift: BayElevator, delta: float, door_ready: bool) -> void:
	var queue: Array = state["queue"]
	var aboard: Array = state["aboard"]
	if not lift.is_free():
		return
	if not aboard.is_empty():
		state["gather_s"] = float(state["gather_s"]) + delta
		if not _capturing_into(bay) and (aboard.size() >= (state["cradles"] as Array).size()
				or float(state["gather_s"]) >= LIFT_GATHER_S):
			for craft: Ship in aboard:
				begin_lower(craft)
			aboard.clear()
			_start_lift(lift, lift.lower)
		return
	if not queue.is_empty() and door_ready and _clock_s - float(state["lifted_at"]) >= LIFT_CLEAR_S and _lanes_free(state) \
			and not _returning_near(bay):
		_start_lift(lift, lift.fetch)


# Whether every lane of a bay is free: nothing launching from it or drawn into it holds one.
func _lanes_free(state: Dictionary) -> bool:
	for i: int in state["cradles"]:
		if cradles.states[i] != CarrierCradles.State.FREE:
			return false
	return true


# Takes a craft of `type` from the pool and sends it out of cradle `index`; it goes back to stock when none can come.
func _send(type: StringName, index: int) -> void:
	var combatant: Combatant = _acquire(type, index)
	if combatant != null:
		combatant.ship.tier_exempt = true  # its carrier's while out: parked in the tier it would read as lost (as CarrierJumps')
	if combatant == null or not launch_ship(combatant.ship, index):
		refused += 1
		stock[type] = int(stock.get(type, 0)) + 1
		if combatant != null:
			ShipPool.for_tree(get_tree()).release(combatant)
		return
	sent += 1
	var lost: Callable = _on_craft_destroyed.bind(combatant.ship.get_instance_id())
	_out[combatant.ship.get_instance_id()] = {"ship": combatant.ship, "combatant": combatant, "type": type, "lost": lost}
	combatant.damageable.destroyed.connect(lost)
	var fold: WingFoldNode = WingFoldNode.attach(combatant.ship)
	if fold != null:
		fold.snap(true)  # it waited in the bay folded


func _acquire(type: StringName, index: int) -> Combatant:
	var pool: ShipPool = ShipPool.for_tree(get_tree())
	var world: WorldFrame = WorldFrame.of(ship)
	if pool == null or world == null or pool.free_count(type) <= 0:
		return null
	var body: RigidBody3D = carrier()
	var at: UniversePos = world.to_universe(body.global_transform * cradles.positions[index])
	var callsign: String = ShipCatalog.entry_text(type, "callsign").capitalize() if not _is_fighter(type) else \
			HangarRules.callsign(ship.faction, wings_sent - 1 if wings_sent > 0 else 0)
	var label: String = pool.next_name(callsign if not callsign.is_empty() else "Craft")
	var made: Dictionary = BrainFactory.from_behaviour(_behaviour(type), at, hash([label, String(ship.name), sent]))
	if not bool(made.get("ok", false)):
		return null
	var combatant: Combatant = pool.acquire(label, at, body.global_basis * cradles.bases[index], body.linear_velocity,
			made["brain"] as PilotBrain, type)
	if combatant != null and combatant.faction != ship.faction:
		_give_faction(combatant, ship.faction)
	return combatant


# A launched craft's pilot: its catalogue profile, a civilian shuttle holding where it is let go.
static func _behaviour(type: StringName) -> Dictionary:
	var profile: String = ShipCatalog.entry_text(type, "ai_profile")
	if profile.is_empty() or profile == "civilian":
		return {"type": "idle", "hold": false}
	return {"type": "ai", "profile": profile}


# A pooled ship flies for the carrier's side: its hull, marker, guns, targeting and pilot all read it (as the bench's sides).
static func _give_faction(c: Combatant, faction: StringName) -> void:
	c.faction = faction
	c.targetable.faction = faction
	c.damageable.faction = faction
	c.cannon.faction = faction
	c.ship.targeting.system.own_faction = faction


# Queues one craft of `type` in the bay that takes it with the shortest queue and still works; out of stock with it.
func _queue_one(type: StringName) -> bool:
	if not has_power() or int(stock.get(type, 0)) <= 0 or ShipPool.for_tree(get_tree()) == null:
		return false
	var best: String = ""
	for bay: String in _bays:
		var takes: bool = false
		for i: int in _bays[bay]["cradles"]:
			takes = takes or cradles.takes(i, type)
		if not takes or not ship.bay_works(bay):
			continue
		if best.is_empty() or (_bays[bay]["queue"] as Array).size() < (_bays[best]["queue"] as Array).size():
			best = bay
	if best.is_empty():
		refused += 1
		return false
	(_bays[best]["queue"] as Array).append(type)
	stock[type] = int(stock[type]) - 1
	return true


# Calls one craft out to the bay lane that takes it with the fewest others already coming, nearest first.
func _recall_one(entry: Dictionary) -> bool:
	var craft: Ship = entry["ship"]
	if not is_instance_valid(craft) or is_handling(craft) or not has_power():
		return false
	var type: StringName = entry["type"]
	var local: Vector3 = carrier().global_transform.affine_inverse() * craft.global_position
	var coming: Dictionary = {}
	for held: Dictionary in _held.values():
		coming[int(held["cradle"])] = int(coming.get(int(held["cradle"]), 0)) + 1
	var best: int = -1
	var best_key: float = INF
	for i: int in cradles.count():
		if not cradles.takes(i, type) or not ship.bay_works(cradles.bays[i]):
			continue
		var key: float = float(coming.get(i, 0)) * 1e7 + cradles.approach_point(i).distance_to(local)
		if key < best_key:
			best = i
			best_key = key
	return best >= 0 and recall_to(craft, best)


# Whether a returning craft at its bay's approach point may come in now: the bay works and is free, its door is open, its
# wings are folded, and a lift bay's lift is at the floor and not about to go down.
func _may_enter(craft: Ship, index: int) -> bool:
	var bay: String = cradles.bays[index]
	if not has_power() or not ship.bay_works(bay) or cradles.states[index] != CarrierCradles.State.FREE:
		return false
	var door: BayDoorNode = door_of(bay)
	if door != null:
		_bays[bay]["idle_s"] = 0.0
		ship.set_bay_door(bay, true)
	var fold: WingFoldNode = WingFoldNode.attach(craft)
	if fold != null:
		fold.set_folded(true)
	var lift: BayElevator = _bays[bay]["lift"]
	var lift_ok: bool = lift == null or lift.is_free()
	return (door == null or door.amount >= 1.0) and (fold == null or fold.is_folded()) and lift_ok


# Whether a craft of the bay is launching, coming in, or close enough on its way back that the door should be open.
func _bay_busy(bay: String) -> bool:
	if int(held_in_bay.get(bay, 0)) == 0:
		return false
	var lead_m: float = float(options["door_lead_m"])
	for entry: Dictionary in _held.values():
		var i: int = int(entry["cradle"])
		if cradles.bays[i] != bay:
			continue
		if not bool(entry["flying"]):
			return true
		var craft: Ship = entry["ship"]
		var mouth: Vector3 = carrier().global_transform * cradles.approach_point(i)
		if is_instance_valid(craft) and craft.global_position.distance_to(mouth) < lead_m:
			return true
	return false


# Whether a craft coming home to `bay` is near its mouth: its launches wait, so nothing leaves into a craft waiting to come in.
func _returning_near(bay: String) -> bool:
	if int(held_in_bay.get(bay, 0)) == 0:
		return false
	for entry: Dictionary in _held.values():
		var i: int = int(entry["cradle"])
		if cradles.bays[i] != bay or not bool(entry["returning"]):
			continue
		var craft: Ship = entry["ship"]
		if not bool(entry["flying"]) or (is_instance_valid(craft) and craft.global_position.distance_to(
				carrier().global_transform * cradles.approach_point(i)) < RETURN_CLEAR_M):
			return true
	return false


# Whether a craft is being drawn into `bay` now.
func _capturing_into(bay: String) -> bool:
	for key: int in _held.keys():
		var entry: Dictionary = _held[key]
		if cradles.bays[int(entry["cradle"])] == bay and _rows.phase_of(key) == PHASE_CAPTURE:
			return true
	return false


# Craft out that were destroyed or left play some other way are no longer the hangar's.
func _drop_gone() -> void:
	for key: int in _out.keys():
		var craft: Ship = _out[key]["ship"]
		if not is_instance_valid(craft) or not craft.is_inside_tree() or (not craft.is_visible_in_tree() and not is_handling(craft)):
			_forget(key)


# The hangar lets go of craft `key` for good: it is not listened to any more.
func _forget(key: int) -> void:
	var entry: Dictionary = _out.get(key, {})
	_out.erase(key)
	var combatant: Combatant = entry.get("combatant") as Combatant
	if combatant != null and is_instance_valid(combatant.damageable) and combatant.damageable.destroyed.is_connected(entry["lost"]):
		combatant.damageable.destroyed.disconnect(entry["lost"])


func _clear_queues() -> void:
	for bay: String in _bays:
		_clear_queue(bay)


# Puts a bay's queued craft back in the stock.
func _clear_queue(bay: String) -> void:
	for type: StringName in _bays[bay]["queue"]:
		stock[type] = int(stock.get(type, 0)) + 1
	(_bays[bay]["queue"] as Array).clear()


func _next_fighter_type() -> StringName:
	for type: Variant in stock:
		if _is_fighter(type) and int(stock[type]) > 0:
			return type
	return &""


static func _is_fighter(type: StringName) -> bool:
	return ShipCatalog.entry_text(type, "role") == "fighter"


# Tells the brain whether it is launching, when that changes: it holds its course meanwhile.
func _push_launching() -> void:
	var now: bool = is_launching()
	if now == _launching:
		return
	_launching = now
	var sim: SimCore = SimCore.for_tree(get_tree())
	if sim != null:
		sim.core.capital_set_launching(ship.get_instance_id(), now)


func _add_lift_nodes() -> void:
	for raw: Variant in ship.hardpoints().get("bays", []):
		var bay: Dictionary = raw
		var lift: BayElevator = lift_of(str(bay.get("name", "")))
		if lift == null:
			continue
		var forward: Vector3 = BayBerths._vec(bay.get("forward"), Vector3.FORWARD).normalized()
		var up: Vector3 = BayBerths._vec(bay.get("up"), Vector3.UP).normalized()
		var abreast: int = int(options.get("elevator_abreast", 3))
		var rows: int = maxi((_bays[str(bay["name"])]["cradles"] as Array).size() / maxi(abreast, 1), 1)
		var width: float = minf(BayBerths.LANE_SPACING_M * float(abreast), float((bay.get("mouth_m", [60.0]) as Array)[0]) - 2.0)
		var length: float = float(options.get("elevator_row_gap_m", 14.0)) * float(rows) + 2.0
		var basis := Basis(forward.cross(up).normalized(), up, -forward)
		add_child(BayElevatorNode.create(lift, BayBerths._vec(bay.get("elevator"), Vector3.ZERO), basis, Vector2(width, length),
				float(bay.get("elevator_travel_m", 30.0))))


func _on_launched(craft: Ship) -> void:
	var fold: WingFoldNode = WingFoldNode.of(craft)
	if fold != null:
		fold.set_folded(false)  # clear of the bay: the wings spread


# A trip reached the floor: its lanes are free for the next one, which sinks once these have run clear.
func _on_lifted(craft: Ship, index: int) -> void:
	free_lane(craft)
	_bays[cradles.bays[index]]["lifted_at"] = _clock_s


# The pool gets the stock's worth of ships once the carrier is in play (not for a hangar emptied straight after spawning).
func _prepare_when_placed() -> void:
	if not _pool_ready and not stock.is_empty() and is_inside_tree():
		_pool_ready = true
		prepare_pool()


func _on_in_bay(craft: Ship, index: int) -> void:
	var state: Dictionary = _bays[cradles.bays[index]]
	if (state["aboard"] as Array).is_empty():
		state["gather_s"] = 0.0
	(state["aboard"] as Array).append(craft)


# A craft home: off its cradle and back to its pool, one more aboard.
func _on_docked(craft: Ship) -> void:
	var index: int = _on_cradle.find(craft)
	if index >= 0:
		take_from(index)
	var entry: Dictionary = _out.get(craft.get_instance_id(), {})
	_forget(craft.get_instance_id())
	var type: StringName = entry.get("type", &"")
	if type != &"":
		stock[type] = int(stock.get(type, 0)) + 1
	recoveries += 1
	var fold: WingFoldNode = WingFoldNode.of(craft)
	if fold != null:
		fold.snap(false)
	var pool: ShipPool = ShipPool.for_tree(get_tree())
	var combatant: Combatant = entry.get("combatant") as Combatant
	if pool != null and combatant != null:
		pool.release(combatant)
	recovered.emit(craft, type)


func _on_craft_destroyed(_info: HitInfo, key: int) -> void:
	if _held.has(key):
		_let_go(key, true)  # the rows place bodies natively: a dead craft leaves them at once
	if _out.has(key):
		_forget(key)
		wing_losses += 1


# The carrier died: what was aboard died with it (Q28).
func _on_hull_destroyed(_info: HitInfo) -> void:
	_clear_queues()
	stock.clear()
