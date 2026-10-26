extends GutTest
## RamTracker (M3-T04, architecture §16 D32): which contacts are new, the window that measures a new contact's velocity
## change, one ram per pair per collision, and the hand-over between swept rams and Jolt's contacts. No Jolt: each tick is a
## list of samples, as the RamResolver reads them.

const DT: float = 1.0 / 60.0
const A: int = 101
const B: int = 202
const C: int = 303
const SAFE: float = 5.0
const LETHAL: float = 18.0

var tracker: RamTracker


func before_each() -> void:
	tracker = RamTracker.new()


func _sample(id: int, velocity: Vector3, touching: Array[int] = [], accel: Vector3 = Vector3.ZERO) -> RamTracker.Sample:
	var sample := RamTracker.Sample.new(id, velocity, accel, SAFE, LETHAL)
	for other_id: int in touching:
		sample.touch(other_id, Vector3(0.0, 0.0, -5.0), Vector3(0.0, 0.0, -1.0))
	return sample


## One tick: the contact phase, then the end of the tick. Returns the contact rams that landed.
func _tick(samples: Array[RamTracker.Sample]) -> Array[RamTracker.ContactRam]:
	var rams: Array[RamTracker.ContactRam] = tracker.contacts(samples, DT)
	tracker.end_tick()
	return rams


## A head-on at 30 m/s closing: approaching on tick 1, stopped against each other from tick 2 on.
func _head_on(ticks: int) -> Array[RamTracker.ContactRam]:
	var all: Array[RamTracker.ContactRam] = []
	all.append_array(_tick([_sample(A, Vector3(0.0, 0.0, -15.0)), _sample(B, Vector3(0.0, 0.0, 15.0))]))
	for i: int in ticks - 1:
		all.append_array(_tick([_sample(A, Vector3.ZERO, [B]), _sample(B, Vector3.ZERO, [A])]))
	return all


# --- contact windows -----------------------------------------------------------------------------------------------


func test_a_bounce_lands_one_ram_per_ship_when_the_window_closes() -> void:
	assert_eq(_head_on(3).size(), 0, "still measuring on the contact's first two ticks")
	tracker.reset()
	var rams: Array[RamTracker.ContactRam] = _head_on(4)
	assert_eq(rams.size(), 2, "the window closes on the third tick of the contact")
	for ram: RamTracker.ContactRam in rams:
		assert_almost_eq(ram.dv, 15.0, 1e-4)
		assert_almost_eq(ram.severity, pow(10.0 / 13.0, 2.0), 1e-4)
		assert_eq(ram.other_id, B if ram.hull_id == A else A)
		assert_almost_eq(ram.relative_speed, 30.0, 1e-4)
		assert_eq(ram.point, Vector3(0.0, 0.0, -5.0))
		assert_eq(ram.normal, Vector3(0.0, 0.0, -1.0))


func test_a_rebase_while_a_window_is_open_shifts_its_point_with_the_world() -> void:
	# M3-T14: the point is World-local, read when the window opens and used when it closes two ticks later.
	_tick([_sample(A, Vector3(0.0, 0.0, -15.0)), _sample(B, Vector3(0.0, 0.0, 15.0))])
	_tick([_sample(A, Vector3.ZERO, [B]), _sample(B, Vector3.ZERO, [A])])
	tracker.shift(Vector3(5000.0, 0.0, -300.0))
	_tick([_sample(A, Vector3.ZERO, [B]), _sample(B, Vector3.ZERO, [A])])
	tracker.shift(Vector3(0.0, 100.0, 0.0))
	var rams: Array[RamTracker.ContactRam] = _tick([_sample(A, Vector3.ZERO, [B]), _sample(B, Vector3.ZERO, [A])])
	assert_eq(rams.size(), 2)
	for ram: RamTracker.ContactRam in rams:
		assert_eq(ram.point, Vector3(-5000.0, -100.0, 295.0), "moved by minus both offsets, like the hulls")
		assert_eq(ram.normal, Vector3(0.0, 0.0, -1.0), "a direction: unchanged")


func test_a_shift_with_no_window_open_changes_nothing() -> void:
	tracker.shift(Vector3(5000.0, 0.0, 0.0))
	assert_eq(_head_on(4).size(), 2)


func test_a_resting_contact_rams_only_once() -> void:
	assert_eq(_head_on(60).size(), 2)


func test_a_lethal_change_lands_at_once() -> void:
	_tick([_sample(A, Vector3(0.0, 0.0, -20.0)), _sample(B, Vector3(0.0, 0.0, 20.0))])
	var rams: Array[RamTracker.ContactRam] = _tick([_sample(A, Vector3.ZERO, [B]), _sample(B, Vector3.ZERO, [A])])
	assert_eq(rams.size(), 2, "the tick the contact is reported")
	assert_eq(rams[0].severity, 1.0)


func test_a_contact_reported_a_tick_before_the_bounce_is_still_measured() -> void:
	# Jolt's speculative contact: reported while the velocity has not changed yet, the bounce spread over the next two steps.
	_tick([_sample(A, Vector3(0.0, 0.0, -14.0))])
	assert_eq(_tick([_sample(A, Vector3(0.0, 0.0, -14.0), [B])]).size(), 0)
	assert_eq(_tick([_sample(A, Vector3(0.0, 0.0, -1.0), [B])]).size(), 0)
	var rams: Array[RamTracker.ContactRam] = _tick([_sample(A, Vector3(0.0, 0.0, -0.2), [B])])
	assert_eq(rams.size(), 1)
	assert_almost_eq(rams[0].dv, 13.8, 1e-4, "the largest change over the window")


func test_thrust_is_never_a_ram() -> void:
	var accel := Vector3(0.0, 0.0, -30.0)
	var v := Vector3(0.0, 0.0, -10.0)
	_tick([_sample(A, v, [], accel)])
	for i: int in 6:
		v += accel * DT  # the velocity changes by exactly what the ship's own forces add
		assert_eq(_tick([_sample(A, v, [B], accel)]).size(), 0)
	# Pressed against a wall with the mains on: the contact cancels the thrust, 0.5 m/s a tick, under the safe change.
	tracker.reset()
	_tick([_sample(A, Vector3.ZERO, [], accel)])
	for i: int in 6:
		assert_eq(_tick([_sample(A, Vector3.ZERO, [B], accel)]).size(), 0)


func test_no_window_without_the_tick_before() -> void:
	# A body seen for the first time (spawned, respawned, ram damage switched on) already in contact: no velocity to compare.
	assert_eq(_tick([_sample(A, Vector3(0.0, 0.0, -30.0), [B])]).size(), 0)
	for i: int in 4:
		assert_eq(_tick([_sample(A, Vector3.ZERO, [B])]).size(), 0, "and the contact is no longer new")


func test_each_pair_has_its_own_window() -> void:
	_tick([_sample(A, Vector3.ZERO)])
	_tick([_sample(A, Vector3(10.0, 0.0, 0.0), [B])])  # B hits A
	_tick([_sample(A, Vector3(10.0, 10.0, 0.0), [B, C])])  # then C, while B's window is open
	var first: Array[RamTracker.ContactRam] = _tick([_sample(A, Vector3(10.0, 10.0, 0.0), [B, C])])
	var second: Array[RamTracker.ContactRam] = _tick([_sample(A, Vector3(10.0, 10.0, 0.0), [B, C])])
	assert_eq(first.size(), 1)
	assert_eq(second.size(), 1)
	if first.size() == 1 and second.size() == 1:
		assert_eq(first[0].other_id, B, "B's ram is B's")
		assert_eq(second[0].other_id, C, "and C's is C's, not merged into B's or lost")
		assert_almost_eq(second[0].dv, 10.0, 1e-4)


func test_a_body_that_leaves_play_takes_its_windows_along() -> void:
	_tick([_sample(A, Vector3(0.0, 0.0, -15.0))])
	_tick([_sample(A, Vector3.ZERO, [B])])
	assert_eq(_tick([] as Array[RamTracker.Sample]).size(), 0, "parked mid-window")
	assert_eq(_tick([_sample(A, Vector3.ZERO, [B])]).size(), 0, "back with no tick before: nothing")
	assert_eq(_tick([_sample(A, Vector3.ZERO, [B])]).size(), 0)


# --- swept rams --------------------------------------------------------------------------------------------------


func test_a_swept_meeting_is_one_ram_per_pair() -> void:
	tracker.contacts([] as Array[RamTracker.Sample], DT)
	assert_true(tracker.swept_meeting(A, B), "a new meeting is a ram")
	tracker.end_tick()
	tracker.contacts([] as Array[RamTracker.Sample], DT)
	assert_false(tracker.swept_meeting(B, A), "still meeting a tick later: the same ram, either order")
	tracker.end_tick()
	for i: int in RamTracker.SWEPT_GRACE_TICKS - 2:
		_tick([] as Array[RamTracker.Sample])
	tracker.contacts([] as Array[RamTracker.Sample], DT)
	assert_false(tracker.swept_meeting(A, B), "meeting again within the grace ticks is still the same collision")
	tracker.end_tick()
	for i: int in RamTracker.SWEPT_GRACE_TICKS + 1:
		_tick([] as Array[RamTracker.Sample])
	tracker.contacts([] as Array[RamTracker.Sample], DT)
	assert_true(tracker.swept_meeting(A, B), "a later meeting is a new ram")
	tracker.end_tick()


func test_jolt_resolving_a_swept_ram_opens_no_contact_window() -> void:
	# The sweep predicts the hit for the coming step; Jolt resolves it in that step and reports the contact next tick.
	tracker.contacts([_sample(A, Vector3(0.0, 0.0, -13.0)), _sample(B, Vector3(0.0, 0.0, 13.0))], DT)
	assert_true(tracker.swept_meeting(A, B))
	tracker.end_tick()
	var rams: Array[RamTracker.ContactRam] = []
	for i: int in RamTracker.SWEPT_GRACE_TICKS + 6:
		rams.append_array(_tick([_sample(A, Vector3.ZERO, [B]), _sample(B, Vector3.ZERO, [A])]))
	assert_eq(rams.size(), 0, "the bounce of a swept ram is not rammed again")


func test_a_contact_that_begins_late_in_the_grace_ticks_opens_no_window() -> void:
	tracker.contacts([_sample(A, Vector3(0.0, 0.0, -13.0)), _sample(B, Vector3(0.0, 0.0, 13.0))], DT)
	assert_true(tracker.swept_meeting(A, B))
	tracker.end_tick()
	for i: int in RamTracker.SWEPT_GRACE_TICKS - 1:
		_tick([_sample(A, Vector3(0.0, 0.0, -13.0)), _sample(B, Vector3(0.0, 0.0, 13.0))])
	var rams: Array[RamTracker.ContactRam] = []
	for i: int in 6:
		rams.append_array(_tick([_sample(A, Vector3.ZERO, [B]), _sample(B, Vector3.ZERO, [A])]))
	assert_eq(rams.size(), 0, "the last grace tick still counts")


func test_a_contact_after_the_grace_ticks_is_a_new_collision() -> void:
	tracker.contacts([] as Array[RamTracker.Sample], DT)
	assert_true(tracker.swept_meeting(A, B))
	tracker.end_tick()
	for i: int in RamTracker.SWEPT_GRACE_TICKS:
		_tick([_sample(A, Vector3(0.0, 0.0, -15.0)), _sample(B, Vector3(0.0, 0.0, 15.0))])
	assert_eq(_head_on(4).size(), 2)


func test_a_swept_ram_takes_over_the_pairs_open_contact_window() -> void:
	_tick([_sample(A, Vector3(0.0, 0.0, -15.0)), _sample(B, Vector3(0.0, 0.0, 15.0))])
	assert_eq(tracker.contacts([_sample(A, Vector3(0.0, 0.0, -5.0), [B]), _sample(B, Vector3(0.0, 0.0, 5.0), [A])], DT).size(), 0)
	assert_true(tracker.in_contact(A, B))
	assert_true(tracker.swept_meeting(A, B), "a tunnelling hit found while the window measures")
	tracker.end_tick()
	var rams: Array[RamTracker.ContactRam] = []
	for i: int in 6:
		rams.append_array(_tick([_sample(A, Vector3.ZERO, [B]), _sample(B, Vector3.ZERO, [A])]))
	assert_eq(rams.size(), 0, "the swept ram replaced the window")


func test_while_jolt_holds_the_pair_it_stays_met() -> void:
	tracker.contacts([] as Array[RamTracker.Sample], DT)
	assert_true(tracker.swept_meeting(A, B))
	tracker.end_tick()
	# Jolt holds them in contact for a while, below tunnelling speed: the resolver does not sweep, it keeps them met.
	for i: int in RamTracker.SWEPT_GRACE_TICKS + 4:
		tracker.contacts([_sample(A, Vector3.ZERO, [B]), _sample(B, Vector3.ZERO, [A])], DT)
		tracker.keep_touching(A, B)
		tracker.end_tick()
	# They separate while the sweep still sees their volumes meeting: the same collision.
	tracker.contacts([_sample(A, Vector3.ZERO), _sample(B, Vector3.ZERO)], DT)
	assert_false(tracker.swept_meeting(A, B))
	tracker.end_tick()


func test_keep_touching_needs_both_a_contact_and_a_meeting() -> void:
	tracker.contacts([_sample(A, Vector3.ZERO, [B]), _sample(B, Vector3.ZERO, [A])], DT)
	tracker.keep_touching(A, B)  # in contact, but their swept volumes never met
	tracker.end_tick()
	for i: int in RamTracker.SWEPT_GRACE_TICKS + 1:
		_tick([_sample(A, Vector3.ZERO), _sample(B, Vector3.ZERO)])
	tracker.contacts([] as Array[RamTracker.Sample], DT)
	assert_true(tracker.swept_meeting(A, B))
	tracker.end_tick()


func test_reset_forgets_everything() -> void:
	tracker.contacts([_sample(A, Vector3(0.0, 0.0, -15.0))], DT)
	assert_true(tracker.swept_meeting(A, B))
	tracker.end_tick()
	tracker.reset()
	tracker.contacts([] as Array[RamTracker.Sample], DT)
	assert_true(tracker.swept_meeting(A, B), "no grace survives a reset")
	tracker.end_tick()
	assert_eq(_tick([_sample(A, Vector3.ZERO, [B])]).size(), 0, "and no velocity from before it")


func test_pair_keys_ignore_the_order() -> void:
	assert_eq(RamTracker.pair_key(A, B), RamTracker.pair_key(B, A))
	assert_ne(RamTracker.pair_key(A, B), RamTracker.pair_key(A, C))
