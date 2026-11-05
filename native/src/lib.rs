// Entry point of the game's native library: registers every native class with Godot.
use godot::prelude::*;

mod body_registry;
mod contact_field;
mod flight_step;
mod hit_sweep;
mod kernels;
mod native_probe;
mod pilot_kernels;
mod ram_phase;
mod rows;
mod sim_core;
mod weapon_kernels;
mod weapon_rows;

struct ScsNative;

#[gdextension]
unsafe impl ExtensionLibrary for ScsNative {}
