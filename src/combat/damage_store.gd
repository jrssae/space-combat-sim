class_name DamageStore
extends RefCounted
## The native damage store's GDScript side (M10-T75, Q94, architecture §15.4): one owner for every hull's, section's and
## part's points, applying the rules natively (`damage_store.rs`). `HullHealth`, `CapitalDamage`, `StationSections`,
## `GridMountHealth` and `StationDamage` keep read-only copies of their ledgers here: each call that changes points answers
## with its result and a write log, which they replay onto their copies, raising their signals where the log says, so a
## listener sees the state as the rules left it at that point. A direct write to a copy's field (a test, the console) goes
## through its setter to the store.

const NATIVE_CLASS: StringName = &"ScsDamageStore"
## A log entry is four numbers: its code, then up to three values.
const WIDTH: int = 4

## The log's codes (`ScsDamageStore.codes()`; `test_damage_store` holds the two sides together). A capital's:
const SEC_HP: int = 1
const SEC_STATE: int = 2
const SECTION_CHANGED: int = 3
const PART_HP: int = 4
const PART_LOST: int = 5
const DRIVE_CHANGED: int = 6
const HULL_HP: int = 7
const BECAME_DISABLED: int = 8
const BLEW: int = 9
const PART_ALIVE: int = 10
const FLAG_DISABLED: int = 11
const FLAG_DESTROYED: int = 12
const BLOWN: int = 13
## A station's:
const ST_SEC_HEALTH: int = 21
const ST_SEC_LOST: int = 22
const ST_MOUNT_HEALTH: int = 23
const ST_MOUNT_OUT: int = 24
const ST_HULL_HP: int = 25
const ST_DISABLED: int = 26
const ST_DESTROYED: int = 27
## A capital's part lists, as the store numbers them.
const PART_MOUNT: int = 0
const PART_ENGINE: int = 1
const PART_BAY: int = 2
const PART_SECTION: int = 3

## What a batch's entry is about (`damage_store::landing`): a hull, a capital's ledger, a station's; entries are six numbers.
const ON_HULL: int = 0
const ON_CAPITAL: int = 1
const ON_STATION: int = 2
const OUT_WIDTH: int = 6

## The process's one store (`ScsDamageStore`).
static var store: Object = NativeLib.instantiate(NATIVE_CLASS)
## True while a copy takes a value from the store: its setters then write the copy alone.
static var quiet: bool = false

# The copies by their ledger's handle and kind (weakly: a copy freed is forgotten), so a batch's writes reach them.
static var _copies: Array[Dictionary] = [{}, {}, {}]


## Copy `copy` holds ledger `ledger` of kind `on` (`ON_HULL`, `ON_CAPITAL`, `ON_STATION`).
static func adopt(on: int, ledger: int, copy: Object) -> void:
	if ledger >= 0:
		_copies[on][ledger] = weakref(copy)


static func forget(on: int, ledger: int) -> void:
	_copies[on].erase(ledger)


## A batch's entries (`OUT_WIDTH` numbers each) onto the copies in order, each copy raising its signals where an entry is an
## event (`CapitalBeams`).
static func apply(entries: PackedFloat64Array) -> void:
	var i: int = 0
	while i + OUT_WIDTH <= entries.size():
		var on: int = int(entries[i])
		var ref: WeakRef = _copies[on].get(int(entries[i + 1]))
		var copy: Object = ref.get_ref() if ref != null else null
		if copy != null:
			if on == ON_HULL:
				(copy as HullHealth).take(entries[i + 3], entries[i + 4] != 0.0, entries[i + 5] != 0.0)
			else:
				copy.call(&"replay", PackedFloat64Array([0.0, entries[i + 2], entries[i + 3], entries[i + 4], entries[i + 5]]))
		i += OUT_WIDTH


## A batch's coalesced writes (`OUT_WIDTH` numbers each, grouped by ledger) onto the copies: no event among them, so each
## ledger's run goes to its copy in one call.
static func take_writes(entries: PackedFloat64Array) -> void:
	var i: int = 0
	var n: int = entries.size()
	while i + OUT_WIDTH <= n:
		var on: int = int(entries[i])
		var ledger: int = int(entries[i + 1])
		var j: int = i + OUT_WIDTH
		while j + OUT_WIDTH <= n and int(entries[j]) == on and int(entries[j + 1]) == ledger:
			j += OUT_WIDTH
		var ref: WeakRef = _copies[on].get(ledger)
		var copy: Object = ref.get_ref() if ref != null else null
		if copy is HullHealth:
			(copy as HullHealth).take(entries[j - 3], entries[j - 2] != 0.0, entries[j - 1] != 0.0)
		elif copy is CapitalDamage:
			(copy as CapitalDamage).take_writes(entries, i, j)
		elif copy is StationDamage:
			(copy as StationDamage).take_writes(entries, i, j)
		i = j


## Hull points the store still holds by kind: hulls, capitals, station sections, grid mounts, stations (a leak shows here).
static func live() -> PackedInt64Array:
	return store.live() if store != null else PackedInt64Array()
