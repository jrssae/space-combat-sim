class_name RebaseFight
extends RefCounted
## Test fixture (M3-T14, AC21): runs a live main scene with the World's automatic rebase threshold forced down, so the world
## rebases every second or so in the middle of whatever the scene does, and checks every tick and every frame that the
## rebases leave no trace. Later tasks prove their own systems rebase-safe (routes, guard posts, rams) with one line, once
## their scene is set up and running:
##
##     var fight: RebaseFight = await RebaseFight.run(self, main, 20.0)
##
## `run` lowers `World.auto_rebase_distance_m` to `threshold_m`, gives the player `cruise_mps` along its nose when it is slower
## (0: leave the player to the caller), runs for `sim_s` seconds of sim time or until `until` returns true, puts the threshold
## back, and asserts on `test`. With `rebase_every_s` > 0 it also forces a rebase of `FORCED_REBASE_M` (in a direction that
## turns each time) at the start of a tick whenever that long has passed without one, so a scene whose player sits still
## (a route or guard test: `cruise_mps` 0) still rebases. Pass `threshold_m` above `FORCED_REBASE_M` with it: below that,
## the automatic rebase re-centres on the player later in the same tick and only the nodes ticking in between see the shift.
## It asserts:
## - the world rebased at least every `MAX_GAP_S` (2 s) of sim time, from the start to the end;
## - no ship, prop or bolt moved in universe terms across a tick by more than its own motion plus `JUMP_SLACK_M` (1 m);
## - no hit landed along a jump: each bolt hit lies on the path its bolt flew that tick and on its target's hull, each ram on
##   the hull it hurt;
## - every rebase moved the chase camera with the player (to 1 mm), and every frame the chase camera kept its offset from the
##   ship as drawn (to 1 cm with the default rigid camera);
## - every frame the HUD's reference range is the 64-bit universe distance from the player to `Main.reference_point()`;
## - in the first frame after a rebase every visible, physics-interpolated node of World (and the cockpit camera's pivot) is
##   drawn at its tick pose, to `SNAP_TOL_M` (the world stalls together for that tick: none is left blending, across the jump
##   or otherwise; silent voices are not checked, nothing hears them);
## - after every rebase, the structure: each object under World (a child of World or of one of its plain containers) is in
##   `world_shiftable` or below a shiftable node, every `top_level` node below World is in the group itself, and no particles
##   below World are emitted in global space (a rebase cannot move what they already emitted; the M3-T14 sparks bug).
## The counts (`rebases`, `hits`, `rams`, `kills`) and worst cases stay on the returned object for the caller's own asserts
## (the waves clear, bolts hit), and `summary()` is one line for `gut.p`. Rebases must come from the scene's own ticks (the
## automatic one or a console statement), not from the test between frames. A `Watch` node samples during the run (at the
## start of every tick and the end of every frame) and is freed when it ends.

const MAX_GAP_S: float = 2.0
const JUMP_SLACK_M: float = 1.0
const CAMERA_TOL_M: float = 0.01
const CAMERA_REBASE_TOL_M: float = 0.001
const HUD_TOL_M: float = 0.05
const SNAP_TOL_M: float = 0.01
## Size of a forced rebase (`rebase_every_s`), m.
const FORCED_REBASE_M: float = 1000.0
## Failures kept for the message (all are counted).
const MAX_REPORTED: int = 8

## Physics ticks run, rebases seen, bolt hits and rams resolved, raiders killed, over the run.
var ticks: int = 0
var rebases: int = 0
var hits: int = 0
var hits_in_rebase_ticks: int = 0
var rams: int = 0
var kills: int = 0
## Longest sim time without a rebase (start and end included), s.
var max_gap_s: float = 0.0
## `World.last_rebase_us` after each tick with a rebase, us (wall clock; the last rebase of the tick, end-of-tick reset included).
var rebase_us: PackedInt64Array = PackedInt64Array()
## Worst cases: universe jump past the bound (m; negative = inside it), chase camera change per frame and at a rebase (m), HUD
## range error (m), drawn-versus-actual gap past a node's tick of motion in the frame after a rebase (m).
var worst_jump_m: float = -INF
var worst_camera_m: float = 0.0
var worst_camera_rebase_m: float = 0.0
var worst_hud_m: float = 0.0
var worst_snap_m: float = 0.0
var jumps_checked: int = 0
var frames_checked: int = 0
var snaps_checked: int = 0
## Rebases forced by `rebase_every_s`; ticks with a rebase (two can share one: a forced or console rebase and the automatic
## one), and structure checks run (one after each of those ticks).
var forced_rebases: int = 0
var rebase_ticks: int = 0
var structure_checks: int = 0
var failures_total: int = 0
var failures: PackedStringArray = PackedStringArray()


## Runs `main` for `sim_s` seconds of sim time (or until `until` returns true) with the rebase threshold at `threshold_m`, and
## asserts the invariants above on `test`. Returns the counts and worst cases.
static func run(test: GutTest, main: Main, sim_s: float, until: Callable = Callable(), threshold_m: float = 40.0,
		cruise_mps: float = 60.0, rebase_every_s: float = 0.0) -> RebaseFight:
	var fight := RebaseFight.new()
	var threshold_before: float = main.world.auto_rebase_distance_m
	main.world.auto_rebase_distance_m = threshold_m
	if cruise_mps > 0.0 and main.ship.linear_velocity.length() < cruise_mps:
		main.ship.linear_velocity = main.ship.forward() * cruise_mps
	var watch := Watch.new(fight, main)
	watch.rebase_every_s = rebase_every_s
	test.add_child(watch)
	await watch.run_for(sim_s, until)
	test.remove_child(watch)
	watch.free()
	main.world.auto_rebase_distance_m = threshold_before
	fight._assert_on(test)
	return fight


## One line with the counts and the worst cases.
func summary() -> String:
	return ("%d ticks, %d rebases (%d forced; longest gap %.2f s; cost min %d, median %d, max %d us), %d bolt hits (%d in rebase ticks), %d rams, %d kills; worst: universe jump %+.3f m past its motion over %d checks, chase camera %.4f m per frame (%.4f m at a rebase) over %d frames, HUD range %.4f m, drawn off its tick pose %.4f m over %d rebase frames; %d structure checks"
			% [ticks, rebases, forced_rebases, max_gap_s, min_rebase_us(), median_rebase_us(), max_rebase_us(), hits, hits_in_rebase_ticks, rams,
			kills, worst_jump_m, jumps_checked, worst_camera_m, worst_camera_rebase_m, frames_checked, worst_hud_m, worst_snap_m, snaps_checked,
			structure_checks])


func median_rebase_us() -> int:
	var sorted: PackedInt64Array = rebase_us.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2] if not sorted.is_empty() else 0


func min_rebase_us() -> int:
	var sorted: PackedInt64Array = rebase_us.duplicate()
	sorted.sort()
	return sorted[0] if not sorted.is_empty() else 0


func max_rebase_us() -> int:
	var sorted: PackedInt64Array = rebase_us.duplicate()
	sorted.sort()
	return sorted[sorted.size() - 1] if not sorted.is_empty() else 0


func _assert_on(test: GutTest) -> void:
	var line: String = summary()
	test.assert_gt(rebases, 0, "the world rebased (%s)" % line)
	test.assert_lte(max_gap_s, MAX_GAP_S, "at least every %.0f s of sim time (%s)" % [MAX_GAP_S, line])
	test.assert_eq(failures_total, 0, "nothing left a trace of a rebase: %s" % "; ".join(failures))
	test.assert_gt(jumps_checked, 0, "universe positions were compared")
	test.assert_gt(frames_checked, 0, "frames were checked")
	test.assert_eq(structure_checks, rebase_ticks, "the structure was checked after every rebase tick")


func _fail(message: String) -> void:
	failures_total += 1
	if failures.size() < MAX_REPORTED:
		failures.append("tick %d: %s" % [ticks, message])


static func _speed_of(node: Node3D) -> float:
	var body := node as RigidBody3D
	if body != null:
		return body.linear_velocity.length()
	var velocity: Variant = node.get(&"velocity")
	return (velocity as Vector3).length() if velocity is Vector3 else 0.0


## Samples the scene for a `RebaseFight` while it runs.
class Watch extends Node:
	var fight: RebaseFight = null
	var main: Main = null
	var world: WorldFrame = null
	var rebase_every_s: float = 0.0

	var _start_s: float = 0.0
	var _last_rebase_s: float = 0.0
	var _rebase_frame: int = -1
	var _snap_frame: int = -1
	var _seen_rebases: int = 0
	var _dt: float = 1.0 / 60.0
	var _previous: Dictionary = {}  # instance id -> [UniversePos, speed, name]
	var _camera_at_tick_start: Vector3 = Vector3.ZERO
	var _camera_valid: bool = false
	var _last_camera_offset: Vector3 = Vector3.INF
	var _kills_at_start: int = 0

	func _init(p_fight: RebaseFight, p_main: Main) -> void:
		fight = p_fight
		main = p_main
		world = p_main.world
		name = "RebaseFightWatch"
		process_physics_priority = -1000  # the start of every tick: Jolt's last step is in, nothing of this tick has run
		process_priority = 2000  # every frame after the cameras, the HUD and the splat sync

	func _ready() -> void:
		world.rebased.connect(_on_rebased)
		(main.get_node(^"Combat/HitResolver") as HitResolver).hit_resolved.connect(_on_hit)
		main.rams.ram_resolved.connect(_on_ram)
		_start_s = SimClock.now()
		_last_rebase_s = _start_s
		_seen_rebases = world.rebases
		_kills_at_start = main.waves.kills

	func _exit_tree() -> void:
		if world.rebased.is_connected(_on_rebased):
			world.rebased.disconnect(_on_rebased)
		var hits_node := main.get_node(^"Combat/HitResolver") as HitResolver
		if hits_node.hit_resolved.is_connected(_on_hit):
			hits_node.hit_resolved.disconnect(_on_hit)
		if main.rams.ram_resolved.is_connected(_on_ram):
			main.rams.ram_resolved.disconnect(_on_ram)

	func run_for(sim_s: float, until: Callable) -> void:
		while SimClock.now() - _start_s < sim_s and not (until.is_valid() and bool(until.call())):
			await get_tree().physics_frame
		await get_tree().physics_frame
		fight.max_gap_s = maxf(fight.max_gap_s, SimClock.now() - _last_rebase_s)
		fight.kills = main.waves.kills - _kills_at_start

	# --- every tick ---------------------------------------------------------------------------------------------

	func _physics_process(delta: float) -> void:
		fight.ticks += 1
		var current: Dictionary = _sample()
		for id: int in current:
			if not _previous.has(id):
				continue
			var before: Array = _previous[id]
			var now: Array = current[id]
			var moved: float = (before[0] as UniversePos).distance_to(now[0] as UniversePos)
			var bound: float = maxf(float(before[1]), float(now[1])) * _dt + JUMP_SLACK_M
			fight.jumps_checked += 1
			fight.worst_jump_m = maxf(fight.worst_jump_m, moved - bound)
			if moved > bound:
				fight._fail("%s moved %.2f m in universe terms in a tick, its own motion allows %.2f m" % [before[2], moved, bound])
		_previous = current
		_dt = delta
		if world.rebases != _seen_rebases:
			# The rebases of the last tick (cost, structure), read here, outside the cost they measure.
			_seen_rebases = world.rebases
			fight.rebase_ticks += 1
			fight.rebase_us.append(world.last_rebase_us)
			_check_structure()
		if rebase_every_s > 0.0 and SimClock.now() - _last_rebase_s >= rebase_every_s:
			fight.forced_rebases += 1
			var turn: float = float(fight.forced_rebases) * 2.39996  # the golden angle, rad
			world.rebase(Vector3(cos(turn), 0.3 * sin(3.0 * turn), sin(turn)).normalized() * FORCED_REBASE_M)
		_camera_valid = _chase_in_view()
		if _camera_valid:
			_camera_at_tick_start = main.camera_rig.chase_camera.global_position - main.ship.global_position

	# Every active hull (ships and props) and every bolt in flight: instance id -> [universe position, speed, name].
	func _sample() -> Dictionary:
		var out: Dictionary = {}
		for node: Node in get_tree().get_nodes_in_group(Damageable.GROUP):
			var damageable := node as Damageable
			if damageable == null or not damageable.is_active():
				continue
			var body: Node3D = damageable.body()
			out[body.get_instance_id()] = [world.to_universe(body.global_position), RebaseFight._speed_of(body), String(body.name)]
		for node: Node in get_tree().get_nodes_in_group(Projectile.GROUP):
			var bolt := node as Projectile
			if bolt != null and not bolt.is_spent() and not bolt.is_queued_for_deletion() and bolt.is_inside_tree():
				out[bolt.get_instance_id()] = [world.to_universe(bolt.global_position), bolt.velocity.length(), "a bolt"]
		return out

	func _on_rebased(_offset: Vector3) -> void:
		fight.rebases += 1
		var now_s: float = SimClock.now()
		fight.max_gap_s = maxf(fight.max_gap_s, now_s - _last_rebase_s)
		_last_rebase_s = now_s
		_rebase_frame = Engine.get_physics_frames()
		if _camera_valid and _chase_in_view():
			# Nothing moves the chase camera or the ship between the start of the tick and the rebase but the rebase itself.
			var offset: Vector3 = main.camera_rig.chase_camera.global_position - main.ship.global_position
			var change: float = (offset - _camera_at_tick_start).length()
			fight.worst_camera_rebase_m = maxf(fight.worst_camera_rebase_m, change)
			if change > CAMERA_REBASE_TOL_M:
				fight._fail("the rebase moved the chase camera %.3f m relative to the ship" % change)

	func _on_hit(info: HitInfo) -> void:
		if info.cause != HitInfo.CAUSE_BOLT:
			return
		fight.hits += 1
		if Engine.get_physics_frames() == _rebase_frame:
			fight.hits_in_rebase_ticks += 1
		_check_on_hull(info, "bolt hit")
		# The bolt that hit is spent this tick and still in the tree: the hit must lie on the path it flew in this tick.
		var nearest: float = INF
		var reach: float = 0.0
		for node: Node in get_tree().get_nodes_in_group(Projectile.GROUP):
			var bolt := node as Projectile
			if bolt == null or not bolt.is_spent() or bolt.shooter_id != info.shooter_id:
				continue
			var d: float = bolt.global_position.distance_to(info.point)
			if d < nearest:
				nearest = d
				reach = bolt.last_step.length() + bolt.hit_radius_m + JUMP_SLACK_M
				if bolt.last_step.length() > bolt.velocity.length() * _dt + 1e-3:
					fight._fail("a bolt's step was %.1f m, its velocity gives %.1f m" % [bolt.last_step.length(),
							bolt.velocity.length() * _dt])
		if nearest > reach:
			fight._fail("a bolt hit landed %.1f m from the bolt that made it (its path this tick reaches %.1f m)" % [nearest, reach])

	func _on_ram(info: HitInfo) -> void:
		fight.rams += 1
		_check_on_hull(info, "ram")

	func _check_on_hull(info: HitInfo, what: String) -> void:
		var body := instance_from_id(info.target_id) as Node3D if is_instance_id_valid(info.target_id) else null
		if body == null:
			return
		var damageable: Damageable = Damageable.of(body)
		var radius: float = damageable.bounding_radius if damageable != null else 0.0
		var beyond: float = info.point.distance_to(body.global_position) - radius - RebaseFight._speed_of(body) * _dt - JUMP_SLACK_M
		if beyond > 0.0:
			fight._fail("a %s on %s landed %.1f m outside its hull" % [what, body.name, beyond])

	# --- every frame --------------------------------------------------------------------------------------------

	func _process(_delta: float) -> void:
		if main == null or not is_instance_valid(main) or main.ship == null:
			return
		fight.frames_checked += 1
		_check_camera()
		_check_hud()
		if _rebase_frame == Engine.get_physics_frames() and _snap_frame != _rebase_frame:
			_snap_frame = _rebase_frame
			_check_snap()

	func _chase_in_view() -> bool:
		return main.player_alive and main.ship.is_visible_in_tree() and main.camera_rig.mode == CameraRig.Mode.CHASE

	func _check_camera() -> void:
		if not _chase_in_view():
			_last_camera_offset = Vector3.INF
			return
		var pose: Transform3D = main.ship.get_global_transform_interpolated()
		var offset: Vector3 = pose.basis.inverse() * (main.camera_rig.chase_camera.global_position - pose.origin)
		if _last_camera_offset != Vector3.INF:
			var change: float = offset.distance_to(_last_camera_offset)
			fight.worst_camera_m = maxf(fight.worst_camera_m, change)
			var tol: float = CAMERA_TOL_M if main.camera_rig.chase_config.smoothing_s <= 0.0 else 1.0
			if change > tol:
				fight._fail("the chase camera's offset from the drawn ship changed by %.3f m in a frame" % change)
		_last_camera_offset = offset

	func _check_hud() -> void:
		var frame: HudFrame = main.hud.frame
		if not main.hud.visible or frame == null or not frame.reference_valid or not main.player_alive:
			return
		var expected: float = world.to_universe(main.ship.global_position).distance_to(main.reference_point())
		var error: float = absf(frame.reference_range_m - expected)
		fight.worst_hud_m = maxf(fight.worst_hud_m, error)
		if error > HUD_TOL_M + 1e-6 * expected:
			fight._fail("the HUD's reference range is %.2f m, the universe distance %.2f m" % [frame.reference_range_m, expected])

	# The frame after a rebase: every interpolated node of World is drawn at its tick pose (the world stalls together for the
	# rebase tick, WorldFrame's class notes). Nodes with interpolation off (the chase camera, the splat nodes the pose sync
	# drives) are placed every frame; the camera has its own check. Silent voices are skipped (the rebase skips them too).
	func _check_snap() -> void:
		fight.snaps_checked += 1
		var nodes: Array[Node] = get_tree().get_nodes_in_group(WorldFrame.SHIFTABLE_GROUP)
		nodes.append(main.camera_rig.cockpit_pivot)
		for member: Node in nodes:
			var node := member as Node3D
			if node == null or not world.is_ancestor_of(node) or not node.is_visible_in_tree() \
					or not node.is_physics_interpolated_and_enabled():
				continue
			if node is AudioStreamPlayer3D and not (node as AudioStreamPlayer3D).playing:
				continue
			var gap: float = node.get_global_transform_interpolated().origin.distance_to(node.global_position)
			fight.worst_snap_m = maxf(fight.worst_snap_m, gap)
			if gap > SNAP_TOL_M:
				fight._fail("%s is drawn %.2f m from its tick pose in the frame after a rebase" % [node.name, gap])

	# --- after every rebase -----------------------------------------------------------------------------------------

	func _check_structure() -> void:
		fight.structure_checks += 1
		_check_below(world, false)

	# `followed`: `node` moves with a rebase (it is shiftable, below a shiftable node, or the cockpit pivot the ship drives).
	func _check_below(node: Node, followed: bool) -> void:
		for child: Node in node.get_children():
			var child_followed: bool = followed
			var spatial := child as Node3D
			if spatial != null:
				var shiftable: bool = spatial.is_in_group(WorldFrame.SHIFTABLE_GROUP)
				if spatial.top_level and not shiftable:
					fight._fail("%s is top_level below World but not world_shiftable: a rebase leaves it behind" % world.get_path_to(spatial))
				elif not followed and not shiftable and spatial != main.camera_rig.cockpit_pivot and not _is_container(spatial):
					fight._fail("%s sits in World space but neither it nor a parent is world_shiftable" % world.get_path_to(spatial))
				var global_particles: bool = (child is GPUParticles3D and not (child as GPUParticles3D).local_coords) \
						or (child is CPUParticles3D and not (child as CPUParticles3D).local_coords)
				if global_particles:
					fight._fail("%s emits particles in global space: a rebase cannot move them" % world.get_path_to(spatial))
				child_followed = shiftable or (followed and not spatial.top_level) or spatial == main.camera_rig.cockpit_pivot
			_check_below(child, child_followed)

	# A plain holder of world objects (World/Ships, World/Projectiles, the camera rig): a bare Node3D (scripted or not) at the
	# World's origin; what it holds is checked on its own.
	func _is_container(node: Node3D) -> bool:
		return node.get_class() == "Node3D" and (world.global_transform.affine_inverse() * node.global_transform).is_equal_approx(
				Transform3D.IDENTITY)
