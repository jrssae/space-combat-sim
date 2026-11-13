class_name CarrierRun
extends RefCounted
## One jump-capable ship bringing a group of fighters in through its point (M6-T23): what `CarrierJumps` keeps for it from its
## arrival to its jump back.

enum State { ARRIVING, HOLDING, LEAVING, STAYING, DONE }
const STATE_NAMES: Array[String] = ["arriving", "holding", "leaving", "staying", "done"]

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
## The fighters brought through so far, and when the run and its state began (sim seconds).
var fighters: Array[RigidBody3D] = []
var started_s: float = 0.0
var state_at_s: float = 0.0
## The velocity its fighters leave the mouth with when the caller gives none (the carrier's own), World frame.
var exit_velocity: Vector3 = Vector3.ZERO


func state_name() -> String:
	return STATE_NAMES[state]
