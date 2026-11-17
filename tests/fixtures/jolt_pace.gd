class_name JoltPace
extends Node
## Test fixture (M7-T14): keeps a sped-up Jolt run from outrunning the engine's worker pool. Godot's Jolt job system holds
## 2 048 jobs, and a job the main thread ran itself is freed only when its pool task comes round, so many steps back to back
## on a pool starved by a loaded machine (four test shards at once) run it dry: "Jolt Physics job system exceeded the maximum
## number of jobs". While in the tree it holds each physics tick until the pool has caught up with the tick before.

var _marker: int = -1


## Waits for `previous`, the marker task queued a tick ago (-1 for none): the pool takes its tasks in order, so once it is
## done every Jolt task queued before it has run and its job is free. Returns the next marker (-1 when `again` is false).
static func pace(previous: int, again: bool = true) -> int:
	if previous >= 0:
		while not WorkerThreadPool.is_task_completed(previous):
			OS.delay_usec(50)
		WorkerThreadPool.wait_for_task_completion(previous)
	return WorkerThreadPool.add_task(Callable(Time, &"get_ticks_usec"), true, "jolt pace") if again else -1


func _physics_process(_delta: float) -> void:
	_marker = pace(_marker)


func _exit_tree() -> void:
	_marker = pace(_marker, false)
