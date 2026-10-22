class_name PilotCommand
extends RefCounted
## Everything one InputAdapter.sample() produces: what the ship gets (flight, combat) and what Main gets (ui).

var flight: FlightCommand = FlightCommand.new()
var combat: CombatCommand = CombatCommand.new()
var ui: UiCommand = UiCommand.new()
