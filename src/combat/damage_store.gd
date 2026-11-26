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

## The process's one store (`ScsDamageStore`).
static var store: Object = NativeLib.instantiate(NATIVE_CLASS)
## True while a copy takes a value from the store: its setters then write the copy alone.
static var quiet: bool = false


## Hull points the store still holds by kind: hulls, capitals, station sections, grid mounts, stations (a leak shows here).
static func live() -> PackedInt64Array:
	return store.live() if store != null else PackedInt64Array()
