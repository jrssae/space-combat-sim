class_name StationDoorLeaves
extends RefCounted
## The Cobra bays' door leaves (M7-T05's props, two a door, one instance an arm) swung on their hinges for a launch (M7-T08). Each
## leaf opens outward, away from the drum, about its hinge on the door's outer edge. Found from the drum's built props and the
## manifest's hardpoints, so T21's reshaped arm moves nothing here.

# Each leaf by bay name: Array of {mm: MultiMesh, index, base: Transform3D, hinge: Vector3, axis: Vector3, sign: float}, all in its
# section's frame.
var _by_bay: Dictionary = {}
var _angles: Dictionary = {}  # bay name -> degrees last set


## The leaves of every bay in `hardpoints`, found among `piece`'s props (the drum's `RenderPiece`, in the drum's frame).
static func find(piece: RenderPiece, hardpoints: StationHardpoints) -> StationDoorLeaves:
	var made := StationDoorLeaves.new()
	if piece == null or hardpoints == null:
		return made
	var nodes: Dictionary = {}
	for node: MultiMeshInstance3D in piece.prop_nodes():
		nodes[String(node.name)] = node
	for bay: Dictionary in hardpoints.cobra_bays:
		var normal: Vector3 = (bay["normal"] as Vector3).normalized()
		var list: Array[Dictionary] = []
		for leaf: Dictionary in bay.get("leaves", []) as Array:
			var kind: String = "door_leaf_%d_%s" % [int(bay["door_number"]), str(leaf["leaf"])]
			var node := nodes.get("Props_%s" % kind.to_pascal_case()) as MultiMeshInstance3D
			if node == null:
				continue
			var origin: Vector3 = (node.get_parent() as Node3D).position  # the section's place in the drum's frame
			var mm: MultiMesh = node.multimesh
			for i: int in mm.instance_count:
				var base: Transform3D = mm.get_instance_transform(i)
				if (base.basis * Vector3.UP).normalized().dot(normal) < 0.99:
					continue  # another arm's leaf
				var hinge: Vector3 = leaf["point"]
				var axis: Vector3 = (leaf["axis"] as Vector3).normalized()
				var inward: Vector3 = (bay["door"] as Vector3) - hinge
				list.append({"mm": mm, "index": i, "base": base, "hinge": hinge - origin, "axis": axis,
						"sign": 1.0 if axis.cross(inward).dot(normal) > 0.0 else -1.0})
		if not list.is_empty():
			made._by_bay[String(bay["name"])] = list
	return made


## How many bays have leaves to swing.
func count() -> int:
	return _by_bay.size()


## Swings bay `bay_name`'s leaves `degrees` open (0 shut).
func set_open(bay_name: String, degrees: float) -> void:
	if float(_angles.get(bay_name, 0.0)) == degrees:
		return
	_angles[bay_name] = degrees
	for leaf: Dictionary in _by_bay.get(bay_name, []) as Array:
		var hinge: Vector3 = leaf["hinge"]
		var swing := Basis(leaf["axis"] as Vector3, deg_to_rad(degrees) * float(leaf["sign"]))
		var about := Transform3D(swing, hinge - swing * hinge)
		(leaf["mm"] as MultiMesh).set_instance_transform(int(leaf["index"]), about * (leaf["base"] as Transform3D))


## Degrees bay `bay_name`'s leaves were last set open.
func open_deg(bay_name: String) -> float:
	return float(_angles.get(bay_name, 0.0))


## Where a leaf's free edge is now (the first leaf of the bay), in its section's frame: for tests.
func leaf_transform(bay_name: String, which: int = 0) -> Transform3D:
	var list: Array = _by_bay.get(bay_name, [])
	if which >= list.size():
		return Transform3D.IDENTITY
	var leaf: Dictionary = list[which]
	return (leaf["mm"] as MultiMesh).get_instance_transform(int(leaf["index"]))
