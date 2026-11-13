class_name CollisionBodies
extends RefCounted
## Builds the physics body of one collision piece (M7-T03, D73): a `StaticBody3D` for a piece that never moves in its
## frame, an `AnimatableBody3D` for one its owner moves (a turning drum). The caller names it, sets its layers and adds it
## to the tree; neither kind of body has damping to set.


## One body with a `CollisionShape3D` child per shape of `piece` (a `CollisionPieces` piece).
static func build(piece: Dictionary, animatable: bool = false) -> PhysicsBody3D:
	var body: PhysicsBody3D = AnimatableBody3D.new() if animatable else StaticBody3D.new()
	body.name = str(piece.get("name", "piece")).to_pascal_case().validate_node_name()
	var shapes: Array[Dictionary] = piece.get("shapes", [] as Array[Dictionary])
	for entry: Dictionary in shapes:
		var node := CollisionShape3D.new()
		node.name = str(entry["name"]).to_pascal_case().validate_node_name()
		node.shape = entry["shape"]
		node.transform = entry["transform"]
		body.add_child(node, true)
	return body
