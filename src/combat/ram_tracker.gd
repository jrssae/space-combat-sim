class_name RamTracker
extends RefCounted
## The bookkeeping behind ram detection (architecture §16 D32, M3-T04), pure. The `RamResolver` reads the bodies and runs the
## sweeps; this decides which contacts are new, measures each new contact's velocity change, and keeps one ram per pair per
## collision. Once per physics tick, in this order:
##
## 1. `contacts(samples, delta)`: every rigid body as read this tick. Returns the contact rams that land now.
## 2. For each pair the resolver sweeps: `swept_meeting(a, b)` when the sweep found their volumes meeting (true = ram now).
##    For each rigid pair it does not sweep (below tunnelling speed): `keep_touching(a, b)`.
## 3. `end_tick()`.
##
## Contact windows. When a body reports a contact with a body it did not touch on the last tick, a window opens for that pair
## (hull, other). For `CONTACT_WINDOW_TICKS` ticks, counting the first, it tracks the largest change of the hull's velocity
## from before the contact that the hull's own forces do not explain (`RamMath.contact_dv`). Jolt may report a speculative
## contact a tick before the bounce and spread the bounce over two steps, hence the window. The ram lands once, when the
## window closes, or at once when the change is already lethal. A body that leaves play loses its windows; a body seen without
## the tick before (spawned, respawned) opens none.
##
## Swept rams. A pair the sweep finds meeting is rammed when it did not meet on the last tick. The ram cancels the pair's open
## contact windows, and for `SWEPT_GRACE_TICKS` ticks after it the pair opens no contact window and takes no other swept ram:
## the sweep predicts the hit for the coming step, and Jolt reports the same collision as a contact afterwards. While Jolt holds
## a pair that met in contact and the resolver does not sweep it, `keep_touching` keeps it met, so it is not rammed again when
## the two separate.

## Ticks over which a new contact's velocity change is measured, counting the tick it is first reported.
const CONTACT_WINDOW_TICKS: int = 3
## Ticks after a swept ram during which its pair opens no contact window and takes no other swept ram.
const SWEPT_GRACE_TICKS: int = CONTACT_WINDOW_TICKS + 1


## Where a contact touches a hull: a `World`-local point and the hull's surface normal there.
class Touch extends RefCounted:
	var point: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.ZERO

	func _init(p_point: Vector3 = Vector3.ZERO, p_normal: Vector3 = Vector3.ZERO) -> void:
		point = p_point
		normal = p_normal


## One rigid body as the resolver read it this tick (before Jolt's step).
class Sample extends RefCounted:
	var id: int = 0
	var velocity: Vector3 = Vector3.ZERO
	## What the body's own forces (thrust, the environment) add to its velocity per second; applied before this tick's step.
	var accel: Vector3 = Vector3.ZERO
	## The bodies Jolt reported touching it in the last step: instance id -> where.
	var contacts: Dictionary[int, Touch] = {}
	var safe_dv_mps: float = 5.0
	var lethal_dv_mps: float = 18.0

	func _init(p_id: int = 0, p_velocity: Vector3 = Vector3.ZERO, p_accel: Vector3 = Vector3.ZERO, p_safe_dv_mps: float = 5.0,
			p_lethal_dv_mps: float = 18.0) -> void:
		id = p_id
		velocity = p_velocity
		accel = p_accel
		safe_dv_mps = p_safe_dv_mps
		lethal_dv_mps = p_lethal_dv_mps

	## Records a contact with `other_id` (the first one per body counts). Returns self.
	func touch(other_id: int, point: Vector3, normal: Vector3) -> Sample:
		if not contacts.has(other_id):
			contacts[other_id] = Touch.new(point, normal)
		return self


## A contact ram that lands this tick: the hull, the body it met, its velocity change and the share of its hull that takes.
class ContactRam extends RefCounted:
	var hull_id: int = 0
	var other_id: int = 0
	var dv: float = 0.0
	var severity: float = 0.0
	var point: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.ZERO
	## Speed of the other body relative to the hull on the tick before the contact.
	var relative_speed: float = 0.0


# One open contact window.
class _Window extends RefCounted:
	var ram: ContactRam = ContactRam.new()
	var v_before: Vector3 = Vector3.ZERO
	var own_dv: Vector3 = Vector3.ZERO
	var ticks_left: int = CONTACT_WINDOW_TICKS


var _tick: int = 0
var _previous: Dictionary[int, Sample] = {}
# Directed key "hull>other" -> its open window.
var _windows: Dictionary[String, _Window] = {}
var _in_contact: Dictionary[String, bool] = {}
var _touching: Dictionary[String, bool] = {}
var _touching_now: Dictionary[String, bool] = {}
# Pair key -> the tick of its last swept ram.
var _swept_at: Dictionary[String, int] = {}


## The key of an unordered pair of instance ids.
static func pair_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


## Phase 1 of a tick: the rigid bodies as read now. Opens windows for new contacts, measures the open ones and returns the
## rams whose windows close (or turn lethal) this tick. `delta` is the physics time step.
func contacts(samples: Array[Sample], delta: float) -> Array[ContactRam]:
	_tick += 1
	_in_contact.clear()
	_touching_now.clear()
	var current: Dictionary[int, Sample] = {}
	for sample: Sample in samples:
		current[sample.id] = sample
	for sample: Sample in samples:
		for other_id: int in sample.contacts:
			_in_contact[pair_key(sample.id, other_id)] = true
		var previous: Sample = _previous.get(sample.id)
		if previous == null:
			continue
		for other_id: int in sample.contacts:
			var key: String = _directed(sample.id, other_id)
			if previous.contacts.has(other_id) or _windows.has(key) or _swept_recently(pair_key(sample.id, other_id)):
				continue
			_windows[key] = _open(sample, other_id, previous)
	var landed: Array[ContactRam] = []
	var still_open: Dictionary[String, _Window] = {}
	for key: String in _windows:
		var window: _Window = _windows[key]
		var sample: Sample = current.get(window.ram.hull_id)
		var previous: Sample = _previous.get(window.ram.hull_id)
		if sample == null or previous == null:
			continue  # the body left play (or was away a tick): its windows go
		window.own_dv += previous.accel * delta
		window.ram.dv = maxf(window.ram.dv, RamMath.contact_dv(sample.velocity, window.v_before, window.own_dv))
		window.ticks_left -= 1
		window.ram.severity = RamMath.severity(window.ram.dv, sample.safe_dv_mps, sample.lethal_dv_mps)
		if window.ticks_left > 0 and window.ram.severity < 1.0:
			still_open[key] = window
		elif window.ram.severity > 0.0:
			landed.append(window.ram)
	_windows = still_open
	_previous = current
	return landed


## True when Jolt reported `a` and `b` touching this tick (valid after `contacts`).
func in_contact(a: int, b: int) -> bool:
	return _in_contact.has(pair_key(a, b))


## Phase 2: the sweep found the volumes of `a` and `b` meeting this tick. True when that is a new ram: they did not meet on the
## last tick and took no swept ram in the last `SWEPT_GRACE_TICKS` ticks. A ram cancels the pair's open contact windows.
func swept_meeting(a: int, b: int) -> bool:
	var key: String = pair_key(a, b)
	_touching_now[key] = true
	if _touching.has(key) or _swept_recently(key):
		return false
	_swept_at[key] = _tick
	_windows.erase(_directed(a, b))
	_windows.erase(_directed(b, a))
	return true


## Phase 2, for a rigid pair the resolver does not sweep this tick: a pair that met stays met while Jolt holds it in contact.
func keep_touching(a: int, b: int) -> void:
	var key: String = pair_key(a, b)
	if _in_contact.has(key) and _touching.has(key):
		_touching_now[key] = true


## Phase 3: the tick is over.
func end_tick() -> void:
	_touching = _touching_now
	_touching_now = {}
	for key: String in _swept_at.keys():
		if _tick - _swept_at[key] >= SWEPT_GRACE_TICKS:
			_swept_at.erase(key)


## Forgets everything (ram damage switched off): no velocity, contact, window or grace carries over.
func reset() -> void:
	_tick = 0
	_previous.clear()
	_windows.clear()
	_in_contact.clear()
	_touching.clear()
	_touching_now.clear()
	_swept_at.clear()


func _swept_recently(key: String) -> bool:
	return _swept_at.has(key) and _tick - _swept_at[key] <= SWEPT_GRACE_TICKS


func _open(sample: Sample, other_id: int, previous: Sample) -> _Window:
	var window := _Window.new()
	var touch: Touch = sample.contacts[other_id]
	var other_previous: Sample = _previous.get(other_id)
	window.v_before = previous.velocity
	window.ram.hull_id = sample.id
	window.ram.other_id = other_id
	window.ram.point = touch.point
	window.ram.normal = touch.normal
	window.ram.relative_speed = (previous.velocity - (other_previous.velocity if other_previous != null else Vector3.ZERO)).length()
	return window


static func _directed(hull_id: int, other_id: int) -> String:
	return "%d>%d" % [hull_id, other_id]
