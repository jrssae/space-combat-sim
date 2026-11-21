class_name MissionFacts
extends RefCounted
## Numbers the game keeps about a mission's run for its script (M8 D79): counted from the scene's own signals and written into
## the `MissionWorld` each tick, where `TriggerSpec.fact` and `MissionApi.fact` read them. `MissionStage` owns it.

## Gate jumps the player flew; bolts raiders landed on anything; Starfuries (the player apart), civilians and nav buoys
## destroyed; raider capitals destroyed, and those a raid brought that are in play now (`MissionStage` counts them); Control's
## docking offers; the player's repairs; tour stops shown; the player's hull, 0 to 1. The player's state, each 1 or 0 (M8-T33's
## play-test): auto-track holds the nose on a target; the view is the cockpit's; the targeted gate takes a jump request now.
const NAMES: Array[StringName] = [&"gate_jumps", &"hostile_hits", &"starfuries_lost", &"civilians_lost", &"buoys_lost",
		&"capitals_destroyed", &"capitals_in_play", &"dock_offers", &"repairs", &"tour_stops", &"player_hull", &"auto_track",
		&"cockpit_view", &"gate_offer"]
## The facts read from the scene each tick instead of counted.
const READ: Array[StringName] = [&"player_hull", &"capitals_in_play", &"auto_track", &"cockpit_view", &"gate_offer"]

var main: Main = null
var counts: Dictionary = {}  # StringName -> int
var _jumps_before: int = 0


func setup(p_main: Main) -> void:
	main = p_main
	for fact: StringName in NAMES:
		if not READ.has(fact):
			counts[fact] = 0
	_jumps_before = main.gates.jump.completed if main.gates != null else 0
	(main.get_node(^"Combat/HitResolver") as HitResolver).hit_resolved.connect(_on_hit)
	main.director.ship_destroyed.connect(_on_ship_destroyed)
	main.director.buoy_destroyed.connect(func(_buoy: NavBuoy, _info: HitInfo) -> void: counts[&"buoys_lost"] += 1)
	main.director.capital_destroyed.connect(func(_capital: CapitalBody, _info: HitInfo) -> void: counts[&"capitals_destroyed"] += 1)
	if main.docking != null:
		main.docking.dock_offered.connect(func() -> void: counts[&"dock_offers"] += 1)
		main.docking.player_relaunched.connect(func() -> void: counts[&"repairs"] += 1)
	if main.tours != null:
		main.tours.point_started.connect(func(_point: String, _caption: String) -> void: counts[&"tour_stops"] += 1)


## Writes this tick's numbers into `snapshot`.
func refresh(snapshot: MissionWorld) -> void:
	if main == null or not is_instance_valid(main):
		return
	if main.gates != null:
		counts[&"gate_jumps"] = main.gates.jump.completed - _jumps_before
	for fact: StringName in counts:
		snapshot.set_fact(fact, float(counts[fact]))
	var hull: float = main.combatant.damageable.hull.fraction() if main.player_alive and main.combatant != null else 0.0
	snapshot.set_fact(&"player_hull", hull)
	var flying: bool = main.player_alive and main.ship != null
	snapshot.set_fact(&"auto_track", 1.0 if flying and main.ship.get_flight_output().tracking else 0.0)
	snapshot.set_fact(&"cockpit_view", 1.0 if main.camera_rig != null and main.camera_rig.mode == CameraRig.Mode.COCKPIT else 0.0)
	snapshot.set_fact(&"gate_offer", 1.0 if flying and main.gates != null and main.gates.can_request_jump() else 0.0)


func _on_hit(info: HitInfo) -> void:
	if info.cause == HitInfo.CAUSE_BOLT and info.faction == Factions.RAIDERS:
		counts[&"hostile_hits"] += 1


func _on_ship_destroyed(combatant: Combatant, _info: HitInfo) -> void:
	if combatant == main.combatant:
		return
	if combatant.civilian:
		counts[&"civilians_lost"] += 1
	elif main.ships.type_of(combatant) == ShipPool.ALLY_TYPE:
		counts[&"starfuries_lost"] += 1
