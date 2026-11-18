class_name CarrierRun
extends RefCounted
## One jump-capable ship bringing a group of fighters in through its point (M6-T23): what `CarrierJumps` keeps for it from its
## arrival to its jump back.

## A carrier with cradles (M12-T19) also stands off (`STANDOFF`: its fighters out, it hangs back) and flees (`FLEEING`, M8-T08:
## it waits for its fighters or runs, until it can jump or reaches a gate).
enum State { ARRIVING, HOLDING, LEAVING, STAYING, DONE, STANDOFF, FLEEING }
const STATE_NAMES: Array[String] = ["arriving", "holding", "leaving", "staying", "done", "standoff", "fleeing"]
## How it left: through its own point, or through a jumpgate.
const VIA_POINT: StringName = &"point"
const VIA_GATE: StringName = &"gate"

var state: State = State.ARRIVING
## The carrier (a capital stand-in) and the pool its points come from.
var carrier: CapitalStandin = null
var pool: JumpPointPool = null
## Its arrival point, which the fighters come out of, and the point it leaves through (null until it leaves).
var arrival: JumpVortex = null
var departure: JumpVortex = null
var faction: StringName = &""
## What it does once its fighters are out: `CarrierJumps.THEN_DEPART` or `THEN_STAY`.
var then: StringName = &"depart"
## Where its group's first fighter was to come out, World-local at the start (later fighters within reach join it).
var first_place: Vector3 = Vector3.ZERO
## The fighters brought through and still its own (one left behind is dropped), how many it brought, and when the run and its
## state began (sim seconds).
var fighters: Array[RigidBody3D] = []
var brought: int = 0
var started_s: float = 0.0
var state_at_s: float = 0.0
## The velocity its fighters leave the mouth with when the caller gives none (the carrier's own), World frame.
var exit_velocity: Vector3 = Vector3.ZERO


## The raid's options (`CarrierTactics.options`): how its fighters arrive, its stand-off, when they go home, when it flees.
var options: Dictionary = CarrierTactics.options({})
## When every fighter was called home (sim seconds; negative: not yet), why it flees (`CarrierTactics.FLEE_*`, empty while it
## stays), what it does about it now (`CarrierTactics.MOVE_*`), the gate it runs for, and how it left.
var recalled_at_s: float = -1.0
var flee_reason: StringName = CarrierTactics.STAYS
var move: StringName = &""
var gate: Jumpgate = null
var left_via: StringName = &""
## The raid was ended by its script or the console (`CarrierJumps.end_raid`).
var raid_ended: bool = false
## When the carrier last looked for the nearest enemy and decided (sim seconds).
var decided_s: float = -INF
## Fighters aboard when it left, and left behind, so far.
var recovered: int = 0
var left_behind: int = 0


func state_name() -> String:
	return STATE_NAMES[state]
