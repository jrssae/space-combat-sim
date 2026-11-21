class_name CapitalBody
extends RigidBody3D
## What every capital body shares (M10-T07): a Newtonian rigid body with no damping, a `Targetable` of kind capital and a
## `Damageable`, a side, a jump drive, and the hand-over to the low-attention tier. The tier director, the destruction director
## and the jump points take any capital through this class: the bench's `CapitalStandin` (until T45) and the real
## `CapitalShip`.
##
## In the tier a capital is a row holding `cruise_velocity` (the tier's capital law, §17.14); a subclass keeps that velocity as
## the one it means to fly.

var faction: StringName = Factions.NEUTRAL
## The velocity it means to hold, World frame, m/s: its engines' cruise, and its tier row's.
var cruise_velocity: Vector3 = Vector3.ZERO
## For the environment's pull; null means none.
var world: WorldFrame = null
var targetable: Targetable = null
var damageable: Damageable = null
## The hull's numbers; null for the bench's boxes.
var spec: ShipSpec = null
## Where it opens its own jump point (`{position, mouth_radius_m}` in its frame), empty for a hull that gives none.
var jump_anchor: Dictionary = {}
## Its jump drive (M8-T08): it needs its class's recharge after a jump before it opens another point.
var jump_drive: JumpDrive = JumpDrive.new()
## Kept out of the low-attention tier (M6-T23): while it flies a jump vortex's funnel, as a pooled ship is (`VortexTransits`).
var tier_exempt: bool = false


func _init() -> void:
	gravity_scale = 0.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	can_sleep = false
	collision_layer = CollisionLayers.layer_of(&"capital")
	collision_mask = CollisionLayers.mask_of(&"capital")


## The hull box's half extents in its own frame (width, height, length), m.
func half_extents() -> Vector3:
	return Vector3.ZERO


## Its length along the nose, m.
func length_m() -> float:
	return 2.0 * half_extents().z


## The radius across its nose, m: what its own jump point is sized for (it comes out nose first).
func cross_radius_m() -> float:
	var half: Vector3 = half_extents()
	return Vector2(half.x, half.y).length()


## Whether it can open a jump point of its own (M6-T23, `JumpCapability`).
func can_open_jump_point() -> bool:
	return spec != null and spec.can_open_jump_point


## How far from its point's mouth it holds the point open, m.
func jump_hold_range_m() -> float:
	var anchor_m: float = (jump_anchor["position"] as Vector3).length() if not jump_anchor.is_empty() else 0.0
	return JumpCapability.hold_range_m(length_m(), spec.jump_hold_range_m if spec != null else 0.0, anchor_m)


## The mesh its far proxy draws (M4-T23).
func drawn_mesh() -> Mesh:
	return null


## Changes its side (a pooled carrier taken by another faction's raid, M6-T23).
func set_faction(p_faction: StringName) -> void:
	faction = p_faction
	targetable.faction = p_faction
	damageable.faction = p_faction


## Parks the body for the low-attention tier (M4-T21): hidden and not processing, its children with it, so it leaves Jolt,
## the scan and the weapon rows while its tier row cruises on.
func park_for_tier() -> void:
	ShiftableRegistry.set_out(self, &"_scs_tier_row", true)
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED


## Brings the body back from its tier row exactly where the row left it.
func unpark_from_tier(xform: Transform3D, velocity: Vector3, spin: Vector3) -> void:
	ShiftableRegistry.set_out(self, &"_scs_tier_row", false)
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	global_transform = xform
	linear_velocity = velocity
	angular_velocity = spin
	reset_physics_interpolation()


## Whether the body is parked for the tier now.
func is_tier_parked() -> bool:
	return has_meta(&"_scs_tier_row")


## A velocity rebase (`WorldFrame.boost`): the hull and the velocity it means to hold keep their universe velocity.
func frame_boost(dv: Vector3) -> void:
	linear_velocity -= dv
	cruise_velocity -= dv


## Takes a destroyed capital out of play (M4-T23): hidden and not processing, its children with it, for good.
func leave_play() -> void:
	ShiftableRegistry.set_out(self, &"_scs_tier_row", false)
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
