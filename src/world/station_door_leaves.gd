class_name StationDoorLeaves
extends RefCounted
## The Cobra bays' door leaves (M7-T05's props, two a door, one instance an arm) slid apart for a launch (M7-T08, M8-T02): each
## toothed leaf retracts across the arm under the deck, as far as its bay's hardpoint says. Found from the drum's props as the
## manifest places them and the manifest's hardpoints, so a reshaped arm moves nothing here.

# Each leaf by bay name: Array of {mm: MultiMesh (null when its node is not drawn), index, base: Transform3D, slide: Vector3,
# travel: float}, all in its section's frame.
var _by_bay: Dictionary = {}
var _shares: Dictionary = {}  # bay name -> how far open it was last set (0 shut to 1 open)


## The leaves of every bay in `hardpoints`, found among `piece`'s props (the drum's `RenderPiece`, in the drum's frame).
static func find(piece: RenderPiece, hardpoints: StationHardpoints) -> StationDoorLeaves:
	var made := StationDoorLeaves.new()
	if piece == null or piece.sections == null or hardpoints == null:
		return made
	# The closed places come from the manifest, not the drawn instances: a headless run's rendering server keeps none.
	var groups: Dictionary = {}
	for group: Dictionary in piece.sections.prop_groups:
		groups[String(group["kind"])] = group
	for bay: Dictionary in hardpoints.cobra_bays:
		var normal: Vector3 = (bay["normal"] as Vector3).normalized()
		var list: Array[Dictionary] = []
		for leaf: Dictionary in bay.get("leaves", []) as Array:
			var kind: String = "door_leaf_%d_%s" % [int(bay["door_number"]), str(leaf["leaf"])]
			if not groups.has(kind) or not leaf.has("slide"):
				continue
			var group: Dictionary = groups[kind]
			var section: Node = piece.section_node(String(group["section"]))
			var node: MultiMeshInstance3D = null
			if section != null:
				node = section.get_node_or_null("Props_%s" % kind.to_pascal_case()) as MultiMeshInstance3D
			var closed: Array[Transform3D] = group["transforms"]
			for i: int in closed.size():
				if (closed[i].basis * Vector3.UP).normalized().dot(normal) < 0.99:
					continue  # another arm's leaf
				list.append({"mm": node.multimesh if node != null else null, "index": i, "base": closed[i],
						"slide": (leaf["slide"] as Vector3).normalized(), "travel": float(leaf.get("travel_m", 0.0))})
		if not list.is_empty():
			made._by_bay[String(bay["name"])] = list
	return made


## How many bays have leaves to slide.
func count() -> int:
	return _by_bay.size()


## Slides bay `bay_name`'s leaves apart: `share` 0 shut, 1 fully back.
func set_open(bay_name: String, share: float) -> void:
	share = clampf(share, 0.0, 1.0)
	if float(_shares.get(bay_name, 0.0)) == share:
		return
	_shares[bay_name] = share
	var list: Array = _by_bay.get(bay_name, [])
	for which: int in list.size():
		var leaf: Dictionary = list[which]
		if leaf["mm"] != null:
			MultiMeshUpload.set_instance_transform(leaf["mm"] as MultiMesh, int(leaf["index"]), leaf_transform(bay_name, which))


## How far open bay `bay_name`'s leaves were last set (0 shut to 1 open).
func open_share(bay_name: String) -> float:
	return float(_shares.get(bay_name, 0.0))


## How many leaves bay `bay_name` has.
func leaf_count(bay_name: String) -> int:
	return (_by_bay.get(bay_name, []) as Array).size()


## Metres leaf `which` of the bay has slid from its closed place.
func slide_m(bay_name: String, which: int = 0) -> float:
	var list: Array = _by_bay.get(bay_name, [])
	return open_share(bay_name) * float((list[which] as Dictionary)["travel"]) if which < list.size() else 0.0


## Where leaf `which` of the bay stands now, in its section's frame.
func leaf_transform(bay_name: String, which: int = 0) -> Transform3D:
	var list: Array = _by_bay.get(bay_name, [])
	if which >= list.size():
		return Transform3D.IDENTITY
	var leaf: Dictionary = list[which]
	var base: Transform3D = leaf["base"]
	return Transform3D(base.basis, base.origin + (leaf["slide"] as Vector3) * slide_m(bay_name, which))


## Which way leaf `which` of the bay slides to open (unit, the drum's frame).
func slide_direction(bay_name: String, which: int = 0) -> Vector3:
	var list: Array = _by_bay.get(bay_name, [])
	return (list[which] as Dictionary)["slide"] if which < list.size() else Vector3.ZERO
