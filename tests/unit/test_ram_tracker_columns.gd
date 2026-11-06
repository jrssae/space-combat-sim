extends GutTest
## RamTracker's contact phase in columns (M4-T34): `contacts_columns` takes every rigid body's id, velocity and accel as
## columns and a `Sample`-like contact list only for the bodies Jolt reported touching something, and must land the same
## rams, field for field and in the same order, as `contacts` over the samples those make. Seeded random ticks with bodies
## coming and going, contacts opening and closing, swept meetings, Jolt holding pairs, rebases and lethal bounces drive two
## trackers side by side.

const DT: float = 1.0 / 60.0
const BODIES: int = 12
const TICKS: int = 400


class Limits extends RefCounted:
	var by_id: Dictionary = {}

	func of(id: int) -> PackedFloat64Array:
		return by_id[id]


func _ram_line(ram: RamTracker.ContactRam) -> String:
	return var_to_str([ram.hull_id, ram.other_id, ram.dv, ram.severity, ram.point, ram.normal, ram.relative_speed])


func test_the_columns_land_the_same_rams_as_the_samples() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3434
	var by_samples := RamTracker.new()
	var by_columns := RamTracker.new()
	var limits := Limits.new()
	var velocities: Dictionary = {}
	var present: Dictionary = {}
	var touching: Dictionary = {}  # pair key -> true while Jolt holds the pair
	for b: int in BODIES:
		var id: int = 1000 + b * 7
		velocities[id] = Vector3(rng.randf_range(-30.0, 30.0), rng.randf_range(-30.0, 30.0), rng.randf_range(-30.0, 30.0))
		present[id] = true
		limits.by_id[id] = PackedFloat64Array([rng.randf_range(2.0, 8.0), rng.randf_range(12.0, 40.0)])
	var landed: int = 0
	var swept: int = 0
	for tick: int in TICKS:
		# Bodies leave and come back; velocities jump (bounces, some lethal); pairs start and stop touching.
		for id: int in velocities:
			if rng.randf() < 0.03:
				present[id] = not present[id]
			var jump: float = 60.0 if rng.randf() < 0.05 else 4.0
			velocities[id] += Vector3(rng.randf_range(-jump, jump), rng.randf_range(-jump, jump), rng.randf_range(-jump, jump))
		var ids_now: Array = velocities.keys()
		if rng.randf() < 0.3:
			var a: int = ids_now[rng.randi_range(0, BODIES - 1)]
			var b: int = ids_now[rng.randi_range(0, BODIES - 1)]
			if a != b:
				var key: String = RamTracker.pair_key(a, b)
				if touching.has(key):
					touching.erase(key)
				else:
					touching[key] = [a, b]
		var samples: Array[RamTracker.Sample] = []
		var ids := PackedInt64Array()
		var vels := PackedVector3Array()
		var accels := PackedVector3Array()
		var touches: Dictionary[int, Dictionary] = {}
		for id: int in ids_now:
			if not present[id]:
				continue
			var accel := Vector3(rng.randf_range(-20.0, 20.0), 0.0, rng.randf_range(-20.0, 20.0))
			var sample := RamTracker.Sample.new(id, velocities[id], accel, limits.by_id[id][0], limits.by_id[id][1])
			var contacts: Dictionary[int, RamTracker.Touch] = {}
			for key: String in touching:
				var pair: Array = touching[key]
				if pair[0] != id and pair[1] != id:
					continue
				var other: int = pair[1] if pair[0] == id else pair[0]
				var point := Vector3(rng.randf_range(-100.0, 100.0), rng.randf_range(-100.0, 100.0), rng.randf_range(-100.0, 100.0))
				var normal := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), 1.0).normalized()
				sample.touch(other, point, normal)
				# A second report of the same pair: only the first counts.
				sample.touch(other, point + Vector3.ONE, -normal)
				contacts[other] = RamTracker.Touch.new(point, normal)
			samples.append(sample)
			ids.append(id)
			vels.append(velocities[id])
			accels.append(accel)
			if not contacts.is_empty():
				touches[id] = contacts
		var a_rams: Array[RamTracker.ContactRam] = by_samples.contacts(samples, DT)
		var b_rams: Array[RamTracker.ContactRam] = by_columns.contacts_columns(ids, vels, accels, touches, limits.of, DT)
		var a_lines := PackedStringArray()
		var b_lines := PackedStringArray()
		for ram: RamTracker.ContactRam in a_rams:
			a_lines.append(_ram_line(ram))
		for ram: RamTracker.ContactRam in b_rams:
			b_lines.append(_ram_line(ram))
		if a_lines != b_lines:
			fail_test("tick %d: the rams differ: %s against %s" % [tick, a_lines, b_lines])
			return
		landed += a_lines.size()
		# Phase 2 alike on both: some swept meetings, Jolt's pairs kept touching.
		for key: String in touching:
			var pair: Array = touching[key]
			assert_eq(by_columns.in_contact(pair[0], pair[1]), by_samples.in_contact(pair[0], pair[1]), "tick %d: in contact" % tick)
			if rng.randf() < 0.1:
				var met_a: bool = by_samples.swept_meeting(pair[0], pair[1])
				var met_b: bool = by_columns.swept_meeting(pair[0], pair[1])
				assert_eq(met_b, met_a, "tick %d: the same swept answer" % tick)
				swept += 1 if met_a else 0
			else:
				by_samples.keep_touching(pair[0], pair[1])
				by_columns.keep_touching(pair[0], pair[1])
		if rng.randf() < 0.05:
			var offset := Vector3(rng.randf_range(-500.0, 500.0), 0.0, rng.randf_range(-500.0, 500.0))
			by_samples.shift(offset)
			by_columns.shift(offset)
		by_samples.end_tick()
		by_columns.end_tick()
	gut.p("%d contact rams and %d swept rams over %d ticks" % [landed, swept, TICKS])
	assert_gt(landed, 10, "the run landed contact rams to compare")
	assert_gt(swept, 3, "and swept rams took windows over")


func test_reset_forgets_the_columns_too() -> void:
	var tracker := RamTracker.new()
	var ids := PackedInt64Array([1, 2])
	var vels := PackedVector3Array([Vector3(0.0, 0.0, -15.0), Vector3(0.0, 0.0, 15.0)])
	var accels := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var limits := Limits.new()
	limits.by_id = {1: PackedFloat64Array([5.0, 18.0]), 2: PackedFloat64Array([5.0, 18.0])}
	var empty: Dictionary[int, Dictionary] = {}
	tracker.contacts_columns(ids, vels, accels, empty, limits.of, DT)
	tracker.end_tick()
	tracker.reset()
	var stopped := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var touches: Dictionary[int, Dictionary] = {
		1: {2: RamTracker.Touch.new(Vector3.ZERO, Vector3.BACK)},
		2: {1: RamTracker.Touch.new(Vector3.ZERO, Vector3.FORWARD)},
	}
	var rams: Array[RamTracker.ContactRam] = []
	for i: int in 4:
		rams.append_array(tracker.contacts_columns(ids, stopped, accels, touches, limits.of, DT))
		tracker.end_tick()
	assert_eq(rams.size(), 0, "after a reset no body has a tick before, so the contact opens no window")
