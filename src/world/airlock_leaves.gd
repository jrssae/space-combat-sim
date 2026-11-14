class_name AirlockLeaves
extends RefCounted
## The main docking bay's two inner door leaves (M7-T25's props, one instance each in the bay's section), slid apart to open: the
## upper one up, the lower one down, by the manifest's `main_docking_bay_doors_open_m`. Found from the drum's built props.

const KINDS: Array[String] = ["airlock_leaf_upper", "airlock_leaf_lower"]

# Each leaf: {mm: MultiMesh, base: Transform3D, sign: float}, in its section's frame.
var _leaves: Array[Dictionary] = []
var _offset: float = -1.0


## The leaves among `piece`'s props (the drum's `RenderPiece`).
static func find(piece: RenderPiece) -> AirlockLeaves:
	var made := AirlockLeaves.new()
	if piece == null:
		return made
	var nodes: Dictionary = {}
	for node: MultiMeshInstance3D in piece.prop_nodes():
		nodes[String(node.name)] = node
	for k: int in KINDS.size():
		var node := nodes.get("Props_%s" % KINDS[k].to_pascal_case()) as MultiMeshInstance3D
		if node == null or node.multimesh.instance_count < 1:
			continue
		made._leaves.append({"mm": node.multimesh, "base": node.multimesh.get_instance_transform(0), "sign": 1.0 if k == 0 else -1.0})
	return made


## How many leaves were found (2 on a built station).
func count() -> int:
	return _leaves.size()


## Slides each leaf `metres` from shut (0) away from the seam.
func set_offset(metres: float) -> void:
	if metres == _offset:
		return
	_offset = metres
	for leaf: Dictionary in _leaves:
		var base: Transform3D = leaf["base"]
		(leaf["mm"] as MultiMesh).set_instance_transform(0, Transform3D(base.basis, base.origin + Vector3.UP * float(leaf["sign"]) * metres))


## A leaf's place now (0 upper, 1 lower), in its section's frame: for tests.
func leaf_origin(which: int) -> Vector3:
	if which >= _leaves.size():
		return Vector3.ZERO
	return (_leaves[which]["mm"] as MultiMesh).get_instance_transform(0).origin
