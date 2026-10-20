class_name FuelTank
extends RefCounted
## A ship's reaction-mass tank (architecture §5.1, M2-T14). Pure: the Ship feeds it `FlightOutput.mass_flow_kg_s`
## and the tick length, and asks `is_empty()` whether the flight model may fire any thruster.
##
## - Starts full. `draw` removes `flow × dt` and clamps at zero; it never goes negative.
## - `unlimited` (the `fuel_unlimited` setting, the default in the game) reads as a permanently full tank: `draw`
##   removes nothing and `mass_kg`, `fraction` and `is_empty` report full. The stored amount is kept, so switching back
##   to a finite tank resumes from wherever it was.
## - The mass is not subtracted from the ship's `mass` as it burns (the `ShipSpec` mass is the loaded mass and stays
##   constant). Doing so is a later refinement; the flow bookkeeping here would not change.
##
## A tick in which the remaining fuel is less than the flow asks for still flies that tick at full thrust (the
## shortfall is under one tick of flow); `is_empty` is true from the next tick on.

## kg; 0 means no tank at all (a finite tank of that size is empty from the start).
var capacity_kg: float = 0.0
## Never drawn down, always reads full.
var unlimited: bool = false

var _stored_kg: float = 0.0


func _init(p_capacity_kg: float = 0.0, p_unlimited: bool = false) -> void:
	capacity_kg = maxf(0.0, p_capacity_kg)
	unlimited = p_unlimited
	_stored_kg = capacity_kg


## Reaction mass on board, kg (the capacity while `unlimited`).
func mass_kg() -> float:
	return capacity_kg if unlimited else _stored_kg


## 0..1; 1 while `unlimited`; 0 for a finite tank without capacity.
func fraction() -> float:
	if unlimited:
		return 1.0
	if capacity_kg <= 0.0:
		return 0.0
	return clampf(mass_kg() / capacity_kg, 0.0, 1.0)


## True when no thruster can fire: finite and out of reaction mass. Never true while `unlimited`.
func is_empty() -> bool:
	return not unlimited and _stored_kg <= 0.0


## Burns `flow_kg_s` for `dt` seconds and returns the kg actually removed (less than asked when the tank runs dry,
## 0 while `unlimited`). Negative or non-finite flow or time removes nothing.
func draw(flow_kg_s: float, dt: float) -> float:
	if unlimited or not (flow_kg_s > 0.0 and dt > 0.0) or not is_finite(flow_kg_s * dt):
		return 0.0
	var taken: float = minf(flow_kg_s * dt, _stored_kg)
	_stored_kg -= taken
	if _stored_kg < 0.0:
		_stored_kg = 0.0
	return taken


## Adds `amount_kg` (all the way to full by default) and returns the kg added. Applies to the stored amount even
## while `unlimited`.
func refuel(amount_kg: float = INF) -> float:
	if not amount_kg > 0.0:
		return 0.0
	var before: float = _stored_kg
	_stored_kg = minf(capacity_kg, _stored_kg + amount_kg)
	return _stored_kg - before


## Sets the stored amount, clamped to 0..capacity (console and tests).
func set_kg(value: float) -> void:
	_stored_kg = clampf(value, 0.0, capacity_kg) if not is_nan(value) else _stored_kg
