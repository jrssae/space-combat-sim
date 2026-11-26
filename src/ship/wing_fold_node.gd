class_name WingFoldNode
extends Node3D
## Folds a shuttle's wings on screen (M10-T17, Q73, Q93; the rules are `WingFold`): while the wings are not spread the hull is
## drawn as its break-up chunks, the wings turned about their joints, and the one-piece hull is hidden. A child of the `Ship`,
## made on first use (`attach`) and kept with the pooled ship. Visual only: the hull's hit volumes do not fold.

const NODE_NAME: StringName = &"WingFold"

## 0 spread, 1 folded: the share of the fold's time done.
var amount: float = 0.0
var fold_deg: float = 90.0
var fold_s: float = 4.0
var _target: float = 0.0
var _ship: Ship = null
var _chunks: Array[Dictionary] = []  # {entry, node}


## The fold node of `ship`, made the first time; null when its craft does not fold or its wings are not their own chunks.
static func attach(ship: Ship) -> WingFoldNode:
	if ship == null or ship.spec == null:
		return null
	var found := ship.get_node_or_null(NodePath(NODE_NAME)) as WingFoldNode
	if found != null:
		return found
	var fold: Dictionary = WingFold.of_asset(ship.spec.asset_id)
	if fold.is_empty():
		return null
	var dir: String = Ship.asset_dir(ship.spec)
	var chunks: Array = Hardpoints.load_file(dir.path_join("hardpoints.json")).raw.get("chunks", []) as Array
	if not WingFold.has_wings(chunks):
		return null
	var node := WingFoldNode.new()
	node.name = NODE_NAME
	node.fold_deg = float(fold.get("fold_deg", 90.0))
	node.fold_s = float(fold.get("fold_s", 4.0))
	node._ship = ship
	for raw: Variant in chunks:
		var entry: Dictionary = raw
		var mesh: Mesh = MeshAssets.chunk_mesh(dir, str(entry.get("mesh", "")))
		if mesh == null:
			continue
		var part := MeshInstance3D.new()
		part.name = str(entry.get("name", "chunk")).to_pascal_case()
		part.mesh = mesh
		part.visible = false
		node.add_child(part)
		node._chunks.append({"entry": entry, "node": part})
	ship.add_child(node)
	node._draw()
	node.set_process(false)
	return node


## The fold node `ship` already has, else null.
static func of(ship: Node) -> WingFoldNode:
	return ship.get_node_or_null(NodePath(NODE_NAME)) as WingFoldNode if ship != null else null


## Starts folding (true) or spreading the wings.
func set_folded(folded: bool) -> void:
	_target = 1.0 if folded else 0.0
	set_process(not is_equal_approx(amount, _target) or amount > 0.0)


## Folds or spreads them at once (a craft brought out of a bay already folded).
func snap(folded: bool) -> void:
	_target = 1.0 if folded else 0.0
	amount = _target
	_draw()
	set_process(amount > 0.0)


func is_folded() -> bool:
	return amount >= 1.0


func is_spread() -> bool:
	return amount <= 0.0


func _process(delta: float) -> void:
	amount = WingFold.advance(amount, _target, delta, fold_s)
	_draw()
	if is_equal_approx(amount, _target) and amount <= 0.0:
		set_process(false)  # folded, it keeps drawing: a far dot's switch shows the one-piece hull again


# Spread: the one-piece hull. Otherwise the chunks, the wings part way up.
func _draw() -> void:
	var spread: bool = amount <= 0.0
	var far: bool = _ship != null and _ship.is_far_dot()
	if _ship != null and _ship.hull != null:
		_ship.hull.visible = spread and not far
	var share: float = WingFold.eased(amount)
	for c: Dictionary in _chunks:
		var part: MeshInstance3D = c["node"]
		part.visible = not spread and not far
		part.transform = WingFold.chunk_transform(c["entry"], share, fold_deg)
