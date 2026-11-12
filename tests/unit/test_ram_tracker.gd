extends GutTest
## The ram tracker (M3-T04, architecture §16 D32; native since M5-T33, §18.23): which contacts are new, the window that
## measures a new contact's velocity change, one ram per pair per collision, and the hand-over between swept rams and Jolt's
## contacts. No Jolt: each tick is a list of bodies, fed to `ScsRamTracker.feed` as columns. `RamTracker` (GDScript, in
## `tests/fixtures/`) is the reference the native tracker repeats: the last test runs both side by side.

const DT: float = 1.0 / 60.0
const A: int = 101
const B: int = 202
const C: int = 303
const SAFE: float = 5.0
const LETHAL: float = 18.0
const TRACKER_CLASS: StringName = &"ScsRamTracker"

var tracker: Object


func before_each() -> void:
	tracker = NativeLib.instantiate(TRACKER_CLASS)


# One rigid body as read this tick: its id, velocity, the bodies it touches and what its own forces add per second.
func _sample(id: int, velocity: Vector3, touching: Array[int] = [], accel: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"id": id, "velocity": velocity, "touching": touching, "accel": accel}


func _limits(_id: int) -> PackedFloat64Array:
	return PackedFloat64Array([SAFE, LETHAL])


## The contact phase for `samples`, in the columns the native tracker takes. Returns the contact rams that landed.
func _contacts(samples: Array) -> Array[RamTracker.ContactRam]:
	return _feed(tracker, samples, Vector3(0.0, 0.0, -5.0))


## `samples` fed to the native `to` (every contact at `point`), each asked hull answered with the test's limits.
func _feed(to: Object, samples: Array, point: Vector3) -> Array[RamTracker.ContactRam]:
	var ids := PackedInt64Array()
	var velocities := PackedVector3Array()
	var accels := PackedVector3Array()
	var touched := PackedInt32Array()
	var starts := PackedInt32Array()
	var others := PackedInt64Array()
	for sample: Dictionary in samples:
		var touching: Array[int] = sample["touching"]
		if not touching.is_empty():
			touched.append(ids.size())
			starts.append(others.size())
			for other_id: int in touching:
				others.append(other_id)
		ids.append(sample["id"])
		velocities.append(sample["velocity"])
		accels.append(sample["accel"])
	starts.append(others.size())
	var points := PackedVector3Array()
	points.resize(others.size())
	points.fill(point)
	var normals := PackedVector3Array()
	normals.resize(others.size())
	normals.fill(Vector3(0.0, 0.0, -1.0))
	var asked: PackedInt64Array = to.feed(ids, velocities, accels, touched, starts, others, points, normals, DT)
	var limits := PackedFloat64Array()
	for id: int in asked:
		limits.append_array(_limits(id))
	var landed: Array = to.land(limits)
	var rams: Array[RamTracker.ContactRam] = []
	for r: int in (landed[0] as PackedInt64Array).size():
		var ram := RamTracker.ContactRam.new()
		ram.hull_id = landed[0][r]
		ram.other_id = landed[1][r]
		ram.dv = landed[2][r]
		ram.severity = landed[3][r]
		ram.point = landed[4][r]
		ram.normal = landed[5][r]
		ram.relative_speed = landed[6][r]
		rams.append(ram)
	return rams


## The same contact phase on the GDScript reference.
func _feed_reference(to: RamTracker, samples: Array, point: Vector3) -> Array[RamTracker.ContactRam]:
	var ids := PackedInt64Array()
	var velocities := PackedVector3Array()
	var accels := PackedVector3Array()
	var touches: Dictionary[int, Dictionary] = {}
	for sample: Dictionary in samples:
		ids.append(sample["id"])
		velocities.append(sample["velocity"])
		accels.append(sample["accel"])
		var touching: Array[int] = sample["touching"]
		if touching.is_empty():
			continue
		var contacts: Dictionary = {}
		for other_id: int in touching:
			if not contacts.has(other_id):
				contacts[other_id] = RamTracker.Touch.new(point, Vector3(0.0, 0.0, -1.0))
		touches[int(sample["id"])] = contacts
	return to.contacts_columns(ids, velocities, accels, touches, _limits, DT)


## One tick: the contact phase, then the end of the tick. Returns the contact rams that landed.
func _tick(samples: Array) -> Array[RamTracker.ContactRam]:
	var rams: Array[RamTracker.ContactRam] = _contacts(samples)
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
	assert_eq(_tick([]).size(), 0, "parked mid-window")
	assert_eq(_tick([_sample(A, Vector3.ZERO, [B])]).size(), 0, "back with no tick before: nothing")
	assert_eq(_tick([_sample(A, Vector3.ZERO, [B])]).size(), 0)


# --- swept rams --------------------------------------------------------------------------------------------------


func test_a_swept_meeting_is_one_ram_per_pair() -> void:
	_contacts([])
	assert_true(tracker.swept_meeting(A, B), "a new meeting is a ram")
	tracker.end_tick()
	_contacts([])
	assert_false(tracker.swept_meeting(B, A), "still meeting a tick later: the same ram, either order")
	tracker.end_tick()
	for i: int in RamTracker.SWEPT_GRACE_TICKS - 2:
		_tick([])
	_contacts([])
	assert_false(tracker.swept_meeting(A, B), "meeting again within the grace ticks is still the same collision")
	tracker.end_tick()
	for i: int in RamTracker.SWEPT_GRACE_TICKS + 1:
		_tick([])
	_contacts([])
	assert_true(tracker.swept_meeting(A, B), "a later meeting is a new ram")
	tracker.end_tick()


func test_jolt_resolving_a_swept_ram_opens_no_contact_window() -> void:
	# The sweep predicts the hit for the coming step; Jolt resolves it in that step and reports the contact next tick.
	_contacts([_sample(A, Vector3(0.0, 0.0, -13.0)), _sample(B, Vector3(0.0, 0.0, 13.0))])
	assert_true(tracker.swept_meeting(A, B))
	tracker.end_tick()
	var rams: Array[RamTracker.ContactRam] = []
	for i: int in RamTracker.SWEPT_GRACE_TICKS + 6:
		rams.append_array(_tick([_sample(A, Vector3.ZERO, [B]), _sample(B, Vector3.ZERO, [A])]))
	assert_eq(rams.size(), 0, "the bounce of a swept ram is not rammed again")


func test_a_contact_that_begins_late_in_the_grace_ticks_opens_no_window() -> void:
	_contacts([_sample(A, Vector3(0.0, 0.0, -13.0)), _sample(B, Vector3(0.0, 0.0, 13.0))])
	assert_true(tracker.swept_meeting(A, B))
	tracker.end_tick()
	for i: int in RamTracker.SWEPT_GRACE_TICKS - 1:
		_tick([_sample(A, Vector3(0.0, 0.0, -13.0)), _sample(B, Vector3(0.0, 0.0, 13.0))])
	var rams: Array[RamTracker.ContactRam] = []
	for i: int in 6:
		rams.append_array(_tick([_sample(A, Vector3.ZERO, [B]), _sample(B, Vector3.ZERO, [A])]))
	assert_eq(rams.size(), 0, "the last grace tick still counts")


func test_a_contact_after_the_grace_ticks_is_a_new_collision() -> void:
	_contacts([])
	assert_true(tracker.swept_meeting(A, B))
	tracker.end_tick()
	for i: int in RamTracker.SWEPT_GRACE_TICKS:
		_tick([_sample(A, Vector3(0.0, 0.0, -15.0)), _sample(B, Vector3(0.0, 0.0, 15.0))])
	assert_eq(_head_on(4).size(), 2)


func test_a_swept_ram_takes_over_the_pairs_open_contact_window() -> void:
	_tick([_sample(A, Vector3(0.0, 0.0, -15.0)), _sample(B, Vector3(0.0, 0.0, 15.0))])
	assert_eq(_contacts([_sample(A, Vector3(0.0, 0.0, -5.0), [B]), _sample(B, Vector3(0.0, 0.0, 5.0), [A])]).size(), 0)
	assert_true(tracker.in_contact(A, B))
	assert_true(tracker.swept_meeting(A, B), "a tunnelling hit found while the window measures")
	tracker.end_tick()
	var rams: Array[RamTracker.ContactRam] = []
	for i: int in 6:
		rams.append_array(_tick([_sample(A, Vector3.ZERO, [B]), _sample(B, Vector3.ZERO, [A])]))
	assert_eq(rams.size(), 0, "the swept ram replaced the window")


func test_while_jolt_holds_the_pair_it_stays_met() -> void:
	_contacts([])
	assert_true(tracker.swept_meeting(A, B))
	tracker.end_tick()
	# Jolt holds them in contact for a while, below tunnelling speed: the resolver does not sweep, it keeps them met.
	for i: int in RamTracker.SWEPT_GRACE_TICKS + 4:
		_contacts([_sample(A, Vector3.ZERO, [B]), _sample(B, Vector3.ZERO, [A])])
		tracker.keep_touching(A, B)
		tracker.end_tick()
	# They separate while the sweep still sees their volumes meeting: the same collision.
	_contacts([_sample(A, Vector3.ZERO), _sample(B, Vector3.ZERO)])
	assert_false(tracker.swept_meeting(A, B))
	tracker.end_tick()


func test_keep_touching_needs_both_a_contact_and_a_meeting() -> void:
	_contacts([_sample(A, Vector3.ZERO, [B]), _sample(B, Vector3.ZERO, [A])])
	tracker.keep_touching(A, B)  # in contact, but their swept volumes never met
	tracker.end_tick()
	for i: int in RamTracker.SWEPT_GRACE_TICKS + 1:
		_tick([_sample(A, Vector3.ZERO), _sample(B, Vector3.ZERO)])
	_contacts([])
	assert_true(tracker.swept_meeting(A, B))
	tracker.end_tick()


func test_reset_forgets_everything() -> void:
	_contacts([_sample(A, Vector3(0.0, 0.0, -15.0))])
	assert_true(tracker.swept_meeting(A, B))
	tracker.end_tick()
	tracker.reset()
	_contacts([])
	assert_true(tracker.swept_meeting(A, B), "no grace survives a reset")
	tracker.end_tick()
	assert_eq(_tick([_sample(A, Vector3.ZERO, [B])]).size(), 0, "and no velocity from before it")


func test_reset_forgets_the_last_ticks_velocities() -> void:
	# From test_ram_tracker_columns (M6-T18): without the reset this head-on's window would close with two rams.
	_tick([_sample(A, Vector3(0.0, 0.0, -15.0)), _sample(B, Vector3(0.0, 0.0, 15.0))])
	tracker.reset()
	var rams: Array[RamTracker.ContactRam] = []
	for i: int in 4:
		rams.append_array(_tick([_sample(A, Vector3.ZERO, [B]), _sample(B, Vector3.ZERO, [A])]))
	assert_eq(rams.size(), 0, "after a reset no body has a tick before, so the contact opens no window")


func test_pair_keys_ignore_the_order() -> void:
	assert_eq(RamTracker.pair_key(A, B), RamTracker.pair_key(B, A))
	assert_ne(RamTracker.pair_key(A, B), RamTracker.pair_key(A, C))


# --- the native tracker against its GDScript reference (M5-T33) ---------------------------------------------------


func test_the_native_tracker_repeats_the_reference_tick_for_tick() -> void:
	# Six bodies that come and go, touch at random (a pair now and then reported twice), thrust, and are swept or kept
	# touching at random, with a rebase now and then: every ram and every answer must match, bit for bit.
	var reference := RamTracker.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3305
	var bodies: Array[int] = [11, 22, 33, 44, 55, 66]
	var velocities: Dictionary[int, Vector3] = {}
	for id: int in bodies:
		velocities[id] = Vector3.ZERO
	var rams_seen: int = 0
	var swept_seen: int = 0
	for tick: int in 1500:
		var samples: Array = []
		for id: int in bodies:
			if rng.randf() < 0.08:
				continue  # away this tick
			if rng.randf() < 0.3:
				velocities[id] = Vector3(rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0))
			var touching: Array[int] = []
			for other_id: int in bodies + [777]:
				if other_id != id and rng.randf() < 0.18:
					touching.append(other_id)
					if rng.randf() < 0.2:
						touching.append(other_id)
			samples.append(_sample(id, velocities[id], touching, Vector3(rng.randf_range(-40.0, 40.0), 0.0, rng.randf_range(-40.0, 40.0))))
		var point := Vector3(rng.randf_range(-50.0, 50.0), 0.0, float(tick))
		var want: Array[RamTracker.ContactRam] = _feed_reference(reference, samples, point)
		var got: Array[RamTracker.ContactRam] = _feed(tracker, samples, point)
		rams_seen += want.size()
		if not _same_rams(got, want):
			fail_test("tick %d: the rams differ: %s, reference %s" % [tick, _described(got), _described(want)])
			return
		for k: int in rng.randi_range(0, 3):
			var a: int = bodies[rng.randi_range(0, bodies.size() - 1)]
			var b: int = bodies[rng.randi_range(0, bodies.size() - 1)]
			if a == b:
				continue
			if reference.in_contact(a, b) != tracker.in_contact(a, b):
				fail_test("tick %d: in_contact(%d, %d) differs" % [tick, a, b])
				return
			if rng.randf() < 0.5:
				var met: bool = reference.swept_meeting(a, b)
				swept_seen += 1 if met else 0
				if tracker.swept_meeting(a, b) != met:
					fail_test("tick %d: swept_meeting(%d, %d) differs (reference %s)" % [tick, a, b, met])
					return
			else:
				reference.keep_touching(a, b)
				tracker.keep_touching(a, b)
		if rng.randf() < 0.05:
			var offset := Vector3(rng.randf_range(-900.0, 900.0), 0.0, rng.randf_range(-900.0, 900.0))
			reference.shift(offset)
			tracker.shift(offset)
		if tick == 900:
			reference.reset()
			tracker.reset()
		reference.end_tick()
		tracker.end_tick()
	assert_gt(rams_seen, 100, "the run landed contact rams (%d)" % rams_seen)
	assert_gt(swept_seen, 100, "and swept ones (%d)" % swept_seen)
	pass_test("1500 ticks: %d contact rams and %d swept rams, the same on both" % [rams_seen, swept_seen])


func test_a_feed_whose_columns_do_not_line_up_is_refused() -> void:
	var asked: PackedInt64Array = tracker.feed(PackedInt64Array([A]), PackedVector3Array(), PackedVector3Array([Vector3.ZERO]),
			PackedInt32Array(), PackedInt32Array([0]), PackedInt64Array(), PackedVector3Array(), PackedVector3Array(), DT)
	assert_engine_error("do not line up")
	assert_eq(asked.size(), 0)
	assert_eq(_head_on(4).size(), 2, "and the tracker still works")


func _same_rams(got: Array[RamTracker.ContactRam], want: Array[RamTracker.ContactRam]) -> bool:
	if got.size() != want.size():
		return false
	for r: int in want.size():
		var g: RamTracker.ContactRam = got[r]
		var w: RamTracker.ContactRam = want[r]
		if g.hull_id != w.hull_id or g.other_id != w.other_id or g.dv != w.dv or g.severity != w.severity or g.point != w.point \
				or g.normal != w.normal or g.relative_speed != w.relative_speed:
			return false
	return true


func _described(rams: Array[RamTracker.ContactRam]) -> String:
	var out := PackedStringArray()
	for ram: RamTracker.ContactRam in rams:
		out.append("%d>%d dv %s sev %s at %s speed %s" % [ram.hull_id, ram.other_id, ram.dv, ram.severity, ram.point,
				ram.relative_speed])
	return "[%s]" % ", ".join(out)
