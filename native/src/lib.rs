// Entry point of the game's native library: registers every native class with Godot.
use godot::prelude::*;

mod body_registry;
mod bolt_kernels;
mod bolt_rows;
mod brain;
mod brain_behaviours;
mod brain_maths;
mod cannons;
mod contact_field;
mod flight_step;
mod hit_sweep;
mod kernels;
mod native_probe;
mod pilot_kernels;
mod ram_phase;
mod row_commands;
mod rows;
mod sim_core;
mod threads;
mod v3;
mod weapon_kernels;
mod weapon_rows;

struct ScsNative;

#[gdextension]
unsafe impl ExtensionLibrary for ScsNative {}

// M4-T34: the cheaper bolt read at the core's sync points.
mod bolt_sync;

// M4-T34: the hit broad phase's grid with hashed cells, an engine-free kernel.
mod sweep_cells;
