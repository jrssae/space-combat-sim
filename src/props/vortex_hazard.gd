class_name VortexHazard
extends RefCounted
## Jump points kill (M8-T17, maintainer 2026-11-19): when a vortex forms, any ship in the space it forms in is destroyed, and when
## it closes, any ship still in it is. Everyone, the player included, at a gate or at a point a ship opened; spared are the ship that
## opened the point and the ships it is carrying through (every arrival of that opening, the whole way out and after, seen or not;
## a departure on its way in; a fighter docked on its opener; M8-T17 fix, 2026-11-20). The space is the
## funnel, from the mouth's plane to its base, as wide as the funnel at each depth. Pure but for `sweep` and `warning`, which read
## the physics and the scene. Ships far from the player wait in the low-attention tier with no body in the world; the rule reaches
## the ships flying in full round the player, where a jump point is seen.

## A ship this far outside the funnel's wall still counts as in it (its own hull reaches in), as a share of its radius.
const HULL_SHARE: float = 1.0
## What the HUD says to a pilot sitting in a vortex about to form.
const WARNING: String = "JUMP POINT OPENING — CLEAR THE MOUTH"
## The bodies that can be caught: ships of every kind.
const MASK: int = CollisionLayers.PLAYER | CollisionLayers.FIGHTER | CollisionLayers.CAPITAL


## Whether a point `local` in the vortex's frame (origin the mouth's centre, +Z down the funnel), with a hull `radius_m` round it,
## lies in the funnel of `fit`.
static func inside(fit: VortexFit, local: Vector3, radius_m: float = 0.0) -> bool:
	var reach: float = radius_m * HULL_SHARE
	if fit.depth_m <= 0.0 or local.z < -reach or local.z > fit.depth_m + reach:
		return false
	var share: float = VortexTransit.radius_share_at(clampf(local.z / fit.depth_m, 0.0, 1.0))
	var axes: Vector2 = fit.semi_axes() * share + Vector2(reach, reach)
	if axes.x <= 0.0 or axes.y <= 0.0:
		return false
	return Vector2(local.x / axes.x, local.y / axes.y).length() <= 1.0


## Destroys the ships in `vortex`'s funnel now, but its opener and the ships it carries; returns how many. `space` is the physics to
## ask (the vortex's own world by default).
static func sweep(vortex: JumpVortex) -> int:
	if vortex == null or not vortex.is_inside_tree():
		return 0
	var killed: int = 0
	var transits: VortexTransits = VortexTransits.for_node(vortex)
	for body: RigidBody3D in caught(vortex):
		if vortex.spares(body) or (transits != null and transits.is_passing(body)):
			continue
		var damageable: Damageable = Damageable.of(body)
		if damageable != null and damageable.kill(HitInfo.CAUSE_VORTEX):
			killed += 1
	return killed


## The ships in `vortex`'s funnel now, spared or not.
static func caught(vortex: JumpVortex) -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	var frame: Transform3D = vortex.true_frame()
	var fit: VortexFit = vortex.fit
	var axes: Vector2 = fit.semi_axes()
	var box := BoxShape3D.new()
	box.size = Vector3(axes.x * 2.0 + 200.0, axes.y * 2.0 + 200.0, fit.depth_m + 200.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = frame * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, fit.depth_m * 0.5))
	query.collision_mask = MASK
	var space: PhysicsDirectSpaceState3D = vortex.get_world_3d().direct_space_state
	for hit: Dictionary in space.intersect_shape(query, 128):
		var body := hit.get("collider") as RigidBody3D
		if body == null or out.has(body):
			continue
		var damageable: Damageable = Damageable.of(body)
		var radius: float = damageable.bounding_radius if damageable != null else 0.0
		if inside(fit, frame.affine_inverse() * body.global_position, radius):
			out.append(body)
	return out


## The HUD's warning for `ship` sitting in a vortex about to form ("" when it is in none), the ship's own jump aside.
static func warning(ship: Node3D, tree: SceneTree) -> String:
	if ship == null or tree == null:
		return ""
	var transits: VortexTransits = VortexTransits.for_node(ship)
	if transits != null and transits.is_passing(ship):
		return ""
	var damageable: Damageable = Damageable.of(ship)
	var radius: float = damageable.bounding_radius if damageable != null else 0.0
	for node: Node in tree.get_nodes_in_group(JumpVortex.GROUP):
		var vortex := node as JumpVortex
		if vortex == null or not vortex.is_forming() or vortex.spares(ship):
			continue
		if inside(vortex.fit, vortex.true_frame().affine_inverse() * ship.global_position, radius):
			return WARNING
	return ""
