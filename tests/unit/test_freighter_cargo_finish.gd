extends GutTest
## A freighter's cargo job ends once (M7-T40): an unload keeps its node until the station traffic lets the Saturn go, and must
## not tell `finished` again on every tick after its last pod is carried.

var told: int = 0


func _on_finished() -> void:
	told += 1


func test_an_unload_that_is_done_tells_finished_once() -> void:
	var cargo := FreighterCargo.new()
	cargo.job = CargoFerryJob.new()  # no pods: its first update says done
	cargo.loading = false
	cargo.finished.connect(_on_finished)
	add_child_autofree(cargo)
	cargo.set_process(false)  # no ship here to look at (the node turns it on as it enters the tree)
	for i: int in 5:
		await get_tree().physics_frame
	assert_eq(told, 1, "finished is told once, not every tick")
	assert_false(cargo.restored, "an unload is not restored by its end")
