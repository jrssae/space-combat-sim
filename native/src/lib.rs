// Entry point of the game's native library: registers every native class with Godot.
use godot::prelude::*;

mod contact_field;
mod native_probe;

struct ScsNative;

#[gdextension]
unsafe impl ExtensionLibrary for ScsNative {}
