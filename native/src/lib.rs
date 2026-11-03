// Entry point of the game's native library: registers every native class with Godot.
use godot::prelude::*;

mod native_probe;

struct ScsNative;

#[gdextension]
unsafe impl ExtensionLibrary for ScsNative {}
