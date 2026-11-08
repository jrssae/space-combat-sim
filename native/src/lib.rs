// Entry point of the game's native library: registers every native class with Godot.
use godot::prelude::*;

mod body_registry;
mod bolt_kernels;
mod bolt_rows;
mod brain;
mod brain_behaviours;
mod brain_maths;
mod brain_step;
mod cannons;
mod civilian;
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

// M4-T21: the low-attention tier's rows and integrator, and the core's shell around them.
mod tier;
mod tier_rows;

// M4-T22: the low-attention tier's fire, an engine-free kernel.
mod tier_fire;

// M5-T21: the defensive turrets, engine-free kernels and the core's shell around them.
mod turret_kernels;
mod turret_rows;

// M5-T28: the engine voices' ship query, an engine-free kernel and the core's shell around it.
mod voice_kernels;
mod voice_rows;
