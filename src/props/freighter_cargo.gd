class_name FreighterCargo
extends Node3D
## A Saturn's cargo (its pods, or a tanker's tanks) carried between it and the station's cargo bay by maintenance bots (M7-T30;
## T10's `FreighterPods` flew the pods in by themselves). The Saturn's hull is one mesh, so while its cargo is off its hull is
## hidden and its break-up chunks stand in: the parts that are not cargo ride the ship, and each pod is a node of its own, on the
## ship while it sits on the hull and in the station's frame while the bots carry it (`CargoFerryJob`). Unloading leaves the
## Saturn without its pods (`restore` when it goes back to its pool); loading puts the hull back once the last pod is on.
##
## Ambient: the pods have no body, target or row, and the freighter's mass and hit volumes stay as they were. A few nodes for a
## few minutes, so this is GDScript (`CLAUDE.md`'s split). Runs after the bots each tick, so a pod and its bots move together.

const NODE_NAME: String = "FreighterCargo"
## After the bots' fleet in the physics tick.
const PRIORITY: int = 50

signal pod_done(pod_name: String)
signal finished

var ship: Ship = null
var job: CargoFerryJob = null
var loading: bool = false
## The crew's nodes in the station's bot fleet while the job runs.
var crew_bots: Array[MaintenanceBot] = []
var fleet: BotFleet = null
var restored: bool = false

var _riding: Array[MeshInstance3D] = []
# name -> {node, offset}
var _pods: Dictionary = {}
var _frame: Node3D = null


## Whether a break-up chunk is cargo the bots carry.
static func is_cargo(chunk_name: String) -> bool:
	return chunk_name.begins_with("pod") or chunk_name.begins_with("tank")


## The freighter's break-up chunks as boxes in its own frame, `{name, box, mesh, offset}` (only those with a mesh).
static func chunk_boxes(freighter: Ship) -> Array[Dictionary]:
	return chunk_boxes_of(freighter.spec.asset_id, freighter.get_hardpoints())


## The same for the hull `asset_id` (its hardpoints read from its asset when not given).
static func chunk_boxes_of(asset_id: String, hardpoints: Hardpoints = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir: String = ShipSpec.ASSET_ROOT.path_join(asset_id)
	if hardpoints == null:
		hardpoints = Hardpoints.load_file(dir.path_join("hardpoints.json"))
	if hardpoints == null:
		return out
	for entry: Dictionary in hardpoints.chunks:
		var mesh: Mesh = MeshAssets.chunk_mesh(dir, String(entry.get("mesh", ""))) if entry.has("mesh") else null
		if mesh == null:
			continue
		var offset: Vector3 = entry.get("offset", Vector3.ZERO)
		var box: AABB = mesh.get_aabb()
		out.append({"name": String(entry.get("name", "")), "box": AABB(box.position + offset, box.size), "mesh": mesh, "offset": offset})
	return out


## Takes `freighter`'s cargo off its hull for the bots: its pods sit on it (`aboard`, to unload) or are in the bay (to load). Null
## for a hull without cargo chunks.
static func attach(freighter: Ship, aboard: bool) -> FreighterCargo:
	var cargo := FreighterCargo.new()
	cargo.name = NODE_NAME
	cargo.ship = freighter
	cargo.loading = not aboard
	cargo.process_physics_priority = PRIORITY
	for entry: Dictionary in chunk_boxes(freighter):
		var instance := MeshInstance3D.new()
		instance.name = String(entry["name"]).to_pascal_case()
		instance.mesh = entry["mesh"]
		instance.position = entry["offset"]
		instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
		cargo.add_child(instance)
		if is_cargo(String(entry["name"])):
			instance.visible = aboard
			cargo._pods[String(entry["name"])] = {"node": instance, "offset": entry["offset"], "aboard": aboard, "told": false}
		else:
			cargo._riding.append(instance)
	if cargo._pods.is_empty():
		cargo.free()
		return null
	freighter.add_child(cargo)
	freighter.hull.visible = false
	return cargo


## Sends the station's bots to carry the cargo, the Saturn where it is now (or, `early`, still on its way to the hold point: the
## bots go out now and `berth` plans again from where it stops). "" or why not (no bots, no plan).
func start(station: Station, early: bool = false) -> String:
	if station == null or station.bots == null:
		return "the station has no maintenance bots"
	fleet = station.bots
	_frame = fleet.frame_parent()
	var boxes: Array[Dictionary] = chunk_boxes(ship)
	var collision: Array[Dictionary] = Hardpoints.load_collision_only(
			ShipSpec.ASSET_ROOT.path_join(ship.spec.asset_id).path_join("hardpoints.json"))
	# The station's own frame: its frame piece is drawn closer than it is while the station is far off.
	var plan: CargoFerryPlan = CargoFerryPlan.for_freighter(station.hardpoints.cargo_bay, boxes, collision,
			null if early else station.to_local(ship.global_position))
	if not plan.valid:
		return plan.error
	job = CargoFerryJob.create(plan, loading)
	if early:
		for pod: FerryPod in job.pods:
			pod.berthed = false
	for m: BotFerryMotion in job.crew:
		crew_bots.append(fleet.add_ferry_bot(m))
	return ""


## The freighter is at its hold point: the job is planned again from exactly where it stopped, and the pods may move.
func berth(station: Station) -> void:
	if job == null:
		return
	var boxes: Array[Dictionary] = chunk_boxes(ship)
	var collision: Array[Dictionary] = Hardpoints.load_collision_only(
			ShipSpec.ASSET_ROOT.path_join(ship.spec.asset_id).path_join("hardpoints.json"))
	var plan: CargoFerryPlan = CargoFerryPlan.for_freighter(station.hardpoints.cargo_bay, boxes, collision,
			station.to_local(ship.global_position))
	if plan.valid:
		job.replan(plan)
	job.berth()


## Pods carried all the way so far, and in all.
func pods_done() -> int:
	return job.pods_done() if job != null else 0


func pod_count() -> int:
	return _pods.size()


func busy() -> bool:
	return job != null and not job.done()


func _physics_process(_delta: float) -> void:
	if job == null or restored:
		return
	for pod: FerryPod in job.pods:
		_place(pod)
	var all_done: bool = job.update()
	for pod: FerryPod in job.pods:
		var entry: Dictionary = _pods[pod.trip.pod_name]
		if pod.done() and not bool(entry["told"]):
			entry["told"] = true
			pod_done.emit(pod.trip.pod_name)
	if all_done:
		_remove_crew()
		finished.emit()
		if loading:
			restore()  # the last pod is on: the hull is whole again


# A pod on the hull rides the ship; one being carried is in the station's frame where the trip puts it.
func _place(pod: FerryPod) -> void:
	var entry: Dictionary = _pods[pod.trip.pod_name]
	var node: MeshInstance3D = entry["node"]
	var aboard: bool = pod.done() if loading else (pod.state == FerryPod.State.WAITING and pod.s <= FerryPod.EPS_M)
	entry["aboard"] = aboard
	if aboard:
		if node.get_parent() != self:
			node.reparent(self, false)
			node.transform = Transform3D(Basis.IDENTITY, entry["offset"])
			node.reset_physics_interpolation()
		return
	var fresh: bool = node.get_parent() != _frame
	if fresh:
		node.reparent(_frame, false)
	node.transform = pod.pose()
	if fresh:
		node.reset_physics_interpolation()
	node.visible = not pod.inside_wall()


func _process(_delta: float) -> void:
	if restored:
		return
	# The ship's own LOD switch shows the hull again when it comes back from a far dot: the stand-ins follow it.
	var far: bool = ship.is_far_dot()
	ship.hull.visible = false
	for part: MeshInstance3D in _riding:
		part.visible = not far
	for entry: Dictionary in _pods.values():
		var node: MeshInstance3D = entry["node"]
		if node.get_parent() == self:
			node.visible = bool(entry["aboard"]) and not far


## Puts the hull back and removes the stand-ins, the pods and the bots still out.
func restore() -> void:
	_remove_crew()
	for entry: Dictionary in _pods.values():
		var node: Node = entry["node"]
		if is_instance_valid(node) and node.get_parent() != self:
			node.queue_free()
	if is_instance_valid(ship):
		ship.hull.visible = not ship.is_far_dot()
	restored = true
	queue_free()


func _remove_crew() -> void:
	if fleet != null and is_instance_valid(fleet):
		for bot: MaintenanceBot in crew_bots:
			fleet.remove_ferry_bot(bot)
	crew_bots.clear()
