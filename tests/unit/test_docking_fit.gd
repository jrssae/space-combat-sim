extends GutTest
## Every hull the docking lane takes (`DockingPlan.tunnel_types()`) fits the main docking bay's mouth (M7-T25: the STL's band across
## a taller core, scaled to 80 m) and its black void, lying square in it as the lane flies it (on the axis, its top to the drum's):
## its collision shapes seen from ahead stay `MARGIN_M` inside the mouth's clear outline, and it lies wholly behind the inner
## doors at the lane's end, short of the void's back wall.

const MARGIN_M: float = 2.0
const STEP_M: float = 0.5


func _bay() -> Dictionary:
	var hardpoints := StationHardpoints.from_manifest(MeshAssets.read_manifest(Station.ASSET_ID))
	return hardpoints.main_docking_bay if hardpoints.valid else {}


# The shape's outline seen from ahead (x, y in the bay's frame: the hull's nose down the axis, its top up), densely sampled.
static func _front_points(entry: Dictionary) -> PackedVector2Array:
	var shape: Shape3D = entry["shape"]
	var half := Vector3.ZERO
	if shape is BoxShape3D:
		half = 0.5 * (shape as BoxShape3D).size
	elif shape is CapsuleShape3D:
		half = Vector3((shape as CapsuleShape3D).radius, 0.5 * (shape as CapsuleShape3D).height, (shape as CapsuleShape3D).radius)
	var t: Transform3D = entry["transform"]
	var out := PackedVector2Array()
	for i: int in 8:
		var corner := Vector3(half.x * (1.0 if i & 1 else -1.0), half.y * (1.0 if i & 2 else -1.0), half.z * (1.0 if i & 4 else -1.0))
		var p: Vector3 = t * corner
		out.append(Vector2(-p.x, p.y))  # the nose (-Z) down the bay's +z: the hull's right is the bay's -x
	var ring := PackedVector2Array(out)
	for a: Vector2 in ring:  # the edges between every pair of corners, for the mouth's notches
		for b: Vector2 in ring:
			var n: int = int(a.distance_to(b) / STEP_M)
			for k: int in range(1, n):
				out.append(a.lerp(b, float(k) / float(n)))
	return out


static func _fits(points: PackedVector2Array, outline: PackedVector2Array, margin: float) -> bool:
	var shrunk: Array[PackedVector2Array] = Geometry2D.offset_polygon(outline, -margin, Geometry2D.JOIN_MITER)
	if shrunk.size() != 1:
		return false
	for p: Vector2 in points:
		if not Geometry2D.is_point_in_polygon(p, shrunk[0]):
			return false
	return true


func test_every_tunnel_hull_fits_the_mouth_lying_square() -> void:
	var bay: Dictionary = _bay()
	if not bay.has("main_docking_bay_opening"):
		pending("the babylon5_station asset is not generated")
		return
	var outline: PackedVector2Array = bay["main_docking_bay_opening"]
	for type: StringName in DockingPlan.tunnel_types():
		var shapes: Array[Dictionary] = Hardpoints.load_collision_only("res://assets/generated/%s/hardpoints.json" % type)
		if shapes.is_empty():
			pending("%s is not generated" % type)
			continue
		var points := PackedVector2Array()
		for entry: Dictionary in shapes:
			points.append_array(_front_points(entry))
		assert_true(_fits(points, outline, MARGIN_M), "%s clears the mouth by %.1f m" % [type, MARGIN_M])
		var room: float = MARGIN_M
		while _fits(points, outline, room + STEP_M):
			room += STEP_M
		gut.p("%s: %.1f m clear of the mouth all round" % [type, room])


func test_every_tunnel_hull_lies_wholly_in_the_void_at_the_lanes_end() -> void:
	var bay: Dictionary = _bay()
	if not bay.has("main_docking_bay_doors"):
		pending("the babylon5_station asset is not generated")
		return
	var doors: float = (bay["main_docking_bay_doors"] as Vector3).z
	var wall: float = (bay["main_docking_bay_airlock"] as Vector3).z
	var end: float = wall - DockingPlan.AIRLOCK_SHORT_M
	for type: StringName in DockingPlan.tunnel_types():
		var body := RigidBody3D.new()
		for entry: Dictionary in Hardpoints.load_collision_only("res://assets/generated/%s/hardpoints.json" % type):
			var node := CollisionShape3D.new()
			node.shape = entry["shape"]
			node.transform = entry["transform"]
			body.add_child(node)
		add_child_autofree(body)
		var reach: Vector2 = StationAirlock.hull_reach(body)
		assert_gt(reach.x + reach.y, 50.0, "%s has its shapes" % type)
		assert_gt(end - reach.y, doors + 5.0, "%s's tail is behind the doors at the lane's end" % type)
		assert_lt(end + reach.x, wall - 40.0, "%s's nose is well short of the void's back wall (room to brake late)" % type)
