// Entry point of the game's native library: registers every native class with Godot.
use godot::prelude::*;

mod body_registry;
mod contact_field;
mod flight_step;
mod hit_sweep;
mod native_probe;

struct ScsNative;

#[gdextension]
unsafe impl ExtensionLibrary for ScsNative {}
