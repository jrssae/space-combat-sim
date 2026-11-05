extends GutTest
## A targetable finds its owner's hull once (M4-T34): the player's candidate list builds a `TargetInfo` for every
## targetable each tick, and looking the hull up three times per info walked the ship's children three times. The answer
## must stay what `Damageable.of(parent)` gives at that moment: the first hull among the owner's children, whatever was
## added, moved or freed since.

const BOX := Vector3(4.0, 2.0, 6.0)

var owner_node: Node3D
var targetable: Targetable


func before_each() -> void:
	owner_node = Node3D.new()
	add_child_autofree(owner_node)
	targetable = Targetable.new()
	owner_node.add_child(targetable)


func _hull(max_hp: float, size: Vector3 = BOX) -> Damageable:
	var hull := Damageable.new()
	var box := BoxShape3D.new()
	box.size = size
	var collision: Array[Dictionary] = [{"name": "hull", "shape": box, "transform": Transform3D.IDENTITY}]
	hull.setup(collision, max_hp, &"neutral")
	return hull


func _matches_lookup(label: String) -> void:
	var expected: Damageable = Damageable.of(owner_node)
	var info: TargetInfo = targetable.to_target_info()
	assert_eq(info.hull_fraction, expected.hull.fraction() if expected != null else -1.0, label + ": hull fraction")
	assert_eq(info.bounding_radius, expected.bounding_radius if expected != null else 0.0, label + ": bounding radius")
	assert_eq(targetable.get_hull_fraction(), info.hull_fraction, label + ": get_hull_fraction")
	assert_eq(targetable.get_bounding_radius(), info.bounding_radius, label + ": get_bounding_radius")


func test_an_info_follows_the_first_hull_through_every_change() -> void:
	_matches_lookup("no hull yet")
	var first: Damageable = _hull(100.0)
	owner_node.add_child(first)
	first.hull.apply(25.0)
	_matches_lookup("a hull added")
	var second: Damageable = _hull(50.0, Vector3(20.0, 20.0, 20.0))
	owner_node.add_child(second)
	_matches_lookup("a second hull after it")
	owner_node.move_child(second, 0)
	_matches_lookup("the second moved first")
	owner_node.remove_child(second)
	second.free()
	_matches_lookup("the second freed")
	first.hull.apply(50.0)
	_matches_lookup("damage taken")


func test_the_hull_is_looked_up_once_until_the_children_change() -> void:
	targetable.get_hull_fraction()
	var bare: int = Targetable.hull_lookups
	targetable.get_hull_fraction()
	assert_eq(Targetable.hull_lookups, bare, "no hull is an answer kept too")
	owner_node.add_child(_hull(100.0))
	targetable.to_target_info()
	var before: int = Targetable.hull_lookups
	for i: int in 5:
		targetable.to_target_info()
		targetable.get_hull_fraction()
		targetable.get_bounding_radius()
	assert_eq(Targetable.hull_lookups, before, "no lookup while the owner's children stay as they were")
	owner_node.add_child(Node3D.new())
	targetable.to_target_info()
	assert_eq(Targetable.hull_lookups, before + 1, "one lookup after the children changed")


func test_a_targetable_out_of_the_tree_looks_its_hull_up_each_time() -> void:
	owner_node.add_child(_hull(100.0))
	remove_child(owner_node)
	var before: int = Targetable.hull_lookups
	targetable.get_hull_fraction()
	targetable.get_bounding_radius()
	assert_eq(Targetable.hull_lookups, before + 2, "no cache outside the tree, where no signal keeps it honest")
	add_child(owner_node)
	_matches_lookup("back in the tree")
