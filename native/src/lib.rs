// Entry point of the game's native library: registers every native class with Godot.
use godot::prelude::*;

mod body_registry;
mod contact_field;
mod flight_step;
mod hit_sweep;
mod kernels;
mod native_probe;
mod ram_phase;
mod rows;
mod sim_core;

struct ScsNative;

#[gdextension]
unsafe impl ExtensionLibrary for ScsNative {}
