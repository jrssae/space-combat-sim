class_name ShiftableRegistry
extends RefCounted
## The `world_shiftable` nodes in play, World by World (M6-T21): what a position rebase and a velocity rebase walk instead of
## the whole group, which holds every parked ship of the pools and the low-attention tier too.
##
## Kept from the tree's own `node_added` and `node_removed`: a node in the group is listed under its World when it enters the
## tree and dropped when it leaves (or is freed). A node its pool or the tier parks out of play (`set_out`: hidden, not
## processing, placed again when it comes back) leaves the list until it is back. A node that joins the group only after it
## entered the tree, or leaves the group while staying in it, is caught by a count check before every walk (the group's size
## against what is known), which reads the group again.

## The metas that mark a node parked out of play: the tier's and the pools'.
const OUT_METAS: Array[StringName] = [&"_scs_tier_row", &"_scs_pool_parked"]

static var _current: ShiftableRegistry = null

var tree: SceneTree = null
## Times the whole group was read again (a work count; one at the start).
var resyncs: int = 0

# Every node of the group in the tree, and the World it is under (null outside one).
var _world_of: Dictionary = {}
# Per World (its instance id), the nodes in play as the keys of a Dictionary.
var _in_play: Dictionary = {}


func _init(p_tree: SceneTree) -> void:
	tree = p_tree
	tree.node_added.connect(_on_node_added)
	tree.node_removed.connect(_on_node_removed)
	_resync()


## The registry of `p_tree`, made on first ask.
static func of_tree(p_tree: SceneTree) -> ShiftableRegistry:
	if _current == null or _current.tree != p_tree:
		if _current != null:
			_current.close()
		_current = ShiftableRegistry.new(p_tree)
	return _current


## Marks `node` parked out of play under `meta` (one of `OUT_METAS`), or back in play, and lists it again to match.
static func set_out(node: Node, meta: StringName, out: bool) -> void:
	if out:
		node.set_meta(meta, true)
	elif node.has_meta(meta):
		node.remove_meta(meta)
	if _current != null and node.is_inside_tree() and node.get_tree() == _current.tree:
		_current._refresh(node)


## Whether `node` is parked out of play by its pool or the tier.
static func is_out(node: Node) -> bool:
	for meta: StringName in OUT_METAS:
		if node.has_meta(meta):
			return true
	return false


## The nodes of `world` in play, as the keys of a Dictionary (read, never write). The group is read again first when its
## size says something joined or left it without entering or leaving the tree.
func in_play(world: WorldFrame) -> Dictionary:
	if tree.get_node_count_in_group(WorldFrame.SHIFTABLE_GROUP) != _world_of.size():
		_resync()
	return _list(world)


## Forgets a World that leaves the tree.
func forget_world(world: WorldFrame) -> void:
	_in_play.erase(world.get_instance_id())


## Stops listening to the tree.
func close() -> void:
	if tree != null and is_instance_valid(tree):
		if tree.node_added.is_connected(_on_node_added):
			tree.node_added.disconnect(_on_node_added)
			tree.node_removed.disconnect(_on_node_removed)


func _on_node_added(node: Node) -> void:
	if node.is_in_group(WorldFrame.SHIFTABLE_GROUP) and not _world_of.has(node):
		_note(node)


func _on_node_removed(node: Node) -> void:
	if not _world_of.has(node):
		return
	var world: WorldFrame = _world_of[node]
	_world_of.erase(node)
	if world != null:
		_list(world).erase(node)


func _note(node: Node) -> void:
	var world: WorldFrame = WorldFrame.of(node)
	_world_of[node] = world
	if world != null and node is Node3D and not is_out(node):
		_list(world)[node] = true


func _refresh(node: Node) -> void:
	if not _world_of.has(node):
		return
	var world: WorldFrame = _world_of[node]
	if world == null or not node is Node3D:
		return
	if is_out(node):
		_list(world).erase(node)
	else:
		_list(world)[node] = true


func _list(world: WorldFrame) -> Dictionary:
	var id: int = world.get_instance_id()
	var list: Variant = _in_play.get(id)
	if list == null:
		list = {}
		_in_play[id] = list
	return list


func _resync() -> void:
	resyncs += 1
	_world_of.clear()
	_in_play.clear()
	for node: Node in tree.get_nodes_in_group(WorldFrame.SHIFTABLE_GROUP):
		_note(node)
